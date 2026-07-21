extends Node

## ЗАЛ — ЧАСТОТА КОМБО: сколько A3/F3 combo_events реально confirmed за N матчей на
## пару стилей. Читает тот же info.combo_events[], что уходит в живую игру/JSONL
## контроллера (rules_core.gd _settle_frame_combo_events) — просто агрегирует по симу
## вместо одного матча. Не меняет ядро/AI-политику, только считает то, что уже возвращается.
## Запуск: открыть res://duelogue/tools/sim_combo_frequency.tscn, F6.

const RulesCore := preload("res://duelogue/core/rules/rules_core.gd")
const Ai := preload("res://duelogue/core/ai/ai.gd")

@export var matches_per_pairing: int = 1500
@export var hand_size: int = 5

var _ai: RefCounted

const BASE := 1
const KOMI := 0
const STEAL := 2
const FORTIFY := 0
const CLINCH := true
const FREEZE := true
const CAPTURE_MODE := 1  # "трофей" — тот же средний режим, что в sim_runner по умолчанию
const COMP_U := 3
const COMP_T := 8
const COMP_R := 9

## def_will_clinch/atk_will_clinch у всех стилей решают ТОЛЬКО «играть/пасовать»; выбор
## exact защитной карты идёт через def_answer_index (тот же шов, что battle_controller —
## любой стиль, играя, закрывает известный маршрут осознанно, если ответ есть в руке).
## Атакующая сторона симметричного route-seeking пока не имеет: открыть LINK/дожать ARMED
## осознанно, а не структурно, стили ещё не умеют. Поэтому разница между стилями ниже —
## это structural exposure (кто как часто клинчует и в какие рамки бьёт) плюс защитное
## мастерство, но НЕ атакующее «мешер vs эксперт».
const PAIRINGS := [
	["balanced", "balanced"],
	["aggro", "aggro"],
	["smart", "smart"],
	["smart", "balanced"],
]


func _ready() -> void:
	_ai = Ai.new()
	await get_tree().process_frame
	print("\n=== ЗАЛ — ЧАСТОТА КОМБО (%d матчей/пара, захват=трофей, рука=%d) ===" % [
		matches_per_pairing, hand_size])
	for pairing in PAIRINGS:
		_run_pairing(String(pairing[0]), String(pairing[1]))
	print("\n=== КОНЕЦ ===\n")
	get_tree().quit()


func _run_pairing(style_you: String, style_opp: String) -> void:
	var matches := 0
	var clinches := 0
	var total_confirmed := 0
	var matches_with_combo := 0
	var confirmed_by_family := {}
	var confirmed_by_topology := {}
	var confirmed_by_name := {}
	for i in matches_per_pairing:
		var m := RulesCore.new()
		var first := RulesCore.SIDE_YOU if randf() < 0.5 else RulesCore.SIDE_OPP
		m.reset(first, COMP_U, COMP_T, COMP_R, hand_size, BASE, KOMI, STEAL, FORTIFY,
			CLINCH, FREEZE, CAPTURE_MODE)
		var res: Dictionary = _ai.simulate(m, style_you, style_opp)
		matches += 1
		clinches += int(res.get("clinches", 0))
		var match_has_combo := false
		for raw in res.get("combo_events", []):
			var ev: Dictionary = raw
			if String(ev.get("terminal", "")) != "confirmed":
				continue
			total_confirmed += 1
			match_has_combo = true
			var family := String(ev.get("family", ""))
			confirmed_by_family[family] = int(confirmed_by_family.get(family, 0)) + 1
			var topology := String(ev.get("topology", ""))
			confirmed_by_topology[topology] = int(confirmed_by_topology.get(topology, 0)) + 1
			var cname := String(ev.get("combo_name", ""))
			if cname != "":
				confirmed_by_name[cname] = int(confirmed_by_name.get(cname, 0)) + 1
		if match_has_combo:
			matches_with_combo += 1
	print("\n--- %s vs %s ---" % [style_you, style_opp])
	print("матчей: %d · клинчей: %d · confirmed комбо: %d" % [matches, clinches, total_confirmed])
	print("комбо/клинч: %.1f%% · матчей хотя бы с 1 комбо: %.1f%% · комбо/матч: %.2f" % [
		100.0 * float(total_confirmed) / float(maxi(1, clinches)),
		100.0 * float(matches_with_combo) / float(maxi(1, matches)),
		float(total_confirmed) / float(maxi(1, matches))])
	print("  по семейству: %s" % _fmt_counts(confirmed_by_family))
	print("  по топологии: %s" % _fmt_counts(confirmed_by_topology))
	print("  топ-8 имён: %s" % _fmt_top(confirmed_by_name, 8))


func _fmt_counts(d: Dictionary) -> String:
	var keys := d.keys()
	keys.sort_custom(func(a, b): return int(d[a]) > int(d[b]))
	var parts: Array = []
	for k in keys:
		parts.append("%s=%d" % [String(k), int(d[k])])
	return ", ".join(parts) if not parts.is_empty() else "—"


func _fmt_top(d: Dictionary, n: int) -> String:
	var keys := d.keys()
	keys.sort_custom(func(a, b): return int(d[a]) > int(d[b]))
	var parts: Array = []
	for i in mini(n, keys.size()):
		var k = keys[i]
		parts.append("%s×%d" % [String(k), int(d[k])])
	return ", ".join(parts) if not parts.is_empty() else "—"
