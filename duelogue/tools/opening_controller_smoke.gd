extends "res://duelogue/app/battle_controller.gd"

## Интеграционный smoke opening-фазы контроллера. Переопределяет файловые логгеры,
## чтобы тест не загрязнял живую стенограмму ручных плейтестов.

var failures := 0


func _ready() -> void:
	super._ready()
	ReadingPace.CUTSCENES = false
	start_match()
	_check(input_mode() == "opening" and opening_stage() == "active",
		"контроллер начинает двухэтапный opening с выбора активной рамки")
	var options := opening_options()
	_check(options.size() == 3, "active-этап отдаёт три варианта")
	if options.is_empty():
		_finish_smoke()
		return

	var hand_before := (model.sides[SIDE_YOU].hand as Array).size()
	var draw_before := (model.sides[SIDE_YOU].draw as Array).size()
	var active_id := String(options[0].id)
	var expected_reserve_ids: Array = []
	for option in options:
		if String(option.id) != active_id:
			expected_reserve_ids.append(String(option.id))
	expected_reserve_ids.sort()
	# Первый клик только фиксирует Базу: матч ещё не стартует и предлагает две оставшиеся
	# смысловые рамки для публичной страховки в H5.
	_first_side = SIDE_YOU
	model.current = SIDE_YOU
	choose_opening(active_id)
	var reserve_options := opening_options()
	var active_was_removed := reserve_options.size() == 2
	var actual_reserve_ids: Array = []
	for option in reserve_options:
		active_was_removed = active_was_removed and String(option.id) != active_id
		actual_reserve_ids.append(String(option.id))
	actual_reserve_ids.sort()
	_check(input_mode() == "opening" and opening_stage() == "reserve" and active_was_removed and
		actual_reserve_ids == expected_reserve_ids,
		"reserve-этап оставляет именно два headline исходного offer, не подмешивает четвёртый")
	if reserve_options.is_empty():
		_finish_smoke()
		return
	var reserve_id := String(reserve_options[0].id)
	choose_opening_reserve(reserve_id)
	_check(input_mode() == "locked", "повторный ввод закрыт на время вступлений")
	_check(opening_stage() == "", "после второго выбора opening-транзакция закрыта")
	_check(model.turn_count == 0, "opening не расходует ход")
	_check(model.score(SIDE_YOU) == 1 and model.score(SIDE_OPP) == 1,
		"opening сохраняет симметричную Базу 1:1")
	_check((model.sides[SIDE_YOU].hand as Array).size() == hand_before and
		(model.sides[SIDE_YOU].draw as Array).size() == draw_before,
		"opening не меняет размер H5 или число карт в доборе")
	_check(_count_hand_type(SIDE_YOU, TYPE_USTANOVKA) == 1 and
		_count_hand_type(SIDE_OPP, TYPE_USTANOVKA) == 1 and
		model.reserve_count(SIDE_YOU) == 1 and model.reserve_count(SIDE_OPP) == 1,
		"после opening у обеих сторон H5 содержит ровно одну публичную Установку-резерв")
	_check(String(model.sides[SIDE_YOU].lines[0].get("claim_id", "")) != "" and
		String(model.sides[SIDE_OPP].lines[0].get("claim_id", "")) != "",
		"обе стартовые рамки получили смысловой id")
	var my_reserve := _reserve_card(SIDE_YOU)
	var opp_reserve := _reserve_card(SIDE_OPP)
	var my_reserve_index := _reserve_index(SIDE_YOU)
	_check(not my_reserve.is_empty() and String(my_reserve.get("claim_id", "")) == reserve_id and
		String(model.sides[SIDE_YOU].lines[0].get("claim_id", "")) == active_id and
		active_id != reserve_id,
		"активный и резервный headline игрока различны и резерв привязан к выбранной U")
	_check(my_reserve_index >= 0 and
		String(installation_option(my_reserve_index).get("id", "")) == reserve_id,
		"installation_option читает смысл прямо с публичной reserve-карты")
	_check(not opp_reserve.is_empty() and String(opp_reserve.get("claim_id", "")) != "" and
		String(opp_reserve.get("claim_id", "")) !=
			String(model.sides[SIDE_OPP].lines[0].get("claim_id", "")),
		"AI также держит публичный смысловой резерв, отличный от своей Базы")
	_check_pinned_reserve_does_not_shift_installations()
	_check_installation_variants()
	_check_frame_threat_contract()
	await _check_reframe_input_filter()
	_finish_smoke()


func _count_hand_type(side: String, type: String) -> int:
	var n := 0
	for card in model.sides[side].hand:
		if String(card.get("type", "")) == type:
			n += 1
	return n


func _reserve_card(side: String) -> Dictionary:
	for card in model.sides[side].hand:
		if bool(card.get("opening_reserve", false)):
			return card
	return {}


func _reserve_index(side: String) -> int:
	var hand: Array = model.sides[side].hand
	for i in hand.size():
		if bool(hand[i].get("opening_reserve", false)):
			return i
	return -1


## Регрессия: три U-карты не должны показывать один headline, а выбор средней обязан
## разыграть именно её вариант и оставить две разные рамки на оставшихся картах.
func _check_installation_variants() -> void:
	model.sides[SIDE_YOU].hand = [
		DeckLib.make_card(TYPE_USTANOVKA, 0),
		DeckLib.make_card(TYPE_USTANOVKA, 1),
		DeckLib.make_card(TYPE_USTANOVKA, 2),
	]
	model.sides[SIDE_YOU].draw = []
	_mode = "move"
	var before := [installation_option(0), installation_option(1), installation_option(2)]
	_check(String(before[0].id) != String(before[1].id) and
		String(before[1].id) != String(before[2].id) and
		String(before[0].id) != String(before[2].id),
		"три Установки в руке показывают три разные рамки")
	_check(hand_preview(0) != hand_preview(1) and hand_preview(1) != hand_preview(2),
		"тексты трёх Установок не дублируются")
	var chosen_id := String(before[1].id)
	play_hand(1)
	_check(String(model.sides[SIDE_YOU].lines[-1].get("claim_id", "")) == chosen_id,
		"разыграна рамка выбранной, а не первой U-карты")
	var left_a := installation_option(0)
	var left_b := installation_option(1)
	_check(not left_a.is_empty() and not left_b.is_empty() and
		String(left_a.id) != String(left_b.id) and
		String(left_a.id) != chosen_id and String(left_b.id) != chosen_id,
		"после розыгрыша две оставшиеся Установки не дублируются")


func _check_pinned_reserve_does_not_shift_installations() -> void:
	var expected_options: Array = nar.headline_options(SIDE_YOU, 1)
	if expected_options.is_empty():
		_check(false, "неприкреплённой Установке доступен следующий неиспользованный headline")
		return
	model.sides[SIDE_YOU].hand.append(DeckLib.make_card(TYPE_USTANOVKA, 77))
	var index := (model.sides[SIDE_YOU].hand as Array).size() - 1
	var actual: Dictionary = installation_option(index)
	_check(String(actual.get("id", "")) == String(expected_options[0].id),
		"pinned opening-reserve не сдвигает ordinal следующих обычных Установок")


func _check_reframe_input_filter() -> void:
	start_match()
	model.current = SIDE_YOU
	model.game_over = false
	model.board_ko_enabled = true
	model.sides[SIDE_YOU].lines = []
	model.sides[SIDE_YOU].hand = [
		{"type": TYPE_USTANOVKA, "name": "Сбережённая рамка",
			"opening_reserve": true, "recovery_ready": true,
			"claim_id": "reserve_test", "claim": "смысл переживает падение рамки",
			"preferred_axes": ["logic"]},
		{"type": TYPE_USTANOVKA, "name": "Поздний топдек"},
		{"type": TYPE_TEZIS, "name": "Обычный ход"},
	]
	model.sides[SIDE_YOU].draw = []
	model.sides[SIDE_YOU]["recovery_pending"] = true
	_mode = "reframe"
	var turn_before := int(model.turn_count)
	play_hand(1)
	_check(input_mode() == "reframe" and model.sides[SIDE_YOU].lines.is_empty() and
		model.turn_count == turn_before and model.recovery_pending(SIDE_YOU),
		"controller игнорирует позднюю U, которой не было в snapshot последней рамки")
	play_hand(0)
	await get_tree().process_frame
	_check(model.sides[SIDE_YOU].lines.size() == 1 and
		model.turn_count == turn_before + 1 and not model.recovery_pending(SIDE_YOU),
		"recovery_ready U восстанавливает рамку и тратит ровно один полный ход")
	_check(String(model.sides[SIDE_YOU].lines[0].get("claim_id", "")) == "reserve_test" and
		String(model.sides[SIDE_YOU].lines[0].get("claim", "")) ==
			"смысл переживает падение рамки",
		"reframe переносит смысл выбранной reserve-карты на новую рамку")


func _check_frame_threat_contract() -> void:
	start_match()
	model.sides[SIDE_YOU].lines = [
		{"theses": 1, "closed": false, "name": "Андердог", "stolen": 0},
	]
	model.sides[SIDE_OPP].lines = [
		{"theses": 4, "closed": false, "name": "Фаворит", "stolen": 0},
	]
	model.sides[SIDE_OPP].hand = []
	model.sides[SIDE_OPP].draw = []
	audience.lean = -4
	audience.heat = 0
	model.set_external_zal(-4, true)
	var calm: Dictionary = frame_threat(SIDE_OPP, 0)
	# Heat and strain remain visible in their own systems but cannot secretly change reach.
	audience.heat = 3
	emotion.observe(SIDE_OPP, "argument_lost", 6, {}, 1.0)
	var lethal: Dictionary = frame_threat(SIDE_OPP, 0)
	_check(int(calm.get("reach", 0)) == 4 and int(lethal.get("reach", 0)) == 4 and
		int(lethal.get("owner_favor", 0)) == 4 and bool(lethal.get("shaky", false)) and
		not lethal.has("heat") and not lethal.has("strain") and
		bool(lethal.get("last_frame", false)) and bool(lethal.get("lethal", false)),
		"frame_threat телеграфирует reach 4 только из Lean и отдельно показывает угрозу KO")
	model.sides[SIDE_OPP].hand.append({"type": TYPE_USTANOVKA, "name": "Публичный резерв",
		"opening_reserve": true})
	var insured: Dictionary = frame_threat(SIDE_OPP, 0)
	_check(int(insured.get("reserve", 0)) == 1 and not bool(insured.get("lethal", true)),
		"тот же threat-контракт различает KO и восстановление по публичному резерву")


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures += 1


func _finish_smoke() -> void:
	print("=== OPENING CONTROLLER: %s ===" % ("OK" if failures == 0 else "FAIL (%d)" % failures))
	var code := 0 if failures == 0 else 1
	queue_free()
	get_tree().call_deferred("quit", code)


func _emit(_data: Dictionary) -> void:
	pass


func _tx_write(_line: String) -> void:
	pass


func _present_openings() -> void:
	pass  # презентационные await не нужны для проверки перехода состояния


func _log_action(_info: Dictionary) -> void:
	pass


func _say(_side: String, _text: String, _tag: String = "", _card_type: String = "",
	_steals: bool = false, _mood: String = "", _extra_meta: Dictionary = {}) -> void:
	pass


func _run_until_player() -> void:
	pass
