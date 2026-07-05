extends Node

## ЗАЛ v0.3 — свип ЗАХВАТА РАМКИ × УМНЫЙ БОТ.
## (1) Захват: Кража, снёсшая последний тезис рамки, переносит рамку к атакующему.
## (2) smart-бот: играет ось мастерства (захват/защита от захвата/teardown + экономный клинч).
## Смотрим: сильнее ли smart обычных стилей; живее ли smart-vs-smart (смен лида) под захватом.
## Запуск: открыть zal_v3_sim.tscn, F6.

const ZalV3 := preload("res://test/prototype_zal/zal_v3_model.gd")

@export var matches_per_cell: int = 300
@export var hand_size: int = 5

const BASE := 1
const KOMI := 0
const STEAL := 2
const FORTIFY := 0
const CLINCH := true
const FREEZE := true
const COMP_U := 3
const COMP_T := 8
const COMP_R := 9

const CAPTURE_MODES := [0, 1, 2]
const CAP_NAMES := {0: "выкл", 1: "трофей", 2: "актив"}
const MIRRORS := ["balanced", "smart"]
const STYLES := ["tall", "wide", "aggro", "balanced", "smart"]


func _ready() -> void:
	await get_tree().process_frame
	print("\n=== ЗАЛ v0.3 · ЗАХВАТ × УМНЫЙ БОТ (база=%d, клинч, %d Кражи, рука=%d, матчей=%d) ===" % [
		BASE, STEAL, hand_size, matches_per_cell])

	print("\n--- ЗЕРКАЛО (стиль vs он же): динамика и исходы ---")
	print("%-8s %-9s | 1й ход | нок | реш | нич | ходов | смен лида | реш.точка" % ["захват", "стиль"])
	for cap in CAPTURE_MODES:
		for ms in MIRRORS:
			_mirror_row(cap, ms)
	print("Цель: smart-vs-smart — смен лида ВЫШЕ и реш.точка БЛИЖЕ к 1.0, чем у balanced.")

	print("\n--- ПОЛЕ СТИЛЕЙ (средний %% побед стиля против всех прочих) ---")
	print("%-8s | %-5s %-5s %-5s %-5s %-5s" % ["захват", "tall", "wide", "aggr", "bal", "SMART"])
	for cap in CAPTURE_MODES:
		_field_row(cap)
	print("Цель: smart заметно >50%% (реально сильнее), aggro подтянут, доминанты-стиля нет.")

	for cap in CAPTURE_MODES:
		_triangle(cap)
	print("\n=== КОНЕЦ ===\n")
	get_tree().quit()


func _mirror_row(cap: int, style: String) -> void:
	var m := _mirror(cap, style)
	print("%-8s %-9s |  %3.0f%% |%3.0f%% |%3.0f%% |%3.0f%% | %5.1f | %8.2f | %8.2f" % [
		CAP_NAMES[cap], style, m.first * 100.0, m.ko * 100.0, m.dec * 100.0, m.draw * 100.0,
		m.turns, m.lead_changes, m.decision_frac])


func _field_row(cap: int) -> void:
	var field := {}
	for s in STYLES:
		var wsum := 0.0
		for o in STYLES:
			if o == s:
				continue
			wsum += _winrate(s, o, cap)
		field[s] = wsum / float(STYLES.size() - 1)
	print("%-8s | %4.0f%% %4.0f%% %4.0f%% %4.0f%% %4.0f%%" % [
		CAP_NAMES[cap], field.tall * 100.0, field.wide * 100.0, field.aggro * 100.0,
		field.balanced * 100.0, field.smart * 100.0])


## Зеркало style-vs-style: %% побед 1-го ходящего + разбивка исходов + динамика лида.
func _mirror(cap: int, style: String) -> Dictionary:
	var first_wins := 0
	var decisive := 0
	var ko := 0
	var dec := 0
	var draw := 0
	var turns_sum := 0
	var lead_sum := 0
	var decfrac_sum := 0.0
	for i in matches_per_cell:
		var m := ZalV3.new()
		var first := ZalV3.SIDE_YOU if randf() < 0.5 else ZalV3.SIDE_OPP
		m.reset(first, COMP_U, COMP_T, COMP_R, hand_size, BASE, KOMI, STEAL, FORTIFY, CLINCH, FREEZE, cap)
		var res := m.simulate(style, style)
		turns_sum += int(res.turns)
		lead_sum += int(res.lead_changes)
		decfrac_sum += float(res.decision_frac)
		match String(res.reason):
			"knockout": ko += 1
			"decision": dec += 1
			"draw": draw += 1
		if String(res.reason) != "draw":
			decisive += 1
			if String(res.winner) == first:
				first_wins += 1
	var n := float(matches_per_cell)
	return {
		"first": float(first_wins) / float(maxi(1, decisive)),
		"ko": float(ko) / n, "dec": float(dec) / n, "draw": float(draw) / n,
		"turns": float(turns_sum) / n,
		"lead_changes": float(lead_sum) / n,
		"decision_frac": decfrac_sum / n,
	}


func _winrate(a: String, b: String, cap: int) -> float:
	var a_wins := 0
	var decisive := 0
	for i in matches_per_cell:
		var m := ZalV3.new()
		var first := ZalV3.SIDE_YOU if i % 2 == 0 else ZalV3.SIDE_OPP
		m.reset(first, COMP_U, COMP_T, COMP_R, hand_size, BASE, KOMI, STEAL, FORTIFY, CLINCH, FREEZE, cap)
		var res := m.simulate(a, b)
		if String(res.reason) != "draw":
			decisive += 1
			if String(res.winner) == ZalV3.SIDE_YOU:
				a_wins += 1
	if decisive == 0:
		return 0.5
	return float(a_wins) / float(decisive)


func _triangle(cap: int) -> void:
	print("\n--- МАТРИЦА захват=%s (%% побед строки YOU vs столбца OPP) ---" % CAP_NAMES[cap])
	var header := "%-10s" % "YOU\\OPP"
	for col in STYLES:
		header += " %8s" % col
	print(header)
	for row in STYLES:
		var line := "%-10s" % row
		for col in STYLES:
			line += " %7.0f%%" % (_winrate(row, col, cap) * 100.0)
		print(line)
