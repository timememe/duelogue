extends Control

## DUELOGUE — КАТАЛОГ КОМБО: все маршруты грамматики одним экраном, СОБРАННЫЕ ИЗ НАСТОЯЩИХ
## КАРТ (ui/card/card.tscn) — тот же виджет, что в руке. Данные читаются из онтологии
## (grammar.gd ANSWER_OF) напрямую — каталог всегда синхронен коду и руками не ведётся.
##
## Раскладка на группу схемы: одна карта-Тезис слева (наживка, вооружает LINK своим
## присутствием сверху рамки) + справа колонка веток — каждая ветка: карта-Разбор с
## зацепкой (что бьёт наживку) → карта(-ы)-Тезис (чем вооружать ответ) → имя комбо.
## Цвет карты несёт ТИП (зелёный Тезис/красный Разбор — как в руке); масть схемы (Логос/
## Этос/Пафос) — рамка и чип группы, второй, более крупный слой группировки.

const Grammar := preload("res://duelogue/core/cards/grammar.gd")
const CardScene := preload("res://duelogue/ui/card/card.tscn")

const SUIT_RU := {"logos": "Логос", "ethos": "Этос", "pathos": "Пафос"}
const SUIT_COLOR := {"logos": "4fb8d0", "ethos": "d9a441", "pathos": "d9678c"}

const COL_GOLD := "e5b84b"
const COL_DIM := "8a93a3"
const COL_BG := "05080c"
const COL_TEXT := "e8e8e8"

const SETUP_SCALE := 0.86
const BRANCH_SCALE := 0.58

@onready var _list: VBoxContainer = %RouteList
@onready var _title: Label = %CatalogTitle


func _ready() -> void:
	_build()


## Карты обоймы, несущие схему Тезиса (reverse фабричного CARD_SCHEME).
func _cards_of_scheme(scheme: String) -> String:
	var names: Array = []
	for nm in Grammar.CARD_SCHEME:
		if String(Grammar.CARD_SCHEME[nm]) == scheme:
			names.append(String(nm))
	return " / ".join(names)


## Карты обоймы, бьющие этим приёмом (reverse фабричного CARD_DEVICE).
func _cards_of_device(device: String) -> String:
	var names: Array = []
	for nm in Grammar.CARD_DEVICE:
		if String(Grammar.CARD_DEVICE[nm]) == device:
			names.append(String(nm))
	return " / ".join(names)


## Приём, хватающий за эту зацепку (HOOK_OF биективен: 7 приёмов → 7 зацепок).
func _device_of_hook(hook: String) -> String:
	for device in Grammar.HOOK_OF:
		if String(Grammar.HOOK_OF[device]) == hook:
			return String(device)
	return hook


func _build() -> void:
	for c in _list.get_children():
		c.queue_free()
	# Карты собираются в детально detached-поддереве (обычные .new()/add_child без сцены) —
	# setup() трогает @onready-поля шаблона, которые резолвятся только в _ready(). Поэтому
	# сперва достраиваем и вешаем на живое дерево ВСЮ группу схемы, и только потом, когда
	# у всех вложенных карт уже отработал _ready(), вызываем setup() по накопленному списку.
	var pending: Array = []
	var total := 0
	for scheme in Grammar.ANSWER_OF:
		var by_hook: Dictionary = Grammar.ANSWER_OF[scheme]
		total += by_hook.size()
		_list.add_child(_build_scheme_group(String(scheme), by_hook, pending))
	for entry in pending:
		var inst: Button = entry[0]
		var card: Dictionary = entry[1]
		inst.setup(card, String(entry[2]), String(entry[3]), true)
		var k: float = entry[4]
		inst.scale = Vector2(k, k)
		inst.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inst.focus_mode = Control.FOCUS_NONE
	_title.text = "КОМБО-МАРШРУТЫ · %d" % total


func _build_scheme_group(scheme: String, by_hook: Dictionary, pending: Array) -> PanelContainer:
	var suit := String(Grammar.SUIT_OF.get(scheme, ""))
	var suit_col := String(SUIT_COLOR.get(suit, COL_DIM))

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.html("#" + COL_BG).lerp(Color.html("#" + suit_col), 0.06)
	sb.border_color = Color.html("#" + suit_col)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	vbox.add_child(_build_header(scheme, suit, suit_col))
	vbox.add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	vbox.add_child(body)

	var setup_card := {"type": "T", "scheme": scheme, "suit": suit, "combo_eligible": true}
	var hooks: Array = Grammar.OPEN_HOOKS.get(scheme, [])
	var setup_body := "Открытые зацепки:\n%s" % ", ".join(hooks)
	var setup_wrap := _card_wrap(setup_card, scheme, setup_body, SETUP_SCALE, pending)
	setup_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_child(setup_wrap)

	var branches := VBoxContainer.new()
	branches.add_theme_constant_override("separation", 10)
	body.add_child(branches)
	for hook in by_hook:
		branches.add_child(_build_branch(String(hook), by_hook[hook], pending))

	return panel


func _build_header(scheme: String, suit: String, suit_col: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.html("#" + suit_col).darkened(0.55)
	sb.border_color = Color.html("#" + suit_col)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	chip.add_theme_stylebox_override("panel", sb)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var chip_label := Label.new()
	chip_label.text = String(SUIT_RU.get(suit, suit)).to_upper()
	chip_label.add_theme_font_size_override("font_size", 12)
	chip_label.add_theme_color_override("font_color", Color.html("#" + suit_col).lightened(0.35))
	chip.add_child(chip_label)
	row.add_child(chip)

	var title := Label.new()
	title.text = scheme.to_upper()
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color.html("#" + COL_TEXT))
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)

	var deck_names := Label.new()
	deck_names.text = "· наживка в обойме: %s" % _cards_of_scheme(scheme)
	deck_names.add_theme_font_size_override("font_size", 12)
	deck_names.add_theme_color_override("font_color", Color.html("#" + COL_DIM))
	deck_names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(deck_names)
	return row


## Ветка — своя колонка: имя комбо ОТДЕЛЬНОЙ строкой сверху (не втиснуто в общую
## HBoxContainer-строку с картами) — иначе на маршрутах с двумя answer_schemes ярлыку не
## остаётся ширины и autowrap схлопывает его в вертикальный столбик по букве на строку.
func _build_branch(hook: String, rec: Dictionary, pending: Array) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)

	var name_label := Label.new()
	name_label.text = "⚡ «%s»" % String(rec.get("combo_name", ""))
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color.html("#" + COL_GOLD))
	col.add_child(name_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)

	var fork := Label.new()
	fork.text = "↳"
	fork.add_theme_font_size_override("font_size", 16)
	fork.add_theme_color_override("font_color", Color.html("#" + COL_DIM))
	fork.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(fork)

	var device := _device_of_hook(hook)
	var attack_card := {"type": "R", "device": device, "hook": hook, "combo_eligible": true}
	var attack_body := "Зацепка «%s»\nОбойма: %s" % [hook, _cards_of_device(device)]
	var attack_wrap := _card_wrap(attack_card, device, attack_body, BRANCH_SCALE, pending)
	attack_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(attack_wrap)

	row.add_child(_arrow_label(COL_GOLD))

	var answer_schemes: Array = rec.get("answer_schemes", [])
	for i in answer_schemes.size():
		var ans := String(answer_schemes[i])
		var answer_card := {"type": "T", "scheme": ans, "combo_eligible": true}
		var answer_body := "Вооружает комбо\nОбойма: %s" % _cards_of_scheme(ans)
		var answer_wrap := _card_wrap(answer_card, ans, answer_body, BRANCH_SCALE, pending)
		answer_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(answer_wrap)
		if i < answer_schemes.size() - 1:
			var or_label := Label.new()
			or_label.text = "или"
			or_label.add_theme_font_size_override("font_size", 12)
			or_label.add_theme_color_override("font_color", Color.html("#" + COL_DIM))
			or_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(or_label)

	return col


func _arrow_label(colhex: String) -> Label:
	var l := Label.new()
	l.text = "→"
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color.html("#" + colhex))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## Заворачивает Card в Control фиксированного thumbnail-размера (custom_minimum_size задаёт
## контейнеру место в layout) и откладывает setup() в pending — см. _build().
func _card_wrap(card: Dictionary, title: String, body: String, scale_k: float, pending: Array) -> Control:
	var inst: Button = CardScene.instantiate()
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(141, 188) * scale_k
	wrap.add_child(inst)
	pending.append([inst, card, title, body, scale_k])
	return wrap
