class_name RulesEngine


static func get_advantage(attacker_cat: Enums.CardCategory, defender_last_cat: Enums.CardCategory) -> Enums.Advantage:
	# Attack > Defense, Defense > Evasion, Evasion > Attack
	if attacker_cat == Enums.CardCategory.ATTACK and defender_last_cat == Enums.CardCategory.DEFENSE:
		return Enums.Advantage.ATTACKER
	if attacker_cat == Enums.CardCategory.DEFENSE and defender_last_cat == Enums.CardCategory.EVASION:
		return Enums.Advantage.ATTACKER
	if attacker_cat == Enums.CardCategory.EVASION and defender_last_cat == Enums.CardCategory.ATTACK:
		return Enums.Advantage.ATTACKER
	return Enums.Advantage.NEUTRAL


static func calculate_damage(base_damage: int, emotion_multiplier: float, advantage: Enums.Advantage) -> int:
	var damage := float(base_damage) * emotion_multiplier
	if advantage == Enums.Advantage.ATTACKER:
		damage *= 1.5
	return int(floor(damage))


static func calculate_heal(base_heal: int, advantage: Enums.Advantage) -> int:
	var heal := float(base_heal)
	if advantage == Enums.Advantage.ATTACKER:
		heal *= 1.5
	return int(floor(heal))


static func resolve_random_effect() -> StringName:
	if randf() > 0.5:
		return &"logic"
	return &"emotion"


static func hand_limit_for_logic(logic: int) -> int:
	if logic <= 0: return 3
	if logic <= 2: return 4
	if logic <= 4: return 5
	if logic <= 6: return 6
	return 7


static func emotion_multiplier(emotion: int) -> float:
	if emotion <= 0: return 0.5
	if emotion <= 2: return 0.75
	if emotion <= 4: return 1.0
	if emotion <= 6: return 1.25
	return 1.5
