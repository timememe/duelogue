extends Node

## Сквозной smoke первичных вводных: форма видит каталоги, а выбранные записи доходят до
## контроллера, сцены и ядра персонажей. Настройки меняются только в памяти процесса.

const BattleController := preload("res://duelogue/app/battle_controller.gd")
const CharacterCore := preload("res://duelogue/core/characters/character_core.gd")
const StageCore := preload("res://duelogue/core/stage/stage_core.gd")
const StageScene := preload("res://duelogue/core/stage/stage.tscn")
const SetupScene := preload("res://duelogue/ui/debate_setup.tscn")

var _failures := 0
var _old_settings := {}


func _ready() -> void:
	_old_settings = Profile.settings.duplicate(true)
	var decks := Profile.list_decks()
	_check(not decks.is_empty(), "каталог даёт хотя бы одну колоду оппонента")
	if decks.is_empty():
		_finish()
		return

	var chosen_deck: Dictionary = decks[0]
	Profile.settings["opponent_deck_id"] = String(chosen_deck.id)
	Profile.settings["opponent_character_id"] = "blue_advocate"
	Profile.settings["stage_id"] = "prototype_arena"

	var controller := BattleController.new()
	controller.logging_enabled = false
	add_child(controller)
	_check(controller._opponent_deck() == chosen_deck.deck,
		"контроллер получает выбранный состав колоды ИИ")
	controller.start_match()
	var opp_side: Dictionary = controller.model.sides[BattleController.SIDE_OPP]
	var composition := _deck_composition(opp_side)
	_check(composition.u == int(chosen_deck.deck.u)
		and composition.t == int(chosen_deck.deck.t)
		and composition.r == int(chosen_deck.deck.r),
		"сторона оппонента реально пересобрана из выбранной колоды (%s → %s)" % [
			str(chosen_deck.deck), str(composition)])

	var stage = StageScene.instantiate()
	add_child(stage)
	var expected_stage: Dictionary = StageCore.catalog_entry("prototype_arena")
	_check((stage.get_node("Bg") as TextureRect).texture == expected_stage.texture,
		"stage_core применяет выбранное окружение")

	var characters := CharacterCore.new()
	characters.bind(stage, null)
	add_child(characters)
	var expected_character: Dictionary = CharacterCore.catalog_entry("blue_advocate")
	_check(stage.actor_sprite("opp").texture == (expected_character.states as Dictionary).idle,
		"character_core ставит выбранный state-map на сторону оппонента")

	var setup = SetupScene.instantiate()
	add_child(setup)
	_check((setup.get_node("%CharacterOption") as OptionButton).item_count == CharacterCore.catalog_entries().size(),
		"форма показывает весь каталог персонажей")
	_check((setup.get_node("%OpponentDeckOption") as OptionButton).item_count == decks.size(),
		"форма показывает весь каталог колод")
	_check((setup.get_node("%StageOption") as OptionButton).item_count == StageCore.catalog_entries().size(),
		"форма показывает весь каталог сцен")
	_check((setup.get_node("%ThemeOption") as OptionButton).item_count == ThemeLibrary.list_themes().size(),
		"форма показывает всю библиотеку тем")
	_finish()


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		_failures += 1


func _deck_composition(side: Dictionary) -> Dictionary:
	var result := {"u": 0, "t": 0, "r": 0}
	var cards: Array = []
	cards.append_array(side.get("hand", []))
	cards.append_array(side.get("draw", []))
	cards.append_array(side.get("discard", []))
	for raw_line in side.get("lines", []):
		var line: Dictionary = raw_line
		cards.append_array(line.get("thesis_stack", []))
	for raw in cards:
		var card: Dictionary = raw
		var type := String(card.get("type", "")).to_lower()
		if result.has(type):
			result[type] += 1
	return result


func _finish() -> void:
	Profile.settings = _old_settings
	print("=== DEBATE SETUP: %s ===" % ("OK" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)
