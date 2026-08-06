extends RefCounted

## DUELOGUE — GENERIC PATTERN BUILDER (feasibility-прототип, план см.
## .claude/plans/snappy-foraging-papert.md): строит GUARD/TRAP-паттерны register-формата
## (combo_register.gd) параметрически из route-данных (setup_scheme/hook/answer_scheme,
## те же поля, что несёт ANSWER_OF в grammar.gd), а не как руками написанные константы.
## Доказательство, что форма общая: P_DOMAIN_MATCH_GUARD/TRAP и
## P_MECHANISM_SHOWN(_ANALOGY)_GUARD/TRAP (combo_register.gd) отличаются от соседей по
## тому же route_id только setup_scheme/hook/answer_scheme/combo_name/owner/confirm —
## seed/path/where и arbitration по роли фиксированы.
##
## Чистые функции без побочных эффектов. Не подключено к A3_CATALOG/RESERVED_A3_CATALOG
## и не трогает боевой runtime — сверяется отдельным
## duelogue/tools/combo_pattern_builder_probe.gd.

const GUARD_ARBITRATION := {"channel": "clinch", "tier": 3, "priority": 30}
const TRAP_ARBITRATION := {"channel": "clinch", "tier": 2, "priority": 10}


## specificity="exact" — $reply обязан нести answer_scheme (текущее поведение всех именных
## паттернов). specificity="any" — scheme со слота снимается вовсе, годится любой Тезис
## (та же идея, что мы применили к G-01 через удаление grammar_answers, здесь — параметр).
static func _reply_card(answer_scheme: String, specificity: String) -> Dictionary:
	if specificity == "any":
		return {"type": "T"}
	return {"type": "T", "scheme": answer_scheme}


static func _seed(setup_scheme: String) -> Dictionary:
	return {"$setup": {"lane": "board", "selector": "context.top_thesis",
		"card": {"type": "T", "scheme": setup_scheme}}}


static func _path(hook: String, reply_card: Dictionary) -> Array:
	return [
		{"slot": "$ask", "role": "A", "card": {"type": "R", "hook": hook}, "selector": "first"},
		{"slot": "$reply", "role": "B", "card": reply_card, "selector": "next"},
	]


static func _where() -> Array:
	return [
		{"kind": "targets", "from": "$ask", "to": "$setup"},
		{"kind": "responds_to", "from": "$reply", "to": "$ask"},
		{"kind": "bind", "slot": "$reply_thesis", "rel": "materializes_as", "from": "$reply"},
	]


## GUARD: owner B. Confirm — защитник выиграл клинч, а exact ответ удержался на доске.
static func build_guard(id: String, setup_scheme: String, hook: String, answer_scheme: String,
		combo_name: String, specificity: String = "exact") -> Dictionary:
	return {
		"id": id, "version": 1, "family": "A3", "topology": "trt_guard",
		"combo_name": combo_name, "scope": "action",
		"arbitration": GUARD_ARBITRATION.duplicate(true),
		"seed": _seed(setup_scheme),
		"path": _path(hook, _reply_card(answer_scheme, specificity)),
		"where": _where(),
		"claim": {"owner": "B", "confirm": [
			{"kind": "winner", "role": "B"},
			{"kind": "outcome_in", "slot": "$reply", "results": ["held"]},
			{"kind": "board_contains", "bind": "$reply_thesis"},
		]},
	}


## TRAP: owner A. Confirm — атакующий выиграл клинч, а textbook-ответ защитника не устоял
## (снят/украден) при том что открывающая атака сама прошла.
static func build_trap(id: String, setup_scheme: String, hook: String, answer_scheme: String,
		combo_name: String, specificity: String = "exact") -> Dictionary:
	return {
		"id": id, "version": 1, "family": "A3", "topology": "trt_trap",
		"combo_name": combo_name, "scope": "action",
		"arbitration": TRAP_ARBITRATION.duplicate(true),
		"seed": _seed(setup_scheme),
		"path": _path(hook, _reply_card(answer_scheme, specificity)),
		"where": _where(),
		"claim": {"owner": "A", "confirm": [
			{"kind": "winner", "role": "A"},
			{"kind": "outcome_in", "slot": "$reply", "results": ["removed", "stolen"]},
			{"kind": "outcome_in", "slot": "$ask", "results": ["landed", "captured"]},
			{"kind": "effect_in", "slot": "$ask", "effects": ["breakdown", "capture"]},
		]},
	}
