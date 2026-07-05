extends Node

## ЗАЛ v0.3 — свип ЗАЛ-НОКАУТА (TKO «унёс зал»): порог K, при котором крен зала в твою
## пользу, доживший до начала твоего хода, выигрывает партию (у отстающего был полный ход
## на спасение поимкой/захватом — гейт на таком крене открыт на максимум).
## Вопрос игрока (2026-07-02): край шкалы должен быть достижим и что-то значить.
## Гипотезы ЗА: mercy-rule для решённых партий (ходов ↓), цель для пассивной коды,
## климакс для холднутой Кражи, tall получает путь к победе. Риски: снежный ком лидера
## (сторож: 1-й ход и реш.точка не должны просесть), tall-раш доминанта, дешёвые TKO при
## малом K. Фон: гейт 2/4 + добыча «со всей силой» (канон v0.3.2), sw выкл.
## Запуск: res://duelogue/tools/sim_tail.tscn (F6) или headless:
##   Godot --headless --path . res://duelogue/tools/sim_tail.tscn

const Rules := preload("res://duelogue/core/rules/rules_core.gd")
const Ai := preload("res://duelogue/core/ai/ai.gd")

@export var matches_per_cell: int = 1000
@export var field_matches: int = 300

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

## [K, hold]: порог зал-нокаута и «счёт судьи» (сколько кругов подряд держать). [0,1] = выкл.
const ZAL_KOS := [[0, 1], [8, 2], [8, 3], [10, 2], [10, 3]]
const STYLES := ["tall", "wide", "aggro", "balanced", "smart"]
## Конфиги поля стилей: [K, hold].
const FIELD_KOS := [[0, 1], [8, 3], [10, 3]]


func _ready() -> void:
	_ai = Ai.new()
	await get_tree().process_frame
	print("\n=== ЗАЛ v0.3 · ЗАЛ-НОКАУТ «УНЁС ЗАЛ» (гейт 2/4, лут=всё; матчей=%d) ===" % matches_per_cell)

	for mirror_style in ["smart", "balanced"]:
		print("\n--- ЗЕРКАЛО %s vs %s ---" % [mirror_style, mirror_style])
		print("%-7s | 1й ход | нок | ТОЛПА | реш | нич | ходов | смен лида | реш.точка | tail | капч" % "K/hold")
		for k in ZAL_KOS:
			_mirror_row(mirror_style, k[0], k[1])
	print("Цель: ТОЛПА — заметный, но не главный исход (~10-25%); ходов ЗАМЕТНО меньше;")
	print("      1й ход 45-60% и реш.точка ~0.6 НЕ просели; ничьи <=8%.")

	print("\n--- ПОЛЕ СТИЛЕЙ (средний %% побед стиля против всех прочих, матчей=%d) ---" % field_matches)
	print("%-8s | %-5s %-5s %-5s %-5s %-5s" % ["конфиг", "tall", "wide", "aggr", "bal", "SMART"])
	for k in FIELD_KOS:
		_field_row(k[0], k[1])
	print("Цель: доминанты нет, smart сверху; tall может подрасти (блеск теперь грозит TKO),")
	print("      но НЕ в топ; aggro не провален.")
	print("\n=== КОНЕЦ ===\n")
	get_tree().quit()


func _new_match(first: String, zal_ko: int, hold: int) -> RefCounted:
	var m: RefCounted = Rules.new()
	m.reset(first, COMP_U, COMP_T, COMP_R, 5, BASE, KOMI, STEAL, FORTIFY,
		CLINCH, FREEZE, CAPTURE, GATE_X, GATE_Y, SW, LOOT, zal_ko, hold)
	return m


func _mirror_row(style: String, zal_ko: int, hold: int) -> void:
	var first_wins := 0
	var decisive := 0
	var ko := 0
	var crowd := 0
	var dec := 0
	var draw := 0
	var turns_sum := 0
	var lead_sum := 0
	var decfrac_sum := 0.0
	var tail_sum := 0.0
	var cap_sum := 0
	for i in matches_per_cell:
		var first := Rules.SIDE_YOU if randf() < 0.5 else Rules.SIDE_OPP
		var m := _new_match(first, zal_ko, hold)
		var res: Dictionary = _ai.simulate(m, style, style)
		turns_sum += int(res.turns)
		lead_sum += int(res.lead_changes)
		decfrac_sum += float(res.decision_frac)
		tail_sum += float(res.tail_interaction)
		cap_sum += int(res.captures)
		match String(res.reason):
			"knockout": ko += 1
			"crowd": crowd += 1
			"decision": dec += 1
			"draw": draw += 1
		if String(res.reason) != "draw":
			decisive += 1
			if String(res.winner) == first:
				first_wins += 1
	var n := float(matches_per_cell)
	print("%-7s |  %3.0f%% |%3.0f%% | %4.0f%% |%3.0f%% |%3.0f%% | %5.1f | %9.2f | %9.2f | %3.0f%% | %4.2f" % [
		("выкл" if zal_ko == 0 else "%d/%d" % [zal_ko, hold]),
		float(first_wins) / float(maxi(1, decisive)) * 100.0,
		float(ko) / n * 100.0, float(crowd) / n * 100.0, float(dec) / n * 100.0, float(draw) / n * 100.0,
		float(turns_sum) / n, float(lead_sum) / n, decfrac_sum / n,
		tail_sum / n * 100.0, float(cap_sum) / n])


func _field_row(zal_ko: int, hold: int) -> void:
	var field := {}
	for s in STYLES:
		var wsum := 0.0
		for o in STYLES:
			if o == s:
				continue
			wsum += _winrate(s, o, zal_ko, hold)
		field[s] = wsum / float(STYLES.size() - 1)
	print("K=%-6s | %4.0f%% %4.0f%% %4.0f%% %4.0f%% %4.0f%%" % [
		("выкл" if zal_ko == 0 else "%d/%d" % [zal_ko, hold]), field.tall * 100.0, field.wide * 100.0,
		field.aggro * 100.0, field.balanced * 100.0, field.smart * 100.0])


func _winrate(a: String, b: String, zal_ko: int, hold: int) -> float:
	var a_wins := 0
	var decisive := 0
	for i in field_matches:
		var first := Rules.SIDE_YOU if i % 2 == 0 else Rules.SIDE_OPP
		var m := _new_match(first, zal_ko, hold)
		var res: Dictionary = _ai.simulate(m, a, b)
		if String(res.reason) != "draw":
			decisive += 1
			if String(res.winner) == Rules.SIDE_YOU:
				a_wins += 1
	if decisive == 0:
		return 0.5
	return float(a_wins) / float(decisive)
