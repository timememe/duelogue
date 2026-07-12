extends RefCounted

## DUELOGUE — КАРТОЧНОЕ ЯДРО ПРАВИЛ v0.3 (спека: context/zal_core_v0.3.md).
## Чистая механика спора-как-битвы-аргументов: доска, ход, клинч-механика, счёт. БЕЗ UI,
## БЕЗ колоды (фабрика — core/cards/deck.gd) и БЕЗ ИИ-эвристик (политика — core/ai/ai.gd).
## Авто-разрешение клинча и симуляция живут в ai.gd; здесь только мехобработка одного удара
## (_resolve_single_razbor) и применение исхода воли (clinch_finalize) — их зовут драйверы
## (интерактивная сцена / ai-сим), сами ведя волю «разбор↔тезис».
##
## Доска: у каждой стороны линия установок (рамок). У рамки сверху лежат тезисы.
## Активна последняя установка. Закрытая (замороженная новой) не принимает тезисы.
## Установка с 0 тезисов удаляется. Счёт = число стоящих установок ("Ширина").

const Cards := preload("res://duelogue/core/cards/card_types.gd")
const Deck := preload("res://duelogue/core/cards/deck.gd")

const TYPE_TEZIS := Cards.TYPE_TEZIS
const TYPE_RAZBOR := Cards.TYPE_RAZBOR
const TYPE_USTANOVKA := Cards.TYPE_USTANOVKA
const SIDE_YOU := Cards.SIDE_YOU
const SIDE_OPP := Cards.SIDE_OPP
const ZAL_MAX := Cards.ZAL_MAX

const DEFAULT_HAND := 5

var sides := {}
var current := SIDE_YOU
var game_over := false
var winner := ""           ## SIDE_YOU | SIDE_OPP | "" (ничья)
var end_reason := ""       ## "knockout" | "decision" | "draw"
var turn_count := 0
var hand_size := DEFAULT_HAND
## Лекарство 1 (card advantage): Кража — отдельная карта-атака. Забирает снятый тезис в
## свою активную установку (а не сбрасывает). steal_cards — сколько Краж в колоде из общего
## числа карт атаки n_r (остальные — обычные Разборы). Игрок видит и выбирает карту сам.
var steal_cards := 0
## Лекарство 3 (глубина): сила рамки = тезисы + краденые (краденые считаются вдвое).
## При силе >= fortify_threshold рамка УКРЕПЛЕНА — кража с неё отскакивает (но обычное
## снятие тезиса работает). 0 — выключено. (По симуляции — кормит aggro, держим выкл.)
var fortify_threshold := 0
## Лекарство 2 (клинч / yomi): при атаке на рамку защитник может отвечать тезисом (гасит
## разбор и +1 к рамке), атакующий — добивать разбором. Волю ведёт драйвер (сцена/ai).
## clinch_freeze — заморозка добора на время воли (бой из руки, аггро может выдохнуться).
var clinch_enabled := false
var clinch_freeze := true
## Захват рамки (teardown-рычаг против храповика): Кража, снёсшая ПОСЛЕДНИЙ тезис рамки,
## переносит рамку к атакующему (−1 оппоненту, +1 себе), а не просто сносит её.
## 0 — выкл; 1 — приходит ЗАКРЫТЫМ трофеем; 2 — приходит АКТИВНОЙ (закрывает прежнюю активную).
var capture_mode := 0
## Зал-гейт 2A (асимметрия в пользу отстающего): чем сильнее зал кренится ПРОТИВ стороны,
## тем толще рамки, которые её Кража забирает ЦЕЛИКОМ. Базовый порог захвата 1 (рамка с
## 1 тезисом — текущее поведение трофея); при крене >= gate_x порог 2; >= gate_y — порог 3.
## gate_x = 0 — гейт выключен. Порог обязан рендериться на рамках (маркер «шатается»).
var gate_x := 0
var gate_y := 0
## Второе дыхание (топливо финала): когда у стороны пусты И рука, И добор, она вытягивает
## 1 СЛУЧАЙНУЮ карту из СВОЕГО сброса (стопка публична — шансы читаемы). 0 — выкл;
## N > 0 — не больше N вытяжек за партию; -1 — без лимита (пока сброс не пуст).
## Вытянутая карта помечается recycled: после использования ИЗГОНЯЕТСЯ, а не сбрасывается
## снова — пул строго убывает, бесконечной рогалик-концовки не бывает.
var second_wind := 0
## Добыча захвата: 0 — голый трофей (рамка переходит с 1 тезисом, лишнее — в сброс);
## 1 — «переманил вместе с аргументами»: рамка переходит СО ВСЕМИ стоящими тезисами
## (забрал действующую рамку — забрал её силу в глазах зала).
var capture_loot := 0
## Счётчики захватов за партию (диагностика сима/плейтеста).
var captures := 0
var capture_theses := 0
## Зал-нокаут (TKO, «унёс зал»): если крен зала В ТВОЮ пользу >= zal_ko доживает до начала
## твоего хода zal_hold раз ПОДРЯД — победа (end_reason "crowd"). «Счёт судьи»: hold=1 —
## отстающему один ход на спасение; hold=3 — три круга держать зал у края (окно поимки шире,
## гейт на таком крене открыт на максимум). 0 — выкл. crowd_streak — текущий счёт (для UI).
var zal_ko := 0
var zal_hold := 1
var crowd_streak := {}
## Смещение стрелки зала (+ в пользу you): стартовый крен run-слоя (§3.1 zal_run) и цена
## грязных именных приёмов (Ad hominem, §4). 0 = ваниль; двигается снаружи/твистами.
var zal_bias := 0
## Розыгрыши именных приёмов за партию по сторонам (диагностика сима/плейтеста).
var named_played := {}


func reset(
	first_side: String, n_u: int, n_t: int, n_r: int,
	p_hand_size: int = DEFAULT_HAND, base_theses: int = 1, komi: int = 0,
	p_steal_cards: int = 0, p_fortify: int = 0,
	p_clinch: bool = false, p_clinch_freeze: bool = true,
	p_capture: int = 0, p_gate_x: int = 0, p_gate_y: int = 0, p_second_wind: int = 0,
	p_capture_loot: int = 0, p_zal_ko: int = 0, p_zal_hold: int = 1
) -> void:
	hand_size = p_hand_size
	steal_cards = p_steal_cards
	fortify_threshold = p_fortify
	clinch_enabled = p_clinch
	clinch_freeze = p_clinch_freeze
	capture_mode = p_capture
	gate_x = p_gate_x
	gate_y = p_gate_y
	second_wind = p_second_wind
	capture_loot = p_capture_loot
	zal_ko = p_zal_ko
	zal_hold = maxi(1, p_zal_hold)
	crowd_streak = {SIDE_YOU: 0, SIDE_OPP: 0}
	zal_bias = 0
	named_played = {SIDE_YOU: 0, SIDE_OPP: 0}
	captures = 0
	capture_theses = 0
	clinch = {}
	game_over = false
	winner = ""
	end_reason = ""
	turn_count = 0
	current = first_side
	sides = {
		SIDE_YOU: Deck.build_side(n_u, n_t, n_r, base_theses, steal_cards, hand_size),
		SIDE_OPP: Deck.build_side(n_u, n_t, n_r, base_theses, steal_cards, hand_size),
	}
	# Коми: ходящий вторым получает фору на стартовой рамке (компенсация темпа).
	if komi > 0:
		sides[other(first_side)].lines[0].theses += komi


func other(side: String) -> String:
	return SIDE_OPP if side == SIDE_YOU else SIDE_YOU


## Счёт стороны = число стоящих установок (все имеют >=1 тезис по инварианту).
func score(side: String) -> int:
	return sides[side].lines.size()


## Сила рамки = тезисы; при включённом укреплении краденые считаются вдвое (lекарство 3).
## Когда укрепление выкл — stolen чисто визуальный (золотая карта), на силу не влияет.
func line_strength(line: Dictionary) -> int:
	var s := int(line.theses)
	if fortify_threshold > 0:
		s += int(line.get("stolen", 0))
	return s


## Украденный тезис кладётся в АКТИВНУЮ установку вора (мгновенный +1 на доску).
## Если рамок нет — в колоду добора (страховка). Помечается stolen (визуал).
func _give_stolen(attacker: String, info: Dictionary) -> void:
	var al: Array = sides[attacker].lines
	if al.size() > 0:
		al[-1].theses = int(al[-1].theses) + 1
		al[-1].stolen = int(al[-1].get("stolen", 0)) + 1
	else:
		sides[attacker].draw.append({"type": TYPE_TEZIS, "name": "Перехват", "stolen": true})
	info["stolen"] = true


func is_fortified(line: Dictionary) -> bool:
	return fortify_threshold > 0 and line_strength(line) >= fortify_threshold


## Порог захвата стороны: Кража забирает целиком рамку с тезисами <= порога.
## 1 — базовый (только рамка на последнем тезисе); крен зала ПРОТИВ стороны поднимает
## порог до 2 (>= gate_x) и 3 (>= gate_y). 0 — захват выключен вовсе.
func capture_threshold(side: String) -> int:
	if capture_mode == 0:
		return 0
	var thresh := 1
	if gate_x <= 0:
		return thresh
	var crank := -zal() if side == SIDE_YOU else zal()  # крен зала против side
	if crank >= gate_x:
		thresh += 1
	if gate_y > gate_x and crank >= gate_y:
		thresh += 1
	return thresh


## Сброс — публичная стопка стороны: её потраченные карты атаки, сбитые с её рамок тезисы
## (не украденные — те уходят на доску вора), её павшие рамки. Карта со «второго дыхания»
## (recycled) повторно НЕ сбрасывается — изгоняется, чтобы финал был конечен.
func _discard(side: String, card: Dictionary) -> void:
	if card.is_empty() or card.get("recycled", false):
		return
	sides[side].discard.append(card)


## Второе дыхание: рука И добор пусты → 1 случайная карта из своего сброса (если лимит
## позволяет). Не срабатывает во время клинча (заморозка свята: воля бьётся тем, что в руке).
func _try_second_wind(s: Dictionary) -> void:
	if second_wind == 0 or clinch_active():
		return
	if not (s.hand.is_empty() and s.draw.is_empty()):
		return
	var pile: Array = s.discard
	if pile.is_empty():
		return
	if second_wind > 0 and int(s.get("sw_used", 0)) >= second_wind:
		return
	var i := randi() % pile.size()
	var c: Dictionary = pile[i]
	pile.remove_at(i)
	c["recycled"] = true
	s.hand.append(c)
	s.sw_used = int(s.get("sw_used", 0)) + 1


## Захват: переносит павшую рамку defender[idx] на сторону attacker (−1 ему, +1 себе).
## capture_mode 1 — закрытым трофеем; 2 — активной (закрывает прежнюю активную атакующего).
func _capture_frame(attacker: String, defender: String, idx: int, info: Dictionary) -> void:
	var dl: Array = sides[defender].lines
	if idx < 0 or idx >= dl.size():
		return
	var captured: Dictionary = dl[idx]
	dl.remove_at(idx)
	if capture_loot == 1:
		# «Переманил вместе с аргументами»: рамка переходит со всеми стоящими тезисами
		# (мин. 1 — добытый) — вся её сила в глазах зала теперь твоя.
		captured.theses = maxi(1, int(captured.theses))
	else:
		# Голый трофей: лишние тезисы поверх добытого — в сброс владельца.
		for k in int(captured.theses) - 1:
			_discard(defender, Deck.make_card(TYPE_TEZIS, k))
		captured.theses = 1
	captured.stolen = int(captured.theses)   # визуал: вся стопка — добыча (золото)
	captures += 1
	capture_theses += int(captured.theses)
	# Опциональная презентационная нагрузка нарративного слоя (реплики чужой рамки)
	# к трофею не относится — сбрасываем, чтобы не рассинхронить со счётом тезисов.
	if captured.has("statements"):
		captured["statements"] = []
	var al: Array = sides[attacker].lines
	if capture_mode == 2:
		if not al.is_empty():
			al[-1].closed = true
		captured.closed = false
	else:
		captured.closed = true
	al.append(captured)
	info["captured"] = true
	info["removed"] = true


## Сумма силы рамок стороны (для «блеска» / крена зала).
func shine(side: String) -> int:
	var total := 0
	for ln in sides[side].lines:
		total += line_strength(ln)
	return total


## Зал — производная стрелка: крен по числу установок И их силе (тезисам) + смещение
## zal_bias (стартовый крен забега / цена грязных приёмов). Плюс — в сторону игрока.
func zal() -> int:
	var you_w := score(SIDE_YOU) + shine(SIDE_YOU)
	var opp_w := score(SIDE_OPP) + shine(SIDE_OPP)
	return clampi(you_w - opp_w + zal_bias, -ZAL_MAX, ZAL_MAX)


func legal_types(side: String) -> Array:
	var s: Dictionary = sides[side]
	var out: Array = []
	var has := {TYPE_TEZIS: false, TYPE_RAZBOR: false, TYPE_USTANOVKA: false}
	for c in s.hand:
		has[c.type] = true
	if has[TYPE_TEZIS] and not s.lines.is_empty():
		out.append(TYPE_TEZIS)
	if has[TYPE_RAZBOR] and not sides[other(side)].lines.is_empty():
		out.append(TYPE_RAZBOR)
	if has[TYPE_USTANOVKA]:
		out.append(TYPE_USTANOVKA)
	return out


## Начало хода стороны. Возвращает статус:
##   "over"     — игра уже кончена
##   "ko"       — сторона обнулена и не может развернуть рамку → она проиграла
##   "crowd"    — крен зала в пользу стороны >= zal_ko продержался круг → она ВЫИГРАЛА (TKO)
##   "redeploy" — рамок не было, но в руке Установка: развернул её (ход потрачен)
##   "end"      — оба спасовали → решение по «Ширине» (см. winner/end_reason)
##   "pass"     — сторона не может ходить (рука пуста), но партия продолжается
##   "ok"       — сторона должна выбрать действие
func begin_turn(side: String) -> String:
	if game_over:
		return "over"
	var s: Dictionary = sides[side]
	# Именной «Перенос бремени»: защита рамки от захвата живёт до начала хода ВЛАДЕЛЬЦА.
	for ln in s.lines:
		if ln.get("braced", false):
			ln.braced = false
	# Нокаут / страховка Установкой.
	if s.lines.is_empty():
		if _hand_has(side, TYPE_USTANOVKA):
			play_action(side, TYPE_USTANOVKA)
			s.passed = false
			return "redeploy"
		_finish(other(side), "knockout")
		return "ko"
	# Зал-нокаут: крен в пользу ходящего дожил до начала его хода zal_hold раз подряд —
	# оппонент имел ход(ы) на спасение (поимка/захват) и не вернул стрелку. Зал уведён.
	if zal_ko > 0:
		var adv := zal() if side == SIDE_YOU else -zal()
		if adv >= zal_ko:
			crowd_streak[side] = int(crowd_streak.get(side, 0)) + 1
			if int(crowd_streak[side]) >= zal_hold:
				_finish(side, "crowd")
				return "crowd"
		else:
			crowd_streak[side] = 0
	# Второе дыхание ПОСЛЕ проверки нокаута (на грани топдек-лотереи нет — спасает только
	# карта, вытянутая заранее), но ДО проверки паса: сброс может вернуть сторону в игру.
	_try_second_wind(s)
	# Может ли ходить?
	if s.hand.is_empty():
		s.passed = true
		if sides[other(side)].passed:
			_end_by_decision()
			return "end"
		return "pass"
	s.passed = false
	return "ok"


func advance() -> void:
	current = other(current)


## Применить ОДНО действие. Для RAZBOR — снос одного тезиса БЕЗ воли (single-razbor).
## Волю клинча («разбор↔тезис») ведёт драйвер снаружи через remove_attack + clinch_finalize.
func play_action(side: String, type: String, target: int = -1, hand_index: int = -1) -> Dictionary:
	var info := {"side": side, "type": type, "name": "", "removed": false}
	var s: Dictionary = sides[side]
	match type:
		TYPE_TEZIS:
			var c := _remove_selected_card(side, TYPE_TEZIS, hand_index)
			info.name = c.get("name", "")
			s.lines[-1].theses = int(s.lines[-1].theses) + 1
			if c.get("stolen", false):
				s.lines[-1].stolen = int(s.lines[-1].get("stolen", 0)) + 1
		TYPE_USTANOVKA:
			var c := _remove_selected_card(side, TYPE_USTANOVKA, hand_index)
			info.name = c.get("name", "")
			if not s.lines.is_empty():
				s.lines[-1].closed = true
			s.lines.append({"theses": 1, "closed": false, "name": info.name, "stolen": 0})
		TYPE_RAZBOR:
			var c: Dictionary
			if hand_index >= 0:
				c = _remove_selected_card(side, TYPE_RAZBOR, hand_index)
			else:
				c = remove_attack(side, true)
			info.name = c.get("name", "")
			var init_steals: bool = c.get("steals", false)
			_discard(side, c)  # потраченная атака — в свой сброс
			var opp := other(side)
			var lines: Array = sides[opp].lines
			# Цель не задана — бьём по активной (последней) рамке оппонента.
			if target < 0 or target >= lines.size():
				target = lines.size() - 1
			if target >= 0 and target < lines.size():
				_resolve_single_razbor(side, opp, target, info, init_steals)
	_refill(s)
	turn_count += 1
	return info


## Разбор без клинча: снять 1 тезис; если карта — Кража, забрать его; упавшую рамку убрать.
## Кража по рамке не толще порога захвата (capture_threshold) забирает её ЦЕЛИКОМ.
func _resolve_single_razbor(attacker: String, defender: String, target: int, info: Dictionary, init_steals: bool) -> void:
	var line: Dictionary = sides[defender].lines[target]
	var will_steal := init_steals and not is_fortified(line)
	if init_steals and not will_steal:
		info["bounced"] = true
	info["target_name"] = line.name
	# Захват (базовый порог 1 = рамка на последнем тезисе; зал-гейт поднимает до 2/3).
	# braced — именной «Перенос бремени»: рамка временно не захватывается (тезис снять можно).
	if will_steal and int(line.theses) <= capture_threshold(attacker) and not line.get("braced", false):
		_capture_frame(attacker, defender, target, info)
		return
	line.theses = int(line.theses) - 1
	if will_steal:
		_give_stolen(attacker, info)
	else:
		_discard(defender, Deck.make_card(TYPE_TEZIS, 0))  # сбитый тезис — в сброс владельца
	if int(line.theses) <= 0:
		# Рамка пала (обычным Разбором, либо Кражей при выключенном захвате).
		_discard(defender, {"type": TYPE_USTANOVKA, "name": String(line.get("name", ""))})
		sides[defender].lines.remove_at(target)
		info["removed"] = true
	else:
		if int(line.get("stolen", 0)) > int(line.theses):
			line.stolen = int(line.theses)


# --- Именные приёмы (zal_run §2): розыгрыш по ИНДЕКСУ руки, диспатч по id твиста ---
## Не-клинчевые твисты; сократик идёт через begin_clinch(hand_index). Реестр карт —
## core/cards/named_cards.gd; здесь только исполнение. target — индекс рамки оппонента
## (атаки). Возвращает info хода ({} — розыгрыш нелегален, карта НЕ потрачена).

func play_named(side: String, hand_index: int, target: int = -1) -> Dictionary:
	var s: Dictionary = sides[side]
	if hand_index < 0 or hand_index >= s.hand.size():
		return {}
	var card: Dictionary = s.hand[hand_index]
	var id := String(card.get("named", ""))
	if id == "":
		return {}
	# Легальность ДО снятия карты (зеркалит legal_types: атакам нужны рамки оппонента,
	# тезису — своя активная рамка).
	if card.type == TYPE_RAZBOR and sides[other(side)].lines.is_empty():
		return {}
	if card.type == TYPE_TEZIS and s.lines.is_empty():
		return {}
	s.hand.remove_at(hand_index)
	named_played[side] = int(named_played.get(side, 0)) + 1
	var info := {"side": side, "type": String(card.type), "name": String(card.name),
		"named": id, "removed": false}
	match id:
		"gish_gallop":
			_discard(side, card)
			_named_gish(side, target, info)
		"ad_hominem":
			_discard(side, card)
			_named_ad_hominem(side, target, info)
		"strawman":
			_discard(side, card)
			_named_strawman(side, target, info)
		"burden_shift":
			var line: Dictionary = s.lines[-1]
			line.theses = int(line.theses) + 1
			line.braced = true   # не захватывается до начала хода владельца (begin_turn снимет)
			info["braced"] = true
		"axiom":
			if not s.lines.is_empty():
				s.lines[-1].closed = true
			s.lines.append({"theses": 2, "closed": false, "name": String(card.name),
				"stolen": 0, "no_defend": true})
		_:
			pass
	_refill(s)
	turn_count += 1
	return info


## Гиш-галоп: по 1 тезису с ДВУХ разных рамок (цель + самая толстая из прочих), без кражи,
## без клинча. Бьём с большего индекса к меньшему — падение рамки не сдвигает вторую цель.
func _named_gish(attacker: String, target: int, info: Dictionary) -> void:
	var opp := other(attacker)
	var lines: Array = sides[opp].lines
	if target < 0 or target >= lines.size():
		target = lines.size() - 1
	var second := -1
	var best := -1
	for i in lines.size():
		if i == target:
			continue
		if int(lines[i].theses) > best:
			best = int(lines[i].theses)
			second = i
	var hits: Array = [target] if second < 0 else [target, second]
	hits.sort()
	hits.reverse()
	info["gish_hits"] = hits.size()
	for i in hits:
		var sub := {}
		_named_chip(opp, i, sub)
		if sub.get("removed", false):
			info["removed"] = true
		if info.get("target_name", "") == "":
			info["target_name"] = sub.get("target_name", "")


## Ad hominem: снимает 2 тезиса с рамки (пала после первого — второй удар пропал),
## цена — крен зала −1 против играющего (грязный приём, §4).
func _named_ad_hominem(attacker: String, target: int, info: Dictionary) -> void:
	var opp := other(attacker)
	var lines: Array = sides[opp].lines
	if target < 0 or target >= lines.size():
		target = lines.size() - 1
	_named_chip(opp, target, info)
	if not info.get("removed", false):
		_named_chip(opp, target, info)
	zal_bias += -1 if attacker == SIDE_YOU else 1
	info["dirty"] = true


## Соломенное чучело: Кража с порогом захвата +1 («длинная рука»), добыча приходит с −1
## тезисом (мин. 1). Вне досягаемости — обычная кража тезиса (ванильный резолв).
func _named_strawman(attacker: String, target: int, info: Dictionary) -> void:
	var opp := other(attacker)
	var lines: Array = sides[opp].lines
	if target < 0 or target >= lines.size():
		target = lines.size() - 1
	var line: Dictionary = lines[target]
	if capture_mode > 0 and not is_fortified(line) and not line.get("braced", false) \
			and int(line.theses) <= capture_threshold(attacker) + 1:
		info["target_name"] = line.name
		_capture_frame(attacker, opp, target, info)
		var cap: Dictionary = sides[attacker].lines[-1]
		if int(cap.theses) > 1:
			cap.theses = int(cap.theses) - 1
			cap.stolen = mini(int(cap.get("stolen", 0)), int(cap.theses))
			_discard(opp, Deck.make_card(TYPE_TEZIS, 0))
		info["strawman"] = true
	else:
		_resolve_single_razbor(attacker, opp, target, info, true)


## Один именной удар-«чип»: −1 тезис рамки владельца, сбитое — в его сброс, павшая рамка
## снимается. Без кражи и без захвата (это механики Кражи, не потока).
func _named_chip(owner: String, idx: int, info: Dictionary) -> void:
	var lines: Array = sides[owner].lines
	if idx < 0 or idx >= lines.size():
		return
	var line: Dictionary = lines[idx]
	line.theses = int(line.theses) - 1
	_discard(owner, Deck.make_card(TYPE_TEZIS, 0))
	info["target_name"] = line.name
	if int(line.theses) <= 0:
		_discard(owner, {"type": TYPE_USTANOVKA, "name": String(line.get("name", ""))})
		lines.remove_at(idx)
		info["removed"] = true
	elif int(line.get("stolen", 0)) > int(line.theses):
		line.stolen = int(line.theses)


## Применяет исход клинча: финальный непогашенный разбор (если есть) снимает тезис и,
## возможно, крадёт; упавшую рамку убирает; добор обеим. Зовётся драйвером воли (сцена/ai).
func clinch_finalize(attacker: String, defender: String, line_index: int, t_added: int, r_count: int, info: Dictionary, atk_steals: int = 0) -> void:
	if line_index < 0 or line_index >= sides[defender].lines.size():
		return
	var line: Dictionary = sides[defender].lines[line_index]
	info["clinch_t"] = t_added
	info["clinch_r"] = r_count
	info["target_name"] = line.name
	if r_count > t_added:
		# Атакующий перестоял: ВСЕ его удары проходят по рамке (на ней уже лежат защитные
		# тезисы). Каждая Кража забирает тезис себе, Разборы — в сброс.
		var to_remove := mini(r_count, int(line.theses))
		var to_steal := 0 if is_fortified(line) else mini(atk_steals, to_remove)
		line.theses = int(line.theses) - to_remove
		# Была Кража и остаток рамки в досягаемости порога захвата (базово 0 = пала;
		# зал-гейт дотягивается до выживших с 1–2 тезисами) → рамка переходит целиком
		# (вместо россыпи краденых тезисов); снятые в клинче тезисы — в сброс владельца.
		if to_steal > 0 and int(line.theses) <= capture_threshold(attacker) - 1 and not line.get("braced", false):
			for k in to_remove:
				_discard(defender, Deck.make_card(TYPE_TEZIS, k))
			_capture_frame(attacker, defender, line_index, info)
		elif int(line.theses) <= 0:
			for k in to_steal:
				_give_stolen(attacker, info)
			info["stolen_count"] = to_steal
			for k in to_remove - to_steal:
				_discard(defender, Deck.make_card(TYPE_TEZIS, k))
			_discard(defender, {"type": TYPE_USTANOVKA, "name": String(line.get("name", ""))})
			sides[defender].lines.remove_at(line_index)
			info["removed"] = true
		else:
			for k in to_steal:
				_give_stolen(attacker, info)
			info["stolen_count"] = to_steal
			for k in to_remove - to_steal:
				_discard(defender, Deck.make_card(TYPE_TEZIS, k))
			if int(line.get("stolen", 0)) > int(line.theses):
				line.stolen = int(line.theses)
	# иначе защитник перестоял — его тезисы уже на рамке, остаются (усиление).
	_refill(sides[attacker])
	_refill(sides[defender])


# --- Клинч как явный СТЕЙТ (синхронный автомат; волю ведёт драйвер: контроллер/ai) ---
## Пусто = нет клинча. Активный: {attacker, defender, idx, t_added, r_count, atk_steals,
## init_steals, phase}. phase: "await_defend" (ход защитника) | "await_attack" (атакующего).
## Заменяет корутинный клинч UI: переходы синхронны, async/пейсинг — забота драйвера.
var clinch := {}


## Начать клинч: attacker бьёт рамку defender[idx]. Снимает первый удар, ставит стейт.
## hand_index >= 0 — клинч ИМЕННО этой картой руки (именные приёмы, напр. Сократический
## вопрос); иначе карта берётся слепо по prefer_steal (ваниль — как раньше).
## Возвращает {card, is_callback} для стартовой реплики (наррацию делает драйвер). {} если цель invalid.
func begin_clinch(attacker: String, defender: String, idx: int, prefer_steal: bool, hand_index: int = -1) -> Dictionary:
	var lines: Array = sides[defender].lines
	if idx < 0 or idx >= lines.size():
		return {}
	var initc: Dictionary
	var ah: Array = sides[attacker].hand
	if hand_index >= 0 and hand_index < ah.size() and ah[hand_index].type == TYPE_RAZBOR:
		initc = ah[hand_index]
		ah.remove_at(hand_index)
	else:
		initc = remove_attack(attacker, prefer_steal)
	var init_steals: bool = initc.get("steals", false)
	if initc.has("named"):
		named_played[attacker] = int(named_played.get(attacker, 0)) + 1
	_discard(attacker, initc)
	clinch = {
		"attacker": attacker, "defender": defender, "idx": idx,
		"t_added": 0, "r_count": 1, "atk_steals": (1 if init_steals else 0),
		"init_steals": init_steals, "phase": "await_defend",
		"named": String(initc.get("named", "")),
	}
	return {"card": initc, "is_callback": bool(lines[idx].closed)}


func clinch_active() -> bool:
	return not clinch.is_empty()


## Чья воля сейчас: await_defend → защитник, await_attack → атакующий. "" если нет клинча.
func clinch_pending_side() -> String:
	if clinch.is_empty():
		return ""
	return String(clinch.defender) if clinch.phase == "await_defend" else String(clinch.attacker)


## Может ли сторона, чья воля, сделать ход (есть нужная карта в руке).
## Рамку именной «Аксиомы» (no_defend) оборонять в клинче нельзя — защита всегда пас.
func clinch_can_act(side: String) -> bool:
	if clinch.is_empty():
		return false
	if clinch.phase == "await_defend":
		var dl: Array = sides[clinch.defender].lines
		var i := int(clinch.idx)
		if i >= 0 and i < dl.size() and dl[i].get("no_defend", false):
			return false
		return _hand_has(clinch.defender, TYPE_TEZIS)
	return _hand_has(clinch.attacker, TYPE_RAZBOR)


## Решение текущей стороны. "play" продолжает волю, "pass" завершает клинч (finalize).
## Возвращает {event}: "hold" (защитник держит, card=тезис) | "press" (атакующий добил,
## card=карта атаки) | "resolved" (клинч закрыт; info+landed+счётчики).
func clinch_submit(decision: String, prefer_steal: bool = true, hand_index: int = -1) -> Dictionary:
	if clinch.is_empty():
		return {}
	if decision != "play":
		return _finish_clinch()
	if clinch.phase == "await_defend":
		var line: Dictionary = sides[clinch.defender].lines[clinch.idx]
		var dc: Dictionary = _remove_selected_card(clinch.defender, TYPE_TEZIS, hand_index)
		line.theses = int(line.theses) + 1
		clinch.t_added = int(clinch.t_added) + 1
		if not clinch_freeze:
			_refill(sides[clinch.defender])
		clinch.phase = "await_attack"
		return {"event": "hold", "card": dc}
	else:
		var ac: Dictionary
		if hand_index >= 0:
			ac = _remove_selected_card(clinch.attacker, TYPE_RAZBOR, hand_index)
		else:
			ac = remove_attack(clinch.attacker, prefer_steal)
		_discard(clinch.attacker, ac)
		clinch.r_count = int(clinch.r_count) + 1
		if ac.get("steals", false):
			clinch.atk_steals = int(clinch.atk_steals) + 1
		if not clinch_freeze:
			_refill(sides[clinch.attacker])
		clinch.phase = "await_defend"
		return {"event": "press", "card": ac}


## Закрыть клинч: применить исход (clinch_finalize), очистить стейт, вернуть итог.
func _finish_clinch() -> Dictionary:
	var attacker: String = clinch.attacker
	var defender: String = clinch.defender
	var idx: int = clinch.idx
	var t_added: int = clinch.t_added
	var r_count: int = clinch.r_count
	var atk_steals: int = clinch.atk_steals
	var named: String = String(clinch.get("named", ""))
	var info := {"side": attacker, "type": TYPE_RAZBOR}
	clinch = {}   # очистить ДО finalize, чтобы рендер не считал рамку контестом
	clinch_finalize(attacker, defender, idx, t_added, r_count, info, atk_steals)
	# Именной «Сократический вопрос»: защитник отвечал тезисами → первый защитный тезис
	# уходит атакующему (ловушка). Рамка снята в finalize — ловушка сгорела вместе с ней.
	if named == "socratic" and t_added > 0:
		_socratic_trap(attacker, defender, idx, info)
	return {
		"event": "resolved", "info": info, "landed": r_count > t_added,
		"attacker": attacker, "defender": defender, "idx": idx,
		"t_added": t_added, "r_count": r_count,
	}


func _socratic_trap(attacker: String, defender: String, idx: int, info: Dictionary) -> void:
	var dl: Array = sides[defender].lines
	if idx < 0 or idx >= dl.size():
		return
	var line: Dictionary = dl[idx]
	line.theses = int(line.theses) - 1
	_give_stolen(attacker, info)
	info["socratic"] = true
	if int(line.theses) <= 0:
		_discard(defender, {"type": TYPE_USTANOVKA, "name": String(line.get("name", ""))})
		dl.remove_at(idx)
		info["removed"] = true
	elif int(line.get("stolen", 0)) > int(line.theses):
		line.stolen = int(line.theses)


# Публичные обёртки для драйвера воли (сцена/ai сами ведут «разбор↔тезис»).
func has_card(side: String, type: String) -> bool:
	return _hand_has(side, type)

func remove_card_of(side: String, type: String) -> Dictionary:
	return _remove_card(side, type)

## Снять карту атаки нужного вида: prefer_steal=true → Кражу, иначе обычный Разбор.
## Если нужного вида нет — любую карту атаки. Именные атаки берегутся (второй проход):
## их место — осознанный розыгрыш по индексу (play_named / begin_clinch hand_index).
func remove_attack(side: String, prefer_steal: bool) -> Dictionary:
	var hand: Array = sides[side].hand
	for pass_named in [false, true]:
		for i in hand.size():
			if hand[i].type == TYPE_RAZBOR and bool(hand[i].get("steals", false)) == prefer_steal \
					and hand[i].has("named") == pass_named:
				var c: Dictionary = hand[i]
				hand.remove_at(i)
				return c
	return _remove_card(side, TYPE_RAZBOR)

func refill_side(side: String) -> void:
	_refill(sides[side])


# --- внутреннее ---

func _refill(s: Dictionary) -> void:
	Deck.refill(s, hand_size)
	_try_second_wind(s)


func _hand_has(side: String, type: String) -> bool:
	for c in sides[side].hand:
		if c.type == type:
			return true
	return false


func _remove_card(side: String, type: String) -> Dictionary:
	var hand: Array = sides[side].hand
	# Слепой добор типа тратит сперва ванильные карты — именные берегутся для розыгрыша
	# по индексу (второй проход отдаёт именную, если других не осталось).
	for pass_named in [false, true]:
		for i in hand.size():
			if hand[i].type == type and hand[i].has("named") == pass_named:
				var c: Dictionary = hand[i]
				hand.remove_at(i)
				return c
	return {}


## UI выбирает конкретную карту, а не только её тип. Fallback сохраняет старый API для AI,
## симуляций и страховочных автодействий, где hand_index не передаётся.
func _remove_selected_card(side: String, type: String, hand_index: int) -> Dictionary:
	var hand: Array = sides[side].hand
	if hand_index >= 0 and hand_index < hand.size() and String(hand[hand_index].type) == type:
		var card: Dictionary = hand[hand_index]
		hand.remove_at(hand_index)
		return card
	return _remove_card(side, type)


func _finish(win_side: String, reason: String) -> void:
	game_over = true
	winner = win_side
	end_reason = reason


## Решение по «Ширине»; тай-брейк — зал (число установок + блеск). Ничья только при
## полном равенстве веса. Так зал из §3 работает как условие, а не только индикатор.
func _end_by_decision() -> void:
	game_over = true
	var sy := score(SIDE_YOU)
	var so := score(SIDE_OPP)
	if sy != so:
		winner = SIDE_YOU if sy > so else SIDE_OPP
		end_reason = "decision"
		return
	var z := zal()  # score+shine diff, плюс — в сторону игрока
	if z > 0:
		winner = SIDE_YOU
		end_reason = "decision"
	elif z < 0:
		winner = SIDE_OPP
		end_reason = "decision"
	else:
		winner = ""
		end_reason = "draw"
