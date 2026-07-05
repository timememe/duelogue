class_name ComboTrack
extends RefCounted

## Ring buffer of last N cards played, with owner tag from the player's perspective.
## ComboResolver reads get_window() to check recipes against the current state.

const DEFAULT_MAX_SIZE := 3

var entries: Array = [] ## elements: {card: CardInstance, owner: String}
var max_size: int = DEFAULT_MAX_SIZE


func _init(initial_size: int = DEFAULT_MAX_SIZE) -> void:
	max_size = initial_size


func add_entry(card: CardInstance, owner: String) -> void:
	if card == null:
		return
	entries.append({"card": card, "owner": owner})
	while entries.size() > max_size:
		entries.pop_front()


func get_window() -> Array:
	return entries.duplicate()


func size() -> int:
	return entries.size()


func clear() -> void:
	entries.clear()
