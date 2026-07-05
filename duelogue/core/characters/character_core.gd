extends Node

## DUELOGUE — ЯДРО ПЕРСОНАЖЕЙ. Владелец актёров (спрайтов дебатёров на общем плане арены) И
## режиссёр мини-сцены реакции (reaction_scene) — «ядро персонажа вызывает анимации и
## отображение высказывания карты». На utterance — крупный план с баблом реплики и портретом,
## подобранным ПО ТИПУ КАРТЫ (Тезис/Разбор/Кража/Установка — см. _portrait_for); на impact
## (яркий исход клинча) — вспышка со спидлайнами, портрет нейтральный (idle).

const RulesCore := preload("res://duelogue/core/rules/rules_core.gd")
const TYPE_TEZIS := RulesCore.TYPE_TEZIS
const TYPE_RAZBOR := RulesCore.TYPE_RAZBOR
const TYPE_USTANOVKA := RulesCore.TYPE_USTANOVKA

const CHAR_SCENE := preload("res://duelogue/core/characters/character.tscn")
const IDLE_TEX := preload("res://duelogue/assets/char_idle.png")
const REACT_TEZIS := preload("res://duelogue/assets/char_react_tez.png")
const REACT_RAZBOR := preload("res://duelogue/assets/char_react_raz.png")
const REACT_KRAJA := preload("res://duelogue/assets/char_react_kra.png")
const REACT_USTANOVKA := preload("res://duelogue/assets/char_react_ust.png")

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


func _on_utterance(side: String, text: String, meta: Dictionary) -> void:
	if _reaction != null:
		var tex := _portrait_for(String(meta.get("card_type", "")), bool(meta.get("steals", false)))
		_reaction.show_utterance(side, text, tex)


func _on_impact(side: String, _kind: String) -> void:
	if _reaction != null:
		_reaction.show_impact(side, IDLE_TEX)


func _on_turn_changed(_side: String) -> void:
	pass  # позже: поза/idle активной стороны
