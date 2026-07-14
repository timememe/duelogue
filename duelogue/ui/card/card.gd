extends Button

## DUELOGUE — ШАБЛОН КАРТЫ (переиспользуемый виджет: рука, позже редактор/кулуары/награды).
## Пропорция 3:4. Основа — прозрачный card_clean_v1.png, который работает как верхняя
## рамка/маска. Под ним лежат цвет фона заголовка и иллюстрация; над ним — только тексты.
## Скрипт заполняет контент и красит ДАННЫЕ-зависимые акценты. ТИП карты читается
## ЦВЕТОМ (слова-типа на карте нет): цвет несёт верхняя плашка; Кража — золото, Установка —
## голубой (не делят цвет — цвет теперь единственный носитель типа). Именная — аметистовая
## плашка названия. Цвета акцентов — @export, крутятся в инспекторе шаблона.
##
## Слои (сзади → вперёд, см. card.tscn):
##   прозрачная подложка Button (состояния не закрашивают альфа-поля шаблона)
##   → TitleBackground (ЦВЕТ ТИПА, виден через прозрачное окно шаблона)
##   → ArtFrame + ArtSlot (фон и иллюстрация, видны через прозрачное окно шаблона)
##   → CardTemplate (нейтральная рамка clean; внешний фон и два верхних окна прозрачны)
##   → Title (название карты)
##   → TextArea + Body (текст высказывания поверх встроенного светлого поля).
##
## Контракт: instantiate → add_child → setup(card, title, body, enabled). Корень — Button:
## интерактивные состояния не возвращают прямоугольную подложку; клик подключает view.

const C := preload("res://duelogue/core/cards/card_types.gd")
const CardArt := preload("res://duelogue/core/cards/card_art.gd")

const BODY_FONT_MAX := 10
const BODY_FONT_MIN := 7
const BODY_FIT_BOTTOM_PADDING := 2.0

@export_group("Акценты типов (плашка)")
@export var col_tezis := Color("43c59e")
@export var col_razbor := Color("e45b5b")
@export var col_krazha := Color("e5b84b")
@export var col_ustanovka := Color("57a3e3")
@export_group("Именная карта")
@export var col_named := Color("a875e8")   ## аметистовый фон заголовка вместо отдельной ленты

@onready var _template: TextureRect = %CardTemplate
@onready var _plate: ColorRect = %TitleBackground
@onready var _type_icon: TextureRect = %TypeIcon
@onready var _title: Label = %Title
@onready var _art: ColorRect = %ArtFrame
@onready var _art_slot: TextureRect = $ArtFrame/ArtSlot
@onready var _text_area: Control = %TextArea
@onready var _body: Label = %Body

var _art_texture: Texture2D
var _body_source := ""
var _body_fit_queued := false


func _ready() -> void:
	_apply_art_texture()


## Заполнить карту. art_texture — необязательная картинка; её также можно передать
## полем card.art. Без картинки остаётся нейтральный тёмный слот-плейсхолдер.
## title/body — подготовленные владельцем строки (нарратив-превью или правило именной).
func setup(card: Dictionary, title: String, body: String, enabled: bool, art_texture: Texture2D = null) -> void:
	var named: bool = card.has("named")
	var tcol := col_named if named else _type_color(card)
	_title.text = title
	_body_source = body
	_body.text = _body_source
	_type_icon.texture = CardArt.type_icon_for(card)
	# И арт, и текстовая область всегда занимают свои места. Длинный текст переносится
	# по словам в фиксированном окне, а кегль уменьшается только в безопасных пределах.
	var embedded_art: Variant = card.get("art")
	if art_texture == null and embedded_art is Texture2D:
		art_texture = embedded_art
	if art_texture == null:
		art_texture = CardArt.art_for(card, title)
	set_art_texture(art_texture)
	var title_font := 10
	if title.length() > 18:
		title_font = 7
	elif title.length() > 13:
		title_font = 8
	elif title.length() > 10:
		title_font = 9
	_title.add_theme_font_size_override("font_size", title_font)
	# Длина строки не равна её реальной высоте: переносы, длинные слова и ручные
	# переводы строк делают эвристику по количеству символов ненадёжной. После
	# первого layout подбираем кегль по фактическому числу строк в поле карты.
	_body.add_theme_font_size_override("font_size", BODY_FONT_MAX)
	_queue_body_fit()
	disabled = not enabled
	# Цвет лежит ПОД clean-шаблоном и виден только в его прозрачном окне заголовка.
	_plate.color = tcol if enabled else tcol.darkened(0.45)
	var title_color := Color("141820") if tcol.get_luminance() > 0.48 else Color("fff8ea")
	_title.add_theme_color_override("font_color", title_color if enabled else title_color.darkened(0.3))
	var a := 1.0 if enabled else 0.55
	_template.modulate.a = a
	_type_icon.modulate.a = a
	_title.modulate.a = a
	_text_area.modulate.a = a
	_body.modulate.a = 1.0
	_art.modulate.a = a


## Заменить иллюстрацию без пересоздания карты (например, после загрузки превью).
func set_art_texture(art_texture: Texture2D) -> void:
	_art_texture = art_texture
	if not is_node_ready():
		return
	_apply_art_texture()


func _apply_art_texture() -> void:
	if _art_slot == null:
		return
	_art_slot.texture = _art_texture
	_art_slot.visible = _art_texture != null


func _queue_body_fit() -> void:
	if _body_fit_queued:
		return
	_body_fit_queued = true
	call_deferred("_fit_body_to_text_area")


func _fit_body_to_text_area() -> void:
	_body_fit_queued = false
	if _text_area.size.y <= 0.0:
		_queue_body_fit()
		return
	var available_height := _text_area.size.y - BODY_FIT_BOTTOM_PADDING
	_body.text = _body_source
	for font_size in range(BODY_FONT_MAX, BODY_FONT_MIN - 1, -1):
		_body.add_theme_font_size_override("font_size", font_size)
		if _body_fits(available_height):
			return
	# Нечитаемо мелкий текст хуже аккуратного сокращения. Полная формулировка
	# остаётся доступна во всплывающей карточке на сцене дебатов.
	_truncate_body_to_fit(available_height)


func _body_fits(available_height: float) -> bool:
	return float(_body.get_line_count() * _body.get_line_height()) <= available_height


func _truncate_body_to_fit(available_height: float) -> void:
	var low := 0
	var high := _body_source.length()
	while low < high:
		var middle := int((low + high + 1) / 2.0)
		_body.text = _body_source.left(middle).strip_edges() + "…"
		if _body_fits(available_height):
			low = middle
		else:
			high = middle - 1
	_body.text = _body_source.left(low).strip_edges()
	if low < _body_source.length():
		_body.text += "…"


func _type_color(card: Dictionary) -> Color:
	match String(card.get("type", "")):
		C.TYPE_TEZIS:
			return col_tezis
		C.TYPE_USTANOVKA:
			return col_ustanovka
		C.TYPE_RAZBOR:
			return col_krazha if bool(card.get("steals", false)) else col_razbor
	return col_tezis
