extends "res://duelogue/app/battle_controller.gd"

## Интеграционный smoke «Выпада» (context/situational_cards_v0.1.md §3): BattleController
## уводит защитника-игрока в режим "lunge" на открытом LINK и переводит выбор модалки в
## решение _clinch_decided. Ядровые ветки clinch_submit (lunge_counter/lunge_yield) —
## в battle_loop_rules_smoke.gd; гейт оффера — в lunge_choice_smoke.gd.
## Запуск:
##   Godot --headless --path . res://duelogue/tools/lunge_controller_smoke.tscn

const RC := preload("res://duelogue/core/rules/rules_core.gd")

var failures := 0
var _ask_result: Dictionary = {}
var _ask_done := false
var _sig_started: Array = []
var _sig_resolved: Array = []


func _ready() -> void:
	super._ready()
	logging_enabled = false
	ReadingPace.CUTSCENES = false
	EventBus.lunge_started.connect(func(defender, route): _sig_started.append([defender, route]))
	EventBus.lunge_resolved.connect(func(pick): _sig_resolved.append(pick))
	start_match()
	call_deferred("_run")


func _run() -> void:
	print("\n=== LUNGE CONTROLLER SMOKE ===")
	await _case("guard", "play", false, true)
	await _case("counter", "lunge_counter", true, true)
	await _case("yield", "lunge_yield", false, false)
	print("=== LUNGE CONTROLLER: %s ===\n" % ("OK" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures += 1


func _eligible_thesis(scheme: String, tid: String) -> Dictionary:
	return {"type": RC.TYPE_TEZIS, "name": "T:" + scheme, "scheme": scheme,
		"thesis_id": tid, "stolen": false, "combo_eligible": true, "steals": false}


func _frame_with(scheme: String, prefix: String) -> Dictionary:
	var t := _eligible_thesis(scheme, prefix + "_0")
	return {"theses": 1, "closed": false, "name": prefix, "stolen": 0,
		"claim_id": prefix, "claim": "claim " + prefix,
		"thesis_stack": [t], "statements": [{"thesis_id": t.thesis_id, "text": "s"}]}


## OPP бьёт рамку YOU ⚡-Разбором «Источник?» → маршрут source_backed (Авторитет+"источник"),
## карта-ответ — «Статистика». Рука защитника: [ответ, тезис-мимо, Кража].
func _setup_link() -> void:
	start_match()
	_epoch += 1   ## гасим отложенные корутины стартового хода до ручной раскладки
	model.sides[SIDE_OPP].lines = [_frame_with("Здравый смысл", "opp_active")]
	model.sides[SIDE_YOU].lines = [_frame_with("Авторитет", "you_tgt")]
	model.sides[SIDE_OPP].hand = [{"type": RC.TYPE_RAZBOR, "name": "Опенер",
		"device": "Источник?", "hook": "источник", "combo_eligible": true, "steals": false}]
	model.sides[SIDE_OPP].draw = []
	model.sides[SIDE_YOU].hand = [
		_eligible_thesis("Статистика", "ans"),
		{"type": RC.TYPE_TEZIS, "name": "Тезис-мимо", "scheme": "Эмоция", "steals": false},
		{"type": RC.TYPE_RAZBOR, "name": "Кража", "steals": true},
	]
	model.sides[SIDE_YOU].draw = []
	model.begin_clinch(SIDE_OPP, SIDE_YOU, 0, false, 0)


func _run_ask() -> void:
	_ask_result = await _ask_clinch("defend")
	_ask_done = true


func _case(kind: String, want_act: String, want_steals: bool, want_hand_index: bool) -> void:
	_setup_link()
	_check(String(model.clinch.get("combo_state", "")) == "link",
		"[%s] клинч на открытом LINK" % kind)
	_ask_done = false
	_sig_started.clear()
	_sig_resolved.clear()
	_run_ask()   ## корутина: доходит до await _clinch_decided внутри _ask_lunge и повисает
	for _i in 30:
		if _mode == "lunge":
			break
		await get_tree().process_frame
	_check(_sig_started.size() == 1 and String((_sig_started[0] as Array)[0]) == "you",
		"[%s] EventBus.lunge_started эмитнут для защитника-игрока" % kind)
	var offer: Dictionary = lunge_offer()
	_check(_mode == "lunge" and bool(offer.get("active", false))
		and int(offer.get("answer_index", -1)) == 0
		and int(offer.get("decoy_index", -1)) == 1
		and int(offer.get("steal_index", -1)) == 2,
		"[%s] _ask_clinch ушёл в lunge, оффер собрал все три слота" % kind)
	lunge_pick(kind)
	for _i in 30:
		if _ask_done:
			break
		await get_tree().process_frame
	var d: Dictionary = _ask_result
	var ok := String(d.get("act", "")) == want_act
	if want_hand_index:
		ok = ok and int(d.get("hand_index", -99)) >= 0
	else:
		ok = ok and int(d.get("hand_index", 0)) == -1
	if want_steals:
		ok = ok and bool(d.get("steals", false))
	_check(ok, "[%s] решение act=%s hand_index=%d steals=%s" % [
		kind, d.get("act", ""), int(d.get("hand_index", -1)), d.get("steals", false)])
	_check(_mode == "locked", "[%s] режим вернулся в locked после выбора" % kind)
	_check(_sig_resolved.size() == 1 and String(_sig_resolved[0]) == kind,
		"[%s] EventBus.lunge_resolved эмитнут с pick=%s" % [kind, kind])
	if not model.clinch.is_empty():
		model.clinch_submit("pass")
