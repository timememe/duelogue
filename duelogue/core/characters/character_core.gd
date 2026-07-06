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
## (_portrait_for) держит совместимость, пока mood не передан.

const RulesCore := preload("res://duelogue/core/rules/rules_core.gd")
const TYPE_TEZIS := RulesCore.TYPE_TEZIS
const TYPE_RAZBOR := RulesCore.TYPE_RAZBOR
const TYPE_USTANOVKA := RulesCore.TYPE_USTANOVKA

const ReadingPace := preload("res://duelogue/core/narrative/reading_pace.gd")
const CHAR_SCENE := preload("res://duelogue/core/characters/character.tscn")
const IDLE_TEX := preload("res://duelogue/assets/states_test/idle.png")
const REACT_TEZIS := preload("res://duelogue/assets/char_react_tez.png")
const REACT_RAZBOR := preload("res://duelogue/assets/char_react_raz.png")
const REACT_KRAJA := preload("res://duelogue/assets/char_react_kra.png")
const REACT_USTANOVKA := preload("res://duelogue/assets/char_react_ust.png")

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

## КОНТРАКТ СКИНА: поза на каждый стейт словаря §16. 9/10 закрыты тестовой пачкой;
## недостающий стейт падает в фолбэк по типу карты, так что система рабочая при любом арте.
const STATE_TEX := {
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

var _stage              ## ядро сцены (через bind) — даёт слой actors и точки-слоты
## Мини-сцена реакции (через bind) — статический узел debate_screen.tscn. Нетипизировано
## намеренно: зовём кастомные show_utterance/show_impact из скрипта сцены, которых нет в
## базовом Control — статическая типизация Control тут выдаст ошибку компиляции на вызове.
var _reaction
var _sprites := {}      ## side → Sprite2D (актёр на общем плане)


## Привязать к ядру сцены и мини-сцене реакции ДО входа в дерево (спавн актёров — в _ready).
func bind(stage, reaction) -> void:
	_stage = stage
	_reaction = reaction


func _ready() -> void:
	if _stage != null:
		_sprites["you"] = _spawn("you", false)
		_sprites["opp"] = _spawn("opp", true)  # оппонент развёрнут лицом к центру
	EventBus.utterance.connect(_on_utterance)
	EventBus.impact.connect(_on_impact)
	EventBus.turn_changed.connect(_on_turn_changed)


## Инстанс актёра на сцену: на слот стороны, в слой actors ядра сцены.
func _spawn(side: String, flip: bool) -> Node2D:
	var s: Sprite2D = CHAR_SCENE.instantiate()
	s.position = _stage.slot(side)
	s.flip_h = flip
	_stage.actor_layer().add_child(s)
	return s


## Портрет реакции по типу карты (+флаг steals — Кража это Разбор с card.steals=true,
## см. narrative_engine.gd — тот же принцип: тип карты = манера, различает приёмы по флагу).
## "" (нет карты — пас/наррация) → нейтральный idle-портрет.
func _portrait_for(card_type: String, steals: bool) -> Texture2D:
	match card_type:
		TYPE_RAZBOR: return REACT_KRAJA if steals else REACT_RAZBOR
		TYPE_TEZIS: return REACT_TEZIS
		TYPE_USTANOVKA: return REACT_USTANOVKA
	return IDLE_TEX


## Катсцена реплики. Тумблер ReadingPace.CUTSCENES: выключен — крупный план не играется,
## реплика остаётся в логе/стенограмме (их пишет debate_screen/контроллер).
## BOARD_BEAT: пауза перед крупным планом — ход, уже отрисованный на доске (контроллер
## эмитит board_changed ДО utterance), успевает считаться игроком. Контроллер держит ровно
## scene_time (BOARD_BEAT входит) — сцены идут строго по очереди и не убивают друг друга.
func _on_utterance(side: String, text: String, meta: Dictionary) -> void:
	if _reaction == null or not ReadingPace.CUTSCENES:
		return
	var mood := String(meta.get("mood", ""))
	var tex: Texture2D = STATE_TEX.get(mood) if STATE_TEX.has(mood) \
		else _portrait_for(String(meta.get("card_type", "")), bool(meta.get("steals", false)))
	await get_tree().create_timer(ReadingPace.BOARD_BEAT).timeout
	_reaction.show_utterance(side, text, tex)


## Яркий исход по стороне side — стейт «пошатнулся» (событийный, ставит контроллер).
## Интенсивность вспышки по тяжести: снят довод — 0.65, рухнула рамка — 1.0.
func _on_impact(side: String, kind: String) -> void:
	if _reaction == null or not ReadingPace.CUTSCENES:
		return
	_reaction.show_impact(side, STATE_TEX["stagger"], 1.0 if kind == "removed" else 0.65)


func _on_turn_changed(_side: String) -> void:
	pass  # позже: поза/idle активной стороны
