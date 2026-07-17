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


class ScriptedDefenseAi:
	extends RefCounted
	func def_will_clinch(_model: RefCounted, _side: String, _line: Dictionary) -> bool:
		return true


var failures := 0
var spoken: Array = []
var emotion_event_calls: Array = []
var clinch_decisions: Array = []
var emitted_events: Array = []


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

	# Точная регрессия плейтеста: открывающая Кража погашена T лишь временно. Обычный
	# Разбор сносит exact T в сброс (кражу он НЕ наследует), после чего перестоявшая
	# Кража доигрывает по рамке: толщина 2 вне reach 1 — захват блокирован, украден
	# верхний тезис. Реплика без thesis_id (sentinel) при этом остаётся на рамке.
	start_match()
	spoken.clear()
	emotion_event_calls.clear()
	emitted_events.clear()
	model.sides[SIDE_YOU].hand = [
		{"type": TYPE_RAZBOR, "name": "Кража", "steals": true},
		{"type": TYPE_RAZBOR, "name": "Финальный Разбор", "steals": false},
	]
	model.sides[SIDE_YOU].draw = []
	model.sides[SIDE_OPP].hand = [{"type": TYPE_TEZIS, "name": "Ответный тезис"}]
	model.sides[SIDE_OPP].draw = []
	model.sides[SIDE_OPP].lines[0]["theses"] = 2
	model.sides[SIDE_OPP].lines[0]["statements"] = [
		{"text": "Базовая реплика", "axis": "base", "device": "sentinel"},
	]
	clinch_decisions = [{"act": "play", "steals": false, "hand_index": 0}]
	regular_ai = ai
	ai = ScriptedDefenseAi.new()
	await _run_clinch(SIDE_YOU, SIDE_OPP, 0, true, 0)
	ai = regular_ai
	var clinch_event: Dictionary = {}
	for event in emitted_events:
		if String((event as Dictionary).get("ev", "")) == "clinch":
			clinch_event = event
	_check(not clinch_event.is_empty() and not clinch_event.get("captured", false) and
		bool(clinch_event.get("capture_blocked", false)) and
		int(clinch_event.get("stolen_count", 0)) == 1 and
		String(clinch_event.get("landing_effect", "")) == "steal_thesis" and
		String(clinch_event.get("landing_target_kind", "")) == "frame" and
		int(model.sides[SIDE_OPP].lines[0].theses) == 1 and
		(model.sides[SIDE_OPP].lines[0].statements as Array).size() == 1 and
		String(model.sides[SIDE_OPP].lines[0].statements[0].device) == "sentinel",
		"контроллер: R сносит exact T в сброс, перестоявшая Кража крадёт верхний тезис рамки")

	# Объектная ловушка в реальном контроллере: S–T1–R–T2 крадёт T1 из середины,
	# поэтому его statement исчезает, а более поздний T2 остаётся верхней репликой.
	start_match()
	spoken.clear()
	emotion_event_calls.clear()
	emitted_events.clear()
	model.sides[SIDE_YOU].hand = [
		{"type": TYPE_RAZBOR, "name": "Сократический вопрос", "steals": false,
			"named": "socratic", "clinch": true},
		{"type": TYPE_RAZBOR, "name": "R2", "steals": false},
	]
	model.sides[SIDE_YOU].draw = []
	model.sides[SIDE_OPP].hand = [
		{"type": TYPE_TEZIS, "name": "T1"},
		{"type": TYPE_TEZIS, "name": "T3"},
	]
	model.sides[SIDE_OPP].draw = []
	model.sides[SIDE_OPP].lines[0]["statements"] = [
		{"text": "Базовая реплика", "axis": "base", "device": "sentinel"},
	]
	clinch_decisions = [{"act": "play", "steals": false, "hand_index": 0}]
	regular_ai = ai
	ai = ScriptedDefenseAi.new()
	await _run_clinch(SIDE_YOU, SIDE_OPP, 0, false, 0)
	ai = regular_ai
	var soc_event: Dictionary = {}
	for event in emitted_events:
		if String((event as Dictionary).get("ev", "")) == "clinch":
			soc_event = event
	var soc_seq: Array = soc_event.get("sequence", [])
	var soc_statements: Array = model.sides[SIDE_OPP].lines[0].get("statements", [])
	_check(bool(soc_event.get("socratic", false)) and soc_seq.size() == 4 and
		String(soc_seq[1].get("result", "")) == "stolen_by_socratic" and
		String(soc_seq[3].get("result", "")) == "held" and soc_statements.size() == 2 and
		String(soc_statements[0].get("device", "")) == "sentinel" and
		String(soc_statements[1].get("thesis_id", "")) ==
			String(soc_seq[3].get("thesis_id", "")),
		"контроллер: Сократик удаляет statement T1 по thesis_id и оставляет T2")

	# Именной chip обязан пользоваться тем же мостом object→statement, что и clinch.
	# Два обычных T сначала получают реальные thesis_id и реплики, затем Ad hominem
	# снимает оба объекта; ghost-реплик на рамке остаться не должно.
	start_match()
	spoken.clear()
	emotion_event_calls.clear()
	emitted_events.clear()
	model.sides[SIDE_OPP].hand = [
		{"type": TYPE_TEZIS, "name": "T-названный 1"},
		{"type": TYPE_TEZIS, "name": "T-названный 2"},
	]
	model.sides[SIDE_OPP].draw = []
	var named_t1: Dictionary = model.play_action(SIDE_OPP, TYPE_TEZIS, -1, 0)
	await _log_action(named_t1)
	var named_t2: Dictionary = model.play_action(SIDE_OPP, TYPE_TEZIS, -1, 0)
	await _log_action(named_t2)
	model.sides[SIDE_YOU].hand = [
		{"type": TYPE_RAZBOR, "name": "Ad hominem", "steals": false,
			"named": "ad_hominem", "clinch": false},
	]
	model.sides[SIDE_YOU].draw = []
	var ad_card: Dictionary = model.sides[SIDE_YOU].hand[0].duplicate(true)
	var ad_info: Dictionary = model.play_named(SIDE_YOU, 0, 0)
	await _log_named(SIDE_YOU, ad_card, ad_info)
	_check((ad_info.get("removed_thesis_ids", []) as Array).size() == 2 and
		(model.sides[SIDE_OPP].lines[0].get("statements", []) as Array).is_empty() and
		int(model.sides[SIDE_OPP].lines[0].theses) == 1,
		"контроллер: named chip удаляет точные statements двух затронутых thesis_id")

	# Именной T сам создаёт связанный statement. Следующий обычный R снимает тот же объект,
	# и общий sync удаляет именно эту реплику.
	start_match()
	spoken.clear()
	emotion_event_calls.clear()
	emitted_events.clear()
	model.sides[SIDE_YOU].hand = [
		{"type": TYPE_TEZIS, "name": "Перенос бремени", "steals": false,
			"named": "burden_shift", "clinch": false},
	]
	model.sides[SIDE_YOU].draw = []
	var burden_card: Dictionary = model.sides[SIDE_YOU].hand[0].duplicate(true)
	var burden_info: Dictionary = model.play_named(SIDE_YOU, 0, -1)
	await _log_named(SIDE_YOU, burden_card, burden_info)
	var burden_statements: Array = model.sides[SIDE_YOU].lines[0].get("statements", [])
	var burden_id := String(burden_info.get("thesis_id", ""))
	var burden_bound: bool = burden_statements.size() == 1 and burden_id != "" and \
		String(burden_statements[0].get("thesis_id", "")) == burden_id
	model.sides[SIDE_OPP].hand = [
		{"type": TYPE_RAZBOR, "name": "Снять бремя", "steals": false},
	]
	model.sides[SIDE_OPP].draw = []
	model.sides[SIDE_YOU].hand = []
	model.sides[SIDE_YOU].draw = []
	emitted_events.clear()
	await _run_clinch(SIDE_OPP, SIDE_YOU, 0, false, 0)
	var burden_event: Dictionary = {}
	for event in emitted_events:
		if String((event as Dictionary).get("ev", "")) == "clinch":
			burden_event = event
	_check(burden_bound and String(burden_event.get("affected_thesis_id", "")) == burden_id and
		(model.sides[SIDE_YOU].lines[0].get("statements", []) as Array).is_empty() and
		int(model.sides[SIDE_YOU].lines[0].theses) == 1,
		"контроллер: Burden Shift и следующий R разделяют один thesis_id без ghost-реплики")

	# Контролируемый отход и вынужденное исчерпание выглядят одинаково на доске (защита
	# устояла), но различаются для самоконтроля. Сохранённая атака делает «Остановиться»
	# осознанным решением: эмоциональной проверки быть не должно.
	start_match()
	spoken.clear()
	emotion_event_calls.clear()
	model.sides[SIDE_YOU].hand = [
		{"type": TYPE_RAZBOR, "name": "первый нажим", "steals": false},
		{"type": TYPE_RAZBOR, "name": "сохранённый нажим", "steals": false},
	]
	model.sides[SIDE_YOU].draw = []
	model.sides[SIDE_OPP].hand = [{"type": TYPE_TEZIS, "name": "защита"}]
	model.sides[SIDE_OPP].draw = []
	clinch_decisions = [{"act": "pass"}]
	regular_ai = ai
	ai = ScriptedDefenseAi.new()
	await _run_clinch(SIDE_YOU, SIDE_OPP, 0, false)
	ai = regular_ai
	_check(emotion_event_calls.is_empty(),
		"добровольное «Остановиться» при сохранённой атаке не повышает strain")

	# Та же защита, но после первого удара атак в руке не осталось: автомат клинча
	# помечает exhausted, а контроллер единожды отправляет attack_stalled проигравшему.
	start_match()
	spoken.clear()
	emotion_event_calls.clear()
	model.sides[SIDE_YOU].hand = [
		{"type": TYPE_RAZBOR, "name": "последний нажим", "steals": false},
	]
	model.sides[SIDE_YOU].draw = []
	model.sides[SIDE_OPP].hand = [{"type": TYPE_TEZIS, "name": "защита"}]
	model.sides[SIDE_OPP].draw = []
	clinch_decisions.clear()
	regular_ai = ai
	ai = ScriptedDefenseAi.new()
	await _run_clinch(SIDE_YOU, SIDE_OPP, 0, false)
	ai = regular_ai
	_check(emotion_event_calls.size() == 1 and
		String((emotion_event_calls[0] as Dictionary).side) == SIDE_YOU and
		String((emotion_event_calls[0] as Dictionary).stimulus) == "attack_stalled",
		"вынужденное исчерпание атаки даёт ровно одну проверку attack_stalled")

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


func _emit(data: Dictionary) -> void:
	emitted_events.append(data.duplicate(true))


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
