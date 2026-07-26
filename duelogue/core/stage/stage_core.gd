extends Control

## DUELOGUE — ЯДРО СЦЕНЫ. Скрипт сцены stage.tscn (декорации арены ПОЗАДИ всего UI).
## Визуал авторится НОДАМИ в редакторе (фон Bg, Actors/Actor*, кафедры PropsFront/Pulpit*),
## скрипт лишь ссылается на них — поэтому всё можно двигать/настраивать мышкой в Godot.
## Слои сцены (сзади→вперёд): Bg → Actors (постоянные Sprite2D персонажей) →
## PropsFront (кафедры спереди). Режиссура (камера/свет) — забота этого ядра; лёгкий мышиный
## параллакс (Parallax, 2026-07-25) — первый шаг: каждый слой держит авторскую позицию и
## сдвигается на общий сглаженный офсет мыши своей силой (дальше = меньше). Полноценная
## режиссура (акценты клинча/темы) по-прежнему впереди — заготовки ниже.

const Parallax := preload("res://duelogue/core/stage/parallax.gd")
const PARALLAX_BG := 5.0
const PARALLAX_ACTORS := 12.0
const PARALLAX_PROPS_FRONT := 20.0

@onready var _actor_you: Sprite2D = %ActorYou
@onready var _actor_opp: Sprite2D = %ActorOpp
@onready var _bg: TextureRect = $Bg
@onready var _actors: Node2D = %Actors
@onready var _props_front: Node2D = $PropsFront

var _bg_base := Vector2.ZERO
var _actors_base := Vector2.ZERO
var _props_front_base := Vector2.ZERO
var _parallax_offset := Vector2.ZERO


func _ready() -> void:
	EventBus.match_started.connect(_on_match_started)
	EventBus.clinch_started.connect(_on_clinch_started)
	_bg_base = _bg.position
	_actors_base = _actors.position
	_props_front_base = _props_front.position


func _process(delta: float) -> void:
	var target := Parallax.normalized_mouse(get_viewport())
	_parallax_offset = Parallax.step(_parallax_offset, target, delta)
	_bg.position = _bg_base + _parallax_offset * PARALLAX_BG
	_actors.position = _actors_base + _parallax_offset * PARALLAX_ACTORS
	_props_front.position = _props_front_base + _parallax_offset * PARALLAX_PROPS_FRONT


# --- API для ядра персонажей ---

## Постоянные актёры сцены: положение, масштаб и превью-текстуры правятся в редакторе,
## а CharacterCore в рантайме меняет данные конкретной стороны.
func actor_sprite(side: String) -> Sprite2D:
	return _actor_you if side == "you" else _actor_opp


# --- заготовки реакций (пока no-op; сцена статична) ---

func _on_match_started(_info: Dictionary) -> void:
	pass  # позже: выставление сцены под тему

func _on_clinch_started(_attacker: String, _defender: String, _idx: int) -> void:
	pass  # позже: акцент камеры/освещения на схватке
