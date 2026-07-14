extends "res://duelogue/app/battle_controller.gd"

## Интеграционный smoke: BattleController действительно проводит реакционную реплику,
## но эмоциональное ядро v0.2 ни на байт не меняет rules_core.

var failures := 0
var spoken: Array = []


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
	var rally_model_before := JSON.stringify(model.sides)
	await _emotion_clinch_round(SIDE_YOU, SIDE_OPP, "тестовая рамка")
	_check(int(emotion_state(SIDE_YOU).strain) == 1 and
		int(emotion_state(SIDE_OPP).strain) == 1,
		"завершённый раунд клинча нагревает обе стороны")
	_check(JSON.stringify(model.sides) == rally_model_before,
		"эмоциональное давление клинча не меняет rules_core")

	start_match()
	_check(int(emotion_state(SIDE_YOU).strain) == 0 and
		int(emotion_state(SIDE_OPP).strain) == 0,
		"новый матч сбрасывает обе шкалы")
	_finish()


func _say(side: String, text: String, tag: String = "", card_type: String = "",
	steals: bool = false, mood: String = "", extra_meta: Dictionary = {}) -> void:
	spoken.append({"side": side, "text": text, "tag": tag, "card_type": card_type,
		"steals": steals, "mood": mood, "meta": extra_meta.duplicate(true)})


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
