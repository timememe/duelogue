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
const Grammar := preload("res://duelogue/core/cards/grammar.gd")
const ComboRegister := preload("res://duelogue/core/rules/combo_register.gd")

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
## Захват рамки (teardown-рычаг против храповика): только разблокированная Кража, сыгранная
## прямо в рамку в пределах reach, переносит её атакующему (−1 оппоненту, +1 себе).
## Ответный Тезис накрывает именно её; поздняя атака снимает exact T, после чего unwind
## снова открывает исходную Кражу по рамке.
## 0 — выкл; 1 — приходит ЗАКРЫТЫМ трофеем; 2 — приходит АКТИВНОЙ (закрывает прежнюю активную).
var capture_mode := 0
## Audience wobble band. A one-thesis frame is always exposed. If public Lean favours
## the frame owner, every point in [gate_x..gate_y] raises direct Theft reach by one:
## defaults 2->2, 3->3, 4+->4. gate_x=0 disables only the extra crowd reach.
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
## Экспериментальный шов: по умолчанию zal() остаётся старой производной доски. Профиль
## может передать независимый Lean из AudienceCore; гейт/TKO читают тот же публичный API.
var external_zal_enabled := false
var external_zal := 0
var external_zal_cap := ZAL_MAX
## Векторные профили доводят матч до общего вердикта даже после потери последней рамки.
## Legacy сохраняет немедленный нокаут. Саму формулу вердикта RulesCore не знает.
var board_ko_enabled := true
## Розыгрыши именных приёмов за партию по сторонам (диагностика сима/плейтеста).
var named_played := {}
## Тезис — не только число на рамке, а конкретный объект карты. Скалярные theses/stolen
## остаются совместимым read-model для UI и старых симов; авторитетный порядок хранится
## в line.thesis_stack (снизу вверх), а thesis_id связывает карту, реплику и цель эффекта.
var _thesis_serial := 0
## R0 комбо-регистра (combo_register_architecture §7/§9): три минимальные identity.
## frame_id живёт на объекте рамки и переживает перенос/захват; action_id — один полный
## игровой action (у клинча — всё ралли целиком); play_id — occurrence розыгрыша карты
## в матче (одна и та же карта после recycle получает новый play_id). Пока чистая
## телеметрия: комбо-поведение и решения ядра эти id не читают.
var _frame_serial := 0
var _action_serial := 0
var _play_serial := 0
## R1 регистра: механический relation trace клинча. Ребро — физический факт розыгрыша
## («кто, когда, куда»), НЕ семантический вердикт: eligibility и маршруты решает matcher.
## Content-relations (supports/undercuts…) по шву §7 добавит controller тем же контрактом.
var _relation_serial := 0
## R2: единственный ComboRegister матча (§3) — Pattern-каталог и derived runs. Легаси-поля
## combo_*/closer_* клинча и info пишутся ТОЛЬКО из его legacy_view() (§7).
var combo_register := ComboRegister.new()


func reset(
	first_side: String, n_u: int, n_t: int, n_r: int,
	p_hand_size: int = DEFAULT_HAND, base_theses: int = 1, komi: int = 0,
	p_steal_cards: int = 0, p_fortify: int = 0,
	p_clinch: bool = false, p_clinch_freeze: bool = true,
	p_capture: int = 0, p_gate_x: int = 0, p_gate_y: int = 0, p_second_wind: int = 0,
	p_capture_loot: int = 0, p_zal_ko: int = 0, p_zal_hold: int = 1,
	p_board_ko_enabled: bool = true
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
	board_ko_enabled = p_board_ko_enabled
	crowd_streak = {SIDE_YOU: 0, SIDE_OPP: 0}
	zal_bias = 0
	external_zal_enabled = false
	external_zal = 0
	external_zal_cap = ZAL_MAX
	named_played = {SIDE_YOU: 0, SIDE_OPP: 0}
	_thesis_serial = 0
	_frame_serial = 0
	_action_serial = 0
	_play_serial = 0
	_relation_serial = 0
	combo_register = ComboRegister.new()
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
	for side_key in [SIDE_YOU, SIDE_OPP]:
		for ln in sides[side_key].lines:
			_ensure_frame_id(ln)
	# Коми: ходящий вторым получает фору на стартовой рамке (компенсация темпа).
	if komi > 0:
		sides[other(first_side)].lines[0].theses += komi
	# Та же экономика рамок, что и у розыгрыша Установки в игре: стартовая База получает
	# реальные случайные тезисы с первого хода, а не ленивый filler (§ правка «Заявка»).
	seed_starting_theses(SIDE_YOU)
	seed_starting_theses(SIDE_OPP)


## Публичная: reset() зовёт это для обеих сторон сразу после сборки. Дополнительно нужна
## вызывающему коду, который пересобирает sides[side] напрямую через Deck.build_side()
## ПОСЛЕ reset() (battle_controller — сторона игрока из профиля редактора колоды) —
## такая пересборка минует reset() и снова оставляет ленивый filler, если не досеять руками.
func seed_starting_theses(side: String) -> void:
	for ln in sides[side].lines:
		var want := int(ln.get("theses", 1))
		for i in want:
			_seed_frame_thesis(side, ln)


func other(side: String) -> String:
	return SIDE_OPP if side == SIDE_YOU else SIDE_YOU


## Счёт стороны = число стоящих установок (все имеют >=1 тезис по инварианту).
func score(side: String) -> int:
	return sides[side].lines.size()


func _next_thesis_id() -> String:
	_thesis_serial += 1
	return "thesis_%d" % _thesis_serial


func _next_frame_id() -> String:
	_frame_serial += 1
	return "frame_%d" % _frame_serial


func _next_action_id() -> String:
	_action_serial += 1
	return "action_%d" % _action_serial


func _next_play_id() -> String:
	_play_serial += 1
	return "play_%d" % _play_serial


## Ленивый сторож по образцу _ensure_thesis_stack: рамки создают и ядро, и тесты/ран-слой
## напрямую — identity догоняет объект при первом касании. Сам объект переносится при
## захвате целиком, поэтому frame_id постоянен на всю жизнь рамки.
func _ensure_frame_id(line: Dictionary) -> String:
	if String(line.get("frame_id", "")) == "":
		line["frame_id"] = _next_frame_id()
	return String(line["frame_id"])


## RelationFact (§2.3 архитектуры): типизированное ребро между exact ссылками.
## Механические связи (provenance="rules") эмитит ядро в момент розыгрыша;
## content-рёбра приходят через add_content_relation (шов §7, вариант 2).
func _relation_fact(type: String, from_kind: String, from_id: String,
		to_kind: String, to_id: String, action_id: String,
		provenance: String = "rules", attrs: Dictionary = {}) -> Dictionary:
	_relation_serial += 1
	return {"id": "rel_%d" % _relation_serial, "type": type,
		"from": {"kind": from_kind, "id": from_id},
		"to": {"kind": to_kind, "id": to_id},
		"scope_refs": [{"kind": "action", "id": action_id}],
		"provenance": provenance,
		"attrs": attrs.duplicate(true)}


## Шов §7 (вариант 2): controller добавляет content-RelationFact ПОСЛЕ физического play
## и ДО settlement. Ядро не знает риторических route names — только общий контракт ребра;
## register сам решает, вооружает ли факт какой-нибудь content-гейт рецепта. R3: только
## clinch-scope (единственный потребитель — A3-рецепты).
func add_content_relation(type: String, from_kind: String, from_id: String,
		to_kind: String, to_id: String, attrs: Dictionary = {}) -> Dictionary:
	if clinch.is_empty():
		return {}
	var action_id := String(clinch.get("action_id", ""))
	var rel := _relation_fact(type, from_kind, from_id, to_kind, to_id, action_id,
		"content", attrs)
	var relations: Array = clinch.get("relations", [])
	relations.append(rel)
	clinch["relations"] = relations
	combo_register.on_content_relation(action_id, rel)
	return rel


## Authoritative stable-board snapshot для frame-scoped recipes. Register не хранит
## копию доски: получает exact рамки/порядок только на boundary полного action.
func _combo_board_snapshot() -> Array:
	var out: Array = []
	for side in [SIDE_YOU, SIDE_OPP]:
		for raw in sides[side].lines:
			var line: Dictionary = raw
			out.append({"frame_id": _ensure_frame_id(line), "owner": side,
				"thesis_stack": _ensure_thesis_stack(line).duplicate(true)})
	return out


func _settle_frame_combo_events(info: Dictionary) -> void:
	var action_id := String(info.get("action_id", ""))
	if action_id == "":
		return
	combo_register.board_stable(action_id, _combo_board_snapshot())
	info["combo_events"] = combo_register.events_for_action(action_id)


func _thesis_token(card: Dictionary = {}) -> Dictionary:
	var token: Dictionary = card if not card.is_empty() else Deck.filler_thesis()
	token["type"] = TYPE_TEZIS
	if String(token.get("name", "")) == "":
		token["name"] = "Тезис"
	if String(token.get("thesis_id", "")) == "":
		token["thesis_id"] = _next_thesis_id()
	return token


## Лениво мигрирует старую рамку {theses, stolen} в стек объектов. Если тест/ран-слой
## напрямую поправил совместимый скаляр, стек один раз догоняет его; все штатные мутации
## ниже меняют объект и тут же пересчитывают скаляры обратно.
func _ensure_thesis_stack(line: Dictionary) -> Array:
	_ensure_frame_id(line)
	var wanted := maxi(0, int(line.get("theses", 0)))
	var wanted_stolen := clampi(int(line.get("stolen", 0)), 0, wanted)
	var stack: Array = line.get("thesis_stack", [])
	while stack.size() < wanted:
		stack.append(_thesis_token())
	while stack.size() > wanted:
		stack.pop_back()
	for raw in stack:
		_thesis_token(raw as Dictionary)
	var actual_stolen := 0
	for raw in stack:
		if bool((raw as Dictionary).get("stolen", false)):
			actual_stolen += 1
	if actual_stolen < wanted_stolen:
		for i in range(stack.size() - 1, -1, -1):
			var token: Dictionary = stack[i]
			if not bool(token.get("stolen", false)):
				token["stolen"] = true
				actual_stolen += 1
				if actual_stolen == wanted_stolen:
					break
	elif actual_stolen > wanted_stolen:
		for i in range(stack.size() - 1, -1, -1):
			var token: Dictionary = stack[i]
			if bool(token.get("stolen", false)):
				token.erase("stolen")
				actual_stolen -= 1
				if actual_stolen == wanted_stolen:
					break
	line["thesis_stack"] = stack
	return stack


func _sync_thesis_scalars(line: Dictionary) -> void:
	var stack: Array = line.get("thesis_stack", [])
	line["theses"] = stack.size()
	var stolen := 0
	for raw in stack:
		if bool((raw as Dictionary).get("stolen", false)):
			stolen += 1
	line["stolen"] = stolen


func _thesis_ids(line: Dictionary) -> Array:
	var ids: Array = []
	for raw in line.get("thesis_stack", []):
		ids.append(String((raw as Dictionary).get("thesis_id", "")))
	return ids


func _put_thesis(line: Dictionary, card: Dictionary = {}) -> Dictionary:
	var stack := _ensure_thesis_stack(line)
	var token := _thesis_token(card)
	stack.append(token)
	line["thesis_stack"] = stack
	_sync_thesis_scalars(line)
	return token


## Случайная карта заданного типа из стопки (добор/сброс), с изъятием. {} — подходящих нет.
func _take_random_of_type(pile: Array, type: String) -> Dictionary:
	var idx: Array = []
	for i in pile.size():
		if String((pile[i] as Dictionary).get("type", "")) == type:
			idx.append(i)
	if idx.is_empty():
		return {}
	var pick: int = idx[randi() % idx.size()]
	var card: Dictionary = pile[pick]
	pile.remove_at(pick)
	return card


## Экономика открытия рамки: первый тезис — не ленивый filler, а случайная настоящая
## карта. Источник по приоритету: свой добор → свой сброс (Тезисов в доборе не осталось) →
## filler (крайний случай — ни одного Тезиса не осталось нигде, весь пул уже на досках).
## Раздачу руки не трогает: это отдельный от руки источник, добор идёт после как обычно.
func _seed_frame_thesis(side: String, line: Dictionary) -> void:
	var s: Dictionary = sides[side]
	var card := _take_random_of_type(s.draw, TYPE_TEZIS)
	if card.is_empty():
		card = _take_random_of_type(s.discard, TYPE_TEZIS)
	var stack: Array = line.get("thesis_stack", [])
	stack.append(_thesis_token(card))
	line["thesis_stack"] = stack
	_sync_thesis_scalars(line)


func _take_top_thesis(line: Dictionary) -> Dictionary:
	var stack := _ensure_thesis_stack(line)
	if stack.is_empty():
		return {}
	var token: Dictionary = stack.pop_back()
	line["thesis_stack"] = stack
	_sync_thesis_scalars(line)
	return token


func _take_thesis_object(line: Dictionary, thesis_id: String) -> Dictionary:
	var stack := _ensure_thesis_stack(line)
	if thesis_id == "":
		return {}
	for i in stack.size():
		var token: Dictionary = stack[i]
		if String(token.get("thesis_id", "")) == thesis_id:
			stack.remove_at(i)
			line["thesis_stack"] = stack
			_sync_thesis_scalars(line)
			return token
	return {}


## Сила рамки = тезисы; при включённом укреплении краденые считаются вдвое (lекарство 3).
## Когда укрепление выкл — stolen чисто визуальный (золотая карта), на силу не влияет.
func line_strength(line: Dictionary) -> int:
	var s := int(line.theses)
	if fortify_threshold > 0:
		s += int(line.get("stolen", 0))
	return s


## Украденный объект тезиса кладётся в АКТИВНУЮ установку вора (мгновенный +1 на доску).
## Если рамок нет — в колоду добора (страховка). Карта сохраняет thesis_id: кража
## переносит объект, а не создаёт безымянную единицу силы.
func _give_stolen(attacker: String, info: Dictionary, card: Dictionary = {}) -> void:
	var stolen_card := _thesis_token(card)
	stolen_card["stolen"] = true
	var al: Array = sides[attacker].lines
	if al.size() > 0:
		_put_thesis(al[-1], stolen_card)
	else:
		sides[attacker].draw.append(stolen_card)
	info["stolen"] = true
	info["stolen_thesis_id"] = String(stolen_card.get("thesis_id", ""))


func is_fortified(line: Dictionary) -> bool:
	return fortify_threshold > 0 and line_strength(line) >= fortify_threshold


## Public crowd pressure on a frame owner. Positive means the audience currently
## favours that owner and therefore wants to see the favourite challenged.
func audience_favor_for(owner: String) -> int:
	return zal() if owner == SIDE_YOU else -zal()


## Maximum frame thickness an ordinary direct Theft can capture from this owner.
## One-thesis frames are always in reach. With the default public band 2..4 every
## further point of audience favour opens one further thickness: 2->2, 3->3, 4+->4.
## Heat, emotion strain and board score deliberately do not alter this public number.
func frame_capture_reach(owner: String) -> int:
	if capture_mode == 0:
		return 0
	var reach := 1
	if gate_x <= 0:
		return reach
	var band_end := maxi(gate_x, gate_y)
	var owner_favor := maxi(0, audience_favor_for(owner))
	return reach + clampi(owner_favor - gate_x + 1, 0, band_end - gate_x + 1)


## Compatibility API for callers that reason from the raider's side.
func capture_threshold(attacker: String) -> int:
	return frame_capture_reach(other(attacker))


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
func _capture_frame(attacker: String, defender: String, idx: int,
		info: Dictionary) -> Dictionary:
	var dl: Array = sides[defender].lines
	if idx < 0 or idx >= dl.size():
		return {}
	var captured: Dictionary = dl[idx]
	info["captured_frame_id"] = _ensure_frame_id(captured)
	var captured_stack := _ensure_thesis_stack(captured)
	dl.remove_at(idx)
	if capture_loot == 1:
		# «Переманил вместе с аргументами»: рамка переходит со всеми стоящими тезисами
		# (мин. 1 — добытый) — вся её сила в глазах зала теперь твоя.
		if captured_stack.is_empty():
			captured_stack.append(_thesis_token())
	else:
		# Голый трофей: один конкретный опорный тезис переходит с рамкой, остальные
		# реальные объекты карт уходят в сброс прежнего владельца.
		while captured_stack.size() > 1:
			_discard(defender, captured_stack.pop_back())
		if captured_stack.is_empty():
			captured_stack.append(_thesis_token())
	for raw in captured_stack:
		var token: Dictionary = raw
		token["stolen"] = true
		token.erase("statement")
	var captured_ids: Array = []
	for raw in captured_stack:
		captured_ids.append(String((raw as Dictionary).get("thesis_id", "")))
	captured["thesis_stack"] = captured_stack
	_sync_thesis_scalars(captured)
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
		al.append(captured)
	else:
		captured.closed = true
		# Active frame is always lines[-1]. A closed trophy must not steal that slot:
		# insert it immediately before the current active frame.
		if al.is_empty():
			captured.closed = false
			al.append(captured)
		else:
			al.insert(al.size() - 1, captured)
	info["captured"] = true
	info["captured_thesis_ids"] = captured_ids
	info["captured_thickness"] = captured_stack.size()
	info["removed"] = true
	_snapshot_last_frame_loss(defender, info)
	return captured


## Снимок делается в момент падения последней рамки — до любого добора. Рамка в руке
## спасает от KO, но помечается для обязательного восстановления целым следующим ходом.
func _snapshot_last_frame_loss(side: String, info: Dictionary) -> void:
	if not sides[side].lines.is_empty():
		return
	info["last_frame_lost"] = true
	var ready := 0
	for card in sides[side].hand:
		if String(card.get("type", "")) == TYPE_USTANOVKA:
			ready += 1
	info["recovery_available"] = ready
	if not board_ko_enabled:
		return
	if ready <= 0:
		info["knockout"] = true
		_finish(other(side), "knockout")
		return
	for card in sides[side].hand:
		if String(card.get("type", "")) == TYPE_USTANOVKA:
			card["recovery_ready"] = true
	sides[side]["recovery_pending"] = true
	info["recovery_pending"] = true


## Сумма силы рамок стороны (для «блеска» / крена зала).
func shine(side: String) -> int:
	var total := 0
	for ln in sides[side].lines:
		total += line_strength(ln)
	return total


## Зал — производная стрелка: крен по числу установок И их силе (тезисам) + смещение
## zal_bias (стартовый крен забега / цена грязных приёмов). Плюс — в сторону игрока.
func zal() -> int:
	if external_zal_enabled:
		return clampi(external_zal + zal_bias, -external_zal_cap, external_zal_cap)
	var you_w := score(SIDE_YOU) + shine(SIDE_YOU)
	var opp_w := score(SIDE_OPP) + shine(SIDE_OPP)
	return clampi(you_w - opp_w + zal_bias, -ZAL_MAX, ZAL_MAX)


func set_external_zal(value: int, enabled: bool = true, cap: int = ZAL_MAX) -> void:
	external_zal_cap = clampi(cap, 1, ZAL_MAX)
	external_zal = clampi(value, -external_zal_cap, external_zal_cap)
	external_zal_enabled = enabled


func clear_external_zal() -> void:
	external_zal = 0
	external_zal_cap = ZAL_MAX
	external_zal_enabled = false


func legal_types(side: String) -> Array:
	var s: Dictionary = sides[side]
	var out: Array = []
	if bool(s.get("recovery_pending", false)):
		if not recovery_indices(side).is_empty():
			out.append(TYPE_USTANOVKA)
		return out
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
##   "reframe"  — последняя рамка потеряна, резерв в руке ждёт выбора (весь ход)
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
	# Нокаут уже решён снимком в момент потери рамки; здесь — обязательный ход восстановления.
	if s.lines.is_empty():
		if bool(s.get("recovery_pending", false)) and not recovery_indices(side).is_empty():
			s.passed = false
			return "reframe"
		if board_ko_enabled:
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
	if s.hand.is_empty() or (not board_ko_enabled and legal_types(side).is_empty()):
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
	if game_over or not type in legal_types(side):
		return {}
	if hand_index >= 0:
		var selected: Array = sides[side].hand
		if hand_index >= selected.size() or String(selected[hand_index].get("type", "")) != type:
			return {}
	var info := {"side": side, "type": type, "name": "", "removed": false,
		"action_id": _next_action_id(), "play_id": _next_play_id()}
	var s: Dictionary = sides[side]
	match type:
		TYPE_TEZIS:
			var c := _remove_selected_card(side, TYPE_TEZIS, hand_index)
			info.name = c.get("name", "")
			var thesis_frame: Dictionary = s.lines[-1]
			var token := _put_thesis(thesis_frame, c)
			info["thesis_id"] = String(token.get("thesis_id", ""))
			info["frame_id"] = _ensure_frame_id(thesis_frame)
			combo_register.record_thesis_origin(String(info.action_id), String(info.play_id),
				side, String(info.frame_id), String(info.thesis_id))
		TYPE_USTANOVKA:
			var c := _remove_selected_card(side, TYPE_USTANOVKA, hand_index)
			info.name = c.get("name", "")
			if not s.lines.is_empty():
				s.lines[-1].closed = true
			var new_line := {"theses": 1, "closed": false, "name": info.name, "stolen": 0}
			_copy_claim(c, new_line)
			info["frame_id"] = _ensure_frame_id(new_line)
			s.lines.append(new_line)
			_seed_frame_thesis(side, new_line)
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
	_settle_frame_combo_events(info)
	return info


## Разбор без клинча: снять 1 тезис; если карта — Кража, забрать его; упавшую рамку убрать.
## Кража по рамке не толще порога захвата (capture_threshold) забирает её ЦЕЛИКОМ.
func _resolve_single_razbor(attacker: String, defender: String, target: int, info: Dictionary, init_steals: bool) -> void:
	var line: Dictionary = sides[defender].lines[target]
	var will_steal := init_steals and not is_fortified(line)
	if init_steals and not will_steal:
		info["bounced"] = true
	info["target_name"] = line.name
	info["target_frame_id"] = _ensure_frame_id(line)
	# Захват (базовый порог 1 = рамка на последнем тезисе; зал-гейт поднимает до 2/3).
	# braced — именной «Перенос бремени»: рамка временно не захватывается (тезис снять можно).
	if will_steal and int(line.theses) <= capture_threshold(attacker) and not line.get("braced", false):
		info["affected_kind"] = "frame"
		_capture_frame(attacker, defender, target, info)
		return
	var affected := _take_top_thesis(line)
	if affected.is_empty():
		info["affected_kind"] = ""
		return
	info["affected_kind"] = "thesis"
	info["affected_thesis_id"] = String(affected.get("thesis_id", ""))
	var removed_ids: Array = info.get("removed_thesis_ids", [])
	removed_ids.append(String(affected.get("thesis_id", "")))
	info["removed_thesis_ids"] = removed_ids
	if will_steal:
		_give_stolen(attacker, info, affected)
	else:
		_discard(defender, affected)  # сбитый объект тезиса — в сброс владельца
	if int(line.theses) <= 0:
		# Рамка пала (обычным Разбором, либо Кражей при выключенном захвате).
		_discard(defender, {"type": TYPE_USTANOVKA, "name": String(line.get("name", ""))})
		sides[defender].lines.remove_at(target)
		info["removed"] = true
		_snapshot_last_frame_loss(defender, info)


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
		"named": id, "removed": false,
		"action_id": _next_action_id(), "play_id": _next_play_id()}
	match id:
		"gish_gallop":
			_discard(side, card)
			_named_gish(side, target, info)
		"ad_hominem":
			_discard(side, card)
			_named_ad_hominem(side, target, info)
		"strawman":
			_discard(side, card)
			_named_strawman(side, target, info, card)
		"burden_shift":
			var line: Dictionary = s.lines[-1]
			var token := _put_thesis(line, card)
			info["thesis_id"] = String(token.get("thesis_id", ""))
			info["frame_id"] = _ensure_frame_id(line)
			combo_register.record_thesis_origin(String(info.action_id), String(info.play_id),
				side, String(info.frame_id), String(info.thesis_id))
			line.braced = true   # не захватывается до начала хода владельца (begin_turn снимет)
			info["braced"] = true
		"axiom":
			if not s.lines.is_empty():
				s.lines[-1].closed = true
			var axiom_line := {"theses": 2, "closed": false, "name": String(card.name),
				"stolen": 0, "no_defend": true}
			_copy_claim(card, axiom_line)
			info["frame_id"] = _ensure_frame_id(axiom_line)
			s.lines.append(axiom_line)
			_seed_frame_thesis(side, axiom_line)
			_seed_frame_thesis(side, axiom_line)
		_:
			pass
	_refill(s)
	turn_count += 1
	_settle_frame_combo_events(info)
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
		var removed_ids: Array = info.get("removed_thesis_ids", [])
		removed_ids.append_array(sub.get("removed_thesis_ids", []))
		info["removed_thesis_ids"] = removed_ids
		if String(sub.get("affected_thesis_id", "")) != "":
			info["affected_thesis_id"] = String(sub.affected_thesis_id)
			info["affected_kind"] = "thesis"
		if sub.get("removed", false):
			info["removed"] = true
		if info.get("target_name", "") == "":
			info["target_name"] = sub.get("target_name", "")


## Ad hominem: снимает 2 тезиса с рамки (пала после первого — второй удар пропал).
## Публичная цена возвращается относительным audience_conduct: векторный зал применит её
## через AudienceCore вместе со всей сценой; legacy по-прежнему хранит цену в zal_bias.
func _named_ad_hominem(attacker: String, target: int, info: Dictionary) -> void:
	var opp := other(attacker)
	var lines: Array = sides[opp].lines
	if target < 0 or target >= lines.size():
		target = lines.size() - 1
	_named_chip(opp, target, info)
	if not info.get("removed", false):
		_named_chip(opp, target, info)
	info["audience_conduct"] = -1
	if not external_zal_enabled:
		zal_bias += -1 if attacker == SIDE_YOU else 1
	info["dirty"] = true


## Соломенное чучело: Кража с порогом захвата +1 («длинная рука»), добыча приходит с −1
## тезисом (мин. 1). Вне досягаемости — обычная кража тезиса (ванильный резолв).
func _named_strawman(attacker: String, target: int, info: Dictionary,
		card: Dictionary) -> void:
	var opp := other(attacker)
	var lines: Array = sides[opp].lines
	if target < 0 or target >= lines.size():
		target = lines.size() - 1
	var line: Dictionary = lines[target]
	var capture_bonus := maxi(0, int(card.get("capture_bonus", 0)))
	if capture_mode > 0 and not is_fortified(line) and not line.get("braced", false) \
			and int(line.theses) <= capture_threshold(attacker) + capture_bonus:
		info["target_name"] = line.name
		var cap: Dictionary = _capture_frame(attacker, opp, target, info)
		var trim := maxi(0, int(card.get("capture_trim", 0)))
		while trim > 0 and int(cap.theses) > 1:
			var trimmed := _take_top_thesis(cap)
			_discard(opp, trimmed)
			trim -= 1
		info["captured_thesis_ids"] = _thesis_ids(cap)
		info["captured_thickness"] = int(cap.theses)
		info["strawman"] = true
		info["capture_bonus"] = capture_bonus
	else:
		_resolve_single_razbor(attacker, opp, target, info, true)


## Один именной удар-«чип»: −1 тезис рамки владельца, сбитое — в его сброс, павшая рамка
## снимается. Без кражи и без захвата (это механики Кражи, не потока).
func _named_chip(owner: String, idx: int, info: Dictionary) -> void:
	var lines: Array = sides[owner].lines
	if idx < 0 or idx >= lines.size():
		return
	var line: Dictionary = lines[idx]
	var affected := _take_top_thesis(line)
	if affected.is_empty():
		return
	_discard(owner, affected)
	info["affected_kind"] = "thesis"
	info["affected_thesis_id"] = String(affected.get("thesis_id", ""))
	var removed_ids: Array = info.get("removed_thesis_ids", [])
	removed_ids.append(String(affected.get("thesis_id", "")))
	info["removed_thesis_ids"] = removed_ids
	info["target_name"] = line.name
	if int(line.theses) <= 0:
		_discard(owner, {"type": TYPE_USTANOVKA, "name": String(line.get("name", ""))})
		lines.remove_at(idx)
		info["removed"] = true
		_snapshot_last_frame_loss(owner, info)


## Применяет ОДИН точный объект атаки к его точной цели. Полный клинч вызывает этот
## примитив сверху вниз: press снимает адресный защитный T, после чего освобождённая
## атака под ним тоже может разрешиться. Так K→T→R сначала снимает T объектом R,
## затем исходный объект K снова получает доступ к рамке.
func clinch_finalize(attacker: String, defender: String, line_index: int, t_added: int,
		r_count: int, info: Dictionary, landing_attack: Dictionary = {}) -> void:
	if line_index < 0 or line_index >= sides[defender].lines.size():
		return
	var line: Dictionary = sides[defender].lines[line_index]
	_ensure_thesis_stack(line)
	info["clinch_t"] = t_added
	info["clinch_r"] = r_count
	info["target_name"] = line.name
	var protected_thickness := int(info.get("protected_thickness", int(line.theses)))
	var capture_reach := int(info.get("capture_reach", frame_capture_reach(defender)))
	var opening_thickness := int(info.get("opening_thickness",
		maxi(0, protected_thickness - t_added)))
	var capture_fortified := is_fortified(line)
	var attack_landed := r_count > t_added
	var landing_card: Dictionary = landing_attack.duplicate(true)
	if attack_landed and landing_card.is_empty():
		landing_card = {"type": TYPE_RAZBOR, "name": "Разбор", "steals": false}
	var landing_steals := attack_landed and bool(landing_card.get("steals", false))
	var landing_target_kind := String(info.get("landing_target_kind",
		"frame" if t_added == 0 else "thesis"))
	var landing_target_card: Dictionary = info.get("landing_target_card", {})
	var capture_attempted := landing_steals and landing_target_kind == "frame" \
		and capture_reach > 0
	info["opening_thickness"] = opening_thickness
	info["protected_thickness"] = protected_thickness
	info["pre_effect_thickness"] = protected_thickness
	info["capture_reach"] = capture_reach
	info["capture_audience_favor"] = int(info.get("capture_audience_favor",
		audience_favor_for(defender)))
	info["landing_attack_name"] = String(landing_card.get("name", ""))
	info["landing_attack_steals"] = landing_steals
	info["landing_target_kind"] = landing_target_kind if attack_landed else ""
	info["landing_aim_kind"] = landing_target_kind if attack_landed else ""
	info["capture_attempted"] = capture_attempted
	info["removed_thesis_ids"] = info.get("removed_thesis_ids", [])
	info["removed_thesis_steps"] = info.get("removed_thesis_steps", [])
	if not attack_landed:
		info["final_thickness"] = int(line.theses)
		return
	# Полный трофей проверяет только объект Кражи, который сам целится в рамку. Ответный T
	# блокирует его лишь пока остаётся в стеке: press имеет отдельную цель-T, а после её
	# снятия unwind отдельно вызывает этот opener уже по исходной рамке.
	if capture_attempted and protected_thickness <= capture_reach \
			and not line.get("braced", false) and not capture_fortified:
		info["full_capture"] = true
		info["landing_effect"] = "capture"
		info["affected_kind"] = "frame"
		info["damage_count"] = int(line.theses)
		_capture_frame(attacker, defender, line_index, info)
		info["final_thickness"] = 0
		return
	# Укрепление принадлежит рамке, поэтому оно может отбить только Кражу, направленную
	# в рамку. Press-K, направленная в конкретный ответный T, крадёт этот T как обычно.
	var theft_hits_fortification := landing_steals and landing_target_kind == "frame" \
		and capture_fortified
	var steal_thesis := landing_steals and not theft_hits_fortification
	if landing_steals:
		if theft_hits_fortification:
			info["bounced"] = true
			if capture_attempted:
				info["capture_blocked"] = true
				info["capture_block_reason"] = "fortified"
		elif capture_attempted and line.get("braced", false):
			info["capture_blocked"] = true
			info["capture_block_reason"] = "braced"
		elif capture_attempted and protected_thickness > capture_reach:
			info["capture_blocked"] = true
			info["capture_block_reason"] = "out_of_reach"
	var affected: Dictionary
	if landing_target_kind == "thesis":
		affected = _take_thesis_object(line, String(landing_target_card.get("thesis_id", "")))
	else:
		affected = _take_top_thesis(line)
	# Объект уже исчез — эффект не перескакивает на соседний тезис. Это защитный инвариант
	# для будущих именных карт и отложенных эффектов.
	if affected.is_empty():
		info["landing_effect"] = "no_target"
		info["affected_kind"] = ""
		info["damage_count"] = 0
		info["final_thickness"] = int(line.theses)
		return
	var affected_id := String(affected.get("thesis_id", ""))
	info["affected_kind"] = "thesis"
	info["affected_thesis_id"] = affected_id
	info["damage_count"] = 1
	(info["removed_thesis_ids"] as Array).append(affected_id)
	var target_step := int(info.get("landing_target_step", -1))
	if target_step >= 0:
		(info["removed_thesis_steps"] as Array).append(target_step)
	if steal_thesis:
		_give_stolen(attacker, info, affected)
		info["stolen_count"] = 1
		info["landing_effect"] = "steal_thesis"
	else:
		_discard(defender, affected)
		info["stolen_count"] = 0
		info["landing_effect"] = "breakdown"
	if int(line.theses) <= 0:
		_discard(defender, {"type": TYPE_USTANOVKA, "name": String(line.get("name", ""))})
		sides[defender].lines.remove_at(line_index)
		info["removed"] = true
		_snapshot_last_frame_loss(defender, info)
		info["final_thickness"] = 0
	else:
		info["final_thickness"] = int(line.theses)
	# иначе защитник перестоял — его тезисы уже на рамке, остаются (усиление).


# --- Клинч как явный СТЕЙТ (синхронный автомат; волю ведёт драйвер: контроллер/ai) ---
## Пусто = нет клинча. Активный: {attacker, defender, idx, t_added, r_count,
## init_steals, sequence, phase}. sequence хранит полные объекты карт и их точные связи;
## при победе атаки стек разворачивается сверху вниз. phase: "await_defend" | "await_attack".
## Заменяет корутинный клинч UI: переходы синхронны, async/пейсинг — забота драйвера.
var clinch := {}


## Единая объектная легальность карты в ралли. Именной clinch=true означает только
## «может ОТКРЫТЬ клинч»; пока у карты нет собственного on_defend/on_press, превращать
## её в безымянный ответ нельзя — иначе написанный на объекте твист молча потеряется.
func clinch_card_legal(card: Dictionary, phase: String = "") -> bool:
	var active_phase := phase if phase != "" else String(clinch.get("phase", ""))
	var type := String(card.get("type", ""))
	var named_id := String(card.get("named", ""))
	match active_phase:
		"open":
			return type == TYPE_RAZBOR and \
				(named_id == "" or bool(card.get("clinch", false)))
		"await_defend":
			return type == TYPE_TEZIS and named_id == ""
		"await_attack":
			return type == TYPE_RAZBOR and named_id == ""
	return false


func clinch_legal_indices(side: String, phase: String = "") -> Array:
	var out: Array = []
	if not sides.has(side):
		return out
	for i in sides[side].hand.size():
		if clinch_card_legal(sides[side].hand[i], phase):
			out.append(i)
	return out


func clinch_legal_count(side: String, phase: String = "") -> int:
	return clinch_legal_indices(side, phase).size()


func _take_clinch_card(side: String, phase: String, prefer_steal: bool,
		hand_index: int = -1) -> Dictionary:
	var hand: Array = sides[side].hand
	if hand_index >= 0:
		if hand_index >= hand.size() or not clinch_card_legal(hand[hand_index], phase):
			return {}
		var selected: Dictionary = hand[hand_index]
		hand.remove_at(hand_index)
		return selected
	# Сначала точная steals-природа и ваниль, затем другая ваниль; opener-only named
	# (сейчас Socratic) — лишь последний допустимый fallback.
	for allow_named in [false, true]:
		for exact_steal in [true, false]:
			for i in hand.size():
				var candidate: Dictionary = hand[i]
				if not clinch_card_legal(candidate, phase) or \
						candidate.has("named") != allow_named:
					continue
				if exact_steal and bool(candidate.get("steals", false)) != prefer_steal:
					continue
				hand.remove_at(i)
				return candidate
	return {}


## Начать клинч: attacker бьёт рамку defender[idx]. Снимает первый удар, ставит стейт.
## hand_index >= 0 — клинч ИМЕННО этой картой руки (именные приёмы, напр. Сократический
## вопрос); иначе карта берётся слепо по prefer_steal (ваниль — как раньше).
## Возвращает {card, is_callback} для стартовой реплики (наррацию делает драйвер). {} если цель invalid.
func begin_clinch(attacker: String, defender: String, idx: int, prefer_steal: bool, hand_index: int = -1) -> Dictionary:
	var lines: Array = sides[defender].lines
	if idx < 0 or idx >= lines.size():
		return {}
	var initc := _take_clinch_card(attacker, "open", prefer_steal, hand_index)
	if initc.is_empty():
		return {}
	# R0: клинч — один полный action; его action_id — будущий scope id регистра. frame_id
	# цели фиксируется здесь же: индекс idx может сместиться, сам объект рамки — нет.
	var action_id := _next_action_id()
	var frame_id := _ensure_frame_id(lines[idx])
	var init_steals: bool = initc.get("steals", false)
	var capture_reach := frame_capture_reach(defender)
	var capture_audience_favor := audience_favor_for(defender)
	var opening_thickness := int(lines[idx].theses)
	var opening_capture_eligible: bool = init_steals and capture_reach > 0 \
		and opening_thickness <= capture_reach and not lines[idx].get("braced", false) \
		and not is_fortified(lines[idx])
	if initc.has("named"):
		named_played[attacker] = int(named_played.get(attacker, 0)) + 1
	_discard(attacker, initc)
	turn_count += 1
	# Комбо-грамматика (§2 combo_grammar_v0.2): opening_anchor — снапшот EXACT верхнего
	# Тезиса рамки в момент объявления. Matcher не перепрыгивает через неeligible объект
	# (техническую Базу) к схеме ниже. Пока чистая телеметрия — механику клинча не меняет.
	var opening_anchor := {}
	var opening_stack := _ensure_thesis_stack(lines[idx])
	if not opening_stack.is_empty():
		var top_thesis: Dictionary = opening_stack[-1]
		if Grammar.eligible(top_thesis):
			opening_anchor = {
				"thesis_id": String(top_thesis.get("thesis_id", "")),
				"scheme": String(top_thesis.get("scheme", "")),
				"suit": String(top_thesis.get("suit", "")),
				"frame_owner": defender, "frame_index": idx, "frame_id": frame_id,
				"hit": Grammar.hit(top_thesis, initc),
				"card": top_thesis.duplicate(true),
			}
	# R0: запись sequence — де-факто PlayFact; actor/role/step/play_id ставятся сразу при
	# play, а не на settlement (settlement лишь дописывает result/effect).
	var opener_play: Dictionary = initc.duplicate(true)
	opener_play["play_id"] = _next_play_id()
	opener_play["actor"] = attacker
	opener_play["role"] = "attack"
	opener_play["step"] = 0
	# R1: опенер физически объявлен на рамку; exact верхний тезис в момент объявления —
	# второе ребро НЕЗАВИСИМО от eligibility (техническая База — тоже факт цели).
	var relations: Array = []
	relations.append(_relation_fact("targets", "play", String(opener_play.play_id),
		"frame", frame_id, action_id))
	if not opening_stack.is_empty():
		relations.append(_relation_fact("targets", "play", String(opener_play.play_id),
			"thesis", String((opening_stack[-1] as Dictionary).get("thesis_id", "")),
			action_id))
	# R2: LINK решает register по Pattern G-01, а не инлайновый matcher; клинч хранит
	# только run_id + проекцию legacy_view (прежний контракт для AI/UI/телеметрии).
	var combo_run_id := combo_register.open_action_run(action_id, frame_id,
		attacker, defender, opening_anchor, opener_play)
	var combo_view: Dictionary = combo_register.legacy_view(combo_run_id)
	clinch = {
		"attacker": attacker, "defender": defender, "idx": idx,
		"action_id": action_id, "frame_id": frame_id,
		"t_added": 0, "r_count": 1,
		"init_steals": init_steals, "phase": "await_defend",
		"capture_reach": capture_reach,
		"capture_audience_favor": capture_audience_favor,
		"opening_thickness": opening_thickness,
		"opening_capture_eligible": opening_capture_eligible,
		"named": String(initc.get("named", "")),
		"sequence": [opener_play],
		"relations": relations,
		"opening_anchor": opening_anchor,
		"opening_hook": Grammar.hook_of(initc),
		"combo_run_id": combo_run_id,
		"combo_route": combo_view.combo_route,
		"combo_state": combo_view.combo_state,
		"combo_owner": combo_view.combo_owner,
		"closer_step": combo_view.closer_step,
		"closer_thesis_id": combo_view.closer_thesis_id,
	}
	return {"card": initc, "is_callback": bool(lines[idx].closed),
		"action_id": action_id, "play_id": String(opener_play.play_id)}


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
	if clinch.is_empty() or side != clinch_pending_side():
		return false
	if clinch.phase == "await_defend":
		var dl: Array = sides[clinch.defender].lines
		var i := int(clinch.idx)
		if i >= 0 and i < dl.size() and dl[i].get("no_defend", false):
			return false
	return clinch_legal_count(side, String(clinch.phase)) > 0


## Решение текущей стороны. "play" продолжает волю, "pass" завершает клинч (finalize).
## Возвращает {event}: "hold" (защитник держит, card=тезис) | "press" (атакующий добил,
## card=карта атаки) | "resolved" (клинч закрыт; info+landed+счётчики).
func clinch_submit(decision: String, prefer_steal: bool = true, hand_index: int = -1,
		stop_reason: String = "voluntary") -> Dictionary:
	if clinch.is_empty():
		return {}
	if decision != "play":
		var stopped_side := clinch_pending_side()
		if not clinch_can_act(clinch_pending_side()):
			stop_reason = "exhausted"
		return _finish_clinch(stop_reason, stopped_side)
	if clinch.phase == "await_defend":
		var line: Dictionary = sides[clinch.defender].lines[clinch.idx]
		var dc := _take_clinch_card(clinch.defender, "await_defend", false, hand_index)
		if dc.is_empty():
			return {"event": "invalid"}
		var token := _put_thesis(line, dc)
		clinch.t_added = int(clinch.t_added) + 1
		var sequence: Array = clinch.get("sequence", [])
		var hold_play: Dictionary = token.duplicate(true)
		hold_play["play_id"] = _next_play_id()
		hold_play["actor"] = String(clinch.defender)
		hold_play["role"] = "defense"
		hold_play["step"] = sequence.size()
		sequence.append(hold_play)
		clinch["sequence"] = sequence
		# R1: ответ парирует exact предыдущий нажим и материализуется в стабильный thesis_id
		# (единственный мост play → тезис; нахождение на рамке трейс не дублирует).
		var relations: Array = clinch.get("relations", [])
		var prev_attack: Dictionary = sequence[int(hold_play.step) - 1]
		var responds_rel := _relation_fact("responds_to", "play", String(hold_play.play_id),
			"play", String(prev_attack.get("play_id", "")), String(clinch.get("action_id", "")))
		var mat_rel := _relation_fact("materializes_as", "play", String(hold_play.play_id),
			"thesis", String(token.get("thesis_id", "")), String(clinch.get("action_id", "")))
		relations.append(responds_rel)
		relations.append(mat_rel)
		clinch["relations"] = relations
		# Комбо §4 через register: вооружает только ответ с ребром на exact опенер (факт-
		# эквивалент прежнего «первый T на открытый LINK»). Owner и closer зафиксированы
		# в run'е; дальнейшие hold/press его не переписывают (реверс — будущий
		# COUNTER_CLAIM, не скрытая автоматика). Клинч получает свежую проекцию.
		combo_register.on_response(String(clinch.get("action_id", "")), hold_play,
			[responds_rel, mat_rel],
			(clinch.get("opening_anchor", {}) as Dictionary).get("card", {}), sequence[0])
		var combo_view: Dictionary = combo_register.legacy_view(
			String(clinch.get("combo_run_id", "")))
		clinch.combo_state = combo_view.combo_state
		clinch.combo_owner = combo_view.combo_owner
		clinch.closer_step = combo_view.closer_step
		clinch.closer_thesis_id = combo_view.closer_thesis_id
		if not clinch_freeze:
			_refill(sides[clinch.defender])
		clinch.phase = "await_attack"
		return {"event": "hold", "card": token, "step": sequence.size() - 1,
			"thesis_id": String(token.get("thesis_id", "")),
			"play_id": String(hold_play.play_id)}
	else:
		var ac := _take_clinch_card(clinch.attacker, "await_attack", prefer_steal, hand_index)
		if ac.is_empty():
			return {"event": "invalid"}
		_discard(clinch.attacker, ac)
		clinch.r_count = int(clinch.r_count) + 1
		var sequence: Array = clinch.get("sequence", [])
		var press_play: Dictionary = ac.duplicate(true)
		press_play["play_id"] = _next_play_id()
		press_play["actor"] = String(clinch.attacker)
		press_play["role"] = "attack"
		press_play["step"] = sequence.size()
		sequence.append(press_play)
		clinch["sequence"] = sequence
		# R1: press целится в exact материализованный тезис предыдущего ответа.
		var relations: Array = clinch.get("relations", [])
		var prev_defense: Dictionary = sequence[int(press_play.step) - 1]
		var press_rel := _relation_fact("targets", "play", String(press_play.play_id),
			"thesis", String(prev_defense.get("thesis_id", "")),
			String(clinch.get("action_id", "")))
		relations.append(press_rel)
		clinch["relations"] = relations
		# R3: RTR-вахты регистра видят press как milestone (закрытие трёхзвенного path).
		combo_register.on_press(String(clinch.get("action_id", "")), press_play, [press_rel])
		if not clinch_freeze:
			_refill(sides[clinch.attacker])
		clinch.phase = "await_defend"
		return {"event": "press", "card": ac, "step": int(press_play.step),
			"play_id": String(press_play.play_id)}


## Закрыть клинч: применить исход (clinch_finalize), очистить стейт, вернуть итог.
func _finish_clinch(stop_reason: String = "voluntary", stopped_side: String = "") -> Dictionary:
	var attacker: String = clinch.attacker
	var defender: String = clinch.defender
	var idx: int = clinch.idx
	var action_id: String = String(clinch.get("action_id", ""))
	var target_frame_id: String = String(clinch.get("frame_id", ""))
	var t_added: int = clinch.t_added
	var r_count: int = clinch.r_count
	var named: String = String(clinch.get("named", ""))
	var combo_run_id: String = String(clinch.get("combo_run_id", ""))
	var opening_anchor: Dictionary = (clinch.get("opening_anchor", {}) as Dictionary) \
		.duplicate(true)
	var sequence: Array = clinch.get("sequence", []).duplicate(true)
	var relations: Array = clinch.get("relations", []).duplicate(true)
	var reach: int = int(clinch.get("capture_reach", 1))
	var capture_audience_favor: int = int(clinch.get("capture_audience_favor", 0))
	var opening_thickness: int = int(clinch.get("opening_thickness", 0))
	var opening_capture_eligible: bool = bool(clinch.get("opening_capture_eligible", false))
	var peak_thickness: int = opening_thickness + t_added
	var latest_attack := -1
	var initially_countered_steps: Array = []
	var initially_countered_theft_steps: Array = []
	for i in sequence.size():
		var step_card: Dictionary = sequence[i]
		step_card["step"] = i
		if String(step_card.get("type", "")) == TYPE_RAZBOR:
			step_card["actor"] = attacker
			step_card["role"] = "attack"
			step_card["result"] = "pending"
			step_card["target_kind"] = "frame" if i == 0 else "thesis"
			step_card["aim_kind"] = String(step_card.target_kind)
			step_card["target_step"] = -1 if i == 0 else i - 1
			latest_attack = i
		else:
			step_card["actor"] = defender
			step_card["role"] = "defense"
			step_card["result"] = "held"
			if latest_attack >= 0:
				step_card["counters"] = latest_attack
				var parried: Dictionary = sequence[latest_attack]
				parried["result"] = "parried"
				parried["countered_by"] = i
				initially_countered_steps.append(latest_attack)
				if bool(parried.get("steals", false)):
					initially_countered_theft_steps.append(latest_attack)
	var attacker_won := r_count > t_added
	var info := {"side": attacker, "type": TYPE_RAZBOR,
		"action_id": action_id, "target_frame_id": target_frame_id,
		"capture_reach": reach, "capture_audience_favor": capture_audience_favor,
		"opening_thickness": opening_thickness,
		"peak_thickness": peak_thickness, "protected_thickness": peak_thickness,
		"landing_step": -1, "landing_target_kind": "", "landing_target_step": -1,
		"initially_countered_steps": initially_countered_steps.duplicate(),
		"initially_countered_theft_steps": initially_countered_theft_steps.duplicate(),
		"parried_steps": ([] if attacker_won else initially_countered_steps.duplicate()),
		"parried_theft_steps": ([] if attacker_won else initially_countered_theft_steps.duplicate()),
		"parried_steals": 0 if attacker_won else initially_countered_theft_steps.size(),
		"opening_capture_eligible": opening_capture_eligible,
		"parried_capture": not attacker_won and opening_capture_eligible and
			initially_countered_theft_steps.has(0),
		"capture_reactivated": attacker_won and opening_capture_eligible and
			initially_countered_theft_steps.has(0),
		"resolved_attack_steps": [], "resolved_effects": [],
		"removed_thesis_ids": [], "removed_thesis_steps": [],
		"stolen_count": 0, "damage_count": 0,
		"stop_reason": stop_reason, "stop_side": stopped_side,
		"exhausted_side": stopped_side if stop_reason == "exhausted" else ""}
	clinch = {}   # очистить ДО finalize, чтобы рендер не считал рамку контестом
	if attacker_won:
		# Стек разворачивается сверху вниз. Каждый press работает только со своим exact T;
		# opener выполняется последним уже по очищенной от защитных T исходной рамке.
		for i in range(sequence.size() - 1, -1, -1):
			var attack_card: Dictionary = sequence[i]
			if String(attack_card.get("type", "")) != TYPE_RAZBOR:
				continue
			var target_step := -1 if i == 0 else i - 1
			var target_kind := "frame" if i == 0 else "thesis"
			var target_card: Dictionary = {} if target_step < 0 else \
				(sequence[target_step] as Dictionary).duplicate(true)
			var current_thickness := opening_thickness
			if idx >= 0 and idx < sides[defender].lines.size():
				current_thickness = int(sides[defender].lines[idx].theses)
			var step_info := {"side": attacker, "type": TYPE_RAZBOR,
				"capture_reach": reach, "capture_audience_favor": capture_audience_favor,
				"opening_thickness": opening_thickness,
				"protected_thickness": current_thickness,
				"landing_step": i, "landing_target_kind": target_kind,
				"landing_target_step": target_step, "landing_target_card": target_card,
				"removed_thesis_ids": [], "removed_thesis_steps": []}
			clinch_finalize(attacker, defender, idx, 0, 1, step_info,
				attack_card.duplicate(true))
			_merge_clinch_effect(info, step_info)
			(info["resolved_attack_steps"] as Array).append(i)
			attack_card["result"] = "captured" if bool(step_info.get("captured", false)) \
				else "landed"
			attack_card["effect"] = String(step_info.get("landing_effect", ""))
			attack_card["affected_kind"] = String(step_info.get("affected_kind", ""))
			attack_card["affected_thesis_id"] = String(step_info.get("affected_thesis_id", ""))
			if target_step >= 0 and String(step_info.get("landing_effect", "")) in \
					["breakdown", "steal_thesis"]:
				sequence[target_step]["result"] = "stolen" if \
					String(step_info.get("landing_effect", "")) == "steal_thesis" else "removed"
	else:
		clinch_finalize(attacker, defender, idx, t_added, r_count, info, {})
	info["clinch_t"] = t_added
	info["clinch_r"] = r_count
	# Именной «Сократический вопрос»: защитник отвечал тезисами → первый защитный тезис
	# уходит атакующему, только если именно этот объект всё ещё лежит на рамке.
	if named == "socratic" and t_added > 0:
		_socratic_trap(attacker, defender, idx, info, sequence)
	# R1: single-assignment outcome (§2.2) — одна нормализованная запись на розыгрыш,
	# строго после полного unwind и именных твистов; дальше не переписывается.
	for raw in sequence:
		var entry: Dictionary = raw
		if entry.has("outcome"):
			continue
		var outcome := {"result": String(entry.get("result", ""))}
		if String(entry.get("role", "")) == "attack":
			outcome["effect"] = String(entry.get("effect", ""))
			match String(entry.get("affected_kind", "")):
				"thesis":
					outcome["affected"] = {"kind": "thesis",
						"id": String(entry.get("affected_thesis_id", ""))}
				"frame":
					outcome["affected"] = {"kind": "frame", "id": target_frame_id}
				_:
					outcome["affected"] = {}
		else:
			outcome["affected"] = {"kind": "thesis", "id": String(entry.get("thesis_id", ""))}
		entry["outcome"] = outcome
	info["relations"] = relations
	# Комбо-settlement (§4) через register: строго ПОСЛЕ полного unwind и именных
	# post-resolve твистов и ДО рефилла. Run терминализируется по claim.confirm рецепта
	# (CONFIRMED = owner победил + exact closer held + его тезис на рамке; сорванная
	# ARMED-ставка — BREAK; незакрытый LINK истекает и не считается). Payoff не
	# применяется до выбора бумагой A0 — поля ниже чистая телеметрия.
	opening_anchor.erase("card")
	info["opening_anchor"] = opening_anchor
	var settle_frame_ids: Array = []
	if idx >= 0 and idx < sides[defender].lines.size():
		settle_frame_ids = _thesis_ids(sides[defender].lines[idx])
	combo_register.settle_action(action_id, attacker_won, sequence, settle_frame_ids)
	var combo_view: Dictionary = combo_register.legacy_view(combo_run_id)
	info["combo_state"] = String(combo_view.combo_state)
	info["combo_route_id"] = String((combo_view.combo_route as Dictionary).get("route_id", ""))
	info["combo_name"] = String((combo_view.combo_route as Dictionary).get("combo_name", ""))
	info["combo_owner"] = String(combo_view.combo_owner)
	info["combo_result"] = String(combo_view.combo_result)
	info["combo_payoff"] = ""
	info["combo_run"] = combo_register.run_view(combo_run_id)
	# R4: после action-settlement тот же boundary проверяет stable board; наружу одним
	# массивом выходят action- и frame-scoped runs, payoff пока всегда пуст.
	_settle_frame_combo_events(info)
	info["resolved_sequence"] = sequence.duplicate(true)
	# Снимок KO/резерва уже сделан внутри резолва; только теперь разрешён добор.
	_refill(sides[attacker])
	_refill(sides[defender])
	return {
		"event": "resolved", "info": info, "landed": attacker_won,
		"attacker": attacker, "defender": defender, "idx": idx,
		"t_added": t_added, "r_count": r_count, "sequence": sequence,
		"stop_reason": stop_reason, "stop_side": stopped_side,
		"exhausted_side": stopped_side if stop_reason == "exhausted" else "",
	}


## Склеивает эффекты одного шага unwind в публичный итог клинча. Поля landing_* всегда
## описывают последний разрешённый шаг; поскольку обход идёт сверху вниз, в конце это
## opener и его исход по рамке. Побочные точные T сохраняются в resolved_effects/IDs.
func _merge_clinch_effect(total: Dictionary, step: Dictionary) -> void:
	for key in ["target_name", "protected_thickness", "pre_effect_thickness",
			"landing_step", "landing_attack_name", "landing_attack_steals",
			"landing_target_kind", "landing_aim_kind", "landing_target_step",
			"landing_target_card", "capture_attempted", "capture_blocked",
			"capture_block_reason", "bounced", "affected_kind", "affected_thesis_id",
			"landing_effect", "final_thickness", "stolen_thesis_id"]:
		if step.has(key):
			total[key] = step[key]
	for flag in ["full_capture", "captured", "stolen", "removed", "last_frame_lost",
			"knockout", "recovery_pending"]:
		if bool(step.get(flag, false)):
			total[flag] = true
	for key in ["captured_thesis_ids", "captured_thickness", "recovery_available"]:
		if step.has(key):
			total[key] = step[key]
	(total["removed_thesis_ids"] as Array).append_array(step.get("removed_thesis_ids", []))
	(total["removed_thesis_steps"] as Array).append_array(step.get("removed_thesis_steps", []))
	total["stolen_count"] = int(total.get("stolen_count", 0)) + int(step.get("stolen_count", 0))
	total["damage_count"] = int(total.get("damage_count", 0)) + int(step.get("damage_count", 0))
	(total["resolved_effects"] as Array).append({
		"step": int(step.get("landing_step", -1)),
		"name": String(step.get("landing_attack_name", "")),
		"steals": bool(step.get("landing_attack_steals", false)),
		"target_kind": String(step.get("landing_target_kind", "")),
		"target_step": int(step.get("landing_target_step", -1)),
		"effect": String(step.get("landing_effect", "")),
		"affected_thesis_id": String(step.get("affected_thesis_id", "")),
	})


func _socratic_trap(attacker: String, defender: String, idx: int, info: Dictionary,
		sequence: Array) -> void:
	var target_step := -1
	for i in sequence.size():
		if String((sequence[i] as Dictionary).get("role", "")) == "defense":
			target_step = i
			break
	info["socratic_target_step"] = target_step
	if target_step < 0 or String((sequence[target_step] as Dictionary).get("result", "")) != "held":
		info["socratic_expired"] = true
		return
	var dl: Array = sides[defender].lines
	if idx < 0 or idx >= dl.size():
		info["socratic_expired"] = true
		return
	var line: Dictionary = dl[idx]
	var target_card: Dictionary = sequence[target_step]
	var stolen_object := _take_thesis_object(line, String(target_card.get("thesis_id", "")))
	if stolen_object.is_empty():
		info["socratic_expired"] = true
		return
	_give_stolen(attacker, info, stolen_object)
	info["socratic"] = true
	info["stolen_count"] = int(info.get("stolen_count", 0)) + 1
	(sequence[target_step] as Dictionary)["result"] = "stolen_by_socratic"
	var removed_ids: Array = info.get("removed_thesis_ids", [])
	removed_ids.append(String(stolen_object.get("thesis_id", "")))
	info["removed_thesis_ids"] = removed_ids
	var removed_steps: Array = info.get("removed_thesis_steps", [])
	removed_steps.append(target_step)
	info["removed_thesis_steps"] = removed_steps
	if int(line.theses) <= 0:
		_discard(defender, {"type": TYPE_USTANOVKA, "name": String(line.get("name", ""))})
		dl.remove_at(idx)
		info["removed"] = true
		_snapshot_last_frame_loss(defender, info)
		info["final_thickness"] = 0
	else:
		info["final_thickness"] = int(line.theses)


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


## Публичная экономика рамок: UI показывает весь резерв в руке, но восстановить можно
## только те U, которые находились там в точный момент потери последней рамки.
func reserve_count(side: String) -> int:
	var count := 0
	for card in sides[side].hand:
		if String(card.get("type", "")) == TYPE_USTANOVKA:
			count += 1
	return count


func recovery_pending(side: String) -> bool:
	return bool(sides[side].get("recovery_pending", false))


func recovery_indices(side: String) -> Array:
	var out: Array = []
	var hand: Array = sides[side].hand
	for i in hand.size():
		if String(hand[i].get("type", "")) == TYPE_USTANOVKA \
				and bool(hand[i].get("recovery_ready", false)):
			out.append(i)
	return out


func play_redeploy(side: String, hand_index: int) -> Dictionary:
	if game_over or not recovery_pending(side) or not hand_index in recovery_indices(side):
		return {}
	var card: Dictionary = sides[side].hand[hand_index]
	# Восстановление нормализует любую U до голой рамки с 1 тезисом: твист именной Аксиомы
	# здесь не срабатывает, потому что это аварийное возвращение в спор, а не обычный розыгрыш.
	sides[side].hand.remove_at(hand_index)
	sides[side]["recovery_pending"] = false
	var line := {"theses": 1, "closed": false, "name": String(card.get("name", "Рамка")),
		"stolen": 0}
	_copy_claim(card, line)
	sides[side].lines.append(line)
	_seed_frame_thesis(side, line)
	for held in sides[side].hand:
		held.erase("recovery_ready")
	_refill(sides[side])
	turn_count += 1
	var info := {"side": side, "type": TYPE_USTANOVKA, "name": String(card.get("name", "")),
		"removed": false, "action_id": _next_action_id(), "play_id": _next_play_id(),
		"frame_id": _ensure_frame_id(line)}
	if card.has("named"):
		info["named_suppressed"] = String(card.named)
	info["redeploy"] = true
	info["recovery_spent"] = true
	_settle_frame_combo_events(info)
	return info


# --- внутреннее ---

func _refill(s: Dictionary) -> void:
	Deck.refill(s, hand_size)
	_try_second_wind(s)


func _copy_claim(card: Dictionary, line: Dictionary) -> void:
	for key in ["claim_id", "claim", "preferred_axes"]:
		if card.has(key):
			line[key] = card[key].duplicate(true) if card[key] is Array or card[key] is Dictionary \
				else card[key]


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
