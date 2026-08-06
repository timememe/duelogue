extends RefCounted

## DUELOGUE — ЯДРО ПЕРКОВ/ДЕБАФОВ (статусов) v0.1, фундамент (брейншторм-сессия).
## Единственный источник правил жизненного цикла статуса: применить, снять, тикнуть ход,
## отдать активные записи нужной системе. Не знает НИЧЕГО о зале/эмоциях/колоде — только
## о своей записи ({id, applied_turn, remaining_turns}) и общем костяке каталога
## (durability/source/target_system). Payload статуса для него непрозрачен: отдаёт как
## есть, интерпретирует только коннектор нужной системы (см. zal_status_bridge.gd).
##
## Никаких Node/EventBus/UI/async — чистые static-функции над обычным Dictionary-состоянием
## (тот же принцип, что в run_rules.gd: логика отдельно от данных). state — произвольный
## Dictionary вида {side_key: [record, ...]}; сторона не валидируется против конкретных
## SIDE_YOU/SIDE_OPP — вызывающий код сам решает, какими ключами пользоваться.
##
## Симметрично: применимо к любой стороне матча независимо, обе стороны читаются одним и
## тем же API — это и есть «присваивается обоим оппонентам».

const StatusRegistry := preload("res://duelogue/core/status/status_registry.gd")


static func new_state() -> Dictionary:
	return {}


static func _find_index(list: Array, status_id: String) -> int:
	for i in list.size():
		if String((list[i] as Dictionary).get("id", "")) == status_id:
			return i
	return -1


## Применить статус стороне. Поведение при повторном apply того же id зависит от
## durability: fundamental — отказ (уже и так навсегда с ней), base — переприменяется
## (обновляет applied_turn), temporary — обновляет remaining_turns заново ("продлить").
static func apply(state: Dictionary, side: String, status_id: String, turn: int = 0) -> Dictionary:
	if not StatusRegistry.has(status_id):
		return {"ok": false, "reason": "unknown_status"}
	var entry := StatusRegistry.get_entry(status_id)
	var durability := String(entry.get("durability", ""))
	var list: Array = state.get(side, [])
	var idx := _find_index(list, status_id)
	if idx >= 0:
		if durability == StatusRegistry.DURABILITY_FUNDAMENTAL:
			return {"ok": false, "reason": "already_applied"}
		var record: Dictionary = list[idx]
		if durability == StatusRegistry.DURABILITY_TEMPORARY:
			record["remaining_turns"] = int(entry.get("turns", 1))
		else:
			record["applied_turn"] = turn
		state[side] = list
		return {"ok": true, "reason": "refreshed", "entry": record.duplicate()}
	var record := {
		"id": status_id,
		"applied_turn": turn,
		"remaining_turns": int(entry.get("turns", 1)) if durability == StatusRegistry.DURABILITY_TEMPORARY else -1,
	}
	list.append(record)
	state[side] = list
	return {"ok": true, "reason": "", "entry": record.duplicate()}


## Снять статус. Фундаментальные снять нельзя никаким путём — это весь смысл прочности
## "навсегда"; основные и временные снимаются свободно (временные к тому же тикают сами).
static func remove(state: Dictionary, side: String, status_id: String) -> Dictionary:
	var list: Array = state.get(side, [])
	var idx := _find_index(list, status_id)
	if idx < 0:
		return {"ok": false, "reason": "not_active"}
	var entry := StatusRegistry.get_entry(status_id)
	if String(entry.get("durability", "")) == StatusRegistry.DURABILITY_FUNDAMENTAL:
		return {"ok": false, "reason": "fundamental_cannot_be_removed"}
	list.remove_at(idx)
	state[side] = list
	return {"ok": true, "reason": ""}


## Вызывать раз на begin_turn стороны: временные статусы теряют 1 ход, истёкшие снимаются
## сами. Фундаментальные/основные remaining_turns=-1 не трогает.
static func tick_turn(state: Dictionary, side: String) -> Dictionary:
	var list: Array = state.get(side, [])
	var expired: Array = []
	var kept: Array = []
	for raw in list:
		var record: Dictionary = raw
		var remaining := int(record.get("remaining_turns", -1))
		if remaining < 0:
			kept.append(record)
			continue
		remaining -= 1
		if remaining <= 0:
			expired.append(String(record.get("id", "")))
		else:
			record["remaining_turns"] = remaining
			kept.append(record)
	state[side] = kept
	return {"expired": expired}


static func has_status(state: Dictionary, side: String, status_id: String) -> bool:
	return _find_index(state.get(side, []), status_id) >= 0


## Активные записи стороны, нацеленные на конкретную систему — то, что коннектор этой
## системы читает. Отдаёт {id, polarity, payload}; payload передаётся как есть, без
## интерпретации (её форму знает только коннектор, не это ядро).
static func active_for(state: Dictionary, side: String, target_system: String) -> Array:
	var out: Array = []
	for raw in state.get(side, []):
		var record: Dictionary = raw
		var entry := StatusRegistry.get_entry(String(record.get("id", "")))
		if entry.is_empty() or String(entry.get("target_system", "")) != target_system:
			continue
		out.append({
			"id": record.get("id", ""),
			"polarity": entry.get("polarity", ""),
			"payload": entry.get("payload", {}),
		})
	return out


## Полный человекочитаемый список — для UI/дебага, не для коннекторов (те берут active_for).
static func list_active(state: Dictionary, side: String) -> Array:
	var out: Array = []
	for raw in state.get(side, []):
		var record: Dictionary = raw
		var entry := StatusRegistry.get_entry(String(record.get("id", "")))
		out.append({
			"id": record.get("id", ""),
			"label": entry.get("label", ""),
			"polarity": entry.get("polarity", ""),
			"durability": entry.get("durability", ""),
			"source": entry.get("source", ""),
			"remaining_turns": record.get("remaining_turns", -1),
		})
	return out
