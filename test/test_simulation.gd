extends Node

## Batch simulation harness: runs N AI vs AI matches and prints aggregate metrics
## designed to surface design concerns:
##   - average match length / variance (pacing)
##   - scale dynamics (back-and-forth vs monotonic drain)
##   - tension / rage / burst frequency (is comeback drama happening?)
##   - combo trigger rate + which recipes fire (does the system show off?)
##   - card usage distribution (is the deck actually being explored?)
##   - damage scaling triggers (is anyone spamming one effect?)
##   - lead changes (is there real contest, or one-sided marches?)
##
## Run by opening test/test_simulation.tscn and pressing F6.

@export var num_matches: int = 50
@export var max_turns: int = 200
@export var deck_name: String = "Кофе"


func _ready() -> void:
	await get_tree().process_frame
	run_simulation()


func run_simulation() -> void:
	print("\n=== СИМУЛЯЦИЯ: %d матчей, колода '%s' ===\n" % [num_matches, deck_name])
	var deck := CardDatabase.get_deck(deck_name)
	if deck == null:
		push_error("Колода '%s' не найдена" % deck_name)
		return

	var totals := _new_totals()
	var t_start := Time.get_ticks_msec()

	for i in num_matches:
		_simulate_match(deck, totals)
		if (i + 1) % 10 == 0:
			print("  ... %d / %d" % [i + 1, num_matches])

	var t_elapsed := (Time.get_ticks_msec() - t_start) / 1000.0
	print("\n=== ОТЧЁТ (за %.1f с) ===" % t_elapsed)
	_print_report(totals)


func _new_totals() -> Dictionary:
	return {
		"matches_played": 0,
		"player_wins": 0,
		"timed_out": 0,
		"ended_by_points": 0,
		"ended_by_exhaustion": 0,
		"turn_counts": [],
		"combo_counts": [],
		"player_combo_counts": [],
		"opponent_combo_counts": [],
		"combo_by_id": {},
		"card_usage": {},
		"category_usage": {0: 0, 1: 0, 2: 0},
		"rage_uses": 0,
		"burst_uses": 0,
		"max_tensions": [],
		"scale_swings": [],
		"max_scales_abs": [],
		"lead_changes": [],
		"damage_scale_triggers": [],
		"first_point_turn": [],
		"point_diffs": [],
		"total_points_per_match": [],
		"knockdown_points": [],
	}


func _simulate_match(deck: DeckData, totals: Dictionary) -> void:
	var state := GameState.new()
	state.ai = AIBasic.new()
	state.initialize(deck, state.ai)

	var ai_player := AIBasic.new() # acts on player side

	# Per-match counters captured via closures.
	var combo_count := [0]
	var player_combo_count := [0]
	var opponent_combo_count := [0]
	var combo_by_id := {}
	var damage_scale_triggers := [0]
	var end_reason := [""]

	state.combo_triggered.connect(func(recipe: ComboRecipe) -> void:
		combo_count[0] += 1
		combo_by_id[recipe.recipe_id] = combo_by_id.get(recipe.recipe_id, 0) + 1)

	state.match_over.connect(func(_won: bool, reason: String) -> void:
		end_reason[0] = reason)

	# Track scale peaks via signal so we catch the value *before* point-reset zeros it.
	var max_scale_signal := [0]
	state.scales_mgr.scales_changed.connect(func(old_v: int, new_v: int) -> void:
		max_scale_signal[0] = maxi(max_scale_signal[0], maxi(absi(old_v), absi(new_v))))

	var knockdown_points := [0]
	state.turn_resolved.connect(func(log: Array) -> void:
		for line in log:
			if typeof(line) != TYPE_STRING:
				continue
			if line.begins_with("Снижение повтора"):
				damage_scale_triggers[0] += 1
			elif line.begins_with("КОМБО Вы"):
				player_combo_count[0] += 1
			elif line.begins_with("КОМБО Оппонент"):
				opponent_combo_count[0] += 1)

	# Knockdown points fire via turn_resolver's effect_applied (lines that start with "ОБВАЛ").
	state.turn_resolver.effect_applied.connect(func(desc: String) -> void:
		if desc.begins_with("ОБВАЛ"):
			knockdown_points[0] += 1)

	var category_usage := {0: 0, 1: 0, 2: 0}
	var card_usage := {}
	var max_tension := 0
	var scale_swings := 0
	var max_scale_abs := 0
	var lead_changes := 0
	var last_lead := 0
	var first_point_turn := -1
	var prev_total_points := 0

	# Opening half-turn when opponent won the coin flip.
	if not state.is_player_turn:
		state.play_opening_ai()
		max_tension = maxi(max_tension, state.player.tension)
		max_tension = maxi(max_tension, state.opponent.tension)
		max_scale_abs = maxi(max_scale_abs, absi(state.scales_mgr.scales))

	var turn := 0
	while state.phase != Enums.GamePhase.MATCH_OVER and turn < max_turns:
		turn += 1
		var prev_scales := state.scales_mgr.scales

		var player_card := ai_player.choose_card(state.player.hand, state.player, state.opponent)
		if player_card == null:
			break

		card_usage[player_card.data.card_id] = card_usage.get(player_card.data.card_id, 0) + 1
		category_usage[int(player_card.data.category)] += 1

		state.play_turn(player_card)

		max_tension = maxi(max_tension, state.player.tension)
		max_tension = maxi(max_tension, state.opponent.tension)

		var cur_scales: int = state.scales_mgr.scales
		scale_swings += absi(cur_scales - prev_scales)
		max_scale_abs = maxi(max_scale_abs, absi(cur_scales))
		max_scale_abs = maxi(max_scale_abs, max_scale_signal[0])

		var total_points: int = state.player.points + state.opponent.points
		if first_point_turn < 0 and total_points > prev_total_points:
			first_point_turn = turn
		prev_total_points = total_points

		var cur_lead := 0
		if state.player.points > state.opponent.points:
			cur_lead = 1
		elif state.player.points < state.opponent.points:
			cur_lead = -1
		if cur_lead != 0 and last_lead != 0 and cur_lead != last_lead:
			lead_changes += 1
		if cur_lead != 0:
			last_lead = cur_lead

	# Aggregate.
	totals["matches_played"] += 1
	if turn >= max_turns and state.phase != Enums.GamePhase.MATCH_OVER:
		totals["timed_out"] += 1
	if state.player.points >= 3:
		totals["player_wins"] += 1
	totals["turn_counts"].append(turn)
	totals["combo_counts"].append(combo_count[0])
	totals["player_combo_counts"].append(player_combo_count[0])
	totals["opponent_combo_counts"].append(opponent_combo_count[0])
	if end_reason[0] == "points":
		totals["ended_by_points"] += 1
	elif end_reason[0] == "exhaustion":
		totals["ended_by_exhaustion"] += 1
	for cid in combo_by_id:
		totals["combo_by_id"][cid] = totals["combo_by_id"].get(cid, 0) + combo_by_id[cid]
	for cid in card_usage:
		totals["card_usage"][cid] = totals["card_usage"].get(cid, 0) + card_usage[cid]
	for cat in category_usage:
		totals["category_usage"][cat] += category_usage[cat]
	if state.player.rage_used:
		totals["rage_uses"] += 1
	if state.opponent.rage_used:
		totals["rage_uses"] += 1
	if state.player.burst_used:
		totals["burst_uses"] += 1
	if state.opponent.burst_used:
		totals["burst_uses"] += 1
	totals["max_tensions"].append(max_tension)
	totals["scale_swings"].append(scale_swings)
	totals["max_scales_abs"].append(max_scale_abs)
	totals["lead_changes"].append(lead_changes)
	totals["damage_scale_triggers"].append(damage_scale_triggers[0])
	if first_point_turn > 0:
		totals["first_point_turn"].append(first_point_turn)
	totals["point_diffs"].append(absi(state.player.points - state.opponent.points))
	totals["total_points_per_match"].append(state.player.points + state.opponent.points)
	totals["knockdown_points"].append(knockdown_points[0])


func _print_report(totals: Dictionary) -> void:
	var matches: int = totals["matches_played"]
	if matches == 0:
		print("Нет данных.")
		return

	print("Матчей: %d (победы игрока: %d / %.0f%%, таймауты: %d)" % [
		matches, totals["player_wins"], 100.0 * totals["player_wins"] / matches, totals["timed_out"]
	])
	print("Концовки: %d очков / %d истощение" % [
		totals["ended_by_points"], totals["ended_by_exhaustion"]
	])

	print("\n--- ДЛИТЕЛЬНОСТЬ ---")
	_print_stats("Ходы за матч", totals["turn_counts"])
	_print_stats("Ход первого очка", totals["first_point_turn"])
	_print_stats("Всего очков набрано в матче", totals["total_points_per_match"])
	_print_stats("Из них через обвал (knockdown)", totals["knockdown_points"])
	_print_stats("Разрыв в очках на финиш", totals["point_diffs"])

	print("\n--- ДИНАМИКА ВЕСОВ ---")
	_print_stats("Сумма свингов |Δвесы| за матч", totals["scale_swings"])
	_print_stats("Пиковая |весы| в матче", totals["max_scales_abs"])
	_print_stats("Смен лидера (после первого очка)", totals["lead_changes"])

	print("\n--- НАПРЯЖЕНИЕ / COMEBACK ---")
	_print_stats("Пик накала за матч (любая сторона)", totals["max_tensions"])
	print("Активаций Rage: %d (%.2f на матч из 2 сторон)" % [
		totals["rage_uses"], float(totals["rage_uses"]) / matches
	])
	print("Использований Burst: %d (%.2f на матч из 2 сторон)" % [
		totals["burst_uses"], float(totals["burst_uses"]) / matches
	])

	print("\n--- РАЗНООБРАЗИЕ И СПАМ ---")
	_print_stats("Срабатываний damage scaling", totals["damage_scale_triggers"])
	_print_stats("Всего комбо за матч", totals["combo_counts"])
	_print_stats("Комбо игрока", totals["player_combo_counts"])
	_print_stats("Комбо оппонента", totals["opponent_combo_counts"])

	print("\n--- РАСПРЕДЕЛЕНИЕ КАТЕГОРИЙ (со стороны игрока) ---")
	var total_plays := 0
	for cat in totals["category_usage"]:
		total_plays += totals["category_usage"][cat]
	var cat_names := ["АТАКА", "ЗАЩИТА", "УКЛОНЕНИЕ"]
	for cat in totals["category_usage"]:
		var count = totals["category_usage"][cat]
		var pct = 100.0 * count / maxi(1, total_plays)
		print("  %s: %d (%.0f%%)" % [cat_names[cat], count, pct])

	print("\n--- ТОП КОМБО ---")
	if totals["combo_by_id"].is_empty():
		print("  (ни одно не сработало — повод задуматься)")
	else:
		for cid in _top_keys(totals["combo_by_id"], 10):
			print("  %-22s %d" % [cid, totals["combo_by_id"][cid]])

	print("\n--- ТОП КАРТ (игрок) ---")
	for cid in _top_keys(totals["card_usage"], 15):
		print("  %-22s %d" % [cid, totals["card_usage"][cid]])

	print("\n=== КОНЕЦ ОТЧЁТА ===\n")


func _print_stats(label: String, values: Array) -> void:
	if values.is_empty():
		print("  %-40s нет данных" % label)
		return
	var n := values.size()
	var sum_v := 0.0
	var mn: int = values[0]
	var mx: int = values[0]
	for v in values:
		sum_v += float(v)
		if int(v) < mn:
			mn = v
		if int(v) > mx:
			mx = v
	var avg := sum_v / float(n)
	var var_sum := 0.0
	for v in values:
		var_sum += pow(float(v) - avg, 2)
	var std := sqrt(var_sum / float(n))
	print("  %-40s avg %6.1f  std %5.1f  min %d  max %d" % [label, avg, std, mn, mx])


func _top_keys(d: Dictionary, n: int) -> Array:
	var keys := d.keys()
	keys.sort_custom(func(a, b) -> bool: return d[a] > d[b])
	return keys.slice(0, mini(n, keys.size()))
