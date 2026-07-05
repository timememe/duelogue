extends RefCounted

## DUELOGUE — ядро v0.3: спор как битва аргументов (спека: context/zal_core_v0.3.md).
## Чистая логика без UI. Используется сценой zal_v3.gd и симулятором zal_v3_sim.gd.
## НЕ зависит от основного движка.
##
## Доска: у каждой стороны линия установок (рамок). У рамки сверху лежат тезисы.
## Активна последняя установка. Закрытая (замороженная новой) не принимает тезисы.
## Установка с 0 тезисов удаляется. Счёт = число стоящих установок ("Ширина").

const TYPE_TEZIS := "T"
const TYPE_RAZBOR := "R"
const TYPE_USTANOVKA := "U"

const SIDE_YOU := "you"
const SIDE_OPP := "opp"

const DEFAULT_HAND := 5
const ZAL_MAX := 20

const TEZIS_NAMES := ["Довод", "Контрфакт", "Аргумент", "Уточнение", "Пример", "Ссылка", "Факт", "Логика"]
const RAZBOR_NAMES := ["Не в кассу", "Передёрг", "Контрпример", "Софизм?", "Источник?", "Подмена", "Мимо", "А докажи"]
const USTANOVKA_NAMES := ["Рамка", "Тезис дня", "Позиция", "Постулат", "Принцип", "Аксиома"]

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
## разбор и +1 к рамке), атакующий — добивать разбором. Воля до паса; кто перестоял.
## clinch_freeze — заморозка добора на время воли (бой из руки, аггро может выдохнуться).
var clinch_enabled := false
var clinch_freeze := true
## Захват рамки (teardown-рычаг против храповика): Кража, снёсшая ПОСЛЕДНИЙ тезис рамки,
## переносит рамку к атакующему (−1 оппоненту, +1 себе), а не просто сносит её.
## 0 — выкл; 1 — приходит ЗАКРЫТЫМ трофеем; 2 — приходит АКТИВНОЙ (закрывает прежнюю активную).
var capture_mode := 0
## Стиль ИИ по стороне — чтобы клинч-решения (внутри _resolve_clinch) знали, умная ли сторона.
## Ставится в simulate() и сценой через set_ai_style(). "" — человек/дефолт.
var ai_style := {}


func reset(
	first_side: String, n_u: int, n_t: int, n_r: int,
	p_hand_size: int = DEFAULT_HAND, base_theses: int = 1, komi: int = 0,
	p_steal_cards: int = 0, p_fortify: int = 0,
	p_clinch: bool = false, p_clinch_freeze: bool = true,
	p_capture: int = 0
) -> void:
	hand_size = p_hand_size
	steal_cards = p_steal_cards
	fortify_threshold = p_fortify
	clinch_enabled = p_clinch
	clinch_freeze = p_clinch_freeze
	capture_mode = p_capture
	ai_style = {}
	game_over = false
	winner = ""
	end_reason = ""
	turn_count = 0
	current = first_side
	sides = {
		SIDE_YOU: _new_side(n_u, n_t, n_r, base_theses),
		SIDE_OPP: _new_side(n_u, n_t, n_r, base_theses),
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


## Захват: переносит павшую рамку defender[idx] на сторону attacker (−1 ему, +1 себе).
## capture_mode 1 — закрытым трофеем; 2 — активной (закрывает прежнюю активную атакующего).
func _capture_frame(attacker: String, defender: String, idx: int, info: Dictionary) -> void:
	var dl: Array = sides[defender].lines
	if idx < 0 or idx >= dl.size():
		return
	var captured: Dictionary = dl[idx]
	dl.remove_at(idx)
	captured.theses = 1            # рамка переходит с 1 тезисом (добытым)
	captured.stolen = 1            # визуал: добыта
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


## Зал — производная стрелка: крен по числу установок И их силе (тезисам).
## Вклад рамки = 1 (за установку) + тезисы (за блеск). Плюс — в сторону игрока.
func zal() -> int:
	var you_w := score(SIDE_YOU) + shine(SIDE_YOU)
	var opp_w := score(SIDE_OPP) + shine(SIDE_OPP)
	return clampi(you_w - opp_w, -ZAL_MAX, ZAL_MAX)


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
##   "redeploy" — рамок не было, но в руке Установка: развернул её (ход потрачен)
##   "end"      — оба спасовали → решение по «Ширине» (см. winner/end_reason)
##   "pass"     — сторона не может ходить (рука пуста), но партия продолжается
##   "ok"       — сторона должна выбрать действие
func begin_turn(side: String) -> String:
	if game_over:
		return "over"
	var s: Dictionary = sides[side]
	# Нокаут / страховка Установкой.
	if s.lines.is_empty():
		if _hand_has(side, TYPE_USTANOVKA):
			play_action(side, TYPE_USTANOVKA)
			s.passed = false
			return "redeploy"
		_finish(other(side), "knockout")
		return "ko"
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


func play_action(side: String, type: String, target: int = -1) -> Dictionary:
	var info := {"side": side, "type": type, "name": "", "removed": false}
	var s: Dictionary = sides[side]
	match type:
		TYPE_TEZIS:
			var c := _remove_card(side, TYPE_TEZIS)
			info.name = c.get("name", "")
			s.lines[-1].theses = int(s.lines[-1].theses) + 1
			if c.get("stolen", false):
				s.lines[-1].stolen = int(s.lines[-1].get("stolen", 0)) + 1
		TYPE_USTANOVKA:
			var c := _remove_card(side, TYPE_USTANOVKA)
			info.name = c.get("name", "")
			if not s.lines.is_empty():
				s.lines[-1].closed = true
			s.lines.append({"theses": 1, "closed": false, "name": info.name, "stolen": 0})
		TYPE_RAZBOR:
			var c := remove_attack(side, true)
			info.name = c.get("name", "")
			var init_steals: bool = c.get("steals", false)
			var opp := other(side)
			var lines: Array = sides[opp].lines
			if target < 0 or target >= lines.size():
				target = _razbor_target(side)
			if target >= 0 and target < lines.size():
				if clinch_enabled:
					_resolve_clinch(side, opp, target, info, init_steals)
				else:
					_resolve_single_razbor(side, opp, target, info, init_steals)
	_refill(s)
	turn_count += 1
	return info


## Разбор без клинча: снять 1 тезис; если карта — Кража, забрать его; упавшую рамку убрать.
func _resolve_single_razbor(attacker: String, defender: String, target: int, info: Dictionary, init_steals: bool) -> void:
	var line: Dictionary = sides[defender].lines[target]
	var will_steal := init_steals and not is_fortified(line)
	if init_steals and not will_steal:
		info["bounced"] = true
	line.theses = int(line.theses) - 1
	info["target_name"] = line.name
	if int(line.theses) <= 0:
		# Рамка пала. Если её добила Кража и захват включён — переносим рамку себе.
		if will_steal and capture_mode > 0:
			_capture_frame(attacker, defender, target, info)
		else:
			if will_steal:
				_give_stolen(attacker, info)
			sides[defender].lines.remove_at(target)
			info["removed"] = true
	else:
		if int(line.get("stolen", 0)) > int(line.theses):
			line.stolen = int(line.theses)
		if will_steal:
			_give_stolen(attacker, info)


## Клинч: воля «разбор → тезис → разбор → …» по атакованной рамке, пока кто-то не спасует.
## Каждый тезис гасит разбор И остаётся на рамке (защита усиливает). Если атакующий
## продавил (на 1 разбор больше) — финальный разбор проходит (с шансом кражи).
func _resolve_clinch(attacker: String, defender: String, target: int, info: Dictionary, init_steals: bool = false) -> void:
	var line: Dictionary = sides[defender].lines[target]
	var t_added := 0
	var r_count := 1
	var atk_steals := 1 if init_steals else 0
	var guard := 0
	while guard < 60:
		guard += 1
		# Защитник отвечает тезисом?
		if _hand_has(defender, TYPE_TEZIS) and _def_will_clinch(defender, line):
			_remove_card(defender, TYPE_TEZIS)
			line.theses = int(line.theses) + 1
			t_added += 1
			if not clinch_freeze:
				_refill(sides[defender])
		else:
			break
		# Атакующий добивает (предпочитает Кражу)?
		if _hand_has(attacker, TYPE_RAZBOR) and _atk_will_clinch(attacker, line):
			var ac := remove_attack(attacker, true)
			r_count += 1
			if ac.get("steals", false):
				atk_steals += 1
			if not clinch_freeze:
				_refill(sides[attacker])
		else:
			break
	clinch_finalize(attacker, defender, target, t_added, r_count, info, atk_steals)


## Применяет исход клинча: финальный непогашенный разбор (если есть) снимает тезис и,
## возможно, крадёт; упавшую рамку убирает; добор обеим. Зовётся и автo-волей, и сценой.
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
		if int(line.theses) <= 0:
			# Рамка пала в клинче. Если среди добивших была Кража и захват включён —
			# переносим рамку себе (вместо снятия + россыпи краденых тезисов).
			if to_steal > 0 and capture_mode > 0:
				_capture_frame(attacker, defender, line_index, info)
			else:
				for k in to_steal:
					_give_stolen(attacker, info)
				info["stolen_count"] = to_steal
				sides[defender].lines.remove_at(line_index)
				info["removed"] = true
		else:
			for k in to_steal:
				_give_stolen(attacker, info)
			info["stolen_count"] = to_steal
			if int(line.get("stolen", 0)) > int(line.theses):
				line.stolen = int(line.theses)
	# иначе защитник перестоял — его тезисы уже на рамке, остаются (усиление).
	_refill(sides[attacker])
	_refill(sides[defender])


# Публичные обёртки для интерактивной сцены (та сама ведёт волю, спрашивая человека).
func has_card(side: String, type: String) -> bool:
	return _hand_has(side, type)

func remove_card_of(side: String, type: String) -> Dictionary:
	return _remove_card(side, type)

## Снять карту атаки нужного вида: prefer_steal=true → Кражу, иначе обычный Разбор.
## Если нужного вида нет — любую карту атаки.
func remove_attack(side: String, prefer_steal: bool) -> Dictionary:
	var hand: Array = sides[side].hand
	for i in hand.size():
		if hand[i].type == TYPE_RAZBOR and bool(hand[i].get("steals", false)) == prefer_steal:
			var c: Dictionary = hand[i]
			hand.remove_at(i)
			return c
	return _remove_card(side, TYPE_RAZBOR)

func refill_side(side: String) -> void:
	_refill(sides[side])

func set_ai_style(side: String, style: String) -> void:
	ai_style[side] = style

func ai_def_will_clinch(side: String, line: Dictionary) -> bool:
	return _def_will_clinch(side, line)

func ai_atk_will_clinch(side: String, line: Dictionary) -> bool:
	return _atk_will_clinch(side, line)


func _def_will_clinch(defender: String, line: Dictionary) -> bool:
	if String(ai_style.get(defender, "")) == "smart":
		return _smart_def_will_clinch(defender, line)
	# Обязательно защищаем, если потеря рамки = нокаут.
	if sides[defender].lines.size() == 1 and int(line.theses) <= 1:
		return true
	return randf() < 0.75


func _atk_will_clinch(attacker: String, line: Dictionary) -> bool:
	if String(ai_style.get(attacker, "")) == "smart":
		return _smart_atk_will_clinch(attacker, line)
	# Дожимаем охотнее, если рамка вот-вот падёт.
	if int(line.theses) <= 1:
		return true
	return randf() < 0.5


## Умная защита в клинче — по ЭКОНОМИКЕ РУКИ (ось мастерства из GDD §7), не по монетке.
func _smart_def_will_clinch(defender: String, line: Dictionary) -> bool:
	var theses := int(line.theses)
	# Потеря рамки = нокаут → держим обязательно.
	if sides[defender].lines.size() == 1 and theses <= 1:
		return true
	var tez := _hand_count(defender, TYPE_TEZIS)
	if tez == 0:
		return false
	# Рамку вот-вот ЗАХВАТЯТ (1 тезис, захват вкл) — защита переводит её в безопасные 2.
	if capture_mode > 0 and theses <= 1:
		return true
	# Иначе держим только при запасе тезисов — не палим последнюю карту на дешёвую рамку.
	return tez >= 2


## Умное добивание — дожимаем, только когда это окупается и есть запас атак.
func _smart_atk_will_clinch(attacker: String, line: Dictionary) -> bool:
	var atk := _hand_count(attacker, TYPE_RAZBOR)
	if atk == 0:
		return false
	# Рамка вот-вот падёт (а с Кражей — ещё и захват) → добиваем.
	if int(line.theses) <= 1:
		return true
	# Дожимать дальше — только при запасе атак.
	return atk >= 2


## Выбор хода ИИ по стилю. Возвращает {type, target?}.
func ai_pick(side: String, style: String) -> Dictionary:
	if style == "smart":
		return _ai_pick_smart(side)
	var legal := legal_types(side)
	if legal.is_empty():
		return {}
	var opp := other(side)
	var opp_lines: Array = sides[opp].lines

	# 1. Летальный разбор (снять последнюю рамку оппонента).
	if legal.has(TYPE_RAZBOR) and opp_lines.size() == 1 and int(opp_lines[0].theses) == 1:
		return {"type": TYPE_RAZBOR, "target": 0}

	# 2. Выживание: единственная хрупкая рамка — укрепить.
	var me: Dictionary = sides[side]
	if me.lines.size() == 1 and int(me.lines[0].theses) <= 1:
		if legal.has(TYPE_TEZIS):
			return {"type": TYPE_TEZIS}
		if legal.has(TYPE_USTANOVKA):
			return {"type": TYPE_USTANOVKA}

	# 3. По стилю.
	for pref in _style_order(style):
		if pref == TYPE_RAZBOR and legal.has(TYPE_RAZBOR):
			var t := _razbor_target(side)
			if t >= 0:
				return {"type": TYPE_RAZBOR, "target": t}
		elif legal.has(pref):
			return {"type": pref}
	return {"type": legal[0]}


## Умный бот: играет ось мастерства (GDD §7) — захват, защита от захвата, teardown под
## отставание, иначе строит ширину. Клинч-решения экономные (см. _smart_*_will_clinch).
func _ai_pick_smart(side: String) -> Dictionary:
	var legal := legal_types(side)
	if legal.is_empty():
		return {}
	var opp := other(side)
	var opp_lines: Array = sides[opp].lines
	var my_lines: Array = sides[side].lines

	# 1. Летал: снести последнюю рамку оппонента (нокаут).
	if legal.has(TYPE_RAZBOR) and opp_lines.size() == 1 and int(opp_lines[0].theses) == 1:
		return {"type": TYPE_RAZBOR, "target": 0}

	# 2. Выживание: единственная рамка хрупкая → укрепить (защита от KO/захвата).
	if my_lines.size() == 1 and int(my_lines[0].theses) <= 1:
		if legal.has(TYPE_TEZIS):
			return {"type": TYPE_TEZIS}
		if legal.has(TYPE_USTANOVKA):
			return {"type": TYPE_USTANOVKA}

	# 3. Капитализировать захват: чужая рамка на 1 тезисе + Кража в руке → забрать (+2 к счёту).
	if capture_mode > 0 and legal.has(TYPE_RAZBOR) and _hand_has_steal(side):
		var cap_t := _capturable_target(side)
		if cap_t >= 0:
			return {"type": TYPE_RAZBOR, "target": cap_t}

	# 4. Защита от захвата: довести активную рамку до безопасных 2 тезисов прежде, чем расширяться.
	if capture_mode > 0 and legal.has(TYPE_TEZIS):
		var active: Dictionary = my_lines[-1]
		if not active.closed and int(active.theses) < 2:
			return {"type": TYPE_TEZIS}

	# 5. Отстаю по ширине → давить teardown: грызть лучшую чужую цель.
	if score(side) < score(opp) and legal.has(TYPE_RAZBOR):
		var t := _razbor_target(side)
		if t >= 0:
			return {"type": TYPE_RAZBOR, "target": t}

	# 6. Иначе строю ширину (она напрямую к победе); запас тезисов держит экономику.
	if legal.has(TYPE_USTANOVKA):
		return {"type": TYPE_USTANOVKA}
	if legal.has(TYPE_TEZIS):
		return {"type": TYPE_TEZIS}
	if legal.has(TYPE_RAZBOR):
		var t2 := _razbor_target(side)
		if t2 >= 0:
			return {"type": TYPE_RAZBOR, "target": t2}
	return {"type": legal[0]}


## Полный матч ИИ vs ИИ. Возвращает результат для метрик.
## Дополнительно трекает динамику лида (диагностика «статичности» исхода):
##   diffs        — ряд (score_you − score_opp) после каждого действия;
##   lead_changes — сколько раз менялся лидер (знак диффа) за партию;
##   decision_frac — доля партии (0..1), пройденная к моменту, когда будущий
##                   победитель взял лид и больше его не отдавал (1.0 — решилось только в конце).
func simulate(style_you: String, style_opp: String, max_turns: int = 400) -> Dictionary:
	ai_style[SIDE_YOU] = style_you
	ai_style[SIDE_OPP] = style_opp
	var guard := 0
	var diffs: Array[int] = []
	while not game_over and guard < max_turns:
		guard += 1
		var st := begin_turn(current)
		if st == "ko" or st == "end" or st == "over":
			break
		if st == "redeploy" or st == "pass":
			advance()
			continue
		var style := style_you if current == SIDE_YOU else style_opp
		var act := ai_pick(current, style)
		if act.is_empty():
			sides[current].passed = true
			if sides[other(current)].passed:
				_end_by_decision()
				break
			advance()
			continue
		play_action(current, act.type, act.get("target", -1))
		diffs.append(score(SIDE_YOU) - score(SIDE_OPP))
		advance()
	if not game_over:
		_end_by_decision()
	return {
		"winner": winner,
		"reason": end_reason,
		"turns": turn_count,
		"score_you": score(SIDE_YOU),
		"score_opp": score(SIDE_OPP),
		"lead_changes": _count_lead_changes(diffs),
		"decision_frac": _decision_frac(diffs, winner),
	}


## Число смен лидера: переходы знака диффа (нули — «ничейный» лид — пропускаем,
## смена считается между последним ненулевым знаком и новым ненулевым).
func _count_lead_changes(diffs: Array[int]) -> int:
	var changes := 0
	var last_sign := 0
	for d in diffs:
		var s := signi(d)
		if s != 0 and s != last_sign:
			if last_sign != 0:
				changes += 1
			last_sign = s
	return changes


## Доля партии до «точки решения»: ищем последний момент, когда победитель НЕ был
## строго впереди; решение наступило сразу после него. Ничья / пустой ряд → 1.0.
func _decision_frac(diffs: Array[int], win: String) -> float:
	if win == "" or diffs.is_empty():
		return 1.0
	var sign := 1 if win == SIDE_YOU else -1
	var last_not_ahead := -1
	for i in diffs.size():
		if diffs[i] * sign <= 0:
			last_not_ahead = i
	return float(last_not_ahead + 1) / float(diffs.size())


# --- внутреннее ---

func _new_side(n_u: int, n_t: int, n_r: int, base_theses: int = 1) -> Dictionary:
	var draw: Array = []
	for i in n_t:
		draw.append(_mk(TYPE_TEZIS, i))
	# Карты атаки: часть — Кражи (steals), остальные — обычные Разборы.
	var n_steal := clampi(steal_cards, 0, n_r)
	var n_plain := n_r - n_steal
	for i in n_plain:
		draw.append(_mk(TYPE_RAZBOR, i))
	for i in n_steal:
		draw.append({"type": TYPE_RAZBOR, "name": "Кража", "steals": true})
	for i in n_u:
		draw.append(_mk(TYPE_USTANOVKA, i))
	draw.shuffle()
	var s := {
		"lines": [{"theses": maxi(1, base_theses), "closed": false, "name": "База", "stolen": 0}],
		"hand": [],
		"draw": draw,
		"passed": false,
	}
	_refill(s)
	return s


func _mk(type: String, i: int) -> Dictionary:
	var nm := ""
	match type:
		TYPE_TEZIS: nm = TEZIS_NAMES[i % TEZIS_NAMES.size()]
		TYPE_RAZBOR: nm = RAZBOR_NAMES[i % RAZBOR_NAMES.size()]
		TYPE_USTANOVKA: nm = USTANOVKA_NAMES[i % USTANOVKA_NAMES.size()]
	return {"type": type, "name": nm, "steals": false}


func _refill(s: Dictionary) -> void:
	while s.hand.size() < hand_size and not s.draw.is_empty():
		s.hand.append(s.draw.pop_back())


func _hand_has(side: String, type: String) -> bool:
	for c in sides[side].hand:
		if c.type == type:
			return true
	return false


func _hand_count(side: String, type: String) -> int:
	var n := 0
	for c in sides[side].hand:
		if c.type == type:
			n += 1
	return n


func _hand_has_steal(side: String) -> bool:
	for c in sides[side].hand:
		if c.type == TYPE_RAZBOR and bool(c.get("steals", false)):
			return true
	return false


## Индекс чужой рамки, которую можно ЗАХВАТИТЬ Кражей (ровно 1 тезис, не укреплена). -1 если нет.
func _capturable_target(side: String) -> int:
	var lines: Array = sides[other(side)].lines
	for i in lines.size():
		if int(lines[i].theses) == 1 and not is_fortified(lines[i]):
			return i
	return -1


func _remove_card(side: String, type: String) -> Dictionary:
	var hand: Array = sides[side].hand
	for i in hand.size():
		if hand[i].type == type:
			var c: Dictionary = hand[i]
			hand.remove_at(i)
			return c
	return {}


## Лучшая цель для разбора: снять последнюю рамку (KO) > убрать 1-тезисную рамку >
## грызть самую жирную закрытую (неремонтопригодную) > грызть самую жирную.
func _razbor_target(side: String) -> int:
	var lines: Array = sides[other(side)].lines
	if lines.is_empty():
		return -1
	if lines.size() == 1 and int(lines[0].theses) == 1:
		return 0
	var best := -1
	var best_score := -1.0
	for i in lines.size():
		var ln: Dictionary = lines[i]
		var sc := 0.0
		if int(ln.theses) == 1:
			sc = 100.0
		else:
			sc = float(ln.theses)
			if ln.closed:
				sc += 0.5
		# Укреплённая рамка — плохая цель: кража отскакивает, а сама она глубокая.
		if is_fortified(ln):
			sc -= 50.0
		if sc > best_score:
			best_score = sc
			best = i
	return best


func _style_order(style: String) -> Array:
	match style:
		"wide": return [TYPE_USTANOVKA, TYPE_TEZIS, TYPE_RAZBOR]
		"tall": return [TYPE_TEZIS, TYPE_USTANOVKA, TYPE_RAZBOR]
		"aggro": return [TYPE_RAZBOR, TYPE_TEZIS, TYPE_USTANOVKA]
		"defensive": return [TYPE_TEZIS, TYPE_RAZBOR, TYPE_USTANOVKA]
		_:
			var opts := [TYPE_TEZIS, TYPE_RAZBOR, TYPE_USTANOVKA]
			opts.shuffle()
			return opts


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
