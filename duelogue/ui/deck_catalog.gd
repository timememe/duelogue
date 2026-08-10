extends Control

## DUELOGUE — КАТАЛОГ КОЛОД: список сохранённых обойм (Profile.decks). Управляет СПИСКОМ —
## имя, какая активна (идёт в катку/сезон — battle_controller читает Profile.deck), добавить/
## удалить запись; СОСТАВ конкретной обоймы правит ui/deck_editor (открывается отсюда с
## Profile.editing_deck_id). Ряды строятся кодом (число колод динамическое), сама панель —
## в deck_catalog.tscn.
##
## Удаление вооружается в два клика (без ConfirmationDialog — в проекте нет прецедента
## модалок): первый клик красит кнопку и взводит confirm-flag на DELETE_ARM_SEC, второй,
## пока флаг ещё жив, удаляет запись. Каталог не даёт удалить последнюю колоду (Profile
## сам это гарантирует) — кнопка неактивна, когда запись единственная.

const DELETE_ARM_SEC := 3.0

const COL_DIM := Color(0.5412, 0.5765, 0.6392)
const COL_GOOD := Color(0.44, 0.81, 0.5)
const COL_WARN := Color(0.85, 0.35, 0.3)

@onready var _list: VBoxContainer = %DeckList
@onready var _add_btn: Button = %AddBtn


func _ready() -> void:
	_add_btn.pressed.connect(_on_add)
	_rebuild()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	for entry in Profile.list_decks():
		_list.add_child(_build_row(entry))


func _build_row(entry: Dictionary) -> PanelContainer:
	var id := String(entry.id)
	var is_active := id == Profile.active_deck_id

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.62, 0.42, 0.10) if is_active else Color(1, 1, 1, 0.03)
	sb.border_color = COL_GOOD if is_active else Color(1, 1, 1, 0.08)
	sb.set_border_width_all(2 if is_active else 1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	info.add_child(name_row)

	var name_edit := LineEdit.new()
	name_edit.text = String(entry.name)
	name_edit.custom_minimum_size = Vector2(240, 0)
	name_edit.add_theme_font_size_override("font_size", 15)
	name_edit.text_submitted.connect(func(_t: String) -> void: _on_rename(id, name_edit))
	name_edit.focus_exited.connect(_on_rename.bind(id, name_edit))
	name_row.add_child(name_edit)

	if is_active:
		var tag := Label.new()
		tag.text = "АКТИВНА"
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color", COL_GOOD)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(tag)

	var summary := Label.new()
	summary.text = Profile.deck_summary_for(entry.deck)
	summary.add_theme_font_size_override("font_size", 12)
	summary.add_theme_color_override("font_color", COL_DIM)
	info.add_child(summary)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(actions)

	var select_btn := Button.new()
	select_btn.text = "Выбрана" if is_active else "Выбрать"
	select_btn.disabled = is_active
	select_btn.custom_minimum_size = Vector2(88, 32)
	select_btn.add_theme_font_size_override("font_size", 12)
	select_btn.pressed.connect(_on_select.bind(id))
	actions.add_child(select_btn)

	var edit_btn := Button.new()
	edit_btn.text = "Редактировать"
	edit_btn.custom_minimum_size = Vector2(116, 32)
	edit_btn.add_theme_font_size_override("font_size", 12)
	edit_btn.pressed.connect(_on_edit.bind(id))
	actions.add_child(edit_btn)

	var del_btn := Button.new()
	del_btn.text = "Удалить"
	del_btn.custom_minimum_size = Vector2(88, 32)
	del_btn.add_theme_font_size_override("font_size", 12)
	del_btn.disabled = Profile.list_decks().size() <= 1
	del_btn.tooltip_text = "В каталоге должна остаться хотя бы одна колода" if del_btn.disabled else ""
	del_btn.pressed.connect(_on_delete.bind(id, del_btn))
	actions.add_child(del_btn)

	return panel


func _on_rename(id: String, edit: LineEdit) -> void:
	Profile.rename_deck(id, edit.text)
	edit.text = String(Profile.get_deck_entry(id).get("name", edit.text))


func _on_select(id: String) -> void:
	Profile.set_active_deck(id)
	_rebuild()


func _on_edit(id: String) -> void:
	Profile.editing_deck_id = id
	get_tree().change_scene_to_file("res://duelogue/ui/deck_editor.tscn")


func _on_add() -> void:
	var id := Profile.add_deck()
	# Сразу в редактор новой записи — пустой каталожной строкой без состава ловить нечего.
	_on_edit(id)


func _on_delete(id: String, btn: Button) -> void:
	if not btn.has_meta("armed"):
		btn.set_meta("armed", true)
		btn.text = "Точно?"
		btn.add_theme_color_override("font_color", COL_WARN)
		await get_tree().create_timer(DELETE_ARM_SEC).timeout
		if is_instance_valid(btn) and btn.has_meta("armed"):
			btn.remove_meta("armed")
			btn.text = "Удалить"
			btn.remove_theme_color_override("font_color")
		return
	Profile.delete_deck(id)
	_rebuild()
