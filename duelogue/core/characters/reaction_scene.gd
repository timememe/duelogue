extends Control

## DUELOGUE — МИНИ-СЦЕНА РЕАКЦИИ (Ace Attorney-стиль). Полноэкранная подмена композиции на
## момент высказывания карты или яркого исхода: свой фон (живой муд-шейдер для реплики ИЛИ
## шейдер-спидлайны для импакта), крупный портрет персонажа, бабл с текстом (для реплики). Владелец вызовов — character_core
## («ядро персонажа вызывает анимации и отображение высказывания карты»). Узел живёт статически
## в debate_screen.tscn последним ребёнком (рендер поверх игрового UI, но НИЖЕ модального меню
## паузы — то добавляется кодом позже = выше). Одна активная реакция за раз: новый вызов
## убивает предыдущий tween, чтобы не «драться» за одни и те же свойства при частых репликах.

const ReadingPace := preload("res://duelogue/core/narrative/reading_pace.gd")

## Модальный контракт с экраном боя: с первого кадра катсцены UI очищает hover-баблы и
## перестаёт их создавать; finished приходит только после полного fade-out.
signal scene_started
signal scene_finished

## Фазы (FADE_IN/FADE_OUT/IMPACT_HOLD) — в ReadingPace: единые часы с пейсингом контроллера
## (scene_time/impact_time), чтобы автоход никогда не обрывал идущую сцену.
const BUBBLE_BOTTOM_MARGIN := 22.0
const BUBBLE_YOU_COLOR := Color("6fd9a0")
const BUBBLE_OPP_COLOR := Color("f1a064")

## Фон крупного плана — аниме-спидлайны (mood_bg.gdshader): длинные штрихи-«веретёна» летят
## по направлению эмоции, их края/хвосты РАССЫПАЮТСЯ ДИЗЕРОМ (зерно живёт в самих линиях,
## фон-градиент гладкий). Градиент — цвета стороны (§UI: зелёный "вы"/оранжевый "опп", тона
## BarYouLabel/BarOppLabel в debate_screen.tscn) с подмесом эмоции. Портрету — свой дизер
## ТОЛЬКО ПО ТЕНЯМ (dither.gdshader на ноде Portrait, dark_ceiling; тюнится в инспекторе).
const BG_YOU_TOP := Color(0.086, 0.2, 0.15, 1)
const BG_YOU_BOTTOM := Color(0.02, 0.05, 0.045, 1)
const BG_OPP_TOP := Color(0.22, 0.13, 0.06, 1)
const BG_OPP_BOTTOM := Color(0.05, 0.03, 0.02, 1)
const STATIC_STATEMENT_MOODS := ["", "declare", "idle"]

## Муд → профиль спидлайн-фона (словарь стейтов §16 — тот же, что STATE_TEX character_core;
## муд без строки здесь падает в нейтральный idle-профиль, система рабочая всегда).
## intensity — МОЩНОСТЬ (плотность зерна линий + подмес tint в градиент + дыхание луча;
## регистр уже закодирован в муде: burst-панч = максимум); dir — направление В СИСТЕМЕ «you»
## (вперёд = +x, к оппоненту; для "opp" x зеркалится): атака рвётся вперёд, паника осыпается
## вниз, кураж лениво всплывает, юление пятится; speed — темп полёта; density — рядов
## поперёк; fill — длина мазка; line_a ↔ line_b — перелив цвета вдоль линий (line_a также
## подсвечивает луч); tint — подмес в градиент. КОМФОРТ-ДИАПАЗОНЫ (калибровка fx_lab,
## 2026-07-09, держимся их): speed ≥ 1, fill 0.42..1, density 25..42; ячейка вдоль (0.5)
## и толщина (0.3..0.8, своя у каждого ряда) — канон, живут дефолтами шейдера.
const MOOD_FX := {
	"declare": {"tint": Color(1.0, 0.93, 0.78), "intensity": 0.35, "dir": Vector2(1.0, 0.0), "speed": 1.2, "density": 25.0, "fill": 0.5, "line_a": Color(1.0, 0.96, 0.86), "line_b": Color(0.7, 0.78, 0.8)},
	"hold":    {"tint": Color(1.0, 0.28, 0.16), "intensity": 0.55, "dir": Vector2(-1.0, 0.15), "speed": 2.2, "density": 30.0, "fill": 0.55, "line_a": Color(1.0, 0.45, 0.3), "line_b": Color(0.85, 0.2, 0.12)},
	"attack":  {"tint": Color(1.0, 0.42, 0.12), "intensity": 0.75, "dir": Vector2(1.0, 0.0), "speed": 4.0, "density": 36.0, "fill": 0.7, "line_a": Color(1.0, 0.6, 0.25), "line_b": Color(1.0, 0.3, 0.1)},
	"gotcha":  {"tint": Color(1.0, 0.84, 0.25), "intensity": 0.7, "dir": Vector2(1.0, 0.5), "speed": 3.0, "density": 32.0, "fill": 0.6, "line_a": Color(1.0, 0.9, 0.45), "line_b": Color(1.0, 0.7, 0.15)},
	"burst":   {"tint": Color(1.0, 0.15, 0.1), "intensity": 1.0, "dir": Vector2(1.0, 0.0), "speed": 6.5, "density": 42.0, "fill": 0.9, "line_a": Color(1.0, 0.95, 0.9), "line_b": Color(1.0, 0.25, 0.15)},
	"evade":   {"tint": Color(0.62, 0.66, 0.45), "intensity": 0.45, "dir": Vector2(-0.8, -0.35), "speed": 1.6, "density": 27.0, "fill": 0.45, "line_a": Color(0.75, 0.78, 0.6), "line_b": Color(0.55, 0.6, 0.42)},
	"swagger": {"tint": Color(0.95, 0.68, 0.3), "intensity": 0.5, "dir": Vector2(0.25, -1.0), "speed": 1.0, "density": 25.0, "fill": 0.55, "line_a": Color(1.0, 0.85, 0.5), "line_b": Color(0.95, 0.65, 0.28)},
	"panic":   {"tint": Color(0.5, 0.6, 0.8), "intensity": 0.65, "dir": Vector2(0.0, 1.0), "speed": 4.5, "density": 40.0, "fill": 0.5, "line_a": Color(0.7, 0.8, 1.0), "line_b": Color(0.4, 0.5, 0.75)},
	"idle":    {"tint": Color(1.0, 1.0, 1.0), "intensity": 0.15, "dir": Vector2(1.0, 0.0), "speed": 1.0, "density": 25.0, "fill": 0.42, "line_a": Color(0.9, 0.9, 0.9), "line_b": Color(0.7, 0.7, 0.7)},
}

@onready var _bg_mood: ColorRect = $BgMood
@onready var _mood_mat: ShaderMaterial = _bg_mood.material as ShaderMaterial
@onready var _bg_opp_default: TextureRect = $BgOppDefault
@onready var _bg_you_default: TextureRect = $BgYouDefault
@onready var _bg_shader: ColorRect = $BgShader
@onready var _shader_mat: ShaderMaterial = _bg_shader.material as ShaderMaterial
@onready var _portrait: TextureRect = $Portrait
## Рамки-якоря по стороне (двигаются/масштабируются в редакторе, как ActorYou/ActorOpp в
## stage.tscn) — задают угол + высоту, под которую портрет ложится крупным планом снизу.
@onready var _frame_you: Control = %PortraitFrameYou
@onready var _frame_opp: Control = %PortraitFrameOpp
@onready var _bubble: Control = $Bubble
@onready var _bubble_frame: ColorRect = $Bubble/Frame
@onready var _bubble_frame_mat: ShaderMaterial = _bubble_frame.material as ShaderMaterial
@onready var _speaker_plate: ColorRect = %SpeakerPlate
@onready var _speaker_label: Label = %SpeakerLabel
@onready var _eyebrow: Label = $Bubble/Eyebrow
@onready var _bubble_label: Label = $Bubble/Label

var _gen := 0            ## генерация; новый show_* инвалидирует ожидающие await прошлого
var _active_tween: Tween  ## текущий tween (убиваем перед стартом нового — без борьбы за свойства)
var _modal_active := false

## Ace Attorney-стамп (2026-07-22, боевой каталог resolved-by-construction): шипастая вспышка
## со словом ПЕРЕД обычной позой-реакцией. Построен процедурно (Polygon2D-звезда), без новых
## текстур — тот же принцип, что у остального VFX проекта (шейдеры/процедурные линии).
const STAMP_TRAP_COLOR := Color(0.82, 0.14, 0.14)   # ловушка — тревожный красный
const STAMP_GUARD_COLOR := Color(0.95, 0.76, 0.12)  # защита — уверенное золото
var _stamp_poly: Polygon2D
var _stamp_label: Label


func _ready() -> void:
	visible = false
	modulate.a = 0.0
	_bubble.pivot_offset = _bubble.size / 2.0
	_bg_mood.visible = false
	_bg_opp_default.visible = false
	_bg_you_default.visible = false
	_bg_shader.visible = false


func is_modal_active() -> bool:
	return _modal_active


## Новый show_* может заменить уже идущую реакцию. В таком случае модальность не моргает:
## started/finished обрамляют всю непрерывную цепочку крупных планов.
func _begin_modal_scene() -> void:
	if not _modal_active:
		_modal_active = true
		scene_started.emit()
	visible = true


## Юниформы спидлайн-фона из профиля MOOD_FX. Градиент замешивается здесь, на CPU:
## середина — верхний тон стороны + эмоция (cap 55% на пике мощности), края — нижний тон
## с подмесом мягче; оттенок владельца хода читается всегда. Луч по центру красится смесью
## середины и светлого цвета линий (сила/ширина/зерно луча — дефолты шейдера, тюнятся на
## материале BgMood). Направление профиля задано «лицом вперёд» (+x = к оппоненту) —
## для стороны "opp" зеркалится по x.
func _apply_mood_bg(side: String, mood: String) -> void:
	var fx: Dictionary = MOOD_FX.get(mood, MOOD_FX["idle"])
	var top := BG_YOU_TOP if side == "you" else BG_OPP_TOP
	var bottom := BG_YOU_BOTTOM if side == "you" else BG_OPP_BOTTOM
	var tint: Color = fx.tint
	var k: float = fx.intensity
	var dir: Vector2 = fx.dir
	if side == "opp":
		dir.x = -dir.x
	var center := top.lerp(tint, 0.55 * k)
	_mood_mat.set_shader_parameter("center_color", center)
	_mood_mat.set_shader_parameter("edge_color", bottom.lerp(tint, 0.3 * k))
	_mood_mat.set_shader_parameter("beam_color", center.lerp(fx.line_a, 0.5))
	_mood_mat.set_shader_parameter("direction", dir)
	_mood_mat.set_shader_parameter("line_intensity", k)
	_mood_mat.set_shader_parameter("speed", fx.speed)
	_mood_mat.set_shader_parameter("line_density", fx.density)
	_mood_mat.set_shader_parameter("line_fill", fx.fill)
	_mood_mat.set_shader_parameter("line_color_a", fx.line_a)
	_mood_mat.set_shader_parameter("line_color_b", fx.line_b)


func _uses_static_statement_background(mood: String) -> bool:
	return mood in STATIC_STATEMENT_MOODS


## Крупный план: портрет прижат к своей рамке-якорю (left-anchor для "you", right-anchor для
## "opp") и растянут по её высоте с сохранением пропорций текста — так композиция реактов
## (поясной кадр, жест до края) ложится крупно и «от низа рамки», не искажаясь.
func _layout_portrait(side: String, tex: Texture2D) -> void:
	if tex == null:
		return
	var frame := _frame_you if side == "you" else _frame_opp
	var tex_size := tex.get_size()
	var h := frame.size.y
	var w := h * (tex_size.x / maxf(1.0, tex_size.y))
	_portrait.size = Vector2(w, h)
	_portrait.position.y = frame.position.y
	if side == "you":
		_portrait.position.x = frame.position.x
	else:
		_portrait.position.x = frame.position.x + frame.size.x - w


## Реплика всегда внизу по центру: взгляд игрока остаётся на одной вертикальной оси,
## а яркий портрет может менять сторону без скачка текста вправо-влево.
func _layout_bubble(side: String) -> void:
	_bubble.position = Vector2(
		roundf((size.x - _bubble.size.x) * 0.5),
		size.y - _bubble.size.y - BUBBLE_BOTTOM_MARGIN
	)
	var speaker_color := BUBBLE_YOU_COLOR if side == "you" else BUBBLE_OPP_COLOR
	_speaker_label.text = "ВЫ" if side == "you" else "ОППОНЕНТ"
	_speaker_plate.color = speaker_color.darkened(0.58)
	_speaker_label.add_theme_color_override("font_color", speaker_color.lightened(0.22))
	_bubble_frame_mat.set_shader_parameter("border_color", speaker_color.lightened(0.12))


## Реакция-реплика: сторона side говорит text (реплика карты), портрет portrait_tex,
## mood — стейт говорящего (§16) — красит живой фон профилем эмоции (MOOD_FX).
## Длительность сцены НЕ фиксирована — определяется скоростью печати текста в бабле плюс
## паузой на дочитывание (см. ReadingPace — общая формула с пейсингом battle_controller).
func show_utterance(side: String, text: String, portrait_tex: Texture2D, mood: String = "",
	portrait_flip_h: bool = false, eyebrow: String = "") -> void:
	_gen += 1
	var my_gen := _gen
	_begin_modal_scene()
	var use_static_statement_background := _uses_static_statement_background(mood)
	_bg_opp_default.visible = use_static_statement_background and side == "opp"
	_bg_you_default.visible = use_static_statement_background and side == "you"
	_bg_mood.visible = not use_static_statement_background
	if not use_static_statement_background:
		_apply_mood_bg(side, mood)
	_bg_shader.visible = false
	_layout_portrait(side, portrait_tex)
	_portrait.texture = portrait_tex
	_portrait.flip_h = portrait_flip_h
	_layout_bubble(side)
	_bubble.visible = true
	_eyebrow.visible = eyebrow != ""
	_eyebrow.text = eyebrow
	_bubble_label.offset_top = 12.0
	_bubble_label.text = text
	_bubble_label.visible_ratio = 0.0
	_bubble.scale = Vector2(0.7, 0.7)
	if _active_tween:
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	_active_tween.tween_property(self, "modulate:a", 1.0, ReadingPace.FADE_IN)
	_active_tween.tween_property(_bubble, "scale", Vector2.ONE, ReadingPace.FADE_IN * 1.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await _active_tween.finished
	if my_gen != _gen:
		return
	# Печать текста — длительность сцены живёт здесь, а не по константному таймеру.
	# ReadingPace — общая формула с battle_controller (его пейсинг ждёт ровно столько же).
	_active_tween = create_tween()
	_active_tween.tween_property(_bubble_label, "visible_ratio", 1.0, ReadingPace.type_time(text))
	await _active_tween.finished
	if my_gen != _gen:
		return
	await get_tree().create_timer(ReadingPace.HOLD_AFTER_TEXT).timeout
	if my_gen != _gen:
		return
	await _fade_out(my_gen)


## Яркий исход (клинч landed): фон-шейдер вместо картинки, без бабла, короче и резче.
## intensity 0..1 — пик спидлайнов (тяжесть исхода: снят довод / рухнула рамка).
func show_impact(side: String, portrait_tex: Texture2D, intensity: float = 1.0, portrait_flip_h: bool = false) -> void:
	_gen += 1
	var my_gen := _gen
	_begin_modal_scene()
	_bg_opp_default.visible = false
	_bg_you_default.visible = false
	_bg_mood.visible = false
	_bg_shader.visible = true
	_shader_mat.set_shader_parameter("progress", 0.0)
	_layout_portrait(side, portrait_tex)
	_portrait.texture = portrait_tex
	_portrait.flip_h = portrait_flip_h
	_bubble.visible = false
	modulate.a = 1.0
	if _active_tween:
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.tween_method(_set_progress, 0.0, clampf(intensity, 0.0, 1.0), ReadingPace.IMPACT_HOLD * 0.5)
	_active_tween.tween_method(_set_progress, clampf(intensity, 0.0, 1.0), 0.0, ReadingPace.IMPACT_HOLD * 0.5)
	await _active_tween.finished
	if my_gen != _gen:
		return
	await _fade_out(my_gen)


func _set_progress(p: float) -> void:
	_shader_mat.set_shader_parameter("progress", p)


## Строит узлы стампа лениво при первом вызове — не трогаем .tscn руками, всё процедурно.
func _ensure_stamp() -> void:
	if _stamp_poly != null:
		return
	_stamp_poly = Polygon2D.new()
	_stamp_poly.polygon = _burst_points(230.0, 148.0, 13)
	add_child(_stamp_poly)
	_stamp_label = Label.new()
	_stamp_label.add_theme_font_size_override("font_size", 60)
	_stamp_label.add_theme_color_override("font_color", Color.WHITE)
	_stamp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_stamp_label.add_theme_constant_override("outline_size", 10)
	_stamp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stamp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stamp_label.size = Vector2(460.0, 210.0)
	_stamp_label.pivot_offset = _stamp_label.size / 2.0
	add_child(_stamp_label)
	_stamp_poly.visible = false
	_stamp_label.visible = false


## Шипастый (звёздный) контур — 2×spikes точек, чередование внешнего/внутреннего радиуса,
## центрировано на (0,0): Polygon2D/Control вращаются и масштабируются вокруг своего же центра.
func _burst_points(outer: float, inner: float, spikes: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in spikes * 2:
		var r := outer if i % 2 == 0 else inner
		var a := TAU * float(i) / float(spikes * 2) - PI / 2.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


## Ace Attorney-стамп: шипастая вспышка со словом (ЗАЩИТА!/ЛОВУШКА!) ДО позы-реакции владельца
## (character_core вызывает show_utterance сразу после). Панч-ин с перелётом (тот же почерк,
## что у баббла реплики: TRANS_BACK/EASE_OUT) → короткая пауза → панч-аут с фейдом.
func show_combo_stamp(word: String, is_trap: bool) -> void:
	_ensure_stamp()
	_gen += 1
	var my_gen := _gen
	_begin_modal_scene()
	modulate.a = 1.0
	_bg_opp_default.visible = false
	_bg_you_default.visible = false
	_bg_mood.visible = false
	_bg_shader.visible = false
	_bubble.visible = false
	_stamp_poly.color = STAMP_TRAP_COLOR if is_trap else STAMP_GUARD_COLOR
	_stamp_poly.position = size / 2.0
	_stamp_poly.rotation = deg_to_rad(-7.0)
	_stamp_label.text = word
	_stamp_label.position = size / 2.0 - _stamp_label.size / 2.0
	_stamp_label.rotation = deg_to_rad(-7.0)
	_stamp_poly.modulate.a = 1.0
	_stamp_label.modulate.a = 1.0
	_stamp_poly.scale = Vector2(0.15, 0.15)
	_stamp_label.scale = Vector2(0.15, 0.15)
	_stamp_poly.visible = true
	_stamp_label.visible = true
	if _active_tween:
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	_active_tween.tween_property(_stamp_poly, "scale", Vector2.ONE, ReadingPace.STAMP_PUNCH_IN) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_stamp_label, "scale", Vector2.ONE, ReadingPace.STAMP_PUNCH_IN) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await _active_tween.finished
	if my_gen != _gen:
		return
	await get_tree().create_timer(ReadingPace.STAMP_HOLD).timeout
	if my_gen != _gen:
		return
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	_active_tween.tween_property(_stamp_poly, "scale", Vector2(1.25, 1.25), ReadingPace.STAMP_PUNCH_OUT)
	_active_tween.tween_property(_stamp_label, "scale", Vector2(1.25, 1.25), ReadingPace.STAMP_PUNCH_OUT)
	_active_tween.tween_property(_stamp_poly, "modulate:a", 0.0, ReadingPace.STAMP_PUNCH_OUT)
	_active_tween.tween_property(_stamp_label, "modulate:a", 0.0, ReadingPace.STAMP_PUNCH_OUT)
	await _active_tween.finished
	if my_gen != _gen:
		return
	_stamp_poly.visible = false
	_stamp_label.visible = false


func _fade_out(my_gen: int) -> void:
	if _active_tween:
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.tween_property(self, "modulate:a", 0.0, ReadingPace.FADE_OUT)
	await _active_tween.finished
	if my_gen != _gen:
		return
	visible = false
	if _modal_active:
		_modal_active = false
		scene_finished.emit()
