extends Control

## DUELOGUE — МИНИ-СЦЕНА РЕАКЦИИ (Ace Attorney-стиль). Полноэкранная подмена композиции на
## момент высказывания карты или яркого исхода: свой фон (картинка ИЛИ шейдер-спидлайны),
## крупный портрет персонажа, бабл с текстом (для реплики). Владелец вызовов — character_core
## («ядро персонажа вызывает анимации и отображение высказывания карты»). Узел живёт статически
## в debate_screen.tscn последним ребёнком (рендер поверх игрового UI, но НИЖЕ модального меню
## паузы — то добавляется кодом позже = выше). Одна активная реакция за раз: новый вызов
## убивает предыдущий tween, чтобы не «драться» за одни и те же свойства при частых репликах.

const ReadingPace := preload("res://duelogue/core/narrative/reading_pace.gd")

## Фазы (FADE_IN/FADE_OUT/IMPACT_HOLD) — в ReadingPace: единые часы с пейсингом контроллера
## (scene_time/impact_time), чтобы автоход никогда не обрывал идущую сцену.
const BUBBLE_MARGIN := 32.0  ## отступ бабла от края экрана — бабл держится СО СТОРОНЫ,
                              ## противоположной портрету, чтобы не лечь на лицо/жест

## Фон крупного плана — не картинка, а градиент по стороне (§UI: зелёный "вы"/оранжевый
## "опп", те же тона что и BarYouLabel/BarOppLabel в debate_screen.tscn). Генерятся один раз
## в _ready, дальше BgImage.texture просто переключается по side.
const BG_YOU_TOP := Color(0.086, 0.2, 0.15, 1)
const BG_YOU_BOTTOM := Color(0.02, 0.05, 0.045, 1)
const BG_OPP_TOP := Color(0.22, 0.13, 0.06, 1)
const BG_OPP_BOTTOM := Color(0.05, 0.03, 0.02, 1)

@onready var _bg_image: TextureRect = $BgImage
@onready var _bg_shader: ColorRect = $BgShader
@onready var _shader_mat: ShaderMaterial = _bg_shader.material as ShaderMaterial
@onready var _portrait: TextureRect = $Portrait
## Рамки-якоря по стороне (двигаются/масштабируются в редакторе, как SlotYou/SlotOpp в
## stage.tscn) — задают угол + высоту, под которую портрет ложится крупным планом снизу.
@onready var _frame_you: Control = %PortraitFrameYou
@onready var _frame_opp: Control = %PortraitFrameOpp
@onready var _bubble: Control = $Bubble
@onready var _bubble_label: Label = $Bubble/Label

var _gen := 0            ## генерация; новый show_* инвалидирует ожидающие await прошлого
var _active_tween: Tween  ## текущий tween (убиваем перед стартом нового — без борьбы за свойства)
var _bg_you: GradientTexture2D
var _bg_opp: GradientTexture2D


func _ready() -> void:
	visible = false
	modulate.a = 0.0
	_bubble.pivot_offset = _bubble.size / 2.0
	_bg_shader.visible = false
	_bg_you = _make_bg_gradient(BG_YOU_TOP, BG_YOU_BOTTOM)
	_bg_opp = _make_bg_gradient(BG_OPP_TOP, BG_OPP_BOTTOM)


## Вертикальный градиент 8×8 (растягивается TextureRect'ом на весь экран — размер текстуры
## не важен, важны только цвета в двух точках).
func _make_bg_gradient(top: Color, bottom: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([top, bottom])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2(0.5, 0.0)
	t.fill_to = Vector2(0.5, 1.0)
	t.width = 8
	t.height = 8
	return t


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


## Бабл держится со стороны, противоположной портрету, чтобы не перекрывать лицо/жест.
func _layout_bubble(side: String) -> void:
	var w := _bubble.size.x
	if side == "you":
		_bubble.position.x = 1152.0 - BUBBLE_MARGIN - w
	else:
		_bubble.position.x = BUBBLE_MARGIN


## Спокойная реакция: сторона side говорит text (реплика карты), портрет portrait_tex.
## Длительность сцены НЕ фиксирована — определяется скоростью печати текста в бабле плюс
## паузой на дочитывание (см. ReadingPace — общая формула с пейсингом battle_controller).
func show_utterance(side: String, text: String, portrait_tex: Texture2D) -> void:
	_gen += 1
	var my_gen := _gen
	_bg_image.texture = _bg_you if side == "you" else _bg_opp
	_bg_image.visible = true
	_bg_shader.visible = false
	_layout_portrait(side, portrait_tex)
	_portrait.texture = portrait_tex
	_portrait.flip_h = side == "opp"
	_layout_bubble(side)
	_bubble.visible = true
	_bubble_label.text = text
	_bubble_label.visible_ratio = 0.0
	_bubble.scale = Vector2(0.7, 0.7)
	visible = true
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
func show_impact(side: String, portrait_tex: Texture2D, intensity: float = 1.0) -> void:
	_gen += 1
	var my_gen := _gen
	_bg_image.visible = false
	_bg_shader.visible = true
	_shader_mat.set_shader_parameter("progress", 0.0)
	_layout_portrait(side, portrait_tex)
	_portrait.texture = portrait_tex
	_portrait.flip_h = side == "opp"
	_bubble.visible = false
	visible = true
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


func _fade_out(my_gen: int) -> void:
	if _active_tween:
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.tween_property(self, "modulate:a", 0.0, ReadingPace.FADE_OUT)
	await _active_tween.finished
	if my_gen != _gen:
		return
	visible = false
