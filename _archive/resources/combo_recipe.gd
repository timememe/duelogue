class_name ComboRecipe
extends Resource

## A combo recipe describes a pattern in the combo track that triggers a bonus.
## Pattern is an Array of slot dictionaries — each slot describes what card must be
## in that position for the recipe to match. Matching is evaluated by ComboResolver
## against the last N entries of the ComboTrack (from the player's perspective).

const TYPE_SOLO := "solo"
const TYPE_REACTIVE := "reactive"
const TYPE_BAIT := "bait"
const TYPE_ECHO := "echo"

const OWNER_SELF := "self"
const OWNER_OPPONENT := "opponent"
const OWNER_ANY := "any"

const WILDCARD := -1 ## use for category/effect "any"

@export var recipe_id: String
@export var display_name: String
@export var recipe_type: String = TYPE_SOLO ## one of TYPE_*
@export var pattern: Array = [] ## Array of slot dicts: {owner, category, effect}
@export var bonus_damage: int = 0
@export var bonus_heal: int = 0
@export var bonus_effect_id: String = "" ## hook for special effects ("force_discard", etc.)
@export var description: String = ""


static func from_dict(data: Dictionary) -> ComboRecipe:
	var r := ComboRecipe.new()
	r.recipe_id = data.get("id", "")
	r.display_name = data.get("name", "")
	r.recipe_type = data.get("type", TYPE_SOLO)
	r.bonus_damage = data.get("bonus_damage", 0)
	r.bonus_heal = data.get("bonus_heal", 0)
	r.bonus_effect_id = data.get("bonus_effect_id", "")
	r.description = data.get("desc", "")

	var raw_pattern = data.get("pattern", [])
	if raw_pattern is Array:
		for slot in raw_pattern:
			if slot is Dictionary:
				var parsed_slot := {
					"owner": slot.get("owner", OWNER_ANY),
					"category": _parse_category_value(slot.get("category", WILDCARD)),
					"effect": _parse_effect_value(slot.get("effect", WILDCARD)),
				}
				if slot.has("card_id"):
					parsed_slot["card_id"] = str(slot["card_id"])
				if slot.has("tag"):
					parsed_slot["tag"] = str(slot["tag"])
				if slot.has("same_card_as"):
					parsed_slot["same_card_as"] = int(slot["same_card_as"])
				if slot.has("min_damage"):
					parsed_slot["min_damage"] = int(slot["min_damage"])
				if slot.has("max_damage"):
					parsed_slot["max_damage"] = int(slot["max_damage"])
				r.pattern.append(parsed_slot)

	return r


## Returns true if this slot description matches a given track entry.
## Entry expected as {card: CardInstance, owner: String}.
func slot_matches(slot: Dictionary, entry: Dictionary) -> bool:
	var slot_owner: String = slot.get("owner", OWNER_ANY)
	var slot_cat: int = int(slot.get("category", WILDCARD))
	var slot_eff: int = int(slot.get("effect", WILDCARD))
	var slot_card_id: String = slot.get("card_id", "")
	var slot_tag: String = slot.get("tag", "")
	var min_damage: int = int(slot.get("min_damage", -1))
	var max_damage: int = int(slot.get("max_damage", -1))

	var entry_owner: String = entry.get("owner", "")
	var card: CardInstance = entry.get("card", null)
	if card == null or card.data == null:
		return false

	if slot_owner != OWNER_ANY and slot_owner != entry_owner:
		return false
	if slot_cat != WILDCARD and slot_cat != card.data.category:
		return false
	if slot_eff != WILDCARD and slot_eff != card.data.effect:
		return false
	if slot_card_id != "" and slot_card_id != card.data.card_id:
		return false
	if slot_tag != "" and not card.data.combo_tags.has(slot_tag):
		return false
	if min_damage >= 0 and card.data.base_damage < min_damage:
		return false
	if max_damage >= 0 and card.data.base_damage > max_damage:
		return false
	return true


static func _parse_category_value(value) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	var key := str(value).to_lower()
	match key:
		"", "any", "*":
			return WILDCARD
		"attack", "atk", "атака":
			return Enums.CardCategory.ATTACK
		"defense", "def", "защита":
			return Enums.CardCategory.DEFENSE
		"evasion", "evd", "уклонение":
			return Enums.CardCategory.EVASION
	return WILDCARD


static func _parse_effect_value(value) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	var key := str(value).to_lower()
	match key:
		"", "any", "*":
			return WILDCARD
		"logic", "heal_logic":
			return Enums.CardEffect.LOGIC
		"emotion", "heal_emotion":
			return Enums.CardEffect.EMOTION
		"shield":
			return Enums.CardEffect.SHIELD
		"cancel":
			return Enums.CardEffect.CANCEL
		"mirror":
			return Enums.CardEffect.MIRROR
		"reflect":
			return Enums.CardEffect.REFLECT
		"random":
			return Enums.CardEffect.RANDOM
		"burst":
			return Enums.CardEffect.BURST
	return WILDCARD
