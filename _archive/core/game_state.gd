class_name GameState
extends RefCounted

const COMBO_RECIPES_PATH := "res://data/combos/v0_combos.json"
const SPECIAL_BURST_ID := "special_burst"
const SPECIAL_RAGE_ID := "special_rage"

var player: CharacterStats
var opponent: CharacterStats
var scales_mgr: ScalesManager
var turn_resolver: TurnResolver
var event_checker: EventChecker
var ai: AIStrategy
var deck_data: DeckData

## Combo system: shared track of recent cards plus recipe resolver.
var combo_track: ComboTrack
var combo_resolver: ComboResolver
var action_history: Array = [] ## Reversible normal card actions for Burst.

var turn_number: int = 0
var phase: Enums.GamePhase = Enums.GamePhase.COIN_FLIP
var is_player_turn: bool = true

signal turn_resolved(turn_log: Array[String])
signal event_occurred(event_data: Dictionary)
signal point_scored(is_player: bool, points: int)
signal match_over(player_won: bool, reason: String)
signal combo_triggered(recipe: ComboRecipe)


func initialize(p_deck_data: DeckData, p_ai: AIStrategy) -> void:
	deck_data = p_deck_data
	ai = p_ai

	player = CharacterStats.new()
	opponent = CharacterStats.new()
	scales_mgr = ScalesManager.new()
	event_checker = EventChecker.new()
	turn_resolver = TurnResolver.new(scales_mgr)
	combo_track = ComboTrack.new()
	combo_resolver = ComboResolver.new()
	var loaded_combo_count := combo_resolver.load_recipes_from_file(COMBO_RECIPES_PATH)
	print("Загружено комбо-рецептов: %d" % loaded_combo_count)

	# Connect signals
	scales_mgr.point_scored.connect(_on_point_scored)

	# Build decks
	player.deck = CardDatabase.create_full_deck(deck_data, true)
	opponent.deck = CardDatabase.create_full_deck(deck_data, false)

	# Deal starting hands
	player.hand = CardDatabase.create_starting_hand(deck_data, player, true)
	opponent.hand = CardDatabase.create_starting_hand(deck_data, opponent, false)
	_add_special_to_hand(player, deck_data.burst_card)
	_add_special_to_hand(opponent, deck_data.burst_card)

	# Coin flip
	is_player_turn = randf() < 0.5
	phase = Enums.GamePhase.PLAYER_TURN if is_player_turn else Enums.GamePhase.OPPONENT_TURN


func play_turn(player_card: CardInstance, boost: bool = false) -> Array[String]:
	## Игрок играет карту, ИИ отвечает. Возвращает журнал хода.
	var log: Array[String] = []

	# Collect resolver messages
	var messages: Array[String] = []
	var _on_effect := func(desc: String) -> void:
		messages.append(desc)
	turn_resolver.effect_applied.connect(_on_effect)

	turn_number += 1

	# Ход игрока.
	phase = Enums.GamePhase.RESOLVING
	messages.clear()
	log.append("[b]Вы:[/b] %s" % player_card.data.card_name)
	var player_quote := _pick_card_text(player_card)
	if player_quote != "":
		log.append("[color=#9aa3b0][i]«%s»[/i][/color]" % player_quote)
	if _is_burst_card(player_card):
		log.append_array(_play_burst_card(player_card, player, opponent, true))
	else:
		var player_action := _begin_action(ComboRecipe.OWNER_SELF)
		turn_resolver._apply_single_card(player_card, player, opponent, true, boost)
		_update_damage_scaling_decay(player, player_card)
		_consume_card(player_card, player)
		combo_track.add_entry(player_card, ComboRecipe.OWNER_SELF)
		log.append_array(messages)
		log.append_array(_check_combo_after_card(player, opponent, true))
		scales_mgr.check_points(player, opponent)
		_finish_action(player_action, player_card)

	_maybe_grant_rage(opponent, log, "Оппонент")

	# Ход ИИ.
	messages.clear()
	var ai_card := _execute_opponent_turn(log, messages)

	_maybe_grant_rage(player, log, "Вы")

	# Events
	phase = Enums.GamePhase.EVENT_CHECK
	if player_card and ai_card:
		event_checker.record_turn(player_card, ai_card)
	var event := event_checker.check_for_events(player, opponent)
	if not event.is_empty():
		if event.get("ended", false):
			log.append("Событие завершилось: %s" % event.get("message", ""))
		else:
			if event.get("duration", 0) == 0:
				log.append("СОБЫТИЕ: %s" % event.get("name", ""))
				log.append(event.get("message", ""))
			var effects := event_checker.apply_event_effects(player, opponent)
			if effects.has("message") and effects["message"] != "":
				log.append(effects["message"])
		event_occurred.emit(event)

	# Draw cards
	phase = Enums.GamePhase.DRAW
	_draw_cards_to_hand_limit(player)
	_draw_cards_to_hand_limit(opponent)
	_maybe_grant_rage(player, log, "Вы")
	_maybe_grant_rage(opponent, log, "Оппонент")

	# Victory check — match only ends on 3 points.
	phase = Enums.GamePhase.VICTORY_CHECK
	var victory := scales_mgr.check_victory(player, opponent)
	if victory != 0:
		phase = Enums.GamePhase.MATCH_OVER
		var player_won := victory > 0
		log.append("%s побеждает: 3 очка" % ("Вы" if player_won else "Оппонент"))
		match_over.emit(player_won, "points")
	else:
		phase = Enums.GamePhase.PLAYER_TURN

	turn_resolver.effect_applied.disconnect(_on_effect)
	turn_resolved.emit(log)
	return log


func play_opening_ai() -> Array[String]:
	## Plays just the opponent's opening card when opponent won the coin flip.
	## Does NOT run events/draw/victory — those happen at the end of the first
	## full round (after the player's first move via play_turn).
	var log: Array[String] = []
	var messages: Array[String] = []
	var _on_effect := func(desc: String) -> void:
		messages.append(desc)
	turn_resolver.effect_applied.connect(_on_effect)

	phase = Enums.GamePhase.RESOLVING
	_execute_opponent_turn(log, messages)
	_maybe_grant_rage(player, log, "Вы")

	phase = Enums.GamePhase.PLAYER_TURN
	turn_resolver.effect_applied.disconnect(_on_effect)
	turn_resolved.emit(log)
	return log


func _execute_opponent_turn(log: Array[String], messages: Array[String]) -> CardInstance:
	## Picks an AI card and applies it. Returns the chosen card (or null if none).
	## Used by both play_turn (AI half) and play_opening_ai.
	var ai_card := ai.choose_card(opponent.hand, opponent, player)
	if ai_card == null:
		log.append("Оппоненту нечего сказать...")
		return null

	log.append("[b]Оппонент:[/b] %s" % ai_card.data.card_name)
	var ai_quote := _pick_card_text(ai_card)
	if ai_quote != "":
		log.append("[color=#c79090][i]«%s»[/i][/color]" % ai_quote)
	if _is_burst_card(ai_card):
		log.append_array(_play_burst_card(ai_card, opponent, player, false))
		return ai_card

	var opponent_action := _begin_action(ComboRecipe.OWNER_OPPONENT)
	turn_resolver._apply_single_card(ai_card, opponent, player, false)
	_update_damage_scaling_decay(opponent, ai_card)
	_consume_card(ai_card, opponent)
	combo_track.add_entry(ai_card, ComboRecipe.OWNER_OPPONENT)
	log.append_array(messages)
	log.append_array(_check_combo_after_card(opponent, player, false))
	scales_mgr.check_points(player, opponent)
	_finish_action(opponent_action, ai_card)
	return ai_card


func get_available_cards() -> Array[CardInstance]:
	var available: Array[CardInstance] = []
	for c in player.hand:
		if not c.is_used():
			available.append(c)
	return available


func _pick_card_text(card: CardInstance) -> String:
	## Returns a card's spoken line. If text_variants exist, picks one at random
	## (storing the choice on the instance so subsequent reads stay consistent).
	if card == null or card.data == null:
		return ""
	if card.data.text_variants.size() > 0:
		card.current_variant_index = randi() % card.data.text_variants.size()
	return card.get_text()


func _add_special_to_hand(stats: CharacterStats, card_data: CardData) -> void:
	if card_data != null:
		stats.hand.append(CardInstance.new(card_data))


func _is_burst_card(card: CardInstance) -> bool:
	return card != null and card.data != null and card.data.card_id == SPECIAL_BURST_ID


func _is_rage_card(card: CardInstance) -> bool:
	return card != null and card.data != null and card.data.card_id == SPECIAL_RAGE_ID


func _maybe_grant_rage(stats: CharacterStats, log: Array[String], label: String) -> void:
	if stats.rage_used:
		return
	if stats.logic + stats.emotion > 3:
		return
	if _has_card_id(stats, SPECIAL_RAGE_ID):
		return
	if deck_data.rage_card == null:
		return
	stats.hand.append(CardInstance.new(deck_data.rage_card))
	log.append("%s: открыт приём ярости" % label)


func _has_card_id(stats: CharacterStats, card_id: String) -> bool:
	for card in stats.hand:
		if card.data != null and card.data.card_id == card_id and not card.is_used():
			return true
	for card in stats.deck:
		if card.data != null and card.data.card_id == card_id and not card.is_used():
			return true
	for card in stats.discard_pile:
		if card.data != null and card.data.card_id == card_id:
			return true
	return false


func _play_burst_card(
	card: CardInstance,
	source: CharacterStats,
	target: CharacterStats,
	is_player_source: bool
) -> Array[String]:
	var log: Array[String] = []
	if source.burst_used:
		log.append("Срыв не сработал: уже использован")
	else:
		source.burst_used = true
		var undone_count := _undo_recent_actions(ComboRecipe.OWNER_OPPONENT if is_player_source else ComboRecipe.OWNER_SELF, 2)
		if undone_count > 0:
			var target_label := "оппонента" if is_player_source else "ваши"
			log.append("Срыв отменил действия %s: %d" % [target_label, undone_count])
		else:
			log.append("Срыв не нашёл действий для отмены")

	_consume_card(card, source)
	combo_track.add_entry(card, ComboRecipe.OWNER_SELF if is_player_source else ComboRecipe.OWNER_OPPONENT)
	source.last_card = card
	source.last_card_effects.clear()
	target.last_card_effects.clear()
	return log


func _begin_action(owner: String) -> Dictionary:
	return {
		"owner": owner,
		"before": _snapshot_battle(),
	}


func _finish_action(action: Dictionary, card: CardInstance) -> void:
	action["card"] = card
	action["after"] = _snapshot_battle()
	action_history.append(action)
	while action_history.size() > 20:
		action_history.pop_front()


func _snapshot_battle() -> Dictionary:
	return {
		"player": _snapshot_stats(player),
		"opponent": _snapshot_stats(opponent),
		"scales": scales_mgr.scales,
	}


func _snapshot_stats(stats: CharacterStats) -> Dictionary:
	return {
		"logic": stats.logic,
		"max_logic": stats.max_logic,
		"emotion": stats.emotion,
		"max_emotion": stats.max_emotion,
		"points": stats.points,
		"shield": stats.shield,
		"tension": stats.tension,
	}


func _undo_recent_actions(owner: String, count: int) -> int:
	var undone := 0
	for i in range(action_history.size() - 1, -1, -1):
		var action: Dictionary = action_history[i]
		if action.get("owner", "") != owner:
			continue
		_reverse_action_delta(action)
		action_history.remove_at(i)
		undone += 1
		if undone >= count:
			break
	_remove_combo_entries(owner, undone)
	_rebuild_last_cards_from_history()
	player.last_card_effects.clear()
	opponent.last_card_effects.clear()
	return undone


func _reverse_action_delta(action: Dictionary) -> void:
	var before: Dictionary = action.get("before", {})
	var after: Dictionary = action.get("after", {})
	if before.is_empty() or after.is_empty():
		return
	var before_player: Dictionary = before.get("player", {})
	var after_player: Dictionary = after.get("player", {})
	var before_opponent: Dictionary = before.get("opponent", {})
	var after_opponent: Dictionary = after.get("opponent", {})
	_reverse_stats_delta(player, before_player, after_player)
	_reverse_stats_delta(opponent, before_opponent, after_opponent)
	var before_scales: int = before.get("scales", scales_mgr.scales)
	var after_scales: int = after.get("scales", scales_mgr.scales)
	scales_mgr.set_scales(scales_mgr.scales - (after_scales - before_scales))


func _reverse_stats_delta(stats: CharacterStats, before: Dictionary, after: Dictionary) -> void:
	if before.is_empty() or after.is_empty():
		return
	stats.logic -= int(after.get("logic", stats.logic)) - int(before.get("logic", stats.logic))
	stats.max_logic -= int(after.get("max_logic", stats.max_logic)) - int(before.get("max_logic", stats.max_logic))
	stats.emotion -= int(after.get("emotion", stats.emotion)) - int(before.get("emotion", stats.emotion))
	stats.max_emotion -= int(after.get("max_emotion", stats.max_emotion)) - int(before.get("max_emotion", stats.max_emotion))
	stats.points -= int(after.get("points", stats.points)) - int(before.get("points", stats.points))
	stats.tension = clampi(
		stats.tension - (int(after.get("tension", stats.tension)) - int(before.get("tension", stats.tension))),
		0,
		CharacterStats.MAX_TENSION
	)
	var shield_delta := int(after.get("shield", stats.shield)) - int(before.get("shield", stats.shield))
	if shield_delta != 0:
		stats.set_shield(maxi(0, stats.shield - shield_delta))


func _remove_combo_entries(owner: String, count: int) -> void:
	var removed := 0
	for i in range(combo_track.entries.size() - 1, -1, -1):
		var entry: Dictionary = combo_track.entries[i]
		if entry.get("owner", "") != owner:
			continue
		combo_track.entries.remove_at(i)
		removed += 1
		if removed >= count:
			return


func _rebuild_last_cards_from_history() -> void:
	player.last_card = null
	opponent.last_card = null
	for i in range(action_history.size() - 1, -1, -1):
		var action: Dictionary = action_history[i]
		var card: CardInstance = action.get("card", null)
		if card == null:
			continue
		if action.get("owner", "") == ComboRecipe.OWNER_SELF and player.last_card == null:
			player.last_card = card
		elif action.get("owner", "") == ComboRecipe.OWNER_OPPONENT and opponent.last_card == null:
			opponent.last_card = card
		if player.last_card != null and opponent.last_card != null:
			return


func _update_damage_scaling_decay(stats: CharacterStats, card: CardInstance) -> void:
	if card == null:
		return
	var current_effect := -1
	if card.data.category == Enums.CardCategory.ATTACK:
		current_effect = card.data.effect

	for effect in stats.effect_use_count.keys():
		if int(effect) == current_effect:
			stats.effect_idle_turns[effect] = 0
			continue
		var idle_turns: int = stats.effect_idle_turns.get(effect, 0) + 1
		if idle_turns >= 3:
			stats.effect_use_count.erase(effect)
			stats.effect_idle_turns.erase(effect)
		else:
			stats.effect_idle_turns[effect] = idle_turns


func _check_combo_after_card(
	source: CharacterStats,
	target: CharacterStats,
	is_player_source: bool
) -> Array[String]:
	var log: Array[String] = []
	if combo_resolver == null:
		return log
	var window: Array = combo_track.get_window()
	if not is_player_source:
		window = _flip_window_owners(window)
	var combo := combo_resolver.check_window(window)
	if combo == null:
		return log

	var label := "Вы" if is_player_source else "Оппонент"
	log.append("КОМБО %s: %s" % [label, combo.display_name])
	log.append_array(_apply_combo_bonus(combo, source, target, is_player_source))
	combo_triggered.emit(combo)
	return log


func _flip_window_owners(window: Array) -> Array:
	var flipped: Array = []
	for entry in window:
		flipped.append({
			"card": entry.get("card", null),
			"owner": _flip_owner(entry.get("owner", ComboRecipe.OWNER_ANY)),
		})
	return flipped


func _flip_owner(owner: String) -> String:
	if owner == ComboRecipe.OWNER_SELF:
		return ComboRecipe.OWNER_OPPONENT
	if owner == ComboRecipe.OWNER_OPPONENT:
		return ComboRecipe.OWNER_SELF
	return owner


func _apply_combo_bonus(
	recipe: ComboRecipe,
	source: CharacterStats,
	target: CharacterStats,
	is_player_source: bool
) -> Array[String]:
	var log: Array[String] = []

	if recipe.bonus_effect_id == "break_shield" and target.shield > 0:
		var removed := target.shield
		target.set_shield(0)
		log.append("Комбо ломает щит: %d" % removed)

	if recipe.bonus_damage > 0:
		log.append_array(_apply_combo_damage(source.last_card, target, recipe.bonus_damage, is_player_source))

	if recipe.bonus_heal > 0:
		var heal_stat := _combo_stat_from_card(source.last_card)
		source.apply_stat_change(heal_stat, recipe.bonus_heal)
		log.append("Комбо-восстановление: +%d %s" % [recipe.bonus_heal, _stat_label(heal_stat)])

	match recipe.bonus_effect_id:
		"discard_one":
			log.append_array(_combo_discard_one(target))
		"mirror_finish":
			log.append_array(_combo_mirror_finish(source, target, is_player_source))
		"fortify_shield":
			source.set_shield(source.shield + 3)
			log.append("Комбо-щит: +3")
		"dogmatic_debuff":
			log.append_array(_apply_combo_damage_to_stat(target, &"logic", 1, is_player_source))
		"break_shield", "":
			pass
		_:
			log.append("Комбо-эффект: %s" % recipe.bonus_effect_id)

	return log


func _apply_combo_damage(
	card: CardInstance,
	target: CharacterStats,
	damage: int,
	is_player_source: bool
) -> Array[String]:
	var stat_name := _combo_stat_from_card(card)
	return _apply_combo_damage_to_stat(target, stat_name, damage, is_player_source)


func _apply_combo_damage_to_stat(
	target: CharacterStats,
	stat_name: StringName,
	damage: int,
	is_player_source: bool
) -> Array[String]:
	var log: Array[String] = []
	var remaining_damage := damage

	if target.shield > 0:
		var absorbed := mini(target.shield, remaining_damage)
		target.set_shield(target.shield - absorbed)
		remaining_damage -= absorbed
		log.append("Комбо: щит поглотил %d" % absorbed)
		if target.shield <= 0:
			log.append("Комбо разрушило щит")

	if remaining_damage <= 0:
		return log

	if scales_mgr:
		var is_player_target := not is_player_source
		var result := scales_mgr.apply_damage_with_scales(target, stat_name, remaining_damage, is_player_target)
		log.append("Комбо-урон: -%d %s" % [result.actual_damage, _stat_label(stat_name)])
		if result.scales_shift != 0:
			log.append("Весы: %+d" % result.scales_shift)
	else:
		target.apply_stat_change(stat_name, -remaining_damage)
		log.append("Комбо-урон: -%d %s" % [remaining_damage, _stat_label(stat_name)])

	return log


func _combo_discard_one(target: CharacterStats) -> Array[String]:
	var log: Array[String] = []
	if target.hand.is_empty():
		log.append("Комбо-сброс не сработал: рука пуста")
		return log
	var idx := randi() % target.hand.size()
	var discarded: CardInstance = target.hand[idx]
	target.hand.remove_at(idx)
	target.discard_pile.append(discarded)
	log.append("Комбо-сброс: %s" % discarded.data.card_name)
	return log


func _combo_mirror_finish(
	source: CharacterStats,
	target: CharacterStats,
	is_player_source: bool
) -> Array[String]:
	var log: Array[String] = []
	if target.last_card == null or target.last_card.data.category != Enums.CardCategory.ATTACK:
		log.append("Зеркальный финиш не сработал")
		return log
	var damage := maxi(1, target.last_card.data.base_damage * 2)
	var stat_name := _combo_stat_from_card(target.last_card)
	log.append_array(_apply_combo_damage_to_stat(target, stat_name, damage, is_player_source))
	if source.shield > 0:
		source.set_shield(source.shield + 1)
		log.append("Зеркальный финиш: щит +1")
	return log


func _combo_stat_from_card(card: CardInstance) -> StringName:
	if card == null or card.data == null:
		return &"logic"
	match card.data.effect:
		Enums.CardEffect.EMOTION:
			return &"emotion"
		Enums.CardEffect.RANDOM:
			return RulesEngine.resolve_random_effect()
	return &"logic"


func _stat_label(stat_name: StringName) -> String:
	if stat_name == &"logic":
		return "логика"
	if stat_name == &"emotion":
		return "эмоции"
	return str(stat_name)


func _consume_card(card: CardInstance, owner: CharacterStats) -> void:
	if _is_rage_card(card):
		owner.rage_used = true
	elif _is_burst_card(card):
		owner.burst_used = true
	var exhausted := card.use()
	if exhausted:
		owner.discard_pile.append(card)
		owner.hand.erase(card)


func _draw_cards_to_hand_limit(stats: CharacterStats) -> void:
	if stats.deck.is_empty():
		_reshuffle_discard_into_deck(stats)
	if stats.deck.is_empty():
		return
	var hand_limit := stats.get_hand_limit()
	var to_draw := hand_limit - stats.hand.size()

	var existing_names: Dictionary = {}
	for c in stats.hand:
		existing_names[c.data.card_name] = true

	for i in to_draw:
		if stats.deck.is_empty():
			break

		# Try to draw a unique card
		var drawn: CardInstance = null
		for attempt in stats.deck.size():
			var idx := randi() % stats.deck.size()
			if not existing_names.has(stats.deck[idx].data.card_name):
				drawn = stats.deck[idx]
				stats.deck.remove_at(idx)
				break

		# Fallback: take any card
		if drawn == null and not stats.deck.is_empty():
			var idx := randi() % stats.deck.size()
			drawn = stats.deck[idx]
			stats.deck.remove_at(idx)

		if drawn:
			existing_names[drawn.data.card_name] = true
			stats.hand.append(drawn)


func _reshuffle_discard_into_deck(stats: CharacterStats) -> void:
	## Moves non-one-shot cards from discard back into the deck, resetting uses.
	## Reshuffles are unlimited — match end is driven entirely by reaching 3 points.
	## One-shot specials (rage/burst) stay in discard so they cannot be replayed.
	if stats.discard_pile.is_empty():
		return
	var kept: Array[CardInstance] = []
	var reshuffled: Array[CardInstance] = []
	for card in stats.discard_pile:
		if card == null or card.data == null:
			continue
		var card_id := card.data.card_id
		if card_id == SPECIAL_RAGE_ID or card_id == SPECIAL_BURST_ID:
			kept.append(card)
			continue
		card.uses_left = card.data.max_uses
		reshuffled.append(card)
	stats.deck.append_array(reshuffled)
	stats.discard_pile = kept


func _on_point_scored(is_player: bool, points: int) -> void:
	point_scored.emit(is_player, points)
