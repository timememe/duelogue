extends Node

## БАЛАНС ТРЕНИЯ/ИСХОДА/ОБЛЕГЧЕНИЯ КЛИНЧА (emotion_reactions.md v0.5 §7).
## Вопрос игрока (2026-08-24): динамика уже есть, но редко ощущается КАК СЛЕДУЕТ — сколько
## именно strain реально навешивает один клинч сегодня, и что будет, если покрутить числа.
##
## Формула v0.5 живёт в battle_controller._run_clinch и не трогается отсюда — этот сим её
## ВОСПРОИЗВОДИТ как чистую математику поверх сырых фактов клинча (ai.simulate().
## clinches_info), не запуская EmotionCore/BattleController: ai.simulate() работает на голом
## RulesCore и уже в сотни раз быстрее, чем гонять полный async-матч через контроллер.
## Если формулу в _run_clinch поменяют — обновить константы ниже вручную, они НЕ импортятся
## оттуда напрямую (там это локальные переменные внутри функции, не константы модуля).
##
## Запуск: res://duelogue/tools/sim_emotion_swing.tscn (F6) или headless:
##   Godot --headless --path . res://duelogue/tools/sim_emotion_swing.tscn

const Rules := preload("res://duelogue/core/rules/rules_core.gd")
const Ai := preload("res://duelogue/core/ai/ai.gd")

@export var matches_per_style: int = 500

var _ai: RefCounted

const BASE := 1
const KOMI := 0
const STEAL := 2
const FORTIFY := 0
const CLINCH := true
const FREEZE := true
const CAPTURE := 1
const HAND := 5
const COMP_U := 3
const COMP_T := 8
const COMP_R := 9

## Формула v0.5 (battle_controller._run_clinch) — outcome/relief/combo/redeem фиксированы
## (не то, что сейчас крутим), меняется только трение: FRICTION_VARIANTS ниже — список
## (делитель, пол). Каждый вариант считается на ОДНИХ И ТЕХ ЖЕ клинчах на пару стилей —
## матчи гоняются один раз, дальше только пересчёт формулы, без повторной симуляции. Так
## сравнение вариантов чистое — различия только от формулы, не от рандома нового прогона.
const OUTCOME_CAP := 3
const RELIEF_CAP := 3
const COMBO_BONUS := 1
const REDEEM_BONUS := 2

## name, делитель длины клинча, пол (минимальная ставка трения если length>0 — 0 = без пола,
## клинч может дать честный stake=0). baseline — то, что сейчас в battle_controller.
const FRICTION_VARIANTS := [
	{"name": "baseline /2, без пола", "divisor": 2, "floor": 0},
	{"name": "/1, без пола (каждая карта, не пара)", "divisor": 1, "floor": 0},
	{"name": "/2, пол=1 (у любого клинча минимум 1)", "divisor": 2, "floor": 1},
	{"name": "/2, пол=2", "divisor": 2, "floor": 2},
	{"name": "/1, пол=1", "divisor": 1, "floor": 1},
]

const STYLE_PAIRS := [["smart", "smart"], ["aggro", "aggro"]]


func _ready() -> void:
	_ai = Ai.new()
	await get_tree().process_frame
	print("\n=== ТРЕНИЕ КЛИНЧА · сравнение вариантов (матчей/пара стилей=%d) ===" % matches_per_style)
	print("outcome/relief=1(+1 снята)(+1 захват),потолок %d · combo=+%d · redeem=+%d — не меняются\n" % [
		OUTCOME_CAP, COMBO_BONUS, REDEEM_BONUS])
	for pair in STYLE_PAIRS:
		var style_a := String(pair[0])
		var style_b := String(pair[1])
		var clinches := _collect_clinches(style_a, style_b)
		print("--- %s vs %s (%d клинчей в выборке) ---" % [style_a, style_b, clinches.size()])
		print("  комбо/redeem не зависят от трения: %s" % _bonus_rates(clinches))
		print("%-32s | avg stake | %%stake=0 | avg удар | %%пиррова | %%чист.облегч | макс удар" % "вариант трения")
		for variant in FRICTION_VARIANTS:
			_report_variant(clinches, variant)
		print("")
	print("=== КОНЕЦ ===\n")
	get_tree().quit()


func _collect_clinches(style_a: String, style_b: String) -> Array:
	var clinches: Array = []
	for i in matches_per_style:
		var m := Rules.new()
		var first := Rules.SIDE_YOU if i % 2 == 0 else Rules.SIDE_OPP
		m.reset(first, COMP_U, COMP_T, COMP_R, HAND, BASE, KOMI, STEAL, FORTIFY, CLINCH, FREEZE, CAPTURE)
		var res: Dictionary = _ai.simulate(m, style_a, style_b)
		clinches.append_array(res.get("clinches_info", []))
	return clinches


func _report_variant(clinches: Array, variant: Dictionary) -> void:
	var divisor := int(variant.divisor)
	var floor_stake := int(variant.floor)
	var stakes: Array = []
	var loser_swings: Array = []
	var winner_swings: Array = []
	var combo_fires := 0
	var redeem_fires := 0
	for raw in clinches:
		var c: Dictionary = raw
		var length := int(c.t_added) + int(c.r_count)
		var stake := length / divisor
		if length > 0 and floor_stake > 0:
			stake = maxi(stake, floor_stake)
		stakes.append(stake)
		var applies := bool(c.landed) or String(c.stop_reason) != "voluntary"
		var loser_swing := stake
		var winner_swing := stake
		if applies:
			var base := 1
			if bool(c.removed):
				base += 1
			if bool(c.captured):
				base += 1
			var outcome := mini(OUTCOME_CAP, base)
			var relief := mini(RELIEF_CAP, base)
			var combo := 0
			if String(c.combo_result) == "confirmed":
				combo = COMBO_BONUS
				combo_fires += 1
			var redeem := 0
			if bool(c.frame_redeemed):
				redeem = REDEEM_BONUS
				redeem_fires += 1
			loser_swing += outcome + combo + redeem
			winner_swing -= relief + combo + redeem
		loser_swings.append(loser_swing)
		winner_swings.append(winner_swing)

	var zero_stake := 0
	for s in stakes:
		if int(s) == 0:
			zero_stake += 1
	var pyrrhic := 0
	var clean := 0
	for w in winner_swings:
		if int(w) > 0:
			pyrrhic += 1
		elif int(w) < 0:
			clean += 1
	var n := maxf(1.0, float(clinches.size()))
	print("%-32s | %9.2f | %7.0f%% | %8.2f | %7.0f%% | %11.0f%% | %9d" % [
		String(variant.name), _avg(stakes), 100.0 * float(zero_stake) / n, _avg(loser_swings),
		100.0 * float(pyrrhic) / n, 100.0 * float(clean) / n, _max_int(loser_swings)])


func _bonus_rates(clinches: Array) -> String:
	var combo_fires := 0
	var redeem_fires := 0
	for raw in clinches:
		var c: Dictionary = raw
		if String(c.combo_result) == "confirmed":
			combo_fires += 1
		if bool(c.frame_redeemed):
			redeem_fires += 1
	var n := maxf(1.0, float(clinches.size()))
	return "комбо %d/%d (%.1f%%) · redeem %d/%d (%.1f%%)" % [
		combo_fires, clinches.size(), 100.0 * float(combo_fires) / n,
		redeem_fires, clinches.size(), 100.0 * float(redeem_fires) / n]


func _avg(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0
	for v in values:
		total += int(v)
	return float(total) / float(values.size())


func _max_int(values: Array) -> int:
	var m := -999
	for v in values:
		m = maxi(m, int(v))
	return m if m > -999 else 0
