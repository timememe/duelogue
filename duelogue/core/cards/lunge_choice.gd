extends RefCounted

## DUELOGUE — «ВЫПАД»: сборщик оффера перед срабатыванием комбо
## (context/situational_cards_v0.1.md §3). Чистая функция от снимка клинча и руки защитника:
## какие 2–3 карты руки показать в модалке-выборе и что каждая делает. Механику НЕ трогает —
## возвращает индексы РУКИ; резолв идёт существующими швами clinch_submit (§3.4):
##   answer_index → clinch_submit("play", …)          — обычная защита, GUARD instant_verdict
##   decoy_index  → clinch_submit("lunge_yield", …)   — «получить урон», опенер добивает рамку
##   steal_index  → clinch_submit("lunge_counter", …) — контратака Кражей, комбо на атакующего
##
## Тот же предикат «правильного ответа», что combo_answer_glow / ai.def_answer_index —
## Grammar.answers(opening_anchor.card, sequence[0], card). Один источник, не третья копия.

const Grammar := preload("res://duelogue/core/cards/grammar.gd")
const C := preload("res://duelogue/core/cards/card_types.gd")

const BLANK := {"active": false, "answer_index": -1, "decoy_index": -1,
	"steal_index": -1, "route_name": ""}


## Оффер для стороны, чья рука передана (обычно защитник-игрок). active=false → «Выпада»
## нет, вызывающий идёт обычным путём _ask_clinch. active=true гарантирует ≥2 непустых слота
## из (answer/decoy/steal); route_name — имя маршрута для шапки модалки.
static func offer(clinch: Dictionary, hand: Array) -> Dictionary:
	if clinch.is_empty() or String(clinch.get("combo_state", "")) != "link":
		return BLANK.duplicate()
	if int(clinch.get("t_added", 0)) != 0:
		return BLANK.duplicate()   ## окно — только первый защитный ответ
	var sequence: Array = clinch.get("sequence", [])
	if sequence.is_empty():
		return BLANK.duplicate()
	var anchor_card: Dictionary = (clinch.get("opening_anchor", {}) as Dictionary).get("card", {})
	var opener: Dictionary = sequence[0]

	var answer_index := -1
	var steal_index := -1
	for i in hand.size():
		var card: Dictionary = hand[i]
		if answer_index < 0 and Grammar.answers(anchor_card, opener, card):
			answer_index = i
		elif steal_index < 0 and String(card.get("type", "")) == C.TYPE_RAZBOR \
				and bool(card.get("steals", false)):
			steal_index = i

	## Карта B — случайный ТЕЗИС из руки (обязан быть легальной защитой), никогда не Установка,
	## не совпадает с answer. Детерминированный сид из состояния клинча (§3.7 п.1: не randf в ядре).
	var decoy_index := _pick_decoy(hand, answer_index,
		int(clinch.get("r_count", 0)) + sequence.size())

	var slots := 0
	for idx in [answer_index, decoy_index, steal_index]:
		if idx >= 0:
			slots += 1
	if slots < 2:
		return BLANK.duplicate()

	var route: Dictionary = clinch.get("combo_route", {})
	var route_name := String(route.get("combo_name", route.get("name", "")))
	if route_name == "":
		route_name = String(Grammar.route(anchor_card, opener).get("name", "маршрут"))
	return {
		"active": true,
		"answer_index": answer_index,
		"decoy_index": decoy_index,
		"steal_index": steal_index,
		"route_name": route_name,
	}


static func _pick_decoy(hand: Array, skip_answer: int, seed_value: int) -> int:
	var pool: Array = []
	for i in hand.size():
		if i == skip_answer:
			continue
		if String((hand[i] as Dictionary).get("type", "")) != C.TYPE_TEZIS:
			continue
		pool.append(i)
	if pool.is_empty():
		return -1
	return int(pool[absi(seed_value) % pool.size()])
