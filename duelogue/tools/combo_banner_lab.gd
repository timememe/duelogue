extends Control

## DUELOGUE — ЛАБОРАТОРИЯ COMBO-BANNER (F6 на combo_banner_lab.tscn).
## Инстанцирует настоящий ui/combo_name_banner.gd: шкалы меняют его реальные shape/layer/
## animation-поля, Static показывает позу покоя, Replay запускает боевой show_combo().
## Открывается на текущем боевом каноне; отдельный стартовый пресет оставлен для экспериментов.

const ComboNameBanner := preload("res://duelogue/ui/combo_name_banner.gd")
const PREVIEW_BG := preload("res://duelogue/assets/bg_courtroom_v2.png")

const CANVAS_SIZE := Vector2(1152.0, 648.0)
const PREVIEW_SCALE := 0.58
const TWO_LAYER_OVERRIDES := {
	"back_layer_enabled": true,
	"back_layer_scale": 1.28,
	"back_layer_spikes": 11.0,
	"back_layer_sharpness": 3.6,
	"back_layer_rotation_offset_deg": 18.0,
	"back_layer_alpha": 0.30,
	"back_layer_tone": -0.18,
	"anim_in_rotation_delta_deg": -18.0,
	"anim_out_rotation_delta_deg": 10.0,
	"anim_back_delay": 0.06,
}

var _banner
var _params := {}
var _side := "you"
var _name_edit: LineEdit
var _side_btn: Button
var _back_check: CheckBox
var _auto_check: CheckBox
var _status: Label
var _rows := {}
var _auto := false
var _auto_elapsed := 0.0


func _ready() -> void:
	_params = ComboNameBanner.CANON_TUNING.duplicate(true)

	var frame := _make_preview_frame()
	add_child(frame)
	_build_preview_background(frame)
	_banner = ComboNameBanner.new()
	_banner.size = CANVAS_SIZE
	frame.add_child(_banner)

	_build_panel()
	_build_hint()
	_refresh_static("Загружен текущий боевой канон — крути форму или нажми Replay.")


func _process(delta: float) -> void:
	if not _auto:
		return
	_auto_elapsed += delta
	if _auto_elapsed >= _animation_total() + 0.35:
		_replay()


func _make_preview_frame() -> Control:
	var frame := Control.new()
	frame.position = Vector2(8.0, 8.0)
	frame.size = CANVAS_SIZE
	frame.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	frame.clip_contents = true
	return frame


func _build_preview_background(frame: Control) -> void:
	var bg := TextureRect.new()
	bg.texture = PREVIEW_BG
	bg.size = CANVAS_SIZE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(bg)
	var dim := ColorRect.new()
	dim.size = CANVAS_SIZE
	dim.color = Color(0.02, 0.03, 0.06, 0.42)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(dim)


func _build_hint() -> void:
	var hint := Label.new()
	hint.position = Vector2(8.0, CANVAS_SIZE.y * PREVIEW_SCALE + 18.0)
	hint.size = Vector2(CANVAS_SIZE.x * PREVIEW_SCALE, 116.0)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64))
	hint.text = ("Превью %.0f%% канон-канваса %dx%d. Это настоящий ComboNameBanner: Static " +
		"мгновенно показывает слои, Replay запускает реальный tween. Боевой дефолт остаётся " +
		"однослойным, пока подобранный пресет отдельно не перенесён в ComboNameBanner.") % [
		PREVIEW_SCALE * 100.0, int(CANVAS_SIZE.x), int(CANVAS_SIZE.y)]
	add_child(hint)


func _build_panel() -> void:
	var panel_x := CANVAS_SIZE.x * PREVIEW_SCALE + 24.0
	var pbg := ColorRect.new()
	pbg.color = Color(0.07, 0.08, 0.11, 0.96)
	pbg.position = Vector2(panel_x, 8.0)
	pbg.size = Vector2(456.0, 632.0)
	add_child(pbg)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(panel_x + 8.0, 12.0)
	scroll.size = Vector2(440.0, 624.0)
	add_child(scroll)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(420.0, 0.0)
	vb.add_theme_constant_override("separation", 3)
	scroll.add_child(vb)

	_header(vb, "COMBO-BANNER LAB · НАСТОЯЩИЙ ЭФФЕКТ")
	_name_edit = LineEdit.new()
	_name_edit.text = "Консенсус сильнее"
	_name_edit.placeholder_text = "Название комбо"
	_name_edit.text_changed.connect(func(_text: String) -> void: _refresh_static())
	vb.add_child(_name_edit)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 5)
	vb.add_child(top)
	_side_btn = _btn(top, "Сторона: ВЫ", _toggle_side)
	_btn(top, "▶ Replay", _replay)
	_btn(top, "■ Static", func() -> void: _refresh_static())
	_auto_check = _add_check(vb, "Автоповтор анимации",
		func(enabled: bool) -> void:
			_auto = enabled
			_auto_elapsed = 0.0
			if enabled:
				_replay())

	_header(vb, "ФОРМА ОСНОВНОЙ ФИГУРЫ")
	_add_slider(vb, "burst_spikes", "Лучей / spikes", 2.0, 40.0, 1.0,
		_params.burst_spikes, "%.0f", _param_cb("burst_spikes"))
	_add_slider(vb, "burst_outer_frac", "Внешний радиус", 0.10, 0.72, 0.005,
		_params.burst_outer_frac, "%.3f", _param_cb("burst_outer_frac"))
	_add_slider(vb, "burst_inner_frac", "Внутренняя впадина", 0.02, 0.68, 0.005,
		_params.burst_inner_frac, "%.3f", _param_cb("burst_inner_frac"))
	_add_slider(vb, "burst_sharpness", "Острота лучей", 1.0, 20.0, 0.1,
		_params.burst_sharpness, "%.1f", _param_cb("burst_sharpness"))
	_add_slider(vb, "burst_edge_fade", "Ширина дизер-края", 0.001, 0.08, 0.001,
		_params.burst_edge_fade, "%.3f", _param_cb("burst_edge_fade"))
	_add_slider(vb, "burst_rotation_deg", "Поворот фигуры", -45.0, 45.0, 0.5,
		_params.burst_rotation_deg, "%.1f°", _param_cb("burst_rotation_deg"))

	_header(vb, "ВТОРОЙ СЛОЙ ПОЗАДИ")
	_back_check = _add_check(vb, "Показывать фоновую фигуру",
		func(enabled: bool) -> void:
			_params.back_layer_enabled = enabled
			_refresh_static())
	_back_check.set_pressed_no_signal(bool(_params.back_layer_enabled))
	_add_slider(vb, "back_layer_scale", "Масштаб", 0.50, 2.0, 0.01,
		_params.back_layer_scale, "%.2f", _param_cb("back_layer_scale"))
	_add_slider(vb, "back_layer_spikes", "Лучей / spikes", 2.0, 40.0, 1.0,
		_params.back_layer_spikes, "%.0f", _param_cb("back_layer_spikes"))
	_add_slider(vb, "back_layer_sharpness", "Острота лучей", 1.0, 20.0, 0.1,
		_params.back_layer_sharpness, "%.1f", _param_cb("back_layer_sharpness"))
	_add_slider(vb, "back_layer_rotation_offset_deg", "Поворот относительно front", -90.0,
		90.0, 0.5, _params.back_layer_rotation_offset_deg, "%.1f°",
		_param_cb("back_layer_rotation_offset_deg"))
	_add_slider(vb, "back_layer_alpha", "Прозрачность", 0.0, 1.0, 0.01,
		_params.back_layer_alpha, "%.2f", _param_cb("back_layer_alpha"))
	_add_slider(vb, "back_layer_tone", "Тон: − темнее / + светлее", -1.0, 1.0, 0.01,
		_params.back_layer_tone, "%+.2f", _param_cb("back_layer_tone"))
	_add_slider(vb, "back_offset_x", "Смещение X", -240.0, 240.0, 2.0,
		(_params.back_layer_offset as Vector2).x, "%.0f", _offset_cb(true))
	_add_slider(vb, "back_offset_y", "Смещение Y", -180.0, 180.0, 2.0,
		(_params.back_layer_offset as Vector2).y, "%.0f", _offset_cb(false))

	_header(vb, "АНИМАЦИЯ")
	_add_slider(vb, "anim_start_scale", "Стартовый масштаб", 0.01, 1.0, 0.01,
		_params.anim_start_scale, "%.2f", _param_cb("anim_start_scale"))
	_add_slider(vb, "anim_out_scale", "Масштаб на выходе", 1.0, 2.0, 0.01,
		_params.anim_out_scale, "%.2f", _param_cb("anim_out_scale"))
	_add_slider(vb, "anim_in_rotation_delta_deg", "Докрутка на входе", -180.0, 180.0, 1.0,
		_params.anim_in_rotation_delta_deg, "%+.0f°", _param_cb("anim_in_rotation_delta_deg"))
	_add_slider(vb, "anim_out_rotation_delta_deg", "Докрутка на выходе", -180.0, 180.0, 1.0,
		_params.anim_out_rotation_delta_deg, "%+.0f°", _param_cb("anim_out_rotation_delta_deg"))
	_add_slider(vb, "anim_back_delay", "Задержка второго слоя", 0.0, 0.5, 0.01,
		_params.anim_back_delay, "%.2fs", _param_cb("anim_back_delay"))
	_add_slider(vb, "anim_punch_in", "Punch-in", 0.05, 1.0, 0.01,
		_params.anim_punch_in, "%.2fs", _param_cb("anim_punch_in"))
	_add_slider(vb, "anim_hold", "Пауза чтения", 0.0, 3.0, 0.05,
		_params.anim_hold, "%.2fs", _param_cb("anim_hold"))
	_add_slider(vb, "anim_punch_out", "Punch-out", 0.05, 1.0, 0.01,
		_params.anim_punch_out, "%.2fs", _param_cb("anim_punch_out"))

	_header(vb, "ПРЕСЕТ / ВЫНОС")
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 5)
	vb.add_child(actions)
	_btn(actions, "Боевой канон", _reset_canon)
	_btn(actions, "Старт: 2 слоя", _reset_two_layers)
	_btn(vb, "Скопировать параметры", _copy)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size = Vector2(410.0, 52.0)
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64))
	vb.add_child(_status)


func _btn(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _header(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.29))
	parent.add_child(label)


func _add_slider(parent: VBoxContainer, key: String, title: String, min_value: float,
		max_value: float, step: float, value: float, format: String, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	parent.add_child(row)
	var label := Label.new()
	label.custom_minimum_size = Vector2(226.0, 0.0)
	label.add_theme_font_size_override("font_size", 11)
	label.text = "%s: %s" % [title, format % value]
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void:
		label.text = "%s: %s" % [title, format % v]
		callback.call(v))
	row.add_child(slider)
	_rows[key] = {"slider": slider, "label": label, "title": title, "format": format}


func _add_check(parent: Control, text: String, callback: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.add_theme_font_size_override("font_size", 12)
	check.toggled.connect(callback)
	parent.add_child(check)
	return check


func _set_row(key: String, value: float) -> void:
	if not _rows.has(key):
		return
	var row: Dictionary = _rows[key]
	(row.slider as HSlider).set_value_no_signal(value)
	(row.label as Label).text = "%s: %s" % [row.title, String(row.format) % value]


func _param_cb(key: String) -> Callable:
	return func(value: float) -> void:
		_params[key] = value
		_refresh_static()


func _offset_cb(horizontal: bool) -> Callable:
	return func(value: float) -> void:
		var offset: Vector2 = _params.back_layer_offset
		if horizontal:
			offset.x = value
		else:
			offset.y = value
		_params.back_layer_offset = offset
		_refresh_static()


func _toggle_side() -> void:
	_side = "opp" if _side == "you" else "you"
	_side_btn.text = "Сторона: " + ("ВЫ" if _side == "you" else "ОПП")
	_refresh_static()


func _refresh_static(message: String = "") -> void:
	_auto_elapsed = 0.0
	_banner.apply_tuning(_params)
	_banner.show_static_preview(_name_edit.text, _side)
	if _status:
		_status.text = message if message != "" else _summary("Static")


func _replay() -> void:
	_auto_elapsed = 0.0
	_banner.apply_tuning(_params)
	_banner.show_combo(_name_edit.text, _side)
	if _status:
		_status.text = _summary("Replay")


func _animation_total() -> float:
	var delay := float(_params.anim_back_delay) if bool(_params.back_layer_enabled) else 0.0
	return float(_params.anim_punch_in) + delay + float(_params.anim_hold) + \
		float(_params.anim_punch_out)


func _summary(mode: String) -> String:
	return "%s · %s · %s · %.2fs · front %d лучей / back %d" % [
		mode, "ВЫ" if _side == "you" else "ОПП",
		"2 слоя" if bool(_params.back_layer_enabled) else "1 слой", _animation_total(),
		roundi(float(_params.burst_spikes)), roundi(float(_params.back_layer_spikes))]


func _apply_preset(base: Dictionary, overrides: Dictionary = {}) -> void:
	_params = base.duplicate(true)
	for key: String in overrides:
		_params[key] = overrides[key]
	for key: String in ComboNameBanner.TUNING_KEYS:
		if _params[key] is float or _params[key] is int:
			_set_row(key, float(_params[key]))
	var offset: Vector2 = _params.back_layer_offset
	_set_row("back_offset_x", offset.x)
	_set_row("back_offset_y", offset.y)
	_back_check.set_pressed_no_signal(bool(_params.back_layer_enabled))
	_refresh_static()


func _reset_canon() -> void:
	_auto = false
	_auto_check.set_pressed_no_signal(false)
	_apply_preset(ComboNameBanner.CANON_TUNING)
	_status.text = "Сброшено на текущий боевой канон: два слоя, 2.06s."


func _reset_two_layers() -> void:
	_auto = false
	_auto_check.set_pressed_no_signal(false)
	_apply_preset(ComboNameBanner.CANON_TUNING, TWO_LAYER_OVERRIDES)
	_status.text = "Загружен стартовый двухслойный эксперимент."


func _copy() -> void:
	var lines := PackedStringArray(["# ComboNameBanner tuning"])
	for key: String in ComboNameBanner.TUNING_KEYS:
		var value: Variant = _params[key]
		if value is bool:
			lines.append("%s = %s" % [key, "true" if value else "false"])
		elif value is Vector2:
			lines.append("%s = Vector2(%.1f, %.1f)" % [key, value.x, value.y])
		else:
			lines.append("%s = %.3f" % [key, float(value)])
	lines.append("# total ≈ %.3fs; при переносе тайминга синхронизировать ReadingPace.BANNER_*" %
		_animation_total())
	var output := "\n".join(lines)
	DisplayServer.clipboard_set(output)
	print(output)
	_status.text = "Параметры скопированы в буфер и консоль."
