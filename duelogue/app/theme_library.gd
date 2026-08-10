extends Node

## DUELOGUE — БИБЛИОТЕКА ТЕМ (autoload "ThemeLibrary"): каталог тем нарративного движка
## (контракт — context/narrative_engine.md §5/§10: тема = граф аргументов — stances с
## headlines для Установок + спорные axes с contra/pro, опционально tag/appeal/takes/
## supports). Раньше темы были ТРЁМЯ хардкод-скриптами (theme_pineapple/shawarma/
## evangelion.gd) и выбор жил в compile-time константе battle_controller.ACTIVE_THEME.
## Теперь это каталог ДАННЫХ (как Profile.decks для колод): добавляется/редактируется/
## импортируется из JSON в рантайме, без правки кода. Единственный владелец сейва
## user://theme_library.json. battle_controller/run_controller читают ТОЛЬКО отсюда
## (get_active_theme_data/list_themes/select), про сами файлы theme_*.gd знает только
## этот файл — и то лишь чтобы засеять каталог при первом запуске.
##
## Валидация двухуровневая (validate_theme): errors — блокируют сохранение (сломают движок
## при обращении: пустой topic, отсутствующие stances.pro/contra.headlines, отсутствующие/
## пустые axes или axis без id/contra/pro — narrative_engine.gd делает ax.id/theme.stances[..]
## БЕЗ .get-фолбэков, отсюда и жёсткость именно этих полей); warnings — не блокируют (авторский
## ориентир контракта §5: ≥6 осей, ≥4 headlines на стойку, ≥2 takes на полюс, appeal-покрытие
## К6, теги/appeal у осей) — те же «индикаторы, не запреты», что и коридоры в deck_editor.

const PineappleTheme := preload("res://duelogue/core/narrative/themes/theme_pineapple.gd")
const ShawarmaTheme := preload("res://duelogue/core/narrative/themes/theme_shawarma.gd")
const EvangelionTheme := preload("res://duelogue/core/narrative/themes/theme_evangelion.gd")
const BUILTIN_SCRIPTS := [PineappleTheme, ShawarmaTheme, EvangelionTheme]

const SAVE_PATH := "user://theme_library.json"
const APPEALS := ["logos", "pathos", "ethos"]

var themes := []           ## каталог: [{id, name, source, data}, ...] — минимум 1 запись всегда
var active_theme_id := ""
var editing_theme_id := "" ## транзит-хэндофф theme_catalog → theme_editor; "" = создать новую (не сейвится)
var pending_import_text := "" ## черновик JSON от Кодекса (theme_catalog → theme_editor); не сейвится


func _ready() -> void:
	load_library()
	_ensure_catalog()


func list_themes() -> Array:
	return themes.duplicate(true)


func get_theme_entry(id: String) -> Dictionary:
	var i := _index_of(id)
	return (themes[i] as Dictionary).duplicate(true) if i != -1 else {}


## Контент активной темы (то, что видит narrative_engine.start()). Предельный фолбэк на
## первую встроенную тему — каталог не должен пустеть, но падать вместо игры хуже, чем
## однажды тихо откатиться на канон.
func get_active_theme_data() -> Dictionary:
	var e := get_theme_entry(active_theme_id)
	if not e.is_empty():
		return (e.data as Dictionary).duplicate(true)
	return _normalize_theme(BUILTIN_SCRIPTS[0].data(), "pineapple")


# ------------------------------------------------------------- каталог тем ----

func add_theme(data: Variant, name: String = "") -> Dictionary:
	var result := validate_theme(data)
	if not (result.errors as Array).is_empty():
		return {"ok": false, "id": "", "errors": result.errors, "warnings": result.warnings}
	var id := _new_id()
	var norm := _normalize_theme(data as Dictionary, id)
	var nm := name.strip_edges() if name.strip_edges() != "" else String(norm.get("topic", "Тема"))
	themes.append({"id": id, "name": nm, "source": "custom", "data": norm})
	save_library()
	return {"ok": true, "id": id, "errors": [], "warnings": result.warnings}


## Импорт из сырого JSON-текста (файл или вставленный текст) — главный вход «загрузить новую
## тему». Отдельная от add_theme ошибка parse даёт номер строки — быстрее чем гадать в тексте.
func import_theme_json(text: String, name: String = "") -> Dictionary:
	var parser := JSON.new()
	var err := parser.parse(text)
	if err != OK:
		return {"ok": false, "id": "", "errors": [
			"JSON-ошибка (строка %d): %s" % [parser.get_error_line(), parser.get_error_message()]],
			"warnings": []}
	return add_theme(parser.data, name)


## Каталог не может опуститься до нуля записей — бою и афишам забега всегда нужна тема.
func delete_theme(id: String) -> void:
	if themes.size() <= 1:
		return
	var i := _index_of(id)
	if i == -1:
		return
	themes.remove_at(i)
	if active_theme_id == id:
		set_active_theme(String(themes[0].id))
	else:
		save_library()


func rename_theme(id: String, name: String) -> void:
	var i := _index_of(id)
	if i == -1:
		return
	var nm := name.strip_edges()
	if nm != "":
		themes[i]["name"] = nm
	save_library()


## Полная копия существующей записи — реалистичный старт нового кастома («хочу тему как
## Ананас, но про буррито»): руками с нуля 6 осей × takes/supports не пишут.
func duplicate_theme(id: String) -> String:
	var i := _index_of(id)
	if i == -1:
		return ""
	var src: Dictionary = themes[i]
	var new_id := _new_id()
	var data: Dictionary = (src.data as Dictionary).duplicate(true)
	data["id"] = new_id
	themes.append({"id": new_id, "name": "%s (копия)" % String(src.name), "source": "custom", "data": data})
	save_library()
	return new_id


## Пишет СОДЕРЖИМОЕ конкретной записи (theme_editor.save).
func save_theme_data(id: String, data: Variant) -> Dictionary:
	var i := _index_of(id)
	if i == -1:
		return {"ok": false, "id": id, "errors": ["Запись каталога не найдена."], "warnings": []}
	var result := validate_theme(data)
	if not (result.errors as Array).is_empty():
		return {"ok": false, "id": id, "errors": result.errors, "warnings": result.warnings}
	themes[i]["data"] = _normalize_theme(data as Dictionary, id)
	save_library()
	return {"ok": true, "id": id, "errors": [], "warnings": result.warnings}


func set_active_theme(id: String) -> void:
	if _index_of(id) == -1:
		return
	active_theme_id = id
	save_library()


func export_theme_json(id: String) -> String:
	var e := get_theme_entry(id)
	return JSON.stringify(e.get("data", {}), "\t") if not e.is_empty() else ""


## Короткая сводка темы (каталог/редактор): «6 осей · headlines 6/6 · appeal L2 P2 E2».
func theme_summary_for(data: Dictionary) -> String:
	var axes: Array = data.get("axes", []) if data.get("axes") is Array else []
	var st: Dictionary = data.get("stances", {}) if data.get("stances") is Dictionary else {}
	var counts := {"logos": 0, "pathos": 0, "ethos": 0}
	for raw_ax in axes:
		if raw_ax is Dictionary and counts.has(String((raw_ax as Dictionary).get("appeal", ""))):
			counts[String((raw_ax as Dictionary).appeal)] += 1
	var heads_c := ((st.get("contra", {}) as Dictionary).get("headlines", []) as Array).size() if st.get("contra") is Dictionary else 0
	var heads_p := ((st.get("pro", {}) as Dictionary).get("headlines", []) as Array).size() if st.get("pro") is Dictionary else 0
	return "%d осей · headlines %d/%d · appeal L%d P%d E%d" % [
		axes.size(), heads_c, heads_p, counts.logos, counts.pathos, counts.ethos]


func _index_of(id: String) -> int:
	for i in themes.size():
		if String(themes[i].id) == id:
			return i
	return -1


func _new_id() -> String:
	return "th%d_%d" % [Time.get_ticks_usec(), randi() % 1000]


# ------------------------------------------------------------------ контракт --

## Ошибки БЛОКИРУЮТ сохранение (упадёт движок), предупреждения — нет (авторский ориентир,
## §5/§10 narrative_engine.md). Не проверяет K3 (fill-safe пунктуация) и К7 (headline≠take
## дословно) — это текстовые эвристики для будущего theme_lint, не структурные гарантии.
func validate_theme(data: Variant) -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	if not (data is Dictionary):
		errors.append("Тема должна быть JSON-объектом, а не %s." % _type_name(data))
		return {"errors": errors, "warnings": warnings}
	var d: Dictionary = data
	if String(d.get("topic", "")).strip_edges() == "":
		errors.append("Не указан topic (название темы).")
	_validate_stances(d, errors, warnings)
	_validate_axes(d, errors, warnings)
	if d.has("shared_motifs") and not (d.get("shared_motifs") is Array):
		errors.append("shared_motifs должен быть списком строк.")
	if d.has("voices") and not (d.get("voices") is Dictionary):
		errors.append("voices должен быть объектом {contra, pro}.")
	return {"errors": errors, "warnings": warnings}


func _validate_stances(d: Dictionary, errors: Array, warnings: Array) -> void:
	if not (d.get("stances") is Dictionary):
		errors.append("Отсутствует stances (contra/pro).")
		return
	var st: Dictionary = d.stances
	for pole in ["contra", "pro"]:
		if not (st.get(pole) is Dictionary):
			errors.append("stances.%s отсутствует." % pole)
			continue
		var p: Dictionary = st[pole]
		if String(p.get("label", "")).strip_edges() == "":
			errors.append("stances.%s.label пуст." % pole)
		var heads: Variant = p.get("headlines")
		if not (heads is Array) or (heads as Array).is_empty():
			errors.append("stances.%s.headlines пуст — нечем открыть Установку." % pole)
		elif (heads as Array).size() < 4:
			warnings.append("stances.%s.headlines: %d шт (контракт ждёт ≥4)." % [pole, (heads as Array).size()])


func _validate_axes(d: Dictionary, errors: Array, warnings: Array) -> void:
	if not (d.get("axes") is Array) or (d.get("axes") as Array).is_empty():
		errors.append("Отсутствуют axes — теме нечем спорить.")
		return
	var axes: Array = d.axes
	var seen_ids := {}
	var appeals := {}
	for i in axes.size():
		var raw_ax: Variant = axes[i]
		if not (raw_ax is Dictionary):
			errors.append("axes[%d] не является объектом." % i)
			continue
		var ax: Dictionary = raw_ax
		var aid := String(ax.get("id", ""))
		var tag := "axes[%d] (id=%s)" % [i, aid] if aid != "" else "axes[%d]" % i
		if aid == "":
			errors.append("%s: нет id." % tag)
		elif seen_ids.has(aid):
			warnings.append("%s: id повторяется — вторая ось станет недостижимой." % tag)
		seen_ids[aid] = true
		if String(ax.get("contra", "")).strip_edges() == "":
			errors.append("%s: пуст contra (взгляд полюса против)." % tag)
		if String(ax.get("pro", "")).strip_edges() == "":
			errors.append("%s: пуст pro (взгляд полюса за)." % tag)
		var appeal := String(ax.get("appeal", ""))
		if appeal == "":
			warnings.append("%s: нет appeal (logos/pathos/ethos) — приём и ось иногда будут мисматчиться." % tag)
		elif not APPEALS.has(appeal):
			warnings.append("%s: appeal=\"%s\" — ожидался logos/pathos/ethos." % [tag, appeal])
		else:
			appeals[appeal] = true
		if String(ax.get("tag", "")).strip_edges() == "":
			warnings.append("%s: нет tag (короткая ссылка на ось для повторных упоминаний)." % tag)
		var takes: Variant = ax.get("takes")
		if takes is Dictionary:
			for pole in ["contra", "pro"]:
				var tk: Variant = (takes as Dictionary).get(pole)
				if not (tk is Array) or (tk as Array).size() < 2:
					warnings.append("%s: takes.%s меньше 2 вариантов." % [tag, pole])
		else:
			warnings.append("%s: нет takes — движок возьмёт только статичный contra/pro (v0.3-fallback)." % tag)
	if axes.size() < 6:
		warnings.append("Осей %d — авторский ориентир контракта (§5) ждёт ≥6." % axes.size())
	for need in APPEALS:
		if not appeals.has(need):
			warnings.append("Ни одна ось не помечена appeal=%s (К6: нужна ≥1 каждого)." % need)


func _type_name(v: Variant) -> String:
	return type_string(typeof(v))


## Мёрж безопасных дефолтов для полей, которые движок трогает без .get-фолбэков (shared_motifs/
## voices/per-axis tag·appeal·motifs·takes·supports), но НЕ придумывает контент, который
## validate_theme() требует явно (topic/stances/axes) — те либо есть, либо errors не пропустят
## вызывающего сюда. fallback_id уходит в data.id, только если тема сама его не назвала.
func _normalize_theme(raw: Dictionary, fallback_id: String) -> Dictionary:
	var d: Dictionary = raw.duplicate(true)
	d["id"] = String(d.get("id", "")) if String(d.get("id", "")) != "" else fallback_id
	d["topic"] = String(d.get("topic", ""))
	if not (d.get("shared_motifs") is Array):
		d["shared_motifs"] = []
	if d.get("voices") is Dictionary:
		var v: Dictionary = d.voices
		v["contra"] = String(v.get("contra", ""))
		v["pro"] = String(v.get("pro", ""))
	else:
		d["voices"] = {"contra": "", "pro": ""}
	if d.get("stances") is Dictionary:
		var st: Dictionary = d.stances
		for pole in ["contra", "pro"]:
			if st.get(pole) is Dictionary:
				var p: Dictionary = st[pole]
				p["label"] = String(p.get("label", ""))
				if not (p.get("headlines") is Array):
					p["headlines"] = []
	if d.get("axes") is Array:
		var axes: Array = d.axes
		for i in axes.size():
			if not (axes[i] is Dictionary):
				continue
			var ax: Dictionary = axes[i]
			ax["id"] = String(ax.get("id", "axis_%d" % i))
			ax["tag"] = String(ax.get("tag", ax.id))
			ax["appeal"] = String(ax.get("appeal", "logos"))
			ax["contra"] = String(ax.get("contra", ""))
			ax["pro"] = String(ax.get("pro", ""))
			if not (ax.get("motifs") is Array):
				ax["motifs"] = []
			if not (ax.get("takes") is Dictionary):
				ax["takes"] = {"contra": [], "pro": []}
			if not (ax.get("supports") is Dictionary):
				ax["supports"] = {"contra": {}, "pro": {}}
	return d


## Каталог из ≥1 записи после загрузки. Пустой каталог (первый запуск) — засеиваем тремя
## встроенными темами (единственное место, где эти три .gd-файла ещё кому-то нужны). Битый/
## пустой active_theme_id — откат на первую запись каталога.
func _ensure_catalog() -> void:
	if themes.is_empty():
		for script in BUILTIN_SCRIPTS:
			var data: Dictionary = script.data()
			var id := _new_id()
			themes.append({
				"id": id, "name": String(data.get("topic", "Тема")), "source": "builtin",
				"data": _normalize_theme(data, id),
			})
		active_theme_id = String(themes[0].id)
		save_library()
		return
	if _index_of(active_theme_id) == -1:
		active_theme_id = String(themes[0].id)
		save_library()


# --- сейв ---

func save_library() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"themes": themes, "active_theme_id": active_theme_id}, "\t"))
	f.close()


func load_library() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var raw: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not raw is Dictionary:
		return
	var d: Dictionary = raw
	if d.get("themes") is Array:
		var built := []
		for e in (d.themes as Array):
			if e is Dictionary and String((e as Dictionary).get("id", "")) != "" \
					and (e as Dictionary).get("data") is Dictionary:
				var re: Dictionary = e
				built.append({
					"id": String(re.id), "name": String(re.get("name", "Тема")),
					"source": String(re.get("source", "custom")),
					"data": _normalize_theme(re.data, String(re.id)),
				})
		themes = built
		active_theme_id = String(d.get("active_theme_id", ""))
