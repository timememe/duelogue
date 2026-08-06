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

## Аура огня подгоняется под РЕАЛЬНЫЙ размер спрайта актёра (texture.get_size() * scale),
## не на глаз — так рамка всегда "ровно" под конкретным актёром, даже если скин заменят
## через set_stage_sprite_texture другим холстом. Доли — множители относительно роста/ширины
## самого спрайта, не абсолютные пиксели.
const FIRE_WIDTH_SCALE := 1.4    ## шире силуэта — языки видны и по бокам, не только сквозь
const FIRE_HEIGHT_SCALE := 1.05  ## чуть выше роста — есть куда расти языкам над макушкой
const FIRE_BOTTOM_LIFT := 0.03   ## подошва чуть утоплена от нижнего края спрайта (доля роста)

@onready var _actor_you: Sprite2D = %ActorYou
@onready var _actor_opp: Sprite2D = %ActorOpp
@onready var _bg: TextureRect = $Bg
@onready var _actors: Node2D = %Actors
@onready var _props_front: Node2D = $PropsFront
@onready var _fire_you: ColorRect = %FireYou
@onready var _fire_opp: ColorRect = %FireOpp

var _bg_base := Vector2.ZERO
var _actors_base := Vector2.ZERO
var _props_front_base := Vector2.ZERO
var _parallax_offset := Vector2.ZERO


func _ready() -> void:
	EventBus.match_started.connect(_on_match_started)
	EventBus.clinch_started.connect(_on_clinch_started)
	EventBus.emotion_changed.connect(_on_emotion_changed)
	_bg_base = _bg.position
	_actors_base = _actors.position
	_props_front_base = _props_front.position
	_fit_fire_to_actor(_fire_you, _actor_you)
	_fit_fire_to_actor(_fire_opp, _actor_opp)


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

## Огонь запала не переживает партию: emotion.start() в battle_controller молча обнуляет
## strain обеих сторон (без своего emotion_changed) — гасим ауру сами, иначе на новой партии
## мелькнёт огонь, оставшийся от конца предыдущей.
func _on_match_started(_info: Dictionary) -> void:
	_set_fire_intensity(_fire_you, 0.0)
	_set_fire_intensity(_fire_opp, 0.0)

func _on_clinch_started(_attacker: String, _defender: String, _idx: int) -> void:
	pass  # позже: акцент камеры/освещения на схватке


## Огонь позади персонажа на общем плане — прямое чтение EventBus.emotion_changed (тот же
## приём, что character_core слушает utterance/impact напрямую), без общего resolve-моста.
## state — снимок EmotionCore.state(side): {strain, max, ...}; intensity шейдера = strain/max.
func _on_emotion_changed(side: String, state: Dictionary) -> void:
	var maximum := maxi(1, int(state.get("max", 6)))
	var strain := clampi(int(state.get("strain", 0)), 0, maximum)
	var fire := _fire_you if side == "you" else _fire_opp
	_set_fire_intensity(fire, float(strain) / float(maximum))


func _set_fire_intensity(fire: ColorRect, value: float) -> void:
	(fire.material as ShaderMaterial).set_shader_parameter("intensity", value)


## Ставит рамку ColorRect точно вокруг силуэта actor: центр по X — тот же, что у спрайта;
## подошва — у нижнего края спрайта (актёры в stage.tscn все centered=true, position = центр).
func _fit_fire_to_actor(fire: ColorRect, actor: Sprite2D) -> void:
	if actor.texture == null:
		return
	var actor_size := Vector2(actor.texture.get_size()) * actor.scale
	var fire_size := Vector2(actor_size.x * FIRE_WIDTH_SCALE, actor_size.y * FIRE_HEIGHT_SCALE)
	var bottom := actor.position.y + actor_size.y * (0.5 - FIRE_BOTTOM_LIFT)
	fire.position = Vector2(actor.position.x - fire_size.x * 0.5, bottom - fire_size.y)
	fire.size = fire_size
