extends Control

## DUELOGUE — сухое ядро «ЗАЛ» v0.2 (спека: context/zal_core_v0.2.md).
## Самодостаточная тест-сцена: НЕ зависит от основного движка.
## Запуск: открыть эту сцену и нажать F6 (Run Current Scene).
##
## Четыре правила легибельности (раздел 7 спеки) — здесь, в UI:
##   1. Карта показывает итоговый качок (с цепочкой и парой), не базу.
##   2. Ghost-предпросмотр: hover по карте → призрачный маркер на шкале.
##   3. Карты, продолжающие стихию — рамка цвета стихии; ломающие — приглушены.
##   4. Локатор пары: где партнёр (рука/добор/сброс); готовая пара — золотая рамка.

const ZalModel := preload("res://test/prototype_zal/zal_core_model.gd")

const AI_DELAY := 0.7

const COL_HOT := "d9594c"
const COL_COLD := "4c7cd9"
const COL_YOU := "6fcf7f"
const COL_OPP := "d98c4c"
const COL_GOLD := "ffd24a"
const COL_DIM := "8a93a3"

const BAR_X := 226.0
const BAR_W := 700.0
const BAR_Y := 88.0
const BAR_H := 30.0

const LOC_LABEL := {"hand": "в руке", "draw": "в доборе", "discard": "в сбросе"}

var model: RefCounted
var awaiting := false
var sd_logged := false
var log_lines: Array = []

var _marker: ColorRect
var _ghost: ColorRect
var _fill: ColorRect
var _status_label: Label
var _you_combo: Label
var _opp_combo: Label
var _you_thread_rt: RichTextLabel
var _opp_thread_rt: RichTextLabel
var _log_rt: RichTextLabel
var _flash: Label
var _restart_btn: Button
var _hand_buttons: Array = []
var _pile_btn_draw: Button
var _pile_btn_discard: Button
var _pile_btn_opp_discard: Button
var _opp_draw_label: Label
var _overlay: ColorRect
var _overlay_title: Label
var _overlay_rt: RichTextLabel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	model = ZalModel.new()
	_build_ui()
	_new_match()


# ---------------------------------------------------------------- UI ----------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color.html("#15171c")
	bg.size = Vector2(1152, 648)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_mklabel("DUELOGUE · ядро «ЗАЛ» v0.2", 20, 8, 18, Color.html("#e8e8e8"))
	_mklabel("Тяни ЗАЛ в свою сторону. Одна стихия подряд — комбо растёт. Пара приёмов из списка — именной удар.",
		20, 34, 11, Color.html("#" + COL_DIM))
	_mklabel("Карты: добор → рука → сброс; пустой добор = перемешанный сброс. Наведи на карту — призрак покажет качок.",
		20, 50, 11, Color.html("#" + COL_DIM))

	_status_label = _mklabel("", 0, 64, 16, Color.html("#e8e8e8"), 1152, HORIZONTAL_ALIGNMENT_CENTER)

	_mklabel("ОППОНЕНТ", 110, 92, 14, Color.html("#" + COL_OPP))
	_mklabel("ВЫ", 950, 92, 14, Color.html("#" + COL_YOU))

	var bar_bg := ColorRect.new()
	bar_bg.color = Color.html("#2a2e38")
	bar_bg.position = Vector2(BAR_X, BAR_Y)
	bar_bg.size = Vector2(BAR_W, BAR_H)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar_bg)

	_fill = ColorRect.new()
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)

	var tick := ColorRect.new()
	tick.color = Color.html("#cfd6e0")
	tick.position = Vector2(BAR_X + BAR_W / 2.0 - 1.0, BAR_Y - 6.0)
	tick.size = Vector2(2, BAR_H + 12.0)
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tick)

	_ghost = ColorRect.new()
	_ghost.color = Color(1, 1, 1, 0.35)
	_ghost.size = Vector2(8, BAR_H + 8.0)
	_ghost.visible = false
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ghost)

	_marker = ColorRect.new()
	_marker.color = Color.WHITE
	_marker.size = Vector2(8, BAR_H + 8.0)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_marker)

	_opp_combo = _mklabel("", 226, 126, 14, Color.html("#" + COL_OPP))
	_you_combo = _mklabel("", 700, 126, 14, Color.html("#" + COL_YOU), 226, HORIZONTAL_ALIGNMENT_RIGHT)

	_mklabel("Оппонент:", 20, 156, 12, Color.html("#" + COL_OPP))
	_opp_thread_rt = _mkrich(130, 152, 750, 24, false)
	_mklabel("Вы:", 20, 184, 12, Color.html("#" + COL_YOU))
	_you_thread_rt = _mkrich(130, 180, 750, 24, false)

	_mklabel("ИМЕННЫЕ ПРИЁМЫ", 900, 150, 13, Color.html("#e8e8e8"))
	var moves := _mkrich(900, 170, 236, 132, false)
	var lines: Array = []
	for p in ZalModel.PAIRS:
		lines.append("[color=#%s]%s[/color]\n  %s → %s" % [p["col"], p["name"], p["a"], p["b"]])
	moves.text = "\n".join(lines)

	_pile_btn_draw = _mkpilebtn(310, _show_pile.bind("you_draw"))
	_pile_btn_discard = _mkpilebtn(340, _show_pile.bind("you_discard"))
	_pile_btn_opp_discard = _mkpilebtn(370, _show_pile.bind("opp_discard"))
	_opp_draw_label = _mklabel("", 900, 402, 11, Color.html("#" + COL_DIM))

	_restart_btn = Button.new()
	_restart_btn.text = "Новая партия"
	_restart_btn.position = Vector2(900, 424)
	_restart_btn.size = Vector2(236, 36)
	_restart_btn.visible = false
	_restart_btn.pressed.connect(_new_match)
	add_child(_restart_btn)

	_log_rt = _mkrich(20, 212, 860, 238, true)

	_flash = Label.new()
	_flash.position = Vector2(0, 268)
	_flash.size = Vector2(1152, 90)
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_flash.add_theme_font_size_override("font_size", 50)
	_flash.modulate.a = 0.0
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	# Оверлей просмотра зон колоды (добавляется последним — поверх всего).
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.6)
	_overlay.size = Vector2(1152, 648)
	_overlay.visible = false
	_overlay.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_overlay.visible = false)
	add_child(_overlay)

	var panel := ColorRect.new()
	panel.color = Color.html("#1c1f27")
	panel.position = Vector2(336, 120)
	panel.size = Vector2(480, 400)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(panel)

	_overlay_title = Label.new()
	_overlay_title.position = Vector2(356, 132)
	_overlay_title.size = Vector2(440, 24)
	_overlay_title.add_theme_font_size_override("font_size", 14)
	_overlay_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_overlay_title)

	_overlay_rt = RichTextLabel.new()
	_overlay_rt.bbcode_enabled = true
	_overlay_rt.position = Vector2(356, 164)
	_overlay_rt.size = Vector2(440, 320)
	_overlay_rt.add_theme_font_size_override("normal_font_size", 13)
	_overlay_rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_overlay_rt)

	var close_hint := Label.new()
	close_hint.text = "клик — закрыть"
	close_hint.position = Vector2(356, 490)
	close_hint.size = Vector2(440, 20)
	close_hint.add_theme_font_size_override("font_size", 11)
	close_hint.add_theme_color_override("font_color", Color.html("#" + COL_DIM))
	close_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(close_hint)


func _mklabel(txt: String, x: float, y: float, fsize: int, col: Color, w: float = 1110, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = txt
	l.position = Vector2(x, y)
	l.size = Vector2(w, 24)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _mkrich(x: float, y: float, w: float, h: float, scrolling: bool) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = scrolling
	r.scroll_following = scrolling
	r.position = Vector2(x, y)
	r.size = Vector2(w, h)
	r.clip_contents = true
	r.add_theme_font_size_override("normal_font_size", 13)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _mkpilebtn(y: float, handler: Callable) -> Button:
	var btn := Button.new()
	btn.position = Vector2(900, y)
	btn.size = Vector2(236, 26)
	btn.add_theme_font_size_override("font_size", 12)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(handler)
	add_child(btn)
	return btn


# ------------------------------------------------------------- match ----------

func _new_match() -> void:
	awaiting = false
	sd_logged = false
	log_lines = ["Новая партия. Тяни зал в свою сторону."]
	_flash.modulate.a = 0.0
	_restart_btn.visible = false

	var first := ZalModel.SIDE_YOU if randf() < 0.5 else ZalModel.SIDE_OPP
	model.reset(first)
	if first == ZalModel.SIDE_OPP:
		_log("Оппонент берёт слово первым. Коми: зал стартует %+d в вашу сторону." % ZalModel.KOMI)
		_ai_move()
	else:
		_log("Вы берёте слово первым. Коми: зал стартует %+d к оппоненту." % ZalModel.KOMI)
	_refresh()


# --------------------------------------------------------------- turns --------

func _on_card_pressed(i: int) -> void:
	if model.game_over or awaiting:
		return
	var res: Dictionary = model.play(ZalModel.SIDE_YOU, i)
	if res.is_empty():
		return
	_hide_ghost()
	_log_play("you", res)
	if model.game_over:
		_handle_end()
		_refresh()
		return
	awaiting = true
	_refresh()
	await get_tree().create_timer(AI_DELAY).timeout
	awaiting = false
	if not model.game_over:
		_ai_move()
	if model.game_over:
		_handle_end()
	_refresh()


func _ai_move() -> void:
	var idx: int = model.ai_choose(ZalModel.SIDE_OPP)
	if idx < 0:
		return
	var res: Dictionary = model.play(ZalModel.SIDE_OPP, idx)
	_log_play("opp", res)


func _log_play(side: String, res: Dictionary) -> void:
	var card: Dictionary = res.card
	var who := "[color=#%s]%s:[/color]" % [(COL_YOU if side == "you" else COL_OPP), ("Вы" if side == "you" else "Оппонент")]
	_log("%s %s — «%s»" % [who, card["name"], card["quote"]])
	if int(res.bonus) > 0:
		_log("   [color=#%s]КОМБО ×%d: +%d[/color]" % [(COL_YOU if side == "you" else COL_OPP), int(res.chain), int(res.bonus)])
	if bool(res.pair_fired):
		var p: Dictionary = res.pair
		_show_flash(String(p["name"]) + "!", Color.html("#" + String(p["col"])), false)
		_log("   [b][color=#%s]ПРИЁМ «%s»: +%d[/color][/b]" % [p["col"], p["name"], ZalModel.PAIR_BONUS])
	_log("   зал %+d → %+d" % [int(res.room_after) - int(res.room_before), int(res.room_after)])

	if model.sudden_death and not model.game_over and not sd_logged:
		sd_logged = true
		_log("[b][color=#%s]ЗАЛ РОВНО ПОСЕРЕДИНЕ — внезапная смерть, следующий качок решает![/color][/b]" % COL_GOLD)


func _handle_end() -> void:
	match String(model.end_reason):
		"edge":
			_log("Маркер дошёл до края.")
		"cap":
			_log("Лимит ходов: зал расходится, решение по положению маркера.")
		"sudden_death":
			_log("Внезапная смерть: решающий качок.")
	if model.winner == ZalModel.SIDE_YOU:
		_show_flash("ВЫ ВЫИГРАЛИ ЗАЛ", Color.html("#" + COL_YOU), true)
		_log("[b][color=#%s]Зал ваш. Победа.[/color][/b]" % COL_YOU)
	else:
		_show_flash("ЗАЛ ЗА ОППОНЕНТОМ", Color.html("#" + COL_OPP), true)
		_log("[b][color=#%s]Зал ушёл к оппоненту. Поражение.[/color][/b]" % COL_OPP)
	_restart_btn.visible = true


# ----------------------------------------------------------------- view -------

func _refresh() -> void:
	_update_meter()
	_update_status()
	_update_combo()
	_update_threads()
	_update_piles()
	_update_log()
	_build_hand()


func _room_to_x(value: int) -> float:
	var t := clampf(float(value) / float(ZalModel.ROOM_MAX), -1.0, 1.0)
	return BAR_X + BAR_W / 2.0 + t * (BAR_W / 2.0)


func _update_meter() -> void:
	var center_x := BAR_X + BAR_W / 2.0
	var marker_x := _room_to_x(model.room)
	_marker.position = Vector2(marker_x - 4.0, BAR_Y - 4.0)
	if model.room >= 0:
		_fill.position = Vector2(center_x, BAR_Y)
		_fill.size = Vector2(marker_x - center_x, BAR_H)
		_fill.color = Color.html("#" + COL_YOU)
	else:
		_fill.position = Vector2(marker_x, BAR_Y)
		_fill.size = Vector2(center_x - marker_x, BAR_H)
		_fill.color = Color.html("#" + COL_OPP)


func _update_status() -> void:
	var txt := "ЗАЛ: %+d   ·   ход %d / %d" % [model.room, model.full_turns(), ZalModel.TURN_CAP]
	if model.sudden_death and not model.game_over:
		txt += "   ·   ВНЕЗАПНАЯ СМЕРТЬ"
	_status_label.text = txt


func _update_combo() -> void:
	var s_you: Dictionary = model.sides[ZalModel.SIDE_YOU]
	var s_opp: Dictionary = model.sides[ZalModel.SIDE_OPP]
	_you_combo.text = ("КОМБО ×%d" % int(s_you.chain)) if int(s_you.chain) >= 2 else ""
	_opp_combo.text = ("КОМБО ×%d" % int(s_opp.chain)) if int(s_opp.chain) >= 2 else ""


func _update_threads() -> void:
	_opp_thread_rt.text = _thread_bb(model.sides[ZalModel.SIDE_OPP].thread)
	_you_thread_rt.text = _thread_bb(model.sides[ZalModel.SIDE_YOU].thread)


func _thread_bb(thread: Array) -> String:
	var parts: Array = []
	var start := maxi(0, thread.size() - 8)
	for i in range(start, thread.size()):
		var e: Dictionary = thread[i]
		var col := COL_HOT if String(e["stance"]) == "hot" else COL_COLD
		parts.append("[color=#%s]%s[/color]" % [col, e["name"]])
	return "   ·   ".join(parts)


func _update_piles() -> void:
	var s_you: Dictionary = model.sides[ZalModel.SIDE_YOU]
	var s_opp: Dictionary = model.sides[ZalModel.SIDE_OPP]
	_pile_btn_draw.text = "Ваш добор: %d" % s_you.draw.size()
	_pile_btn_discard.text = "Ваш сброс: %d" % s_you.discard.size()
	_pile_btn_opp_discard.text = "Сброс оппонента: %d" % s_opp.discard.size()
	_opp_draw_label.text = "Добор оппонента: %d (рука скрыта)" % s_opp.draw.size()


func _update_log() -> void:
	_log_rt.text = "\n".join(log_lines)


func _build_hand() -> void:
	for b in _hand_buttons:
		if is_instance_valid(b):
			b.queue_free()
	_hand_buttons.clear()

	var s: Dictionary = model.sides[ZalModel.SIDE_YOU]
	for i in s.hand.size():
		var card: Dictionary = s.hand[i]
		var pv: Dictionary = model.preview(ZalModel.SIDE_YOU, i)
		var is_hot := String(card["stance"]) == "hot"
		var scol := COL_HOT if is_hot else COL_COLD
		var kind := "эмоция" if is_hot else "логика"
		var continues: bool = s.chain_stance != "" and s.chain_stance == String(card["stance"])
		var ready: bool = not pv.pair.is_empty()

		# Правило 1: итоговый качок, не база.
		var swing_line := "зал +%d" % int(pv.total_swing)
		var parts: Array = []
		if int(pv.bonus) > 0:
			parts.append("комбо %d" % int(pv.bonus))
		if ready:
			parts.append("приём %d" % ZalModel.PAIR_BONUS)
		if parts.size() > 0:
			swing_line += "  (%d + %s)" % [ZalModel.BASE_SWAY, " + ".join(parts)]

		# Правило 4: локатор пары.
		var pair_block := "\n"
		var p: Dictionary = model.pair_of(card)
		if not p.is_empty():
			if ready:
				pair_block = "⛓ «%s»\nЗАВЕРШАЕТ ПРИЁМ!" % p["name"]
			else:
				var loc: String = model.partner_location(ZalModel.SIDE_YOU, card)
				pair_block = "⛓ «%s»\nпартнёр %s" % [p["name"], LOC_LABEL.get(loc, "?")]

		var btn := Button.new()
		btn.position = Vector2(26 + i * 224, 462)
		btn.size = Vector2(214, 168)
		btn.clip_text = false
		btn.add_theme_font_size_override("font_size", 12)
		btn.text = "%s\n[%s]\n%s\n%s\n«%s»" % [card["name"], kind, swing_line, pair_block, card["quote"]]

		# Правило 3: рамка стихии для продолжающих цепочку, приглушение ломающих.
		# Готовая пара — золотая рамка (правило 4).
		var border_col: Color
		var border_w: int
		var font_col := Color.html("#" + scol)
		if ready:
			border_col = Color.html("#" + COL_GOLD)
			border_w = 3
		elif continues:
			border_col = Color.html("#" + scol)
			border_w = 2
		else:
			border_col = Color.html("#343a46")
			border_w = 1
			if s.chain_stance != "":
				font_col.a = 0.6
		btn.add_theme_stylebox_override("normal", _card_style(Color.html("#20242e"), border_col, border_w))
		btn.add_theme_stylebox_override("hover", _card_style(Color.html("#293040"), border_col, border_w))
		btn.add_theme_stylebox_override("pressed", _card_style(Color.html("#1a1d24"), border_col, border_w))
		btn.add_theme_color_override("font_color", font_col)
		btn.add_theme_color_override("font_hover_color", Color.html("#" + scol))

		btn.disabled = model.game_over or awaiting
		btn.pressed.connect(_on_card_pressed.bind(i))
		# Правило 2: ghost-предпросмотр на шкале.
		btn.mouse_entered.connect(_on_card_hover.bind(i))
		btn.mouse_exited.connect(_hide_ghost)
		add_child(btn)
		_hand_buttons.append(btn)

		if ready:
			var tw := btn.create_tween().set_loops()
			tw.tween_property(btn, "modulate:a", 0.7, 0.45)
			tw.tween_property(btn, "modulate:a", 1.0, 0.45)


func _card_style(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	return sb


func _on_card_hover(i: int) -> void:
	if model.game_over or awaiting:
		return
	var pv: Dictionary = model.preview(ZalModel.SIDE_YOU, i)
	if pv.is_empty():
		return
	var predicted: int = clampi(model.room + int(pv.total_swing), -ZalModel.ROOM_MAX, ZalModel.ROOM_MAX)
	_ghost.position = Vector2(_room_to_x(predicted) - 4.0, BAR_Y - 4.0)
	_ghost.visible = true


func _hide_ghost() -> void:
	_ghost.visible = false


func _show_pile(kind: String) -> void:
	var s_you: Dictionary = model.sides[ZalModel.SIDE_YOU]
	var s_opp: Dictionary = model.sides[ZalModel.SIDE_OPP]
	var title := ""
	var lines: Array = []
	match kind:
		"you_draw":
			title = "Ваш добор — состав известен, порядок нет"
			var names: Array = []
			for c in s_you.draw:
				names.append([String(c["name"]), String(c["stance"])])
			names.sort_custom(func(a, b) -> bool: return a[0] < b[0])
			for n in names:
				lines.append(_pile_line(n[0], n[1]))
		"you_discard":
			title = "Ваш сброс (последняя сыгранная — сверху)"
			for i in range(s_you.discard.size() - 1, -1, -1):
				var c: Dictionary = s_you.discard[i]
				lines.append(_pile_line(String(c["name"]), String(c["stance"])))
		"opp_discard":
			title = "Сброс оппонента (последняя — сверху)"
			for i in range(s_opp.discard.size() - 1, -1, -1):
				var c: Dictionary = s_opp.discard[i]
				lines.append(_pile_line(String(c["name"]), String(c["stance"])))
	_overlay_title.text = title
	_overlay_rt.text = "\n".join(lines) if lines.size() > 0 else "[color=#%s](пусто)[/color]" % COL_DIM
	_overlay.visible = true


func _pile_line(card_name: String, stance: String) -> String:
	var col := COL_HOT if stance == "hot" else COL_COLD
	return "[color=#%s]%s[/color]" % [col, card_name]


func _show_flash(txt: String, col: Color, persist: bool) -> void:
	_flash.text = txt
	_flash.add_theme_color_override("font_color", col)
	_flash.modulate.a = 1.0
	if not persist:
		var tw := create_tween()
		tw.tween_interval(0.4)
		tw.tween_property(_flash, "modulate:a", 0.0, 1.0)


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 60:
		log_lines = log_lines.slice(log_lines.size() - 60, log_lines.size())
