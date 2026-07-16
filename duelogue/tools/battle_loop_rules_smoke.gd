extends Node

## Детерминированный контракт нового боевого лупа. Здесь нет AI/UI: тест фиксирует
## порядок мутаций, который особенно легко сломать рефиллом или сменой презентации.
## Запуск:
##   Godot --headless --path . res://duelogue/tools/battle_loop_rules_smoke.tscn

const RulesCore := preload("res://duelogue/core/rules/rules_core.gd")
const Deck := preload("res://duelogue/core/cards/deck.gd")
const AiCore := preload("res://duelogue/core/ai/ai.gd")
const NamedCards := preload("res://duelogue/core/cards/named_cards.gd")

const H := 5
const U := 3
const T := 8
const R := 9

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("\n=== BATTLE LOOP RULES SMOKE ===")
	_check_opening_reserve()
	_check_ko_snapshot_before_refill()
	_check_forced_redeploy()
	_check_wobble_reach()
	_check_wobble_capture_matrix()
	_check_thick_defense_paths()
	_check_protected_thickness_and_full_loot()
	_check_capture_active_invariant()
	_check_middle_stolen_identity()
	_check_plain_unwind()
	_check_socratic_object_target()
	_check_named_clinch_legality()
	_check_named_capture_object_fields()
	_check_ai_target_awareness()
	_check_clinch_context_snapshot()
	_check_stall_reasons()
	print("=== BATTLE LOOP RULES: %s ===\n" % ("OK" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)


func _fresh(board_ko: bool = true) -> RefCounted:
	var model := RulesCore.new()
	model.reset(RulesCore.SIDE_YOU, U, T, R, H, 1, 0, 2, 0, true, true,
		1, 2, 4, 0, 1, 0, 1, board_ko)
	return model


func _line(theses: int, name: String = "Тестовая рамка") -> Dictionary:
	return {"theses": theses, "closed": false, "name": name, "stolen": 0}


func _object_line(theses: int, name: String, prefix: String) -> Dictionary:
	var stack: Array = []
	var statements: Array = []
	for i in theses:
		var thesis_id := "%s_%d" % [prefix, i]
		stack.append({"type": RulesCore.TYPE_TEZIS, "name": "T%d" % i,
			"thesis_id": thesis_id, "stolen": false, "marker": "%s-m%d" % [prefix, i]})
		statements.append({"thesis_id": thesis_id, "text": "statement %d" % i})
	return {
		"theses": theses, "closed": false, "name": name, "stolen": 0,
		"claim_id": prefix, "claim": "claim %s" % prefix,
		"thesis_stack": stack, "statements": statements,
	}


func _stack_ids(line: Dictionary) -> Array:
	var ids: Array = []
	for raw in line.get("thesis_stack", []):
		ids.append(String((raw as Dictionary).get("thesis_id", "")))
	return ids


func _card(type: String, name: String, steals: bool = false) -> Dictionary:
	return {"type": type, "name": name, "steals": steals}


func _card_counts(side: Dictionary) -> Dictionary:
	var out := {
		RulesCore.TYPE_USTANOVKA: 0,
		RulesCore.TYPE_TEZIS: 0,
		RulesCore.TYPE_RAZBOR: 0,
	}
	for zone in ["hand", "draw"]:
		for raw in side.get(zone, []):
			var type := String((raw as Dictionary).get("type", ""))
			out[type] = int(out.get(type, 0)) + 1
	return out


func _count_hand_type(side: Dictionary, type: String) -> int:
	var n := 0
	for card in side.hand:
		if String(card.get("type", "")) == type:
			n += 1
	return n


func _discard_card(side: Dictionary, name: String) -> Dictionary:
	for raw in side.discard:
		var card: Dictionary = raw
		if String(card.get("name", "")) == name:
			return card
	return {}


func _discard_has_thesis_id(side: Dictionary, thesis_id: String) -> bool:
	for raw in side.discard:
		if String((raw as Dictionary).get("thesis_id", "")) == thesis_id:
			return true
	return false


func _resolved_effect(info: Dictionary, step: int) -> Dictionary:
	for raw in info.get("resolved_effects", []):
		var effect: Dictionary = raw
		if int(effect.get("step", -1)) == step:
			return effect
	return {}


func _check_middle_stolen_identity() -> void:
	var model := _fresh(true)
	model.sides[RulesCore.SIDE_YOU].lines = [_line(1, "Attacker")]
	model.sides[RulesCore.SIDE_OPP].lines = [{
		"theses": 3,
		"closed": false,
		"name": "Object stack",
		"stolen": 1,
		"thesis_stack": [
			{"type": RulesCore.TYPE_TEZIS, "name": "Base", "thesis_id": "base",
				"stolen": false},
			{"type": RulesCore.TYPE_TEZIS, "name": "Stolen", "thesis_id": "stolen-middle",
				"stolen": true},
			{"type": RulesCore.TYPE_TEZIS, "name": "Normal", "thesis_id": "normal-top",
				"stolen": false},
		],
	}]
	model.sides[RulesCore.SIDE_YOU].hand = [
		_card(RulesCore.TYPE_RAZBOR, "Exact top R")]
	model.sides[RulesCore.SIDE_YOU].draw = []
	model.sides[RulesCore.SIDE_OPP].hand = []
	model.sides[RulesCore.SIDE_OPP].draw = []
	model.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, false, 0)
	var info: Dictionary = model.clinch_submit("pass").get("info", {})
	var remaining: Array = model.sides[RulesCore.SIDE_OPP].lines[0].thesis_stack
	_check(String(info.get("affected_thesis_id", "")) == "normal-top" and
		remaining.size() == 2 and
		String((remaining[1] as Dictionary).get("thesis_id", "")) == "stolen-middle" and
		bool((remaining[1] as Dictionary).get("stolen", false)) and
		int(model.sides[RulesCore.SIDE_OPP].lines[0].stolen) == 1,
		"plain R removes the exact normal top object and leaves stolen-middle intact")


func _opening_marker_ok(side: Dictionary) -> bool:
	var marked := 0
	for card in side.hand:
		if bool(card.get("opening_reserve", false)):
			marked += 1
			if String(card.get("type", "")) != RulesCore.TYPE_USTANOVKA:
				return false
	return marked == 1


func _check_opening_reserve() -> void:
	var all_seeds_ok := true
	for i in 64:
		seed(0xD0E109 + i * 104729)
		var model := _fresh()
		for side in [RulesCore.SIDE_YOU, RulesCore.SIDE_OPP]:
			var before := _card_counts(model.sides[side])
			Deck.prepare_opening_reserve(model.sides[side], H)
			var s: Dictionary = model.sides[side]
			all_seeds_ok = all_seeds_ok and s.hand.size() == H \
				and _count_hand_type(s, RulesCore.TYPE_USTANOVKA) == 1 \
				and _opening_marker_ok(s) \
				and int(model.reserve_count(side)) == 1 \
				and _card_counts(s) == before
	_check(all_seeds_ok,
		"opening на 64 seed: H5 = 1 публичный резерв U + 4 действия, состав колоды сохранён")


func _check_ko_snapshot_before_refill() -> void:
	var model := _fresh(true)
	model.sides[RulesCore.SIDE_YOU].lines = [_line(1, "Атака")]
	model.sides[RulesCore.SIDE_OPP].lines = [_line(1, "Последняя")]
	model.sides[RulesCore.SIDE_YOU].hand = [_card(RulesCore.TYPE_RAZBOR, "Последний удар")]
	model.sides[RulesCore.SIDE_YOU].draw = []
	model.sides[RulesCore.SIDE_OPP].hand = [_card(RulesCore.TYPE_TEZIS, "Не страховка")]
	# Эта Установка гарантированно войдёт в руку при refill, но уже ПОСЛЕ снимка KO.
	model.sides[RulesCore.SIDE_OPP].draw = [_card(RulesCore.TYPE_USTANOVKA, "Поздний топдек")]
	model.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, false, 0)
	var resolved: Dictionary = model.clinch_submit("pass")
	var info: Dictionary = resolved.get("info", {})
	_check(bool(info.get("last_frame_lost", false)) and
		not bool(info.get("recovery_available", true)) and bool(info.get("knockout", false)),
		"падение последней рамки сообщает снимок: восстановления не было, KO наступил")
	_check(model.game_over and model.winner == RulesCore.SIDE_YOU and
		model.end_reason == "knockout" and not model.recovery_pending(RulesCore.SIDE_OPP),
		"Установка из последующего refill не отменяет уже зафиксированный нокаут")
	_check(_count_hand_type(model.sides[RulesCore.SIDE_OPP], RulesCore.TYPE_USTANOVKA) == 1 and
		model.recovery_indices(RulesCore.SIDE_OPP).is_empty(),
		"поздняя Установка может физически добраться, но не помечается recovery_ready")


func _check_forced_redeploy() -> void:
	var model := _fresh(true)
	var saved_axiom := _card(RulesCore.TYPE_USTANOVKA, "Аксиома в резерве")
	saved_axiom.merge({
		"named": "axiom", "recovery_ready": false,
		"claim_id": "saved_axiom", "claim": "аварийная рамка остаётся обычной",
		"preferred_axes": ["logic"],
	})
	model.sides[RulesCore.SIDE_YOU].lines = [_line(1, "Атака")]
	model.sides[RulesCore.SIDE_OPP].lines = [_line(1, "Последняя")]
	model.sides[RulesCore.SIDE_YOU].hand = [_card(RulesCore.TYPE_RAZBOR, "Последний удар")]
	model.sides[RulesCore.SIDE_YOU].draw = []
	model.sides[RulesCore.SIDE_OPP].hand = [
		saved_axiom,
		_card(RulesCore.TYPE_TEZIS, "Действие"),
	]
	model.sides[RulesCore.SIDE_OPP].draw = [
		_card(RulesCore.TYPE_TEZIS, "Добор 1"),
		_card(RulesCore.TYPE_TEZIS, "Добор 2"),
		_card(RulesCore.TYPE_TEZIS, "Добор 3"),
		_card(RulesCore.TYPE_USTANOVKA, "Поздняя рамка"),
	]
	model.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, false, 0)
	var resolved: Dictionary = model.clinch_submit("pass")
	var loss: Dictionary = resolved.get("info", {})
	_check(not model.game_over and bool(loss.get("recovery_available", false)) and
		model.recovery_pending(RulesCore.SIDE_OPP) and
		model.recovery_indices(RulesCore.SIDE_OPP).size() == 1,
		"только Установка, уже бывшая в руке при падении, становится восстановлением")
	_check(model.begin_turn(RulesCore.SIDE_OPP) == "reframe" and
		model.sides[RulesCore.SIDE_OPP].lines.is_empty(),
		"начало следующего хода требует явного выбора рамки, не разворачивает её автоматически")
	var late_index := -1
	var recovery_hand: Array = model.sides[RulesCore.SIDE_OPP].hand
	for i in recovery_hand.size():
		if String(recovery_hand[i].get("type", "")) == RulesCore.TYPE_USTANOVKA and \
				not bool(recovery_hand[i].get("recovery_ready", false)):
			late_index = i
			break
	var rejected_turn := int(model.turn_count)
	var rejected: Dictionary = model.play_redeploy(RulesCore.SIDE_OPP, late_index)
	_check(late_index >= 0 and rejected.is_empty() and
		model.turn_count == rejected_turn and model.recovery_pending(RulesCore.SIDE_OPP) and
		model.sides[RulesCore.SIDE_OPP].lines.is_empty(),
		"Установка, пришедшая после снимка с refill, видна в руке, но не разрешена для reframe")
	var idx := int(model.recovery_indices(RulesCore.SIDE_OPP)[0])
	var turn_before := int(model.turn_count)
	var redeploy: Dictionary = model.play_redeploy(RulesCore.SIDE_OPP, idx)
	_check(not redeploy.is_empty() and model.sides[RulesCore.SIDE_OPP].lines.size() == 1 and
		int(model.sides[RulesCore.SIDE_OPP].lines[0].theses) == 1 and
		not bool(model.sides[RulesCore.SIDE_OPP].lines[0].get("no_defend", false)) and
		String(model.sides[RulesCore.SIDE_OPP].lines[0].get("claim_id", "")) == "saved_axiom" and
		String(redeploy.get("named_suppressed", "")) == "axiom",
		"reframe сохраняет смысл U, но подавляет твист Аксиомы: обычная рамка с одним тезисом")
	_check(model.turn_count == turn_before + 1 and
		not model.recovery_pending(RulesCore.SIDE_OPP) and
		model.recovery_indices(RulesCore.SIDE_OPP).is_empty() and
		model.sides[RulesCore.SIDE_OPP].hand.size() == H,
		"восстановление тратит полный ход и лишь затем добирает руку до H5")


func _check_wobble_reach() -> void:
	var model := _fresh(true)
	var you_reach: Array = []
	for lean in [0, -1, -2, -3, -4, -5]:
		model.set_external_zal(lean, true)
		you_reach.append(model.capture_threshold(RulesCore.SIDE_YOU))
	_check(you_reach == [1, 1, 2, 3, 4, 4],
		"public Lean toward the frame owner maps 0–1/2/3/4+ to reach 1/2/3/4")

	var opp_reach: Array = []
	for lean in [0, 1, 2, 3, 4, 5]:
		model.set_external_zal(lean, true)
		opp_reach.append(model.capture_threshold(RulesCore.SIDE_OPP))
	_check(opp_reach == you_reach,
		"audience-only wobble is exactly symmetric for both frame owners")

	model.sides[RulesCore.SIDE_YOU].lines = [_line(1), _line(1), _line(1)]
	model.sides[RulesCore.SIDE_OPP].lines = [_line(4)]
	model.set_external_zal(-3, true)
	var leader_reach := int(model.capture_threshold(RulesCore.SIDE_YOU))
	model.zal_bias = -1
	var biased_reach := int(model.capture_threshold(RulesCore.SIDE_YOU))
	_check(leader_reach == 3 and biased_reach == 4,
		"board lead does not hide public reach; visible zal_bias participates in the same Lean")


func _prime_reach_four(model: RefCounted) -> void:
	model.sides[RulesCore.SIDE_YOU].lines = [_line(1, "Андердог")]
	model.sides[RulesCore.SIDE_OPP].lines = [_line(4, "Фаворит")]
	model.set_external_zal(-4, true)


func _check_wobble_capture_matrix() -> void:
	for thickness in [2, 3, 4]:
		var model := _fresh(true)
		var target := _object_line(thickness, "Favourite %d" % thickness,
			"capture_%d" % thickness)
		var expected_ids := _stack_ids(target)
		model.sides[RulesCore.SIDE_YOU].lines = [_line(1, "Original active")]
		model.sides[RulesCore.SIDE_OPP].lines = [target]
		model.set_external_zal(-thickness, true)
		model.sides[RulesCore.SIDE_YOU].hand = [
			_card(RulesCore.TYPE_RAZBOR, "Direct K%d" % thickness, true)]
		model.sides[RulesCore.SIDE_YOU].draw = []
		model.sides[RulesCore.SIDE_OPP].hand = [
			_card(RulesCore.TYPE_USTANOVKA, "Recovery")]
		model.sides[RulesCore.SIDE_OPP].draw = []
		model.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, true, 0)
		var info: Dictionary = model.clinch_submit("pass").get("info", {})
		var trophy: Dictionary = model.sides[RulesCore.SIDE_YOU].lines[0]
		var all_stolen := true
		var metadata_kept := true
		for i in (trophy.thesis_stack as Array).size():
			var token: Dictionary = trophy.thesis_stack[i]
			all_stolen = all_stolen and bool(token.get("stolen", false))
			metadata_kept = metadata_kept and String(token.get("marker", "")) == \
				"capture_%d-m%d" % [thickness, i]
		var discard_has_captured_id := false
		for raw in model.sides[RulesCore.SIDE_OPP].discard:
			if String((raw as Dictionary).get("thesis_id", "")) in expected_ids:
				discard_has_captured_id = true
		_check(bool(info.get("captured", false)) and
			int(info.get("capture_reach", 0)) == thickness and
			int(info.get("captured_thickness", 0)) == thickness and
			(info.get("captured_thesis_ids", []) as Array) == expected_ids and
			_stack_ids(trophy) == expected_ids and all_stolen and metadata_kept and
			int(trophy.theses) == thickness and int(trophy.stolen) == thickness and
			String(trophy.get("claim_id", "")) == "capture_%d" % thickness and
			(trophy.get("statements", []) as Array).is_empty() and
			not discard_has_captured_id and model.captures == 1 and
			model.capture_theses == thickness,
			"direct K at audience reach %d moves the whole ordered object frame with %d theses" % [
				thickness, thickness])


func _check_thick_defense_paths() -> void:
	for thickness in [2, 3, 4]:
		var ktr := _fresh(true)
		var ktr_target := _object_line(thickness, "Thick KTR", "thick_ktr_%d" % thickness)
		var base_ids := _stack_ids(ktr_target)
		ktr.sides[RulesCore.SIDE_YOU].lines = [_object_line(1, "Attacker", "ktr_active")]
		ktr.sides[RulesCore.SIDE_OPP].lines = [ktr_target]
		ktr.set_external_zal(-thickness, true)
		ktr.sides[RulesCore.SIDE_YOU].hand = [
			_card(RulesCore.TYPE_RAZBOR, "K0", true),
			_card(RulesCore.TYPE_RAZBOR, "R2")]
		ktr.sides[RulesCore.SIDE_YOU].draw = []
		ktr.sides[RulesCore.SIDE_OPP].hand = [
			_card(RulesCore.TYPE_TEZIS, "Exact defense"),
			_card(RulesCore.TYPE_USTANOVKA, "Recovery")]
		ktr.sides[RulesCore.SIDE_OPP].draw = []
		ktr.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, true, 0)
		ktr.clinch_submit("play", false, 0)
		ktr.clinch_submit("play", false, 0)
		var ktr_info: Dictionary = ktr.clinch_submit("pass").get("info", {})
		var ktr_seq: Array = ktr_info.get("resolved_sequence", [])
		var defense_id := String(ktr_seq[1].get("thesis_id", ""))
		var trophy: Dictionary = ktr.sides[RulesCore.SIDE_YOU].lines[0]
		var press_effect := _resolved_effect(ktr_info, 2)
		var opener_effect := _resolved_effect(ktr_info, 0)
		_check(bool(ktr_info.get("opening_capture_eligible", false)) and
			bool(ktr_info.get("capture_reactivated", false)) and
			not bool(ktr_info.get("parried_capture", true)) and
			bool(ktr_info.get("capture_attempted", false)) and
			bool(ktr_info.get("captured", false)) and
			(ktr_info.get("resolved_attack_steps", []) as Array) == [2, 0] and
			String(press_effect.get("effect", "")) == "breakdown" and
			String(press_effect.get("affected_thesis_id", "")) == defense_id and
			String(opener_effect.get("effect", "")) == "capture" and
			(ktr_info.get("captured_thesis_ids", []) as Array) == base_ids and
			_stack_ids(trophy) == base_ids and not defense_id in _stack_ids(trophy) and
			_discard_has_thesis_id(ktr.sides[RulesCore.SIDE_OPP], defense_id) and
			ktr.captures == 1 and ktr.capture_theses == thickness,
			"thick K-T-R unwinds exact T, then captures only original frame IDs at reach %d" % thickness)

	var held := _fresh(true)
	var held_target := _object_line(3, "Thick hold", "thick_hold")
	var held_base_ids := _stack_ids(held_target)
	held.sides[RulesCore.SIDE_YOU].lines = [_line(1, "Attacker")]
	held.sides[RulesCore.SIDE_OPP].lines = [held_target]
	held.set_external_zal(-3, true)
	held.sides[RulesCore.SIDE_YOU].hand = [
		_card(RulesCore.TYPE_RAZBOR, "K0", true)]
	held.sides[RulesCore.SIDE_YOU].draw = []
	held.sides[RulesCore.SIDE_OPP].hand = [
		_card(RulesCore.TYPE_TEZIS, "Held defense")]
	held.sides[RulesCore.SIDE_OPP].draw = []
	held.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, true, 0)
	var hold_event: Dictionary = held.clinch_submit("play", false, 0)
	var held_info: Dictionary = held.clinch_submit("pass").get("info", {})
	var held_stack: Array = held.sides[RulesCore.SIDE_OPP].lines[0].thesis_stack
	_check(bool(held_info.get("parried_capture", false)) and
		not bool(held_info.get("capture_reactivated", false)) and
		(held_info.get("resolved_attack_steps", []) as Array).is_empty() and
		not bool(held_info.get("captured", false)) and held_stack.size() == 4 and
		_stack_ids(held.sides[RulesCore.SIDE_OPP].lines[0]).slice(0, 3) == held_base_ids and
		String((held_stack[-1] as Dictionary).get("thesis_id", "")) ==
			String(hold_event.get("thesis_id", "")),
		"thick K-T-pass leaves the exact defensive T on top of the original object stack")


func _check_capture_active_invariant() -> void:
	var model := _fresh(true)
	var old_active := _object_line(1, "Original active", "old_active")
	var target := _object_line(2, "Closed target", "closed_target")
	target["closed"] = true
	model.sides[RulesCore.SIDE_YOU].lines = [old_active]
	model.sides[RulesCore.SIDE_OPP].lines = [
		target, _object_line(1, "Defender active", "def_active")]
	model.set_external_zal(-2, true)
	model.sides[RulesCore.SIDE_YOU].hand = [
		_card(RulesCore.TYPE_RAZBOR, "Capture K", true)]
	model.sides[RulesCore.SIDE_YOU].draw = []
	model.sides[RulesCore.SIDE_OPP].hand = []
	model.sides[RulesCore.SIDE_OPP].draw = []
	model.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, true, 0)
	model.clinch_submit("pass")
	var lines: Array = model.sides[RulesCore.SIDE_YOU].lines
	var trophy_ids := _stack_ids(lines[0])
	var active_before := int(lines[-1].theses)
	model.sides[RulesCore.SIDE_YOU].hand = [
		_card(RulesCore.TYPE_TEZIS, "Normal T")]
	var thesis_info: Dictionary = model.play_action(RulesCore.SIDE_YOU,
		RulesCore.TYPE_TEZIS, -1, 0)
	var normal_t_id := String(thesis_info.get("thesis_id", ""))
	var normal_t_on_active := String((lines[-1].thesis_stack as Array)[-1].get(
		"thesis_id", "")) == normal_t_id

	model.sides[RulesCore.SIDE_YOU].hand = [
		_card(RulesCore.TYPE_RAZBOR, "K0", true),
		_card(RulesCore.TYPE_RAZBOR, "K2", true),
	]
	model.sides[RulesCore.SIDE_OPP].hand = [
		_card(RulesCore.TYPE_TEZIS, "Defensive T")]
	model.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, true, 0)
	model.clinch_submit("play", true, 0)
	model.clinch_submit("play", true, 0)
	var ktk_info: Dictionary = model.clinch_submit("pass").get("info", {})
	var stolen_t_id := String(ktk_info.get("affected_thesis_id", ""))
	var stolen_t_on_active := String((lines[-1].thesis_stack as Array)[-1].get(
		"thesis_id", "")) == stolen_t_id

	model.sides[RulesCore.SIDE_YOU].hand = [
		_card(RulesCore.TYPE_USTANOVKA, "New active")]
	model.play_action(RulesCore.SIDE_YOU, RulesCore.TYPE_USTANOVKA, -1, 0)
	var open_count := 0
	for line in lines:
		if not bool((line as Dictionary).get("closed", false)):
			open_count += 1
	_check(lines.size() == 3 and bool(lines[0].closed) and
		String(lines[0].name) == "Closed target" and _stack_ids(lines[0]) == trophy_ids and
		active_before == 1 and normal_t_on_active and stolen_t_on_active and
		int(lines[0].theses) == 2 and open_count == 1 and
		not bool(lines[-1].closed) and String(lines[-1].name) == "New active",
		"closed capture trophy stays before active; later T, K-T-K and U preserve one active-last frame")


func _run_base_k_t_x(final_steals: bool) -> Dictionary:
	var model := _fresh(true)
	model.sides[RulesCore.SIDE_YOU].lines = [_line(1, "Атакующий")]
	model.sides[RulesCore.SIDE_OPP].lines = [_line(1, "На последнем тезисе")]
	model.sides[RulesCore.SIDE_YOU].hand = [
		_card(RulesCore.TYPE_RAZBOR, "Первая Кража", true),
		_card(RulesCore.TYPE_RAZBOR, "Финальная Кража" if final_steals else "Финальный Разбор",
			final_steals),
	]
	model.sides[RulesCore.SIDE_YOU].draw = []
	model.sides[RulesCore.SIDE_OPP].hand = [
		_card(RulesCore.TYPE_TEZIS, "Защитный тезис"),
		_card(RulesCore.TYPE_USTANOVKA, "Резерв"),
	]
	model.sides[RulesCore.SIDE_OPP].draw = []
	var start: Dictionary = model.begin_clinch(
		RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, true, 0)
	var hold: Dictionary = model.clinch_submit("play", true, 0)
	var press: Dictionary = model.clinch_submit("play", final_steals, 0)
	var result: Dictionary = model.clinch_submit("pass")
	return {"model": model, "start": start, "hold": hold, "press": press, "result": result}


func _check_protected_thickness_and_full_loot() -> void:
	# Неприкрытая Кража сама попадает в рамку и переносит её целиком.
	var direct := _fresh(true)
	direct.sides[RulesCore.SIDE_YOU].lines = [_line(1, "Атакующий")]
	direct.sides[RulesCore.SIDE_OPP].lines = [_line(1, "Открытая рамка")]
	direct.sides[RulesCore.SIDE_YOU].hand = [_card(RulesCore.TYPE_RAZBOR, "Кража", true)]
	direct.sides[RulesCore.SIDE_YOU].draw = []
	direct.sides[RulesCore.SIDE_OPP].hand = [_card(RulesCore.TYPE_USTANOVKA, "Резерв")]
	direct.sides[RulesCore.SIDE_OPP].draw = []
	direct.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, true, 0)
	var direct_result: Dictionary = direct.clinch_submit("pass")
	var direct_info: Dictionary = direct_result.get("info", {})
	_check(bool(direct_info.get("captured", false)) and
		String(direct_info.get("landing_effect", "")) == "capture" and
		String(direct_info.get("landing_target_kind", "")) == "frame" and
		int(direct_info.get("landing_step", -1)) == 0 and direct.capture_theses == 1,
		"непогашенная Кража по рамке с 1 тезисом захватывает именно эту рамку")

	# K–T–R: первая Кража погашена; последний объект Разбора снимает только ответный T.
	var ktr: Dictionary = _run_base_k_t_x(false)
	var ktr_model: RefCounted = ktr.model
	var ktr_result: Dictionary = ktr.result
	var ktr_info: Dictionary = ktr_result.get("info", {})
	var ktr_seq: Array = ktr_info.get("resolved_sequence", [])
	_check(bool(ktr_result.get("landed", false)) and not ktr_info.get("captured", false) and
		not ktr_info.get("removed", false) and int(ktr_info.get("stolen_count", 0)) == 0 and
		not ktr_info.get("landing_attack_steals", true) and
		String(ktr_info.get("landing_effect", "")) == "breakdown" and
		String(ktr_info.get("landing_target_kind", "")) == "thesis" and
		int(ktr_info.get("parried_steals", 0)) == 1 and ktr_seq.size() == 3 and
		String(ktr_seq[0].get("result", "")) == "parried" and
		String(ktr_seq[1].get("result", "")) == "removed" and
		String(ktr_seq[2].get("result", "")) == "landed" and
		int(ktr_model.sides[RulesCore.SIDE_OPP].lines[0].theses) == 1 and
		String(_discard_card(ktr_model.sides[RulesCore.SIDE_OPP],
			"Защитный тезис").get("thesis_id", "")) ==
			String(ktr_seq[1].get("thesis_id", "")) and
		ktr_model.captures == 0 and ktr_model.capture_theses == 0,
		"K–T–R не наследует Кражу: финальный Разбор отправляет точный защитный T в сброс")

	# K–T–K: первая Кража всё ещё погашена, а финальная крадёт только объект T под ней.
	var ktk: Dictionary = _run_base_k_t_x(true)
	var ktk_model: RefCounted = ktk.model
	var ktk_info: Dictionary = (ktk.result as Dictionary).get("info", {})
	var ktk_seq: Array = ktk_info.get("resolved_sequence", [])
	_check(not ktk_info.get("captured", false) and not ktk_info.get("capture_attempted", true) and
		int(ktk_info.get("stolen_count", 0)) == 1 and
		bool(ktk_info.get("landing_attack_steals", false)) and
		String(ktk_info.get("landing_effect", "")) == "steal_thesis" and
		String(ktk_info.get("landing_target_kind", "")) == "thesis" and
		int(ktk_info.get("parried_steals", 0)) == 1 and ktk_seq.size() == 3 and
		String(ktk_seq[1].get("result", "")) == "stolen" and
		int(ktk_model.sides[RulesCore.SIDE_OPP].lines[0].theses) == 1 and
		int(ktk_model.sides[RulesCore.SIDE_YOU].lines[0].theses) == 2 and
		String((ktk_model.sides[RulesCore.SIDE_YOU].lines[0].thesis_stack as Array)[-1].get(
			"thesis_id", "")) == String(ktk_seq[1].get("thesis_id", "")) and
		_discard_card(ktk_model.sides[RulesCore.SIDE_OPP], "Защитный тезис").is_empty(),
		"K–T–K крадёт только ответный тезис; погашенная первая Кража не оживает")

	# Длинная цепь хранит адреса объектов: финальная K снимает последний T, ранний T остаётся.
	var stack := _fresh(true)
	stack.sides[RulesCore.SIDE_YOU].lines = [_line(1, "Атакующий")]
	stack.sides[RulesCore.SIDE_OPP].lines = [_line(1, "Стековая рамка")]
	stack.sides[RulesCore.SIDE_YOU].hand = [
		_card(RulesCore.TYPE_RAZBOR, "K0", true),
		_card(RulesCore.TYPE_RAZBOR, "R2"),
		_card(RulesCore.TYPE_RAZBOR, "K4", true),
	]
	stack.sides[RulesCore.SIDE_YOU].draw = []
	var stolen_hold := _card(RulesCore.TYPE_TEZIS, "T3")
	stolen_hold["stolen"] = true
	stack.sides[RulesCore.SIDE_OPP].hand = [
		_card(RulesCore.TYPE_TEZIS, "T1"), stolen_hold,
		_card(RulesCore.TYPE_USTANOVKA, "Резерв"),
	]
	stack.sides[RulesCore.SIDE_OPP].draw = []
	stack.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, true, 0)
	stack.clinch_submit("play", true, 0)
	stack.clinch_submit("play", false, 0)
	stack.clinch_submit("play", true, 0)
	stack.clinch_submit("play", true, 0)
	var stack_result: Dictionary = stack.clinch_submit("pass")
	var stack_info: Dictionary = stack_result.get("info", {})
	var stack_seq: Array = stack_info.get("resolved_sequence", [])
	_check(stack_seq.size() == 5 and int(stack_info.get("landing_step", -1)) == 4 and
		int(stack_info.get("landing_target_step", -1)) == 3 and
		(stack_info.get("parried_steps", []) as Array) == [0, 2] and
		String(stack_seq[0].get("target_kind", "")) == "frame" and
		int(stack_seq[2].get("target_step", -1)) == 1 and
		int(stack_seq[4].get("target_step", -1)) == 3 and
		String(stack_seq[1].get("result", "")) == "held" and
		String(stack_seq[3].get("result", "")) == "stolen" and
		int(stack.sides[RulesCore.SIDE_OPP].lines[0].theses) == 2 and
		int(stack.sides[RulesCore.SIDE_OPP].lines[0].stolen) == 0,
		"K–T–R–T–K снимает адресный последний T; ранний T и его объект остаются")

	# Граница: открытая толщина 4 при reach 4 — Кража уводит всю рамку со всеми тезисами.
	var captured := _fresh(true)
	_prime_reach_four(captured)
	captured.sides[RulesCore.SIDE_OPP].hand = [_card(RulesCore.TYPE_USTANOVKA, "Страховка")]
	captured.sides[RulesCore.SIDE_OPP].draw = []
	var cap_info := {}
	captured.clinch_finalize(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, 0, 1, cap_info,
		_card(RulesCore.TYPE_RAZBOR, "Кража", true))
	_check(bool(cap_info.get("captured", false)) and int(cap_info.get("protected_thickness", 0)) == 4 and
		captured.capture_theses == 4 and captured.sides[RulesCore.SIDE_YOU].lines.size() == 2 and
		int(captured.sides[RulesCore.SIDE_YOU].lines[0].theses) == 4 and
		bool(captured.sides[RulesCore.SIDE_YOU].lines[0].closed) and
		not bool(captured.sides[RulesCore.SIDE_YOU].lines[-1].closed) and
		not captured.game_over and captured.recovery_pending(RulesCore.SIDE_OPP),
		"Кража на границе reach 4 переносит полную рамку толщиной 4, а не обрезанный остаток")

	# На толстой рамке T парирует первую Кражу; поздняя K направлена уже только в этот T.
	var defended := _fresh(true)
	_prime_reach_four(defended)
	defended.sides[RulesCore.SIDE_YOU].hand = [
		_card(RulesCore.TYPE_RAZBOR, "Первая Кража", true),
		_card(RulesCore.TYPE_RAZBOR, "Финальная Кража", true),
	]
	defended.sides[RulesCore.SIDE_YOU].draw = []
	defended.sides[RulesCore.SIDE_OPP].hand = [_card(RulesCore.TYPE_TEZIS, "Защита")]
	defended.sides[RulesCore.SIDE_OPP].draw = []
	defended.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, true, 0)
	defended.clinch_submit("play", true, 0)
	defended.clinch_submit("play", true, 0)
	var defended_result: Dictionary = defended.clinch_submit("pass")
	var def_info: Dictionary = defended_result.get("info", {})
	_check(not bool(def_info.get("captured", false)) and
		not bool(def_info.get("capture_attempted", true)) and
		int(def_info.get("parried_steals", 0)) == 1 and
		int(def_info.get("stolen_count", 0)) == 1 and
		String(def_info.get("landing_target_kind", "")) == "thesis" and
		int(def_info.get("opening_thickness", 0)) == 4 and
		int(def_info.get("protected_thickness", 0)) == 5 and
		defended.sides[RulesCore.SIDE_OPP].lines.size() == 1 and
		int(defended.sides[RulesCore.SIDE_OPP].lines[0].theses) == 4,
		"T парирует захват толстой рамки, а финальная Кража забирает только этот T")

	# Решающий отрицательный случай: даже при opening=1 и frozen reach=4 поздняя K
	# адресована ответному T, поэтому capture_attempted обязан остаться false.
	var in_reach := _fresh(true)
	in_reach.sides[RulesCore.SIDE_YOU].lines = [_line(1, "Андердог")]
	in_reach.sides[RulesCore.SIDE_OPP].lines = [_line(1, "Шатается")]
	in_reach.set_external_zal(-4, true)
	in_reach.sides[RulesCore.SIDE_YOU].hand = [
		_card(RulesCore.TYPE_RAZBOR, "K0", true),
		_card(RulesCore.TYPE_RAZBOR, "K2", true),
	]
	in_reach.sides[RulesCore.SIDE_YOU].draw = []
	in_reach.sides[RulesCore.SIDE_OPP].hand = [_card(RulesCore.TYPE_TEZIS, "T1")]
	in_reach.sides[RulesCore.SIDE_OPP].draw = []
	in_reach.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, true, 0)
	in_reach.clinch_submit("play", false, 0)
	in_reach.clinch_submit("play", true, 0)
	var in_reach_result: Dictionary = in_reach.clinch_submit("pass")
	var in_reach_info: Dictionary = in_reach_result.get("info", {})
	_check(int(in_reach_info.get("capture_reach", 0)) == 4 and
		int(in_reach_info.get("opening_thickness", 0)) == 1 and
		not bool(in_reach_info.get("capture_attempted", true)) and
		not bool(in_reach_info.get("captured", false)) and
		String(in_reach_info.get("affected_kind", "")) == "thesis" and
		int(in_reach_info.get("stolen_count", 0)) == 1 and
		int(in_reach.sides[RulesCore.SIDE_OPP].lines[0].theses) == 1,
		"opening 1/reach 4 K–T–K всё равно крадёт только объект T, не рамку")

	# Укрепление — свойство рамки, не лежащего сверху T: press-K не отскакивает от него.
	var fortified := _fresh(true)
	fortified.fortify_threshold = 2
	fortified.sides[RulesCore.SIDE_YOU].lines = [_line(1, "Атакующий")]
	fortified.sides[RulesCore.SIDE_OPP].lines = [_line(1, "Укрепляемая")]
	fortified.sides[RulesCore.SIDE_YOU].hand = [
		_card(RulesCore.TYPE_RAZBOR, "R0"),
		_card(RulesCore.TYPE_RAZBOR, "K2", true),
	]
	fortified.sides[RulesCore.SIDE_YOU].draw = []
	fortified.sides[RulesCore.SIDE_OPP].hand = [_card(RulesCore.TYPE_TEZIS, "T1")]
	fortified.sides[RulesCore.SIDE_OPP].draw = []
	fortified.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, false, 0)
	fortified.clinch_submit("play", false, 0)
	fortified.clinch_submit("play", true, 0)
	var fortified_info: Dictionary = fortified.clinch_submit("pass").get("info", {})
	_check(String(fortified_info.get("landing_effect", "")) == "steal_thesis" and
		not bool(fortified_info.get("bounced", false)) and
		int(fortified.sides[RulesCore.SIDE_OPP].lines[0].theses) == 1,
		"укреплённая рамка не защищает отдельный ответный T от press-Кражи")

	# Идентичность переживает границу клинча: украденный T лежит верхним объектом на рамке
	# вора, и следующий opening-R снимает именно его, корректно обнуляя stolen.
	var moved_id := String(ktk_seq[1].get("thesis_id", ""))
	ktk_model.sides[RulesCore.SIDE_OPP].hand = [_card(RulesCore.TYPE_RAZBOR, "Ответный R")]
	ktk_model.sides[RulesCore.SIDE_OPP].draw = []
	ktk_model.sides[RulesCore.SIDE_YOU].hand = []
	ktk_model.sides[RulesCore.SIDE_YOU].draw = []
	ktk_model.begin_clinch(RulesCore.SIDE_OPP, RulesCore.SIDE_YOU, 0, false, 0)
	var next_info: Dictionary = ktk_model.clinch_submit("pass").get("info", {})
	var returned_card := _discard_card(ktk_model.sides[RulesCore.SIDE_YOU], "Защитный тезис")
	_check(String(next_info.get("affected_thesis_id", "")) == moved_id and
		String(returned_card.get("thesis_id", "")) == moved_id and
		bool(returned_card.get("stolen", false)) and
		int(ktk_model.sides[RulesCore.SIDE_YOU].lines[0].stolen) == 0,
		"следующий клинч снимает тот же украденный thesis_id, а не абстрактную единицу")


func _named_card(type: String, name: String, id: String, opens_clinch: bool = false) -> Dictionary:
	var card := _card(type, name)
	card["named"] = id
	card["clinch"] = opens_clinch
	return card


func _check_named_capture_object_fields() -> void:
	var model := _fresh(true)
	model.sides[RulesCore.SIDE_YOU].lines = [_line(1, "Original active")]
	model.sides[RulesCore.SIDE_OPP].lines = [
		_object_line(3, "Strawman target", "straw_target")]
	model.set_external_zal(-2, true) # ordinary reach 2; this card object adds exactly 1
	model.sides[RulesCore.SIDE_YOU].hand = [NamedCards.make("strawman")]
	model.sides[RulesCore.SIDE_YOU].draw = []
	model.sides[RulesCore.SIDE_OPP].hand = [
		_card(RulesCore.TYPE_USTANOVKA, "Recovery")]
	model.sides[RulesCore.SIDE_OPP].draw = []
	var info: Dictionary = model.play_named(RulesCore.SIDE_YOU, 0, 0)
	var trophy: Dictionary = model.sides[RulesCore.SIDE_YOU].lines[0]
	_check(bool(info.get("captured", false)) and bool(info.get("strawman", false)) and
		int(info.get("capture_bonus", 0)) == 1 and int(trophy.theses) == 2 and
		(info.get("captured_thesis_ids", []) as Array) == _stack_ids(trophy) and
		bool(trophy.closed) and not bool(model.sides[RulesCore.SIDE_YOU].lines[-1].closed),
		"named Theft keeps reach bonus/trim on its card object and preserves active-last")


func _check_socratic_object_target() -> void:
	# S–T–R: финальный R уже потребил объект ответа. Ловушка не имеет права выбрать
	# вместо него базовый тезис рамки.
	var expired := _fresh(true)
	expired.sides[RulesCore.SIDE_YOU].lines = [_line(1, "Сократик")]
	expired.sides[RulesCore.SIDE_OPP].lines = [_line(1, "Ответ")]
	expired.sides[RulesCore.SIDE_YOU].hand = [
		_named_card(RulesCore.TYPE_RAZBOR, "Сократический вопрос", "socratic", true),
		_card(RulesCore.TYPE_RAZBOR, "R2"),
	]
	expired.sides[RulesCore.SIDE_YOU].draw = []
	expired.sides[RulesCore.SIDE_OPP].hand = [_card(RulesCore.TYPE_TEZIS, "T1")]
	expired.sides[RulesCore.SIDE_OPP].draw = []
	expired.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, false, 0)
	expired.clinch_submit("play", false, 0)
	expired.clinch_submit("play", false, 0)
	var expired_info: Dictionary = expired.clinch_submit("pass").get("info", {})
	var expired_seq: Array = expired_info.get("resolved_sequence", [])
	_check(bool(expired_info.get("socratic_expired", false)) and
		not bool(expired_info.get("socratic", false)) and
		int(expired_info.get("stolen_count", 0)) == 0 and expired_seq.size() == 3 and
		String(expired_seq[1].get("result", "")) == "removed" and
		int(expired.sides[RulesCore.SIDE_OPP].lines[0].theses) == 1 and
		int(expired.sides[RulesCore.SIDE_YOU].lines[0].theses) == 1,
		"S–T–R: Сократик не перескакивает с уже снятого T на базовый тезис рамки")

	# S–T1–R–T2: обе атаки погашены, поэтому первый T всё ещё held. Ловушка снимает
	# конкретно T1 из середины стека; T2 и его объект остаются сверху.
	var buried := _fresh(true)
	buried.sides[RulesCore.SIDE_YOU].lines = [_line(1, "Сократик")]
	buried.sides[RulesCore.SIDE_OPP].lines = [_line(1, "Ответ")]
	buried.sides[RulesCore.SIDE_YOU].hand = [
		_named_card(RulesCore.TYPE_RAZBOR, "Сократический вопрос", "socratic", true),
		_card(RulesCore.TYPE_RAZBOR, "R2"),
	]
	buried.sides[RulesCore.SIDE_YOU].draw = []
	buried.sides[RulesCore.SIDE_OPP].hand = [
		_card(RulesCore.TYPE_TEZIS, "T1"), _card(RulesCore.TYPE_TEZIS, "T3"),
	]
	buried.sides[RulesCore.SIDE_OPP].draw = []
	buried.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, false, 0)
	buried.clinch_submit("play", false, 0)
	buried.clinch_submit("play", false, 0)
	buried.clinch_submit("play", false, 0)
	var buried_info: Dictionary = buried.clinch_submit("pass").get("info", {})
	var buried_seq: Array = buried_info.get("resolved_sequence", [])
	var remaining_stack: Array = buried.sides[RulesCore.SIDE_OPP].lines[0].thesis_stack
	_check(bool(buried_info.get("socratic", false)) and
		int(buried_info.get("socratic_target_step", -1)) == 1 and buried_seq.size() == 4 and
		String(buried_seq[1].get("result", "")) == "stolen_by_socratic" and
		String(buried_seq[3].get("result", "")) == "held" and
		String(remaining_stack[-1].get("thesis_id", "")) ==
			String(buried_seq[3].get("thesis_id", "")) and
		int(buried.sides[RulesCore.SIDE_OPP].lines[0].theses) == 2,
		"S–T1–R–T2: ловушка крадёт адресный T1 из середины, оставляя T2")


func _check_named_clinch_legality() -> void:
	var vanilla_t := _card(RulesCore.TYPE_TEZIS, "Обычный T")
	var vanilla_r := _card(RulesCore.TYPE_RAZBOR, "Обычный R")
	var socratic := _named_card(RulesCore.TYPE_RAZBOR, "Сократик", "socratic", true)
	var shot := _named_card(RulesCore.TYPE_RAZBOR, "Гиш", "gish_gallop", false)
	var burden := _named_card(RulesCore.TYPE_TEZIS, "Бремя", "burden_shift", false)
	var probe := _fresh(true)
	_check(probe.clinch_card_legal(vanilla_r, "open") and
		probe.clinch_card_legal(socratic, "open") and
		not probe.clinch_card_legal(shot, "open") and
		probe.clinch_card_legal(vanilla_t, "await_defend") and
		not probe.clinch_card_legal(burden, "await_defend") and
		probe.clinch_card_legal(vanilla_r, "await_attack") and
		not probe.clinch_card_legal(socratic, "await_attack"),
		"единый predicate: named-твист легален только в явно поддержанной роли")

	# Неверный индекс не может молча списать другую карту. Сначала отклоняем named T/R,
	# затем тем же стейтом принимаем выбранные ванильные объекты.
	var exact := _fresh(true)
	exact.sides[RulesCore.SIDE_OPP].lines = [_line(1)]
	exact.sides[RulesCore.SIDE_YOU].hand = [vanilla_r.duplicate(true),
		socratic.duplicate(true), _card(RulesCore.TYPE_RAZBOR, "Press R")]
	exact.sides[RulesCore.SIDE_YOU].draw = []
	exact.sides[RulesCore.SIDE_OPP].hand = [burden.duplicate(true), vanilla_t.duplicate(true)]
	exact.sides[RulesCore.SIDE_OPP].draw = []
	exact.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, false, 0)
	var before_line := int(exact.sides[RulesCore.SIDE_OPP].lines[0].theses)
	var rejected_t: Dictionary = exact.clinch_submit("play", false, 0)
	var accepted_t: Dictionary = exact.clinch_submit("play", false, 1)
	var rejected_r: Dictionary = exact.clinch_submit("play", false, 0)
	var accepted_r: Dictionary = exact.clinch_submit("play", false, 1)
	var exact_info: Dictionary = exact.clinch_submit("pass").get("info", {})
	_check(String(rejected_t.get("event", "")) == "invalid" and
		String(accepted_t.get("event", "")) == "hold" and
		String(rejected_r.get("event", "")) == "invalid" and
		String(accepted_r.get("event", "")) == "press" and
		String(exact.sides[RulesCore.SIDE_YOU].hand[0].get("named", "")) == "socratic" and
		String(exact.sides[RulesCore.SIDE_OPP].hand[0].get("named", "")) == "burden_shift" and
		int(exact_info.get("clinch_t", 0)) == 1 and
		int(exact.sides[RulesCore.SIDE_OPP].lines[0].theses) == before_line,
		"illegal selected index ничего не мутирует и не подменяется другой картой")

	var shot_open := _fresh(true)
	shot_open.sides[RulesCore.SIDE_YOU].hand = [shot.duplicate(true)]
	var shot_before: int = shot_open.sides[RulesCore.SIDE_YOU].hand.size()
	_check(shot_open.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0,
		false, 0).is_empty() and shot_open.sides[RulesCore.SIDE_YOU].hand.size() == shot_before,
		"именную shot-карту нельзя открыть как ванильный клинч")

	var named_only := _fresh(true)
	named_only.sides[RulesCore.SIDE_YOU].hand = [vanilla_r.duplicate(true)]
	named_only.sides[RulesCore.SIDE_YOU].draw = []
	named_only.sides[RulesCore.SIDE_OPP].hand = [burden.duplicate(true)]
	named_only.sides[RulesCore.SIDE_OPP].draw = []
	named_only.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, false, 0)
	var can_named_defend: bool = named_only.clinch_can_act(RulesCore.SIDE_OPP)
	var named_stop: Dictionary = named_only.clinch_submit("pass")
	_check(not can_named_defend and String(named_stop.get("stop_reason", "")) == "exhausted" and
		String(named_only.sides[RulesCore.SIDE_OPP].hand[0].get("named", "")) == "burden_shift",
		"одна неподдержанная named-карта не считается ответом и остаётся в руке")

	var soc_open := _fresh(true)
	soc_open.sides[RulesCore.SIDE_YOU].hand = [socratic.duplicate(true)]
	var started: Dictionary = soc_open.begin_clinch(
		RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, false, 0)
	_check(not started.is_empty() and String(started.card.get("named", "")) == "socratic" and
		int(soc_open.named_played[RulesCore.SIDE_YOU]) == 1,
		"Сократик остаётся полноценным объектом-opener и не теряет собственный hook")


func _check_ai_target_awareness() -> void:
	var plain := _fresh(true)
	plain.sides[RulesCore.SIDE_OPP].lines = [_line(1, "Цель"), _line(1, "Другая")]
	plain.sides[RulesCore.SIDE_YOU].hand = [_card(RulesCore.TYPE_RAZBOR, "Обычный R")]
	plain.sides[RulesCore.SIDE_YOU].draw = []
	plain.sides[RulesCore.SIDE_OPP].hand = [_card(RulesCore.TYPE_TEZIS, "Последний T")]
	plain.sides[RulesCore.SIDE_OPP].draw = []
	var plain_ai := AiCore.new()
	plain_ai.set_style(RulesCore.SIDE_OPP, "smart")
	plain.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, false, 0)
	var plain_defense: bool = plain_ai.def_will_clinch(plain, RulesCore.SIDE_OPP,
		plain.sides[RulesCore.SIDE_OPP].lines[0])

	var theft := _fresh(true)
	theft.sides[RulesCore.SIDE_OPP].lines = [_line(1, "Цель"), _line(1, "Другая")]
	theft.sides[RulesCore.SIDE_YOU].hand = [_card(RulesCore.TYPE_RAZBOR, "Кража", true)]
	theft.sides[RulesCore.SIDE_YOU].draw = []
	theft.sides[RulesCore.SIDE_OPP].hand = [_card(RulesCore.TYPE_TEZIS, "Последний T")]
	theft.sides[RulesCore.SIDE_OPP].draw = []
	var theft_ai := AiCore.new()
	theft_ai.set_style(RulesCore.SIDE_OPP, "smart")
	theft.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, true, 0)
	var theft_defense: bool = theft_ai.def_will_clinch(theft, RulesCore.SIDE_OPP,
		theft.sides[RulesCore.SIDE_OPP].lines[0])
	_check(not plain_defense and theft_defense,
		"smart AI читает frozen-объект opener: последний T бережёт от plain-R, но тратит на K")

	var model := _fresh(true)
	model.sides[RulesCore.SIDE_OPP].lines = [_line(1, "Последняя")]
	model.sides[RulesCore.SIDE_YOU].hand = [
		_card(RulesCore.TYPE_RAZBOR, "R0"),
		_card(RulesCore.TYPE_RAZBOR, "R2"),
	]
	model.sides[RulesCore.SIDE_YOU].draw = []
	model.sides[RulesCore.SIDE_OPP].hand = [
		_card(RulesCore.TYPE_TEZIS, "T1"),
		_card(RulesCore.TYPE_TEZIS, "T3"),
	]
	model.sides[RulesCore.SIDE_OPP].draw = []
	var ai := AiCore.new()
	ai.set_style(RulesCore.SIDE_OPP, "smart")
	ai.set_style(RulesCore.SIDE_YOU, "smart")
	model.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, false, 0)
	var protects_frame: bool = ai.def_will_clinch(model, RulesCore.SIDE_OPP,
		model.sides[RulesCore.SIDE_OPP].lines[0])
	model.clinch_submit("play", false, 0)
	var spends_last_press: bool = ai.atk_will_clinch(model, RulesCore.SIDE_YOU,
		model.sides[RulesCore.SIDE_OPP].lines[0])
	# Для проверки второй defense-фазы вручную разыгрываем press, который smart сохранил бы.
	model.clinch_submit("play", false, 0)
	var feeds_press: bool = ai.def_will_clinch(model, RulesCore.SIDE_OPP,
		model.sides[RulesCore.SIDE_OPP].lines[0])
	_check(protects_frame and not spends_last_press and not feeds_press,
		"smart AI отличает opener→frame от press→T и не кормит поздний press последним T")


func _check_clinch_context_snapshot() -> void:
	var model := _fresh(true)
	_prime_reach_four(model)
	model.sides[RulesCore.SIDE_YOU].hand = [
		_card(RulesCore.TYPE_RAZBOR, "Кража", true),
	]
	model.sides[RulesCore.SIDE_YOU].draw = []
	model.sides[RulesCore.SIDE_OPP].hand = [_card(RulesCore.TYPE_USTANOVKA, "Страховка")]
	model.sides[RulesCore.SIDE_OPP].draw = []
	var turn_before := int(model.turn_count)
	var started: Dictionary = model.begin_clinch(
		RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, true, 0)
	# После открытия сцены условия исчезли; этот клинч обязан дочитать старый снимок reach=4.
	model.set_external_zal(0, true)
	var result: Dictionary = model.clinch_submit("pass")
	var info: Dictionary = result.get("info", {})
	_check(not started.is_empty() and bool(info.get("captured", false)) and
		int(info.get("capture_reach", 0)) == 4,
		"public audience reach фиксируется при открытии клинча и не меняется ретроактивно")
	var late := _fresh(true)
	late.sides[RulesCore.SIDE_YOU].lines = [_line(1, "Attacker")]
	late.sides[RulesCore.SIDE_OPP].lines = [_object_line(4, "Late wobble", "late")]
	late.set_external_zal(0, true)
	late.sides[RulesCore.SIDE_YOU].hand = [
		_card(RulesCore.TYPE_RAZBOR, "Early stable K", true)]
	late.sides[RulesCore.SIDE_YOU].draw = []
	late.sides[RulesCore.SIDE_OPP].hand = []
	late.sides[RulesCore.SIDE_OPP].draw = []
	late.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, true, 0)
	late.set_external_zal(-4, true)
	var late_info: Dictionary = late.clinch_submit("pass").get("info", {})
	_check(int(late_info.get("capture_reach", 0)) == 1 and
		not bool(late_info.get("captured", false)) and
		bool(late_info.get("capture_blocked", false)) and
		String(late_info.get("capture_block_reason", "")) == "out_of_reach" and
		int(late.sides[RulesCore.SIDE_OPP].lines[0].theses) == 3,
		"audience shift after opening cannot retroactively turn a stable target into full capture")
	_check(model.turn_count == turn_before + 1,
		"полный клинч считается одним действием независимо от длины внутреннего ралли")


func _stall_result(extra_attack: bool) -> Dictionary:
	var model := _fresh(true)
	model.sides[RulesCore.SIDE_YOU].lines = [_line(1, "Атакующий")]
	model.sides[RulesCore.SIDE_OPP].lines = [_line(1, "Защитник")]
	model.sides[RulesCore.SIDE_YOU].hand = [
		_card(RulesCore.TYPE_RAZBOR, "Первый нажим"),
	]
	if extra_attack:
		model.sides[RulesCore.SIDE_YOU].hand.append(
			_card(RulesCore.TYPE_RAZBOR, "Можно продолжить"))
	model.sides[RulesCore.SIDE_YOU].draw = []
	model.sides[RulesCore.SIDE_OPP].hand = [_card(RulesCore.TYPE_TEZIS, "Удержал")]
	model.sides[RulesCore.SIDE_OPP].draw = []
	model.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, false, 0)
	model.clinch_submit("play", true, 0)
	return model.clinch_submit("pass")


func _check_stall_reasons() -> void:
	var voluntary := _stall_result(true)
	var exhausted := _stall_result(false)
	_check(not bool(voluntary.get("landed", true)) and
		String(voluntary.get("stop_reason", "")) == "voluntary",
		"атакующий с доступным продолжением может осознанно остановить клинч без forced stall")
	_check(not bool(exhausted.get("landed", true)) and
		String(exhausted.get("stop_reason", "")) == "exhausted",
		"отсутствие следующей атаки помечается отдельным stop_reason=exhausted")


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures += 1
