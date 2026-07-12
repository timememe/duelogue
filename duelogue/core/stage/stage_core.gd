extends Control

## DUELOGUE — ЯДРО СЦЕНЫ. Скрипт сцены stage.tscn (декорации арены ПОЗАДИ всего UI).
## Визуал авторится НОДАМИ в редакторе (фон Bg, Actors/Actor*, кафедры PropsFront/Pulpit*),
## скрипт лишь ссылается на них — поэтому всё можно двигать/настраивать мышкой в Godot.
## Слои сцены (сзади→вперёд): Bg → Actors (постоянные Sprite2D персонажей) →
## PropsFront (кафедры спереди). Режиссура (камера/свет) — забота этого ядра; пока статично.

@onready var _actor_you: Sprite2D = %ActorYou
@onready var _actor_opp: Sprite2D = %ActorOpp


func _ready() -> void:
	EventBus.match_started.connect(_on_match_started)
	EventBus.clinch_started.connect(_on_clinch_started)


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
