extends Node

## ИМЕННЫЕ ПРИЁМЫ (zal_run §2) — сим-полигон. Меряет ЦЕНУ каждого приёма в винрейте:
## обойма you = канон 20 с ЗАМЕНОЙ ванильных карт на именные (named_cards.inject),
## оппонент — чистый канон; smart vs smart. Вопросы:
##   · играется ли карта вообще (np — розыгрышей именных за матч; ~0 = бот её не находит);
##   · дельта винрейта на 1 приём (цена награды: цель +2..6 пп — сильнее ванили, не чит);
##   · стак ×2 (развилка §10.2: уникальность копий) и «грязный сет» из всех 6;
##   · зеркало 6vs6 — здоровье меты, когда приёмы у обеих сторон.
## Первая строка — ваниль vs ваниль: РЕГРЕССИЯ канона (хуки именных guarded и обязаны
## не сдвигать базу). Запуск: sim_named.tscn (F6) или headless:
##   Godot --headless --path . res://duelogue/tools/sim_named.tscn

const Rules := preload("res://duelogue/core/rules/rules_core.gd")
const Ai := preload("res://duelogue/core/ai/ai.gd")
const NamedCards := preload("res://duelogue/core/cards/named_cards.gd")

@export var matches_per_cell: int = 500

# Канон партии (= battle_controller / sim_tail; GDD v0.3.2).
const BASE := 1
const KOMI := 0
const STEAL := 2
const FORT := 0
const CLINCH := true
const FREEZE := true
const CAPTURE := 1
const GATE_X := 2
const GATE_Y := 4
const SW := 0
const LOOT := 1
const ZAL_KO := 10
const ZAL_HOLD := 3
const HAND := 5
const U := 3
const T := 8
const R := 9

var _ai: RefCounted


func _ready() -> void:
	_ai = Ai.new()
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	print("\n=== ИМЕННЫЕ ПРИЁМЫ · СИМ-ПОЛИГОН (замена в каноне 20; smart vs smart; матчей/ячейку=%d) ===" % matches_per_cell)
	print("%-26s | win%%Ы | нок толпа реш нич | ходов | капч | npЫ npО" % "обойма you")
	_cell("ваниль (регрессия канона)", [], [])
	print("  · соло-приёмы (замена 1 карты):")
	for id in ["gish_gallop", "socratic", "ad_hominem", "strawman", "burden_shift", "axiom"]:
		_cell(String(NamedCards.get_def(id).name), [id], [])
	print("  · стак и наборы:")
	_cell("Гиш-галоп ×2", ["gish_gallop", "gish_gallop"], [])
	_cell("Аксиома ×2", ["axiom", "axiom"], [])
	_cell("грязный сет (все 6)", NamedCards.ids(), [])
	_cell("зеркало: 6 vs 6", NamedCards.ids(), NamedCards.ids())
	print("Чтение: npЫ ~0 — приём не играется (чинить политику ИИ, не карту); дельта к регрессии —")
	print("        цена приёма; ×2 заметно > ×1 — довод за уникальность копий (§10.2).")
	print("\n=== КОНЕЦ (%.1f c) ===\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit()


func _cell(label: String, named_you: Array, named_opp: Array) -> void:
	var wins_you := 0
	var ko := 0
	var crowd := 0
	var dec := 0
	var draw := 0
	var turns_sum := 0
	var caps_sum := 0
	var np_you := 0
	var np_opp := 0
	for i in matches_per_cell:
		var first := Rules.SIDE_YOU if randf() < 0.5 else Rules.SIDE_OPP
		var m: RefCounted = Rules.new()
		m.reset(first, U, T, R, HAND, BASE, KOMI, STEAL, FORT,
			CLINCH, FREEZE, CAPTURE, GATE_X, GATE_Y, SW, LOOT, ZAL_KO, ZAL_HOLD)
		NamedCards.inject(m.sides[Rules.SIDE_YOU], named_you)
		NamedCards.inject(m.sides[Rules.SIDE_OPP], named_opp)
		var res: Dictionary = _ai.simulate(m, "smart", "smart")
		if String(res.winner) == Rules.SIDE_YOU:
			wins_you += 1
		match String(res.reason):
			"knockout": ko += 1
			"crowd": crowd += 1
			"decision": dec += 1
			"draw": draw += 1
		turns_sum += int(res.turns)
		caps_sum += int(res.captures)
		np_you += int(m.named_played.get(Rules.SIDE_YOU, 0))
		np_opp += int(m.named_played.get(Rules.SIDE_OPP, 0))
	var n := float(matches_per_cell)
	print("%-26s | %5.1f%% | %4.0f%% %5.0f%% %4.0f%% %4.0f%% | %5.1f | %4.2f | %4.2f %4.2f" % [
		label, float(wins_you) / n * 100.0,
		float(ko) / n * 100.0, float(crowd) / n * 100.0,
		float(dec) / n * 100.0, float(draw) / n * 100.0,
		float(turns_sum) / n, float(caps_sum) / n,
		float(np_you) / n, float(np_opp) / n])
