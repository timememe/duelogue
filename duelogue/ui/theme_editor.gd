extends Control

## DUELOGUE — РЕДАКТОР ТЕМЫ: сырой JSON одной записи каталога ThemeLibrary. Какую запись
## открыть — решает ThemeLibrary.editing_theme_id (транзит-хэндофф от theme_catalog; пусто →
## заготовка новой темы — либо TEMPLATE, либо черновик от Кодекса, если theme_catalog прислал
## его через ThemeLibrary.pending_import_text). Это ФУНДАМЕНТ (текст + валидация контракта), не финальный UI —
## структурный грид-редактор по осям/takes/supports отдельным слоем поверх этого же
## ThemeLibrary API (add_theme/save_theme_data не знают и не должны знать, кто их вызвал:
## текстовое поле или будущая форма).
##
## Save парсит текст → ThemeLibrary.validate_theme(): errors блокируют кнопку «Сохранить»
## (сломали бы движок при обращении — narrative_engine.md §5), warnings — только подсказка
## (авторский ориентир контракта, не запрет — та же философия, что коридоры в deck_editor).

const COL_DIM := Color(0.5412, 0.5765, 0.6392)
const COL_GOOD := Color(0.44, 0.81, 0.5)
const COL_WARN := Color(0.85, 0.35, 0.3)
const COL_CAUTION := Color(1.0, 0.82, 0.29)
const CatalogHub := preload("res://duelogue/ui/catalog_hub.gd")

const TEMPLATE := """{
	"topic": "Название спора",
	"stances": {
		"contra": {"label": "против ...", "headlines": [
			{"id": "contra_1", "text": "первая широкая позиция", "preferred_axes": []}
		]},
		"pro": {"label": "за ...", "headlines": [
			{"id": "pro_1", "text": "первая широкая позиция", "preferred_axes": []}
		]}
	},
	"axes": [
		{"id": "axis_1", "tag": "тег", "appeal": "logos",
		 "contra": "взгляд полюса против по этой оси", "pro": "взгляд полюса за по этой оси",
		 "motifs": [], "takes": {"contra": [], "pro": []}, "supports": {"contra": {}, "pro": {}}}
	],
	"shared_motifs": [],
	"voices": {"contra": "", "pro": ""}
}"""

var _editing_id := ""
var _file_dialog: FileDialog

@onready var _title_label: Label = %TitleLabel
@onready var _name_edit: LineEdit = %NameEdit
@onready var _text_edit: TextEdit = %ThemeText
@onready var _status_label: Label = %StatusLabel
@onready var _errors_label: Label = %ErrorsLabel
@onready var _warnings_label: Label = %WarningsLabel
@onready var _save_btn: Button = %SaveBtn


func _ready() -> void:
	%BackBtn.pressed.connect(_to_catalog)
	%LoadFileBtn.pressed.connect(func() -> void: _file_dialog.popup_centered())
	%TemplateBtn.pressed.connect(_load_template)
	%ValidateBtn.pressed.connect(_validate_only)
	_save_btn.pressed.connect(_save)
	_setup_file_dialog()

	_editing_id = ThemeLibrary.editing_theme_id
	ThemeLibrary.editing_theme_id = ""
	var entry := ThemeLibrary.get_theme_entry(_editing_id) if _editing_id != "" else {}
	if not entry.is_empty():
		_name_edit.text = String(entry.name)
		_text_edit.text = JSON.stringify(entry.data, "\t")
		_title_label.text = "РЕДАКТОР ТЕМЫ — %s" % String(entry.name)
	else:
		_editing_id = ""
		_name_edit.text = ""
		# Хэндофф из Кодекса (theme_catalog) перекрывает пустой шаблон — та же логика
		# «разовый хэндофф, сразу гасим», что у editing_theme_id.
		var draft := ThemeLibrary.pending_import_text
		ThemeLibrary.pending_import_text = ""
		if draft.strip_edges() != "":
			_text_edit.text = draft
			_title_label.text = "РЕДАКТОР ТЕМЫ — черновик от Кодекса"
		else:
			_text_edit.text = TEMPLATE
			_title_label.text = "РЕДАКТОР ТЕМЫ — новая"
	_validate_only()


func _setup_file_dialog() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.json ; JSON темы"])
	_file_dialog.title = "Загрузить тему из JSON"
	_file_dialog.size = Vector2i(720, 520)
	_file_dialog.file_selected.connect(_on_file_selected)
	add_child(_file_dialog)


func _on_file_selected(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_show_report(["Не удалось открыть файл: %s" % path], [], "Файл не загружен.", COL_WARN)
		return
	_text_edit.text = f.get_as_text()
	f.close()
	if _name_edit.text.strip_edges() == "":
		_name_edit.text = path.get_file().get_basename()
	_validate_only()


func _load_template() -> void:
	_text_edit.text = TEMPLATE
	_validate_only()


# ------------------------------------------------------------- парс + отчёт ---

func _parse_current() -> Dictionary:
	var parser := JSON.new()
	var err := parser.parse(_text_edit.text)
	if err != OK:
		return {"ok": false, "data": null, "errors": [
			"JSON-ошибка (строка %d): %s" % [parser.get_error_line(), parser.get_error_message()]],
			"warnings": []}
	var v := ThemeLibrary.validate_theme(parser.data)
	var errs: Array = v.errors
	return {"ok": errs.is_empty(), "data": parser.data, "errors": v.errors, "warnings": v.warnings}


func _validate_only() -> void:
	var r := _parse_current()
	var errs: Array = r.errors
	var warns: Array = r.warnings
	if not errs.is_empty():
		_show_report(errs, warns, "Есть ошибки — сохранение недоступно, пока они не исправлены.", COL_WARN)
	elif not warns.is_empty():
		_show_report(errs, warns, "Можно сохранять — но контракт §5 отмечает предупреждения ниже.", COL_CAUTION)
	else:
		_show_report(errs, warns, "Проверено — ошибок и предупреждений нет.", COL_GOOD)


func _save() -> void:
	var r := _parse_current()
	var errs: Array = r.errors
	if not errs.is_empty():
		_show_report(errs, r.warnings, "Есть ошибки — сохранение недоступно, пока они не исправлены.", COL_WARN)
		return
	var res: Dictionary
	if _editing_id == "":
		res = ThemeLibrary.add_theme(r.data, _name_edit.text)
	else:
		res = ThemeLibrary.save_theme_data(_editing_id, r.data)
		if bool(res.get("ok", false)):
			ThemeLibrary.rename_theme(_editing_id, _name_edit.text)
	if not bool(res.get("ok", false)):
		_show_report(res.get("errors", []), res.get("warnings", []), "Не сохранено.", COL_WARN)
		return
	_editing_id = String(res.id)
	var warns: Array = res.get("warnings", [])
	var msg := "Сохранено." if warns.is_empty() else "Сохранено (см. предупреждения ниже)."
	_show_report([], warns, msg, COL_GOOD)


func _show_report(errs: Array, warns: Array, status_text: String, status_color: Color) -> void:
	_errors_label.text = "\n".join(errs.map(func(e: String) -> String: return "✕ %s" % e))
	_warnings_label.text = "\n".join(warns.map(func(w: String) -> String: return "△ %s" % w))
	_status_label.add_theme_color_override("font_color", status_color)
	_status_label.text = status_text
	_save_btn.disabled = not errs.is_empty()


func _to_catalog() -> void:
	CatalogHub.requested_tab = 1  # вкладка «Темы»
	get_tree().change_scene_to_file("res://duelogue/ui/catalog_hub.tscn")
