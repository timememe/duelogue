extends Control

## DUELOGUE — ЭКРАН ДЕБАТОВ (чистый view). Каркас UI авторится НОДАМИ в debate_screen.tscn
## (двигается/настраивается в редакторе); скрипт лишь ссылается на них (%Name) и рендерит
## состояние из модели по сигналам EventBus, шлёт интенты контроллеру. Динамика (карты руки и
## рамки) пересобирается кодом в редактируемые контейнеры OppRow/YouRow/HandRow.
## Стенограмма — выезжающий справа ящик (кнопка-тумблер слева от меню). F6.

const ZalV3 := preload("res://duelogue/core/rules/rules_core.gd")  ## ядро правил — константы SIDE_*/TYPE_*/ZAL_MAX
const BattleController := preload("res://duelogue/app/battle_controller.gd")
const CardScene := preload("res://duelogue/ui/card/card.tscn")  ## шаблон карты руки (слои правятся в card.tscn)
const CardArt := preload("res://duelogue/core/cards/card_art.gd")
const CharacterCore := preload("res://duelogue/core/characters/character_core.gd")  ## ядро персонажей (актёры на сцену)
const ReadingPace := preload("res://duelogue/core/narrative/reading_pace.gd")  ## настройка скорости печати (меню)

const COL_TEZIS := "43c59e"
const COL_RAZBOR := "e45b5b"
const COL_USTAN := "57a3e3"
const COL_YOU := "43c59e"
const COL_OPP := "d98c4c"
const COL_DIM := "8a93a3"
const COL_GOLD := "e5b84b"

const CARD_W := 42.0
const CARD_H := 56.0
const CARD_G := 4.0
## Первый тезис не должен заезжать под золотую рамку. Сжимаются только интервалы МЕЖДУ
## зелёными тезисами; этот стык всегда остаётся обычным положительным отступом.
const FRAME_TO_THESIS_GAP := CARD_G
const HAND_CARD_PITCH := 84.0
const HAND_CARD_PITCH_MIN := 52.0
const HAND_SIDE_GUTTER := 108.0
const HAND_FAN_DEPTH := 15.0
const HAND_FAN_ANGLE := 7.0
const HAND_HOVER_LIFT := 26.0
const HAND_HOVER_SCALE := 1.1
## Служебный хвост группы справа: место под +N/лёгкое вращение рамки. Он является частью
## РЕАЛЬНОЙ ширины ряда и обязан участвовать в расчёте, иначе визуал шире математики.
const FRAME_GROUP_PAD := 16.0
## Тезисы внутри рамки НЕкликабельны (кликабельна только сама РАМКА) — им можно ложиться
## внахлёст плотно, как карты Разбора в стопке клинча. Тот же шаг (9px), тот же приём.
const THESIS_PITCH_MIN := 9.0
## Между рамками сначала используется separation из сцены. Если внутреннего нахлёста уже
## недостаточно, разрешаем аварийно сближать и сами группы, но не сильнее этого значения.
const FRAME_SEP_HARD_MIN := -40.0
const FRAME_SEP_DEFAULT := 12.0
const CLINCH_STACK_OFFSET := 10.0
const CLINCH_STACK_PITCH := 18.0
## Фактический правый край карт держим не у самой линии, а заранее начинаем сжатие в этой
## защитной зоне. Row уже имеет 8 px отступа от видимого контура Board.
const BOARD_EDGE_APPROACH := 12.0

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
var _bubble_owner: Control
var _cutscene_active := false

@onready var _stage: Control = $Stage
@onready var _score_label: Label = %ScoreLabel
@onready var _zal_label: Label = %ZalLabel
@onready var _hint_label: Label = %HintLabel
@onready var _marker: ColorRect = %BarMarker
@onready var _fill: ColorRect = %BarFill
@onready var _opp_row: Control = %OppRow
@onready var _you_row: Control = %YouRow
@onready var _hand_row: Control = %HandRow
@onready var _draw_count: Label = %DrawCount
@onready var _log_rt: RichTextLabel = %Log
@onready var _flash: Label = %Flash
@onready var _restart_btn: Button = %RestartBtn
@onready var _cancel_btn: Button = %CancelBtn
@onready var _clinch_btn: Button = %ClinchBtn
@onready var _drawer: Control = %TranscriptDrawer
@onready var _bar_bg: ColorRect = %BarBg  ## геометрия бара ЗАЛа читается отсюда, не дублируется числами
@onready var _reaction: Control = $ReactionScene  ## мини-сцена реакции (Ace Attorney-стиль)
@onready var _card_bubble: Panel = %CardInfoBubble
@onready var _card_bubble_title: Label = %CardInfoTitle
@onready var _card_bubble_body: Label = %CardInfoBody
@onready var _you_strain_bg: ColorRect = %YouStrainBg
@onready var _you_strain_fill: ColorRect = %YouStrainFill
@onready var _you_strain_label: Label = %YouStrainLabel
@onready var _opp_strain_bg: ColorRect = %OppStrainBg
@onready var _opp_strain_fill: ColorRect = %OppStrainFill
@onready var _opp_strain_label: Label = %OppStrainLabel


func _ready() -> void:
	controller = BattleController.new()
	add_child(controller)  # _ready контроллера создаёт model/nar/ai
	model = controller.model
	nar = controller.nar
	# Ядро персонажей кладёт актёров в слой сцены и режиссирует мини-сцену реакции.
	var chars := CharacterCore.new()
	chars.bind(_stage, _reaction)
	add_child(chars)
	# ReactionScene — модальный полноэкранный слой. Строковый connect сохраняет доступ к
	# кастомным сигналам сцены при статическом типе Control у onready-ссылки.
	_reaction.connect("scene_started", _on_cutscene_started)
	_reaction.connect("scene_finished", _on_cutscene_finished)
	_opp_sep0 = FRAME_SEP_DEFAULT
	_you_sep0 = FRAME_SEP_DEFAULT
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


func _on_opening_pressed(headline_id: String) -> void:
	controller.choose_opening(headline_id)


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
	var kind := String(meta.get("reaction_kind", ""))
	var role := String(meta.get("stance", ""))
	var bolt := ""
	match kind:
		"parry":
			role = "ПАРИРОВКА · %s" % String(meta.get("reaction_title", "холодный ответ"))
			bolt = "↩ "
		"counter_burst":
			role = "ОТВЕТНЫЙ СРЫВ · %s" % String(meta.get("reaction_title", "реакция"))
			bolt = "⚡↯ "
		"burst":
			role = "РЕАКЦИЯ · %s" % String(meta.get("reaction_title", "срыв"))
			bolt = "⚡ "
	_log("[color=#%s]— %s%s (%s):[/color] %s" % [col, bolt, who, role, text])
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
	_update_emotion_hud()
	var input_mode := String(controller.input_mode())
	_rebuild_frames(_opp_row, board_lines_for_mode(model.sides[ZalV3.SIDE_OPP].lines,
		input_mode), false, _opp_sep0)
	_rebuild_frames(_you_row, board_lines_for_mode(model.sides[ZalV3.SIDE_YOU].lines,
		input_mode), true, _you_sep0)
	_rebuild_hand()
	_draw_count.text = str(model.sides[ZalV3.SIDE_YOU].draw.size())
	_update_controls()


## Стартовые рамки уже существуют в rules state для симметричной Базы 1:1, но до выбора
## игроком это ещё не сыгранные карты. Скрываем только presentation; модель не мутируем.
static func board_lines_for_mode(lines: Array, input_mode: String) -> Array:
	return [] if input_mode == "opening" else lines


func _update_emotion_hud() -> void:
	_render_strain(controller.emotion_state(ZalV3.SIDE_YOU), _you_strain_bg,
		_you_strain_fill, _you_strain_label, "ВЫ")
	_render_strain(controller.emotion_state(ZalV3.SIDE_OPP), _opp_strain_bg,
		_opp_strain_fill, _opp_strain_label, "ОПП")


func _render_strain(state: Dictionary, bg: ColorRect, fill: ColorRect, label: Label,
	who: String) -> void:
	var maximum := maxi(1, int(state.get("max", 6)))
	var strain := clampi(int(state.get("strain", 0)), 0, maximum)
	var t := float(strain) / float(maximum)
	var height := bg.size.y * t
	fill.size = Vector2(bg.size.x, height)
	fill.position = Vector2(bg.position.x, bg.position.y + bg.size.y - height)
	fill.color = Color.html("#d8b04a").lerp(Color.html("#ef4b4b"), t)
	var status := "СРЫВ %d%%" % roundi(float(state.get("chance", 0.0)) * 100.0)
	if int(state.get("draw_left", 0)) <= 0:
		status = "ПУСТО"
	elif int(state.get("cooldown", 0)) > 0:
		status = "РАЗРЯДКА"
	label.text = "%s\n%d/%d\n%s" % [who, strain, maximum, status]


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


## Ширина зоны доски ФИКСИРОВАНА (row.size.x — внутренняя область видимой рамки Board). Если
## карты при полных отступах не влезают — fit_board_row сжимает их ДВУМЯ рычагами по очереди:
##   1) шаг тезисов ВНУТРИ рамки — они некликабельны, ложатся внахлёст (как стопка Разбора
##      в клинче), поэтому это основной и самый ёмкий рычаг;
##   2) отступ МЕЖДУ рамками — сжимаем только если первого рычага не хватило.
## Board.clip_contents дополнительно гарантирует, что ни один декоративный выброс не перекроет
## персонажей или соседние зоны даже при заведомо невозможной ширине.
func _rebuild_frames(row: Control, lines: Array, is_you: bool, default_sep: float) -> void:
	for c in row.get_children():
		c.queue_free()
	var n := lines.size()
	var thesis_counts: Array = []
	var trailing_pads: Array = []
	for i in n:
		thesis_counts.append(_display_thesis_count(lines[i], is_you, i))
		trailing_pads.append(_frame_trailing_pad(is_you, i))
	var fit := fit_board_row(thesis_counts, trailing_pads, row.size.x, default_sep)
	var gap_used := float(fit.gap)
	var sep_used := float(fit.separation)
	var reverse := not is_you
	row.set_meta("reverse_layout", reverse)
	var cursor_x := row.size.x if reverse else 0.0
	for i in n:
		var group := _make_frame_group(lines[i], is_you, i, gap_used,
			float(trailing_pads[i]), reverse)
		if reverse:
			cursor_x -= group.custom_minimum_size.x
			group.position.x = cursor_x
			cursor_x -= sep_used
		else:
			group.position.x = cursor_x
			cursor_x += group.custom_minimum_size.x + sep_used
		row.add_child(group)
	# Второй проход намеренно отложен: Control должен сначала применить реальные minimum size
	# текста/стилей. После этого измеряем уже не формулу, а фактические прямоугольники карт.
	var generation := int(row.get_meta("layout_generation", 0)) + 1
	row.set_meta("layout_generation", generation)
	call_deferred("_compress_row_from_actual_bounds", row, generation)


## Фактический проход от якорной рамки к внешнему краю линии. Для игрока ось идёт слева
## направо, для оппонента координаты зеркально считаются от правого края к левому. Если карты
## вошли в защитную зону BOARD_EDGE_APPROACH, равномерно уменьшаем реальные промежутки.
## Размеры карт не масштабируются. Стык рамка→первый тезис может дойти до касания, но никогда
## не становится отрицательным — тезис не прячется под свою золотую рамку.
func _compress_row_from_actual_bounds(row: Control, generation: int) -> void:
	if not is_instance_valid(row) or int(row.get_meta("layout_generation", -1)) != generation:
		return
	var entries: Array = []
	var reverse := bool(row.get_meta("reverse_layout", false))
	for group in row.get_children():
		if group.is_queued_for_deletion():
			continue
		for card in group.get_children():
			if not card is Control or not bool(card.get_meta("board_card", false)):
				continue
			var node := card as Control
			var absolute_x := float(group.position.x + node.position.x)
			var width := float(node.size.x)
			entries.append({
				"node": node,
				"group": group,
				"local_x": float(node.position.x),
				# axis_x всегда растёт ОТ якорной рамки к внешнему краю линии.
				"axis_x": row.size.x - (absolute_x + width) if reverse else absolute_x,
				"width": width,
				"role": String(node.get_meta("board_role", "thesis")),
			})
	if entries.size() < 2:
		return
	entries.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.axis_x) < float(b.axis_x))
	var first_x := float(entries[0].axis_x)
	var last_right := first_x
	for entry in entries:
		last_right = maxf(last_right, float(entry.axis_x) + float(entry.width))
	var target_right := row.size.x - BOARD_EDGE_APPROACH
	var required := last_right - target_right
	if required <= 0.0:
		return

	# Ёмкость каждого реального промежутка. Между рамкой и её первым тезисом минимум = ширина
	# рамки (касание); между тезисами разрешён карточный нахлёст до THESIS_PITCH_MIN.
	var capacities: Array = []
	var total_capacity := 0.0
	for i in range(1, entries.size()):
		var prev: Dictionary = entries[i - 1]
		var cur: Dictionary = entries[i]
		var delta := float(cur.axis_x) - float(prev.axis_x)
		var same_group: bool = cur.group == prev.group
		var frame_to_first: bool = same_group and String(prev.role) == "frame" and String(cur.role) == "thesis"
		var floor_pitch := float(prev.width) if frame_to_first else THESIS_PITCH_MIN
		# Новая рамка не должна залезать под последнюю карту предыдущей группы: до касания можно,
		# глубже — только жёсткий clip_contents как аварийная страховка невозможного состояния.
		if not same_group and String(cur.role) == "frame":
			floor_pitch = float(prev.width)
		var capacity := maxf(0.0, delta - floor_pitch)
		capacities.append(capacity)
		total_capacity += capacity
	if total_capacity <= 0.0:
		return
	var ratio := minf(1.0, required / total_capacity)
	var desired_x: Array = [first_x]
	for i in range(1, entries.size()):
		var delta := float(entries[i].axis_x) - float(entries[i - 1].axis_x)
		desired_x.append(float(desired_x[i - 1]) + delta - float(capacities[i - 1]) * ratio)

	# Сначала переносим корни групп по их золотой рамке, затем раскладываем дочерние карты
	# относительно нового корня. Row — обычный Control и не перезапишет эти координаты.
	var group_x := {}
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var desired_absolute := row.size.x - float(desired_x[i]) - float(entry.width) \
			if reverse else float(desired_x[i])
		entry["desired_absolute"] = desired_absolute
		if String(entry.role) == "frame":
			group_x[entry.group] = desired_absolute - float(entry.local_x)
	for group in group_x:
		(group as Control).position.x = float(group_x[group])
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var group := entry.group as Control
		var node := entry.node as Control
		node.position.x = float(entry.desired_absolute) - group.position.x


## Чистая функция горизонтальной укладки доски. Возвращает общий gap карт внутри рамок и
## separation между рамками. В расчёт входят не только лица карт, но и реальные хвосты групп.
static func fit_board_row(thesis_counts: Array, trailing_pads: Array,
	available_width: float, default_sep: float) -> Dictionary:
	var n := thesis_counts.size()
	if n == 0:
		return {"gap": CARD_G, "separation": default_sep, "width": 0.0}
	var natural_total := 0.0
	var total_gaps := 0
	for i in n:
		var theses := int(thesis_counts[i])
		natural_total += _group_width(theses, CARD_G) + float(trailing_pads[i])
		# Первый стык «рамка → тезис» защищён от нахлёста. Рычаг сжатия начинается
		# только со второго тезиса.
		total_gaps += maxi(0, mini(theses, 8) - 1)
	if n > 1:
		natural_total += default_sep * float(n - 1)

	# THESIS_PITCH_MIN — минимальный шаг позиций тезисов. Так как позиция считается как
	# CARD_W + gap, отрицательный gap означает контролируемый нахлёст, а не отрицательный шаг.
	var gap_floor := THESIS_PITCH_MIN - CARD_W
	var gap_used := CARD_G
	var sep_used := default_sep
	var overflow := maxf(0.0, natural_total - available_width)
	if overflow > 0.0 and total_gaps > 0:
		var thesis_budget := float(total_gaps) * (CARD_G - gap_floor)
		var thesis_reduction := minf(overflow, thesis_budget)
		gap_used -= thesis_reduction / float(total_gaps)
		overflow -= thesis_reduction
	if overflow > 0.0 and n > 1:
		var sep_room := (default_sep - FRAME_SEP_HARD_MIN) * float(n - 1)
		var sep_reduction := minf(overflow, sep_room)
		sep_used -= sep_reduction / float(n - 1)
		overflow -= sep_reduction
	var fitted_width := _board_row_width(thesis_counts, trailing_pads, gap_used, sep_used)
	return {"gap": gap_used, "separation": sep_used, "width": fitted_width,
		"clipped_overflow": overflow}


static func _board_row_width(thesis_counts: Array, trailing_pads: Array,
	gap: float, separation: float) -> float:
	var total := 0.0
	for i in thesis_counts.size():
		total += _group_width(int(thesis_counts[i]), gap) + float(trailing_pads[i])
	if thesis_counts.size() > 1:
		total += separation * float(thesis_counts.size() - 1)
	return total


## Хронологическая стопка клинча торчит правее обычного хвоста рамки; её ширина тоже
## участвует в раскладке, чтобы соседняя рамка не накрывала последовательность ходов.
func _frame_trailing_pad(is_you: bool, idx: int) -> float:
	var trailing := FRAME_GROUP_PAD
	var cl: Dictionary = model.clinch
	if cl.is_empty():
		return trailing
	var side := ZalV3.SIDE_YOU if is_you else ZalV3.SIDE_OPP
	if String(cl.get("defender", "")) != side or int(cl.get("idx", -1)) != idx:
		return trailing
	var sequence := _clinch_sequence(cl)
	if not sequence.is_empty():
		trailing = maxf(trailing, CLINCH_STACK_OFFSET +
			float(sequence.size() - 1) * CLINCH_STACK_PITCH)
	return trailing


func _display_thesis_count(line: Dictionary, is_you: bool, idx: int) -> int:
	var count := int(line.theses)
	var cl: Dictionary = model.clinch
	if cl.is_empty():
		return count
	var side := ZalV3.SIDE_YOU if is_you else ZalV3.SIDE_OPP
	if String(cl.get("defender", "")) == side and int(cl.get("idx", -1)) == idx:
		count -= int(cl.get("t_added", 0))
	return maxi(0, count)


## Новые партии получают точную sequence из rules_core. Реконструкция оставлена для старых
## сейвов/ручных тестов: автомат клинча всегда чередует Разбор → Тезис → Разбор.
func _clinch_sequence(cl: Dictionary) -> Array:
	var exact: Array = cl.get("sequence", [])
	if not exact.is_empty():
		return exact
	var fallback: Array = []
	var razbors := int(cl.get("r_count", 0))
	var theses := int(cl.get("t_added", 0))
	var steals_left := int(cl.get("atk_steals", 0))
	for i in razbors:
		var steals := bool(cl.get("init_steals", false)) if i == 0 else steals_left > 0
		fallback.append({"type": ZalV3.TYPE_RAZBOR, "steals": steals})
		if steals:
			steals_left = maxi(0, steals_left - 1)
		if i < theses:
			fallback.append({"type": ZalV3.TYPE_TEZIS, "stolen": false})
	return fallback


## Ширина группы «рамка + видимые тезисы» при заданном отступе gap между карточками.
static func _group_width(theses: int, gap: float) -> float:
	var shown := mini(theses, 8)
	if shown <= 0:
		return CARD_W
	return CARD_W + FRAME_TO_THESIS_GAP + CARD_W + \
		float(shown - 1) * (CARD_W + gap)


static func thesis_position_x(index: int, gap: float) -> float:
	return CARD_W + FRAME_TO_THESIS_GAP + float(index) * (CARD_W + gap)


## Зеркалим только ПОЗИЦИЮ карты внутри группы, но не scale/текст/саму ноду.
static func board_card_position_x(ltr_x: float, content_width: float,
	outer_pad: float, reverse: bool) -> float:
	return outer_pad + content_width - CARD_W - ltr_x if reverse else ltr_x


func _make_frame_group(line: Dictionary, is_you: bool, idx: int, gap: float,
	trailing_pad: float = FRAME_GROUP_PAD, reverse: bool = false) -> Control:
	var total_theses := int(line.theses)
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
	var theses := total_theses - (int(cl.get("t_added", 0)) if contested else 0)
	theses = maxi(0, theses)
	var targetable: bool = String(controller.input_mode()) == "target" and not is_you
	# «Шатается» = рамку прямо сейчас может забрать целиком Кража соперника её владельца:
	# тезисов не больше его порога захвата (базово 1; зал-гейт против фаворита поднимает до 2/3).
	var raider := ZalV3.SIDE_OPP if is_you else ZalV3.SIDE_YOU
	var shaky: bool = not contested and theses <= int(model.capture_threshold(raider))

	var shown := mini(theses, 8)
	var width := _group_width(theses, gap)
	var root := Control.new()
	root.custom_minimum_size = Vector2(maxf(width, CARD_W) + trailing_pad, CARD_H + 30.0)
	var y0 := 26.0
	if shaky:
		_start_wobble(root)

	# Карта-установка показывает claim (позицию-топик), если он назначен.
	var claim_txt: String = String(line.get("claim", line.name))
	var uc := _mkcard({"type": ZalV3.TYPE_USTANOVKA, "steals": false},
		COL_USTAN, closed, contested)
	uc.set_meta("board_card", true)
	uc.set_meta("board_role", "frame")
	uc.position = Vector2(board_card_position_x(0.0, width, trailing_pad, reverse), y0)
	var frame_info := claim_txt
	if shaky:
		frame_info += "\n\n⚠ ШАТАЕТСЯ: Кража соперника заберёт эту рамку целиком."
		var warn := Label.new()
		warn.text = "шатается"
		warn.position = Vector2(uc.position.x - 2.0, y0 - 18.0)
		warn.add_theme_font_size_override("font_size", 10)
		warn.add_theme_color_override("font_color", Color.html("#" + COL_RAZBOR))
		warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(warn)
	if targetable:
		uc.disabled = false
		uc.pressed.connect(_on_target_pressed.bind(idx))
		var spoken: String = controller.target_preview(idx)
		if spoken != "":
			frame_info += "\n\nСКАЖЕТЕ:\n%s" % spoken
	_attach_card_bubble(uc, "Рамка", frame_info,
		{"type": ZalV3.TYPE_USTANOVKA, "steals": false})
	root.add_child(uc)

	for j in shown:
		var is_st := j >= (theses - mini(stolen, theses))
		# Украденный тезис сохраняет тезисную пиктограмму; золото живёт только в окантовке.
		var tc := _mkcard({"type": ZalV3.TYPE_TEZIS, "steals": false},
			(COL_GOLD if is_st else COL_TEZIS), closed, false)
		tc.set_meta("board_stolen", is_st)
		tc.set_meta("board_card", true)
		tc.set_meta("board_role", "thesis")
		# Первый тезис стоит ПОСЛЕ рамки; отрицательный gap уплотняет только следующие
		# тезисы относительно друг друга и больше не прячет их под золотую карту.
		tc.position = Vector2(board_card_position_x(thesis_position_x(j, gap),
			width, trailing_pad, reverse), y0)
		root.add_child(tc)
	if theses > 8:
		var more := Label.new()
		more.text = "+%d" % (theses - 8)
		more.position = Vector2(maxf(0.0, trailing_pad - 24.0) if reverse else width + 2.0,
			y0 + CARD_H / 2.0 - 8.0)
		more.add_theme_font_size_override("font_size", 11)
		more.add_theme_color_override("font_color", Color.html("#" + COL_TEZIS))
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(more)

	if contested and razbors > 0:
		var sequence := _clinch_sequence(cl)
		for k in sequence.size():
			var played: Dictionary = sequence[k]
			var played_type := String(played.get("type", ZalV3.TYPE_RAZBOR))
			var is_theft := played_type == ZalV3.TYPE_RAZBOR and bool(played.get("steals", false))
			var is_stolen_thesis := played_type == ZalV3.TYPE_TEZIS and bool(played.get("stolen", false))
			var border_col := COL_TEZIS if played_type == ZalV3.TYPE_TEZIS else COL_RAZBOR
			if is_theft or is_stolen_thesis:
				border_col = COL_GOLD
			var rc := _mkcard({"type": played_type, "steals": is_theft}, border_col, false, false)
			rc.set_meta("board_card", true)
			rc.set_meta("board_role", "overlay")
			rc.set_meta("clinch_order", k)
			var overlay_ltr_x := width - CARD_W + CLINCH_STACK_OFFSET + \
				float(k) * CLINCH_STACK_PITCH
			rc.position = Vector2(board_card_position_x(overlay_ltr_x,
				width, trailing_pad, reverse), y0 - 18.0 - float(k) * 1.5)
			rc.z_index = 20 + k
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


func _mkcard(visual: Dictionary, colhex: String, dim: bool, contested: bool) -> Button:
	var b := Button.new()
	b.size = Vector2(CARD_W, CARD_H)
	b.custom_minimum_size = Vector2(CARD_W, CARD_H)
	# Критично для геометрии Board: при clip_text=false Button включает ширину всей строки
	# в свой внутренний minimum size и молча становится шире CARD_W. Тогда fit_board_row считает
	# 42 px, а реальная «РАМКА «длинный claim»» занимает 80–100 px и тезисы уезжают под неё.
	b.clip_text = true
	b.clip_contents = true
	b.text = ""
	var base := Color.html("#" + colhex)
	var border := base.lightened(0.18)
	var bg := Color.html("#05080c")
	if dim:
		border = border.darkened(0.35)
		bg = bg.darkened(0.22)
	if contested:
		bg = bg.lerp(Color.html("#" + COL_RAZBOR), 0.2)
	b.add_theme_stylebox_override("normal", _card_style(bg, border, 3))
	b.add_theme_stylebox_override("hover", _card_style(bg.lightened(0.08), border.lightened(0.1), 3))
	b.add_theme_stylebox_override("pressed", _card_style(bg.darkened(0.12), border, 3))
	b.add_theme_stylebox_override("disabled", _card_style(bg, border, 3))
	b.icon = CardArt.type_icon_for(visual, true)
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", 32)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var icon_color := Color(1.0, 1.0, 1.0, 0.5 if dim else 1.0)
	b.add_theme_color_override("icon_normal_color", icon_color)
	b.add_theme_color_override("icon_hover_color", icon_color)
	b.add_theme_color_override("icon_pressed_color", icon_color)
	b.add_theme_color_override("icon_disabled_color", icon_color)
	b.set_meta("board_visual_type", String(visual.get("type", "")))
	b.set_meta("board_visual_steals", bool(visual.get("steals", false)))
	b.set_meta("board_border_color", colhex)
	b.disabled = true
	return b


func _short(s: String) -> String:
	return s if s.length() <= 9 else s.substr(0, 8) + "…"


func _rebuild_hand() -> void:
	_clear_card_bubble()
	for c in _hand_row.get_children():
		c.queue_free()
	var mode := String(controller.input_mode())
	if mode == "opening":
		_rebuild_opening_hand()
		_layout_hand()
		return
	var hand: Array = model.sides[ZalV3.SIDE_YOU].hand
	for i in hand.size():
		var card: Dictionary = hand[i]
		var enabled := false
		match mode:
			"clinch_defend":
				enabled = card.type == ZalV3.TYPE_TEZIS
			"clinch_attack":
				enabled = card.type == ZalV3.TYPE_RAZBOR
			"move":
				enabled = true
		# Лицо карты: у ванильной — точная контекстная реплика; у ИМЕННОЙ (zal_run §2) —
		# имя и правило-твист. Для Разбора точная строка появляется на рамке после выбора карты,
		# потому что содержание зависит от цели.
		# Сам дизайн карты (слои/шрифты/размер) — шаблон ui/card/card.tscn, правится в редакторе.
		var is_named: bool = card.has("named")
		# Установки имеют собственные названия (Рамка / Тезис дня / Позиция), поэтому не
		# схлопываем их все в одинаковый заголовок «Установка».
		var title: String = String(card.get("name", "")) if is_named or \
			card.type == ZalV3.TYPE_USTANOVKA else nar.device_label(card)
		var body: String = String(card.get("text", "")) if is_named else controller.hand_preview(i)
		var btn: Button = CardScene.instantiate()
		_hand_row.add_child(btn)  # в дерево ДО setup: слои шаблона резолвятся в _ready
		btn.setup(card, title, body, enabled)
		var bubble_title := title if is_named else "%s · %s" % [title, String(card.get("name", ""))]
		var bubble_body := String(card.get("text", "")) if is_named else "СКАЖЕТЕ:\n%s" % body
		if is_named:
			bubble_body = "Именной приём\n\n" + bubble_body
		_attach_card_bubble(btn, bubble_title, bubble_body, card)
		_attach_hand_motion(btn)
		btn.pressed.connect(_on_hand_pressed.bind(i))
	_layout_hand()


## На нулевом ходе смысловые варианты выглядят как обычные карты-Установки в руке.
## Это presentation-only: контроллер по-прежнему не списывает U-карту и не двигает ход.
func _rebuild_opening_hand() -> void:
	for option in controller.opening_options():
		var axes: Array = nar.axis_tags(option.get("preferred_axes", []))
		var focus := "" if axes.is_empty() else "Фокус: %s" % " · ".join(axes)
		var card := {"type": ZalV3.TYPE_USTANOVKA, "name": "Стартовая рамка", "steals": false}
		var body := "«%s»" % String(option.get("text", ""))
		if focus != "":
			body += "\n\n" + focus
		var btn: Button = CardScene.instantiate()
		_hand_row.add_child(btn)
		btn.setup(card, "Установка", body, true)
		var bubble_body := "%s\n\n%s\n\nНе расходует карту или ход. Сила Базы остаётся 1." % [
			"«%s»" % String(option.get("text", "")), focus]
		_attach_card_bubble(btn, "Стартовая Установка", bubble_body, card)
		_attach_hand_motion(btn)
		btn.pressed.connect(_on_opening_pressed.bind(String(option.get("id", ""))))


## Карты лежат веером с нахлёстом, как физическая рука: центр выше, края ниже и повёрнуты.
## Раскладка ручная, потому что Container не позволяет соседям перекрываться и вращаться.
func _layout_hand() -> void:
	var live: Array = _hand_row.get_children().filter(func(c): return not c.is_queued_for_deletion())
	var n := live.size()
	if n == 0:
		return
	var sample := live[0] as Control
	var card_size := sample.custom_minimum_size
	var area_w := (_hand_row.get_parent() as Control).size.x
	var available_pitch := (area_w - HAND_SIDE_GUTTER * 2.0 - card_size.x) / maxf(1.0, float(n - 1))
	var pitch := HAND_CARD_PITCH if n == 1 else clampf(available_pitch,
		HAND_CARD_PITCH_MIN, HAND_CARD_PITCH)
	var total_w := card_size.x + pitch * float(n - 1)
	var left := maxf(HAND_SIDE_GUTTER, (area_w - total_w) * 0.5)
	var center := float(n - 1) * 0.5
	var radius := maxf(1.0, center)
	for i in n:
		var card := live[i] as Control
		var fan := (float(i) - center) / radius
		var y := pow(absf(fan), 1.55) * HAND_FAN_DEPTH
		var base_position := Vector2(left + float(i) * pitch, y)
		var base_rotation := fan * HAND_FAN_ANGLE
		card.position = base_position
		card.rotation_degrees = base_rotation
		card.scale = Vector2.ONE
		card.pivot_offset = Vector2(card_size.x * 0.5, card_size.y)
		card.z_index = i
		card.set_meta("hand_base_position", base_position)
		card.set_meta("hand_base_rotation", base_rotation)
		card.set_meta("hand_base_z", i)
		card.set_meta("hand_hovered", false)


func _attach_hand_motion(card: Control) -> void:
	card.mouse_entered.connect(_set_hand_hover.bind(card, true))
	card.mouse_exited.connect(_set_hand_hover.bind(card, false))


func _set_hand_hover(card: Control, hovered: bool) -> void:
	if not is_instance_valid(card) or not card.has_meta("hand_base_position"):
		return
	card.set_meta("hand_hovered", hovered)
	var previous: Variant = card.get_meta("hand_tween", null)
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()
	var base_position: Vector2 = card.get_meta("hand_base_position")
	var base_rotation := float(card.get_meta("hand_base_rotation"))
	var base_z := int(card.get_meta("hand_base_z"))
	var target_position := base_position + Vector2(0.0, -HAND_HOVER_LIFT) if hovered else base_position
	var target_rotation := 0.0 if hovered else base_rotation
	var target_scale := Vector2.ONE * HAND_HOVER_SCALE if hovered else Vector2.ONE
	# При уходе сразу возвращаем базовый z: выходящая левая карта больше не перехватывает
	# мышь у соседки во время обратного tween и не вызывает дрожание слоёв.
	card.z_index = 1000 + base_z if hovered else base_z
	var tween := card.create_tween()
	tween.set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position", target_position, 0.15)
	tween.tween_property(card, "rotation_degrees", target_rotation, 0.15)
	tween.tween_property(card, "scale", target_scale, 0.15)
	card.set_meta("hand_tween", tween)


## Нативный tooltip заменён фиксированным непрозрачным баблом: он не прыгает за мышью,
## имеет стабильную ширину и переносит текст по словам.
func _attach_card_bubble(owner: Control, title: String, body: String, card: Dictionary) -> void:
	owner.tooltip_text = ""
	owner.mouse_entered.connect(_show_card_bubble.bind(owner, title, body, card))
	owner.mouse_exited.connect(_hide_card_bubble.bind(owner))


func _show_card_bubble(owner: Control, title: String, body: String, card: Dictionary) -> void:
	if _cutscene_active or _reaction.visible:
		return
	_bubble_owner = owner
	_card_bubble_title.text = title
	_card_bubble_body.text = body
	var border := Color.html("#" + COL_TEZIS)
	match String(card.get("type", "")):
		ZalV3.TYPE_RAZBOR:
			border = Color.html("#" + (COL_GOLD if bool(card.get("steals", false)) else COL_RAZBOR))
		ZalV3.TYPE_USTANOVKA:
			border = Color.html("#" + COL_USTAN)
	_card_bubble.add_theme_stylebox_override("panel",
		_card_style(Color.html("#111722"), border, 2))
	_card_bubble.visible = true


func _hide_card_bubble(owner: Control) -> void:
	if _bubble_owner == owner:
		_clear_card_bubble()


func _clear_card_bubble() -> void:
	_bubble_owner = null
	_card_bubble.visible = false


func _on_cutscene_started() -> void:
	_cutscene_active = true
	# Hover мог открыться кадром раньше микросцены — убираем его синхронно со стартом,
	# чтобы ни рамка, ни текст карточки не проступали поверх крупного плана.
	_clear_card_bubble()


func _on_cutscene_finished() -> void:
	_cutscene_active = false


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
	_menu_overlay.z_index = 200
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
	var panel_h := settings_top + 170.0 - 130.0

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
		var prof := get_node_or_null("/root/Profile")
		if prof != null:
			prof.set_setting("chars_per_sec", v)
	)
	_menu_overlay.add_child(slider)
	# Тумблер катсцен-реплик (ReadingPace.CUTSCENES — единые часы: выключил — сцены не
	# играются, реплики остаются в логе/стенограмме, темп партии сжимается до OFF_BEAT).
	var cuts := CheckButton.new()
	cuts.text = "Катсцены реплик (крупный план)"
	cuts.button_pressed = ReadingPace.CUTSCENES
	cuts.position = Vector2(376, settings_top + 74.0)
	cuts.size = Vector2(400, 28)
	cuts.add_theme_font_size_override("font_size", 12)
	cuts.toggled.connect(func(v: bool) -> void:
		ReadingPace.CUTSCENES = v
		var prof := get_node_or_null("/root/Profile")
		if prof != null:
			prof.set_setting("cutscenes", v)
	)
	_menu_overlay.add_child(cuts)
	_menu_btn("В главное меню", 376, settings_top + 108.0, 400, 32, func() -> void:
		get_tree().change_scene_to_file("res://duelogue/ui/main_menu.tscn"))
