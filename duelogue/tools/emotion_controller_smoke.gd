extends "res://duelogue/app/battle_controller.gd"

## Интеграционный smoke: BattleController действительно проводит реакционную реплику,
## но эмоциональное ядро v0.2 ни на байт не меняет rules_core.

class ScriptedClinchAi:
	extends RefCounted
	func atk_will_clinch(_model: RefCounted, _side: String, _line: Dictionary) -> bool:
		return true

	func atk_prefer_steal(_model: RefCounted, _side: String, _defender: String,
		_target: int) -> bool:
		return false


var failures := 0
var spoken: Array = []
var emotion_event_calls: Array = []
var clinch_decisions: Array = []


func _ready() -> void:
	super._ready()
	ReadingPace.CUTSCENES = false
	start_match()
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	# Подводим шкалу к гарантированному срыву контролируемым roll, затем второй stimulus
	# идёт через настоящий интеграционный шов контроллера.
	emotion.observe(SIDE_YOU, "argument_lost", 3, {"target": "тест"}, 0.99)
	var model_before := JSON.stringify(model.sides)
	var turn_before: int = int(model.turn_count)
	var zal_before: int = int(model.zal())
	await _emotion_event(SIDE_YOU, "frame_lost", 3, {"target": "тестовая рамка"})
	_check(spoken.size() == 2 and bool((spoken[0] as Dictionary).meta.get("reaction", false)),
		"контроллер подал отдельную реакционную реплику")
	_check(String((spoken[1] as Dictionary).side) == SIDE_OPP and
		String((spoken[1] as Dictionary).meta.get("reaction_kind", "")) == "parry",
		"спокойный оппонент немедленно парирует срыв")
	_check(int(emotion_state(SIDE_OPP).strain) == 0 and
		int(emotion_state(SIDE_OPP).reactions) == 0,
		"спокойная парировка не тратит шкалу или реакционную карту")
	_check(int(emotion_state(SIDE_YOU).reactions) == 1,
		"контроллер читает состояние эмоционального ядра")
	_check(JSON.stringify(model.sides) == model_before and model.turn_count == turn_before and
		model.zal() == zal_before,
		"реакция не меняет доску, руку, ход или зал")

	start_match()
	spoken.clear()
	emotion.observe(SIDE_YOU, "argument_lost", 3, {}, 0.99)
	emotion.observe(SIDE_OPP, "argument_lost", 5, {}, 0.99)
	var chain_model_before := JSON.stringify(model.sides)
	await _emotion_event(SIDE_YOU, "frame_lost", 3, {"target": "цепная рамка"})
	_check(spoken.size() == 2 and
		String((spoken[1] as Dictionary).meta.get("reaction_kind", "")) == "counter_burst",
		"сторона на 5/6 отвечает собственной реакционной картой")
	_check(int(emotion_state(SIDE_OPP).reactions) == 1,
		"чужой срыв связал вторую шкалу с субколодой")
	_check(JSON.stringify(model.sides) == chain_model_before,
		"цепная эмоциональная реакция не меняет rules_core")

	start_match()
	spoken.clear()
	emotion_event_calls.clear()
	# Настоящий затяжной клинч: игрок один раз защищается, AI один раз дожимает, затем
	# защита кончается. Даже после полной пары только проигравший получает одну проверку
	# уже закрытого исхода; mid-rally проверки сразу сделают этот счётчик > 1.
	model.sides[SIDE_YOU].hand = [
		{"type": TYPE_TEZIS, "name": "защита"},
	]
	model.sides[SIDE_OPP].hand = [
		{"type": TYPE_RAZBOR, "name": "удар 1", "steals": false},
		{"type": TYPE_RAZBOR, "name": "удар 2", "steals": false},
	]
	clinch_decisions = [{"act": "play", "steals": false, "hand_index": 0}]
	var regular_ai := ai
	ai = ScriptedClinchAi.new()
	await _run_clinch(SIDE_OPP, SIDE_YOU, 0, false)
	ai = regular_ai
	_check(emotion_event_calls.size() == 1 and
		String((emotion_event_calls[0] as Dictionary).side) == SIDE_YOU,
		"затяжной клинч проверяет один раз только проигравшего после исхода")
	_check(String((emotion_event_calls[0] as Dictionary).stimulus) in [
		"argument_lost", "frame_lost", "captured", "attack_stalled"],
		"проверка получает уже разрешённый исход, а не шум ралли")

	start_match()
	_check(int(emotion_state(SIDE_YOU).strain) == 0 and
		int(emotion_state(SIDE_OPP).strain) == 0,
		"новый матч сбрасывает обе шкалы")
	_finish()


func _say(side: String, text: String, tag: String = "", card_type: String = "",
	steals: bool = false, mood: String = "", extra_meta: Dictionary = {}) -> void:
	spoken.append({"side": side, "text": text, "tag": tag, "card_type": card_type,
		"steals": steals, "mood": mood, "meta": extra_meta.duplicate(true)})


func _emotion_event(side: String, stimulus: String, intensity: int,
	context: Dictionary = {}) -> Dictionary:
	emotion_event_calls.append({"side": side, "stimulus": stimulus, "intensity": intensity})
	return await super._emotion_event(side, stimulus, intensity, context)


func _ask_clinch(_mode_name: String) -> Dictionary:
	if clinch_decisions.is_empty():
		return {"act": "pass"}
	return clinch_decisions.pop_front()


func _emit(_data: Dictionary) -> void:
	pass


func _tx_write(_line: String) -> void:
	pass


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures += 1


func _finish() -> void:
	print("=== EMOTION CONTROLLER: %s ===" % ("OK" if failures == 0 else "FAIL (%d)" % failures))
	var code := 0 if failures == 0 else 1
	queue_free()
	get_tree().call_deferred("quit", code)
