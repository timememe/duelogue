extends Node

## DUELOGUE — ПРОФИЛЬ ИГРОКА (autoload "Profile"): обойма + настройки презентации/боя.
## Единственный владелец сейва user://profile.json. Редактор колоды (deck_editor) ПИШЕТ
## сюда, битва (battle_controller) ЧИТАЕТ отсюда состав стороны игрока. Настройки
## применяются к статикам ReadingPace при загрузке и при каждом set_setting.
##
## Обойма (deck): счётчики базовых типов + список id именных приёмов (по 1 копии, §10.2);
## каждый именной ЗАМЕЩАЕТ ванильную карту своей базы ВНУТРИ счётчиков (named_cards.inject) —
## размер обоймы задают только счётчики. r — ВСЕ карты атаки, steals из них Кражи
## (контракт Deck.build_side, как DECK_R/STEAL_CARDS боя).

const NamedCards := preload("res://duelogue/core/cards/named_cards.gd")
const ReadingPace := preload("res://duelogue/core/narrative/reading_pace.gd")

const SAVE_PATH := "user://profile.json"

## Канон-обойма (= константы боя, GDD v0.3.2): У3 Т8 Р9 (из них 2 Кражи), без именных.
const CLASSIC := {"u": 3, "t": 8, "r": 9, "steals": 2, "named": []}
const OPP_STYLES := ["smart", "balanced", "aggro", "tall", "wide"]

var deck := {}
var settings := {
	"opp_style": "smart", "chars_per_sec": 30.0, "cutscenes": true,
	"outcome_profile": "vector_conduct", "outcome_contract_version": 2,
}


func _ready() -> void:
	deck = classic()
	load_profile()
	_apply_presentation()


func classic() -> Dictionary:
	return CLASSIC.duplicate(true)


func deck_total() -> int:
	return int(deck.get("u", 0)) + int(deck.get("t", 0)) + int(deck.get("r", 0))


## Короткая сводка обоймы (меню/редактор): «У3 Т8 Р7+К2 · именных 2 · всего 20».
func deck_summary() -> String:
	var named_n := (deck.get("named", []) as Array).size()
	return "У%d Т%d Р%d+К%d · именных %d · всего %d" % [
		int(deck.u), int(deck.t), int(deck.r) - int(deck.steals), int(deck.steals),
		named_n, deck_total()]


func set_deck(d: Dictionary) -> void:
	deck = d.duplicate(true)
	save_profile()


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	_apply_presentation()
	save_profile()


# --- сейв ---

func save_profile() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"deck": deck, "settings": settings}, "\t"))
	f.close()


func load_profile() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not data is Dictionary:
		return
	var d: Dictionary = data
	if d.get("deck") is Dictionary:
		# Merge поверх классики: новые поля обоймы получают дефолт, старые сейвы живут.
		var loaded: Dictionary = d.deck
		deck = classic()
		for k in loaded:
			deck[k] = loaded[k]
	if d.get("settings") is Dictionary:
		var ls: Dictionary = d.settings
		var old_contract := int(ls.get("outcome_contract_version", 0)) < 2
		for k in ls:
			settings[k] = ls[k]
		# Одноразово переводим только прежний дефолт. После этой отметки пользователь может
		# вручную выбрать vector_reaction — следующий запуск уже не переопределит его выбор.
		if old_contract:
			if String(settings.get("outcome_profile", "")) == "vector_reaction":
				settings["outcome_profile"] = "vector_conduct"
			settings["outcome_contract_version"] = 2
			save_profile()


## Настройки презентации — в статики ReadingPace (единые часы сцен и пейсинга).
func _apply_presentation() -> void:
	ReadingPace.CHARS_PER_SEC = clampf(float(settings.get("chars_per_sec", 30.0)),
		ReadingPace.MIN_CHARS_PER_SEC, ReadingPace.MAX_CHARS_PER_SEC)
	ReadingPace.CUTSCENES = bool(settings.get("cutscenes", true))
