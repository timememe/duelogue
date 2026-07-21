extends Node

## ИЗОЛИРОВАННЫЙ эксперимент — 3 архетипа комбо-развязки (не риторика, чистая механика):
##   pure_guard — единственная схема ответа, owner всегда B, confirm без winner/outcome:
##                как только $reply легла, ставка решена.
##   pure_trap  — единственная (заведомо не канон-ответ) схема ответа, owner всегда A,
##                confirm тоже без winner/outcome — не нужен третий ход, чтобы "поймать".
##   fork       — ОДИН и тот же $ask, но $reply-схема ветвит: одна схема → GUARD-ветка,
##                другая → TRAP-ветка. Обе confirm сразу на своём match, без гонки survival.
## Ничего из этого не трогает боевые 20 маршрутов: recipe'ы живут только здесь и подсаживаются
## через combo_register.extra_a3_catalog (см. combo_register.gd) на отдельном arbitration-канале
## "test_archetypes" — легаси G-01 и боевые A3-recipe по тем же setup+hook продолжают
## работать параллельно и не мешают счёту (сравниваем только свои pattern_id).
## Запуск: res://duelogue/tools/combo_archetype_probe.tscn, F6.

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
const CAPTURE_MODE := 1
const COMP_U := 3
const COMP_T := 8
const COMP_R := 9

const PAIRINGS := [
	["balanced", "balanced"],
	["aggro", "aggro"],
	["smart", "smart"],
	["smart", "balanced"],
]

## --- Архетип 1: pure GUARD (переиспользует реальные "guard-only" тройки грамматики) ---
const P_TEST_G1 := {
	"id": "test_g1_exception_noted", "version": 1, "family": "TEST", "topology": "pure_guard",
	"combo_name": "Тест-Гард: Исключение учтено", "scope": "action",
	"arbitration": {"channel": "test_archetypes", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Аналогия"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "исключение"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Авторитет"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": []},
}
const P_TEST_G2 := {
	"id": "test_g2_about_people", "version": 1, "family": "TEST", "topology": "pure_guard",
	"combo_name": "Тест-Гард: Это касается людей", "scope": "action",
	"arbitration": {"channel": "test_archetypes", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Эмоция"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "уместность"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Пример"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": []},
}

## --- Архетип 2: pure TRAP (та же setup+hook, что у реальных маршрутов, но $reply —
## заведомо НЕ канонический ответ ANSWER_OF; легаси G-01 на неё не вооружается,
## это чисто тестовая "правдоподобная, но пустая" реплика). ---
const P_TEST_T1 := {
	"id": "test_t1_source_offtrack", "version": 1, "family": "TEST", "topology": "pure_trap",
	"combo_name": "Тест-Трап: мимо источника", "scope": "action",
	"arbitration": {"channel": "test_archetypes", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Авторитет"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "источник"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Здравый смысл"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": []},
}
const P_TEST_T2 := {
	"id": "test_t2_tradition_offtrack", "version": 1, "family": "TEST", "topology": "pure_trap",
	"combo_name": "Тест-Трап: мимо границ", "scope": "action",
	"arbitration": {"channel": "test_archetypes", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Традиция"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "следствие"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Эмоция"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": []},
}

## --- Архетип 3: fork (переиспользует реальные dual-scheme записи ANSWER_OF: один и тот же
## $ask, ветвление по exact схеме $reply — не гонка за survival одной и той же карты). ---
const P_TEST_F1_GUARD := {
	"id": "test_f1_guard", "version": 1, "family": "TEST", "topology": "fork_guard",
	"combo_name": "Тест-Вилка1: механизм", "scope": "action",
	"arbitration": {"channel": "test_archetypes", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Статистика"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "связь"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Пример"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": []},
}
const P_TEST_F1_TRAP := {
	"id": "test_f1_trap", "version": 1, "family": "TEST", "topology": "fork_trap",
	"combo_name": "Тест-Вилка1: только иллюстрация", "scope": "action",
	"arbitration": {"channel": "test_archetypes", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Статистика"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "связь"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Аналогия"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": []},
}
const P_TEST_F2_GUARD := {
	"id": "test_f2_guard", "version": 1, "family": "TEST", "topology": "fork_guard",
	"combo_name": "Тест-Вилка2: по аналогии", "scope": "action",
	"arbitration": {"channel": "test_archetypes", "tier": 3, "priority": 30},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Здравый смысл"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "следствие"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Аналогия"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "B", "confirm": []},
}
const P_TEST_F2_TRAP := {
	"id": "test_f2_trap", "version": 1, "family": "TEST", "topology": "fork_trap",
	"combo_name": "Тест-Вилка2: просто здравый смысл", "scope": "action",
	"arbitration": {"channel": "test_archetypes", "tier": 2, "priority": 10},
	"seed": {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": "Здравый смысл"}}},
	"path": [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": "следствие"},
			"selector": "first"},
		{"slot": "$reply", "role": "B", "card": {"type": "T", "scheme": "Здравый смысл"},
			"selector": "next"},
	],
	"where": [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	],
	"claim": {"owner": "A", "confirm": []},
}

const TEST_CATALOG := [
	P_TEST_G1, P_TEST_G2, P_TEST_T1, P_TEST_T2,
	P_TEST_F1_GUARD, P_TEST_F1_TRAP, P_TEST_F2_GUARD, P_TEST_F2_TRAP,
]

## pattern_id → archetype-бакет для агрегации.
const ARCHETYPE_OF := {
	"test_g1_exception_noted": "pure_guard", "test_g2_about_people": "pure_guard",
	"test_t1_source_offtrack": "pure_trap", "test_t2_tradition_offtrack": "pure_trap",
	"test_f1_guard": "fork_guard", "test_f1_trap": "fork_trap",
	"test_f2_guard": "fork_guard", "test_f2_trap": "fork_trap",
}


func _ready() -> void:
	_ai = Ai.new()
	await get_tree().process_frame
	print("\n=== АРХЕТИПЫ КОМБО — ИЗОЛИРОВАННЫЙ ПИЛОТ (%d матчей/пара) ===" % matches_per_pairing)
	for pairing in PAIRINGS:
		_run_pairing(String(pairing[0]), String(pairing[1]))
	print("\n=== КОНЕЦ ===\n")
	get_tree().quit()


func _run_pairing(style_you: String, style_opp: String) -> void:
	var matches := 0
	var clinches := 0
	var by_archetype_terminal := {}
	var by_pattern_confirmed := {}
	for i in matches_per_pairing:
		var m := RulesCore.new()
		var first := RulesCore.SIDE_YOU if randf() < 0.5 else RulesCore.SIDE_OPP
		m.reset(first, COMP_U, COMP_T, COMP_R, hand_size, BASE, KOMI, STEAL, FORTIFY,
			CLINCH, FREEZE, CAPTURE_MODE)
		m.combo_register.extra_a3_catalog = TEST_CATALOG
		var res: Dictionary = _ai.simulate(m, style_you, style_opp)
		matches += 1
		clinches += int(res.get("clinches", 0))
		for raw in res.get("combo_events", []):
			var ev: Dictionary = raw
			var pid := String(ev.get("pattern_id", ""))
			if not ARCHETYPE_OF.has(pid):
				continue
			var archetype := String(ARCHETYPE_OF[pid])
			var terminal := String(ev.get("terminal", "?"))
			var key := "%s/%s" % [archetype, terminal]
			by_archetype_terminal[key] = int(by_archetype_terminal.get(key, 0)) + 1
			if terminal == "confirmed":
				by_pattern_confirmed[pid] = int(by_pattern_confirmed.get(pid, 0)) + 1
	print("\n--- %s vs %s ---" % [style_you, style_opp])
	print("матчей: %d · клинчей: %d" % [matches, clinches])
	print("  по архетипу/terminal: %s" % _fmt_counts(by_archetype_terminal))
	print("  confirmed по pattern_id: %s" % _fmt_counts(by_pattern_confirmed))


func _fmt_counts(d: Dictionary) -> String:
	var keys := d.keys()
	keys.sort_custom(func(a, b): return int(d[a]) > int(d[b]))
	var parts: Array = []
	for k in keys:
		parts.append("%s=%d" % [String(k), int(d[k])])
	return ", ".join(parts) if not parts.is_empty() else "—"
