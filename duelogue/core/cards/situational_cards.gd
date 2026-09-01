extends RefCounted

## DUELOGUE — ЭМОЦ. КАРТЫ В РУКЕ (situational_cards_v0.1 §2, второй абзац; §4 п.4 —
## рабочее имя источника).
##
## Это НЕ отдельный источник контента/рандома. EmotionCore.draw_situational() изымает
## определение из той же конечной колоды, что питает неконтролируемые реакции, а этот файл
## лишь превращает его в обычный объект руки с тегом поверх настоящего типа T. Поэтому
## сарказм, взятый в руку, уже не сможет позже выпасть как автоматический срыв в том же матче.

const SITUATIONAL_TAG := "situational_emotion"
## Небольшой гарантированный импульс при осознанном розыгрыше. Общий коэффициент боевого
## эмоционального урона применяет battle_controller, поэтому здесь хранится базовое число.
const BASE_EMOTION_DAMAGE := 1
## В затяжном клинче карта может материализоваться раньше общей hot-границы 4: локальный
## обмен уже сам создаёт достаточную ситуацию, но тяжёлые реакции всё равно фильтруются их
## min_strain внутри EmotionCore.
const CLINCH_TRIGGER_STRAIN := 2
## Не больше одной неразыгранной карты в руке одновременно — держит эффект редким и
## заметным, а не фоновым шумом при каждом стимуле выше порога.
const HOLD_LIMIT := 1

## Держит ли рука уже одну неразыгранную эмоц. карту (HOLD_LIMIT). Чистая функция от
## переданной руки — состояние держит сам rules_core (карта живёт в sides[side].hand),
## эта колода не дублирует бухгалтерию «что сейчас в руке».
static func is_holding(hand: Array) -> bool:
	var count := 0
	for card in hand:
		if bool((card as Dictionary).get(SITUATIONAL_TAG, false)):
			count += 1
	return count >= HOLD_LIMIT

## Адаптирует уже реализованную EmotionCore запись в карту руки. Пустой source означает,
## что единый реакционный пул исчерпан либо на текущем накале нет тематически допустимой
## карты. situational_fresh сохраняет прежний двухходовый контракт распада в RulesCore.
static func make_card(source: Dictionary) -> Dictionary:
	if source.is_empty():
		return {}
	return {
		"type": "T", "name": String(source.get("title", "Эмоциональная реакция")),
		"steals": false,
		"combo_eligible": false, SITUATIONAL_TAG: true, "situational_fresh": true,
		"emotion_damage": int(source.get("emotion_damage", BASE_EMOTION_DAMAGE)),
		"text": String(source.get("text", "")),
		"mood": String(source.get("mood", "burst")),
		"reaction_id": String(source.get("id", "")),
	}
