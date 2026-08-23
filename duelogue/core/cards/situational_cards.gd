extends RefCounted

## DUELOGUE — ЭМОЦ. КАРТЫ В РУКЕ (situational_cards_v0.1 §2, второй абзац; §4 п.4 —
## рабочее имя источника).
##
## Отдельная колода-источник на сторону (draw/discard), остров §0.1: не тасуется с
## Deck.build_side, не участвует в её доборе. Реализованная карта кладётся ПРЯМО в
## sides[side].hand и играется тем же путём, что T/Р/У — тег SITUATIONAL_TAG поверх
## настоящего типа (§7.6, рекомендация «а»: тег, не 4-я type-константа), по образцу
## card.get("named","") у именных приёмов. Эта колода про содержание карты ничего не решает
## за rules_core/battle_controller — только отдаёт готовый словарь по draw().
##
## Конечная, без решафла — тот же принцип «кап колоды = таймер» (zal_gdd §7): у каждой
## стороны ограниченное число этих карт за матч, не бесконечный поток.

const SITUATIONAL_TAG := "situational_emotion"
## Не больше одной неразыгранной карты в руке одновременно — держит эффект редким и
## заметным, а не фоновым шумом при каждом стимуле выше порога.
const HOLD_LIMIT := 1

const CARDS := [
	{"name": "На нервах", "type": "T",
		"text": "Да чтоб тебя — {target}? Вот тебе прямым текстом."},
	{"name": "Задело", "type": "T",
		"text": "Нет уж. По «{target}» — отвечу сейчас, пока не остыл."},
	{"name": "Прорвало", "type": "T",
		"text": "Хватит ходить кругами. {target} — вот что я думаю на самом деле."},
	{"name": "Не сдержался", "type": "T",
		"text": "Ладно, честно: {target} меня реально задевает. Вот почему."},
]

var _draw := {}
var _discard := {}
var _rng := RandomNumberGenerator.new()


func start(seed_value: int, sides: Array = ["you", "opp"]) -> void:
	_rng.seed = seed_value
	_draw = {}
	_discard = {}
	for side in sides:
		var pool := CARDS.duplicate(true)
		_shuffle(pool)
		_draw[String(side)] = pool
		_discard[String(side)] = []


## Держит ли рука уже одну неразыгранную эмоц. карту (HOLD_LIMIT). Чистая функция от
## переданной руки — состояние держит сам rules_core (карта живёт в sides[side].hand),
## эта колода не дублирует бухгалтерию «что сейчас в руке».
static func is_holding(hand: Array) -> bool:
	var count := 0
	for card in hand:
		if bool((card as Dictionary).get(SITUATIONAL_TAG, false)):
			count += 1
	return count >= HOLD_LIMIT


## {} если сторона не заведена в start() или пул исчерпан (вызывающий код это допускает —
## конечная колода, срыв без карты — валидный поздний матч). situational_fresh=true — карта
## переживёт как минимум один полный begin_turn стороны, прежде чем начнёт таять
## (rules_core.begin_turn, двухступенчатый сброс — см. комментарий там же).
func draw(side: String, target: String = "") -> Dictionary:
	if not _draw.has(side):
		return {}
	var pile: Array = _draw[side]
	if pile.is_empty():
		return {}
	var def: Dictionary = pile.pop_front()
	(_discard[side] as Array).append(def)
	var t := String(target).strip_edges()
	if t == "":
		t = "эта позиция"
	return {
		"type": String(def.type), "name": String(def.name), "steals": false,
		"combo_eligible": false, SITUATIONAL_TAG: true, "situational_fresh": true,
		"text": String(def.text).replace("{target}", t),
	}


func draw_left(side: String) -> int:
	return (_draw.get(side, []) as Array).size()


func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp
