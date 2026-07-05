class_name TurnResolver
extends RefCounted

signal effect_applied(description: String)

var scales_mgr: ScalesManager


func _init(scales_manager: ScalesManager = null) -> void:
	scales_mgr = scales_manager


func resolve(
	player_card: CardInstance,
	opponent_card: CardInstance,
	player: CharacterStats,
	opponent: CharacterStats
) -> void:
	_apply_single_card(player_card, player, opponent, true)
	_apply_single_card(opponent_card, opponent, player, false)


func _apply_single_card(
	card: CardInstance,
	source: CharacterStats,
	target: CharacterStats,
	is_player_source: bool,
	boost: bool = false
) -> void:
	if card == null:
		return

	var boost_mult := _consume_boost(source, boost)
	var target_last_cat := Enums.CardCategory.ATTACK
	if target.last_card:
		target_last_cat = target.last_card.data.category

	var advantage := RulesEngine.get_advantage(card.data.category, target_last_cat)

	match card.data.category:
		Enums.CardCategory.EVASION:
			_resolve_evasion(card, source, target, is_player_source, boost_mult)
		Enums.CardCategory.ATTACK:
			_resolve_attack(card, source, target, advantage, is_player_source, boost_mult)
		Enums.CardCategory.DEFENSE:
			_resolve_defense(card, source, target, advantage, boost_mult)

	# Handle fromDiscard -> repeat card
	if card.from_discard:
		_handle_from_discard(target)

	source.last_card = card


func _resolve_attack(
	card: CardInstance,
	source: CharacterStats,
	target: CharacterStats,
	advantage: Enums.Advantage,
	is_player_source: bool,
	boost_mult: float = 1.0
) -> void:
	var emotion_mult := source.get_emotion_multiplier()
	var damage := RulesEngine.calculate_damage(card.data.base_damage, emotion_mult, advantage)
	damage = int(floor(float(damage) * boost_mult))

	if advantage == Enums.Advantage.ATTACKER:
		effect_applied.emit("Преимущество: +50% к урону")

	if damage <= 0:
		return

	var effect_count: int = source.effect_use_count.get(card.data.effect, 0)
	var scale_mult := maxf(0.3, 1.0 - 0.1 * float(effect_count))
	var scaled_damage := int(floor(float(damage) * scale_mult))
	if effect_count > 0 and scaled_damage != damage:
		effect_applied.emit("Снижение повтора: %d -> %d" % [damage, scaled_damage])
	damage = scaled_damage
	source.effect_use_count[card.data.effect] = effect_count + 1

	# Determine target stat
	var stat_name: StringName
	if card.data.effect == Enums.CardEffect.RANDOM:
		stat_name = RulesEngine.resolve_random_effect()
	elif card.data.effect == Enums.CardEffect.LOGIC:
		stat_name = &"logic"
	else:
		stat_name = &"emotion"

	# Shield absorption
	if target.shield > 0:
		var absorbed := mini(target.shield, damage)
		target.set_shield(target.shield - absorbed)
		damage -= absorbed
		effect_applied.emit("Щит поглотил %d урона" % absorbed)
		if target.shield <= 0:
			effect_applied.emit("Щит разрушен")

	if damage > 0 and scales_mgr:
		var is_player_target := not is_player_source
		var result := scales_mgr.apply_damage_with_scales(target, stat_name, damage, is_player_target)
		effect_applied.emit("-%d: %s" % [result.actual_damage, _stat_label(stat_name)])
		if result.scales_shift != 0:
			effect_applied.emit("Весы: %+d" % result.scales_shift)
		if result.get("knockdown", false):
			scales_mgr.award_knockdown_point(source, target, is_player_source, stat_name)
			effect_applied.emit("ОБВАЛ: %s на нуле → очко" % _stat_label(stat_name))
		var dealt_damage: int = result.actual_damage + result.overflow
		if dealt_damage > 0:
			_gain_tension(source, "Вы" if is_player_source else "Оппонент")
			_gain_tension(target, "Оппонент" if is_player_source else "Вы")

		# Track effects for cancel
		target.last_card_effects.clear()
		if stat_name == &"logic":
			target.last_card_effects["logic_damage"] = result.actual_damage + result.overflow
		else:
			target.last_card_effects["emotion_damage"] = result.actual_damage + result.overflow


func _resolve_defense(
	card: CardInstance,
	source: CharacterStats,
	target: CharacterStats,
	advantage: Enums.Advantage,
	boost_mult: float = 1.0
) -> void:
	if card.data.effect == Enums.CardEffect.SHIELD:
		var shield_amount := int(floor(float(card.data.shield_amount) * boost_mult))
		source.set_shield(source.shield + shield_amount)
		effect_applied.emit("Щит +%d" % shield_amount)
		# Track for cancel
		target.last_card_effects.clear()
		target.last_card_effects["shield_added"] = shield_amount
	else:
		var heal := RulesEngine.calculate_heal(card.data.base_heal, advantage)
		heal = int(floor(float(heal) * boost_mult))
		if advantage == Enums.Advantage.ATTACKER:
			effect_applied.emit("Преимущество: +50% к восстановлению")

		var stat_name: StringName
		if card.data.effect == Enums.CardEffect.HEAL_LOGIC or card.data.effect == Enums.CardEffect.LOGIC:
			stat_name = &"logic"
		else:
			stat_name = &"emotion"

		source.apply_stat_change(stat_name, heal)
		effect_applied.emit("+%d: %s" % [heal, _stat_label(stat_name)])

		# Track for cancel
		target.last_card_effects.clear()
		if stat_name == &"logic":
			target.last_card_effects["logic_heal"] = heal
		else:
			target.last_card_effects["emotion_heal"] = heal


func _resolve_evasion(
	card: CardInstance,
	source: CharacterStats,
	target: CharacterStats,
	is_player_source: bool,
	boost_mult: float = 1.0
) -> void:
	match card.data.effect:
		Enums.CardEffect.CANCEL:
			_resolve_cancel(source, target)
		Enums.CardEffect.MIRROR:
			_resolve_mirror(card, source, target, is_player_source, boost_mult)
		Enums.CardEffect.REFLECT:
			_resolve_reflect(source, target, is_player_source, boost_mult)
		Enums.CardEffect.BURST:
			effect_applied.emit("Срыв обрабатывается состоянием партии")


func _resolve_cancel(source: CharacterStats, target: CharacterStats) -> void:
	if source.last_card_effects.is_empty():
		effect_applied.emit("Отмена не сработала: нечего отменять")
		return

	# Reverse all effects from the last card
	if source.last_card_effects.has("logic_damage"):
		source.apply_stat_change(&"logic", source.last_card_effects["logic_damage"])
	if source.last_card_effects.has("emotion_damage"):
		source.apply_stat_change(&"emotion", source.last_card_effects["emotion_damage"])
	if source.last_card_effects.has("logic_heal"):
		target.apply_stat_change(&"logic", -source.last_card_effects["logic_heal"])
	if source.last_card_effects.has("emotion_heal"):
		target.apply_stat_change(&"emotion", -source.last_card_effects["emotion_heal"])
	if source.last_card_effects.has("shield_added"):
		target.set_shield(maxi(0, target.shield - source.last_card_effects["shield_added"]))

	effect_applied.emit("Эффект прошлой карты отменён")
	source.last_card_effects.clear()


func _resolve_mirror(
	card: CardInstance,
	source: CharacterStats,
	target: CharacterStats,
	is_player_source: bool,
	boost_mult: float = 1.0
) -> void:
	if target.last_card == null or target.last_card.data.category != Enums.CardCategory.ATTACK:
		effect_applied.emit("Зеркало не сработало: прошлый ход не был атакой")
		return

	var mult := source.get_emotion_multiplier()
	var mirror_damage := int(floor(float(target.last_card.data.base_damage) * card.data.modifier * mult * boost_mult))

	var stat_name: StringName
	if target.last_card.data.effect == Enums.CardEffect.RANDOM:
		stat_name = RulesEngine.resolve_random_effect()
	elif target.last_card.data.effect == Enums.CardEffect.LOGIC:
		stat_name = &"logic"
	else:
		stat_name = &"emotion"

	if scales_mgr:
		var is_player_target := not is_player_source
		var result := scales_mgr.apply_damage_with_scales(target, stat_name, mirror_damage, is_player_target)
		if result.get("knockdown", false):
			scales_mgr.award_knockdown_point(source, target, is_player_source, stat_name)
			effect_applied.emit("ОБВАЛ через зеркало: %s на нуле → очко" % _stat_label(stat_name))
	var target_label := "оппоненту" if is_player_source else "вам"
	effect_applied.emit("Зеркало: -%d %s %s" % [mirror_damage, _stat_label(stat_name), target_label])


func _resolve_reflect(
	source: CharacterStats,
	target: CharacterStats,
	is_player_source: bool,
	boost_mult: float = 1.0
) -> void:
	if target.last_card == null or target.last_card.data.category != Enums.CardCategory.ATTACK:
		effect_applied.emit("Контратака не сработала: прошлый ход не был атакой")
		return

	var mult := source.get_emotion_multiplier()
	var reflect_damage := int(floor(float(target.last_card.data.base_damage) * mult * boost_mult))

	var stat_name: StringName
	if target.last_card.data.effect == Enums.CardEffect.RANDOM:
		stat_name = RulesEngine.resolve_random_effect()
	elif target.last_card.data.effect == Enums.CardEffect.LOGIC:
		stat_name = &"logic"
	else:
		stat_name = &"emotion"

	if scales_mgr:
		var is_player_target := not is_player_source
		var result := scales_mgr.apply_damage_with_scales(target, stat_name, reflect_damage, is_player_target)
		if result.get("knockdown", false):
			scales_mgr.award_knockdown_point(source, target, is_player_source, stat_name)
			effect_applied.emit("ОБВАЛ через контратаку: %s на нуле → очко" % _stat_label(stat_name))
	var target_label := "оппоненту" if is_player_source else "вам"
	effect_applied.emit("Контратака: -%d %s %s" % [reflect_damage, _stat_label(stat_name), target_label])


func _handle_from_discard(target: CharacterStats) -> void:
	# Check if target already has a Repeat card
	for c in target.hand:
		if c.data.card_name == "Повторение" and not c.is_used():
			return
	# Would need deck_data.repeat_card reference — handled at GameState level
	effect_applied.emit("Из сброса: оппонент получает карту Повторение")


func _consume_boost(source: CharacterStats, boost: bool) -> float:
	if not boost or source.tension <= 0:
		return 1.0
	source.tension -= 1
	effect_applied.emit("EX: -1 накал, +50% силы")
	return 1.5


func _gain_tension(stats: CharacterStats, label: String) -> void:
	var old := stats.tension
	stats.tension = mini(stats.tension + 1, CharacterStats.MAX_TENSION)
	if stats.tension != old:
		effect_applied.emit("%s: накал +1" % label)


func _stat_label(stat_name: StringName) -> String:
	if stat_name == &"logic":
		return "логика"
	if stat_name == &"emotion":
		return "эмоции"
	return str(stat_name)
