extends Node

## ЗАЛ — A/B ПЕЙОФФ КОМБО (2026-07-23): confirmed GUARD → braced (временная неуязвимость к
## захвату до begin_turn владельца); confirmed TRAP → force_capture_eligible (opener считается
## захватывающим ударом даже не будучи Кражей, см. clinch_finalize/_finish_clinch). Сравниваем
## калибровку §8 GDD (capture=трофей, gate 2/4, лут=всё) С пейоффом и БЕЗ — те же метрики, что
## sim_runner.gd/GDD §8: 1й ход/KO/реш/ничьи, ходы, смены лидера, реш.точка, плюс захваты/матч
## и confirmed-комбо/матч (guard/trap отдельно). combo_payoff_enabled — тестовый seam в
## rules_core.gd (true по умолчанию — реальная игра не меняется).
## Запуск: res://duelogue/tools/sim_combo_payoff.tscn (F6) или headless.

const Rules := preload("res://duelogue/core/rules/rules_core.gd")
const Ai := preload("res://duelogue/core/ai/ai.gd")

@export var matches_per_cell: int = 800
@export var field_matches: int = 200
@export var hand_size: int = 5

var _ai: RefCounted

const BASE := 1
const KOMI := 0
const STEAL := 2
const FORTIFY := 0
const CLINCH := true
const FREEZE := true
const CAPTURE := 1
const GATE_X := 2
const GATE_Y := 4
const SW := 0
const LOOT := 1
const COMP_U := 3
const COMP_T := 8
const COMP_R := 9

const PAYOFF_CONFIGS := [
	{"label": "пейофф ВКЛ (guard=braced, trap=force-capture)", "enabled": true},
	{"label": "пейофф ВЫКЛ (было до 2026-07-23)", "enabled": false},
]
const MIRRORS := ["balanced", "aggro", "smart"]
const STYLES := ["tall", "wide", "aggro", "balanced", "smart"]


func _ready() -> void:
	_ai = Ai.new()
	await get_tree().process_frame
	print("\n=== ЗАЛ — A/B ПЕЙОФФ КОМБО (захват=трофей, gate 2/4, лут=всё, рука=%d) ===" % hand_size)
	for config in PAYOFF_CONFIGS:
		var enabled := bool(config.enabled)
		print("\n### %s ###" % String(config.label))
		print("--- зеркало (стиль vs он же, %d матчей/ячейку) ---" % matches_per_cell)
		print("%-9s| 1й ход| нок | реш | нич |ходов| смен лида|реш.точка|захв/матч|guard/матч|trap/матч" % "стиль")
		for style in MIRRORS:
			_mirror_row(style, enabled)
		print("--- поле стилей (%% побед против всех прочих, %d матчей/пара) ---" % field_matches)
		print("%-8s %-5s %-5s %-5s %-5s %-5s" % ["", "tall", "wide", "aggr", "bal", "SMART"])
		_field_row(enabled)
	print("\n=== КОНЕЦ ===\n")
	get_tree().quit()


func _new_match(first: String, payoff_enabled: bool) -> RefCounted:
	var m := Rules.new()
	m.reset(first, COMP_U, COMP_T, COMP_R, hand_size, BASE, KOMI, STEAL, FORTIFY,
		CLINCH, FREEZE, CAPTURE, GATE_X, GATE_Y, SW, LOOT)
	m.combo_payoff_enabled = payoff_enabled
	return m


func _mirror_row(style: String, payoff_enabled: bool) -> void:
	var first_wins := 0
	var decisive := 0
	var ko := 0
	var dec := 0
	var draw := 0
	var turns_sum := 0
	var lead_sum := 0
	var decfrac_sum := 0.0
	var captures_sum := 0
	var guard_confirmed := 0
	var trap_confirmed := 0
	for i in matches_per_cell:
		var first := Rules.SIDE_YOU if randf() < 0.5 else Rules.SIDE_OPP
		var m := _new_match(first, payoff_enabled)
		var res: Dictionary = _ai.simulate(m, style, style)
		turns_sum += int(res.turns)
		lead_sum += int(res.lead_changes)
		decfrac_sum += float(res.decision_frac)
		captures_sum += int(res.captures)
		for raw in res.get("combo_events", []):
			var ev: Dictionary = raw
			if String(ev.get("terminal", "")) != "confirmed" or \
					String((ev.get("arbitration", {}) as Dictionary).get("channel", "")) != "combo_verdict":
				continue
			if String(ev.get("topology", "")).ends_with("trap"):
				trap_confirmed += 1
			else:
				guard_confirmed += 1
		match String(res.reason):
			"knockout": ko += 1
			"decision": dec += 1
			"draw": draw += 1
		if String(res.reason) != "draw":
			decisive += 1
			if String(res.winner) == first:
				first_wins += 1
	var n := float(matches_per_cell)
	print("%-9s| %4.0f%%| %3.0f%%| %3.0f%%| %3.0f%%| %3.1f | %8.2f | %7.2f | %7.2f | %8.2f | %7.2f" % [
		style, 100.0 * float(first_wins) / float(maxi(1, decisive)), 100.0 * float(ko) / n,
		100.0 * float(dec) / n, 100.0 * float(draw) / n, float(turns_sum) / n,
		float(lead_sum) / n, decfrac_sum / n, float(captures_sum) / n,
		float(guard_confirmed) / n, float(trap_confirmed) / n])


func _winrate(a: String, b: String, payoff_enabled: bool) -> float:
	var a_wins := 0
	var decisive := 0
	for i in field_matches:
		var first := Rules.SIDE_YOU if i % 2 == 0 else Rules.SIDE_OPP
		var m := _new_match(first, payoff_enabled)
		var res: Dictionary = _ai.simulate(m, a, b)
		if String(res.reason) != "draw":
			decisive += 1
			if String(res.winner) == Rules.SIDE_YOU:
				a_wins += 1
	if decisive == 0:
		return 0.5
	return float(a_wins) / float(decisive)


func _field_row(payoff_enabled: bool) -> void:
	var field := {}
	for s in STYLES:
		var wsum := 0.0
		for o in STYLES:
			if o == s:
				continue
			wsum += _winrate(s, o, payoff_enabled)
		field[s] = wsum / float(STYLES.size() - 1)
	print("%-8s %4.0f%% %4.0f%% %4.0f%% %4.0f%% %4.0f%%" % [
		"", field.tall * 100.0, field.wide * 100.0, field.aggro * 100.0,
		field.balanced * 100.0, field.smart * 100.0])
