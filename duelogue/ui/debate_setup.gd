extends Control

## DUELOGUE — ПОДГОТОВКА ОДИНОЧНЫХ ДЕБАТОВ. Собирает первичные вводные матча в одной
## транзакционной форме: до кнопки «Начать» глобальные настройки не меняются, поэтому
## возврат в главное меню честно отменяет черновой выбор.

const CharacterCore := preload("res://duelogue/core/characters/character_core.gd")
const StageCore := preload("res://duelogue/core/stage/stage_core.gd")

@onready var _character_option: OptionButton = %CharacterOption
@onready var _character_portrait: TextureRect = %CharacterPortrait
@onready var _character_description: Label = %CharacterDescription
@onready var _deck_option: OptionButton = %OpponentDeckOption
@onready var _deck_summary: Label = %OpponentDeckSummary
@onready var _stage_option: OptionButton = %StageOption
@onready var _stage_preview: TextureRect = %StagePreview
@onready var _stage_description: Label = %StageDescription
@onready var _theme_option: OptionButton = %ThemeOption
@onready var _theme_topic: Label = %ThemeTopic
@onready var _theme_summary: Label = %ThemeSummary
@onready var _player_deck_summary: Label = %PlayerDeckSummary

var _characters: Array = []
var _decks: Array = []
var _stages: Array = []
var _themes: Array = []

var _character_id := "red_advocate"
var _opponent_deck_id := ""
var _stage_id := "courtroom"
var _theme_id := ""


func _ready() -> void:
	%BackBtn.pressed.connect(_back)
	%StartBtn.pressed.connect(_start_debate)
	_character_option.item_selected.connect(_on_character_selected)
	_deck_option.item_selected.connect(_on_deck_selected)
	_stage_option.item_selected.connect(_on_stage_selected)
	_theme_option.item_selected.connect(_on_theme_selected)

	_characters = CharacterCore.catalog_entries()
	_decks = Profile.list_decks()
	_stages = StageCore.catalog_entries()
	_themes = ThemeLibrary.list_themes()

	_character_id = _fill_option(_character_option, _characters,
		String(Profile.settings.get("opponent_character_id", "red_advocate")))
	_opponent_deck_id = _fill_option(_deck_option, _decks,
		String(Profile.settings.get("opponent_deck_id", Profile.active_deck_id)))
	_stage_id = _fill_option(_stage_option, _stages,
		String(Profile.settings.get("stage_id", "courtroom")))
	_theme_id = _fill_option(_theme_option, _themes, ThemeLibrary.active_theme_id)

	var active_player_deck := Profile.get_deck_entry(Profile.active_deck_id)
	_player_deck_summary.text = "ВАША ОБОЙМА · %s · %s" % [
		String(active_player_deck.get("name", "Колода")), Profile.deck_summary()]
	_refresh_character()
	_refresh_deck()
	_refresh_stage()
	_refresh_theme()


## Заполняет OptionButton и возвращает реально выбранный id. Если сохранённая запись уже
## удалена из каталога, форма мягко выбирает первую доступную.
func _fill_option(option: OptionButton, entries: Array, wanted_id: String) -> String:
	option.clear()
	var selected := 0
	for i in entries.size():
		var entry: Dictionary = entries[i]
		option.add_item(String(entry.get("name", entry.get("id", "Без названия"))))
		option.set_item_metadata(i, String(entry.get("id", "")))
		if String(entry.get("id", "")) == wanted_id:
			selected = i
	if entries.is_empty():
		option.disabled = true
		return ""
	option.select(selected)
	return String(option.get_item_metadata(selected))


func _entry_by_id(entries: Array, id: String) -> Dictionary:
	for raw in entries:
		var entry: Dictionary = raw
		if String(entry.get("id", "")) == id:
			return entry
	return {}


func _on_character_selected(index: int) -> void:
	_character_id = String(_character_option.get_item_metadata(index))
	_refresh_character()


func _on_deck_selected(index: int) -> void:
	_opponent_deck_id = String(_deck_option.get_item_metadata(index))
	_refresh_deck()


func _on_stage_selected(index: int) -> void:
	_stage_id = String(_stage_option.get_item_metadata(index))
	_refresh_stage()


func _on_theme_selected(index: int) -> void:
	_theme_id = String(_theme_option.get_item_metadata(index))
	_refresh_theme()


func _refresh_character() -> void:
	var entry := _entry_by_id(_characters, _character_id)
	var states: Dictionary = entry.get("states", {})
	_character_portrait.texture = states.get("idle") as Texture2D
	_character_portrait.flip_h = bool(entry.get("flip_h", false))
	_character_description.text = "%s\n%s" % [
		String(entry.get("status", "ПЕРСОНАЖ")),
		String(entry.get("description", "Нет описания."))]


func _refresh_deck() -> void:
	var entry := _entry_by_id(_decks, _opponent_deck_id)
	var deck: Dictionary = entry.get("deck", {})
	_deck_summary.text = "%s\n\n%s\n\nСтиль ИИ: %s" % [
		String(entry.get("name", "Колода не найдена")),
		Profile.deck_summary_for(deck),
		String(Profile.settings.get("opp_style", "smart"))]


func _refresh_stage() -> void:
	var entry := _entry_by_id(_stages, _stage_id)
	_stage_preview.texture = entry.get("texture") as Texture2D
	_stage_description.text = String(entry.get("description", "Нет описания."))


func _refresh_theme() -> void:
	var entry := _entry_by_id(_themes, _theme_id)
	var data: Dictionary = entry.get("data", {})
	_theme_topic.text = "«%s»" % String(data.get("topic", "Без темы"))
	_theme_summary.text = "%s\n%s" % [
		ThemeLibrary.theme_summary_for(data),
		"Ваша позиция: contra · позиция оппонента: pro"]


func _start_debate() -> void:
	if _character_id == "" or _opponent_deck_id == "" or _stage_id == "" or _theme_id == "":
		return
	Profile.set_settings({
		"opponent_character_id": _character_id,
		"opponent_deck_id": _opponent_deck_id,
		"stage_id": _stage_id,
	})
	ThemeLibrary.set_active_theme(_theme_id)
	get_tree().change_scene_to_file("res://duelogue/ui/debate_screen.tscn")


func _back() -> void:
	get_tree().change_scene_to_file("res://duelogue/ui/main_menu.tscn")
