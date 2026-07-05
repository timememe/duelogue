extends Control

## DUELOGUE — ЯДРО СЦЕНЫ. Скрипт сцены stage.tscn (декорации арены ПОЗАДИ всего UI).
## Визуал авторится НОДАМИ в редакторе (фон Bg, кафедры PropsFront/Pulpit*, слоты Slot*),
## скрипт лишь ссылается на них — поэтому всё можно двигать/настраивать мышкой в Godot.
## Слои сцены (сзади→вперёд): Bg → Actors (спрайты персонажей кладёт character_core) →
## PropsFront (кафедры спереди). Режиссура (камера/свет) — забота этого ядра; пока статично.

@onready var actors: Node2D = %Actors  ## слой актёров между фоном и кафедрами


func _ready() -> void:
	EventBus.match_started.connect(_on_match_started)
	EventBus.clinch_started.connect(_on_clinch_started)


# --- API для ядра персонажей ---

## Слой, в который кладутся спрайты актёров (рисуются ЗА кафедрами).
func actor_layer() -> Node2D:
	return actors

## Точка кафедры стороны (центр спрайта актёра) — маркер, который двигаешь в редакторе.
func slot(side: String) -> Vector2:
	if side == "you":
		return %SlotYou.position
	return %SlotOpp.position


# --- заготовки реакций (пока no-op; сцена статична) ---

func _on_match_started(_info: Dictionary) -> void:
	pass  # позже: выставление сцены под тему

func _on_clinch_started(_attacker: String, _defender: String, _idx: int) -> void:
	pass  # позже: акцент камеры/освещения на схватке
