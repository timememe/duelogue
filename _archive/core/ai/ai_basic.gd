class_name AIBasic
extends AIStrategy

## Basic AI that uses counter-card logic and weighted random selection.
## Ports the JS getCounterCard + getWeightedCard + random fallback.


func choose_card(hand: Array[CardInstance], own_stats: CharacterStats, opponent_stats: CharacterStats) -> CardInstance:
	var available: Array[CardInstance] = []
	for c in hand:
		if not c.is_used():
			available.append(c)

	if available.is_empty():
		return null

	# Try counter-card based on opponent's last card
	var counter := _try_counter(available, opponent_stats)
	if counter:
		return counter

	# Weighted selection based on stats
	return _weighted_pick(available, own_stats)


func _try_counter(available: Array[CardInstance], opponent_stats: CharacterStats) -> CardInstance:
	if opponent_stats.last_card == null:
		return null

	var last_cat := opponent_stats.last_card.data.category

	# Attack > Defense: counter defense with attack (70% chance)
	if last_cat == Enums.CardCategory.DEFENSE and randf() < 0.7:
		var attacks := _filter_category(available, Enums.CardCategory.ATTACK)
		if not attacks.is_empty():
			return attacks[randi() % attacks.size()]

	# Evasion > Attack: counter attack with evasion (70% chance)
	if last_cat == Enums.CardCategory.ATTACK and randf() < 0.7:
		var evasions := _filter_category(available, Enums.CardCategory.EVASION)
		if not evasions.is_empty():
			return evasions[randi() % evasions.size()]

	# Defense > Evasion: counter evasion with defense (70% chance)
	if last_cat == Enums.CardCategory.EVASION and randf() < 0.7:
		var defenses := _filter_category(available, Enums.CardCategory.DEFENSE)
		if not defenses.is_empty():
			return defenses[randi() % defenses.size()]

	return null


func _weighted_pick(available: Array[CardInstance], own_stats: CharacterStats) -> CardInstance:
	var practical: Array[CardInstance] = []
	for c in available:
		if c.data.effect != Enums.CardEffect.BURST:
			practical.append(c)
	if not practical.is_empty():
		available = practical

	# If low on a stat, prefer defense
	if own_stats.logic <= 1 or own_stats.emotion <= 1:
		var defenses := _filter_category(available, Enums.CardCategory.DEFENSE)
		if not defenses.is_empty() and randf() < 0.5:
			return defenses[randi() % defenses.size()]

	# Weight attacks by logic/emotion ratio
	var attacks := _filter_category(available, Enums.CardCategory.ATTACK)
	if not attacks.is_empty() and randf() < 0.6:
		var total := maxi(1, own_stats.logic + own_stats.emotion)
		var logic_weight := float(own_stats.logic) / total
		var use_logic := randf() < logic_weight

		var preferred: Array[CardInstance] = []
		for c in attacks:
			var is_logic := c.data.effect == Enums.CardEffect.LOGIC
			if (use_logic and is_logic) or (not use_logic and not is_logic):
				preferred.append(c)

		if not preferred.is_empty():
			return preferred[randi() % preferred.size()]
		return attacks[randi() % attacks.size()]

	# Fallback: random
	return available[randi() % available.size()]


func _filter_category(cards: Array[CardInstance], cat: Enums.CardCategory) -> Array[CardInstance]:
	var result: Array[CardInstance] = []
	for c in cards:
		if c.data.category == cat:
			result.append(c)
	return result
