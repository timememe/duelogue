extends "res://duelogue/app/battle_controller.gd"

## Интеграционный smoke opening-фазы контроллера. Переопределяет файловые логгеры,
## чтобы тест не загрязнял живую стенограмму ручных плейтестов.

var failures := 0


func _ready() -> void:
	super._ready()
	ReadingPace.CUTSCENES = false
	start_match()
	_check(input_mode() == "opening", "контроллер ждёт выбор рамки")
	var options := opening_options()
	_check(options.size() == 3, "контроллер отдаёт три варианта")
	if options.is_empty():
		_finish_smoke()
		return

	var hand_before := (model.sides[SIDE_YOU].hand as Array).size()
	var draw_before := (model.sides[SIDE_YOU].draw as Array).size()
	# После двух коротких вступлений flow остановится на ходе игрока, без фонового AI-таймера.
	_first_side = SIDE_YOU
	model.current = SIDE_YOU
	choose_opening(String(options[0].id))
	_check(input_mode() == "locked", "повторный ввод закрыт на время вступлений")
	_check(model.turn_count == 0, "opening не расходует ход")
	_check(model.score(SIDE_YOU) == 1 and model.score(SIDE_OPP) == 1,
		"opening сохраняет симметричную Базу 1:1")
	_check((model.sides[SIDE_YOU].hand as Array).size() == hand_before and
		(model.sides[SIDE_YOU].draw as Array).size() == draw_before,
		"opening не расходует карту и не меняет добор")
	_check(String(model.sides[SIDE_YOU].lines[0].get("claim_id", "")) != "" and
		String(model.sides[SIDE_OPP].lines[0].get("claim_id", "")) != "",
		"обе стартовые рамки получили смысловой id")
	_check_installation_variants()
	_finish_smoke()


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


func _run_until_player() -> void:
	pass
