extends Control

## DUELOGUE — РЕДАКТОР КОЛОДЫ (обоймы). Ручная сборка стороны игрока: счётчики базовых
## типов + именные приёмы (по 1 копии, §10.2; каждый ЗАМЕЩАЕТ ванильную карту своей базы
## внутри счётчиков — размер обоймы задают счётчики). Пишет в autoload Profile; битва
## читает оттуда (battle_controller._player_deck). Каркас — нодами в deck_editor.tscn
## (правится в редакторе); ряды счётчиков и список приёмов строятся кодом из реестра.
##
## Канон и коридоры — индикаторы, не запреты: полигон должен позволять и заведомо кривые
## обоймы (симы D/A показали цену краёв — редактор их подсвечивает, но не запрещает).

const NamedCards := preload("res://duelogue/core/cards/named_cards.gd")
const C := preload("res://duelogue/core/cards/card_types.gd")

const CANON_TOTAL := 20
const SLOT_MAX := 15
## Ряды счётчиков: ключ рабочей обоймы → лейбл + сим-коридор (подсветка краёв).
const SLOT_DEFS := [
	{"key": "u", "label": "Установки", "lo": 2, "hi": 5},
	{"key": "t", "label": "Тезисы", "lo": 6, "hi": 10},
	{"key": "plain", "label": "Разборы (обычные)", "lo": 4, "hi": 10},
	{"key": "steals", "label": "Кражи", "lo": 1, "hi": 3},
]

var _deck := {}           ## рабочая копия: {u, t, plain, steals, named: []}
var _count_labels := {}   ## key → Label счётчика
var _named_checks := {}   ## id приёма → CheckBox

@onready var _slots_box: VBoxContainer = %SlotsBox
@onready var _named_box: VBoxContainer = %NamedBox
@onready var _total_label: Label = %TotalLabel
@onready var _warn_label: Label = %WarnLabel
@onready var _save_btn: Button = %SaveBtn


func _ready() -> void:
	%BackBtn.pressed.connect(_to_menu)
	_save_btn.pressed.connect(_save)
	%PresetClassicBtn.pressed.connect(_preset.bind(false))
	%PresetNamedBtn.pressed.connect(_preset.bind(true))
	_deck = _from_profile(Profile.deck)
	_build_slot_rows()
	_build_named_list()
	_refresh()


# ------------------------------------------------ рабочая обойма ↔ профиль ----

## Профиль хранит r = ВСЕ атаки (контракт Deck.build_side); редактор разводит на
## «обычные разборы» и «кражи» — так счётчики читаются как слоты.
func _from_profile(d: Dictionary) -> Dictionary:
	var steals := int(d.get("steals", 2))
	return {
		"u": int(d.get("u", 3)), "t": int(d.get("t", 8)),
		"plain": maxi(0, int(d.get("r", 9)) - steals), "steals": steals,
		"named": (d.get("named", []) as Array).duplicate(),
	}


func _to_profile() -> Dictionary:
	return {
		"u": int(_deck.u), "t": int(_deck.t),
		"r": int(_deck.plain) + int(_deck.steals), "steals": int(_deck.steals),
		"named": (_deck.named as Array).duplicate(),
	}


# ------------------------------------------------------------- динамика UI ----

func _build_slot_rows() -> void:
	for def in SLOT_DEFS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var name_l := Label.new()
		name_l.text = "%s  (коридор %d–%d)" % [def.label, int(def.lo), int(def.hi)]
		name_l.custom_minimum_size = Vector2(280, 0)
		name_l.add_theme_font_size_override("font_size", 14)
		row.add_child(name_l)
		var minus := Button.new()
		minus.text = "−"
		minus.custom_minimum_size = Vector2(34, 30)
		minus.pressed.connect(_bump.bind(String(def.key), -1))
		row.add_child(minus)
		var count_l := Label.new()
		count_l.custom_minimum_size = Vector2(44, 0)
		count_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_l.add_theme_font_size_override("font_size", 17)
		row.add_child(count_l)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(34, 30)
		plus.pressed.connect(_bump.bind(String(def.key), 1))
		row.add_child(plus)
		_slots_box.add_child(row)
		_count_labels[String(def.key)] = count_l


func _build_named_list() -> void:
	for id in NamedCards.ids():
		var card := NamedCards.make(String(id))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var check := CheckBox.new()
		check.text = "%s — %s" % [String(card.name), _base_label(card)]
		check.tooltip_text = String(card.text)
		check.add_theme_font_size_override("font_size", 14)
		check.button_pressed = (_deck.named as Array).has(id)
		check.toggled.connect(_on_named_toggled.bind(String(id)))
		box.add_child(check)
		var rule := Label.new()
		rule.text = String(card.text)
		rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rule.custom_minimum_size = Vector2(0, 0)
		rule.add_theme_font_size_override("font_size", 11)
		rule.add_theme_color_override("font_color", Color(0.63, 0.67, 0.74))
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(rule)
		_named_box.add_child(box)
		_named_checks[String(id)] = check


func _base_label(card: Dictionary) -> String:
	match String(card.type):
		C.TYPE_TEZIS: return "Тезис"
		C.TYPE_USTANOVKA: return "Установка"
		C.TYPE_RAZBOR: return "Кража" if bool(card.get("steals", false)) else "Разбор"
	return "?"


# ---------------------------------------------------------------- интенты -----

func _bump(key: String, delta: int) -> void:
	_deck[key] = clampi(int(_deck[key]) + delta, 0, SLOT_MAX)
	_refresh()


func _on_named_toggled(pressed: bool, id: String) -> void:
	var named: Array = _deck.named
	if pressed and not named.has(id):
		named.append(id)
	elif not pressed:
		named.erase(id)
	_refresh()


func _preset(with_named: bool) -> void:
	_deck = _from_profile(Profile.classic())
	if with_named:
		_deck.named = NamedCards.ids().duplicate()
	for id in _named_checks:
		(_named_checks[id] as CheckBox).set_pressed_no_signal((_deck.named as Array).has(id))
	_refresh()


func _save() -> void:
	Profile.set_deck(_to_profile())
	_warn_label.add_theme_color_override("font_color", Color(0.44, 0.81, 0.5))
	_warn_label.text = "Сохранено — эта обойма пойдёт в следующую катку."


func _to_menu() -> void:
	get_tree().change_scene_to_file("res://duelogue/ui/main_menu.tscn")


# ----------------------------------------------------------------- рендер -----

func _refresh() -> void:
	for def in SLOT_DEFS:
		var key := String(def.key)
		var l: Label = _count_labels[key]
		l.text = str(int(_deck[key]))
		var v := int(_deck[key])
		# Подсветка краёв сим-коридоров (жёлтым): играть можно, но цена известна (§11.4).
		l.add_theme_color_override("font_color",
			Color(0.91, 0.91, 0.91) if v >= int(def.lo) and v <= int(def.hi) else Color(1.0, 0.82, 0.29))
	var total := int(_deck.u) + int(_deck.t) + int(_deck.plain) + int(_deck.steals)
	var named_n := (_deck.named as Array).size()
	_total_label.text = "Всего карт: %d  (канон %d)   ·   именных внутри: %d" % [total, CANON_TOTAL, named_n]
	_total_label.add_theme_color_override("font_color",
		Color(0.44, 0.81, 0.5) if total == CANON_TOTAL else Color(1.0, 0.82, 0.29))
	# Валидация замен: именных приёмов базы не может быть больше, чем карт этой базы.
	var warn := _validate()
	_warn_label.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
	_warn_label.text = warn
	_save_btn.disabled = warn != ""


func _validate() -> String:
	if int(_deck.u) < 1:
		return "Нужна минимум 1 Установка: opening закрепляет её как публичный резерв от нокаута."
	var need := {"u": 0, "t": 0, "plain": 0, "steals": 0}
	for id in _deck.named:
		var card := NamedCards.make(String(id))
		if card.is_empty():
			continue
		match String(card.type):
			C.TYPE_USTANOVKA: need.u += 1
			C.TYPE_TEZIS: need.t += 1
			C.TYPE_RAZBOR:
				if bool(card.get("steals", false)):
					need.steals += 1
				else:
					need.plain += 1
	var labels := {"u": "Установок", "t": "Тезисов", "plain": "Разборов", "steals": "Краж"}
	for key in need:
		if int(need[key]) > int(_deck[key]):
			return "Именных приёмов базы «%s» больше, чем карт в счётчике (%d > %d) — добавь карт или сними приём." % [
				labels[key], int(need[key]), int(_deck[key])]
	return ""
