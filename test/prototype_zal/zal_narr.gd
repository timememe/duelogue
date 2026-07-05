extends Control

## DUELOGUE — ядро v0.3.1 + НАРРАТИВНЫЙ СЛОЙ (дубликат zal_v3.gd для обкатки).
## Механику/модель не меняем: переиспользуем zal_v3_model.gd как есть. Нарратив — отдельный
## модуль narrative_engine.gd, читает действия/клинч и собирает стенограмму спора.
## Тема — narrative_theme_pineapple.gd (сменяемые данные за контрактом). F6.

const ZalV3 := preload("res://test/prototype_zal/zal_v3_model.gd")
const NarEngine := preload("res://test/prototype_zal/narrative_engine.gd")
const PineappleTheme := preload("res://test/prototype_zal/narrative_theme_pineapple.gd")
const ShawarmaTheme := preload("res://test/prototype_zal/narrative_theme_shawarma.gd")
const EvangelionTheme := preload("res://test/prototype_zal/narrative_theme_evangelion.gd")
const THEMES := [PineappleTheme, ShawarmaTheme, EvangelionTheme]  ## колоды для меню выбора
const ACTIVE_THEME := PineappleTheme  ## тема по умолчанию при старте

# --- Константы партии (откалибровано симуляцией, идентично zal_v3) ---
const DECK_U := 3
const DECK_T := 8
const DECK_R := 9
const HAND := 5
const BASE_THESES := 1
const KOMI := 0
const STEAL_CARDS := 2
const FORTIFY := 0
const CLINCH := true
const CLINCH_FREEZE := true
const CAPTURE := 1  ## захват рамки: 0 выкл, 1 закрытым трофеем, 2 активной (как в zal_v3)
const OPP_STYLE := "smart"  ## умный бот: захват/защита от захвата/teardown + экономный клинч
const AI_DELAY := 0.55
const CLINCH_STEP_DELAY := 0.45
const LOG_PATH := "res://test/prototype_zal/playtest_log.jsonl"
const TX_PATH := "res://test/prototype_zal/narrative_transcript.md"  ## общий интерливнутый лог: реплика + тег действия

const COL_TEZIS := "6fcf7f"
const COL_RAZBOR := "d9594c"
const COL_USTAN := "ffd24a"
const COL_YOU := "6fcf7f"
const COL_OPP := "d98c4c"
const COL_DIM := "8a93a3"
const COL_GOLD := "ffd24a"

const BAR_X := 326.0
const BAR_W := 500.0
const BAR_Y := 300.0
const BAR_H := 24.0

signal _clinch_decided(decision: Dictionary)

var model: RefCounted
var nar: RefCounted
var busy := false
var targeting := false
var awaiting_clinch := false
var clinch_mode := ""
var clinch_side := ""
var clinch_idx := -1
var clinch_razbors := 0
var pending_steals := false
var match_id := 0
var log_lines: Array = []
var _theme_data: Dictionary
var _epoch := 0  ## поколение матча; протухшие корутины (await из прошлой партии) выходят по нему

var _score_label: Label
var _zal_label: Label
var _info_label: Label
var _hint_label: Label
var _marker: ColorRect
var _fill: ColorRect
var _opp_row: HBoxContainer
var _you_row: HBoxContainer
var _hand_row: HBoxContainer
var _log_rt: RichTextLabel
var _flash: Label
var _restart_btn: Button
var _cancel_btn: Button
var _clinch_btn: Button
var _menu_overlay: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	model = ZalV3.new()
	nar = NarEngine.new()
	_theme_data = ACTIVE_THEME.data()
	_build_ui()
	_new_match()


# ---------------------------------------------------------------- UI ----------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color.html("#15171c")
	bg.size = Vector2(1152, 648)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_mklabel("DUELOGUE · ядро + нарратив — стенограмма дебатов", 20, 6, 17, Color.html("#e8e8e8"))
	_mklabel("Карта = риторический приём (форма). Рамка = позиция/топик (содержание). Разбор/Кража бьют конкретный тезис.",
		20, 30, 11, Color.html("#" + COL_DIM))
	_mklabel("Клинч: когда бьют твою рамку — держи её тезисом, и она крепнет; не ответил — снос проходит.",
		20, 45, 11, Color.html("#" + COL_DIM))

	_score_label = _mklabel("", 0, 62, 16, Color.html("#e8e8e8"), 1152, HORIZONTAL_ALIGNMENT_CENTER)

	_mklabel("РАМКИ ОППОНЕНТА", 20, 88, 12, Color.html("#" + COL_OPP))
	_opp_row = _mkrow(20, 106)

	_zal_label = _mklabel("", 0, 276, 13, Color.html("#e8e8e8"), 1152, HORIZONTAL_ALIGNMENT_CENTER)
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
	tick.position = Vector2(BAR_X + BAR_W / 2.0 - 1.0, BAR_Y - 5.0)
	tick.size = Vector2(2, BAR_H + 10.0)
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tick)
	_marker = ColorRect.new()
	_marker.color = Color.WHITE
	_marker.size = Vector2(7, BAR_H + 8.0)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_marker)
	_mklabel("ОПП", BAR_X - 42.0, BAR_Y + 2.0, 11, Color.html("#" + COL_OPP))
	_mklabel("ВЫ", BAR_X + BAR_W + 14.0, BAR_Y + 2.0, 11, Color.html("#" + COL_YOU))

	_mklabel("ВАШИ РАМКИ", 20, 332, 12, Color.html("#" + COL_YOU))
	_you_row = _mkrow(20, 350)

	_hint_label = _mklabel("", 20, 476, 13, Color.html("#" + COL_GOLD))
	_hand_row = _mkrow(20, 496)

	var log_panel := ColorRect.new()
	log_panel.color = Color.html("#101216")
	log_panel.position = Vector2(884, 88)
	log_panel.size = Vector2(252, 376)
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(log_panel)
	_info_label = _mklabel("СТЕНОГРАММА", 892, 92, 12, Color.html("#" + COL_GOLD), 236)
	_log_rt = _mkrich(892, 114, 236, 344, true)

	_cancel_btn = _mkbtn("Отмена", 712, 472, 160, 26, _cancel_targeting)
	_cancel_btn.visible = false
	_clinch_btn = _mkbtn("Пропустить", 712, 472, 160, 26, _on_clinch_pass)
	_clinch_btn.visible = false
	_restart_btn = _mkbtn("Новая партия", 892, 428, 230, 30, _new_match)
	_restart_btn.visible = false

	_flash = Label.new()
	_flash.position = Vector2(0, 196)
	_flash.size = Vector2(1152, 80)
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_flash.add_theme_font_size_override("font_size", 40)
	_flash.modulate.a = 0.0
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	# Кнопка меню (поверх всего) + оверлей паузы.
	_mkbtn("☰ Меню", 1024, 4, 110, 26, _open_menu)
	_build_menu()


## Оверлей паузы: продолжить / новая партия / выбор колоды. Перекрывает доску (блокирует клики).
func _build_menu() -> void:
	_menu_overlay = Control.new()
	_menu_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_overlay.size = Vector2(1152, 648)
	_menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # глушит клики по доске под меню
	_menu_overlay.visible = false
	add_child(_menu_overlay)
	_build_menu_contents()


func _menu_btn(txt: String, x: float, y: float, w: float, h: float, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.position = Vector2(x, y)
	b.size = Vector2(w, h)
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	_menu_overlay.add_child(b)
	return b


func _menu_label(txt: String, x: float, y: float, fsize: int, colhex: String, w: float, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var l := Label.new()
	l.text = txt
	l.position = Vector2(x, y)
	l.size = Vector2(w, 24)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", Color.html("#" + colhex))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_overlay.add_child(l)


func _open_menu() -> void:
	_menu_overlay.visible = true


func _close_menu() -> void:
	_menu_overlay.visible = false


func _menu_restart() -> void:
	_close_menu()
	_new_match()


func _select_theme(i: int) -> void:
	_theme_data = THEMES[i].data()
	# Перестроить меню, чтобы отметка «●» переехала на выбранную колоду.
	for c in _menu_overlay.get_children():
		c.queue_free()
	_build_menu_contents()
	_close_menu()
	_new_match()


## Содержимое оверлея (без самого Control) — для перестройки отметки активной колоды.
func _build_menu_contents() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.07, 0.09, 0.82)
	dim.size = Vector2(1152, 648)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_overlay.add_child(dim)
	var panel := ColorRect.new()
	panel.color = Color.html("#1b1f27")
	panel.position = Vector2(356, 130)
	panel.size = Vector2(440, 348)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_overlay.add_child(panel)
	_menu_label("ПАУЗА", 356, 146, 22, COL_GOLD, 440, HORIZONTAL_ALIGNMENT_CENTER)
	_menu_btn("Продолжить", 376, 188, 400, 32, _close_menu)
	_menu_btn("Новая партия (та же колода)", 376, 226, 400, 32, _menu_restart)
	_menu_label("Сменить колоду:", 376, 274, 13, COL_DIM, 400)
	for i in THEMES.size():
		var td: Dictionary = THEMES[i].data()
		var mark := "● " if String(td.id) == String(_theme_data.get("id", "")) else "   "
		_menu_btn(mark + String(td.topic), 376, 298.0 + float(i) * 38.0, 400, 32, _select_theme.bind(i))


func _mkrow(x: float, y: float) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.position = Vector2(x, y)
	h.add_theme_constant_override("separation", 12)
	add_child(h)
	return h


func _mkbtn(txt: String, x: float, y: float, w: float, h: float, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.position = Vector2(x, y)
	b.size = Vector2(w, h)
	b.pressed.connect(cb)
	add_child(b)
	return b


func _mklabel(txt: String, x: float, y: float, fsize: int, col: Color, w: float = 1110, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = txt
	l.position = Vector2(x, y)
	l.size = Vector2(w, 22)
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
	r.add_theme_font_size_override("normal_font_size", 12)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


# ------------------------------------------------------------- match ----------

func _new_match() -> void:
	_epoch += 1  # инвалидируем все незавершённые корутины прошлого матча
	busy = false
	targeting = false
	awaiting_clinch = false
	clinch_side = ""
	clinch_idx = -1
	clinch_razbors = 0
	pending_steals = false
	# Разбудить зависший _ask_clinch прошлого матча — он выйдет по epoch-guard, не тронув модель.
	_clinch_decided.emit({"act": "pass"})
	log_lines = []
	_flash.modulate.a = 0.0
	_restart_btn.visible = false
	_cancel_btn.visible = false
	_clinch_btn.visible = false
	_hint_label.text = ""
	var first := ZalV3.SIDE_YOU if randf() < 0.5 else ZalV3.SIDE_OPP
	model.reset(first, DECK_U, DECK_T, DECK_R, HAND, BASE_THESES, KOMI, STEAL_CARDS, FORTIFY, CLINCH, CLINCH_FREEZE, CAPTURE)
	model.set_ai_style(ZalV3.SIDE_OPP, OPP_STYLE)
	match_id = int(Time.get_unix_time_from_system())
	# Стойки: вы — против ананаса, оппонент — за (можно поменять данными темы).
	nar.start(_theme_data, match_id, {"you": "contra", "opp": "pro"})
	_emit({
		"ev": "start", "ts": match_id,
		"first": "you" if first == ZalV3.SIDE_YOU else "opp",
		"ruleset": {"base": BASE_THESES, "steal_cards": STEAL_CARDS, "deck": "U%d T%d R%d" % [DECK_U, DECK_T, DECK_R], "freeze": CLINCH_FREEZE},
		"theme": nar.theme.id,
	})
	# Вступление: тема + стартовые позиции сторон.
	_tx_header(first)
	_narrate("ТЕМА ДЕБАТОВ: «%s».  Слово первым: %s." % [nar.topic(), ("вы" if first == ZalV3.SIDE_YOU else "оппонент")])
	var yb := _claim_of(ZalV3.SIDE_YOU, model.sides[ZalV3.SIDE_YOU].lines[0])
	var ob := _claim_of(ZalV3.SIDE_OPP, model.sides[ZalV3.SIDE_OPP].lines[0])
	_say(ZalV3.SIDE_YOU, nar.open_line(ZalV3.SIDE_YOU, yb), "start you база")
	_say(ZalV3.SIDE_OPP, nar.open_line(ZalV3.SIDE_OPP, ob), "start opp база")
	_run_until_player()


# --------------------------------------------------------------- flow ---------

func _run_until_player() -> void:
	busy = true
	var my_epoch := _epoch
	while true:
		if my_epoch != _epoch:
			return
		if model.game_over:
			_show_end(); _refresh(); return
		var st: String = model.begin_turn(model.current)
		if st == "ko" or st == "end" or st == "over":
			_show_end(); _refresh(); return
		if st == "redeploy":
			var line: Dictionary = model.sides[model.current].lines[-1]
			var claim := _claim_of(model.current, line)
			_say(model.current, nar.redeploy_line(model.current, claim), "t%d %s redeploy (страховка)" % [model.turn_count, model.current])
			var rev := {"ev": "redeploy", "side": model.current}
			rev.merge(_econ()); _emit(rev)
			model.advance(); _refresh(); continue
		if st == "pass":
			_say(model.current, nar.pass_line(model.current), "t%d %s pass" % [model.turn_count, model.current])
			var pev := {"ev": "pass", "side": model.current}
			pev.merge(_econ()); _emit(pev)
			model.advance(); _refresh(); continue
		# st == "ok"
		if model.current == ZalV3.SIDE_YOU:
			busy = false
			_refresh()
			return
		# --- ход оппонента ---
		_refresh()
		await get_tree().create_timer(AI_DELAY).timeout
		if my_epoch != _epoch:
			return
		if model.game_over:
			continue
		var act: Dictionary = model.ai_pick(ZalV3.SIDE_OPP, OPP_STYLE)
		if act.is_empty():
			model.sides[ZalV3.SIDE_OPP].passed = true
			model.advance(); continue
		if act.type == ZalV3.TYPE_RAZBOR:
			await _run_clinch(ZalV3.SIDE_OPP, ZalV3.SIDE_YOU, int(act.get("target", -1)), true)
			if my_epoch != _epoch:
				return
		else:
			var info: Dictionary = model.play_action(ZalV3.SIDE_OPP, act.type)
			_log_action(info)
		model.advance()


func _on_hand_pressed(index: int) -> void:
	if model.game_over:
		return
	var hand: Array = model.sides[ZalV3.SIDE_YOU].hand
	if index < 0 or index >= hand.size():
		return
	var card: Dictionary = hand[index]

	# Реактивный выбор в клинче.
	if awaiting_clinch:
		var want := ZalV3.TYPE_TEZIS if clinch_mode == "defend" else ZalV3.TYPE_RAZBOR
		if card.type == want:
			_clinch_decided.emit({"act": "play", "steals": bool(card.get("steals", false))})
		return

	if busy or targeting:
		return
	match card.type:
		ZalV3.TYPE_TEZIS, ZalV3.TYPE_USTANOVKA:
			var info: Dictionary = model.play_action(ZalV3.SIDE_YOU, card.type)
			_log_action(info)
			model.advance()
			_run_until_player()
		ZalV3.TYPE_RAZBOR:
			if model.sides[ZalV3.SIDE_OPP].lines.is_empty():
				return
			pending_steals = bool(card.get("steals", false))
			targeting = true
			_hint_label.text = "%s: кликни рамку оппонента, которую атакуешь" % ("КРАЖА" if pending_steals else "РАЗБОР")
			_cancel_btn.visible = true
			_refresh()


func _on_target_pressed(index: int) -> void:
	if not targeting:
		return
	var my_epoch := _epoch
	targeting = false
	_cancel_btn.visible = false
	_hint_label.text = ""
	await _run_clinch(ZalV3.SIDE_YOU, ZalV3.SIDE_OPP, index, pending_steals)
	if my_epoch != _epoch:
		return
	model.advance()
	_run_until_player()


func _cancel_targeting() -> void:
	targeting = false
	_cancel_btn.visible = false
	_hint_label.text = ""
	_refresh()


func _on_clinch_pass() -> void:
	if awaiting_clinch:
		_clinch_decided.emit({"act": "pass"})


## Интерактивная воля клинча. attacker инициирует разбором по рамке defender[idx].
func _run_clinch(attacker: String, defender: String, idx: int, prefer_steal: bool) -> void:
	busy = true
	var my_epoch := _epoch
	if idx < 0 or idx >= model.sides[defender].lines.size():
		return
	var initc: Dictionary = model.remove_attack(attacker, prefer_steal)
	var init_steals: bool = initc.get("steals", false)
	var line: Dictionary = model.sides[defender].lines[idx]
	var target_claim := _claim_of(defender, line)
	var is_callback: bool = line.closed
	clinch_side = defender
	clinch_idx = idx
	clinch_razbors = 1
	# Наррация: атака бьёт конкретный (последний) довод рамки.
	var atk_word := "кража" if init_steals else "разбор"
	var cb := "←старая" if is_callback else ""
	_say(attacker, nar.refute_line(attacker, target_claim, _top_stmt(line), initc, is_callback),
		"t%d %s clinch→%s[%d] %s%s" % [model.turn_count, attacker, defender, idx, atk_word, cb])
	_refresh()
	if attacker == ZalV3.SIDE_OPP:
		await get_tree().create_timer(CLINCH_STEP_DELAY).timeout
		if my_epoch != _epoch:
			return

	var t_added := 0
	var r_count := 1
	var atk_steals := 1 if init_steals else 0
	var atk_left_at_finish := -1  ## диагностика: карт атаки у атакующего на момент решения о добивании
	var guard := 0
	while guard < 40:
		guard += 1
		# Защитник отвечает тезисом?
		var def_plays := false
		if model.has_card(defender, ZalV3.TYPE_TEZIS):
			if defender == ZalV3.SIDE_YOU:
				var dd := await _ask_clinch("defend")
				def_plays = dd.get("act", "pass") == "play"
			else:
				def_plays = model.ai_def_will_clinch(defender, line)
				await get_tree().create_timer(CLINCH_STEP_DELAY).timeout
			if my_epoch != _epoch:
				return
		if def_plays:
			var dc: Dictionary = model.remove_card_of(defender, ZalV3.TYPE_TEZIS)
			line.theses = int(line.theses) + 1
			t_added += 1
			if not CLINCH_FREEZE:
				model.refill_side(defender)
			# Защита — новый довод (свежая ось) в стопку оспариваемой рамки.
			var stmt: Dictionary = nar.make_statement(defender, dc, _used_axes(line), "hold")
			_push_stmt(line, stmt)
			_say(defender, stmt.text, "    hold %s [%s]" % [defender, stmt.axis])
			_refresh()
		else:
			break
		# Атакующий добивает (Разбором или Кражей)?
		var atk_plays := false
		var atk_pref_steal := true
		var atk_cards := 0
		for c in model.sides[attacker].hand:
			if c.type == ZalV3.TYPE_RAZBOR:
				atk_cards += 1
		atk_left_at_finish = atk_cards
		if atk_cards > 0:
			if attacker == ZalV3.SIDE_YOU:
				var ad := await _ask_clinch("attack")
				atk_plays = ad.get("act", "pass") == "play"
				atk_pref_steal = bool(ad.get("steals", false))
			else:
				atk_plays = model.ai_atk_will_clinch(attacker, line)
				await get_tree().create_timer(CLINCH_STEP_DELAY).timeout
			if my_epoch != _epoch:
				return
		elif attacker == ZalV3.SIDE_YOU:
			# Защитили, а добить НЕЧЕМ — делаем явным, чтобы не выглядело как пропавший ход.
			_hint_label.text = "Рамку отстояли — добить нечем (нет карт атаки в руке)"
			await get_tree().create_timer(CLINCH_STEP_DELAY).timeout
		if atk_plays:
			var ac: Dictionary = model.remove_attack(attacker, atk_pref_steal)
			r_count += 1
			clinch_razbors += 1
			if ac.get("steals", false):
				atk_steals += 1
			if not CLINCH_FREEZE:
				model.refill_side(attacker)
			# Добив рефьютит только что выложенный защитный довод.
			_say(attacker, nar.press_line(attacker, _top_stmt(line), ac),
				"    press %s %s" % [attacker, ("кража" if ac.get("steals", false) else "разбор")])
			_refresh()
		else:
			break

	clinch_side = ""
	clinch_idx = -1
	clinch_razbors = 0
	var info := {"side": attacker, "type": ZalV3.TYPE_RAZBOR}
	model.clinch_finalize(attacker, defender, idx, t_added, r_count, info, atk_steals)
	var landed := r_count > t_added
	_narrate(nar.resolve_text(landed, info.get("removed", false), target_claim, int(info.get("stolen_count", 0)), not landed),
		"    resolve t%d r%d %s%s%s" % [t_added, r_count,
			("landed" if landed else "withstand"),
			(" removed" if info.get("removed", false) else ""),
			(" stolen=%d" % int(info.get("stolen_count", 0)) if int(info.get("stolen_count", 0)) > 0 else "")])
	# Синхронизация стопки доводов с числом тезисов (если рамка не снята).
	if not info.get("removed", false):
		var st: Array = line.get("statements", [])
		while st.size() > int(line.theses):
			st.pop_back()
	var ev := {
		"ev": "clinch", "attacker": attacker, "defender": defender,
		"init_steals": init_steals, "t": t_added, "r": r_count,
		"landed": landed,
		"removed": info.get("removed", false), "stolen": info.get("stolen", false),
		"stolen_count": info.get("stolen_count", 0),
		"captured": info.get("captured", false),
		"atk_left_at_finish": atk_left_at_finish,
		"target": info.get("target_name", ""),
	}
	ev.merge(_econ())
	_emit(ev)
	_refresh()


func _ask_clinch(mode: String) -> Dictionary:
	awaiting_clinch = true
	clinch_mode = mode
	if mode == "defend":
		_hint_label.text = "КЛИНЧ! Бьют вашу рамку — сыграйте ТЕЗИС в защиту, или «Пропустить»"
		_clinch_btn.text = "Пропустить (снос пройдёт)"
	else:
		_hint_label.text = "КЛИНЧ! Добейте РАЗБОРОМ или КРАЖЕЙ, или «Остановиться»"
		_clinch_btn.text = "Остановиться"
	_clinch_btn.visible = true
	_refresh()
	var d: Dictionary = await _clinch_decided
	awaiting_clinch = false
	clinch_mode = ""
	_clinch_btn.visible = false
	_hint_label.text = ""
	return d


# ----------------------------------------------------------------- view -------

func _refresh() -> void:
	var you_n: int = model.score(ZalV3.SIDE_YOU)
	var opp_n: int = model.score(ZalV3.SIDE_OPP)
	_score_label.text = "ШИРИНА — оппонент: %d   ·   вы: %d" % [opp_n, you_n]
	var z: int = model.zal()
	_zal_label.text = "ЗАЛ: %+d  (рамки + сила)" % z
	_update_bar(z)
	var you_s: Dictionary = model.sides[ZalV3.SIDE_YOU]
	var opp_s: Dictionary = model.sides[ZalV3.SIDE_OPP]
	_rebuild_frames(_opp_row, opp_s.lines, false)
	_rebuild_frames(_you_row, you_s.lines, true)
	_rebuild_hand()
	_log_rt.text = "\n".join(log_lines)


func _update_bar(z: int) -> void:
	var t := clampf(float(z) / float(ZalV3.ZAL_MAX), -1.0, 1.0)
	var center := BAR_X + BAR_W / 2.0
	var mx := center + t * (BAR_W / 2.0)
	_marker.position = Vector2(mx - 3.5, BAR_Y - 4.0)
	if z >= 0:
		_fill.position = Vector2(center, BAR_Y)
		_fill.size = Vector2(mx - center, BAR_H)
		_fill.color = Color.html("#" + COL_YOU)
	else:
		_fill.position = Vector2(mx, BAR_Y)
		_fill.size = Vector2(center - mx, BAR_H)
		_fill.color = Color.html("#" + COL_OPP)


const CARD_W := 42.0
const CARD_H := 56.0
const CARD_G := 4.0
const HAND_W := 160.0  ## карта в руке: шире старой (146), чтобы поместилась реплика-превью
const HAND_H := 132.0


func _rebuild_frames(row: HBoxContainer, lines: Array, is_you: bool) -> void:
	for c in row.get_children():
		c.queue_free()
	for i in lines.size():
		row.add_child(_make_frame_group(lines[i], is_you, i))


func _make_frame_group(line: Dictionary, is_you: bool, idx: int) -> Control:
	var theses := int(line.theses)
	var stolen := int(line.get("stolen", 0))
	var closed: bool = line.closed
	var contested: bool = (clinch_idx == idx) and ((clinch_side == ZalV3.SIDE_YOU) == is_you)
	var targetable: bool = targeting and not is_you

	var shown := mini(theses, 8)
	var ncards := 1 + shown
	var width := float(ncards) * CARD_W + float(ncards - 1) * CARD_G
	var root := Control.new()
	root.custom_minimum_size = Vector2(maxf(width, CARD_W) + 16.0, CARD_H + 30.0)
	var y0 := 26.0

	# Карта-установка показывает claim (позицию-топик), если он назначен.
	var claim_txt: String = String(line.get("claim", line.name))
	var uc := _mkcard("РАМКА\n«%s»" % _short(claim_txt), COL_USTAN, closed, contested)
	uc.position = Vector2(0, y0)
	uc.tooltip_text = claim_txt
	if targetable:
		uc.disabled = false
		uc.pressed.connect(_on_target_pressed.bind(idx))
	root.add_child(uc)

	for j in shown:
		var is_st := j >= (theses - stolen)
		var tc := _mkcard("ПЕРЕ-\nХВАТ" if is_st else "тезис", (COL_GOLD if is_st else COL_TEZIS), closed, false)
		tc.position = Vector2(float(j + 1) * (CARD_W + CARD_G), y0)
		root.add_child(tc)
	if theses > 8:
		var more := Label.new()
		more.text = "+%d" % (theses - 8)
		more.position = Vector2(width + 2.0, y0 + CARD_H / 2.0 - 8.0)
		more.add_theme_font_size_override("font_size", 11)
		more.add_theme_color_override("font_color", Color.html("#" + COL_TEZIS))
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(more)

	if contested and clinch_razbors > 0:
		for k in clinch_razbors:
			var rc := _mkcard("раз-\nбор", COL_RAZBOR, false, false)
			rc.position = Vector2(width - CARD_W + 10.0 + float(k) * 9.0, y0 - 20.0)
			root.add_child(rc)
	return root


func _mkcard(text: String, colhex: String, dim: bool, contested: bool) -> Button:
	var b := Button.new()
	b.size = Vector2(CARD_W, CARD_H)
	b.custom_minimum_size = Vector2(CARD_W, CARD_H)
	b.clip_text = false
	b.add_theme_font_size_override("font_size", 10)
	b.text = text
	var border := Color.html("#" + colhex)
	var bg := Color.html("#1c2029")
	if dim:
		border = border.darkened(0.5)
		bg = Color.html("#141820")
	if contested:
		border = Color.html("#" + COL_RAZBOR)
	b.add_theme_stylebox_override("normal", _card_style(bg, border, 2))
	b.add_theme_stylebox_override("hover", _card_style(bg.lightened(0.1), border, 2))
	b.add_theme_stylebox_override("pressed", _card_style(bg, border, 2))
	b.add_theme_stylebox_override("disabled", _card_style(bg, border, 2))
	var fcol := Color.html("#" + colhex)
	if dim:
		fcol = fcol.darkened(0.4)
	b.add_theme_color_override("font_color", fcol)
	b.add_theme_color_override("font_disabled_color", fcol)
	b.disabled = true
	return b


func _short(s: String) -> String:
	return s if s.length() <= 9 else s.substr(0, 8) + "…"


func _rebuild_hand() -> void:
	for c in _hand_row.get_children():
		c.queue_free()
	var hand: Array = model.sides[ZalV3.SIDE_YOU].hand
	var normal_turn: bool = (not busy) and (not model.game_over) and model.current == ZalV3.SIDE_YOU and not targeting
	for i in hand.size():
		var card: Dictionary = hand[i]
		var col := COL_TEZIS
		var word := "ТЕЗИС"
		match card.type:
			ZalV3.TYPE_RAZBOR:
				if card.get("steals", false):
					col = COL_USTAN; word = "КРАЖА"
				else:
					col = COL_RAZBOR; word = "РАЗБОР"
			ZalV3.TYPE_USTANOVKA:
				col = COL_USTAN; word = "УСТАНОВКА"
		var enabled := false
		if awaiting_clinch:
			var want := ZalV3.TYPE_TEZIS if clinch_mode == "defend" else ZalV3.TYPE_RAZBOR
			enabled = card.type == want
		else:
			enabled = normal_turn
		# Приём карты — её нарративная идентичность; превью — что карта примерно скажет.
		var dev: String = nar.device_label(card)
		var preview: String = nar.preview_text(ZalV3.SIDE_YOU, card)
		var col_c := Color.html("#" + col)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(HAND_W, HAND_H)
		btn.clip_text = true
		btn.tooltip_text = "%s · приём: %s\n«%s»" % [String(card.get("name", "")), dev, preview]
		var border := col_c
		btn.add_theme_stylebox_override("normal", _card_style(Color.html("#1d2129"), border, 2))
		btn.add_theme_stylebox_override("hover", _card_style(Color.html("#262c38"), border, 2))
		btn.add_theme_stylebox_override("pressed", _card_style(Color.html("#15181f"), border, 2))
		btn.add_theme_stylebox_override("disabled", _card_style(Color.html("#181b21"), border.darkened(0.35), 1))
		btn.disabled = not enabled
		btn.pressed.connect(_on_hand_pressed.bind(i))
		# Заголовок: ТИП · приём (цвет карты), приглушается у неиграбельной карты.
		# Якоря, а не фикс-size: ширина метки всегда = ширине кнопки (перенос считается верно).
		var head := Label.new()
		head.text = "%s · %s" % [word, dev]
		head.anchor_right = 1.0
		head.offset_left = 8; head.offset_top = 6; head.offset_right = -8; head.offset_bottom = 26
		head.clip_text = true
		head.add_theme_font_size_override("font_size", 12)
		head.add_theme_color_override("font_color", col_c if enabled else col_c.darkened(0.35))
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(head)
		# Тело: реплика-превью (что карта примерно произнесёт). При розыгрыше катается заново.
		# Растягивается на всю кнопку якорями → autowrap переносит по словам по реальной ширине,
		# clip_contents страхует от вылета длинной реплики за низ карты.
		var body := Label.new()
		body.text = "«%s»" % preview
		body.anchor_right = 1.0; body.anchor_bottom = 1.0
		body.offset_left = 8; body.offset_top = 28; body.offset_right = -8; body.offset_bottom = -8
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.clip_contents = true
		body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		body.add_theme_font_size_override("font_size", 10)
		var bodycol := Color.html("#cdd4df")
		body.add_theme_color_override("font_color", bodycol if enabled else bodycol.darkened(0.45))
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(body)
		_hand_row.add_child(btn)


func _card_style(bg: Color, border: Color, w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(w)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	return sb


# --------------------------------------------------------------- narrative ----

func _who(side: String) -> String:
	return "Вы" if side == ZalV3.SIDE_YOU else "Оппонент"


## Реплика стороны в стенограмму. tag — мех. действие, породившее реплику (для общего лога).
func _say(side: String, text: String, tag: String = "") -> void:
	var col := COL_YOU if side == ZalV3.SIDE_YOU else COL_OPP
	_log("[color=#%s]— %s (%s):[/color] %s" % [col, _who(side), nar.stance_label(side), text])
	_tx(tag, "%s (%s): %s" % [_who(side), nar.stance_label(side), text])


## Авторская наррация (голос зала / ремарки).
func _narrate(text: String, tag: String = "") -> void:
	_log("[color=#%s][i]%s[/i][/color]" % [COL_DIM, text])
	_tx(tag, "· " + text)


# --- общий транскрипт (нарратив ↔ действия в одном файле, в порядке исполнения) ---

func _tx_header(first: String) -> void:
	_tx_write("")
	_tx_write("=".repeat(72))
	_tx_write("МАТЧ %d · тема «%s» · вы=%s · опп=%s · первым=%s · %s" % [
		match_id, nar.topic(), nar.stance_label(ZalV3.SIDE_YOU), nar.stance_label(ZalV3.SIDE_OPP),
		("вы" if first == ZalV3.SIDE_YOU else "оппонент"), Time.get_datetime_string_from_system(true, true)])
	_tx_write("-".repeat(72))


func _tx(tag: String, body: String) -> void:
	if tag == "":
		_tx_write(body)
	else:
		_tx_write("%-30s %s" % ["[" + tag + "]", body])


func _tx_write(s: String) -> void:
	var f: FileAccess
	if FileAccess.file_exists(TX_PATH):
		f = FileAccess.open(TX_PATH, FileAccess.READ_WRITE)
		if f:
			f.seek_end()
	else:
		f = FileAccess.open(TX_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_line(s)
	f.close()


## Ленивое назначение claim рамке (в порядке стойки). Топик приколот к рамке.
func _claim_of(side: String, line: Dictionary) -> String:
	var c := String(line.get("claim", ""))
	if c == "":
		c = nar.next_headline(side)
		line["claim"] = c
	return c


func _push_stmt(line: Dictionary, stmt: Dictionary) -> void:
	if not line.has("statements"):
		line["statements"] = []
	line["statements"].append(stmt)


func _top_stmt(line: Dictionary) -> Dictionary:
	var st: Array = line.get("statements", [])
	return {} if st.is_empty() else st.back()


## id осей, уже звучавших на рамке (чтобы тезис брал свежую ось).
func _used_axes(line: Dictionary) -> Array:
	var out: Array = []
	for s in line.get("statements", []):
		out.append(s.get("axis", ""))
	return out


## Ход без клинча (Тезис на свою рамку / Установка). Зовётся для обеих сторон.
func _log_action(info: Dictionary) -> void:
	if info.is_empty():
		return
	var ev := {"ev": "move", "side": info.side, "type": info.type, "name": info.get("name", "")}
	ev.merge(_econ())
	_emit(ev)
	var side: String = info.side
	var card := {"type": info.type, "name": info.get("name", ""), "steals": false}
	match info.type:
		ZalV3.TYPE_TEZIS:
			var line: Dictionary = model.sides[side].lines[-1]
			_claim_of(side, line)  # рамке нужна headline-позиция (топик)
			var stmt: Dictionary = nar.make_statement(side, card, _used_axes(line), "assert")
			_push_stmt(line, stmt)
			_say(side, stmt.text, "t%d %s тезис[%s/%s]" % [model.turn_count, side, stmt.device, stmt.axis])
		ZalV3.TYPE_USTANOVKA:
			var line: Dictionary = model.sides[side].lines[-1]
			var claim := _claim_of(side, line)
			_say(side, nar.open_line(side, claim, "open"), "t%d %s установка→рамка" % [model.turn_count, side])
		ZalV3.TYPE_RAZBOR:
			pass  # атаки идут через клинч


func _show_end() -> void:
	busy = true
	_restart_btn.visible = true
	_cancel_btn.visible = false
	_clinch_btn.visible = false
	targeting = false
	awaiting_clinch = false
	var reason := String(model.end_reason)
	var winner_s := "you" if model.winner == ZalV3.SIDE_YOU else ("opp" if model.winner == ZalV3.SIDE_OPP else "draw")
	var ev := {"ev": "end", "winner": winner_s, "reason": reason}
	ev.merge(_econ())
	_emit(ev)
	var verdict: String = nar.verdict_text(
		("you" if model.winner == ZalV3.SIDE_YOU else ("opp" if model.winner == ZalV3.SIDE_OPP else "")),
		reason, nar.stance_label(ZalV3.SIDE_YOU), nar.stance_label(ZalV3.SIDE_OPP))
	_narrate("⚖ " + verdict, "END %s winner=%s рамки %d:%d zal=%+d" % [
		reason, winner_s, model.score(ZalV3.SIDE_YOU), model.score(ZalV3.SIDE_OPP), model.zal()])
	if model.winner == ZalV3.SIDE_YOU:
		_show_flash("ЗАЛ ВАШ — ПОБЕДА", Color.html("#" + COL_YOU))
	elif model.winner == ZalV3.SIDE_OPP:
		_show_flash("ЗАЛ ЗА ОППОНЕНТОМ", Color.html("#" + COL_OPP))
	else:
		_show_flash("НИЧЬЯ", Color.html("#" + COL_DIM))


func _show_flash(txt: String, col: Color) -> void:
	_flash.text = txt
	_flash.add_theme_color_override("font_color", col)
	_flash.modulate.a = 1.0


# --- запись катки (JSONL) ---

func _econ() -> Dictionary:
	var y: Dictionary = model.sides[ZalV3.SIDE_YOU]
	var o: Dictionary = model.sides[ZalV3.SIDE_OPP]
	return {
		"turn": model.turn_count,
		"you_frames": model.score(ZalV3.SIDE_YOU),
		"opp_frames": model.score(ZalV3.SIDE_OPP),
		"zal": model.zal(),
		"you_hand": y.hand.size(), "opp_hand": o.hand.size(),
		"you_deck": y.draw.size(), "opp_deck": o.draw.size(),
	}


func _emit(d: Dictionary) -> void:
	d["m"] = match_id
	var f: FileAccess
	if FileAccess.file_exists(LOG_PATH):
		f = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
		if f:
			f.seek_end()
	else:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_line(JSON.stringify(d))
	f.close()


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 90:
		log_lines = log_lines.slice(log_lines.size() - 90, log_lines.size())
