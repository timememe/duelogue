class_name CardData
extends Resource

@export var card_id: String ## Stable universal id (snake_case). Use card_id for logic.
@export var category: Enums.CardCategory
@export var card_name: String
@export var effect: Enums.CardEffect
@export var base_damage: int = 0
@export var base_heal: int = 0
@export var shield_amount: int = 0
@export var modifier: float = 1.0 ## For mirror (0.75)
@export var text: String
@export var text_variants: PackedStringArray
@export var description: String
@export var max_uses: int = 1
@export var combo_tags: PackedStringArray = [] ## starter / linker / finisher / interrupt / bait / pressure


static func from_dict(data: Dictionary) -> CardData:
	var card := CardData.new()
	card.card_name = data.get("name", "")
	card.card_id = data.get("id", card.card_name.to_snake_case())
	card.category = _parse_category(data.get("category", ""))
	card.effect = _parse_effect(data.get("effect", ""))
	card.base_damage = data.get("damage", 0)
	card.base_heal = data.get("heal", 0)
	card.shield_amount = data.get("shield", 0)
	card.modifier = data.get("modifier", 1.0)
	card.text = data.get("text", "")
	card.description = data.get("desc", "")
	card.max_uses = data.get("usesLeft", 1)

	var variants = data.get("textVariants", [])
	if variants is Array:
		var psa := PackedStringArray()
		for v in variants:
			psa.append(str(v))
		card.text_variants = psa

	var tags = data.get("combo_tags", [])
	if tags is Array:
		var tag_psa := PackedStringArray()
		for t in tags:
			tag_psa.append(str(t))
		card.combo_tags = tag_psa

	return card


static func _parse_category(cat: String) -> Enums.CardCategory:
	match cat:
		"Атака": return Enums.CardCategory.ATTACK
		"Защита": return Enums.CardCategory.DEFENSE
		"Уклонение": return Enums.CardCategory.EVASION
	return Enums.CardCategory.ATTACK


static func _parse_effect(eff: String) -> Enums.CardEffect:
	match eff:
		"logic": return Enums.CardEffect.LOGIC
		"emotion": return Enums.CardEffect.EMOTION
		"shield": return Enums.CardEffect.SHIELD
		"cancel": return Enums.CardEffect.CANCEL
		"mirror": return Enums.CardEffect.MIRROR
		"reflect": return Enums.CardEffect.REFLECT
		"random": return Enums.CardEffect.RANDOM
		"burst": return Enums.CardEffect.BURST
	return Enums.CardEffect.LOGIC
