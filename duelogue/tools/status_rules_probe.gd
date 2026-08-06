extends Node

## DUELOGUE — STATUS RULES PROBE (фундамент пилота перков/дебафов v0.1, брейншторм-сессия):
## проверяет status_rules.gd (жизненный цикл записи: apply/remove/tick_turn/active_for) и
## zal_status_bridge.gd (единственный подключённый коннектор пилота) headless, без UI и без
## боевого runtime — сверяет ровно то, что обсуждалось: 6 ячеек durability×source из
## StatusRegistry.CATALOG, симметрию по сторонам и реальную запись в rules_core.zal().
##
## Изолирован: не подключается к battle_controller/сцене боя.
## Запуск: res://duelogue/tools/status_rules_probe.tscn, F6 (или headless).

const StatusRegistry := preload("res://duelogue/core/status/status_registry.gd")
const StatusRules := preload("res://duelogue/core/status/status_rules.gd")
const ZalBridge := preload("res://duelogue/core/status/zal_status_bridge.gd")
const RulesCore := preload("res://duelogue/core/rules/rules_core.gd")

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("\n=== STATUS RULES PROBE ===")
	_check_lifecycle_fundamental()
	_check_lifecycle_base()
	_check_lifecycle_temporary()
	_check_source_axis_is_orthogonal()
	_check_active_for_filters_by_target_system()
	_check_symmetry_both_sides()
	_check_zal_bridge_math()
	_check_zal_bridge_writes_into_model()
	_check_unknown_status_rejected()
	print("=== STATUS RULES PROBE: %s ===\n" % (
		"OK" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures += 1


## Фундаментальный: применяется один раз, повторный apply — отказ, remove — всегда отказ.
func _check_lifecycle_fundamental() -> void:
	var state := StatusRules.new_state()
	var applied := StatusRules.apply(state, "you", "unbending", 0)
	_check(bool(applied.ok), "fundamental: первый apply(unbending) проходит")
	_check(StatusRules.has_status(state, "you", "unbending"),
		"fundamental: has_status видит применённый статус")
	var reapplied := StatusRules.apply(state, "you", "unbending", 1)
	_check(not bool(reapplied.ok) and String(reapplied.reason) == "already_applied",
		"fundamental: повторный apply отказан (already_applied)")
	var removed := StatusRules.remove(state, "you", "unbending")
	_check(not bool(removed.ok) and String(removed.reason) == "fundamental_cannot_be_removed",
		"fundamental: remove отказан (fundamental_cannot_be_removed)")
	_check(StatusRules.has_status(state, "you", "unbending"),
		"fundamental: статус остался активным после неудачного remove")


## Основной: стартует, может быть переприменён (обновляет applied_turn) и свободно снят.
func _check_lifecycle_base() -> void:
	var state := StatusRules.new_state()
	StatusRules.apply(state, "you", "prepared_opening", 0)
	_check(StatusRules.has_status(state, "you", "prepared_opening"),
		"base: apply(prepared_opening) активен")
	var reapplied := StatusRules.apply(state, "you", "prepared_opening", 5)
	_check(bool(reapplied.ok) and int(reapplied.entry.applied_turn) == 5,
		"base: повторный apply обновляет applied_turn, не отказывает")
	var removed := StatusRules.remove(state, "you", "prepared_opening")
	_check(bool(removed.ok), "base: remove проходит")
	_check(not StatusRules.has_status(state, "you", "prepared_opening"),
		"base: статус реально снят")


## Временный: тикает заданное число ходов, истекает сам, повторный apply освежает срок.
func _check_lifecycle_temporary() -> void:
	var state := StatusRules.new_state()
	StatusRules.apply(state, "you", "ovation", 0)  # turns=2 в каталоге
	var entry: Dictionary = StatusRules.list_active(state, "you")[0]
	_check(int(entry.remaining_turns) == 2, "temporary: стартует с remaining_turns из каталога")
	var t1 := StatusRules.tick_turn(state, "you")
	_check((t1.expired as Array).is_empty(), "temporary: через 1 тик ещё не истёк")
	_check(StatusRules.has_status(state, "you", "ovation"), "temporary: всё ещё активен после 1 тика")
	# Освежить срок посреди жизни статуса — должен вернуться к полному duration, не копиться.
	StatusRules.apply(state, "you", "ovation", 1)
	var refreshed: Dictionary = StatusRules.list_active(state, "you")[0]
	_check(int(refreshed.remaining_turns) == 2, "temporary: повторный apply освежает remaining_turns")
	StatusRules.tick_turn(state, "you")
	var t2 := StatusRules.tick_turn(state, "you")
	_check((t2.expired as Array) == ["ovation"], "temporary: истекает ровно на 2-м тике после освежения")
	_check(not StatusRules.has_status(state, "you", "ovation"), "temporary: снят из активных после истечения")


## source (outgoing/incoming) — это только разметка каталога, не отдельная логика
## жизненного цикла: обе оси независимы (durability решает apply/remove/tick, source никак
## на это не влияет, только присутствует в CATALOG-записи для будущего чтения/UI).
func _check_source_axis_is_orthogonal() -> void:
	var state := StatusRules.new_state()
	StatusRules.apply(state, "you", "tainted_name", 0)   # fundamental + incoming
	StatusRules.apply(state, "opp", "rumor_hit", 0)      # base + incoming
	var you_entry: Dictionary = StatusRules.list_active(state, "you")[0]
	var opp_entry: Dictionary = StatusRules.list_active(state, "opp")[0]
	_check(String(you_entry.source) == StatusRegistry.SOURCE_INCOMING,
		"source: incoming-разметка читается корректно (fundamental)")
	_check(String(opp_entry.source) == StatusRegistry.SOURCE_INCOMING,
		"source: incoming-разметка читается корректно (base)")


func _check_active_for_filters_by_target_system() -> void:
	var state := StatusRules.new_state()
	StatusRules.apply(state, "you", "unbending", 0)
	var zal_hits := StatusRules.active_for(state, "you", "zal")
	var other_hits := StatusRules.active_for(state, "you", "emotion")
	_check(zal_hits.size() == 1 and String(zal_hits[0].id) == "unbending",
		"active_for: находит статус по правильному target_system")
	_check(other_hits.is_empty(), "active_for: не возвращает статус для чужой системы")


func _check_symmetry_both_sides() -> void:
	var state := StatusRules.new_state()
	StatusRules.apply(state, "you", "unbending", 0)
	StatusRules.apply(state, "opp", "tainted_name", 0)
	_check(StatusRules.has_status(state, "you", "unbending") and
		not StatusRules.has_status(state, "opp", "unbending"),
		"symmetry: статус you не просачивается на opp")
	_check(StatusRules.has_status(state, "opp", "tainted_name") and
		not StatusRules.has_status(state, "you", "tainted_name"),
		"symmetry: статус opp не просачивается на you")


func _check_zal_bridge_math() -> void:
	var state := StatusRules.new_state()
	StatusRules.apply(state, "you", "unbending", 0)      # +1 you
	StatusRules.apply(state, "you", "prepared_opening", 0)  # +1 you
	StatusRules.apply(state, "opp", "tainted_name", 0)   # -1 opp (payload value already -1)
	# you-вклад: +1+1=2, opp-вклад: -1 → compute = you(2) - opp(-1) = 3.
	var computed := ZalBridge.compute(state, "you", "opp")
	_check(computed == 3, "bridge: compute суммирует несколько статусов по обеим сторонам (ожидали 3, вышло %d)" % computed)


func _check_zal_bridge_writes_into_model() -> void:
	var model := RulesCore.new()
	model.reset(RulesCore.SIDE_YOU, 3, 8, 9)
	var before := model.zal()
	_check(model.status_zal_bias == 0, "model: status_zal_bias стартует нулём после reset()")
	var state := StatusRules.new_state()
	StatusRules.apply(state, "you", "booed", 0)  # temporary incoming, value -1 на you
	ZalBridge.apply_to_model(state, model, RulesCore.SIDE_YOU, RulesCore.SIDE_OPP)
	_check(model.status_zal_bias == -1, "bridge: apply_to_model записывает пересчитанное значение")
	var after := model.zal()
	_check(after == before - 1,
		"bridge: zal() реально сдвигается на статус-вклад (было %d, стало %d)" % [before, after])
	# Мост не трогает "органический" zal_bias (dirty-приёмы) — оба жёлоба складываются, не
	# перезаписывают друг друга.
	model.zal_bias += 2
	ZalBridge.apply_to_model(state, model, RulesCore.SIDE_YOU, RulesCore.SIDE_OPP)
	_check(model.zal_bias == 2 and model.status_zal_bias == -1,
		"bridge: повторный apply_to_model не трогает органический zal_bias")


func _check_unknown_status_rejected() -> void:
	var state := StatusRules.new_state()
	var result := StatusRules.apply(state, "you", "does_not_exist", 0)
	_check(not bool(result.ok) and String(result.reason) == "unknown_status",
		"registry: apply неизвестного id отказан (unknown_status)")
