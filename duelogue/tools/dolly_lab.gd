extends Control

## DUELOGUE — ДОЛЛИ-ЛАБОРАТОРИЯ (дев-тул, открыть dolly_lab.tscn и F6): ручная калибровка
## долли-наезда общего плана и перехода в крупный план, по образцу fx_lab.gd. НЕ копия логики —
## сцена внутри лабы это настоящие stage.tscn + reaction_scene.tscn + CharacterCore, а шкалы
## крутят РЕАЛЬНЫЕ параметры CharacterCore (static var, не const — специально ради этого, см.
## character_core.gd). Кнопка «Играть» идёт через тот же EventBus.utterance, что и боевой код —
## тюнингуем боевой путь напрямую, не отдельную лабораторную копию, которая могла бы разъехаться
## с реальностью.

const CharacterCore := preload("res://duelogue/core/characters/character_core.gd")
const StageScene := preload("res://duelogue/core/stage/stage.tscn")
const ReactionScene := preload("res://duelogue/core/characters/reaction_scene.tscn")
## ReactionScene выше — это .tscn (PackedScene, только для .instantiate()), у него нет
## статических переменных скрипта. BG_SLIDE_TRANS/EASE живут в самом reaction_scene.gd —
## для чтения/записи static var нужен const именно на скрипт, как CharacterCore выше уже
## (та же ошибка, из-за которой упали строки с ReactionScene.BG_SLIDE_* = ...).
const ReactionSceneScript := preload("res://duelogue/core/characters/reaction_scene.gd")
const ReadingPace := preload("res://duelogue/core/narrative/reading_pace.gd")

## Канон-канвас проекта (project.godot: дефолтный вьюпорт, stretch_mode=canvas_items) — та же
## система координат, в которой авторится stage.tscn/reaction_scene.tscn (абсолютные позиции
## акторов и т.п.), поэтому превью должно быть именно этого размера, не произвольного.
const CANVAS_SIZE := Vector2(1152.0, 648.0)
## Полный канвас в панель рядом не влезает (сам почти равен дефолтному окну) — превью уменьшено,
## панель встаёт справа. Множитель посчитан от него же, чтобы не разъехаться при правке.
const PREVIEW_SCALE := 0.6

const MOODS := ["declare", "hold", "attack", "gotcha", "burst", "evade", "swagger", "panic", "idle"]
const SAMPLE_TEXT := {
	"you": "Проверка долли-камеры на вашей стороне.",
	"opp": "Проверка долли-камеры на стороне оппонента.",
}
const TRANS_OPTIONS := [
	["Linear", Tween.TRANS_LINEAR], ["Sine", Tween.TRANS_SINE], ["Quad", Tween.TRANS_QUAD],
	["Cubic", Tween.TRANS_CUBIC], ["Quart", Tween.TRANS_QUART], ["Back", Tween.TRANS_BACK],
	["Elastic", Tween.TRANS_ELASTIC], ["Expo", Tween.TRANS_EXPO], ["Bounce", Tween.TRANS_BOUNCE],
]
const EASE_OPTIONS := [
	["In", Tween.EASE_IN], ["Out", Tween.EASE_OUT],
	["In-Out", Tween.EASE_IN_OUT], ["Out-In", Tween.EASE_OUT_IN],
]
const TRANS_NAMES := {
	Tween.TRANS_LINEAR: "TRANS_LINEAR", Tween.TRANS_SINE: "TRANS_SINE",
	Tween.TRANS_QUAD: "TRANS_QUAD", Tween.TRANS_CUBIC: "TRANS_CUBIC",
	Tween.TRANS_QUART: "TRANS_QUART", Tween.TRANS_BACK: "TRANS_BACK",
	Tween.TRANS_ELASTIC: "TRANS_ELASTIC", Tween.TRANS_EXPO: "TRANS_EXPO",
	Tween.TRANS_BOUNCE: "TRANS_BOUNCE",
}
const EASE_NAMES := {
	Tween.EASE_IN: "EASE_IN", Tween.EASE_OUT: "EASE_OUT",
	Tween.EASE_IN_OUT: "EASE_IN_OUT", Tween.EASE_OUT_IN: "EASE_OUT_IN",
}

var _side := "you"
var _mood := "declare"
var _side_btn: Button
var _status: Label
var _chars: CharacterCore


func _ready() -> void:
	var frame := _make_stage_frame()
	add_child(frame)

	var stage := StageScene.instantiate()
	frame.add_child(stage)
	var reaction := ReactionScene.instantiate()
	frame.add_child(reaction)

	_chars = CharacterCore.new()
	_chars.bind(stage, reaction, null)
	add_child(_chars)

	# Сеет ShotDirector (кассеты): без этого draw() всегда {} и кассетный вход портрета в
	# переходе не покажется — а это тоже часть того, что нужно откалибровать глазами.
	EventBus.match_started.emit({"match_id": Time.get_unix_time_from_system(),
		"theme": "lab", "first": "you"})

	_build_panel()
	_build_hint()


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
	hint.size = Vector2(CANVAS_SIZE.x * PREVIEW_SCALE, 170.0)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64))
	hint.text = ("Превью в масштабе %.0f%% канон-канваса %dx%d (так авторится stage.tscn — " +
		"абсолютные позиции акторов, не резиновая раскладка). «Играть» шлёт EventBus.utterance " +
		"тем же путём, что боевой код: 1) доска (статично, карт тут нет) → долли — наезд на " +
		"спикера И выезд общего плана вбок ОДНОВРЕМЕННО (цель по X — центр рамки-якоря портрета " +
		"в reaction_scene.gd, НЕ центр актёра на доске — поправка панелью «ЦЕЛЬ НАЕЗДА ПО X»); " +
		"2) следом фон крупного плана въезжает с той же стороны, портрет+бабл фейдятся как " +
		"раньше — без новой паузы, внутри уже существующего фейд-ина; 3) когда крупный план " +
		"полностью отыграет и погаснет — камера ВИДИМО едет обратно в общий план (секция " +
		"«ВОЗВРАТ КАМЕРЫ» ниже) — раньше это было скрыто за фейд-ином, теперь честная " +
		"отдельная фаза.") % [
		PREVIEW_SCALE * 100.0, int(CANVAS_SIZE.x), int(CANVAS_SIZE.y)]
	add_child(hint)


# ------------------------------------------------------------------ панель шкал

func _build_panel() -> void:
	var panel_x := CANVAS_SIZE.x * PREVIEW_SCALE + 24.0
	var pbg := ColorRect.new()
	pbg.color = Color(0.07, 0.08, 0.11, 0.92)
	pbg.position = Vector2(panel_x, 8.0)
	pbg.size = Vector2(420.0, CANVAS_SIZE.y)
	add_child(pbg)
	var vb := VBoxContainer.new()
	vb.position = Vector2(panel_x + 12.0, 14.0)
	vb.size = Vector2(396.0, CANVAS_SIZE.y - 12.0)
	vb.add_theme_constant_override("separation", 3)  ## тесно, как у fx_lab — иначе не влезет
	add_child(vb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	vb.add_child(hb)
	_side_btn = _btn(hb, "Сторона: вы", _toggle_side)
	var mood_ob := OptionButton.new()
	for m in MOODS:
		mood_ob.add_item(m)
	mood_ob.selected = MOODS.find(_mood)
	mood_ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mood_ob.add_theme_font_size_override("font_size", 12)
	mood_ob.item_selected.connect(func(i: int) -> void: _mood = MOODS[i])
	hb.add_child(mood_ob)

	_header(vb, "ДОЛЛИ — ВЪЕЗД К СПИКЕРУ")
	_add_slider(vb, "Масштаб наезда", 1.0, 4.0, 0.01, CharacterCore.DOLLY_SCALE, "%.2f",
		func(v: float) -> void: CharacterCore.DOLLY_SCALE = v)
	_add_slider(vb, "Высота лица (доля от макушки)", 0.0, 1.0, 0.01,
		CharacterCore.DOLLY_FACE_HEIGHT_FRAC, "%.2f",
		func(v: float) -> void: CharacterCore.DOLLY_FACE_HEIGHT_FRAC = v)

	_header(vb, "ХАРАКТЕР НАЕЗДА (scale)")
	_add_option(vb, "Кривая (trans)", TRANS_OPTIONS, CharacterCore.DOLLY_TRANS_IN,
		func(v: int) -> void: CharacterCore.DOLLY_TRANS_IN = v)
	_add_option(vb, "Плавность (ease)", EASE_OPTIONS, CharacterCore.DOLLY_EASE_IN,
		func(v: int) -> void: CharacterCore.DOLLY_EASE_IN = v)

	_header(vb, "ЦЕЛЬ НАЕЗДА ПО X")
	_add_slider(vb, "Поправка ±px (наружу от центра экрана)", -300.0, 300.0, 5.0,
		CharacterCore.DOLLY_TARGET_X_BIAS, "%.0f",
		func(v: float) -> void: CharacterCore.DOLLY_TARGET_X_BIAS = v)

	_header(vb, "ВЫЕЗД ВБОК (одновременно с наездом, та же длительность)")
	_add_slider(vb, "Дистанция выезда, px", 0.0, 1200.0, 10.0,
		CharacterCore.DOLLY_SLIDE_DISTANCE, "%.0f",
		func(v: float) -> void: CharacterCore.DOLLY_SLIDE_DISTANCE = v)
	_add_option(vb, "Кривая (trans)", TRANS_OPTIONS, CharacterCore.DOLLY_SLIDE_TRANS,
		func(v: int) -> void: CharacterCore.DOLLY_SLIDE_TRANS = v)
	_add_option(vb, "Плавность (ease)", EASE_OPTIONS, CharacterCore.DOLLY_SLIDE_EASE,
		func(v: int) -> void: CharacterCore.DOLLY_SLIDE_EASE = v)

	_header(vb, "ВЪЕЗД ФОНА КРУПНОГО ПЛАНА (следом, внутри FADE_IN)")
	_add_option(vb, "Кривая (trans)", TRANS_OPTIONS, ReactionSceneScript.BG_SLIDE_TRANS,
		func(v: int) -> void: ReactionSceneScript.BG_SLIDE_TRANS = v)
	_add_option(vb, "Плавность (ease)", EASE_OPTIONS, ReactionSceneScript.BG_SLIDE_EASE,
		func(v: int) -> void: ReactionSceneScript.BG_SLIDE_EASE = v)
	_add_slider(vb, "Забег вперёд, с (старт раньше конца долли)", 0.0, ReadingPace.BOARD_BEAT,
		0.01, CharacterCore.DOLLY_REVEAL_LEAD, "%.2f",
		func(v: float) -> void: CharacterCore.DOLLY_REVEAL_LEAD = v)

	_header(vb, "ВОЗВРАТ КАМЕРЫ (после конца реплики, теперь ВИДИМЫЙ)")
	_add_slider(vb, "Длительность возврата, с", 0.0, 1.5, 0.01,
		ReadingPace.DOLLY_RETURN_TIME, "%.2f",
		func(v: float) -> void: ReadingPace.DOLLY_RETURN_TIME = v)
	_add_option(vb, "Кривая (trans)", TRANS_OPTIONS, CharacterCore.DOLLY_RETURN_TRANS,
		func(v: int) -> void: CharacterCore.DOLLY_RETURN_TRANS = v)
	_add_option(vb, "Плавность (ease)", EASE_OPTIONS, CharacterCore.DOLLY_RETURN_EASE,
		func(v: int) -> void: CharacterCore.DOLLY_RETURN_EASE = v)

	_header(vb, "ПЕЙСИНГ")
	var pace_label := Label.new()
	pace_label.text = ("BOARD_BEAT = %.2fс — наезд И выезд вбок играют внутри неё ОДНОВРЕМЕННО " +
		"(по запросу игрока — раньше выезд был отдельной последующей паузой, слили в одну). " +
		"Эта пауза не тюнится: свободная длительность разъехалась бы с пейсингом контроллера. " +
		"Крупный план (и его фон) стартует не строго ПОСЛЕ неё, а с забегом вперёд на " +
		"DOLLY_REVEAL_LEAD выше — внахлёст с хвостом долли, без новой паузы (просто короче " +
		"ждём внутри уже существующей). А вот возврат камеры выше (DOLLY_RETURN_TIME) — НЕ " +
		"сжатие, а честная НОВАЯ фаза ПОСЛЕ конца реплики, учтена в ReadingPace.scene_time() " +
		"отдельным слагаемым — крутится свободно, следующий ход всё равно подождёт ровно " +
		"столько, сколько тут выставлено.") % ReadingPace.BOARD_BEAT
	pace_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	pace_label.add_theme_font_size_override("font_size", 11)
	pace_label.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64))
	vb.add_child(pace_label)

	_btn(vb, "▶ Играть переход (доска → долли → крупный план)", _play)
	_btn(vb, "Скопировать константы", _copy)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64))
	_status.text = "Крути и жми «Играть» — параметры боевые, применяются сразу же."
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


func _add_slider(vb: VBoxContainer, title: String, minv: float, maxv: float, step: float,
		value: float, fmt: String, cb: Callable) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	var lab := Label.new()
	lab.custom_minimum_size = Vector2(190.0, 0.0)
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


## options — массив [ярлык:String, значение:int]. cb получает выбранное значение.
func _add_option(vb: VBoxContainer, title: String, options: Array, default_value: int,
		cb: Callable) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	var lab := Label.new()
	lab.custom_minimum_size = Vector2(190.0, 0.0)
	lab.add_theme_font_size_override("font_size", 12)
	lab.text = title
	hb.add_child(lab)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.add_theme_font_size_override("font_size", 12)
	var selected_idx := 0
	for i in options.size():
		var opt: Array = options[i]
		ob.add_item(String(opt[0]))
		if int(opt[1]) == default_value:
			selected_idx = i
	ob.selected = selected_idx
	ob.item_selected.connect(func(i: int) -> void: cb.call(int((options[i] as Array)[1])))
	hb.add_child(ob)


# ------------------------------------------------------------------- события ---

func _toggle_side() -> void:
	_side = "opp" if _side == "you" else "you"
	_side_btn.text = "Сторона: " + ("вы" if _side == "you" else "опп")


## Тот же вход, что и боевой код (character_core._on_utterance слушает EventBus.utterance) —
## не вызываем _dolly_to_speaker/_on_utterance напрямую, чтобы проверять ИМЕННО интеграцию,
## а не отдельно выдранный кусок логики.
func _play() -> void:
	EventBus.utterance.emit(_side, String(SAMPLE_TEXT[_side]), {"mood": _mood})
	_status.text = "Играю: сторона=%s, mood=%s. Смотри на общий план слева." % [_side, _mood]


func _copy() -> void:
	var trans_in: String = TRANS_NAMES.get(CharacterCore.DOLLY_TRANS_IN, "TRANS_SINE")
	var ease_in: String = EASE_NAMES.get(CharacterCore.DOLLY_EASE_IN, "EASE_IN")
	var slide_trans: String = TRANS_NAMES.get(CharacterCore.DOLLY_SLIDE_TRANS, "TRANS_QUAD")
	var slide_ease: String = EASE_NAMES.get(CharacterCore.DOLLY_SLIDE_EASE, "EASE_IN")
	var return_trans: String = TRANS_NAMES.get(CharacterCore.DOLLY_RETURN_TRANS, "TRANS_SINE")
	var return_ease: String = EASE_NAMES.get(CharacterCore.DOLLY_RETURN_EASE, "EASE_IN_OUT")
	var bg_trans: String = TRANS_NAMES.get(ReactionSceneScript.BG_SLIDE_TRANS, "TRANS_QUAD")
	var bg_ease: String = EASE_NAMES.get(ReactionSceneScript.BG_SLIDE_EASE, "EASE_OUT")
	var out := ("# character_core.gd\n" +
		"static var DOLLY_SCALE := %.2f\n" +
		"static var DOLLY_FACE_HEIGHT_FRAC := %.3f\n" +
		"static var DOLLY_TRANS_IN: int = Tween.%s\n" +
		"static var DOLLY_EASE_IN: int = Tween.%s\n" +
		"static var DOLLY_TARGET_X_BIAS := %.0f\n" +
		"static var DOLLY_SLIDE_DISTANCE := %.0f\n" +
		"static var DOLLY_SLIDE_TRANS: int = Tween.%s\n" +
		"static var DOLLY_SLIDE_EASE: int = Tween.%s\n" +
		"static var DOLLY_REVEAL_LEAD := %.2f\n" +
		"static var DOLLY_RETURN_TRANS: int = Tween.%s\n" +
		"static var DOLLY_RETURN_EASE: int = Tween.%s\n" +
		"\n# reaction_scene.gd\n" +
		"static var BG_SLIDE_TRANS: int = Tween.%s\n" +
		"static var BG_SLIDE_EASE: int = Tween.%s\n" +
		"\n# reading_pace.gd\n" +
		"static var DOLLY_RETURN_TIME := %.2f") % [
		CharacterCore.DOLLY_SCALE, CharacterCore.DOLLY_FACE_HEIGHT_FRAC, trans_in, ease_in,
		CharacterCore.DOLLY_TARGET_X_BIAS, CharacterCore.DOLLY_SLIDE_DISTANCE,
		slide_trans, slide_ease, CharacterCore.DOLLY_REVEAL_LEAD, return_trans, return_ease,
		bg_trans, bg_ease, ReadingPace.DOLLY_RETURN_TIME]
	DisplayServer.clipboard_set(out)
	print(out)
	_status.text = "Скопировано в буфер (и в консоль) — три блока на три файла, см. заголовки."
