extends Control

## DUELOGUE — МИНИ-СЦЕНА РЕАКЦИИ (Ace Attorney-стиль). Полноэкранная подмена композиции на
## момент высказывания карты или яркого исхода: свой фон (живой муд-шейдер для реплики ИЛИ
## шейдер-спидлайны для импакта), крупный портрет персонажа, бабл с текстом (для реплики). Владелец вызовов — character_core
## («ядро персонажа вызывает анимации и отображение высказывания карты»). Узел живёт статически
## в debate_screen.tscn последним ребёнком (рендер поверх игрового UI, но НИЖЕ модального меню
## паузы — то добавляется кодом позже = выше). Одна активная реакция за раз: новый вызов
## убивает предыдущий tween, чтобы не «драться» за одни и те же свойства при частых репликах.

const ReadingPace := preload("res://duelogue/core/narrative/reading_pace.gd")
const Parallax := preload("res://duelogue/core/stage/parallax.gd")

## Лёгкий мышиный параллакс (2026-07-25, см. stage_core.gd — тот же приём на общем плане) —
## ТОЛЬКО фон. Портрет сознательно не участвует: им уже управляет кассетный tween входа
## (_prime_cassette_entrance), второй писатель той же position устроил бы ровно ту «борьбу за
## свойства», которой этот файл избегает по конструкции (см. шапку файла). Амплитуда меньше,
## чем на общем плане: фон здесь anchor-full-screen без запаса по краям (0/0/1.0/1.0, никакого
## bleed) — на глаз при подозрении на щель на кромке проверить в первую очередь.
const PARALLAX_BG := 3.0

## Модальный контракт с экраном боя: с первого кадра катсцены UI очищает hover-баблы и
## перестаёт их создавать; finished приходит только после полного fade-out.
signal scene_started
signal scene_finished

## Фазы (FADE_IN/FADE_OUT/IMPACT_HOLD) — в ReadingPace: единые часы с пейсингом контроллера
## (scene_time/impact_time), чтобы автоход никогда не обрывал идущую сцену.
const BUBBLE_BOTTOM_MARGIN := 22.0
const BUBBLE_YOU_COLOR := Color("6fd9a0")
const BUBBLE_OPP_COLOR := Color("f1a064")

## Имя приёма крупным планом за героем (DeviceLine/DeviceLabel) — калибруемые переменные,
## тюнятся в инспекторе узла без правки кода. Шрифт «стильный» тем же приёмом, что уже принят
## в combo_name_banner.gd (_make_label): чёрная обводка вместо кастомного файла шрифта —
## своего .ttf/.otf в проекте пока нет (см. duelogue/assets — шрифтовых ресурсов нет), поэтому
## это не смена гарнитуры, а её имитация размером/весом/обводкой на дефолтном шрифте темы.
@export var device_line_color: Color = Color(0.95, 0.78, 0.25, 0.9)
@export var device_line_edge_color: Color = Color(1.0, 0.97, 0.85, 1.0)
@export var device_line_fade_width: float = 0.45
@export var device_font_size: int = 64
@export var device_font_color: Color = Color(1, 1, 1, 0.92)
## Persona-style лёгкий наклон подписи (2026-08-06) — динамика без обвеса нового арта/шрифта.
## 0 = выключить, если наклон не понравится на глаз.
@export var device_label_tilt_deg: float = -4.0
## Межстрочный интервал подписи (2026-08-07) — theme-константа Label, отрицательные значения
## сжимают ниже «родного» интервала шрифта (дефолт темы на глаз ощущался разреженным на
## крупном многострочном тексте). Грубая отправная точка, как и DEVICE_FONT_STEP ниже — крутить
## в инспекторе узла по месту.
@export var device_label_line_spacing: int = -10
## Добавка к размеру/позиции бокса подписи поверх авто-раскладки по трети экрана
## (_layout_device_name/DEVICE_LABEL_THIRD) — сама треть остаётся правилом («класть в
## противоположную от портрета», см. ниже), эти два поля — точечная подстройка без правки кода
## и без выноса бокса из-под защиты авто-раскладки (растёт ВНУТРЬ экрана от внешнего края —
## см. _layout_device_name, эту гарантию она держит независимо от значения добавки).
## +245 по ширине — калибровка через device_label_lab.tscn (2026-08-08): трети экрана впритык
## не хватало, короткие имена ещё влезали, двухсловные уже подпирали перенос без места на дых.
@export var device_label_size_delta: Vector2 = Vector2(245.0, 0.0)
@export var device_label_offset: Vector2 = Vector2.ZERO

## Верхний размер сжимается сюда, если имя приёма (особенно двухсловные комбо-названия) не
## влезает по высоте в треть экрана — иначе буквы наезжали на следующую строку и ломали вёрстку.
## Шаг подобран грубо (крупный текст, разница в 2пт не читается на глаз), не самоцель точности.
const DEVICE_FONT_MIN := 26
const DEVICE_FONT_STEP := 2

## Треть экрана, куда садится подпись — считается от side (2026-08-06, правка): портрет
## говорящего всегда прижат к своей рамке-якорю (_frame_you слева/_frame_opp справа), значит
## имя приёма нужно класть в ПРОТИВОПОЛОЖНУЮ треть, иначе крупный портрет перекрывает надпись
## почти целиком. Линия при этом остаётся во всю ширину — треть только у текста.
const DEVICE_LABEL_THIRD := {
	"you": Vector2(2.0 / 3.0, 1.0),   ## портрет слева → подпись в правой трети
	"opp": Vector2(0.0, 1.0 / 3.0),   ## портрет справа → подпись в левой трети
}

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

## Кассетный вход портрета (context/director_core_v0.1.md §5) — ЧЕРНОВИК, не провалидирован
## на глаз. Пустая кассета (director её не выдал) = старое поведение, портрет молча появляется
## на месте покоя без анимации. camera_angle — множитель размера в покое (силуэт крупнее/теснее
## поверх якоря рамки из _layout_portrait); transition_in — откуда портрет стартует и каким
## почерком едет к покою. НЕ заводит новую фазу времени: длительность всегда доля УЖЕ
## существующего бюджета фазы (FADE_IN/IMPACT_HOLD), которую передаёт вызывающая сторона —
## ReadingPace остаётся единственным источником правды по времени сцены.
const RAIL_OFFSET := {
	"straight_dolly": Vector2(70.0, 0.0),
	"diagonal_sweep": Vector2(60.0, -40.0),
	"whip_snap": Vector2(24.0, 0.0),
	"slow_drift": Vector2(18.0, 30.0),
}
const CAMERA_ANGLE_SCALE := {
	"push_in_front": 1.0,
	"three_quarter_favor": 1.06,
	"low_creep": 1.0,
	"hold_steady": 1.0,
	"tight_snap": 1.12,
}

## Въезд фона крупного плана (context/director_core_v0.1.md, долли-переход) — фон въезжает с
## той же стороны, куда уехал общий план (character_core._dolly_to_speaker — наезд и выезд
## вбок там теперь одна слитная фаза, не отдельная функция). var, не const — калибруется
## вживую из dolly_lab.gd (тот же приём, что ReadingPace.
## CHARS_PER_SEC и долли-параметры character_core.gd). Живёт внутри уже переданного бюджета
## времени (FADE_IN*1.6 из show_utterance), новую фазу не заводит.
static var BG_SLIDE_TRANS: int = Tween.TRANS_LINEAR
static var BG_SLIDE_EASE: int = Tween.EASE_OUT

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
@onready var _device_line: ColorRect = $DeviceLine
@onready var _device_line_mat: ShaderMaterial = _device_line.material as ShaderMaterial
@onready var _device_label: Label = $DeviceLabel

var _gen := 0            ## генерация; новый show_* инвалидирует ожидающие await прошлого
var _active_tween: Tween  ## текущий tween (убиваем перед стартом нового — без борьбы за свойства)
var _modal_active := false

var _bg_mood_base := Vector2.ZERO
var _bg_opp_default_base := Vector2.ZERO
var _bg_you_default_base := Vector2.ZERO
var _bg_shader_base := Vector2.ZERO
var _parallax_offset := Vector2.ZERO

## Геометрия DeviceLabel из reaction_scene.tscn, снятая один раз в _ready — точка отсчёта для
## _layout_device_name. Читать оттуда каждый show_utterance напрямую с узла нельзя: узел живой
## (следующий вызов должен пересчитать бокс с нуля от исходной разметки), а не расти/съезжать
## от своего же состояния после предыдущего вызова.
var _device_label_base_top := 0.0
var _device_label_base_height := 0.0


func _ready() -> void:
	visible = false
	modulate.a = 0.0
	_bubble.pivot_offset = _bubble.size / 2.0
	_bg_mood.visible = false
	_bg_opp_default.visible = false
	_bg_you_default.visible = false
	_bg_shader.visible = false
	_device_line.visible = false
	_device_label.visible = false
	# AUTOWRAP_WORD, не _SMART (2026-08-07): _SMART форс-разбивает по буквам слово, которое не
	# влезло в ширину бокса, — это и есть баг «перенос букв слова на след. строку». Обычный WORD
	# рвёт только по пробелам; не влезающее целиком слово вместо этого выйдет за ширину — и от
	# этого страхует _fit_device_font_size (сжимает шрифт, пока не влезает САМОЕ широкое слово).
	_device_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_device_label_base_top = _device_label.offset_top
	_device_label_base_height = _device_label.offset_bottom - _device_label.offset_top
	_bg_mood_base = _bg_mood.position
	_bg_opp_default_base = _bg_opp_default.position
	_bg_you_default_base = _bg_you_default.position
	_bg_shader_base = _bg_shader.position


## Фон живёт своей жизнью даже пока модалка невидима — дёшево, и не нужно гейтить видимостью
## ради «лёгкого» эффекта (тот же подход, что у stage_core.gd на общем плане).
func _process(delta: float) -> void:
	var target := Parallax.normalized_mouse(get_viewport())
	_parallax_offset = Parallax.step(_parallax_offset, target, delta)
	var off := _parallax_offset * PARALLAX_BG
	_bg_mood.position = _bg_mood_base + off
	_bg_opp_default.position = _bg_opp_default_base + off
	_bg_you_default.position = _bg_you_default_base + off
	_bg_shader.position = _bg_shader_base + off


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


## Горизонтальный центр рамки-якоря портрета в ГЛОБАЛЬНЫХ координатах — читает
## character_core для наведения долли-камеры (context/director_core_v0.1.md): камера должна
## утыкаться туда же по X, где секунду спустя проявится портрет крупного плана, а не в центр
## актёра на общем плане — иначе переход скачет по горизонтали при смене плана.
func portrait_frame_center_x(side: String) -> float:
	var frame := _frame_you if side == "you" else _frame_opp
	return frame.global_position.x + frame.size.x * 0.5


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


func _rail_trans(rail_id: String) -> int:
	match rail_id:
		"diagonal_sweep":
			return Tween.TRANS_QUAD
		"whip_snap":
			return Tween.TRANS_ELASTIC
		"slow_drift":
			return Tween.TRANS_SINE
	return Tween.TRANS_LINEAR   ## straight_dolly и неизвестные рельсы


func _rail_ease(rail_id: String) -> int:
	if rail_id == "diagonal_sweep" or rail_id == "whip_snap":
		return Tween.EASE_OUT
	return Tween.EASE_IN_OUT   ## straight_dolly, slow_drift — мягко на обоих концах


## Переписывает _portrait.position/size на смещённый СТАРТ кассетного входа (после
## _layout_portrait, который уже поставил портрет в покой) и добавляет tween-шаг возврата к
## этому покою на уже созданный tw. Не решает, параллельно с чем это идёт — вызывающая сторона
## (show_utterance/show_impact) сама держит parallel-режим и бюджет max_duration.
func _prime_cassette_entrance(tw: Tween, side: String, cassette: Dictionary, max_duration: float) -> void:
	var rail_id := String(cassette.get("transition_in", ""))
	if cassette.is_empty() or not RAIL_OFFSET.has(rail_id):
		return
	var scale_mult: float = CAMERA_ANGLE_SCALE.get(String(cassette.get("camera_angle", "")), 1.0)
	var bottom := _portrait.position.y + _portrait.size.y
	var old_size := _portrait.size
	var target_size := old_size * scale_mult
	var target_pos := _portrait.position
	target_pos.y = bottom - target_size.y
	if side == "opp":
		target_pos.x -= target_size.x - old_size.x
	var offset: Vector2 = RAIL_OFFSET[rail_id]
	if side == "opp":
		offset.x = -offset.x
	_portrait.size = target_size
	_portrait.position = target_pos + offset
	var duration := max_duration * clampf(float(cassette.get("duration_mult", 1.0)), 0.4, 1.0)
	tw.tween_property(_portrait, "position", target_pos, duration) \
		.set_trans(_rail_trans(rail_id)).set_ease(_rail_ease(rail_id))


## Долли-переход, второй шаг (character_core._dolly_to_speaker — первый шаг: наезд и выезд
## общего плана вбок, слитые в одну фазу) — фон крупного плана въезжает с той же стороны, куда
## только что уехал общий план: визуальная эстафета, не жёсткий стык. Анимируем БАЗУ
## (_bg_*_base), НЕ .position напрямую — .position каждый кадр перезаписывает параллакс
## (_process выше), тронь его в обход базы — оба писателя дрались бы за одно свойство (см.
## шапку файла про «драться за свойства»). База — тот покой, вокруг которого параллакс
## качается; твин просто едет вместе с ним, конфликта с параллаксом нет. Живёт ВНУТРИ
## переданного max_duration (обычно FADE_IN*1.6 из show_utterance) — новую фазу времени не
## заводит, в отличие от выезда общего плана (тот делит бюджет BOARD_BEAT с наездом, тоже без
## новой фазы — см. character_core.gd).
func _slide_in_bg(side: String, use_static: bool, tw: Tween, max_duration: float) -> void:
	var dir := 1.0 if side == "opp" else -1.0
	var start_offset := Vector2(dir * size.x, 0.0)
	var base_name := "_bg_opp_default_base" if (use_static and side == "opp") \
		else "_bg_you_default_base" if use_static else "_bg_mood_base"
	var rest: Vector2 = get(base_name)
	set(base_name, rest + start_offset)
	tw.tween_property(self, base_name, rest, max_duration) \
		.set_trans(BG_SLIDE_TRANS).set_ease(BG_SLIDE_EASE)


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


## Имя приёма крупным планом: линия и текст сидят МЕЖДУ фоновыми шейдерами (BgMood/BgShader,
## объявлены раньше в дереве) и портретом (Portrait, объявлен позже) — герой всегда поверх,
## линия всегда под текстом, но над фоном (порядок задан порядком узлов в reaction_scene.tscn,
## не z_index). Пустое имя = ничего не показываем, старые вызовы show_utterance() без этого
## аргумента ведут себя как раньше. Бокс = треть экрана (DEVICE_LABEL_THIRD, «противоположная
## портрету») плюс калибруемая добавка device_label_size_delta/device_label_offset поверх неё.
func _layout_device_name(name: String, side: String) -> void:
	var shown := name != ""
	_device_line.visible = shown
	_device_label.visible = shown
	if not shown:
		return
	_device_line_mat.set_shader_parameter("line_color", device_line_color)
	_device_line_mat.set_shader_parameter("edge_color", device_line_edge_color)
	_device_line_mat.set_shader_parameter("fade_width", device_line_fade_width)
	var third: Vector2 = DEVICE_LABEL_THIRD.get(side, DEVICE_LABEL_THIRD["you"])
	# ОДИН анкор на оба края (не anchor_left=third.x/anchor_right=third.y раздельно — регрессия
	# 2026-08-08, чинили её же: anchor-разница УЖЕ давала ширину трети, а offset_right поверх
	# неё добавлял её ЕЩЁ РАЗ, бокс выходил вдвое шире трети и «you» вылезал за правый край
	# экрана). Ширина теперь ЦЕЛИКОМ из box_size через offset_left/right от ОДНОЙ точки анкора —
	# внешнего края экрана со стороны side ("opp" якорится в 0.0 и растёт вправо, "you" — в 1.0
	# и растёт влево), анкор больше не участвует в ширине вообще.
	var outer_anchor := third.x if side == "opp" else third.y
	_device_label.anchor_left = outer_anchor
	_device_label.anchor_right = outer_anchor
	# Абсолютные offset_*, не += к текущим: узел живой и держит значения ПРЕДЫДУЩЕГО вызова,
	# инкремент поверх них означал бы, что бокс уезжает/растёт с каждой репликой подряд.
	# Пересчитываем с нуля от снятой в _ready базы (_device_label_base_top/height — исходная
	# разметка из reaction_scene.tscn).
	var box_size := Vector2(size.x * (third.y - third.x), _device_label_base_height) \
		+ device_label_size_delta
	if side == "opp":
		_device_label.offset_left = device_label_offset.x
		_device_label.offset_right = device_label_offset.x + box_size.x
	else:
		_device_label.offset_left = device_label_offset.x - box_size.x
		_device_label.offset_right = device_label_offset.x
	_device_label.offset_top = _device_label_base_top + device_label_offset.y
	_device_label.offset_bottom = _device_label.offset_top + box_size.y
	_device_label.pivot_offset = box_size / 2.0
	_device_label.rotation_degrees = device_label_tilt_deg
	_device_label.add_theme_constant_override("line_spacing", device_label_line_spacing)
	_device_label.text = name
	_device_label.add_theme_font_size_override("font_size",
		_fit_device_font_size(name, box_size.x, box_size.y))
	_device_label.add_theme_color_override("font_color", device_font_color)


## Сжимает размер шрифта, пока перенесённый по словам текст не влезает в отведённый бокс —
## иначе двухсловные имена (частые у combo_name) переполняли Label и наезжали на соседние
## строки/узлы. Пол задан DEVICE_FONT_MIN — дальше не сжимаем, короткое слово почти никогда
## сюда не доходит. Держит ДВЕ проверки, а не одну: (a) высота переноса по словам в box_height —
## как раньше, и (b) ширина САМОГО ШИРОКОГО ОТДЕЛЬНОГО СЛОВА в box_width — без неё Label в
## режиме AUTOWRAP_WORD (см. _ready) просто вылезал бы этим словом за край бокса, ничего не
## сжимая, раз общая многострочная высота уже «влезала».
func _fit_device_font_size(name: String, box_width: float, box_height: float) -> int:
	var font := _device_label.get_theme_font("font")
	if font == null or box_width <= 0.0:
		return device_font_size
	var fs := device_font_size
	while fs > DEVICE_FONT_MIN:
		if _device_name_fits(font, name, box_width, box_height, fs):
			break
		fs -= DEVICE_FONT_STEP
	return fs


## Правда, только если при размере шрифта fs ни одно слово не шире box_width (иначе
## AUTOWRAP_WORD не переносит его по буквам, а молча вылезает за бокс — тот самый баг, который
## _fit_device_font_size обязана предотвратить) И перенесённый по словам текст умещается по
## высоте в box_height. Слова режутся по пробелу — реальные имена приёмов (Grammar.CARD_DEVICE,
## combo_register.gd) дефисов/переносов внутри слова не используют, более тонкий разбор не нужен.
func _device_name_fits(font: Font, name: String, box_width: float, box_height: float,
	fs: int) -> bool:
	for word in name.split(" ", false):
		if font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > box_width:
			return false
	var measured := font.get_multiline_string_size(
		name, HORIZONTAL_ALIGNMENT_CENTER, box_width, fs)
	return measured.y <= box_height


## Реакция-реплика: сторона side говорит text (реплика карты), портрет portrait_tex,
## mood — стейт говорящего (§16) — красит живой фон профилем эмоции (MOOD_FX).
## Длительность сцены НЕ фиксирована — определяется скоростью печати текста в бабле плюс
## паузой на дочитывание (см. ReadingPace — общая формула с пейсингом battle_controller).
func show_utterance(side: String, text: String, portrait_tex: Texture2D, mood: String = "",
	portrait_flip_h: bool = false, eyebrow: String = "", cassette: Dictionary = {},
	device_name: String = "") -> void:
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
	_layout_device_name(device_name, side)
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
	_prime_cassette_entrance(_active_tween, side, cassette, ReadingPace.FADE_IN * 1.6)
	_slide_in_bg(side, use_static_statement_background, _active_tween, ReadingPace.FADE_IN * 1.6)
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
func show_impact(side: String, portrait_tex: Texture2D, intensity: float = 1.0,
	portrait_flip_h: bool = false, cassette: Dictionary = {}) -> void:
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
	_device_line.visible = false
	_device_label.visible = false
	modulate.a = 1.0
	if _active_tween:
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	_active_tween.tween_method(_set_progress, 0.0, clampf(intensity, 0.0, 1.0), ReadingPace.IMPACT_HOLD * 0.5)
	_prime_cassette_entrance(_active_tween, side, cassette, ReadingPace.IMPACT_HOLD * 0.5)
	_active_tween.set_parallel(false)
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
	if _modal_active:
		_modal_active = false
		scene_finished.emit()
