extends RefCounted

## Test-only механический spike для combo_a3_topologies_v0.1.
##
## Он намеренно НЕ подключён к боевому runtime: читает настоящие карты/sequence
## RulesCore и строит громоздкую fixture-only exchange-проекцию для проверки settlement.
## Это не production state: переноситься должны только проверенные recipes/invariants
## в ComboRegister, описанный в context/combo_register_architecture_v0.1.md.

const Grammar := preload("res://duelogue/core/cards/grammar.gd")

const RESULT_GUARD := "GUARD_CONFIRMED"
const RESULT_TRAP := "TRAP_SPRUNG"
const RESULT_PRESSURE := "PRESSURE_CONFIRMED"
const RESULT_ALL_BREAK := "ALL_BREAK"
const RESULT_UNRESOLVED := "UNRESOLVED"
const RESULT_NO_CLAIM := "NO_CLAIM"

const PRESSURE_EFFECTS := ["breakdown", "steal_thesis"]
const TRAP_OPENER_EFFECTS := ["breakdown", "capture"]


static func observe(opening_anchor: Dictionary, raw_sequence: Array,
		attacker: String, defender: String) -> Dictionary:
	var sequence: Array = raw_sequence.duplicate(true)
	var exchange := {
		"target_frame_ref": "",
		"target_claim_ref": "",
		"argumentative_thread_id": "",
		"defender_claim": {},
		"attacker_claim": {},
		"suppressed_claims": [],
		"rtr_state": "none",
		"window_locked": sequence.size() >= 3,
		"had_candidate": false,
		"semantic_unresolved": false,
	}
	if sequence.is_empty():
		return exchange

	var r0: Dictionary = sequence[0]
	exchange.target_frame_ref = String(r0.get("target_frame_ref", ""))
	exchange.target_claim_ref = String(r0.get("target_claim_ref", ""))
	exchange.argumentative_thread_id = String(r0.get("argumentative_thread_id", ""))
	if _watch_is_coherent(r0):
		exchange.rtr_state = "watch"

	if sequence.size() < 2:
		return exchange
	var t1: Dictionary = sequence[1]
	_observe_trt(exchange, opening_anchor, r0, t1, attacker, defender)

	if _same_thread(r0, t1):
		var prefix: String = _rtr_prefix(r0, t1)
		if prefix != "":
			exchange.rtr_state = "link"
	if sequence.size() < 3:
		return exchange

	var r2: Dictionary = sequence[2]
	var route_id := ""
	if _same_thread(r0, t1, r2):
		route_id = _rtr_route(r0, t1, r2)
	if route_id == "":
		exchange.rtr_state = "miss"
		return exchange

	exchange.had_candidate = true
	if not _rtr_semantic_ok(route_id, r0, t1, r2):
		exchange.semantic_unresolved = true
		exchange.rtr_state = "unresolved"
		return exchange

	var old_trap: Dictionary = exchange.attacker_claim
	if not old_trap.is_empty() and String(old_trap.get("topology", "")) == "trt_trap":
		old_trap = old_trap.duplicate(true)
		old_trap.state = "SUPPRESSED_UPGRADED"
		(exchange.suppressed_claims as Array).append(old_trap)
	exchange.attacker_claim = _claim(route_id, "rtr_pressure", attacker, 2,
		String(t1.get("thesis_id", "")), "")
	exchange.rtr_state = "armed"
	return exchange


static func settle(raw_exchange: Dictionary, info: Dictionary,
		surviving_thesis_ids: Array) -> Dictionary:
	var exchange: Dictionary = raw_exchange.duplicate(true)
	var defender_claim: Dictionary = exchange.get("defender_claim", {})
	var attacker_claim: Dictionary = exchange.get("attacker_claim", {})
	var live_claims: Array = []
	if not defender_claim.is_empty():
		live_claims.append(defender_claim.duplicate(true))
	if not attacker_claim.is_empty():
		live_claims.append(attacker_claim.duplicate(true))

	var out := {
		"result": RESULT_NO_CLAIM,
		"owner": "",
		"route_id": "",
		"winning_basis_subclaim_ref": "",
		"payoff_count": 0,
		"claims": [],
		"suppressed_claims": exchange.get("suppressed_claims", []).duplicate(true),
		"exchange": exchange,
	}
	if live_claims.is_empty():
		if bool(exchange.get("semantic_unresolved", false)):
			out.result = RESULT_UNRESOLVED
		elif bool(exchange.get("had_candidate", false)):
			out.result = RESULT_UNRESOLVED
		return out

	var attacker: String = String(info.get("side", ""))
	var attacker_won: bool = int(info.get("clinch_r", 0)) > int(info.get("clinch_t", 0))
	var winner: String = attacker if attacker_won else _other_owner(live_claims, attacker)
	var winning_claim: Dictionary = attacker_claim if attacker_won else defender_claim
	var winning_valid := not winning_claim.is_empty() and \
		_claim_valid(winning_claim, info, surviving_thesis_ids)

	var resolved_claims: Array = []
	for raw in live_claims:
		var claim: Dictionary = raw.duplicate(true)
		claim["result"] = "confirmed" if winning_valid and \
			String(claim.get("owner", "")) == String(winning_claim.get("owner", "")) and \
			String(claim.get("route_id", "")) == String(winning_claim.get("route_id", "")) \
			else "break"
		resolved_claims.append(claim)
	out.claims = resolved_claims

	if not winning_valid:
		out.result = RESULT_ALL_BREAK
		return out

	out.owner = winner
	out.route_id = String(winning_claim.get("route_id", ""))
	out.winning_basis_subclaim_ref = String(winning_claim.get("basis_subclaim_ref", ""))
	out.payoff_count = 1
	match String(winning_claim.get("topology", "")):
		"trt_guard":
			out.result = RESULT_GUARD
		"trt_trap":
			out.result = RESULT_TRAP
		"rtr_pressure":
			out.result = RESULT_PRESSURE
	return out


static func _observe_trt(exchange: Dictionary, opening_anchor: Dictionary,
		r0: Dictionary, t1: Dictionary, attacker: String, defender: String) -> void:
	var anchor_card: Dictionary = opening_anchor.get("card", {})
	if anchor_card.is_empty() or not Grammar.triple(anchor_card, r0, t1):
		return
	exchange.had_candidate = true
	var verdict: String = String(t1.get("semantic_verdict", "UNRESOLVED"))
	var guard_route: String = String(t1.get("a3_guard_route_id", ""))
	var trap_route: String = String(t1.get("a3_trap_route_id", ""))
	var guard_basis: String = String(t1.get("a3_guard_basis_subclaim_ref", ""))
	var trap_basis: String = String(t1.get("a3_trap_basis_subclaim_ref", ""))
	var target_claim: String = String(exchange.get("target_claim_ref", ""))

	match verdict:
		"DEFENDED":
			if _trt_guard_semantic_ok(guard_route, t1, target_claim):
				exchange.defender_claim = _claim(guard_route, "trt_guard", defender, 1,
					String(t1.get("thesis_id", "")), guard_basis)
			else:
				exchange.semantic_unresolved = true
		"SPRUNG":
			if _trt_trap_semantic_ok(trap_route, t1, target_claim):
				exchange.attacker_claim = _claim(trap_route, "trt_trap", attacker, 1,
					String(t1.get("thesis_id", "")), trap_basis)
			else:
				exchange.semantic_unresolved = true
		"CONTESTED":
			var guard_ok := _trt_guard_semantic_ok(guard_route, t1, target_claim)
			var trap_ok := _trt_trap_semantic_ok(trap_route, t1, target_claim)
			if guard_ok and trap_ok and guard_basis != "" and trap_basis != "" and \
					guard_basis != trap_basis:
				exchange.defender_claim = _claim(guard_route, "trt_guard", defender, 1,
					String(t1.get("thesis_id", "")), guard_basis)
				exchange.attacker_claim = _claim(trap_route, "trt_trap", attacker, 1,
					String(t1.get("thesis_id", "")), trap_basis)
			else:
				exchange.semantic_unresolved = true
		_:
			exchange.semantic_unresolved = true


static func _claim(route_id: String, topology: String, owner: String, closer_step: int,
		closer_thesis_id: String, basis_subclaim_ref: String) -> Dictionary:
	return {
		"route_id": route_id,
		"topology": topology,
		"owner": owner,
		"state": "armed",
		"trigger_steps": [0, 1] if topology != "rtr_pressure" else [0, 1, 2],
		"closer_step": closer_step,
		"closer_thesis_id": closer_thesis_id,
		"basis_subclaim_ref": basis_subclaim_ref,
		"allowed_effects": TRAP_OPENER_EFFECTS.duplicate() if topology == "trt_trap" \
			else PRESSURE_EFFECTS.duplicate() if topology == "rtr_pressure" else [],
	}


static func _watch_is_coherent(r0: Dictionary) -> bool:
	return Grammar.hook_of(r0) != "" and String(r0.get("target_frame_ref", "")) != "" and \
		String(r0.get("target_claim_ref", "")) != "" and \
		String(r0.get("argumentative_thread_id", "")) != ""


static func _same_thread(r0: Dictionary, t1: Dictionary, r2: Dictionary = {}) -> bool:
	var thread: String = String(r0.get("argumentative_thread_id", ""))
	var claim_ref: String = String(r0.get("target_claim_ref", ""))
	if not _watch_is_coherent(r0) or String(t1.get("argumentative_thread_id", "")) != thread \
			or int(t1.get("answers_step", -1)) != 0 or \
			String(t1.get("supports_claim_ref", "")) != claim_ref:
		return false
	if r2.is_empty():
		return true
	return String(r2.get("argumentative_thread_id", "")) == thread and \
		int(r2.get("target_step", -1)) == 1


static func _rtr_prefix(r0: Dictionary, t1: Dictionary) -> String:
	var hook0 := Grammar.hook_of(r0)
	var scheme1 := String(t1.get("scheme", ""))
	if hook0 == "источник" and scheme1 == "Авторитет":
		return "P-01"
	if hook0 == "источник" and scheme1 == "Статистика":
		return "P-06"
	return ""


static func _rtr_route(r0: Dictionary, t1: Dictionary, r2: Dictionary) -> String:
	var prefix := _rtr_prefix(r0, t1)
	var hook2 := Grammar.hook_of(r2)
	if prefix == "P-01" and hook2 == "уместность":
		return "P-01"
	if prefix == "P-06" and hook2 == "связь":
		return "P-06"
	return ""


static func _rtr_semantic_ok(route_id: String, r0: Dictionary, t1: Dictionary,
		r2: Dictionary) -> bool:
	var target_claim: String = String(r0.get("target_claim_ref", ""))
	match route_id:
		"P-01":
			return String(t1.get("authority_subtype", "")) == "expert" and \
				not bool(t1.get("domain_covers_claim", true)) and \
				String(r2.get("challenge_role", "")) == "domain_relevance"
		"P-06":
			return int(t1.get("supplies_source_for_step", -1)) == 0 and \
				String(t1.get("dataset_ref", "")) != "" and \
				String(t1.get("method_ref", "")) != "" and \
				String(t1.get("evidence_role", "")) == "causal" and \
				String(t1.get("causal_claim_ref", "")) == target_claim and \
				String(r2.get("challenge_role", "")) == "correlation_to_cause"
	return false


static func _trt_guard_semantic_ok(route_id: String, t1: Dictionary,
		target_claim: String) -> bool:
	if String(t1.get("supports_claim_ref", "")) != target_claim:
		return false
	match route_id:
		"source_backed":
			return bool(t1.get("independent_support", false))
		"shared_core":
			var basis := _semantic_basis(t1,
				String(t1.get("a3_guard_basis_subclaim_ref", "")))
			return String(basis.get("role", "")) == "shared_core" and \
				bool(basis.get("relevant_to_claim", false)) and \
				(bool(basis.get("predeclared", false)) or \
				bool(basis.get("independently_grounded", false)))
	return false


static func _trt_trap_semantic_ok(route_id: String, t1: Dictionary,
		target_claim: String) -> bool:
	if String(t1.get("supports_claim_ref", "")) != target_claim:
		return false
	match route_id:
		"false_independence":
			return bool(t1.get("claimed_independent", false)) and \
				not bool(t1.get("independent_support", true))
		"redrawn_similarity":
			var basis := _semantic_basis(t1,
				String(t1.get("a3_trap_basis_subclaim_ref", "")))
			return String(basis.get("role", "")) == "scope_qualifier" and \
				bool(basis.get("post_hoc", false)) and \
				not bool(basis.get("independently_grounded", true)) and \
				not bool(basis.get("relevant_to_claim", true))
	return false


static func _semantic_basis(t1: Dictionary, basis_id: String) -> Dictionary:
	for raw in t1.get("semantic_bases", []):
		var basis: Dictionary = raw
		if String(basis.get("id", "")) == basis_id:
			return basis
	return {}


static func _claim_valid(claim: Dictionary, info: Dictionary,
		surviving_thesis_ids: Array) -> bool:
	var sequence: Array = info.get("resolved_sequence", [])
	if sequence.size() < 2:
		return false
	var t1: Dictionary = sequence[1]
	match String(claim.get("topology", "")):
		"trt_guard":
			return String(t1.get("result", "")) == "held" and \
				surviving_thesis_ids.has(String(claim.get("closer_thesis_id", "")))
		"trt_trap":
			if sequence.size() < 3 or not (String(t1.get("result", "")) in ["removed", "stolen"]):
				return false
			var r0: Dictionary = sequence[0]
			var opener_ok: bool = String(r0.get("result", "")) in ["landed", "captured"] and \
				String(r0.get("effect", "")) in (claim.get("allowed_effects", []) as Array)
			var basis_ref: String = String(claim.get("basis_subclaim_ref", ""))
			if basis_ref != "":
				return opener_ok and \
					String((sequence[2] as Dictionary).get("targets_subclaim_ref", "")) == basis_ref
			return opener_ok
		"rtr_pressure":
			if sequence.size() < 3:
				return false
			var r2: Dictionary = sequence[2]
			return String(r2.get("result", "")) == "landed" and \
				int(r2.get("target_step", -1)) == 1 and \
				String(r2.get("affected_thesis_id", "")) == String(t1.get("thesis_id", "")) and \
				String(r2.get("effect", "")) in (claim.get("allowed_effects", []) as Array)
	return false


static func _other_owner(claims: Array, attacker: String) -> String:
	for raw in claims:
		var owner: String = String((raw as Dictionary).get("owner", ""))
		if owner != "" and owner != attacker:
			return owner
	return ""
