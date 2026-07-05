class_name ComboResolver
extends RefCounted

## Matches the current ComboTrack window against a list of ComboRecipes.
## Recipes are loaded from data/combos/*.json and tested in file order.

var recipes: Array[ComboRecipe] = []


func add_recipe(recipe: ComboRecipe) -> void:
	if recipe != null:
		recipes.append(recipe)


func clear_recipes() -> void:
	recipes.clear()


func load_recipes_from_file(path: String) -> int:
	## Loads recipes from a JSON file. Returns count loaded.
	## Implemented now so Phase 3 only needs to author the JSON.
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("ComboResolver: не удалось открыть файл рецептов: %s" % path)
		return 0
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error("ComboResolver: ошибка JSON в %s: %s" % [path, json.get_error_message()])
		return 0
	var data = json.data
	if not data is Array:
		push_error("ComboResolver: ожидался JSON-массив верхнего уровня в %s" % path)
		return 0

	var count := 0
	for entry in data:
		if entry is Dictionary:
			add_recipe(ComboRecipe.from_dict(entry))
			count += 1
	return count


## Returns the first recipe whose pattern matches the tail of the track, or null.
## Matching aligns the pattern to the END of the window (last slot of pattern
## must match the most recent entry). Patterns shorter than the window are
## still tested against the trailing slice.
func check(track: ComboTrack) -> ComboRecipe:
	if track == null:
		return null
	return check_window(track.get_window())


## Same as `check` but accepts a pre-built window. Used to evaluate recipes from
## the opponent's perspective by passing a window with owner labels flipped.
func check_window(window: Array) -> ComboRecipe:
	for recipe in recipes:
		if recipe == null or recipe.pattern.is_empty():
			continue
		if recipe.pattern.size() > window.size():
			if recipe.recipe_type == ComboRecipe.TYPE_BAIT:
				var _is_waiting := _matches_available_prefix(recipe, window)
			continue
		if _matches(recipe, window):
			return recipe
	return null


func _matches(recipe: ComboRecipe, window: Array) -> bool:
	var pattern: Array = recipe.pattern
	var offset := window.size() - pattern.size()
	for i in pattern.size():
		var slot: Dictionary = pattern[i]
		var entry: Dictionary = window[offset + i]
		if not recipe.slot_matches(slot, entry):
			return false
		if not _same_card_constraint_matches(slot, window, offset, i):
			return false
	return true


func _matches_available_prefix(recipe: ComboRecipe, window: Array) -> bool:
	## For bait recipes longer than the visible window, validate the available
	## prefix so callers can later expose a "bait armed" UI without firing early.
	var pattern: Array = recipe.pattern
	var count := mini(pattern.size(), window.size())
	for i in count:
		var slot: Dictionary = pattern[i]
		var entry: Dictionary = window[i]
		if not recipe.slot_matches(slot, entry):
			return false
		if not _same_card_constraint_matches(slot, window, 0, i):
			return false
	return count > 0


func _same_card_constraint_matches(slot: Dictionary, window: Array, offset: int, index: int) -> bool:
	if not slot.has("same_card_as"):
		return true
	var reference_index: int = int(slot["same_card_as"])
	if reference_index < 0 or reference_index >= index:
		return false
	var current: Dictionary = window[offset + index]
	var reference: Dictionary = window[offset + reference_index]
	var current_card: CardInstance = current.get("card", null)
	var reference_card: CardInstance = reference.get("card", null)
	if current_card == null or reference_card == null:
		return false
	return current_card.data.card_id == reference_card.data.card_id
