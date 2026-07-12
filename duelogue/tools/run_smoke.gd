extends Node

## ЗАБЕГ v0.1 — SMOKE-ПРОГОН ЯДРА СЛОЯ (без UI). Три проверки:
## (1) свип генерации карт по сидам × актам: валидатор DAG + распределение типов комнат;
## (2) ASCII-печать одной карты — глазами посмотреть форму графа;
## (3) автопрохождение забегов контроллером: win-путь → victory, lose-путь → defeated
##     на четвёртом поражении (репутация при этом считается независимо по финальному залу).
## Запуск: сцена run_smoke.tscn (F6) или headless:
##   Godot --headless --path . res://duelogue/tools/run_smoke.tscn

const RunMap := preload("res://duelogue/core/run/run_map.gd")
const RoomTypes := preload("res://duelogue/core/run/room_types.gd")
const RunEvents := preload("res://duelogue/core/run/run_events.gd")
const RunState := preload("res://duelogue/core/run/run_state.gd")
const RunRules := preload("res://duelogue/core/run/run_rules.gd")
const RunController := preload("res://duelogue/app/run_controller.gd")

const SWEEP_SEEDS := 300

var _fails := 0


func _ready() -> void:
	await get_tree().process_frame
	print("\n=== ЗАБЕГ v0.1 · SMOKE ЯДРА СЛОЯ ===")
	_sweep()
	_rules_checks()
	_print_ascii(7, 1)
	await _auto_run(7, true)
	await _auto_run(11, false)
	print("\n=== ИТОГ: %s ===\n" % ("OK" if _fails == 0 else "FAIL ×%d" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		_fails += 1


## Чистые переходы мета-ядра без карты/контроллера.
func _rules_checks() -> void:
	print("\n--- Мета-ядро run_rules ---")
	_check(is_equal_approx(RunRules.reputation_delta("you", 5.0), 5.0),
		"победа при +5 → репутация +5")
	_check(is_equal_approx(RunRules.reputation_delta("opp", 5.0), 2.5),
		"поражение при +5 → репутация +2.5")
	_check(is_equal_approx(RunRules.reputation_delta("you", -5.0), -2.5),
		"победа при −5 → репутация −2.5")

	var cap_state := RunState.new()
	cap_state.reputation = 48.0
	var cap := RunRules.apply_reputation_delta(cap_state, 7.0)
	_check(is_equal_approx(cap_state.reputation, 50.0) and is_equal_approx(float(cap.overflow), 5.0),
		"переполнение +55 → +50, забыто 5")

	var loss_state := RunState.new()
	for i in 3:
		var r := RunRules.settle_battle(loss_state,
			{"winner": "opp", "end_reason": "test", "final_zal": -1, "fee": 3})
		_check(bool(r.ok) and not bool(r.run_failed), "поражение %d пережито" % (i + 1))
	var fourth := RunRules.settle_battle(loss_state,
		{"winner": "opp", "end_reason": "test", "final_zal": -1, "fee": 3})
	_check(bool(fourth.run_failed) and loss_state.defeat_marks == 3 and loss_state.outcome == "defeated",
		"четвёртое поражение завершает забег")

	var buy_state := RunState.new()
	buy_state.defeat_marks = 1
	buy_state.fees = 5
	var poor := RunRules.clear_defeat_mark(buy_state, "fee")
	_check(not bool(poor.ok) and buy_state.fees == 5 and buy_state.defeat_marks == 1,
		"неполная оплата не меняет состояние")
	buy_state.fees = RunRules.CLEAR_MARK_FEE
	var paid := RunRules.clear_defeat_mark(buy_state, "fee")
	_check(bool(paid.ok) and buy_state.fees == 0 and buy_state.defeat_marks == 0,
		"очистка за гонорар атомарна")
	buy_state.defeat_marks = 1
	buy_state.reputation = 0.0
	var cringe := RunRules.clear_defeat_mark(buy_state, "rep")
	_check(bool(cringe.ok) and is_equal_approx(buy_state.reputation, -10.0) \
		and buy_state.defeat_marks == 0, "очистка за репутацию атомарна")


func _cfg(run_seed: int, act: int) -> Dictionary:
	return {
		"seed": run_seed, "act": act,
		"layers": RunController.LAYERS_PER_ACT,
		"lanes_min": RunController.LANES_MIN, "lanes_max": RunController.LANES_MAX,
		"themes": [{"id": "stub", "topic": "Тестовая тема"}],
		"opps": RunController.OPP_POOL,
		"bosses": [RunController.BOSS_POOL[(act - 1) % RunController.BOSS_POOL.size()]],
		"events": RunEvents.pool(),
	}


# --- (1) свип генерации ---

func _sweep() -> void:
	var type_counts := {}
	var err_count := 0
	var maps := 0
	for s in SWEEP_SEEDS:
		for act in range(1, 4):
			var map := RunMap.generate(_cfg(s, act))
			maps += 1
			var errs: Array = RunMap.validate(map)
			if not errs.is_empty():
				err_count += 1
				if err_count <= 5:
					print("  ОШИБКА сид=%d акт=%d: %s" % [s, act, ", ".join(errs)])
			for id in map.nodes:
				var t: String = map.nodes[id].type
				type_counts[t] = int(type_counts.get(t, 0)) + 1
	var total := 0
	for t in type_counts:
		total += int(type_counts[t])
	print("\n--- Свип генерации: %d карт (%d сидов × 3 акта) ---" % [maps, SWEEP_SEEDS])
	print("  карт с ошибками валидации: %d %s" % [err_count, "· OK" if err_count == 0 else "· FAIL"])
	if err_count > 0:
		_fails += 1
	var order := [RoomTypes.ROOM_EFIR, RoomTypes.ROOM_ELITE, RoomTypes.ROOM_EVENT,
		RoomTypes.ROOM_SHOP, RoomTypes.ROOM_PREP, RoomTypes.ROOM_BOSS]
	for t in order:
		var n := int(type_counts.get(t, 0))
		print("  %-18s %5d узлов · %4.1f%%" % [RoomTypes.LABELS[t], n, 100.0 * n / total])


# --- (2) ASCII-карта ---

func _print_ascii(run_seed: int, act: int) -> void:
	var map := RunMap.generate(_cfg(run_seed, act))
	print("\n--- Карта: сид=%d акт=%d (id:глиф → цели) ---" % [run_seed, act])
	for l in int(map.layers):
		var row := "  слой %d: " % l
		for id in map.nodes:
			var nd: Dictionary = map.nodes[id]
			if int(nd.layer) != l:
				continue
			var nxt := ""
			if not (nd.next as Array).is_empty():
				var ss: Array = []
				for t in nd.next:
					ss.append(str(t))
				nxt = "→{%s}" % ",".join(ss)
			row += "%2d:%s%-10s " % [int(nd.id), RoomTypes.GLYPHS[nd.type], nxt]
		print(row)


# --- (3) автозабеги через контроллер ---

func _auto_run(run_seed: int, wins: bool) -> void:
	var ctrl: Node = RunController.new()
	add_child(ctrl)
	ctrl.start_run(run_seed)
	var st: RefCounted = ctrl.state
	var glyphs: Array = []
	var guard := 0
	while not st.over and guard < 300:
		guard += 1
		var ids: Array = st.reachable_ids()
		if ids.is_empty():
			print("  FAIL: тупик на акте %d (нет достижимых узлов)" % st.act)
			_fails += 1
			break
		ctrl.enter_node(int(ids[0]))
		var nd: Dictionary = st.node(st.current_id)
		glyphs.append(String(RoomTypes.GLYPHS[nd.type]))
		if String(nd.type) == RoomTypes.ROOM_EVENT:
			# Политика smoke: последний доступный вариант (у crisis_manager это «не стирать»),
			# чтобы all-loss действительно проверял четвёртое поражение без покупок.
			var ev := RunEvents.get_event(String(nd.event_id))
			var choices: Array = ev.get("choices", [])
			var chosen := false
			for i in range(choices.size() - 1, -1, -1):
				if bool(ctrl.event_choice_status(i).ok):
					ctrl.event_choice(i)
					chosen = true
					break
			if not chosen:
				print("  FAIL: событие без доступного выхода")
				_fails += 1
				break
		elif RoomTypes.is_battle(String(nd.type)):
			ctrl.resolve_room("win" if wins else "lose")
		else:
			ctrl.resolve_room("done")
	var expect := "victory" if wins else "defeated"
	var ok := String(st.outcome) == expect
	if not ok:
		_fails += 1
	print("\n--- Автозабег сид=%d (%s все бои) ---" % [run_seed, "выигрываем" if wins else "сливаем"])
	print("  путь: %s" % " ".join(glyphs))
	print("  исход: %s (ожидался %s) · акт %d · комнат %d · репутация %d · гонорары %d %s" % [
		st.outcome, expect, st.act, st.path.size(), st.reputation, st.fees,
		"· OK" if ok else "· FAIL"])
	remove_child(ctrl)
	ctrl.free()
