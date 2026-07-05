class_name EventChecker
extends RefCounted

signal event_started(event_type: Enums.EventType, event_name: String, message: String)
signal event_ended(message: String)
signal event_effects_applied(effects: Dictionary)

var turn_history: Array[Dictionary] = [] ## [{player_cat, enemy_cat}]
var active_event: Dictionary = {} ## {type, name, duration, max_duration, ...}
var event_cooldown: int = 0
var consecutive_empty_decks: int = 0


func record_turn(player_card: CardInstance, enemy_card: CardInstance) -> void:
	var entry := {
		"player_cat": player_card.data.category if player_card else -1,
		"enemy_cat": enemy_card.data.category if enemy_card else -1
	}
	turn_history.append(entry)
	if turn_history.size() > 10:
		turn_history.pop_front()


func check_for_events(player: CharacterStats, enemy: CharacterStats) -> Dictionary:
	## Returns empty dict if no event, otherwise event data
	if event_cooldown > 0:
		event_cooldown -= 1
		return {}

	if not active_event.is_empty():
		return _update_active_event(player, enemy)

	# Check in priority order
	var event: Dictionary

	event = _check_critical_turning_point(player, enemy)
	if not event.is_empty(): return event

	event = _check_meditation()
	if not event.is_empty(): return event

	event = _check_heated_exchange()
	if not event.is_empty(): return event

	event = _check_mind_games()
	if not event.is_empty(): return event

	event = _check_fatigue(player, enemy)
	if not event.is_empty(): return event

	return {}


func apply_event_effects(player: CharacterStats, enemy: CharacterStats) -> Dictionary:
	if active_event.is_empty():
		return {}

	var effects := {"player": {}, "enemy": {}, "message": ""}

	match active_event.get("type", -1):
		Enums.EventType.MEDITATION:
			effects.player = {"emotion": -1, "logic": 1}
			effects.enemy = {"emotion": -1, "logic": 1}
			effects.message = "(Медитация: -1 эмоции, +1 логика)"

		Enums.EventType.HEATED_EXCHANGE:
			effects.player = {"emotion": 2, "max_logic_penalty": -1}
			effects.enemy = {"emotion": 2, "max_logic_penalty": -1}
			effects.message = "(Накал спора: +2 эмоции, максимум логики -1)"

		Enums.EventType.MIND_GAMES:
			effects.player = {"logic": 1, "damage_reduction": 0.25}
			effects.enemy = {"logic": 1, "damage_reduction": 0.25}
			effects.message = "(Игра умов: +1 логика, -25% урона)"

		Enums.EventType.CRITICAL_TURNING_POINT:
			var loser_is_player: bool = active_event.get("loser_is_player", false)
			if loser_is_player:
				effects.player = {"emotion": 3}
				effects.enemy = {"logic": -1}
			else:
				effects.enemy = {"emotion": 3}
				effects.player = {"logic": -1}
			effects.message = "(Критический перелом: проигрывающий +3 эмоции, лидер -1 логика)"

		Enums.EventType.FATIGUE:
			var p_stat: String = "logic" if randf() < 0.5 else "emotion"
			var e_stat: String = "logic" if randf() < 0.5 else "emotion"
			effects.player = {p_stat: -1}
			effects.enemy = {e_stat: -1}
			effects.message = "(Усталость: -1 %s у игрока, -1 %s у оппонента)" % [_stat_label(p_stat), _stat_label(e_stat)]

	# Apply the effects
	_apply_effects_to_stats(player, effects.get("player", {}))
	_apply_effects_to_stats(enemy, effects.get("enemy", {}))
	event_effects_applied.emit(effects)
	return effects


func get_active_event() -> Dictionary:
	return active_event


func reset() -> void:
	turn_history.clear()
	active_event.clear()
	event_cooldown = 0
	consecutive_empty_decks = 0


# --- Private ---

func _apply_effects_to_stats(stats: CharacterStats, effects: Dictionary) -> void:
	if effects.has("logic"):
		stats.apply_stat_change(&"logic", effects["logic"])
	if effects.has("emotion"):
		stats.apply_stat_change(&"emotion", effects["emotion"])
	if effects.has("max_logic_penalty"):
		stats.adjust_max(&"logic", effects["max_logic_penalty"])


func _activate_event(type: Enums.EventType, name: String, message: String, extra: Dictionary = {}) -> Dictionary:
	active_event = {"type": type, "name": name, "duration": 0, "message": message}
	active_event.merge(extra)
	event_started.emit(type, name, message)
	return active_event


func _update_active_event(player: CharacterStats, enemy: CharacterStats) -> Dictionary:
	active_event["duration"] = active_event.get("duration", 0) + 1

	if _check_event_end(player, enemy):
		var end_msg := _get_event_end_message()
		active_event.clear()
		event_cooldown = 2
		event_ended.emit(end_msg)
		return {"ended": true, "message": end_msg}

	return active_event


func _check_event_end(player: CharacterStats, enemy: CharacterStats) -> bool:
	if active_event.is_empty() or turn_history.is_empty():
		return false

	var last: Dictionary = turn_history.back()
	var p_cat: int = last.get("player_cat", -1)
	var e_cat: int = last.get("enemy_cat", -1)

	match active_event.get("type", -1):
		Enums.EventType.MEDITATION:
			return p_cat != Enums.CardCategory.DEFENSE or e_cat != Enums.CardCategory.DEFENSE
		Enums.EventType.HEATED_EXCHANGE:
			return p_cat != Enums.CardCategory.ATTACK or e_cat != Enums.CardCategory.ATTACK
		Enums.EventType.MIND_GAMES:
			return p_cat == Enums.CardCategory.DEFENSE or e_cat == Enums.CardCategory.DEFENSE
		Enums.EventType.CRITICAL_TURNING_POINT:
			return active_event.get("duration", 0) >= active_event.get("max_duration", 1)
		Enums.EventType.FATIGUE:
			return player.deck.size() > 0 or enemy.deck.size() > 0

	return false


func _get_event_end_message() -> String:
	match active_event.get("type", -1):
		Enums.EventType.MEDITATION:
			return "Медитация сорвана. Спор снова ускоряется."
		Enums.EventType.HEATED_EXCHANGE:
			return "Накал спадает."
		Enums.EventType.MIND_GAMES:
			return "Тактическая дуэль завершена."
		Enums.EventType.CRITICAL_TURNING_POINT:
			return "Напряжение спадает."
		Enums.EventType.FATIGUE:
			return "Карты вернулись. Усталость проходит."
	return "Событие завершилось."


func _check_meditation() -> Dictionary:
	if turn_history.size() < 2:
		return {}
	var last2 := turn_history.slice(-2)
	for turn in last2:
		if turn.get("player_cat") != Enums.CardCategory.DEFENSE or turn.get("enemy_cat") != Enums.CardCategory.DEFENSE:
			return {}
	return _activate_event(
		Enums.EventType.MEDITATION,
		"МЕДИТАЦИЯ",
		"Обе стороны ушли в защиту. Темп спора замедляется..."
	)


func _check_heated_exchange() -> Dictionary:
	if turn_history.size() < 3:
		return {}
	var last3 := turn_history.slice(-3)
	for turn in last3:
		if turn.get("player_cat") != Enums.CardCategory.ATTACK or turn.get("enemy_cat") != Enums.CardCategory.ATTACK:
			return {}
	return _activate_event(
		Enums.EventType.HEATED_EXCHANGE,
		"НАКАЛ СПОРА",
		"Аргументы становятся резче. Эмоции растут, логика проседает..."
	)


func _check_mind_games() -> Dictionary:
	if turn_history.size() < 2:
		return {}
	var last2 := turn_history.slice(-2)
	for turn in last2:
		var p_tactical: bool = turn.get("player_cat") == Enums.CardCategory.ATTACK or turn.get("player_cat") == Enums.CardCategory.EVASION
		var e_tactical: bool = turn.get("enemy_cat") == Enums.CardCategory.ATTACK or turn.get("enemy_cat") == Enums.CardCategory.EVASION
		if not (p_tactical and e_tactical):
			return {}
	return _activate_event(
		Enums.EventType.MIND_GAMES,
		"ИГРА УМОВ",
		"Обе стороны играют тактически. Логика острее, но урон ниже..."
	)


func _check_critical_turning_point(player: CharacterStats, enemy: CharacterStats) -> Dictionary:
	var p_total := player.logic + player.emotion
	var e_total := enemy.logic + enemy.emotion
	var gap := absi(p_total - e_total)

	if gap < 5:
		return {}

	var loser_is_player := p_total < e_total
	var loser := player if loser_is_player else enemy

	if loser.logic < 0 or loser.emotion < 0:
		return _activate_event(
			Enums.EventType.CRITICAL_TURNING_POINT,
			"КРИТИЧЕСКИЙ ПЕРЕЛОМ",
			"Одна сторона на грани. В споре чувствуется перелом...",
			{"loser_is_player": loser_is_player, "max_duration": 1}
		)
	return {}


func _check_fatigue(player: CharacterStats, enemy: CharacterStats) -> Dictionary:
	if player.deck.size() == 0 and enemy.deck.size() == 0:
		consecutive_empty_decks += 1
		if consecutive_empty_decks >= 2:
			return _activate_event(
				Enums.EventType.FATIGUE,
				"УСТАЛОСТЬ",
				"Колоды пусты. Участники выдыхаются и теряют фокус..."
			)
	else:
		consecutive_empty_decks = 0
	return {}


func _stat_label(stat: String) -> String:
	if stat == "logic":
		return "логика"
	if stat == "emotion":
		return "эмоции"
	return stat
