extends Control

## DUELOGUE — ЭКРАН ДЕБАТОВ (чистый view). Каркас UI авторится НОДАМИ в debate_screen.tscn
## (двигается/настраивается в редакторе); скрипт лишь ссылается на них (%Name) и рендерит
## состояние из модели по сигналам EventBus, шлёт интенты контроллеру. Динамика (карты руки и
## рамки) пересобирается кодом в редактируемые контейнеры OppRow/YouRow/HandRow.
## Стенограмма — выезжающий справа ящик (кнопка-тумблер слева от меню). F6.

const ZalV3 := preload("res://duelogue/core/rules/rules_core.gd")  ## ядро правил — константы SIDE_*/TYPE_*/ZAL_MAX
const BattleController := preload("res://duelogue/app/battle_controller.gd")
const CharacterCore := preload("res://duelogue/core/characters/character_core.gd")  ## ядро персонажей (актёры на сцену)
const ReadingPace := preload("res://duelogue/core/narrative/reading_pace.gd")  ## настройка скорости печати (меню)

const COL_TEZIS := "6fcf7f"
const COL_RAZBOR := "d9594c"
const COL_USTAN := "ffd24a"
const COL_YOU := "6fcf7f"
const COL_OPP := "d98c4c"
const COL_DIM := "8a93a3"
const COL_GOLD := "ffd24a"

const CARD_W := 42.0
const CARD_H := 56.0
const CARD_G := 4.0
const HAND_W := 160.0
const HAND_H := 132.0
## Тезисы внутри рамки НЕкликабельны (кликабельна только сама РАМКА) — им можно ложиться
## внахлёст плотно, как карты Разбора в стопке клинча. Тот же шаг (9px), тот же приём.
const THESIS_PITCH_MIN := 9.0
## Отступ МЕЖДУ рамками сжимаем мягче — рамки кликабельны (цель атаки), слишком плотно
## нельзя, иначе промахивающийся клик по соседней рамке. Не ниже этой доли от дефолта.
const FRAME_SEP_MIN_FACTOR := 0.3

var _drawer_closed_x := 0.0  ## закрытое (за правым краем) положение ящика — из ширины экрана
var _drawer_open_x := 0.0    ## открытое положение — из ширины экрана И ширины самого ящика
                              ## (считаются в _ready из реальных нод, не задублированы числом)

var controller: Node
var model: RefCounted   ## ссылка на ядро правил контроллера (только чтение для рендера)
var nar: RefCounted     ## ссылка на нарратив (превью/стойки для рендера руки)
var log_lines: Array = []
var _drawer_open := false
var _menu_overlay: Control
## Дефолтный (несжатый) отступ между рамками — читается из сцены ОДИН раз в _ready, ДО того
## как _rebuild_frames впервые применит компрессию (иначе каждый рефреш ужимал бы уже сжатое
## значение всё сильнее — компрессия накапливалась бы, а не считалась от истинного дефолта).
var _opp_sep0 := 0.0
var _you_sep0 := 0.0
var _gate_ticks: Array = []  ## риски порогов зал-гейта на баре ({node, level}), создаются лениво

@onready var _stage: Control = $Stage
@onready var _score_label: Label = %ScoreLabel
@onready var _zal_label: Label = %ZalLabel
@onready var _hint_label: Label = %HintLabel
@onready var _marker: ColorRect = %BarMarker
@onready var _fill: ColorRect = %BarFill
@onready var _opp_row: HBoxContainer = %OppRow
@onready var _you_row: HBoxContainer = %YouRow
@onready var _hand_row: HBoxContainer = %HandRow
@onready var _draw_count: Label = %DrawCount
@onready var _log_rt: RichTextLabel = %Log
@onready var _flash: Label = %Flash
@onready var _restart_btn: Button = %RestartBtn
@onready var _cancel_btn: Button = %CancelBtn
@onready var _clinch_btn: Button = %ClinchBtn
@onready var _drawer: Control = %TranscriptDrawer
@onready var _bar_bg: ColorRect = %BarBg  ## геометрия бара ЗАЛа читается отсюда, не дублируется числами
@onready var _reaction: Control = $ReactionScene  ## мини-сцена реакции (Ace Attorney-стиль)


func _ready() -> void:
	controller = BattleController.new()
	add_child(controller)  # _ready контроллера создаёт model/nar/ai
	model = controller.model
	nar = controller.nar
	# Ядро персонажей кладёт актёров в слой сцены и режиссирует мини-сцену реакции.
	var chars := CharacterCore.new()
	chars.bind(_stage, _reaction)
	add_child(chars)
	_opp_sep0 = float(_opp_row.get_theme_constant("separation"))
	_you_sep0 = float(_you_row.get_theme_constant("separation"))
	_build_menu()  # оверлей паузы (модальный, строится кодом)
	# Закрытое/открытое положение ящика — из реальной ширины экрана и самого ящика, не числами.
	_drawer_closed_x = size.x
	_drawer_open_x = size.x - _drawer.size.x
	_drawer.position.x = _drawer_closed_x
	# Подписка на шину партии.
	EventBus.match_started.connect(_on_match_started)
	EventBus.utterance.connect(_on_utterance)
	EventBus.narration.connect(_on_narration)
	EventBus.board_changed.connect(_on_board_changed)
	EventBus.match_ended.connect(_on_match_ended)
	controller.start_match()


# --------------------------------------------------- интенты игрока → контроллер

func _on_hand_pressed(index: int) -> void:
	controller.play_hand(index)


func _on_target_pressed(index: int) -> void:
	controller.choose_target(index)


func _cancel_targeting() -> void:
	controller.cancel_targeting()


func _on_clinch_pass() -> void:
	controller.clinch_pass()


func _new_match() -> void:
	controller.restart()


## Выезжающий ящик стенограммы (тумблер слева от меню).
func _toggle_drawer() -> void:
	_drawer_open = not _drawer_open
	var target := _drawer_open_x if _drawer_open else _drawer_closed_x
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_drawer, "position:x", target, 0.25)


# ------------------------------------------------- сигналы шины → обновление UI

func _on_match_started(_info: Dictionary) -> void:
	log_lines = []
	_restart_btn.visible = false
	_flash.modulate.a = 0.0
	_log_rt.text = ""
	_refresh()


func _on_utterance(side: String, text: String, meta: Dictionary) -> void:
	var col := COL_YOU if side == ZalV3.SIDE_YOU else COL_OPP
	var who := "Вы" if side == ZalV3.SIDE_YOU else "Оппонент"
	_log("[color=#%s]— %s (%s):[/color] %s" % [col, who, String(meta.get("stance", "")), text])
	_log_rt.text = "\n".join(log_lines)


func _on_narration(text: String, _meta: Dictionary) -> void:
	_log("[color=#%s][i]%s[/i][/color]" % [COL_DIM, text])
	_log_rt.text = "\n".join(log_lines)


func _on_board_changed() -> void:
	_refresh()


func _on_match_ended(winner: String, reason: String, _verdict: String) -> void:
	_restart_btn.visible = true
	if winner == "you":
		_show_flash("ЗАЛ УНЕСЁН — ОВАЦИЯ!" if reason == "crowd" else "ЗАЛ ВАШ — ПОБЕДА",
			Color.html("#" + COL_YOU))
	elif winner == "opp":
		_show_flash("ЗАЛ УШЁЛ С ОППОНЕНТОМ" if reason == "crowd" else "ЗАЛ ЗА ОППОНЕНТОМ",
			Color.html("#" + COL_OPP))
	else:
		_show_flash("НИЧЬЯ", Color.html("#" + COL_DIM))
	_refresh()


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 90:
		log_lines = log_lines.slice(log_lines.size() - 90, log_lines.size())


# ----------------------------------------------------------------- view -------

func _refresh() -> void:
	if model == null:
		return
	var you_n: int = model.score(ZalV3.SIDE_YOU)
	var opp_n: int = model.score(ZalV3.SIDE_OPP)
	_score_label.text = "ШИРИНА — оппонент: %d   ·   вы: %d" % [opp_n, you_n]
	var z: int = model.zal()
	# Зал-гейт: фаворит зала — под прицелом (его тонкие рамки захватываемы целиком).
	var my_reach: int = model.capture_threshold(ZalV3.SIDE_YOU)   # моя сила захвата
	var opp_reach: int = model.capture_threshold(ZalV3.SIDE_OPP)  # его сила захвата
	var gate_note := ""
	if opp_reach >= 2:
		gate_note = "  ·  вы фаворит: ваши рамки ≤%d ШАТАЮТСЯ" % opp_reach
	elif my_reach >= 2:
		gate_note = "  ·  фаворит — оппонент: его рамки ≤%d ШАТАЮТСЯ" % my_reach
	# «Счёт судьи» зал-нокаута перекрывает гейт-заметку: у черты это главный факт на столе.
	if int(model.zal_ko) > 0:
		var sy := int(model.crowd_streak.get(ZalV3.SIDE_YOU, 0))
		var so := int(model.crowd_streak.get(ZalV3.SIDE_OPP, 0))
		if sy > 0:
			gate_note = "  ·  ЗАЛ СКАНДИРУЕТ ЗА ВАС: %d/%d" % [sy, int(model.zal_hold)]
		elif so > 0:
			gate_note = "  ·  ЗАЛ СКАНДИРУЕТ: %d/%d — ВЕРНИТЕ ЗАЛ!" % [so, int(model.zal_hold)]
	_zal_label.text = "ЗАЛ: %+d  (рамки + сила)%s" % [z, gate_note]
	_update_bar(z)
	_rebuild_frames(_opp_row, model.sides[ZalV3.SIDE_OPP].lines, false, _opp_sep0)
	_rebuild_frames(_you_row, model.sides[ZalV3.SIDE_YOU].lines, true, _you_sep0)
	_rebuild_hand()
	_draw_count.text = str(model.sides[ZalV3.SIDE_YOU].draw.size())
	_update_controls()


## Подсказка и кнопки клинча/отмены — из режима ввода контроллера.
func _update_controls() -> void:
	var mode := String(controller.input_mode())
	_hint_label.text = String(controller.hint_text)
	_cancel_btn.visible = mode == "target"
	if mode == "clinch_defend":
		_clinch_btn.text = "Пропустить (снос пройдёт)"
		_clinch_btn.visible = true
	elif mode == "clinch_attack":
		_clinch_btn.text = "Остановиться"
		_clinch_btn.visible = true
	else:
		_clinch_btn.visible = false


## Геометрия бара читается из фактического %BarBg (той же местной системы координат внутри
## ZalBar, что и у _marker/_fill — все трое сиблинги) — подвинешь/растянешь BarBg в редакторе,
## заливка и маркер сами последуют, никаких чисел в скрипте держать в синхроне не нужно.
func _update_bar(z: int) -> void:
	var bar_x := _bar_bg.position.x
	var bar_y := _bar_bg.position.y
	var bar_w := _bar_bg.size.x
	var bar_h := _bar_bg.size.y
	# Шкала бара = черта зал-нокаута (край достижим и означает TKO); без TKO — ZAL_MAX.
	var zmax := int(model.zal_ko) if int(model.zal_ko) > 0 else ZalV3.ZAL_MAX
	var t := clampf(float(z) / float(zmax), -1.0, 1.0)
	var center := bar_x + bar_w / 2.0
	var mx := center + t * (bar_w / 2.0)
	_update_gate_ticks(center, bar_w, bar_y, bar_h, zmax)
	_marker.position = Vector2(mx - 3.5, bar_y - 4.0)
	if z >= 0:
		_fill.position = Vector2(center, bar_y)
		_fill.size = Vector2(mx - center, bar_h)
		_fill.color = Color.html("#" + COL_YOU)
	else:
		_fill.position = Vector2(mx, bar_y)
		_fill.size = Vector2(center - mx, bar_h)
		_fill.color = Color.html("#" + COL_OPP)


## Риски порогов зал-гейта на баре (±gate_x, ±gate_y): стрелка пересекла риску —
## у фаворита зашатались рамки. Создаются один раз, позиционируются с баром.
func _update_gate_ticks(center: float, bar_w: float, bar_y: float, bar_h: float, zmax: int) -> void:
	if model.gate_x <= 0:
		return
	if _gate_ticks.is_empty():
		var levels := [-model.gate_y, -model.gate_x, model.gate_x, model.gate_y]
		for lv in levels:
			if lv == 0:
				continue
			var tick := ColorRect.new()
			tick.color = Color.html("#" + COL_RAZBOR)
			tick.color.a = 0.55
			tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_bar_bg.get_parent().add_child(tick)
			_gate_ticks.append({"node": tick, "level": lv})
		# Риски под маркером/заливкой по z-порядку не мешают — они узкие и тусклее.
	for gt in _gate_ticks:
		var node: ColorRect = gt.node
		var frac := clampf(float(gt.level) / float(zmax), -1.0, 1.0)
		node.position = Vector2(center + frac * (bar_w / 2.0) - 1.0, bar_y - 3.0)
		node.size = Vector2(2.0, bar_h + 6.0)


## Ширина зоны доски ФИКСИРОВАНА (row.size.x — из сцены, под будущие ресайзы/экраны). Если
## рамки при полных отступах не влезают — сжимаем ДВУМЯ рычагами по очереди, а не даём картам
## уезжать за пределы зоны:
##   1) шаг тезисов ВНУТРИ рамки — они некликабельны, ложатся внахлёст (как стопка Разбора
##      в клинче), поэтому это основной и самый ёмкий рычаг;
##   2) отступ МЕЖДУ рамками — они кликабельны (цель атаки), сжимаем мягче и только если
##      одного первого рычага не хватило.
func _rebuild_frames(row: HBoxContainer, lines: Array, is_you: bool, default_sep: float) -> void:
	for c in row.get_children():
		c.queue_free()
	var n := lines.size()
	var natural_total := 0.0
	var total_gaps := 0  # суммарное число тезис-промежутков по всем рамкам ряда
	for line in lines:
		natural_total += _group_width(int(line.theses), CARD_G)
		total_gaps += mini(int(line.theses), 8)
	if n > 1:
		natural_total += default_sep * float(n - 1)

	# THESIS_PITCH_MIN — целевой ШАГ между позициями тезисов (как «k*9.0» у стопки Разбора).
	# У тезисов шаг = CARD_W + gap (не голый gap, как у Разбора) — поэтому порог для самого
	# gap ниже нуля: gap_floor = ШАГ - CARD_W = 9 - 42 = -33 (это и есть нахлёст в 33px).
	var gap_floor := THESIS_PITCH_MIN - CARD_W
	var gap_used := CARD_G
	var sep_used := default_sep
	var overflow := natural_total - row.size.x
	if overflow > 0.0:
		var thesis_budget := float(total_gaps) * (CARD_G - gap_floor)
		if total_gaps > 0 and overflow <= thesis_budget:
			# Хватает одного нахлёста тезисов — рамки друг друга не трогают.
			gap_used = CARD_G - overflow / float(total_gaps)
		else:
			gap_used = gap_floor
			var residual := overflow - maxf(0.0, thesis_budget)
			if n > 1 and residual > 0.0:
				var sep_room := default_sep * (1.0 - FRAME_SEP_MIN_FACTOR)
				var sep_reduction := clampf(residual / float(n - 1), 0.0, sep_room)
				sep_used = default_sep - sep_reduction
	row.add_theme_constant_override("separation", int(round(sep_used)))
	for i in n:
		row.add_child(_make_frame_group(lines[i], is_you, i, gap_used))


## Ширина группы «рамка + видимые тезисы» при заданном отступе gap между карточками.
func _group_width(theses: int, gap: float) -> float:
	var ncards := 1 + mini(theses, 8)
	return float(ncards) * CARD_W + float(ncards - 1) * gap


func _make_frame_group(line: Dictionary, is_you: bool, idx: int, gap: float) -> Control:
	var theses := int(line.theses)
	var stolen := int(line.get("stolen", 0))
	var closed: bool = line.closed
	# Контест и счётчик ударов — прямо из стейта клинча в ядре (model.clinch).
	var cl: Dictionary = model.clinch
	var contested := false
	var razbors := 0
	if not cl.is_empty():
		var my_side := ZalV3.SIDE_YOU if is_you else ZalV3.SIDE_OPP
		contested = (int(cl.idx) == idx) and (String(cl.defender) == my_side)
		razbors = int(cl.r_count)
	var targetable: bool = String(controller.input_mode()) == "target" and not is_you
	# «Шатается» = рамку прямо сейчас может забрать целиком Кража соперника её владельца:
	# тезисов не больше его порога захвата (базово 1; зал-гейт против фаворита поднимает до 2/3).
	var raider := ZalV3.SIDE_OPP if is_you else ZalV3.SIDE_YOU
	var shaky: bool = not contested and theses <= int(model.capture_threshold(raider))

	var shown := mini(theses, 8)
	var width := _group_width(theses, gap)
	var root := Control.new()
	root.custom_minimum_size = Vector2(maxf(width, CARD_W) + 16.0, CARD_H + 30.0)
	var y0 := 26.0
	if shaky:
		_start_wobble(root)

	# Карта-установка показывает claim (позицию-топик), если он назначен.
	var claim_txt: String = String(line.get("claim", line.name))
	var uc := _mkcard("РАМКА\n«%s»" % _short(claim_txt), COL_USTAN, closed, contested)
	uc.position = Vector2(0, y0)
	uc.tooltip_text = claim_txt
	if shaky:
		uc.tooltip_text += "\n⚠ ШАТАЕТСЯ: Кража соперника заберёт эту рамку целиком (трофеем)."
		var warn := Label.new()
		warn.text = "шатается"
		warn.position = Vector2(-2.0, y0 - 18.0)
		warn.add_theme_font_size_override("font_size", 10)
		warn.add_theme_color_override("font_color", Color.html("#" + COL_RAZBOR))
		warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(warn)
	if targetable:
		uc.disabled = false
		uc.pressed.connect(_on_target_pressed.bind(idx))
	root.add_child(uc)

	for j in shown:
		var is_st := j >= (theses - stolen)
		var tc := _mkcard("ПЕРЕ-\nХВАТ" if is_st else "тезис", (COL_GOLD if is_st else COL_TEZIS), closed, false)
		tc.position = Vector2(float(j + 1) * (CARD_W + gap), y0)
		root.add_child(tc)
	if theses > 8:
		var more := Label.new()
		more.text = "+%d" % (theses - 8)
		more.position = Vector2(width + 2.0, y0 + CARD_H / 2.0 - 8.0)
		more.add_theme_font_size_override("font_size", 11)
		more.add_theme_color_override("font_color", Color.html("#" + COL_TEZIS))
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(more)

	if contested and razbors > 0:
		for k in razbors:
			var rc := _mkcard("раз-\nбор", COL_RAZBOR, false, false)
			rc.position = Vector2(width - CARD_W + 10.0 + float(k) * 9.0, y0 - 20.0)
			root.add_child(rc)
	return root


## Качающийся твин «шаткой» рамки: группа покачивается на нижней кромке, как карта,
## которую вот-вот выдернут. Твин привязан к ноде — умирает вместе с ней при ребилде.
func _start_wobble(root: Control) -> void:
	root.pivot_offset = Vector2(root.custom_minimum_size.x / 2.0, root.custom_minimum_size.y)
	root.rotation_degrees = -1.8
	root.tree_entered.connect(func() -> void:
		var tw := root.create_tween().set_loops()
		tw.tween_property(root, "rotation_degrees", 1.8, 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(root, "rotation_degrees", -1.8, 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	, CONNECT_ONE_SHOT)


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
	var mode := String(controller.input_mode())
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
		match mode:
			"clinch_defend":
				enabled = card.type == ZalV3.TYPE_TEZIS
			"clinch_attack":
				enabled = card.type == ZalV3.TYPE_RAZBOR
			"move":
				enabled = true
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
	# Центрируем руку по X между иконками колод добора/сброса (в местных координатах HandArea).
	# Y НЕ трогаем — она держится тем, что задано в сцене (двигаешь всю зону HandArea в редакторе).
	var n := hand.size()
	var w := float(n) * HAND_W + maxf(0.0, float(n - 1)) * 12.0
	var area_w := (_hand_row.get_parent() as Control).size.x
	_hand_row.position.x = maxf(104.0, (area_w - w) / 2.0)


func _card_style(bg: Color, border: Color, w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(w)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	return sb


func _show_flash(txt: String, col: Color) -> void:
	_flash.text = txt
	_flash.add_theme_color_override("font_color", col)
	_flash.modulate.a = 1.0


# ------------------------------------------------------ меню паузы (оверлей, код)

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


func _menu_label(txt: String, x: float, y: float, fsize: int, colhex: String, w: float, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = txt
	l.position = Vector2(x, y)
	l.size = Vector2(w, 24)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", Color.html("#" + colhex))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_overlay.add_child(l)
	return l


func _open_menu() -> void:
	_menu_overlay.visible = true


func _close_menu() -> void:
	_menu_overlay.visible = false


func _menu_restart() -> void:
	_close_menu()
	controller.restart()


func _select_theme(i: int) -> void:
	controller.select_theme(i)
	for c in _menu_overlay.get_children():
		c.queue_free()
	_build_menu_contents()
	_close_menu()


## Содержимое оверлея (без самого Control) — для перестройки отметки активной колоды.
func _build_menu_contents() -> void:
	var themes: Array = controller.theme_list()
	# Панель растёт по высоте вместе со списком колод + блоком настроек снизу.
	var themes_bottom := 298.0 + float(themes.size()) * 38.0
	var settings_top := themes_bottom + 16.0
	var panel_h := settings_top + 96.0 - 130.0

	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.07, 0.09, 0.82)
	dim.size = Vector2(1152, 648)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_overlay.add_child(dim)
	var panel := ColorRect.new()
	panel.color = Color.html("#1b1f27")
	panel.position = Vector2(356, 130)
	panel.size = Vector2(440, panel_h)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_overlay.add_child(panel)
	_menu_label("ПАУЗА", 356, 146, 22, COL_GOLD, 440, HORIZONTAL_ALIGNMENT_CENTER)
	_menu_btn("Продолжить", 376, 188, 400, 32, _close_menu)
	_menu_btn("Новая партия (та же колода)", 376, 226, 400, 32, _menu_restart)
	_menu_label("Сменить колоду:", 376, 274, 13, COL_DIM, 400)
	var active := String(controller.active_theme_id())
	for i in themes.size():
		var td: Dictionary = themes[i]
		var mark := "● " if String(td.id) == active else "   "
		_menu_btn(mark + String(td.topic), 376, 298.0 + float(i) * 38.0, 400, 32, _select_theme.bind(i))

	# --- НАСТРОЙКИ ---
	_menu_label("НАСТРОЙКИ", 376, settings_top, 13, COL_DIM, 400)
	var speed_label := _menu_label(
		"Скорость печати текста: %d симв/с" % int(ReadingPace.CHARS_PER_SEC),
		376, settings_top + 22.0, 12, "e8e8e8", 400)
	var slider := HSlider.new()
	slider.min_value = ReadingPace.MIN_CHARS_PER_SEC
	slider.max_value = ReadingPace.MAX_CHARS_PER_SEC
	slider.step = 2.0
	slider.value = ReadingPace.CHARS_PER_SEC
	slider.position = Vector2(376, settings_top + 46.0)
	slider.size = Vector2(400, 20)
	slider.value_changed.connect(func(v: float) -> void:
		ReadingPace.CHARS_PER_SEC = v
		speed_label.text = "Скорость печати текста: %d симв/с" % int(v)
	)
	_menu_overlay.add_child(slider)
