extends Node

## ЗАЛ v0.2 — пакетный прогон AI vs AI с метриками раздела 10 спеки
## (context/zal_core_v0.2.md). Запуск: открыть zal_core_sim.tscn, F6.
## Печатает отчёт в Output и завершает работу.

const ZalModel := preload("res://test/prototype_zal/zal_core_model.gd")

@export var num_matches: int = 200


func _ready() -> void:
	await get_tree().process_frame
	run_simulation()
	get_tree().quit()


func run_simulation() -> void:
	print("\n=== ЗАЛ v0.2: симуляция %d матчей (AI vs AI) ===" % num_matches)
	print("Константы: ROOM_MAX=%d TURN_CAP=%d BASE_SWAY=%d CHAIN_CAP=%d PAIR_BONUS=%d HAND=%d\n" % [
		ZalModel.ROOM_MAX, ZalModel.TURN_CAP, ZalModel.BASE_SWAY,
		ZalModel.CHAIN_CAP, ZalModel.PAIR_BONUS, ZalModel.HAND_SIZE,
	])

	var turns: Array = []
	var end_edge := 0
	var end_cap := 0
	var end_sudden := 0
	var you_wins := 0
	var first_mover_wins := 0
	var pairs_you: Array = []
	var pairs_opp: Array = []
	var both_paired := 0
	var chain_avgs: Array = []
	var chain_maxes: Array = []
	var lead_changes: Array = []
	var loser_peaks: Array = []

	var t_start := Time.get_ticks_msec()

	for m in num_matches:
		var model := ZalModel.new()
		var first := ZalModel.SIDE_YOU if randf() < 0.5 else ZalModel.SIDE_OPP
		model.reset(first)

		var prev_sign := 0
		var flips := 0
		var peak := {ZalModel.SIDE_YOU: 0, ZalModel.SIDE_OPP: 0}
		var chain_sum := 0
		var chain_max := 0
		var plays := 0
		var guard := 0

		while not model.game_over and guard < 200:
			guard += 1
			var side: String = model.next_side
			var idx: int = model.ai_choose(side)
			if idx < 0:
				break
			var res: Dictionary = model.play(side, idx)
			plays += 1
			chain_sum += int(res.chain)
			chain_max = maxi(chain_max, int(res.chain))
			var sgn := signi(model.room)
			if sgn != 0:
				if prev_sign != 0 and sgn != prev_sign:
					flips += 1
				prev_sign = sgn
			peak[ZalModel.SIDE_YOU] = maxi(peak[ZalModel.SIDE_YOU], model.room)
			peak[ZalModel.SIDE_OPP] = maxi(peak[ZalModel.SIDE_OPP], -model.room)

		turns.append(model.full_turns())
		match String(model.end_reason):
			"edge": end_edge += 1
			"cap": end_cap += 1
			"sudden_death": end_sudden += 1
		if model.winner == ZalModel.SIDE_YOU:
			you_wins += 1
		if model.winner == first:
			first_mover_wins += 1

		var py: int = model.sides[ZalModel.SIDE_YOU].pairs_fired
		var po: int = model.sides[ZalModel.SIDE_OPP].pairs_fired
		pairs_you.append(py)
		pairs_opp.append(po)
		if py >= 1 and po >= 1:
			both_paired += 1

		if plays > 0:
			chain_avgs.append(float(chain_sum) / float(plays))
		chain_maxes.append(chain_max)
		lead_changes.append(flips)
		if model.winner != "":
			loser_peaks.append(peak[model.other(model.winner)])

	var t_elapsed := (Time.get_ticks_msec() - t_start) / 1000.0
	print("=== ОТЧЁТ (за %.1f с) ===\n" % t_elapsed)

	print("Победы стороны you: %d / %d (%.0f%%) — проверка симметрии, цель ~50%%" % [
		you_wins, num_matches, 100.0 * you_wins / num_matches])
	print("Победы ходившего первым: %.0f%% — проверка преимущества первого хода" % (
		100.0 * first_mover_wins / num_matches))

	print("\n--- КОНЦОВКИ ---")
	print("Край шкалы: %d (%.0f%%)  [цель ≥70%%]" % [end_edge, 100.0 * end_edge / num_matches])
	print("Решение по очкам (кап): %d (%.0f%%)" % [end_cap, 100.0 * end_cap / num_matches])
	print("Внезапная смерть: %d" % end_sudden)

	print("\n--- ДЛИТЕЛЬНОСТЬ ---")
	_print_stats("Полных ходов за матч", turns)

	print("\n--- ИМЕННЫЕ ПАРЫ ---")
	_print_stats("Пары за матч (you)", pairs_you)
	_print_stats("Пары за матч (opp)", pairs_opp)
	print("Матчи, где обе стороны собрали ≥1 пару: %.0f%%  [цель: высоко]" % (
		100.0 * both_paired / num_matches))

	print("\n--- ЦЕПОЧКИ ---")
	_print_stats_f("Средняя цепочка при ходе", chain_avgs)
	_print_stats("Пиковая цепочка за матч", chain_maxes)

	print("\n--- ДРАМА ---")
	_print_stats("Смены лидера за матч", lead_changes)
	_print_stats("Пик |зал| проигравшего", loser_peaks)
	print("  (пик проигравшего близко к %d = были моменты «почти выиграл»)" % ZalModel.ROOM_MAX)

	print("\n=== КОНЕЦ ОТЧЁТА ===\n")


func _print_stats(label: String, values: Array) -> void:
	var floats: Array = []
	for v in values:
		floats.append(float(v))
	_print_stats_f(label, floats)


func _print_stats_f(label: String, values: Array) -> void:
	if values.is_empty():
		print("  %-36s нет данных" % label)
		return
	var n := values.size()
	var sum_v := 0.0
	var mn: float = values[0]
	var mx: float = values[0]
	for v in values:
		sum_v += float(v)
		mn = minf(mn, float(v))
		mx = maxf(mx, float(v))
	var avg := sum_v / float(n)
	var var_sum := 0.0
	for v in values:
		var_sum += pow(float(v) - avg, 2)
	var std := sqrt(var_sum / float(n))
	print("  %-36s avg %6.2f  std %5.2f  min %.0f  max %.0f" % [label, avg, std, mn, mx])
