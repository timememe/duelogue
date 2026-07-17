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
var _sprites := {}      ## side → Sprite2D (актёр на общем плане)


## Привязать к ядру сцены и мини-сцене реакции ДО входа в дерево.
func bind(stage, reaction) -> void:
	_stage = stage
	_reaction = reaction


func _ready() -> void:
	if _stage != null:
		_sprites["you"] = _stage.actor_sprite("you")
		_sprites["opp"] = _stage.actor_sprite("opp")
	EventBus.utterance.connect(_on_utterance)
	EventBus.impact.connect(_on_impact)
	EventBus.turn_changed.connect(_on_turn_changed)


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


## Катсцена реплики. Тумблер ReadingPace.CUTSCENES: выключен — крупный план не играется,
## реплика остаётся в логе/стенограмме (их пишет debate_screen/контроллер).
## BOARD_BEAT: пауза перед крупным планом — ход, уже отрисованный на доске (контроллер
## эмитит board_changed ДО utterance), успевает считаться игроком. Контроллер держит ровно
## scene_time (BOARD_BEAT входит) — сцены идут строго по очереди и не убивают друг друга.
func _on_utterance(side: String, text: String, meta: Dictionary) -> void:
	if _reaction == null or not ReadingPace.CUTSCENES:
		return
	var mood := String(meta.get("mood", ""))
	var tex := _state_tex_for(side, mood, String(meta.get("card_type", "")), bool(meta.get("steals", false)))
	var eyebrow := ""
	match String(meta.get("reaction_kind", "")):
		"parry":
			eyebrow = "ХОЛОДНАЯ ПАРИРОВКА · %s" % String(meta.get("reaction_title", "Ответ"))
		"counter_burst":
			eyebrow = "ЦЕПНАЯ РЕАКЦИЯ · %s" % String(meta.get("reaction_title", "Срыв"))
		"burst":
			eyebrow = "ЭМОЦИОНАЛЬНЫЙ СРЫВ · %s" % String(meta.get("reaction_title", "Реакция"))
	await get_tree().create_timer(ReadingPace.BOARD_BEAT).timeout
	# Муд едет и в сцену: тот же стейт ведёт портрет И профиль живого фона (MOOD_FX).
	_reaction.show_utterance(side, text, tex, mood, _portrait_flip_h_for(side), eyebrow)


## Яркий исход по стороне side — стейт «пошатнулся» (событийный, ставит контроллер).
## Интенсивность вспышки по тяжести: снят довод — 0.65, рухнула рамка — 1.0.
func _on_impact(side: String, kind: String) -> void:
	if _reaction == null or not ReadingPace.CUTSCENES:
		return
	var tex := _state_tex_for(side, "stagger", "", false)
	_reaction.show_impact(side, tex, 1.0 if kind == "removed" else 0.65, _portrait_flip_h_for(side))


func _on_turn_changed(_side: String) -> void:
	pass  # позже: поза/idle активной стороны
