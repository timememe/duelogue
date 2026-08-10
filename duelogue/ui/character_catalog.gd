extends Control

## DUELOGUE — КАТАЛОГ ПЕРСОНАЖЕЙ. Read-only просмотрщик настоящих state-map из
## CharacterCore: слева выбирается боец, справа — любое состояние, которое реально может
## показать бой. Не дублирует пути к арту и не заводит параллельную «витринную» базу.

const CharacterCore := preload("res://duelogue/core/characters/character_core.gd")

const COL_TEXT := Color(0.8118, 0.8392, 0.8784)
const COL_DIM := Color(0.5412, 0.5765, 0.6392)
const COL_GOLD := Color(1.0, 0.8235, 0.2902)

@onready var _count_label: Label = %CountLabel
@onready var _character_list: VBoxContainer = %CharacterList
@onready var _preview_panel: PanelContainer = %PreviewPanel
@onready var _portrait: TextureRect = %Portrait
@onready var _name_label: Label = %NameLabel
@onready var _role_label: Label = %RoleLabel
@onready var _status_label: Label = %StatusLabel
@onready var _description_label: Label = %DescriptionLabel
@onready var _source_label: Label = %SourceLabel
@onready var _state_title: Label = %StateTitle
@onready var _state_id_label: Label = %StateIdLabel
@onready var _state_buttons: FlowContainer = %StateButtons

var _entries: Array = []
var _character_buttons: Array[Button] = []
var _state_button_by_id := {}
var _selected_character := 0
var _selected_state := "idle"


func _ready() -> void:
	_entries = CharacterCore.catalog_entries()
	_count_label.text = "%d бойца · %d состояний у каждого" % [
		_entries.size(), CharacterCore.CATALOG_STATE_ORDER.size()]
	_build_character_list()
	_build_state_buttons()
	if not _entries.is_empty():
		_select_character(0)


func _build_character_list() -> void:
	var group := ButtonGroup.new()
	for i in _entries.size():
		var entry: Dictionary = _entries[i]
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_group = group
		btn.custom_minimum_size = Vector2(0, 72)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = "%s\n%s" % [String(entry.name), String(entry.role)]
		btn.tooltip_text = "Открыть state-map: %s" % String(entry.source)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_select_character.bind(i))
		_character_list.add_child(btn)
		_character_buttons.append(btn)


func _build_state_buttons() -> void:
	var group := ButtonGroup.new()
	for state_id in CharacterCore.CATALOG_STATE_ORDER:
		var id := String(state_id)
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_group = group
		btn.custom_minimum_size = Vector2(126, 34)
		btn.text = String(CharacterCore.CATALOG_STATE_LABELS.get(id, id))
		btn.tooltip_text = id
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(_select_state.bind(id))
		_state_buttons.add_child(btn)
		_state_button_by_id[id] = btn


func _select_character(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	_selected_character = index
	for i in _character_buttons.size():
		_character_buttons[i].set_pressed_no_signal(i == index)
	var entry: Dictionary = _entries[index]
	var states: Dictionary = entry.states
	if not states.has(_selected_state):
		_selected_state = "idle"
	_name_label.text = String(entry.name)
	_role_label.text = String(entry.role)
	_status_label.text = String(entry.status)
	_description_label.text = String(entry.description)
	_source_label.text = "ИСТОЧНИК · res://duelogue/%s" % String(entry.source)
	_apply_accent(entry.accent as Color)
	_show_state()


func _select_state(state_id: String) -> void:
	_selected_state = state_id
	_show_state()


func _show_state() -> void:
	if _entries.is_empty():
		return
	var entry: Dictionary = _entries[_selected_character]
	var states: Dictionary = entry.states
	var texture := states.get(_selected_state, states.get("idle")) as Texture2D
	_portrait.texture = texture
	_portrait.flip_h = bool(entry.get("flip_h", false))
	_state_title.text = String(CharacterCore.CATALOG_STATE_LABELS.get(_selected_state, _selected_state))
	_state_id_label.text = "state · %s" % _selected_state
	for id in _state_button_by_id:
		(_state_button_by_id[id] as Button).set_pressed_no_signal(String(id) == _selected_state)


func _apply_accent(accent: Color) -> void:
	_name_label.add_theme_color_override("font_color", accent.lightened(0.22))
	_role_label.add_theme_color_override("font_color", accent.lightened(0.12))
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent.darkened(0.78)
	sb.border_color = accent.darkened(0.2)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	_preview_panel.add_theme_stylebox_override("panel", sb)
