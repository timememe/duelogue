class_name CharacterStats
extends RefCounted

signal stat_changed(stat_name: StringName, old_value: int, new_value: int)
signal shield_changed(old_value: int, new_value: int)

const START_LOGIC := 4
const START_EMOTION := 4
const MAX_TENSION := 3

var logic: int = START_LOGIC
var max_logic: int = START_LOGIC
var emotion: int = START_EMOTION
var max_emotion: int = START_EMOTION
var points: int = 0
var shield: int = 0

var hand: Array[CardInstance] = []
var deck: Array[CardInstance] = []
var discard_pile: Array[CardInstance] = []

var last_card: CardInstance = null
var last_card_effects: Dictionary = {} ## Tracks what the last card did (for cancel)

## New in v0.1: combo / meter scaffolding (Phase 1 — fields only, no behavior yet)
var tension: int = 0
var rage_used: bool = false
var burst_used: bool = false
var effect_use_count: Dictionary = {} ## Enums.CardEffect -> int, for damage scaling
var effect_idle_turns: Dictionary = {} ## Enums.CardEffect -> own turns since last use


func get_hand_limit() -> int:
	if logic <= 0: return 3
	if logic <= 2: return 4
	if logic <= 4: return 5
	if logic <= 6: return 6
	return 7


func get_emotion_multiplier() -> float:
	if emotion <= 0: return 0.5
	if emotion <= 2: return 0.75
	if emotion <= 4: return 1.0
	if emotion <= 6: return 1.25
	return 1.5


func apply_stat_change(stat_name: StringName, amount: int) -> void:
	## Positive amounts (heals) are clamped at the current max — capacity does
	## not grow during a match. Negative amounts (damage / event penalties) are
	## allowed to push the stat below zero so scales-overflow logic stays intact.
	var old_value: int
	if stat_name == &"logic":
		old_value = logic
		if amount > 0:
			logic = mini(logic + amount, max_logic)
		else:
			logic += amount
	elif stat_name == &"emotion":
		old_value = emotion
		if amount > 0:
			emotion = mini(emotion + amount, max_emotion)
		else:
			emotion += amount
	else:
		return
	var new_value := logic if stat_name == &"logic" else emotion
	stat_changed.emit(stat_name, old_value, new_value)


func set_shield(amount: int) -> void:
	var old := shield
	shield = amount
	shield_changed.emit(old, shield)


func adjust_max(stat_name: StringName, delta: int) -> void:
	## Used by events (e.g. Heated Exchange) to permanently change cap mid-match.
	## Clamps current down if cap drops below it.
	if stat_name == &"logic":
		max_logic += delta
		if logic > max_logic:
			logic = max_logic
	elif stat_name == &"emotion":
		max_emotion += delta
		if emotion > max_emotion:
			emotion = max_emotion


func reset() -> void:
	logic = START_LOGIC
	max_logic = START_LOGIC
	emotion = START_EMOTION
	max_emotion = START_EMOTION
	points = 0
	shield = 0
	hand.clear()
	deck.clear()
	discard_pile.clear()
	last_card = null
	last_card_effects.clear()
	tension = 0
	rage_used = false
	burst_used = false
	effect_use_count.clear()
	effect_idle_turns.clear()
