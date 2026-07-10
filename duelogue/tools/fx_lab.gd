extends Control

## DUELOGUE — FX-ЛАБОРАТОРИЯ (дев-тул, открыть fx_lab.tscn и F6): ручная калибровка
## аниме-фона высказывания (mood_bg.gdshader) и частичного дизера портрета
## (dither.gdshader) шкалами вживую. Пресет муда грузит профиль из БОЕВОЙ таблицы
## reaction_scene.MOOD_FX (единый источник — стартуешь с реальных значений), шкалы крутят
## рабочую копию, «Скопировать профиль» кладёт готовую строку таблицы в буфер (+консоль).
## Направление (dir) шкалой не крутится — это язык таблицы; тумблер стороны его зеркалит.
## Диапазоны шкал = КОМФОРТ-КАЛИБРОВКА 2026-07-09 (скорость ≥1, мазок 0.42..1, рядов
## 25..42, ячейка 0.5, толщина 0.3..0.8 по рядам) — держимся их, дефолты совпадают с боем.

const ReactionScene := preload("res://duelogue/core/characters/reaction_scene.gd")
const MOOD_BG_SHADER := preload("res://duelogue/assets/shaders/mood_bg.gdshader")
const DITHER_SHADER := preload("res://duelogue/assets/shaders/dither.gdshader")

const MOODS := ["declare", "hold", "attack", "gotcha", "burst", "evade", "swagger", "panic", "idle"]
const PORTRAITS := [
	preload("res://duelogue/assets/states_test/objection.png"),
	preload("res://duelogue/assets/states_test/idle.png"),
	preload("res://duelogue/assets/states_test/normal.png"),
	preload("res://duelogue/assets/states_test/pointing.png"),
	preload("res://duelogue/assets/states_test/angry.png"),
	preload("res://duelogue/assets/states_test/grinning.png"),
	preload("res://duelogue/assets/states_test/laughing.png"),
	preload("res://duelogue/assets/states_test/shocked.png"),
	preload("res://duelogue/assets/states_test/sweating.png"),
	preload("res://duelogue/assets/states_test/disheartened.png"),
]

var _mood := "burst"
var _side := "you"
var _fx := {}           ## рабочая копия профиля MOOD_FX (мутируется шкалами)
var _spread := 1.0      ## разброс цвета линий: 0 = перелива нет (B=A), 1 = профильный B
var _dash := 0.5        ## ячейка вдоль — канон 0.5 (лаб-ручка на поэкспериментировать)
var _thick_min := 0.3   ## толщина: низ разброса по рядам (канон 0.3)
var _thick_max := 0.8   ## толщина: верх разброса по рядам (канон 0.8)
var _bg_grain := 2.0    ## зерно линий фона (dither_px шейдера фона)
var _beam := {"strength": 0.4, "width": 0.32, "grain": 4.0, "levels": 5.0}  ## луч по центру
var _pt := {"px": 1.0, "levels": 6.0, "ceiling": 0.15, "soft": 0.0, "strength": 0.25}
var _portrait_i := 0

var _bg_mat: ShaderMaterial
var _pt_mat: ShaderMaterial
var _portrait: TextureRect
var _side_btn: Button
var _status: Label
var _rows := {}         ## ключ → {slider, label, title, fmt} — для синка шкал при смене пресета


func _ready() -> void:
	_fx = (ReactionScene.MOOD_FX[_mood] as Dictionary).duplicate()
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = MOOD_BG_SHADER
	_pt_mat = ShaderMaterial.new()
	_pt_mat.shader = DITHER_SHADER

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.material = _bg_mat
	add_child(bg)

	_portrait = TextureRect.new()
	_portrait.material = _pt_mat
	_portrait.texture = PORTRAITS[0]
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.position = Vector2(16, 8)
	_portrait.size = Vector2(600, 632)
	add_child(_portrait)

	_build_panel()
	_apply_bg()
	_apply_pt()


# ------------------------------------------------------------------ панель шкал

func _build_panel() -> void:
	var pbg := ColorRect.new()
	pbg.color = Color(0.07, 0.08, 0.11, 0.92)
	pbg.position = Vector2(688, 4)
	pbg.size = Vector2(456, 640)
	add_child(pbg)
	var vb := VBoxContainer.new()
	vb.position = Vector2(700, 10)
	vb.size = Vector2(432, 628)
	vb.add_theme_constant_override("separation", 2)
	add_child(vb)

	# Верхний ряд: пресет муда / сторона / смена портрета.
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	vb.add_child(hb)
	var ob := OptionButton.new()
	for m in MOODS:
		ob.add_item(m)
	ob.selected = MOODS.find(_mood)
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.add_theme_font_size_override("font_size", 12)
	ob.item_selected.connect(_on_mood)
	hb.add_child(ob)
	_side_btn = _btn(hb, "Сторона: вы", _toggle_side)
	_btn(hb, "Портрет →", _next_portrait)

	_header(vb, "ФОН — СПИДЛАЙНЫ")
	_add_slider(vb, "speed", "Скорость", 1.0, 10.0, 0.1, _fx.speed, "%.1f",
		func(v: float) -> void: _fx.speed = v; _apply_bg())
	_add_slider(vb, "fill", "Длина мазка", 0.42, 1.0, 0.01, _fx.fill, "%.2f",
		func(v: float) -> void: _fx.fill = v; _apply_bg())
	_add_slider(vb, "dash", "Ячейка вдоль (канон 0.5)", 0.25, 2.0, 0.05, _dash, "%.2f",
		func(v: float) -> void: _dash = v; _apply_bg())
	_add_slider(vb, "density", "Кол-во рядов", 25.0, 42.0, 1.0, _fx.density, "%.0f",
		func(v: float) -> void: _fx.density = v; _apply_bg())
	_add_slider(vb, "spread", "Разброс цвета (перелив A↔B)", 0.0, 1.0, 0.01, _spread, "%.2f",
		func(v: float) -> void: _spread = v; _apply_bg())
	_add_slider(vb, "thick_min", "Толщина: низ разброса", 0.05, 1.0, 0.01, _thick_min, "%.2f",
		func(v: float) -> void: _thick_min = v; _apply_bg())
	_add_slider(vb, "thick_max", "Толщина: верх разброса", 0.05, 1.0, 0.01, _thick_max, "%.2f",
		func(v: float) -> void: _thick_max = v; _apply_bg())
	_add_slider(vb, "intensity", "Мощность (зерно линий + подмес)", 0.0, 1.0, 0.01, _fx.intensity, "%.2f",
		func(v: float) -> void: _fx.intensity = v; _apply_bg())
	_add_slider(vb, "bg_grain", "Пиксель зерна линий", 1.0, 8.0, 1.0, _bg_grain, "%.0f",
		func(v: float) -> void: _bg_grain = v; _apply_bg())

	_header(vb, "ЛУЧ ПО ЦЕНТРУ (позади линий)")
	_add_slider(vb, "beam_strength", "Сила луча", 0.0, 1.0, 0.01, _beam.strength, "%.2f",
		func(v: float) -> void: _beam.strength = v; _apply_bg())
	_add_slider(vb, "beam_width", "Ширина луча", 0.05, 1.0, 0.01, _beam.width, "%.2f",
		func(v: float) -> void: _beam.width = v; _apply_bg())
	_add_slider(vb, "beam_grain", "Зерно края (px)", 1.0, 12.0, 1.0, _beam.grain, "%.0f",
		func(v: float) -> void: _beam.grain = v; _apply_bg())
	_add_slider(vb, "beam_levels", "Ступеней градиента", 2.0, 12.0, 1.0, _beam.levels, "%.0f",
		func(v: float) -> void: _beam.levels = v; _apply_bg())

	_header(vb, "ПОРТРЕТ — ДИЗЕР ТЕНЕЙ")
	_add_slider(vb, "pt_px", "Плотность зерна (px чанка)", 1.0, 8.0, 1.0, _pt.px, "%.0f",
		func(v: float) -> void: _pt.px = v; _apply_pt())
	_add_slider(vb, "pt_levels", "Ступени цвета", 2.0, 32.0, 1.0, _pt.levels, "%.0f",
		func(v: float) -> void: _pt.levels = v; _apply_pt())
	_add_slider(vb, "pt_ceiling", "Шкала: порог теней (1 = весь арт)", 0.0, 1.0, 0.01, _pt.ceiling, "%.2f",
		func(v: float) -> void: _pt.ceiling = v; _apply_pt())
	_add_slider(vb, "pt_soft", "Мягкость границы", 0.0, 0.5, 0.01, _pt.soft, "%.2f",
		func(v: float) -> void: _pt.soft = v; _apply_pt())
	_add_slider(vb, "pt_strength", "Сила", 0.0, 1.0, 0.01, _pt.strength, "%.2f",
		func(v: float) -> void: _pt.strength = v; _apply_pt())

	_btn(vb, "Скопировать профиль (строка MOOD_FX + материалы)", _copy)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64))
	_status.text = "Крути шкалы; пресет муда сбрасывает фон на боевые значения."
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


## Строка-шкала: [подпись со значением | HSlider]. Регистрируется в _rows для синка пресетом.
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


## Выставить шкалу без сигнала (при загрузке пресета) + обновить подпись.
func _set_row(key: String, v: float) -> void:
	var r: Dictionary = _rows[key]
	(r.slider as HSlider).set_value_no_signal(v)
	(r.label as Label).text = "%s: %s" % [r.title, String(r.fmt) % v]


# ------------------------------------------------------------------- события ---

func _on_mood(i: int) -> void:
	_mood = MOODS[i]
	_fx = (ReactionScene.MOOD_FX[_mood] as Dictionary).duplicate()
	for key in ["speed", "fill", "density", "intensity"]:
		_set_row(key, _fx[key])
	_apply_bg()
	_status.text = "Пресет «%s»: боевые значения из MOOD_FX." % _mood


func _toggle_side() -> void:
	_side = "opp" if _side == "you" else "you"
	_side_btn.text = "Сторона: " + ("вы" if _side == "you" else "опп")
	_portrait.flip_h = _side == "opp"
	_apply_bg()


func _next_portrait() -> void:
	_portrait_i = (_portrait_i + 1) % PORTRAITS.size()
	_portrait.texture = PORTRAITS[_portrait_i]


# ------------------------------------------------------------------ применение --

## Та же кухня, что reaction_scene._apply_mood_bg (градиент/луч из стороны+эмоции), плюс
## лабораторные ручки: разброс цвета, ячейка/толщина/зерно линий, профиль луча.
func _apply_bg() -> void:
	var top: Color = ReactionScene.BG_YOU_TOP if _side == "you" else ReactionScene.BG_OPP_TOP
	var bottom: Color = ReactionScene.BG_YOU_BOTTOM if _side == "you" else ReactionScene.BG_OPP_BOTTOM
	var tint: Color = _fx.tint
	var k: float = _fx.intensity
	var dir: Vector2 = _fx.dir
	if _side == "opp":
		dir.x = -dir.x
	var center := top.lerp(tint, 0.55 * k)
	_bg_mat.set_shader_parameter("center_color", center)
	_bg_mat.set_shader_parameter("edge_color", bottom.lerp(tint, 0.3 * k))
	_bg_mat.set_shader_parameter("beam_color", center.lerp(_fx.line_a, 0.5))
	_bg_mat.set_shader_parameter("direction", dir)
	_bg_mat.set_shader_parameter("line_intensity", k)
	_bg_mat.set_shader_parameter("speed", _fx.speed)
	_bg_mat.set_shader_parameter("line_density", _fx.density)
	_bg_mat.set_shader_parameter("dash_scale", _dash)
	_bg_mat.set_shader_parameter("line_fill", _fx.fill)
	_bg_mat.set_shader_parameter("thick_min", _thick_min)
	_bg_mat.set_shader_parameter("thick_max", _thick_max)
	_bg_mat.set_shader_parameter("line_color_a", _fx.line_a)
	_bg_mat.set_shader_parameter("line_color_b", (_fx.line_a as Color).lerp(_fx.line_b, _spread))
	_bg_mat.set_shader_parameter("dither_px", _bg_grain)
	_bg_mat.set_shader_parameter("beam_strength", _beam.strength)
	_bg_mat.set_shader_parameter("beam_width", _beam.width)
	_bg_mat.set_shader_parameter("beam_grain", _beam.grain)
	_bg_mat.set_shader_parameter("beam_levels", _beam.levels)


func _apply_pt() -> void:
	_pt_mat.set_shader_parameter("dither_px", _pt.px)
	_pt_mat.set_shader_parameter("color_levels", _pt.levels)
	_pt_mat.set_shader_parameter("dark_ceiling", _pt.ceiling)
	_pt_mat.set_shader_parameter("dark_soft", _pt.soft)
	_pt_mat.set_shader_parameter("strength", _pt.strength)


# ---------------------------------------------------------------------- вынос ---

## Готовая строка таблицы MOOD_FX + значения для материалов (комментарием) — в буфер и
## в консоль: подобранное вставляется в reaction_scene.gd/сцену без пересчёта руками.
func _copy() -> void:
	var b := (_fx.line_a as Color).lerp(_fx.line_b, _spread)
	var line := "\t\"%s\":%s{\"tint\": %s, \"intensity\": %.2f, \"dir\": Vector2(%.2f, %.2f), \"speed\": %.1f, \"density\": %.1f, \"fill\": %.2f, \"line_a\": %s, \"line_b\": %s}," % [
		_mood, " ".repeat(maxi(1, 8 - _mood.length())), _col(_fx.tint), _fx.intensity,
		_fx.dir.x, _fx.dir.y, _fx.speed, _fx.density, _fx.fill, _col(_fx.line_a), _col(b)]
	var mats := "# материал BgMood: dash_scale=%.2f thick_min=%.2f thick_max=%.2f dither_px=%.0f beam_strength=%.2f beam_width=%.2f beam_grain=%.0f beam_levels=%.0f" % [
		_dash, _thick_min, _thick_max, _bg_grain,
		_beam.strength, _beam.width, _beam.grain, _beam.levels]
	var pt := "# материал Portrait: dither_px=%.0f color_levels=%.0f dark_ceiling=%.2f dark_soft=%.2f strength=%.2f" % [
		_pt.px, _pt.levels, _pt.ceiling, _pt.soft, _pt.strength]
	var out := line + "\n" + mats + "\n" + pt
	DisplayServer.clipboard_set(out)
	print(out)
	_status.text = "Скопировано в буфер (и в консоль)."


func _col(c: Color) -> String:
	return "Color(%.2f, %.2f, %.2f)" % [c.r, c.g, c.b]
