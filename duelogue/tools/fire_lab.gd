extends Control

## DUELOGUE — ОГОНЬ ЗАПАЛА, ЛАБОРАТОРИЯ (дев-тул, открыть fire_lab.tscn и F6): калибровка
## fire_aura.gdshader по образцу dolly_lab.gd — НЕ копия, сцена внутри лабы это настоящий
## stage.tscn, шкалы крутят ЕГО материалы. Шкала «Напряжение (strain)» шлёт настоящий
## EventBus.emotion_changed 0..6/6 — те же 7 ступеней и тот же код (stage_core.gd →
## _on_emotion_changed), что боевой battle_controller шлёт по-настоящему; если аура не видна
## в игре, эта шкала честно это повторит (проверка боевого пути, не только шейдера). Остальные
## шкалы (форма/турбулентность/дизер/цвет) крутят шейдер-юниформы обеих аур напрямую — своего
## боевого code-path у них нет, это чистые константы шейдера/материала. «Скопировать параметры»
## кладёт готовые shader_parameter-строки в буфер — вставить в оба ShaderMaterial_fire_* в
## stage.tscn.

const StageScene := preload("res://duelogue/core/stage/stage.tscn")
const EmotionCore := preload("res://duelogue/core/emotion/emotion_core.gd")

## Канон-канвас проекта (как в dolly_lab.gd) — та же система координат, в которой авторится
## stage.tscn (абсолютные позиции актёров), плюс масштаб превью, чтобы влезла панель шкал.
const CANVAS_SIZE := Vector2(1152.0, 648.0)
const PREVIEW_SCALE := 0.6

## Канон-значения из fire_aura.gdshader (дефолты uniform) — стартовые позиции шкал и цель
## кнопки «Сбросить на канон».
const CANON_PARAMS := {
	"noise_scale": 3.2,
	"warp_strength": 1.1,
	"base_speed": 0.5,
	"max_speed": 2.2,
	"base_reach": 0.5,
	"max_reach": 0.98,
	"base_width": 0.34,
	"max_width": 0.62,
	"max_density_bias": 0.22,
	"edge_soft": 0.05,
	"base_edge_flicker": 0.02,
	"max_edge_flicker": 0.12,
	"edge_flicker_scale": 2.5,
	"flame_levels": 6.0,
	"dither_px": 2.0,
}
const CANON_COLORS := {
	"ember": Color(0.35, 0.06, 0.03, 1.0),
	"mid": Color(0.92, 0.35, 0.06, 1.0),
	"hot": Color(1.0, 0.75, 0.15, 0.92),
	"core": Color(1.0, 0.96, 0.78, 1.0),
}

var _stage
var _mat_you: ShaderMaterial
var _mat_opp: ShaderMaterial

var _p := {}          ## рабочая копия числовых юниформ (ключ = имя юниформа шейдера)
var _colors := {}     ## рабочая копия цветов (ключ без префикса color_)
var _strain := 0
var _auto := false
var _auto_t := 0.0
var _auto_dir := 1
var _step_time := 0.5

var _status: Label
var _auto_check: CheckBox
var _rows := {}        ## ключ → {slider, label, title, fmt} — для синка шкал при сбросе
var _color_rows := {}  ## ключ → ColorPickerButton


func _ready() -> void:
	_p = CANON_PARAMS.duplicate()
	_colors = CANON_COLORS.duplicate()

	var frame := _make_stage_frame()
	add_child(frame)
	_stage = StageScene.instantiate()
	frame.add_child(_stage)
	_mat_you = _stage.fire_rect("you").material as ShaderMaterial
	_mat_opp = _stage.fire_rect("opp").material as ShaderMaterial

	_build_panel()
	_build_hint()
	_apply_shape()
	_apply_colors()


func _process(delta: float) -> void:
	if not _auto:
		return
	_auto_t += delta
	if _auto_t < _step_time:
		return
	_auto_t = 0.0
	_strain += _auto_dir
	if _strain >= EmotionCore.MAX_STRAIN:
		_strain = EmotionCore.MAX_STRAIN
		_auto_dir = -1
	elif _strain <= 0:
		_strain = 0
		_auto_dir = 1
	_set_row("strain", float(_strain))
	_apply_strain(_strain)


func _make_stage_frame() -> Control:
	var frame := Control.new()
	frame.position = Vector2(8.0, 8.0)
	frame.size = CANVAS_SIZE
	frame.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	frame.clip_contents = true
	return frame


func _build_hint() -> void:
	var hint := Label.new()
	hint.position = Vector2(8.0, CANVAS_SIZE.y * PREVIEW_SCALE + 20.0)
	hint.size = Vector2(CANVAS_SIZE.x * PREVIEW_SCALE, 90.0)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64))
	hint.text = ("Превью в масштабе %.0f%% канон-канваса %dx%d — тот же stage.tscn, что в бою. " +
		"«Напряжение» шлёт настоящий EventBus.emotion_changed (0..6/6, боевой путь через " +
		"stage_core.gd); остальные шкалы правят шейдер-юниформы обеих аур напрямую (своего " +
		"code-path у формы/цвета нет).") % [
		PREVIEW_SCALE * 100.0, int(CANVAS_SIZE.x), int(CANVAS_SIZE.y)]
	add_child(hint)


# ------------------------------------------------------------------ панель шкал

func _build_panel() -> void:
	var panel_x := CANVAS_SIZE.x * PREVIEW_SCALE + 24.0
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

	_header(vb, "ЭМОЦИОНАЛЬНАЯ ШКАЛА")
	_add_slider(vb, "strain", "Напряжение (strain), боевой EventBus", 0.0,
		float(EmotionCore.MAX_STRAIN), 1.0, 0.0, "%.0f/6",
		func(v: float) -> void:
			_auto = false
			_auto_check.set_pressed_no_signal(false)
			_apply_strain(roundi(v)))
	_auto_check = _add_check(vb, "Авто-прогон по всем этапам (0↔6, петля)",
		func(v: bool) -> void:
			_auto = v
			_auto_t = 0.0)
	_add_slider(vb, "_step", "Шаг автопрогона, с/этап", 0.1, 2.0, 0.05, _step_time, "%.2f",
		func(v: float) -> void: _step_time = v)

	_header(vb, "ФОРМА — ОГИБАЮЩАЯ")
	_add_slider(vb, "base_reach", "Высота на 0/6 (доля рамки)", 0.0, 1.0, 0.01,
		_p.base_reach, "%.2f", _shape_cb("base_reach"))
	_add_slider(vb, "max_reach", "Высота на 6/6", 0.0, 1.0, 0.01,
		_p.max_reach, "%.2f", _shape_cb("max_reach"))
	_add_slider(vb, "base_width", "Ширина у подошвы на 0/6", 0.0, 1.0, 0.01,
		_p.base_width, "%.2f", _shape_cb("base_width"))
	_add_slider(vb, "max_width", "Ширина у подошвы на 6/6", 0.0, 1.0, 0.01,
		_p.max_width, "%.2f", _shape_cb("max_width"))
	_add_slider(vb, "max_density_bias", "Плотность поля на пике (меньше дыр)", 0.0, 0.6, 0.01,
		_p.max_density_bias, "%.2f", _shape_cb("max_density_bias"))
	_add_slider(vb, "edge_soft", "Мягкость краевого спада", 0.0, 0.3, 0.01,
		_p.edge_soft, "%.2f", _shape_cb("edge_soft"))

	_header(vb, "ДРЕБЕЗГ КОНТУРА (огненная тряска силуэта)")
	_add_slider(vb, "base_edge_flicker", "Амплитуда на 0/6", 0.0, 0.3, 0.01,
		_p.base_edge_flicker, "%.2f", _shape_cb("base_edge_flicker"))
	_add_slider(vb, "max_edge_flicker", "Амплитуда на 6/6 (языки рвут силуэт)", 0.0, 0.3, 0.01,
		_p.max_edge_flicker, "%.2f", _shape_cb("max_edge_flicker"))
	_add_slider(vb, "edge_flicker_scale", "Масштаб волн дребезга по высоте", 0.5, 8.0, 0.1,
		_p.edge_flicker_scale, "%.2f", _shape_cb("edge_flicker_scale"))

	_header(vb, "ТУРБУЛЕНТНОСТЬ / СКОРОСТЬ")
	_add_slider(vb, "noise_scale", "Масштаб турбулентности (больше = мельче языки)", 0.5, 10.0,
		0.1, _p.noise_scale, "%.2f", _shape_cb("noise_scale"))
	_add_slider(vb, "warp_strength", "Сила domain-warp", 0.0, 4.0, 0.05,
		_p.warp_strength, "%.2f", _shape_cb("warp_strength"))
	_add_slider(vb, "base_speed", "Скорость на 0/6", 0.05, 4.0, 0.05,
		_p.base_speed, "%.2f", _shape_cb("base_speed"))
	_add_slider(vb, "max_speed", "Скорость на 6/6", 0.05, 8.0, 0.05,
		_p.max_speed, "%.2f", _shape_cb("max_speed"))

	_header(vb, "ПОСВЕТЕРИЗАЦИЯ / ДИЗЕР")
	_add_slider(vb, "flame_levels", "Ступеней цвета", 2.0, 16.0, 1.0,
		_p.flame_levels, "%.0f", _shape_cb("flame_levels"))
	_add_slider(vb, "dither_px", "Чанк-пиксель зерна", 1.0, 8.0, 1.0,
		_p.dither_px, "%.0f", _shape_cb("dither_px"))

	_header(vb, "ЦВЕТ")
	_add_color(vb, "ember", "Холодный край (низкий heat)", _colors.ember, false, _color_cb("ember"))
	_add_color(vb, "mid", "Рабочее пламя", _colors.mid, false, _color_cb("mid"))
	_add_color(vb, "hot", "Яркое пламя (.a = пик альфы!)", _colors.hot, true, _color_cb("hot"))
	_add_color(vb, "core", "Раскалённое ядро (пик heat×intensity)", _colors.core, false,
		_color_cb("core"))

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	vb.add_child(hb)
	_btn(hb, "Сбросить на канон", _reset)
	_btn(hb, "Скопировать параметры", _copy)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64))
	_status.text = "Крути «Напряжение» — реальный EventBus.emotion_changed на обе стороны."
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
	lab.custom_minimum_size = Vector2(226, 0)
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


## Выставить шкалу без сигнала (автопрогон/сброс) + обновить подпись.
func _set_row(key: String, v: float) -> void:
	var r: Dictionary = _rows[key]
	(r.slider as HSlider).set_value_no_signal(v)
	(r.label as Label).text = "%s: %s" % [r.title, String(r.fmt) % v]


func _add_check(vb: VBoxContainer, title: String, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = title
	c.add_theme_font_size_override("font_size", 12)
	c.toggled.connect(cb)
	vb.add_child(c)
	return c


func _add_color(vb: VBoxContainer, key: String, title: String, value: Color, edit_alpha: bool,
		cb: Callable) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	var lab := Label.new()
	lab.custom_minimum_size = Vector2(226, 0)
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


# ------------------------------------------------------------------ применение --

func _shape_cb(key: String) -> Callable:
	return func(v: float) -> void:
		_p[key] = v
		_mat_you.set_shader_parameter(key, v)
		_mat_opp.set_shader_parameter(key, v)


func _color_cb(key: String) -> Callable:
	return func(c: Color) -> void:
		_colors[key] = c
		var uniform := "color_" + key
		_mat_you.set_shader_parameter(uniform, c)
		_mat_opp.set_shader_parameter(uniform, c)


func _apply_shape() -> void:
	for key: String in _p:
		_mat_you.set_shader_parameter(key, _p[key])
		_mat_opp.set_shader_parameter(key, _p[key])


func _apply_colors() -> void:
	for key: String in _colors:
		var uniform := "color_" + key
		_mat_you.set_shader_parameter(uniform, _colors[key])
		_mat_opp.set_shader_parameter(uniform, _colors[key])


## Тот же сигнал, что battle_controller.gd шлёт по-настоящему — stage_core.gd сам делит
## strain/max и ставит intensity на материал; лаба ничего не трогает в обход этого кода.
func _apply_strain(strain: int) -> void:
	_strain = strain
	var maximum := EmotionCore.MAX_STRAIN
	EventBus.emotion_changed.emit("you", {"strain": strain, "max": maximum})
	EventBus.emotion_changed.emit("opp", {"strain": strain, "max": maximum})
	_status.text = ("strain %d/%d → intensity %.3f — настоящий EventBus.emotion_changed, " +
		"тот же код, что боевой battle_controller.") % [
		strain, maximum, float(strain) / float(maximum)]


# ---------------------------------------------------------------------- вынос ---

func _reset() -> void:
	_auto = false
	_auto_check.set_pressed_no_signal(false)
	_step_time = 0.5
	_set_row("_step", 0.5)
	_set_row("strain", 0.0)
	_apply_strain(0)
	for key: String in CANON_PARAMS:
		_p[key] = CANON_PARAMS[key]
		_set_row(key, CANON_PARAMS[key])
	_apply_shape()
	for key: String in CANON_COLORS:
		_colors[key] = CANON_COLORS[key]
		(_color_rows[key] as ColorPickerButton).color = CANON_COLORS[key]
	_apply_colors()
	_status.text = "Сброшено на канон-значения шейдера."


## Готовые shader_parameter-строки — в буфер и в консоль: вставить в оба ShaderMaterial_fire_*
## в stage.tscn без пересчёта руками (тот же приём, что fx_lab._copy()).
func _copy() -> void:
	var lines := PackedStringArray()
	lines.append("shader_parameter/intensity = %.3f" % (float(_strain) / float(EmotionCore.MAX_STRAIN)))
	for key: String in ["ember", "mid", "hot", "core"]:
		lines.append("shader_parameter/color_%s = %s" % [key, _col(_colors[key])])
	for key: String in CANON_PARAMS:
		lines.append("shader_parameter/%s = %.3f" % [key, _p[key]])
	var out := "\n".join(lines)
	DisplayServer.clipboard_set(out)
	print(out)
	_status.text = "Скопировано в буфер — вставить в оба ShaderMaterial_fire_* блока stage.tscn."


func _col(c: Color) -> String:
	return "Color(%.3f, %.3f, %.3f, %.3f)" % [c.r, c.g, c.b, c.a]
