extends Node

## ЗАБЕГ v0.1 — SMOKE-ПРОГОН ЯДРА СЛОЯ (без UI). Три проверки:
## (1) свип генерации карт по сидам × актам: валидатор DAG + распределение типов комнат;
## (2) ASCII-печать одной карты — глазами посмотреть форму графа;
## (3) автопрохождение забегов контроллером: win-путь → victory, lose-путь → cancelled
##     (правила дистанции: гонорары за победы, репутация жжётся поражениями).
## Запуск: сцена run_smoke.tscn (F6) или headless:
##   Godot --headless --path . res://duelogue/tools/run_smoke.tscn

const RunMap := preload("res://duelogue/core/run/run_map.gd")
const RoomTypes := preload("res://duelogue/core/run/room_types.gd")
const RunEvents := preload("res://duelogue/core/run/run_events.gd")
const RunController := preload("res://duelogue/app/run_controller.gd")

const SWEEP_SEEDS := 300

var _fails := 0


func _ready() -> void:
	await get_tree().process_frame
	print("\n=== ЗАБЕГ v0.1 · SMOKE ЯДРА СЛОЯ ===")
	_sweep()
	_print_ascii(7, 1)
	await _auto_run(7, true)
	await _auto_run(11, false)
	print("\n=== ИТОГ: %s ===\n" % ("OK" if _fails == 0 else "FAIL ×%d" % _fails))
	get_tree().quit(1 if _fails > 0 else 0)


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
			ctrl.event_choice(0)
		elif RoomTypes.is_battle(String(nd.type)):
			ctrl.resolve_room("win" if wins else "lose")
		else:
			ctrl.resolve_room("done")
	var expect := "victory" if wins else "cancelled"
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
