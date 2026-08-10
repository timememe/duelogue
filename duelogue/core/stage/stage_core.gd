extends Control

## DUELOGUE — ЯДРО СЦЕНЫ. Скрипт сцены stage.tscn (декорации арены ПОЗАДИ всего UI).
## Визуал авторится НОДАМИ в редакторе (фон Bg, Actors/Actor*+Fire*, кафедры PropsFront/
## Pulpit*), скрипт лишь ссылается на них — поэтому всё можно двигать/настраивать мышкой в
## Godot. Слои сцены (сзади→вперёд): Bg → Actors (постоянные Sprite2D персонажей + аура
## FireYou/FireOpp МЕЖДУ фоном и спрайтом самого актёра — порядок нод в Actors ЭТО порядок
## отрисовки, отсюда родом) → PropsFront (кафедры спереди). Позиция/размер Fire* — такие же
## авторские числа, как у Actor*/Pulpit*, двигаются мышкой прямо тут (открыть stage.tscn —
## тот же файл, где стоят сами актёры, самый прямой визуальный контекст); fire_lab.tscn
## по-прежнему калибрует форму/цвет/турбулентность шейдера. Режиссура (камера/свет) — забота
## этого ядра; лёгкий мышиный параллакс (Parallax, 2026-07-25) — первый шаг: каждый слой
## держит авторскую позицию и сдвигается на общий сглаженный офсет мыши своей силой (дальше =
## меньше). Полноценная режиссура (акценты клинча/темы) по-прежнему впереди — заготовки ниже.

const Parallax := preload("res://duelogue/core/stage/parallax.gd")
const COURTROOM_BG := preload("res://duelogue/assets/bg_courtroom_v2.png")
const PROTOTYPE_BG := preload("res://duelogue/assets/archive/legacy_pixel_character/bg_test.png")
const PARALLAX_BG := 5.0
const PARALLAX_ACTORS := 12.0
const PARALLAX_PROPS_FRONT := 20.0

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


## Каталог окружений для меню подготовки. Пока сцены отличаются фоном и атмосферой, а
## общая геометрия актёров/кафедр остаётся в stage.tscn и продолжает правиться в редакторе.
static func catalog_entries() -> Array:
	return [
		{
			"id": "courtroom",
			"name": "Зал Арбитража",
			"description": "Основная сцена: тёмный зал с золотыми трибунами и весами.",
			"texture": COURTROOM_BG,
		},
		{
			"id": "prototype_arena",
			"name": "Прототипная арена",
			"description": "Светлая пиксельная сцена из раннего прототипа DUELOGUE.",
			"texture": PROTOTYPE_BG,
		},
	]


static func catalog_entry(id: String) -> Dictionary:
	for raw in catalog_entries():
		var entry: Dictionary = raw
		if String(entry.id) == id:
			return entry.duplicate(true)
	return {}


func _ready() -> void:
	_apply_selected_stage()
	EventBus.match_started.connect(_on_match_started)
	EventBus.clinch_started.connect(_on_clinch_started)
	EventBus.emotion_changed.connect(_on_emotion_changed)
	_bg_base = _bg.position
	_actors_base = _actors.position
	_props_front_base = _props_front.position


func _apply_selected_stage() -> void:
	var prof := get_node_or_null("/root/Profile")
	var id := String(prof.settings.get("stage_id", "courtroom")) if prof != null else "courtroom"
	var entry := catalog_entry(id)
	if entry.is_empty():
		entry = catalog_entry("courtroom")
	var texture := entry.get("texture") as Texture2D
	if texture != null:
		_bg.texture = texture


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


## Аура огня конкретной стороны: position/size — авторские числа в stage.tscn (как у
## actor_sprite), правятся мышкой там же; дев-тулам (fire_lab) — для калибровки шейдер-
## параметров на боевом материале ColorRect, без копирования сцены.
func fire_rect(side: String) -> ColorRect:
	return _fire_you if side == "you" else _fire_opp


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
