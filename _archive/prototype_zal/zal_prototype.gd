extends Control

## DUELOGUE — прототип ядра «ЗАЛ» + КОМБО.
## Самодостаточная тест-сцена: НЕ зависит от основного движка и ничего в нём не трогает.
## Запуск: открыть эту сцену и нажать F6 (Run Current Scene). F5 запускает СТАРУЮ игру.
##
## Ядро петли (только оно, без щитов/статов/накала):
##   1. ЗАЛ — одна шкала-перетягивание [-MAX..+MAX]. Кто дотянул зал до своего края — выиграл.
##   2. КОМБО — бьёшь в одну стихию (логика=синяя / эмоция=красная) подряд → растёт счётчик
##      КОМБО, и каждый следующий удар качает зал сильнее. Сменил стихию — комбо сбросилось.
##   3. ИМЕННЫЕ ПРИЁМЫ — некоторые пары карт подряд складываются в именной приём (список
##      справа) и дают мощный доп. качок со вспышкой. Повтор той же карты — слабее (сбивает темп).

const ROOM_MAX := 14
const CHAIN_CAP := 3       ## потолок бонуса за длину комбо
const HAND_SIZE := 5
const AI_DELAY := 0.7

const COL_HOT := "d9594c"
const COL_COLD := "4c7cd9"
const COL_YOU := "6fcf7f"
const COL_OPP := "d98c4c"
const COL_GOLD := "ffd24a"
const COL_DIM := "8a93a3"

# Геометрия шкалы.
const BAR_X := 226.0
const BAR_W := 700.0
const BAR_Y := 96.0
const BAR_H := 34.0

const CARD_POOL := [
	{"name": "Ложная дилемма", "stance": "cold", "sway": 3, "quote": "Либо с нами, либо нет"},
	{"name": "Соломенное чучело", "stance": "cold", "sway": 3, "quote": "Ты предлагаешь всё снести?"},
	{"name": "Reductio ad absurdum", "stance": "cold", "sway": 3, "quote": "Доведём до абсурда"},
	{"name": "Контрпример", "stance": "cold", "sway": 2, "quote": "А вот случай иной"},
	{"name": "К авторитету", "stance": "cold", "sway": 3, "quote": "Это доказано наукой"},
	{"name": "Уточнение", "stance": "cold", "sway": 2, "quote": "Определимся с терминами"},
	{"name": "Ad hominem", "stance": "hot", "sway": 2, "quote": "Что ты понимаешь?"},
	{"name": "Ad populum", "stance": "hot", "sway": 2, "quote": "Все это понимают"},
	{"name": "Сарказм", "stance": "hot", "sway": 2, "quote": "Ну да, гениально"},
	{"name": "Личная история", "stance": "hot", "sway": 3, "quote": "У меня было так же"},
	{"name": "Скользкая дорожка", "stance": "hot", "sway": 2, "quote": "Дальше — только хуже"},
	{"name": "Гипербола", "stance": "hot", "sway": 3, "quote": "Это катастрофа!"},
]

# Именные приёмы: пара карт подряд (a → b) на своей линии → доп. качок + вспышка.
const NAMED := [
	{"a": "Уточнение", "b": "Reductio ad absurdum", "name": "Логический капкан", "bonus": 4, "col": COL_COLD},
	{"a": "Личная история", "b": "Гипербола", "name": "Эмоциональный шквал", "bonus": 4, "col": COL_HOT},
	{"a": "Ad populum", "b": "Ad hominem", "name": "Двойной охват", "bonus": 4, "col": COL_HOT},
]

var room := 0
var you_thread: Array = []
var opp_thread: Array = []
var you_chain := 0
var you_chain_stance := ""
var opp_chain := 0
var opp_chain_stance := ""
var you_deck: Array = []
var opp_deck: Array = []
var you_hand: Array = []
var opp_hand: Array = []
var log_lines: Array = []
var game_over := false
var awaiting := false

var _marker: ColorRect
var _fill: ColorRect
var _room_label: Label
var _you_combo: Label
var _opp_combo: Label
var _you_thread_rt: RichTextLabel
var _opp_thread_rt: RichTextLabel
var _log_rt: RichTextLabel
var _flash: Label
var _restart_btn: Button
var _hand_buttons: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_new_match()


# ---------------------------------------------------------------- UI ----------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color.html("#15171c")
	bg.position = Vector2.ZERO
	bg.size = Vector2(1152, 648)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_mklabel("DUELOGUE · прототип «ЗАЛ» — комбо", 20, 10, 20, Color.html("#e8e8e8"))
	_mklabel("Перетяни ЗАЛ в свою сторону. Бей в одну стихию подряд — растёт КОМБО. Собери именной приём из списка справа.",
		20, 38, 12, Color.html("#" + COL_DIM))

	_room_label = _mklabel("ЗАЛ: +0", 510, 64, 18, Color.html("#e8e8e8"))
	_mklabel("ОППОНЕНТ", 110, 100, 14, Color.html("#" + COL_OPP))
	_mklabel("ВЫ", 940, 100, 14, Color.html("#" + COL_YOU))

	var bar_bg := ColorRect.new()
	bar_bg.color = Color.html("#2a2e38")
	bar_bg.position = Vector2(BAR_X, BAR_Y)
	bar_bg.size = Vector2(BAR_W, BAR_H)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar_bg)

	_fill = ColorRect.new()
	_fill.position = Vector2(BAR_X + BAR_W / 2.0, BAR_Y)
	_fill.size = Vector2(0, BAR_H)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)

	var tick := ColorRect.new()
	tick.color = Color.html("#cfd6e0")
	tick.position = Vector2(BAR_X + BAR_W / 2.0 - 1.0, BAR_Y - 6.0)
	tick.size = Vector2(2, BAR_H + 12.0)
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tick)

	_marker = ColorRect.new()
	_marker.color = Color.WHITE
	_marker.size = Vector2(8, BAR_H + 8.0)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_marker)

	_opp_combo = _mklabel("", 110, 138, 15, Color.html("#" + COL_OPP))
	_you_combo = _mklabel("", 880, 138, 15, Color.html("#" + COL_YOU))

	_mklabel("Линия оппонента:", 20, 178, 13, Color.html("#" + COL_OPP))
	_opp_thread_rt = _mkrich(180, 174, 700, 26, false)
	_mklabel("Ваша линия:", 20, 210, 13, Color.html("#" + COL_YOU))
	_you_thread_rt = _mkrich(180, 206, 700, 26, false)

	# Список именных приёмов (movelist).
	_mklabel("ИМЕННЫЕ ПРИЁМЫ", 905, 176, 13, Color.html("#e8e8e8"))
	var moves := _mkrich(905, 198, 232, 130, false)
	var lines: Array = []
	for r in NAMED:
		lines.append("[color=#%s]%s[/color]\n  %s → %s" % [r["col"], r["name"], r["a"], r["b"]])
	moves.text = "\n".join(lines)

	_log_rt = _mkrich(20, 250, 860, 195, true)

	_flash = Label.new()
	_flash.position = Vector2(0, 268)
	_flash.size = Vector2(1152, 90)
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_flash.add_theme_font_size_override("font_size", 50)
	_flash.modulate.a = 0.0
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_restart_btn = Button.new()
	_restart_btn.text = "Новая партия"
	_restart_btn.position = Vector2(940, 360)
	_restart_btn.size = Vector2(190, 44)
	_restart_btn.visible = false
	_restart_btn.pressed.connect(_new_match)
	add_child(_restart_btn)


func _mklabel(txt: String, x: float, y: float, fsize: int = 14, col: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = txt
	l.position = Vector2(x, y)
	l.size = Vector2(1110, 24)
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


# ------------------------------------------------------------- match ----------

func _new_match() -> void:
	game_over = false
	awaiting = false
	room = 0
	you_thread.clear()
	opp_thread.clear()
	you_chain = 0
	you_chain_stance = ""
	opp_chain = 0
	opp_chain_stance = ""
	you_hand.clear()
	opp_hand.clear()
	_fill_deck(you_deck)
	_fill_deck(opp_deck)
	for i in HAND_SIZE:
		_draw_card(you_hand, you_deck)
		_draw_card(opp_hand, opp_deck)
	log_lines = ["Новая партия. Тяни зал в свою сторону."]
	_flash.modulate.a = 0.0
	_restart_btn.visible = false

	if randf() < 0.5:
		_log("Оппонент берёт слово первым.")
		_ai_move()
	_refresh()


func _fill_deck(deck: Array) -> void:
	deck.clear()
	for card in CARD_POOL:
		deck.append(card)
		deck.append(card)
	deck.shuffle()


func _draw_card(hand: Array, deck: Array) -> void:
	if deck.is_empty():
		_fill_deck(deck)
	if not deck.is_empty():
		hand.append(deck.pop_back())


# --------------------------------------------------------------- turns --------

func _on_card_pressed(i: int) -> void:
	if game_over or awaiting:
		return
	if i < 0 or i >= you_hand.size():
		return
	var card: Dictionary = you_hand[i]
	you_hand.remove_at(i)
	_draw_card(you_hand, you_deck)
	_resolve_card("you", card)
	if game_over:
		_refresh()
		return
	awaiting = true
	_refresh()
	await get_tree().create_timer(AI_DELAY).timeout
	if game_over:
		awaiting = false
		_refresh()
		return
	_ai_move()
	awaiting = false
	_refresh()


func _ai_move() -> void:
	if game_over:
		return
	var idx := _ai_choose()
	if idx < 0 or idx >= opp_hand.size():
		return
	var card: Dictionary = opp_hand[idx]
	opp_hand.remove_at(idx)
	_draw_card(opp_hand, opp_deck)
	_resolve_card("opp", card)


func _ai_choose() -> int:
	var prev := String(opp_thread[-1]["name"]) if opp_thread.size() > 0 else ""
	# 1. Завершить именной приём прямо сейчас.
	for i in opp_hand.size():
		if not _match_named(prev, String(opp_hand[i]["name"])).is_empty():
			return i
	# 2/3. Оценка: качок + бонус комбо + задел под именной приём, минус повтор.
	var best := -1
	var best_score := -999.0
	for i in opp_hand.size():
		var c: Dictionary = opp_hand[i]
		var score := float(c["sway"])
		if opp_chain_stance == c["stance"]:
			score += float(mini(opp_chain, CHAIN_CAP))
		for r in NAMED:
			if c["name"] == r["a"] and _hand_has(opp_hand, String(r["b"])):
				score += 1.5
		if prev == String(c["name"]):
			score -= 2.0
		score += randf() * 0.8
		if score > best_score:
			best_score = score
			best = i
	return best if best >= 0 else 0


# ------------------------------------------------------------- resolve --------

func _resolve_card(actor: String, card: Dictionary) -> void:
	var thread := _thread_for(actor)
	var prev_name := String(thread[-1]["name"]) if thread.size() > 0 else ""
	var who := "[color=#%s]%s:[/color]" % [(COL_YOU if actor == "you" else COL_OPP), ("Вы" if actor == "you" else "Оппонент")]

	var chain := you_chain if actor == "you" else opp_chain
	var cstance := you_chain_stance if actor == "you" else opp_chain_stance
	var repeat := prev_name == String(card["name"])

	if repeat:
		chain = 1
		cstance = String(card["stance"])
	elif cstance == card["stance"]:
		chain += 1
	else:
		chain = 1
		cstance = String(card["stance"])

	if actor == "you":
		you_chain = chain
		you_chain_stance = cstance
	else:
		opp_chain = chain
		opp_chain_stance = cstance

	var bonus := 0 if repeat else mini(chain - 1, CHAIN_CAP)
	var base := int(card["sway"])
	var swing := maxi(1, base - 1) if repeat else base + bonus

	thread.append({"name": card["name"], "stance": card["stance"]})
	_log("%s %s — «%s»" % [who, card["name"], card["quote"]])
	if repeat:
		_log("   [color=#%s]повтор — слабее, комбо сбито[/color]" % COL_DIM)
	elif bonus > 0:
		_log("   [color=#%s]КОМБО ×%d: +%d[/color]" % [(COL_YOU if actor == "you" else COL_OPP), chain, bonus])

	var before := room
	_apply_swing(actor, swing)
	_log("   зал %+d → %d" % [room - before, room])

	# Именной приём.
	var named := _match_named(prev_name, String(card["name"]))
	if not named.is_empty() and not game_over:
		_show_flash(String(named["name"]) + "!", Color.html("#" + String(named["col"])), false)
		var before2 := room
		_apply_swing(actor, int(named["bonus"]))
		_log("   [b][color=#%s]ПРИЁМ «%s»: зал %+d → %d[/color][/b]" % [named["col"], named["name"], room - before2, room])


func _apply_swing(actor: String, amount: int) -> void:
	if actor == "you":
		room = clampi(room + amount, -ROOM_MAX, ROOM_MAX)
	else:
		room = clampi(room - amount, -ROOM_MAX, ROOM_MAX)
	if not game_over and room >= ROOM_MAX:
		_end(true)
	elif not game_over and room <= -ROOM_MAX:
		_end(false)


func _end(you_won: bool) -> void:
	game_over = true
	if you_won:
		_show_flash("ВЫ ВЫИГРАЛИ ЗАЛ", Color.html("#" + COL_YOU), true)
		_log("[b][color=#%s]Зал ваш. Победа.[/color][/b]" % COL_YOU)
	else:
		_show_flash("ЗАЛ ЗА ОППОНЕНТОМ", Color.html("#" + COL_OPP), true)
		_log("[b][color=#%s]Зал ушёл к оппоненту. Поражение.[/color][/b]" % COL_OPP)
	_restart_btn.visible = true


# ---------------------------------------------------------------- helpers -----

func _thread_for(actor: String) -> Array:
	return you_thread if actor == "you" else opp_thread


func _match_named(prev_name: String, cur_name: String) -> Dictionary:
	if prev_name == "":
		return {}
	for r in NAMED:
		if String(r["a"]) == prev_name and String(r["b"]) == cur_name:
			return r
	return {}


func _hand_has(hand: Array, card_name: String) -> bool:
	for c in hand:
		if String(c["name"]) == card_name:
			return true
	return false


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 40:
		log_lines = log_lines.slice(log_lines.size() - 40, log_lines.size())


# ----------------------------------------------------------------- view -------

func _refresh() -> void:
	_update_meter()
	_update_threads()
	_update_combo()
	_update_log()
	_build_hand()


func _update_meter() -> void:
	var t := clampf(float(room) / float(ROOM_MAX), -1.0, 1.0)
	var center_x := BAR_X + BAR_W / 2.0
	var marker_x := center_x + t * (BAR_W / 2.0)
	_marker.position = Vector2(marker_x - 4.0, BAR_Y - 4.0)
	if room >= 0:
		_fill.position = Vector2(center_x, BAR_Y)
		_fill.size = Vector2(marker_x - center_x, BAR_H)
		_fill.color = Color.html("#" + COL_YOU)
	else:
		_fill.position = Vector2(marker_x, BAR_Y)
		_fill.size = Vector2(center_x - marker_x, BAR_H)
		_fill.color = Color.html("#" + COL_OPP)
	_room_label.text = "ЗАЛ: %+d" % room


func _update_combo() -> void:
	_you_combo.text = ("КОМБО ×%d" % you_chain) if you_chain >= 2 else ""
	_opp_combo.text = ("КОМБО ×%d" % opp_chain) if opp_chain >= 2 else ""


func _update_threads() -> void:
	_opp_thread_rt.text = _thread_bb(opp_thread)
	_you_thread_rt.text = _thread_bb(you_thread)


func _thread_bb(thread: Array) -> String:
	var parts: Array = []
	var start := maxi(0, thread.size() - 8)
	for i in range(start, thread.size()):
		var e: Dictionary = thread[i]
		var col := COL_HOT if e["stance"] == "hot" else COL_COLD
		parts.append("[color=#%s]%s[/color]" % [col, e["name"]])
	return "   ·   ".join(parts)


func _update_log() -> void:
	_log_rt.text = "\n".join(log_lines)


func _build_hand() -> void:
	for b in _hand_buttons:
		if is_instance_valid(b):
			b.queue_free()
	_hand_buttons.clear()
	for i in you_hand.size():
		var c: Dictionary = you_hand[i]
		var btn := Button.new()
		btn.position = Vector2(26 + i * 224, 470)
		btn.size = Vector2(214, 150)
		btn.clip_text = false
		btn.add_theme_font_size_override("font_size", 13)
		var is_hot: bool = c["stance"] == "hot"
		var col := COL_HOT if is_hot else COL_COLD
		var kind := "эмоция" if is_hot else "логика"
		btn.text = "%s\n[%s]\nзал +%d\n«%s»" % [c["name"], kind, int(c["sway"]), c["quote"]]
		btn.add_theme_color_override("font_color", Color.html("#" + col))
		btn.disabled = game_over or awaiting
		btn.pressed.connect(_on_card_pressed.bind(i))
		add_child(btn)
		_hand_buttons.append(btn)


func _show_flash(txt: String, col: Color, persist: bool) -> void:
	_flash.text = txt
	_flash.add_theme_color_override("font_color", col)
	_flash.modulate.a = 1.0
	if not persist:
		var tw := create_tween()
		tw.tween_interval(0.4)
		tw.tween_property(_flash, "modulate:a", 0.0, 1.0)
