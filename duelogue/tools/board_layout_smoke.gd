extends Node

## Регрессия горизонтальных границ Board: четыре максимально раскрытые рамки должны
## уплотниться до доступных 584 px, включая служебные хвосты и стопку клинча.

const DebateScreen := preload("res://duelogue/ui/debate_screen.gd")


func _ready() -> void:
	var failures := 0
	# Проверяем не только формулу: длинный текст не должен раздувать реальный Button шире
	# CARD_W, иначе контейнер и визуал снова будут жить в разных геометриях.
	var view := DebateScreen.new()
	var probe: Button = view._mkcard("РАМКА\n«очень длинное название рамки»", "ffd24a", false, false)
	add_child(probe)
	await get_tree().process_frame
	failures += _check(probe.get_combined_minimum_size().x <= 42.01 and probe.size.x <= 42.01,
		"длинный текст не раздувает мини-карту шире 42 px")
	probe.queue_free()

	var counts := [8, 8, 8, 8]
	var pads := [16.0, 46.0, 16.0, 16.0]
	var fit: Dictionary = DebateScreen.fit_board_row(counts, pads, 584.0, 12.0)
	failures += _check(float(fit.width) <= 584.01,
		"четыре широкие рамки помещаются во внутреннюю границу")
	failures += _check(float(fit.gap) < 4.0,
		"при достижении края карты начинают перекрываться плотнее")
	failures += _check(is_zero_approx(float(fit.clipped_overflow)),
		"для штатного максимума жёсткое отсечение не требуется")

	var relaxed: Dictionary = DebateScreen.fit_board_row([1, 1], [16.0, 16.0], 584.0, 12.0)
	failures += _check(is_equal_approx(float(relaxed.gap), 4.0) and
		is_equal_approx(float(relaxed.separation), 12.0),
		"свободный ряд сохраняет авторские отступы сцены")
	var first_thesis_x := DebateScreen.thesis_position_x(0, float(fit.gap))
	failures += _check(is_equal_approx(first_thesis_x, 46.0) and
		DebateScreen.thesis_position_x(1, float(fit.gap)) < 92.0,
		"первый тезис никогда не заезжает под золотую рамку")
	var mirror_width := DebateScreen._group_width(2, 4.0)
	var opp_frame_x := DebateScreen.board_card_position_x(0.0, mirror_width, 16.0, true)
	var opp_thesis_x := DebateScreen.board_card_position_x(46.0, mirror_width, 16.0, true)
	failures += _check(opp_frame_x > opp_thesis_x and
		is_equal_approx(opp_frame_x - (opp_thesis_x + 42.0), 4.0),
		"карты оппонента зеркально растут от рамки справа налево")

	# Второй проход работает по фактическим rect нод, а не по ожидаемой формуле.
	var actual_row := Control.new()
	actual_row.size = Vector2(300.0, 100.0)
	add_child(actual_row)
	_add_probe_group(view, actual_row, 0.0, 2)
	_add_probe_group(view, actual_row, 210.0, 1)
	actual_row.set_meta("layout_generation", 1)
	view._compress_row_from_actual_bounds(actual_row, 1)
	var measured_right := 0.0
	var protected_first := true
	for group in actual_row.get_children():
		var frame_x := float(group.position.x)
		for card in group.get_children():
			if not card is Control or not bool(card.get_meta("board_card", false)):
				continue
			measured_right = maxf(measured_right,
				float(group.position.x + card.position.x + card.size.x))
			if String(card.get_meta("board_role", "")) == "thesis" and int(card.get_meta("probe_index", -1)) == 0:
				protected_first = protected_first and float(group.position.x + card.position.x) >= frame_x + 42.0
	failures += _check(measured_right <= 288.01 and protected_first,
		"фактический край сжимается до защитной зоны без заезда под рамку")
	actual_row.queue_free()

	# Тот же фактический проход зеркально защищает левый край линии оппонента.
	var reverse_row := Control.new()
	reverse_row.size = Vector2(300.0, 100.0)
	reverse_row.set_meta("reverse_layout", true)
	add_child(reverse_row)
	_add_probe_group(view, reverse_row, 196.0, 1, true)
	_add_probe_group(view, reverse_row, -12.0, 1, true)
	reverse_row.set_meta("layout_generation", 2)
	view._compress_row_from_actual_bounds(reverse_row, 2)
	var measured_left := 300.0
	var protected_reverse := true
	for group in reverse_row.get_children():
		var frame_left := 0.0
		for card in group.get_children():
			if String(card.get_meta("board_role", "")) == "frame":
				frame_left = float(group.position.x + card.position.x)
		for card in group.get_children():
			if not card is Control or not bool(card.get_meta("board_card", false)):
				continue
			measured_left = minf(measured_left, float(group.position.x + card.position.x))
			if String(card.get_meta("board_role", "")) == "thesis" and int(card.get_meta("probe_index", -1)) == 0:
				protected_reverse = protected_reverse and \
					float(group.position.x + card.position.x + card.size.x) <= frame_left
	failures += _check(measured_left >= 11.99 and protected_reverse,
		"зеркальное сжатие держит левую границу линии оппонента")
	reverse_row.queue_free()
	view.free()
	print("=== BOARD LAYOUT: %s ===" % ("OK" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> int:
	print("  %s · %s" % [label, "OK" if ok else "FAIL"])
	return 0 if ok else 1


func _add_probe_group(view: Control, row: Control, x: float, thesis_count: int,
	reverse: bool = false) -> void:
	var group := Control.new()
	group.position.x = x
	row.add_child(group)
	var width := DebateScreen._group_width(thesis_count, 4.0)
	var frame: Button = view._mkcard("РАМКА", "ffd24a", false, false)
	frame.position.x = DebateScreen.board_card_position_x(0.0, width, 16.0, reverse)
	frame.set_meta("board_card", true)
	frame.set_meta("board_role", "frame")
	group.add_child(frame)
	for i in thesis_count:
		var thesis: Button = view._mkcard("тезис", "6fcf7f", false, false)
		var ltr_x := 46.0 + float(i) * 46.0
		thesis.position.x = DebateScreen.board_card_position_x(ltr_x, width, 16.0, reverse)
		thesis.set_meta("board_card", true)
		thesis.set_meta("board_role", "thesis")
		thesis.set_meta("probe_index", i)
		group.add_child(thesis)
