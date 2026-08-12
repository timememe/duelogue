extends Control

## DUELOGUE — ЛАБОРАТОРИЯ ИМЕНИ ПРИЁМА (дев-тул, открыть device_label_lab.tscn и F6):
## калибровка DeviceLabel/DeviceLine ВНУТРИ настоящего reaction_scene.tscn — шкалы крутят его
## реальные @export-переменные (device_font_size/device_label_line_spacing/
## device_label_size_delta/device_label_offset/device_line_fade_width), раскладку
## каждый раз пересчитывает тот же _layout_device_name/_fit_device_font_size, что идёт в бою
## (приём как у fire_lab.gd: настоящая сцена, не копия — если тут не влезает, в бою тоже не
## влезет). Портрет/бабл выставлены статично, БЕЗ tween/автоскрытия show_utterance — крути
## шкалы сколько нужно, сцена сама не погаснет.
##
## Розовая пунктирная рамка — debug-контур ТЕКУЩИХ position/size/rotation бокса подписи;
## бирюзовые вертикальные линии — истинные левый/правый край экрана (x=0 и x=CANVAS_SIZE.x).
## Повод тула (2026-08-08): сторона «you» вылезала текстом за правый край экрана после правки
## offset_left/right в _layout_device_name — глазами это не поймать без явных ориентиров, а
## числовая строка статуса ниже ловит переполнение даже там, где рамку закрыла сама панель шкал.

const ReactionSceneScene := preload("res://duelogue/core/characters/reaction_scene.tscn")
const SAMPLE_PORTRAIT := preload("res://duelogue/assets/states_test/idle.png")

const CANVAS_SIZE := Vector2(1152.0, 648.0)
const PREVIEW_SCALE := 0.6

## Реальные имена приёмов (Grammar.CARD_DEVICE, значения — то, что реально долетает в
## meta.device) плюс синтетический стресс-тест на переполнение (см. reaction_modal_smoke.gd).
const STRESS_NAME := "Устоявшееся значение по определению без всякого сомнения"
const PRESET_NAMES := ["Передёрг", "Контрпример", "До абсурда", "Источник?", "Корреляция",
	"Ложная аналогия", "Не в кассу", STRESS_NAME]

## Инстанс настоящего reaction_scene.tscn — приватные поля/методы читаем напрямую, тем же
## приёмом, что reaction_modal_smoke.gd (probe._layout_bubble и т.п.)
var _reaction
var _frame: Control
var _outline: Panel
var _side := "you"
var _side_btn: Button
var _name_edit: LineEdit
var _status: Label
var _canon := {}       ## стартовые @export-значения _reaction, снятые один раз — цель «Сбросить»
var _rows := {}        ## ключ → {slider, label, title, fmt} — для синка шкал при сбросе
var _color_rows := {}  ## ключ → ColorPickerButton


func _ready() -> void:
	_frame = _make_stage_frame()
	add_child(_frame)
	_reaction = ReactionSceneScene.instantiate()
	_frame.add_child(_reaction)
	_canon = {
		"device_font_size": _reaction.device_font_size,
		"device_font_color": _reaction.device_font_color,
		"device_label_line_spacing": _reaction.device_label_line_spacing,
		"device_label_size_delta": _reaction.device_label_size_delta,
		"device_label_offset": _reaction.device_label_offset,
		"device_line_fade_width": _reaction.device_line_fade_width,
	}
	_build_edge_guides()
	_outline = _make_outline()
	_reaction.add_child(_outline)

	_build_panel()
	_build_hint()
	_show_side("you")


func _make_stage_frame() -> Control:
	var frame := Control.new()
	frame.position = Vector2(8.0, 8.0)
	frame.size = CANVAS_SIZE
	frame.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	return frame   ## НЕ clip_contents — вылет за канвас обязан оставаться видимым, не прятаться


## Бирюзовые метки истинных x=0/x=CANVAS_SIZE.x — дети _reaction (не _frame), чтобы жить в той
## же локальной системе координат, что и DeviceLabel (в реакции все анкоры полноэкранные, её
## position внутри frame — (0,0), так что локальные координаты совпадают 1:1).
func _build_edge_guides() -> void:
	for x in [0.0, CANVAS_SIZE.x]:
		var guide := ColorRect.new()
		guide.color = Color(0.2, 0.9, 1.0, 0.55)
		guide.position = Vector2(x - 1.0, 0.0)
		guide.size = Vector2(2.0, CANVAS_SIZE.y)
		guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
		guide.z_index = 5
		_reaction.add_child(guide)


func _make_outline() -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(1.0, 0.15, 0.85, 0.95)
	sb.set_border_width_all(3)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.z_index = 6
	return p


func _build_hint() -> void:
	var hint := Label.new()
	hint.position = Vector2(8.0, CANVAS_SIZE.y * PREVIEW_SCALE + 20.0)
	hint.size = Vector2(CANVAS_SIZE.x * PREVIEW_SCALE, 90.0)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64))
	hint.text = ("Настоящий reaction_scene.tscn — раскладку подписи считает тот же " +
		"_layout_device_name/_fit_device_font_size, что и в бою. Портрет/бабл выставлены " +
		"статично (без tween/автоскрытия show_utterance), чтобы крутить шкалы сколько нужно. " +
		"Бирюзовые линии — истинные левый/правый край экрана; розовая рамка — текущий бокс " +
		"подписи (крутится вместе с наклоном).")
	add_child(hint)


# ------------------------------------------------------------------ статичный показ стороны --

## Нетвиновая версия setup-части show_utterance (reaction_scene.gd) — портрет/фон/бабл встают
## сразу в покой, без fade-in/печати/авто-fade-out, чтобы лаба не гасла сама через пару секунд.
func _show_side(side: String) -> void:
	_side = side
	_reaction.visible = true
	_reaction.modulate.a = 1.0
	var use_static: bool = _reaction._uses_static_statement_background("")
	_reaction._bg_opp_default.visible = use_static and side == "opp"
	_reaction._bg_you_default.visible = use_static and side == "you"
	_reaction._bg_mood.visible = not use_static
	_reaction._bg_shader.visible = false
	_reaction._layout_portrait(side, SAMPLE_PORTRAIT)
	_reaction._portrait.texture = SAMPLE_PORTRAIT
	_reaction._portrait.flip_h = false
	_reaction._layout_bubble(side)
	_reaction._bubble.visible = true
	_reaction._bubble.scale = Vector2.ONE
	_reaction._eyebrow.visible = false
	_reaction._bubble_label.offset_top = 12.0
	_reaction._bubble_label.text = "Превью реплики — для контекста рядом с подписью приёма."
	_reaction._bubble_label.visible_ratio = 1.0
	if _side_btn:
		_side_btn.text = "Сторона: " + ("вы, портрет слева" if side == "you" else "опп, портрет справа")
	_relayout()


func _relayout() -> void:
	_reaction._layout_device_name(_name_edit.text, _side)
	_sync_outline()
	_update_status()


func _sync_outline() -> void:
	var lbl: Label = _reaction._device_label
	_outline.visible = lbl.visible
	_outline.position = lbl.position
	_outline.size = lbl.size
	_outline.pivot_offset = lbl.pivot_offset
	_outline.rotation_degrees = lbl.rotation_degrees


func _update_status() -> void:
	var lbl: Label = _reaction._device_label
	# screen_w явно typed float: _reaction нетипизированная (Variant), .size.x без явного типа
	# тянет за собой Variant дальше по цепочке — Godot 4.6 отказывается вывести тип overflow
	# через := от выражения с Variant-операндом ("Cannot infer the type").
	var screen_w: float = _reaction.size.x
	var left := lbl.position.x
	var right := lbl.position.x + lbl.size.x
	var overflow: bool = left < -0.5 or right > screen_w + 0.5
	var fitted := lbl.get_theme_font_size("font_size")
	_status.text = "Бокс: x=%.0f..%.0f (экран 0..%.0f) · %dpx · наклон %.1f° · %s" % [
		left, right, screen_w, fitted, lbl.rotation_degrees,
		"ЗА ГРАНЬЮ ЭКРАНА!" if overflow else "в пределах экрана"]
	_status.add_theme_color_override("font_color",
		Color(1.0, 0.35, 0.35) if overflow else Color(0.55, 0.58, 0.64))


# ------------------------------------------------------------------ панель шкал ---------------

func _build_panel() -> void:
	var panel_x := CANVAS_SIZE.x * PREVIEW_SCALE + 60.0
	var pbg := ColorRect.new()
	pbg.color = Color(0.07, 0.08, 0.11, 0.92)
	pbg.position = Vector2(panel_x, 8.0)
	pbg.size = Vector2(430.0, CANVAS_SIZE.y)
	add_child(pbg)
	var vb := VBoxContainer.new()
	vb.position = Vector2(panel_x + 12.0, 14.0)
	vb.size = Vector2(406.0, CANVAS_SIZE.y - 12.0)
	vb.add_theme_constant_override("separation", 3)
	add_child(vb)

	_header(vb, "ИМЯ / СТОРОНА")
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	vb.add_child(hb)
	_side_btn = _btn(hb, "Сторона: вы, портрет слева",
		func() -> void: _show_side("opp" if _side == "you" else "you"))
	var preset := OptionButton.new()
	for n in PRESET_NAMES:
		preset.add_item(n if n.length() <= 24 else n.substr(0, 21) + "…")
	preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset.add_theme_font_size_override("font_size", 12)
	preset.item_selected.connect(func(i: int) -> void:
		_name_edit.text = PRESET_NAMES[i]
		_relayout())
	hb.add_child(preset)

	_name_edit = LineEdit.new()
	_name_edit.text = PRESET_NAMES[0]
	_name_edit.placeholder_text = "Своё имя приёма…"
	_name_edit.text_changed.connect(func(_t: String) -> void: _relayout())
	vb.add_child(_name_edit)

	_header(vb, "ШРИФТ")
	_add_slider(vb, "font_size", "Базовый размер (сжимается, если не влезает)", 16.0, 160.0, 1.0,
		_canon.device_font_size, "%.0f",
		func(v: float) -> void: _reaction.device_font_size = roundi(v); _relayout())
	_add_color(vb, "font_color", "Цвет текста", _canon.device_font_color, true,
		func(c: Color) -> void: _reaction.device_font_color = c; _relayout())

	_header(vb, "МЕЖСТРОЧНЫЙ ИНТЕРВАЛ / ПОВОРОТ −10°…+10° СЛУЧАЙНЫЙ")
	_add_slider(vb, "line_spacing", "line_spacing (theme-константа, отриц. = теснее)",
		-40.0, 20.0, 1.0, _canon.device_label_line_spacing, "%.0f",
		func(v: float) -> void: _reaction.device_label_line_spacing = roundi(v); _relayout())

	_header(vb, "БОКС — добавка поверх трети экрана (0 = как в бою)")
	_add_slider(vb, "size_dx", "Ширина ±", -300.0, 300.0, 1.0, _canon.device_label_size_delta.x,
		"%.0f", func(v: float) -> void: _reaction.device_label_size_delta.x = v; _relayout())
	_add_slider(vb, "size_dy", "Высота ±", -100.0, 200.0, 1.0, _canon.device_label_size_delta.y,
		"%.0f", func(v: float) -> void: _reaction.device_label_size_delta.y = v; _relayout())
	_add_slider(vb, "off_x", "Позиция X ±", -300.0, 300.0, 1.0, _canon.device_label_offset.x,
		"%.0f", func(v: float) -> void: _reaction.device_label_offset.x = v; _relayout())
	_add_slider(vb, "off_y", "Позиция Y ±", -150.0, 150.0, 1.0, _canon.device_label_offset.y,
		"%.0f", func(v: float) -> void: _reaction.device_label_offset.y = v; _relayout())

	_header(vb, "АКЦЕНТНАЯ ЛИНИЯ · ЗЕЛЁНАЯ ВЫ / ОРАНЖЕВАЯ ОПП")
	_add_slider(vb, "line_fade", "Ширина затухания к краям", 0.05, 0.6, 0.01,
		_canon.device_line_fade_width, "%.2f",
		func(v: float) -> void: _reaction.device_line_fade_width = v; _relayout())

	var hb2 := HBoxContainer.new()
	hb2.add_theme_constant_override("separation", 6)
	vb.add_child(hb2)
	_btn(hb2, "Сбросить на канон", _reset)
	_btn(hb2, "Скопировать значения", _copy)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.add_theme_font_size_override("font_size", 12)
	vb.add_child(_status)


func _btn(parent: Control, txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _header(vb: VBoxContainer, txt: String) -> void:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(1.0, 0.82, 0.29))
	vb.add_child(l)


## Строка-шкала: [подпись со значением | HSlider]. Регистрируется в _rows для синка при сбросе.
func _add_slider(vb: VBoxContainer, key: String, title: String, minv: float, maxv: float,
		step: float, value: float, fmt: String, cb: Callable) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	var lab := Label.new()
	lab.custom_minimum_size = Vector2(180, 0)
	lab.add_theme_font_size_override("font_size", 12)
	lab.text = "%s: %s" % [title, fmt % value]
	hb.add_child(lab)
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v: float) -> void:
		lab.text = "%s: %s" % [title, fmt % v]
		cb.call(v))
	hb.add_child(s)
	_rows[key] = {"slider": s, "label": lab, "title": title, "fmt": fmt}


## Выставить шкалу без сигнала (сброс) + обновить подпись.
func _set_row(key: String, v: float) -> void:
	var r: Dictionary = _rows[key]
	(r.slider as HSlider).set_value_no_signal(v)
	(r.label as Label).text = "%s: %s" % [r.title, String(r.fmt) % v]


func _add_color(vb: VBoxContainer, key: String, title: String, value: Color, edit_alpha: bool,
		cb: Callable) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	var lab := Label.new()
	lab.custom_minimum_size = Vector2(180, 0)
	lab.add_theme_font_size_override("font_size", 12)
	lab.text = title
	hb.add_child(lab)
	var p := ColorPickerButton.new()
	p.color = value
	p.edit_alpha = edit_alpha
	p.custom_minimum_size = Vector2(90, 24)
	p.color_changed.connect(cb)
	hb.add_child(p)
	_color_rows[key] = p


# ------------------------------------------------------------------------- вынос --------------

func _reset() -> void:
	for key: String in _canon:
		_reaction.set(key, _canon[key])
	_set_row("font_size", _canon.device_font_size)
	_set_row("line_spacing", _canon.device_label_line_spacing)
	_set_row("size_dx", _canon.device_label_size_delta.x)
	_set_row("size_dy", _canon.device_label_size_delta.y)
	_set_row("off_x", _canon.device_label_offset.x)
	_set_row("off_y", _canon.device_label_offset.y)
	_set_row("line_fade", _canon.device_line_fade_width)
	(_color_rows["font_color"] as ColorPickerButton).color = _canon.device_font_color
	_relayout()
	_status.text = "Сброшено на канон-значения reaction_scene.gd."
	_status.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64))


## Готовые присваивания — в буфер и в консоль: вставить как значения @export-полей ReactionScene
## (инспектор узла в debate_screen.tscn) или прямо дефолтами в reaction_scene.gd.
func _copy() -> void:
	var lines := PackedStringArray()
	lines.append("device_font_size = %d" % _reaction.device_font_size)
	lines.append("device_font_color = %s" % _col(_reaction.device_font_color))
	lines.append("device_label_line_spacing = %d" % _reaction.device_label_line_spacing)
	lines.append("device_label_size_delta = Vector2(%.0f, %.0f)" % [
		_reaction.device_label_size_delta.x, _reaction.device_label_size_delta.y])
	lines.append("device_label_offset = Vector2(%.0f, %.0f)" % [
		_reaction.device_label_offset.x, _reaction.device_label_offset.y])
	lines.append("device_line_fade_width = %.2f" % _reaction.device_line_fade_width)
	var out := "\n".join(lines)
	DisplayServer.clipboard_set(out)
	print(out)
	_status.text = "Скопировано в буфер (и в консоль) — вставить в инспектор ReactionScene или дефолтами в reaction_scene.gd."
	_status.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64))


func _col(c: Color) -> String:
	return "Color(%.3f, %.3f, %.3f, %.3f)" % [c.r, c.g, c.b, c.a]
