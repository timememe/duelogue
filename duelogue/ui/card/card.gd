extends Button

## DUELOGUE — ШАБЛОН КАРТЫ (переиспользуемый виджет: рука, позже редактор/кулуары/награды).
## Пропорция 4:6. Дизайн авторится СЛОЯМИ-НОДАМИ в card.tscn и правится в редакторе Godot;
## скрипт только заполняет контент и красит ДАННЫЕ-зависимые акценты. ТИП карты читается
## ЦВЕТОМ (слова-типа на карте нет): цвет несёт верхняя плашка; Кража — золото, Установка —
## голубой (не делят цвет — цвет теперь единственный носитель типа). Именная — золотая
## рамка + лента. Цвета акцентов — @export, крутятся в инспекторе шаблона.
##
## Слои (сзади → вперёд, см. card.tscn):
##   подложка Button (стили normal/hover/pressed/disabled — StyleBoxFlat в инспекторе)
##   → Frame (рамка карты: нейтральная / золото именной)
##   → TitlePlate (верхняя плашка ЦВЕТА ТИПА) + Title (название карты, тёмный текст)
##   → ArtFrame (окошко арта в верхней трети; серая рамка-плейсхолдер)
##     + ArtSlot (TextureRect под будущий арт, скрыт)
##   → Body (нижние ~2/3 — зона текста высказывания/правила)
##   → NamedRibbon (метка именного приёма внизу).
##
## Контракт: instantiate → add_child → setup(card, title, body, enabled). Корень — Button:
## pressed/hover/disabled бесплатно; клик подключает владелец (view).

const C := preload("res://duelogue/core/cards/card_types.gd")

@export_group("Акценты типов (плашка)")
@export var col_tezis := Color("6fcf7f")
@export var col_razbor := Color("d9594c")
@export var col_krazha := Color("ffd24a")
@export var col_ustanovka := Color("6fb7cf")
@export_group("Рамка")
@export var col_frame := Color("2c3340")   ## нейтральная рамка обычной карты
@export var col_named := Color("ffd24a")   ## рамка/лента именного приёма

@onready var _frame: Panel = %Frame
@onready var _plate: ColorRect = %TitlePlate
@onready var _title: Label = %Title
@onready var _art: Panel = %ArtFrame
@onready var _body: Label = %Body
@onready var _ribbon: Label = %NamedRibbon

var _frame_sb: StyleBoxFlat


func _ready() -> void:
	# Личный экземпляр стайлбокса рамки: сабресурсы сцены ОБЩИЕ у всех инстансов,
	# а цвет рамки у каждой карты свой (именная/обычная) — иначе карты красили бы друг друга.
	_frame_sb = (_frame.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	_frame.add_theme_stylebox_override("panel", _frame_sb)


## Заполнить карту. card — словарь ядра ({type, name, steals, named?, text?});
## title/body — подготовленные владельцем строки (нарратив-превью или правило именной).
func setup(card: Dictionary, title: String, body: String, enabled: bool) -> void:
	var named: bool = card.has("named")
	var tcol := _type_color(card)
	_title.text = title
	_body.text = body
	_ribbon.visible = named
	disabled = not enabled
	# Приглушение неиграбельной: акценты гаснут, подложку ведёт stylebox disabled.
	_plate.color = tcol if enabled else tcol.darkened(0.45)
	_frame_sb.border_color = (col_named if named else col_frame) if enabled \
		else (col_named.darkened(0.45) if named else col_frame)
	_ribbon.add_theme_color_override("font_color", col_named if enabled else col_named.darkened(0.45))
	var a := 1.0 if enabled else 0.55
	_title.modulate.a = a
	_body.modulate.a = a
	_art.modulate.a = a


func _type_color(card: Dictionary) -> Color:
	match String(card.get("type", "")):
		C.TYPE_TEZIS:
			return col_tezis
		C.TYPE_USTANOVKA:
			return col_ustanovka
		C.TYPE_RAZBOR:
			return col_krazha if bool(card.get("steals", false)) else col_razbor
	return col_tezis
