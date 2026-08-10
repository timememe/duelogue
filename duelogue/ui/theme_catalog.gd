extends Control

## DUELOGUE — КАТАЛОГ ТЕМ: список тем нарративного движка (ThemeLibrary.themes). Управляет
## СПИСКОМ — имя, какая активна (её играет боёвка и афиши забега — battle_controller/
## run_controller читают ThemeLibrary), добавить (импорт JSON)/дублировать/удалить запись;
## СОДЕРЖИМОЕ конкретной темы правит ui/theme_editor (открывается отсюда с
## ThemeLibrary.editing_theme_id). Ряды строятся кодом, сама панель — в theme_catalog.tscn.
## Зеркалит ui/deck_catalog по устройству (тот же двухкликовый арм на удаление).
##
## Секретная кнопка «⚙» — мостик к vps-codex-agent (HTTP-обёртка над Codex CLI, свой VPS):
## POST {url}/task {prompt, outputSchema} -> {ok, result} (см. AGENT_TOOLS/VPSagent/README.md). URL и
## bearer-токен живут ТОЛЬКО в user://codex_agent.json (вне res://, вне git — секрет никогда
## не коммитится). VPS передаёт игровую схему в `codex exec --output-schema`, а клиент повторно
## парсит и валидирует результат. Даже валидный ответ не сохраняется в каталог напрямую: он уходит черновиком в
## theme_editor (ThemeLibrary.pending_import_text) — та же проверка контракта и то же
## осознанное решение игрока «Сохранить», что и у ручной вставки/импорта файла.

const DELETE_ARM_SEC := 3.0
const CODEX_CONFIG_PATH := "user://codex_agent.json"
const CODEX_DEFAULT_URL := "https://agent.worldorder.online"
const CODEX_TIMEOUT_SEC := 540.0  ## под потолком серверного TASK_TIMEOUT_MS=600000 (10 мин)
const CODEX_CONNECT_TIMEOUT_SEC := 15.0
const THEME_OUTPUT_SCHEMA_PATH := "res://duelogue/data/ai/theme_output.schema.json"

const COL_DIM := Color(0.5412, 0.5765, 0.6392)
const COL_GOOD := Color(0.44, 0.81, 0.5)
const COL_WARN := Color(0.85, 0.35, 0.3)
const COL_GOLD := Color(1.0, 0.8235, 0.2902)

## Инлайнится в каждый запрос — у Codex на VPS нет доступа к этому репозиторию (отдельная
## машина), так что контракт §5/§10 narrative_engine.md пересказывается кратко прямо в промпте.
const CONTRACT_BRIEF := """Ты — соавтор игры DUELOGUE (дебатный карточный рогалик). Нужна НОВАЯ
тема для режима дебатов в формате JSON — и ТОЛЬКО JSON: без markdown-обёртки ```, без пояснений
до или после объекта.

Схема (обязательные поля):
{
  "topic": "короткое название спора",
  "stances": {
    "contra": {"label": "род. оборот, напр. «против X»", "headlines": [
      {"id": "contra_1", "text": "широкая позиция, наст. время, строчная, без точки", "preferred_axes": ["axis_id", "..."]}
      // минимум 4 headline
    ]},
    "pro": {"label": "род. оборот, напр. «за X»", "headlines": [ /* минимум 4, та же форма */ ]}
  },
  "axes": [
    {
      "id": "короткий_латинский_id", "tag": "1-2 слова, именительный (короткая ссылка на ось)",
      "appeal": "logos | pathos | ethos",
      "contra": "целая фраза — взгляд полюса против на эту ось",
      "pro": "целая фраза — взгляд полюса за на эту ось",
      "motifs": ["1-3 именительных существительных"],
      "takes": {"contra": ["2-3 варианта того же взгляда"], "pro": ["2-3 варианта того же взгляда"]},
      "supports": {
        "contra": {"number": ["конкретная фраза со статистикой"], "case": ["конкретный случай"]},
        "pro": {"analogy": ["сравнение"], "source": ["ссылка на эксперта"]}
      }
    }
    // минимум 6 осей
  ],
  "shared_motifs": ["3-5 именительных существительных общего резерва"],
  "voices": {"contra": "архетип голоса", "pro": "архетип голоса"}
}

Правила: contra и pro на КАЖДОЙ оси — прямо противоположные взгляды на ОДИН и тот же
под-вопрос, не разные темы. Среди всех осей должна быть хотя бы одна с appeal=logos, хотя бы
одна pathos, хотя бы одна ethos. Типы supports (используй несколько разных, не один везде):
number/case/source/analogy/common/stake/definition/precedent/exception/distinction/consequence.
Фразы — целиком, без конечной точки. Никаких падежных склонений слотов («у X», «с X») —
только целые фразы или существительные в именительном.

Запрос автора:
"""

@onready var _list: VBoxContainer = %ThemeList
@onready var _import_btn: Button = %ImportBtn
@onready var _codex_btn: Button = %CodexBtn
@onready var _codex_panel: PanelContainer = %CodexPanel
@onready var _url_edit: LineEdit = %UrlEdit
@onready var _token_edit: LineEdit = %TokenEdit
@onready var _save_conn_btn: Button = %SaveConnBtn
@onready var _conn_status_label: Label = %ConnStatusLabel
@onready var _prompt_edit: TextEdit = %PromptEdit
@onready var _ask_btn: Button = %AskBtn
@onready var _request_status_label: Label = %RequestStatusLabel

var _http: HTTPRequest
var _connection_http: HTTPRequest
var _pending_connection := {}


func _ready() -> void:
	_import_btn.pressed.connect(_on_import)
	_codex_btn.pressed.connect(_open_codex_panel)
	%CloseCodexBtn.pressed.connect(func() -> void: _codex_panel.visible = false)
	_save_conn_btn.pressed.connect(_on_save_connection)
	_ask_btn.pressed.connect(_on_ask_codex)
	_http = HTTPRequest.new()
	_http.timeout = CODEX_TIMEOUT_SEC
	add_child(_http)
	_http.request_completed.connect(_on_codex_response)
	_connection_http = HTTPRequest.new()
	_connection_http.timeout = CODEX_CONNECT_TIMEOUT_SEC
	add_child(_connection_http)
	_connection_http.request_completed.connect(_on_connection_checked)
	_rebuild()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	for entry in ThemeLibrary.list_themes():
		_list.add_child(_build_row(entry))


func _build_row(entry: Dictionary) -> PanelContainer:
	var id := String(entry.id)
	var is_active := id == ThemeLibrary.active_theme_id
	var data: Dictionary = entry.data

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
	name_edit.custom_minimum_size = Vector2(220, 0)
	name_edit.add_theme_font_size_override("font_size", 15)
	name_edit.text_submitted.connect(func(_t: String) -> void: _on_rename(id, name_edit))
	name_edit.focus_exited.connect(_on_rename.bind(id, name_edit))
	name_row.add_child(name_edit)

	var badge := Label.new()
	badge.text = "встроенная" if String(entry.source) == "builtin" else "своя"
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_color_override("font_color", COL_GOLD if String(entry.source) == "builtin" else COL_DIM)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(badge)

	if is_active:
		var tag := Label.new()
		tag.text = "АКТИВНА"
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color", COL_GOOD)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(tag)

	var topic := Label.new()
	topic.text = "«%s»" % String(data.get("topic", "без темы"))
	topic.add_theme_font_size_override("font_size", 13)
	info.add_child(topic)

	var summary := Label.new()
	summary.text = ThemeLibrary.theme_summary_for(data)
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

	var dup_btn := Button.new()
	dup_btn.text = "Дублировать"
	dup_btn.custom_minimum_size = Vector2(104, 32)
	dup_btn.add_theme_font_size_override("font_size", 12)
	dup_btn.tooltip_text = "Копия темы — удобный старт, чтобы не писать оси/takes/supports с нуля"
	dup_btn.pressed.connect(_on_duplicate.bind(id))
	actions.add_child(dup_btn)

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
	del_btn.disabled = ThemeLibrary.list_themes().size() <= 1
	del_btn.tooltip_text = "В каталоге должна остаться хотя бы одна тема" if del_btn.disabled else ""
	del_btn.pressed.connect(_on_delete.bind(id, del_btn))
	actions.add_child(del_btn)

	return panel


func _on_rename(id: String, edit: LineEdit) -> void:
	ThemeLibrary.rename_theme(id, edit.text)
	edit.text = String(ThemeLibrary.get_theme_entry(id).get("name", edit.text))


func _on_select(id: String) -> void:
	ThemeLibrary.set_active_theme(id)
	_rebuild()


func _on_duplicate(id: String) -> void:
	var new_id := ThemeLibrary.duplicate_theme(id)
	if new_id == "":
		return
	_on_edit(new_id)


func _on_edit(id: String) -> void:
	ThemeLibrary.editing_theme_id = id
	get_tree().change_scene_to_file("res://duelogue/ui/theme_editor.tscn")


func _on_import() -> void:
	ThemeLibrary.editing_theme_id = ""
	get_tree().change_scene_to_file("res://duelogue/ui/theme_editor.tscn")


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
	ThemeLibrary.delete_theme(id)
	_rebuild()


# ------------------------------------------------------------- Кодекс (VPS) ---

func _open_codex_panel() -> void:
	var cfg := _load_codex_config()
	_url_edit.text = String(cfg.get("url", CODEX_DEFAULT_URL))
	_token_edit.text = String(cfg.get("token", ""))
	_conn_status_label.text = ""
	_request_status_label.text = ""
	_codex_panel.visible = true


func _load_codex_config() -> Dictionary:
	if not FileAccess.file_exists(CODEX_CONFIG_PATH):
		return {}
	var f := FileAccess.open(CODEX_CONFIG_PATH, FileAccess.READ)
	if f == null:
		return {}
	var raw: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return raw if raw is Dictionary else {}


func _on_save_connection() -> void:
	var url := _url_edit.text.strip_edges().trim_suffix("/")
	var token := _token_edit.text.strip_edges()
	if url == "" or token == "":
		_conn_status_label.add_theme_color_override("font_color", COL_WARN)
		_conn_status_label.text = "Нужны и URL, и токен."
		return
	if not url.begins_with("https://") and not url.begins_with("http://"):
		_conn_status_label.add_theme_color_override("font_color", COL_WARN)
		_conn_status_label.text = "URL должен начинаться с https:// (или http:// для локального сервера)."
		return
	_pending_connection = {"url": url, "token": token}
	_save_conn_btn.disabled = true
	_conn_status_label.remove_theme_color_override("font_color")
	_conn_status_label.text = "Проверяю адрес и токен…"
	var headers := PackedStringArray(["Authorization: Bearer %s" % token])
	var err := _connection_http.request(url + "/auth", headers, HTTPClient.METHOD_GET)
	if err != OK:
		_save_conn_btn.disabled = false
		_pending_connection = {}
		_conn_status_label.add_theme_color_override("font_color", COL_WARN)
		_conn_status_label.text = "Не удалось начать проверку подключения (код %d)." % err


func _on_connection_checked(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_save_conn_btn.disabled = false
	var pending := _pending_connection
	_pending_connection = {}
	if result != HTTPRequest.RESULT_SUCCESS:
		_conn_status_label.add_theme_color_override("font_color", COL_WARN)
		_conn_status_label.text = "VPS недоступен (сетевая ошибка %d)." % result
		return
	var response: Variant = JSON.parse_string(body.get_string_from_utf8())
	if response_code != 200 or not (response is Dictionary) or not bool((response as Dictionary).get("ok", false)):
		var detail := String((response as Dictionary).get("error", "ответ сервера не распознан")) \
			if response is Dictionary else "ответ сервера не распознан"
		_conn_status_label.add_theme_color_override("font_color", COL_WARN)
		_conn_status_label.text = "Подключение отклонено (HTTP %d): %s" % [response_code, detail]
		return
	var f := FileAccess.open(CODEX_CONFIG_PATH, FileAccess.WRITE)
	if f == null:
		_conn_status_label.add_theme_color_override("font_color", COL_WARN)
		_conn_status_label.text = "Не удалось сохранить (нет доступа к user://)."
		return
	f.store_string(JSON.stringify(pending, "\t"))
	f.close()
	_conn_status_label.add_theme_color_override("font_color", COL_GOOD)
	_conn_status_label.text = "Подключено как «%s». Секрет сохранён только в user://." % \
		String((response as Dictionary).get("service", "service"))


func _on_ask_codex() -> void:
	var cfg := _load_codex_config()
	var url := String(cfg.get("url", "")).strip_edges().trim_suffix("/")
	var token := String(cfg.get("token", "")).strip_edges()
	if url == "" or token == "":
		_request_status_label.add_theme_color_override("font_color", COL_WARN)
		_request_status_label.text = "Сначала сохрани подключение (URL + токен) выше."
		return
	var user_prompt := _prompt_edit.text.strip_edges()
	if user_prompt == "":
		_request_status_label.add_theme_color_override("font_color", COL_WARN)
		_request_status_label.text = "Опиши, о чём должна быть тема."
		return
	var headers := PackedStringArray([
		"Content-Type: application/json; charset=utf-8",
		"Authorization: Bearer %s" % token,
	])
	var output_schema := _load_theme_output_schema()
	if output_schema.is_empty():
		_request_status_label.add_theme_color_override("font_color", COL_WARN)
		_request_status_label.text = "Локальная JSON-схема темы не загрузилась. Проверь файл theme_output.schema.json."
		return
	var body := JSON.stringify({"prompt": CONTRACT_BRIEF + user_prompt, "outputSchema": output_schema})
	var err := _http.request(url + "/task", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_request_status_label.add_theme_color_override("font_color", COL_WARN)
		_request_status_label.text = "Не удалось отправить запрос (код %d)." % err
		return
	_ask_btn.disabled = true
	_request_status_label.remove_theme_color_override("font_color")
	_request_status_label.text = "Кодекс работает — это может занять до нескольких минут…"


func _on_codex_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_ask_btn.disabled = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_request_status_label.add_theme_color_override("font_color", COL_WARN)
		_request_status_label.text = "Сеть подвела (код %d) — проверь URL и доступность VPS." % result
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		_request_status_label.add_theme_color_override("font_color", COL_WARN)
		_request_status_label.text = "Агент ответил не JSON'ом (код %d)." % response_code
		return
	var d: Dictionary = parsed
	if response_code == 429:
		_request_status_label.add_theme_color_override("font_color", COL_WARN)
		_request_status_label.text = "Лимит подписки исчерпан (%s, %s%%). Повтори через ~%d мин." % [
			String(d.get("window", "?")), str(d.get("usedPercent", "?")), int(float(d.get("retryAfterSec", 0)) / 60.0)]
		return
	if response_code != 200 or not bool(d.get("ok", false)):
		_request_status_label.add_theme_color_override("font_color", COL_WARN)
		_request_status_label.text = "Кодекс не справился (код %d): %s" % [
			response_code, String(d.get("error", d.get("stderr", "неизвестная ошибка агента")))]
		return
	var candidate := _extract_json_candidate(String(d.get("result", "")))
	var theme_data: Variant = JSON.parse_string(candidate)
	if not (theme_data is Dictionary):
		_request_status_label.add_theme_color_override("font_color", COL_WARN)
		_request_status_label.text = "Кодекс завершил задачу, но не вернул объект темы. Попробуй ещё раз."
		return
	var validation := ThemeLibrary.validate_theme(theme_data)
	if not (validation.errors as Array).is_empty():
		_request_status_label.add_theme_color_override("font_color", COL_WARN)
		_request_status_label.text = "Ответ не прошёл контракт темы: %s" % "; ".join(validation.errors)
		return
	ThemeLibrary.pending_import_text = JSON.stringify(theme_data, "\t")
	ThemeLibrary.editing_theme_id = ""
	get_tree().change_scene_to_file("res://duelogue/ui/theme_editor.tscn")


func _load_theme_output_schema() -> Dictionary:
	var f := FileAccess.open(THEME_OUTPUT_SCHEMA_PATH, FileAccess.READ)
	if f == null:
		return {}
	var raw: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return raw if raw is Dictionary else {}


## Обратная совместимость со старым сервером/CLI: schema-режим возвращает чистый JSON, но если
## пришла прежняя ```-обёртка, срезаем её перед обязательным разбором и валидацией.
func _extract_json_candidate(text: String) -> String:
	var t := text.strip_edges()
	if t.begins_with("```"):
		var first_nl := t.find("\n")
		if first_nl != -1:
			t = t.substr(first_nl + 1)
		if t.ends_with("```"):
			t = t.substr(0, t.length() - 3)
		t = t.strip_edges()
	var start := t.find("{")
	var last := t.rfind("}")
	if start != -1 and last != -1 and last > start:
		return t.substr(start, last - start + 1)
	return t
