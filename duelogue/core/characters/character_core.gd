extends Node

## DUELOGUE — ЯДРО ПЕРСОНАЖЕЙ. Владелец актёров (спрайтов дебатёров на общем плане арены) И
## режиссёр мини-сцены реакции (reaction_scene) — «ядро персонажа вызывает анимации и
## отображение высказывания карты».
##
## СТЕЙТЫ РЕАКЦИЙ (контракт §16 narrative_engine.md, Ace Attorney-вдохновение): портрет/позу
## выбирает СТЕЙТ (meta.mood), а не тип карты. Стейт вычисляет тот, кто знает семантику:
## нарративный движок — для реплик (акт × регистр × зал × попадание), контроллер — для
## исходов (impact → stagger). Персонаж только РЕНДЕРИТ: скин = данные «стейт → портрет»
## (STATE_TEX) — новый персонаж = новый набор поз, ни строчки кода. Фолбэк по типу карты
## (_portrait_for) подбирает актуальный стейт по типу карты, пока mood не передан.

const C := preload("res://duelogue/core/cards/card_types.gd")
const TYPE_TEZIS := C.TYPE_TEZIS
const TYPE_RAZBOR := C.TYPE_RAZBOR
const TYPE_USTANOVKA := C.TYPE_USTANOVKA

const ReadingPace := preload("res://duelogue/core/narrative/reading_pace.gd")
const ShotDirector := preload("res://duelogue/core/director/shot_director.gd")
const CameraCassettes := preload("res://duelogue/core/director/camera_cassettes.gd")

## Тестовая пачка эмоций (assets/states_test, генерация 2026-07-05) — примапплена на стейты
## ниже. При финализации скина переехать в assets/characters/<skin>/ с именами стейтов.
const ST_IDLE := preload("res://duelogue/assets/states_test/idle.png")
const ST_DECLARE := preload("res://duelogue/assets/states_test/normal.png")
const ST_ATTACK := preload("res://duelogue/assets/states_test/pointing.png")
const ST_BURST := preload("res://duelogue/assets/states_test/objection.png")
const ST_HOLD := preload("res://duelogue/assets/states_test/angry.png")
const ST_SWAGGER := preload("res://duelogue/assets/states_test/grinning.png")
const ST_GOTCHA := preload("res://duelogue/assets/states_test/laughing.png")
const ST_STAGGER := preload("res://duelogue/assets/states_test/shocked.png")
const ST_EVADE := preload("res://duelogue/assets/states_test/sweating.png")
const ST_PANIC := preload("res://duelogue/assets/states_test/disheartened.png")

const OPP_IDLE := preload("res://duelogue/assets/characters/red_advocate/idle.png")
const OPP_DECLARE := preload("res://duelogue/assets/characters/red_advocate/normal.png")
const OPP_ATTACK := preload("res://duelogue/assets/characters/red_advocate/pointing.png")
const OPP_BURST := preload("res://duelogue/assets/characters/red_advocate/objection.png")
const OPP_HOLD := preload("res://duelogue/assets/characters/red_advocate/angry.png")
const OPP_SWAGGER := preload("res://duelogue/assets/characters/red_advocate/grinning.png")
const OPP_GOTCHA := preload("res://duelogue/assets/characters/red_advocate/laughing.png")
const OPP_STAGGER := preload("res://duelogue/assets/characters/red_advocate/shocked.png")
const OPP_EVADE := preload("res://duelogue/assets/characters/red_advocate/sweating.png")
const OPP_PANIC := preload("res://duelogue/assets/characters/red_advocate/disheartened.png")

## КОНТРАКТ СКИНА: поза на каждый стейт словаря §16. 9/10 закрыты тестовой пачкой;
## недостающий стейт падает в фолбэк по типу карты, так что система рабочая при любом арте.
const YOU_STATE_TEX := {
	"declare": ST_DECLARE,       # заявляю (normal: спокойная уверенность «у трибуны»)
	"hold": ST_HOLD,             # держит удар, закипая (angry: стиснутые зубы, красный контровой)
	"attack": ST_ATTACK,        # атакую (pointing: суровое обвинение)
	"gotcha": ST_GOTCHA,        # подловил (laughing: открытый хохот-издёвка «Ха! Попался!»)
	"burst": ST_BURST,          # вспышка-панч (objection: крик, палец вверх)
	"evade": ST_EVADE,          # юлит (sweating: пот, взгляд вбок, съёжен)
	"swagger": ST_SWAGGER,      # кураж фаворита (grinning: вальяжная ухмылка)
	"panic": ST_PANIC,          # сник/мнётся (disheartened; TODO арт: суетливая паника сочнее)
	"stagger": ST_STAGGER,      # пошатнулся (shocked: отшат, пот) — со спидлайнами
	"idle": ST_IDLE,            # нейтраль/пауза (idle: фигура в полный рост «у трибуны»)
}

const OPP_STATE_TEX := {
	"declare": OPP_DECLARE,
	"hold": OPP_HOLD,
	"attack": OPP_ATTACK,
	"gotcha": OPP_GOTCHA,
	"burst": OPP_BURST,
	"evade": OPP_EVADE,
	"swagger": OPP_SWAGGER,
	"panic": OPP_PANIC,
	"stagger": OPP_STAGGER,
	"idle": OPP_IDLE,
}

const PORTRAIT_FLIP_H := {"you": false, "opp": false}

var _stage              ## ядро сцены (через bind) — даёт постоянные stage-спрайты сторон
## Мини-сцена реакции (через bind) — статический узел debate_screen.tscn. Нетипизировано
## намеренно: зовём кастомные show_utterance/show_impact из скрипта сцены, которых нет в
## базовом Control — статическая типизация Control тут выдаст ошибку компиляции на вызове.
var _reaction
## Баннер названия комбо (через bind) — отдельный от reaction_scene узел (combo_name_banner.gd,
## тоже нетипизирован по той же причине: кастомный show_combo).
var _combo_banner
var _sprites := {}      ## side → Sprite2D (актёр на общем плане)
## Режиссёр камера-кассет (context/director_core_v0.1.md) — пересеивается на match_started.
var _director := ShotDirector.new()
var _dolly_tween: Tween  ## долли-наезд на общем плане (см. _dolly_to_speaker/_reset_dolly)


## Привязать к ядру сцены, мини-сцене реакции и баннеру комбо ДО входа в дерево.
func bind(stage, reaction, combo_banner = null) -> void:
	_stage = stage
	_reaction = reaction
	_combo_banner = combo_banner


func _ready() -> void:
	if _stage != null:
		_sprites["you"] = _stage.actor_sprite("you")
		_sprites["opp"] = _stage.actor_sprite("opp")
	EventBus.match_started.connect(_on_match_started)
	EventBus.utterance.connect(_on_utterance)
	EventBus.impact.connect(_on_impact)
	EventBus.combo_verdict.connect(_on_combo_verdict)
	EventBus.turn_changed.connect(_on_turn_changed)
	# Возврат камеры теперь ВИДИМЫЙ (по запросу игрока) — играет уже ПОСЛЕ того, как крупный
	# план полностью отыграл и погас, а не молча под фейд-ином, как раньше (см. _reset_dolly).
	if _reaction != null:
		_reaction.connect("scene_finished", _reset_dolly)


## Кассетный режиссёр пересеивается на каждую партию — тот же приём, что emotion.start в
## battle_controller (match_id ^ отдельная константа, чтобы потоки RNG не совпадали друг с
## другом). Чисто косметический слой — не участвует в баланс-симах, детерминизм здесь ради
## воспроизводимости конкретной партии на глаз, не ради sim-регрессии.
func _on_match_started(info: Dictionary) -> void:
	_director.start(CameraCassettes.data(), int(info.get("match_id", 0)) ^ 0xCA55E77E)


## Точка загрузки общего плана: будущие скины назначают свою текстуру нужной стороне,
## не меняя авторские положение, масштаб или порядок слоёв в stage.tscn.
func set_stage_sprite_texture(side: String, texture: Texture2D) -> void:
	if not _sprites.has(side) or texture == null:
		return
	(_sprites[side] as Sprite2D).texture = texture


## Фолбэк-муд по типу карты (+флаг steals — Кража это Разбор с card.steals=true,
## см. narrative_engine.gd — тот же принцип: тип карты = манера, различает приёмы по флагу).
## Использует только актуальные портреты из state map, без legacy-пиксельных реакций.
func _fallback_mood_for_card(card_type: String, steals: bool) -> String:
	match card_type:
		TYPE_RAZBOR:
			return "gotcha" if steals else "attack"
		TYPE_TEZIS:
			return "declare"
		TYPE_USTANOVKA:
			return "hold"
	return "idle"


## Портрет реакции по типу карты, если нарратив ещё не передал отдельный mood.
## "" (нет карты — пас/наррация) → нейтральный idle-портрет.
func _portrait_for(side: String, card_type: String, steals: bool) -> Texture2D:
	var states: Dictionary = OPP_STATE_TEX if side == "opp" else YOU_STATE_TEX
	return states.get(_fallback_mood_for_card(card_type, steals), states["idle"]) as Texture2D


func _state_tex_for(side: String, mood: String, card_type: String, steals: bool) -> Texture2D:
	var states: Dictionary = OPP_STATE_TEX if side == "opp" else YOU_STATE_TEX
	if states.has(mood):
		return states[mood] as Texture2D
	return _portrait_for(side, card_type, steals)


func _portrait_flip_h_for(side: String) -> bool:
	return bool(PORTRAIT_FLIP_H.get(side, false))


## Стейт для режиссёра — тот же fallback, что уже ведёт текстуру (§16): текстуру и кассету
## должен вести ОДИН эффективный стейт, не два независимых расчёта, которые могут разойтись.
func _effective_state_for(side: String, mood: String, card_type: String, steals: bool) -> String:
	var states: Dictionary = OPP_STATE_TEX if side == "opp" else YOU_STATE_TEX
	if states.has(mood):
		return mood
	return _fallback_mood_for_card(card_type, steals)


## Долли-наезд общего плана (context/director_core_v0.1.md §1, «средний план») — раньше между
## доской и крупным планом была голая пауза (BOARD_BEAT), теперь на ней виден переезд камеры к
## тому, кто сейчас скажет реплику. Настоящей Camera2D в проекте нет: имитируем через масштаб
## ВСЕГО _stage (Bg+Actors+PropsFront, см. stage_core.gd) вокруг пивота на спикере — растущий
## масштаб от пивота сам по себе толкает всё остальное «прочь от камеры», отдельный сдвиг
## позиции не нужен. Живёт СТРОГО внутри уже существующего BOARD_BEAT — не заводим новую фазу
## времени (тот же принцип, что у кассетного входа портрета в reaction_scene.gd).
## var, не const — как ReadingPace.CHARS_PER_SEC/CUTSCENES (тот же приём: калибруется вживую,
## сейчас из duelogue/tools/dolly_lab.gd, не гейткипер, поэтому крутится без пересборки).
static var DOLLY_SCALE := 2.5
## Пивот — не центр спрайта, а точка на высоте актёра, считая от макушки (0.0 = сама макушка,
## текущая калибровка; 1/3 = «верхняя треть», исходное предположение). Формула симметрична для
## обеих сторон — геометрия ActorYou/ActorOpp одинакова в stage.tscn (тот же scale/Y, только
## зеркальный X), отдельного случая для «оппонента» не нужно.
static var DOLLY_FACE_HEIGHT_FRAC := 0.0
## Тип int, не Tween.TransitionType/EaseType — set_trans/set_ease их и так молча принимают
## (enum = обёрнутый int в Godot), а как ТИП ПЕРЕМЕННОЙ формально Tween.TransitionType нигде в
## проекте ещё не использовался — не рискуем словить ошибку компиляции там, где раньше не
## проверяли. Тот же приём у DOLLY_RETURN_TRANS/EASE ниже (возврат камеры, теперь тоже тюнится —
## он больше не спрятан за фейд-ином, см. _reset_dolly).
static var DOLLY_TRANS_IN: int = Tween.TRANS_SINE
static var DOLLY_EASE_IN: int = Tween.EASE_IN
## Ручная поправка цели по X поверх portrait_frame_center_x, px. Знак — «наружу от центра
## экрана» (+ = дальше в сторону своего края); мирроригуется по стороне ниже, а не хранится
## отдельно на каждую — геометрия симметрична, второй ручки не нужно.
static var DOLLY_TARGET_X_BIAS := 195.0

## Выезд общего плана вбок — раньше отдельная фаза 2 после наезда, теперь слит с ним: едет
## ОДНОВРЕМЕННО со скейлом наезда, той же BOARD_BEAT-длительностью, свой trans/ease (Tween
## поддерживает разные кривые на разных tween_property внутри одного parallel-блока). Опять
## НЕ заводим новую фазу времени — вернулись к тому же принципу, что у наезда/кассетного входа
## портрета. reaction_scene._slide_in_bg по-прежнему подхватывает эстафету той же стороной
## следом, уже внутри FADE_IN.
static var DOLLY_SLIDE_DISTANCE := 0.0
static var DOLLY_SLIDE_TRANS: int = Tween.TRANS_QUAD
static var DOLLY_SLIDE_EASE: int = Tween.EASE_IN

## Насколько раньше стартует крупный план (портрет+бабл+фон) относительно конца BOARD_BEAT —
## по запросу игрока (фон крупного плана должен начинать въезжать раньше, внахлёст с хвостом
## долли, а не строго после него). Секунды, не доля: 0 = как было, ждём BOARD_BEAT целиком.
## Не новая фаза времени — просто СОКРАЩАЕТ уже существующее ожидание в _on_utterance, общий
## бюджет scene_time() не трогаем (реальная суммарная пауза становится чуть короче факта; это
## безопасная сторона ошибки — контроллер ждёт не меньше, чем нужно, самое большее чуть дольше).
static var DOLLY_REVEAL_LEAD := 0.15

## Возврат камеры из наезда в общий план (_reset_dolly) — по запросу игрока ТЕПЕРЬ ВИДИМАЯ фаза
## ПОСЛЕ конца реплики (раньше был молчаливый сброс за фейд-ином крупного плана). Своя кривая,
## отдельная от DOLLY_TRANS_IN/EASE_IN наезда — обратное движение не обязано быть зеркалом
## прямого. Длительность — ReadingPace.DOLLY_RETURN_TIME (там же и почему это честная фаза
## scene_time(), а не сжатие существующей).
static var DOLLY_RETURN_TRANS: int = Tween.TRANS_SINE
static var DOLLY_RETURN_EASE: int = Tween.EASE_IN_OUT


## Точка «где лицо» в глобальных координатах — оси считаются РАЗНЫМИ источниками, не одним:
## - Y — DOLLY_FACE_HEIGHT_FRAC высоты текстуры спрайта на общем плане, считая от макушки
##   (там лицо КОНКРЕТНОГО актёра; Sprite2D.to_global уже учитывает position/scale/rotation
##   ноды сам). Sprite2D.centered — дефолт true (так и в stage.tscn, оба актёра без override) —
##   учитываем оба случая, раз это обычный экспортируемый флаг, который легко переключить в
##   редакторе.
## - X — НЕ центр спрайта, а горизонтальный центр рамки-якоря портрета в reaction_scene.gd
##   (portrait_frame_center_x): камера должна утыкаться туда же по горизонтали, где секунду
##   спустя проявится портрет крупного плана — иначе переход скачет по X при смене плана.
##   У рамки-якоря нет понятия «верхняя треть», поэтому вертикаль по-прежнему от спрайта.
func _face_zone_global(side: String, sprite: Sprite2D) -> Vector2:
	var y := sprite.global_position.y
	if sprite.texture != null:
		var h := float(sprite.texture.get_height())
		var top_local_y := -h * 0.5 if sprite.centered else 0.0
		y = sprite.to_global(Vector2(0.0, top_local_y + h * DOLLY_FACE_HEIGHT_FRAC)).y
	var x := sprite.global_position.x
	if _reaction != null:
		x = _reaction.portrait_frame_center_x(side)
	x += DOLLY_TARGET_X_BIAS if side == "opp" else -DOLLY_TARGET_X_BIAS
	return Vector2(x, y)


## Наезд (scale вокруг пивота-лица) и выезд вбок (position:x) идут ОДНОВРЕМЕННО, одной
## BOARD_BEAT-длительностью, каждый своей кривой — по запросу игрока (были отдельными
## последовательными фазами, слиты в одну). "you" тянет влево, "opp" вправо — тот же принцип
## направления, что везде в проекте.
func _dolly_to_speaker(side: String) -> void:
	if _stage == null or not _sprites.has(side):
		return
	var sprite: Sprite2D = _sprites[side]
	var global_target := _face_zone_global(side, sprite)
	# Control не даёт to_local() (это метод Node2D, не CanvasItem) — тот же результат через
	# инверсию глобальной трансформации.
	_stage.pivot_offset = _stage.get_global_transform().affine_inverse() * global_target
	if _dolly_tween:
		_dolly_tween.kill()
	var dir := 1.0 if side == "opp" else -1.0
	_dolly_tween = _stage.create_tween()
	_dolly_tween.set_parallel(true)
	_dolly_tween.tween_property(_stage, "scale", Vector2.ONE * DOLLY_SCALE, ReadingPace.BOARD_BEAT) \
		.set_trans(DOLLY_TRANS_IN).set_ease(DOLLY_EASE_IN)
	_dolly_tween.tween_property(_stage, "position:x", dir * DOLLY_SLIDE_DISTANCE, ReadingPace.BOARD_BEAT) \
		.set_trans(DOLLY_SLIDE_TRANS).set_ease(DOLLY_SLIDE_EASE)


## ВИДИМО возвращает общий план к покою (масштаб И позицию — слайд тоже надо откатить) — по
## запросу игрока (раньше сбрасывалось молча, за фейд-ином крупного плана). Привязан к
## scene_finished (_ready), то есть стартует только когда крупный план ПОЛНОСТЬЮ отыграл и погас:
## игрок видит саму камеру, едущую обратно в общий план. _reset_dolly вызывается по сигналу
## (fire-and-forget, никто его не await-ит), но ReadingPace.DOLLY_RETURN_TIME всё равно честно
## сидит в scene_time() — иначе следующий ход оборвал бы возврат камеры на полпути.
func _reset_dolly() -> void:
	if _stage == null:
		return
	if _dolly_tween:
		_dolly_tween.kill()
	_dolly_tween = _stage.create_tween()
	_dolly_tween.set_parallel(true)
	_dolly_tween.set_trans(DOLLY_RETURN_TRANS).set_ease(DOLLY_RETURN_EASE)
	_dolly_tween.tween_property(_stage, "scale", Vector2.ONE, ReadingPace.DOLLY_RETURN_TIME)
	_dolly_tween.tween_property(_stage, "position", Vector2.ZERO, ReadingPace.DOLLY_RETURN_TIME)


## Катсцена реплики. Тумблер ReadingPace.CUTSCENES: выключен — крупный план не играется,
## реплика остаётся в логе/стенограмме (их пишет debate_screen/контроллер).
## BOARD_BEAT: пауза перед крупным планом — ход, уже отрисованный на доске (контроллер
## эмитит board_changed ДО utterance), успевает считаться игроком. Контроллер держит ровно
## scene_time (BOARD_BEAT входит) — сцены идут строго по очереди и не убивают друг друга.
## Теперь BOARD_BEAT — не голая пауза, а долли к спикеру: наезд и выезд вбок одновременно
## (_dolly_to_speaker). Дальше reaction_scene въезжает фоном с той же стороны следом
## (_slide_in_bg, внутри уже существующего FADE_IN — там новую фазу не заводили).
## DOLLY_REVEAL_LEAD укорачивает это ожидание — крупный план (и его фон) стартует чуть раньше
## конца долли, внахлёст с её хвостом, а не строго после.
func _on_utterance(side: String, text: String, meta: Dictionary) -> void:
	if _reaction == null or not ReadingPace.CUTSCENES:
		return
	var mood := String(meta.get("mood", ""))
	var card_type := String(meta.get("card_type", ""))
	var steals := bool(meta.get("steals", false))
	var tex := _state_tex_for(side, mood, card_type, steals)
	var cassette := _director.draw(side, _effective_state_for(side, mood, card_type, steals))
	var eyebrow := ""
	match String(meta.get("reaction_kind", "")):
		"parry":
			eyebrow = "ХОЛОДНАЯ ПАРИРОВКА · %s" % String(meta.get("reaction_title", "Ответ"))
		"counter_burst":
			eyebrow = "ЦЕПНАЯ РЕАКЦИЯ · %s" % String(meta.get("reaction_title", "Срыв"))
		"burst":
			eyebrow = "ЭМОЦИОНАЛЬНЫЙ СРЫВ · %s" % String(meta.get("reaction_title", "Реакция"))
	_dolly_to_speaker(side)
	await get_tree().create_timer(maxf(0.0, ReadingPace.BOARD_BEAT - DOLLY_REVEAL_LEAD)).timeout
	# Муд едет и в сцену: тот же стейт ведёт портрет И профиль живого фона (MOOD_FX). Кассета —
	# отдельно, только вход/ракурс камеры (director_core_v0.1.md); {} = дефолтный вход.
	# device (2026-08-06): та же метка приёма/схемы, что уже идёт в живой лог боевого экрана
	# (battle_controller._say → meta.device) — раньше сюда не долетала, крупный план был немым.
	var device_name := String(meta.get("device", ""))
	_reaction.show_utterance(side, text, tex, mood, _portrait_flip_h_for(side), eyebrow, cassette,
		device_name)


## Яркий исход по стороне side — стейт «пошатнулся» (событийный, ставит контроллер).
## Интенсивность вспышки по тяжести: снят довод — 0.65, рухнула рамка — 1.0.
func _on_impact(side: String, kind: String) -> void:
	if _reaction == null or not ReadingPace.CUTSCENES:
		return
	var tex := _state_tex_for(side, "stagger", "", false)
	var cassette := _director.draw(side, "stagger")
	_reaction.show_impact(side, tex, 1.0 if kind == "removed" else 0.65, _portrait_flip_h_for(side), cassette)


## Боевой каталог (2026-07-22, resolved-by-construction): вердикт клинча решён конструкцией
## ответа, не физикой unwind (см. rules_core.gd instant_verdict/forced_winner_side) — игрок
## должен ОДНОЗНАЧНО увидеть, что комбо сработало И кто победил. Баннер названия комбо
## (2026-07-23, combo_name_banner.gd) СНАЧАЛА — это не реакция владельца, а нейтральный эффект
## самой игры поверх всей сцены, поэтому НЕ гейтится ReadingPace.CUTSCENES (тумблер отключает
## только тяжёлые катсцены-реплики; игрок должен видеть исход комбо всегда). Потом уже —
## знакомая поза-реакция владельца (burst=защита держит, gotcha=ловушка сработала) поверх
## того же utterance-пайплайна, которая по-прежнему уважает CUTSCENES.
func _on_combo_verdict(side: String, combo_name: String, topology: String) -> void:
	if _combo_banner != null:
		await _combo_banner.show_combo(combo_name, side)
	if _reaction == null or not ReadingPace.CUTSCENES:
		return
	var is_trap := topology.ends_with("trap")
	var mood := "gotcha" if is_trap else "burst"
	var tex := _state_tex_for(side, mood, "", false)
	var cassette := _director.draw(side, mood)
	var eyebrow := "🪤 ЛОВУШКА СРАБОТАЛА" if is_trap else "⚡ ЗАЩИТА ДЕРЖИТ"
	_reaction.show_utterance(side,
		("Попался! «%s»." % combo_name) if is_trap else ("Не сдвинулось! «%s»." % combo_name),
		tex, mood, _portrait_flip_h_for(side), eyebrow, cassette, combo_name)


func _on_turn_changed(_side: String) -> void:
	pass  # позже: поза/idle активной стороны
