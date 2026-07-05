class_name AIStrategy
extends RefCounted


func choose_card(_hand: Array[CardInstance], _own_stats: CharacterStats, _opponent_stats: CharacterStats) -> CardInstance:
	push_error("AIStrategy.choose_card() is abstract")
	return null
