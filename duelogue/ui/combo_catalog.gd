extends Control

## DUELOGUE — КАТАЛОГ КОМБО: все маршруты грамматики одним экраном. Данные читаются из
## онтологии (grammar.gd ANSWER_OF) напрямую — каталог всегда синхронен коду и руками не
## ведётся. Формат маршрута: setup-Тезис сверху рамки → зацепка Разбора → правильный
## Тезис-ответ вооружает комбо (ARMED); финишер пережил клинч — CONFIRMED.

const Grammar := preload("res://duelogue/core/cards/grammar.gd")

const SUIT_RU := {"logos": "Логос", "ethos": "Этос", "pathos": "Пафос"}
# Цвета — те же, что на доске: тезисы зелёные, атаки красные, золото акцентов.
const COL_SETUP := "e5b84b"
const COL_ATTACK := "e45b5b"
const COL_ANSWER := "43c59e"
const COL_DIM := "8a93a3"

@onready var _routes: RichTextLabel = %Routes
@onready var _title: Label = %CatalogTitle


func _ready() -> void:
	%BackBtn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://duelogue/ui/main_menu.tscn"))
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
	var total := 0
	var text := ""
	for scheme in Grammar.ANSWER_OF:
		var suit := String(SUIT_RU.get(String(Grammar.SUIT_OF.get(scheme, "")), ""))
		text += "[b][color=#%s]%s[/color][/b] [color=#%s]· %s · наживка в обойме: %s[/color]\n" % [
			COL_SETUP, String(scheme).to_upper(), COL_DIM, suit, _cards_of_scheme(scheme)]
		var by_hook: Dictionary = Grammar.ANSWER_OF[scheme]
		for hook in by_hook:
			total += 1
			var rec: Dictionary = by_hook[hook]
			var device := _device_of_hook(String(hook))
			var answer_parts: Array = []
			for ans in rec.get("answer_schemes", []):
				answer_parts.append("[color=#%s]%s[/color] [color=#%s](%s)[/color]" % [
					COL_ANSWER, String(ans), COL_DIM, _cards_of_scheme(String(ans))])
			text += "    [color=#%s]%s[/color] [color=#%s](%s · зацепка «%s»)[/color]  →  %s   [b]«%s»[/b]\n" % [
				COL_ATTACK, device, COL_DIM, _cards_of_device(device), String(hook),
				" или ".join(answer_parts), String(rec.get("combo_name", ""))]
		text += "\n"
	_routes.text = text
	_title.text = "КОМБО-МАРШРУТЫ · %d" % total
