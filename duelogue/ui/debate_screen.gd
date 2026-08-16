extends Control

## DUELOGUE — ЭКРАН ДЕБАТОВ (чистый view). Каркас UI авторится НОДАМИ в debate_screen.tscn
## (двигается/настраивается в редакторе); скрипт лишь ссылается на них (%Name) и рендерит
## состояние из модели по сигналам EventBus, шлёт интенты контроллеру. Динамика (карты руки и
## рамки) пересобирается кодом в редактируемые контейнеры OppRow/YouRow/HandRow.
## Стенограмма — выезжающий справа ящик (кнопка-тумблер слева от меню). F6.

const C := preload("res://duelogue/core/cards/card_types.gd")  ## общий контракт — константы SIDE_*/TYPE_*/ZAL_MAX
const BattleController := preload("res://duelogue/app/battle_controller.gd")
const CardScene := preload("res://duelogue/ui/card/card.tscn")  ## шаблон карты руки (слои правятся в card.tscn)
const CardArt := preload("res://duelogue/core/cards/card_art.gd")
const CharacterCore := preload("res://duelogue/core/characters/character_core.gd")  ## ядро персонажей (актёры на сцену)
const ReadingPace := preload("res://duelogue/core/narrative/reading_pace.gd")  ## настройка скорости печати (меню)
const StatusIcon := preload("res://duelogue/ui/status_icon.gd")  ## перк-иконка с кастомным тултипом-у-курсора
## Тот же Sofia Sans Condensed Black wght=900, что у имени приёма в реакции (reaction_scene)
## и в баннере комбо (combo_name_banner.gd) — держим тот же вес и для тег-лейблов рамки.
const TAG_FONT := preload("res://duelogue/assets/fonts/SofiaSansCondensed-Black.tres")

const COL_TEZIS := "43c59e"
const COL_RAZBOR := "e45b5b"
const COL_USTAN := "57a3e3"
const COL_YOU := "43c59e"
const COL_OPP := "d98c4c"
const COL_DIM := "8a93a3"
const COL_GOLD := "e5b84b"

const AUDIENCE_LOG_SLIDE := 14.0
const AUDIENCE_LOG_TWEEN_TIME := 0.18
const OPP_EMOTION_LOG_GAP := 10.0
const OPP_EMOTION_LOG_CLOSED_REVEAL := 18.0

## Перк-иконки поверх кафедры (core/status/): круглая заглушка без арт-ассетов — первая
## буква label на цветном кружке (зелёный=perk, красный=debuff), полное имя+durability/source
## в tooltip. Своя мини-функция, не _card_style() — тот заточен под карты с полями/рамкой.
const STATUS_ICON_SIZE := 22.0
const STATUS_ICON_GAP := 5.0

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

## Второй способ разыгрывать карту руки — драг-дроп (первый — клик-клик, _on_hand_pressed/
## _on_target_pressed, НЕ трогаем). Порог в пикселях отличает клик от начала протяжки.
const DRAG_THRESHOLD := 6.0
const DRAG_GHOST_LAND_TIME := 0.28
const DRAG_GHOST_CANCEL_TIME := 0.2
## Автонаведение: рамка-цель во время targeted-драга маркируется по БЛИЖАЙШЕЙ (не по точному
## наведению) — форгивинг-подбор на маленькой (42×56) кнопке.
const DRAG_TARGET_MARK_SCALE := 1.18
const DRAG_TARGET_MARK_COLOR := Color(1.45, 1.3, 0.85)

@export var playtest_logging_enabled := true
## Драйв-полигон комбо (цифровая «бумага A0», §9): обе обоймы заряжаются маршрутом №1.
## Включается сценой tools/combo_drill.tscn, обычная катка не трогается.
@export var combo_drill := false

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
var _bubble_owner: Control
var _cutscene_active := false
var _audience_history: Array[String] = []
var _audience_last_state := {}
var _audience_event_index := -1
var _audience_log_open := false
var _audience_log_open_y := 0.0
var _audience_log_closed_y := 0.0
var _audience_log_tween: Tween
var _emotion_histories := {C.SIDE_YOU: [], C.SIDE_OPP: []}
var _emotion_event_indices := {C.SIDE_YOU: -1, C.SIDE_OPP: -1}
var _emotion_log_side := ""
var _emotion_log_open := false
var _emotion_log_open_x := 0.0
var _emotion_log_closed_x := 0.0
var _emotion_log_tween: Tween

## Драг-дроп руки (второй способ разыгрывать карту, поверх клик-клика — см. константы выше).
var _drag_pending := {}   ## {"card": Control, "index": int} — мышь зажата, порог ещё не пройден
var _drag_active := false
var _drag_kind := ""      ## "targeted" (Разбор/именная с целью — рамка оппонента) | "immediate"
var _drag_index := -1
var _drag_start_global := Vector2.ZERO
var _drag_hand_size := Vector2.ZERO
var _drag_ghost: Control
var _drag_marked_frame: Button   ## текущая рамка-цель под автонаведением (targeted-драг)
## После отпускания targeted-карты коротко блокируем второй выбор цели: сначала призрак
## физически садится на выбранную рамку, и только затем контроллер открывает клинч.
var _target_land_pending := false

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
@onready var _restart_btn: Button = %RestartBtn
@onready var _cancel_btn: Button = %CancelBtn
@onready var _clinch_btn: Button = %ClinchBtn
@onready var _drawer: Control = %TranscriptDrawer
@onready var _zal_bar: Control = $ZalBar
@onready var _bar_bg: ColorRect = %BarBg  ## геометрия бара ЗАЛа читается отсюда, не дублируется числами
@onready var _audience_log_panel: PanelContainer = %AudienceLogPanel
@onready var _audience_log_rt: RichTextLabel = %AudienceReactionLog
@onready var _reaction: Control = $ReactionScene  ## мини-сцена реакции (Ace Attorney-стиль)
@onready var _combo_banner: Control = $ComboNameBanner  ## баннер названия комбо, НЕ часть reaction_scene
@onready var _card_bubble: Panel = %CardInfoBubble
@onready var _card_bubble_title: Label = %CardInfoTitle
@onready var _card_bubble_body: Label = %CardInfoBody
@onready var _you_strain_bg: ColorRect = %YouStrainBg
@onready var _you_strain_fill: ColorRect = %YouStrainFill
@onready var _you_strain_label: Label = %YouStrainLabel
@onready var _you_strain: Control = $EmotionHud/YouStrain
@onready var _opp_strain_bg: ColorRect = %OppStrainBg
@onready var _opp_strain_fill: ColorRect = %OppStrainFill
@onready var _opp_strain_label: Label = %OppStrainLabel
@onready var _opp_strain: Control = $EmotionHud/OppStrain
@onready var _emotion_log_panel: PanelContainer = %OpponentEmotionLogPanel
@onready var _emotion_log_rt: RichTextLabel = %OpponentEmotionLog
@onready var _emotion_summary: Label = %OpponentEmotionSummary
@onready var _emotion_log_close: Button = %OpponentEmotionLogClose
@onready var _emotion_log_title: Label = $EmotionHud/OpponentEmotionLogPanel/Margin/Layout/Header/Title
@onready var _you_status_row: Control = %YouStatusRow  ## перк-иконки поверх кафедры (core/status/)
@onready var _opp_status_row: Control = %OppStatusRow
@onready var _final_overlay: Control = %FinalOverlay
@onready var _final_profile: Label = %FinalProfile
@onready var _final_winner: Label = %FinalWinner
@onready var _final_rule: Label = %FinalRule
@onready var _final_board_score: Label = %FinalBoardScore
@onready var _final_board_detail: Label = %FinalBoardDetail
@onready var _final_audience_score: Label = %FinalAudienceScore
@onready var _final_audience_detail: Label = %FinalAudienceDetail
@onready var _final_emotion_score: Label = %FinalEmotionScore
@onready var _final_emotion_detail: Label = %FinalEmotionDetail
@onready var _final_split: Label = %FinalSplit
@onready var _final_verdict: Label = %FinalVerdict
@onready var _final_description: Label = %FinalDescription


func _ready() -> void:
	controller = BattleController.new()
	add_child(controller)  # _ready контроллера создаёт model/nar/ai
	controller.logging_enabled = playtest_logging_enabled
	controller.combo_drill = combo_drill
	model = controller.model
	nar = controller.nar
	# Ядро персонажей кладёт актёров в слой сцены и режиссирует мини-сцену реакции.
	var chars := CharacterCore.new()
	chars.bind(_stage, _reaction, _combo_banner)
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
	_audience_log_open_y = _zal_bar.size.y + 3.0
	_audience_log_closed_y = _audience_log_open_y - AUDIENCE_LOG_SLIDE
	_audience_log_panel.position.y = _audience_log_closed_y
	_audience_log_panel.modulate.a = 0.0
	_audience_log_panel.visible = false
	_zal_bar.mouse_entered.connect(_open_audience_log)
	_zal_bar.mouse_exited.connect(_queue_audience_log_close)
	_audience_log_panel.mouse_entered.connect(_open_audience_log)
	_audience_log_panel.mouse_exited.connect(_queue_audience_log_close)
	_set_emotion_log_positions(C.SIDE_OPP)
	_emotion_log_panel.position = Vector2(_emotion_log_closed_x, _opp_strain.position.y)
	_emotion_log_panel.modulate.a = 0.0
	_emotion_log_panel.visible = false
	_you_strain.gui_input.connect(_on_strain_gui_input.bind(C.SIDE_YOU))
	_opp_strain.gui_input.connect(_on_strain_gui_input.bind(C.SIDE_OPP))
	_emotion_log_close.pressed.connect(_close_emotion_log)
	# Подписка на шину партии.
	EventBus.match_started.connect(_on_match_started)
	EventBus.utterance.connect(_on_utterance)
	EventBus.narration.connect(_on_narration)
	EventBus.audience_changed.connect(_on_audience_changed)
	EventBus.emotion_observed.connect(_on_emotion_observed)
	EventBus.emotion_linked.connect(_on_emotion_linked)
	EventBus.board_changed.connect(_on_board_changed)
	EventBus.match_reported.connect(_on_match_reported)
	controller.start_match()


# --------------------------------------------------- интенты игрока → контроллер

func _on_hand_pressed(index: int) -> void:
	controller.play_hand(index)


func _on_target_pressed(index: int) -> void:
	if _target_land_pending:
		return
	controller.choose_target(index)


func _cancel_targeting() -> void:
	if _target_land_pending:
		return
	controller.cancel_targeting()


func _on_clinch_pass() -> void:
	controller.clinch_pass()


func _on_opening_pressed(headline_id: String) -> void:
	controller.choose_opening(headline_id)


func _new_match() -> void:
	_final_overlay.visible = false
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
	_audience_history = []
	_audience_last_state = {}
	_audience_event_index = -1
	_audience_log_rt.text = ""
	_emotion_histories = {C.SIDE_YOU: [], C.SIDE_OPP: []}
	_emotion_event_indices = {C.SIDE_YOU: -1, C.SIDE_OPP: -1}
	_emotion_log_rt.text = ""
	for side in [C.SIDE_YOU, C.SIDE_OPP]:
		var emotion_state: Dictionary = controller.emotion_state(side)
		_append_emotion_history(side, _format_emotion_start(side, emotion_state))
	if _emotion_log_side != "":
		_render_emotion_history(_emotion_log_side)
	_restart_btn.visible = false
	_final_overlay.visible = false
	_log_rt.text = ""
	_refresh()


func _on_utterance(side: String, text: String, meta: Dictionary) -> void:
	var col := COL_YOU if side == C.SIDE_YOU else COL_OPP
	var who := "Вы" if side == C.SIDE_YOU else "Оппонент"
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
	if meta.has("conduct_effect"):
		role += " · ВПЕЧАТЛЕНИЕ %+d" % int(meta.conduct_effect)
	# Тип карты/приём (2026-07-22): схема тезиса или device разбора — та же строка, что игрок
	# уже видит в файловой стенограмме, теперь и в живом логе экрана боя.
	var device := String(meta.get("device", ""))
	if device != "" and kind == "":
		role += " · %s" % device
	_log("[color=#%s]— %s%s (%s):[/color] %s" % [col, bolt, who, role, text])
	_log_rt.text = "\n".join(log_lines)


func _on_narration(text: String, _meta: Dictionary) -> void:
	_log("[color=#%s][i]%s[/i][/color]" % [COL_DIM, text])
	_log_rt.text = "\n".join(log_lines)


func _on_board_changed() -> void:
	_refresh()


## Единственная публичная история зала строится по тем же атомарным снимкам, которые двигают
## шкалу. Поэтому лог не пытается угадать эффект по репликам и всегда совпадает с механикой.
func _on_audience_changed(state: Dictionary) -> void:
	var snapshot := state.duplicate(true)
	if _audience_last_state.is_empty():
		_append_audience_history(_format_audience_start(snapshot))
		_audience_last_state = snapshot
		return
	var previous: Dictionary = _audience_last_state
	var scene: Dictionary = snapshot.get("last_scene", {})
	var scene_committed := not scene.is_empty() \
		and int(snapshot.get("scenes", 0)) > int(previous.get("scenes", 0))
	var public_state_changed := int(snapshot.get("lean", 0)) != int(previous.get("lean", 0)) \
		or int(snapshot.get("heat", 0)) != int(previous.get("heat", 0)) \
		or int(snapshot.get("moves", 0)) != int(previous.get("moves", 0)) \
		or int(snapshot.get("reversals", 0)) != int(previous.get("reversals", 0))
	if scene_committed:
		_append_audience_history(_format_audience_scene(previous, snapshot))
	elif public_state_changed:
		_append_audience_history(_format_audience_cooldown(previous, snapshot))
	_audience_last_state = snapshot


func _append_audience_history(body: String) -> void:
	_audience_event_index += 1
	_audience_history.append("[color=#%s]%02d[/color]  %s" % [COL_DIM,
		_audience_event_index, body])
	_audience_log_rt.text = "\n\n".join(_audience_history)
	_audience_log_rt.call_deferred("scroll_to_line", maxi(0, _audience_log_rt.get_line_count() - 1))


func _format_audience_start(state: Dictionary) -> String:
	var lean := int(state.get("lean", 0))
	var heat := int(state.get("heat", 0))
	return "[color=#%s]● СТАРТ[/color]  крен %s · азарт %d/%d\n[color=#%s]Зал слушает обе стороны.[/color]" % [
		COL_GOLD, _signed(lean), heat, int(state.get("heat_max", 0)), COL_DIM]


func _format_audience_scene(previous: Dictionary, state: Dictionary) -> String:
	var scene: Dictionary = state.get("last_scene", {})
	var before_lean := int(previous.get("lean", 0))
	var after_lean := int(state.get("lean", 0))
	var content := int(scene.get("content_delta", 0))
	var conduct := int(scene.get("conduct_applied", 0))
	var reaction_seen := bool(scene.get("reaction_seen", false))
	var surged := bool(scene.get("surged", false))
	var direction := int(scene.get("direction", 0))
	var heading := "ЗАЛ РАЗДЕЛИЛСЯ"
	if surged:
		heading = "ВСПЛЕСК ЗАЛА"
	elif direction > 0:
		heading = "ЗАЛ КАЧНУЛСЯ К ВАМ"
	elif direction < 0:
		heading = "ЗАЛ КАЧНУЛСЯ К ОППОНЕНТУ"
	elif before_lean == after_lean:
		heading = "ЗАЛ УДЕРЖАЛ ПОЗИЦИЮ"
	var accent := COL_GOLD if surged or direction == 0 else (COL_YOU if direction > 0 else COL_OPP)
	var cause: Dictionary = state.get("cause", {})
	var story := _audience_cause_sentence(cause)
	var reactions: Array = cause.get("reactions", [])
	for raw_reaction in reactions:
		var reaction_note: Dictionary = raw_reaction
		var who := "Вы вскипели" if String(reaction_note.get("side", "")) == C.SIDE_YOU \
			else "Оппонент вскипел"
		story += " %s: «%s»." % [who, String(reaction_note.get("title", "реакция"))]
	if story == "":
		story = "Довод и впечатление погасили друг друга." if direction == 0 else \
			("Публика купилась на ваш момент." if direction > 0 else \
			"Публика купилась на момент оппонента.")
	var votes: Array[String] = []
	if content != 0:
		votes.append("довод %s" % _signed(content))
	if conduct != 0:
		votes.append("впечатление %s" % _signed(conduct))
	elif reaction_seen:
		votes.append("реакция без голоса")
	var vote_note := "" if votes.is_empty() else " Голоса: %s." % " · ".join(votes)
	var surge_note := " · АЗАРТ ПРОРВАЛСЯ" if surged else ""
	return "[color=#%s]◆ %s[/color]  крен %s → %s%s\n[color=#%s]%s%s Азарт %d → %d.[/color]" % [
		accent, heading, _signed(before_lean), _signed(after_lean), surge_note, COL_DIM,
		story, vote_note, int(scene.get("heat_before", previous.get("heat", 0))),
		int(state.get("heat", 0))]


static func _audience_cause_sentence(cause: Dictionary) -> String:
	var action := String(cause.get("action", "")).strip_edges()
	if action == "":
		return ""
	var actor := String(cause.get("actor", ""))
	var owner := "Ваш «%s»" % action if actor == C.SIDE_YOU else "«%s» оппонента" % action
	var target := String(cause.get("target", "")).strip_edges()
	var quoted := "«%s»" % target if target != "" else "позицию"
	match String(cause.get("outcome", "")):
		"captured": return "%s увёл рамку %s целиком." % [owner, quoted]
		"frame_lost": return "%s развалил рамку %s." % [owner, quoted]
		"argument_lost": return "%s продавил аргумент вокруг %s." % [owner, quoted]
		"attack_stalled": return "%s упёрся в %s и захлебнулся." % [owner, quoted]
		"dirty_hit": return "%s ударил ниже пояса." % owner
		_: return "%s изменил настроение сцены вокруг %s." % [owner, quoted]


func _format_audience_cooldown(previous: Dictionary, state: Dictionary) -> String:
	return "[color=#%s]◇ ЗАЛ ВЫДЫХАЕТ[/color]  крен %s → %s\n[color=#%s]спокойная пауза · азарт %d → %d[/color]" % [
		COL_DIM, _signed(int(previous.get("lean", 0))), _signed(int(state.get("lean", 0))),
		COL_DIM, int(previous.get("heat", 0)), int(state.get("heat", 0))]


static func _signed(value: int) -> String:
	return "%+d" % value


func _open_audience_log() -> void:
	_audience_log_open = true
	if _audience_log_tween != null:
		_audience_log_tween.kill()
	_audience_log_panel.visible = true
	_audience_log_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_audience_log_tween = create_tween().set_parallel(true)
	_audience_log_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_audience_log_tween.tween_property(_audience_log_panel, "position:y",
		_audience_log_open_y, AUDIENCE_LOG_TWEEN_TIME)
	_audience_log_tween.tween_property(_audience_log_panel, "modulate:a", 1.0,
		AUDIENCE_LOG_TWEEN_TIME * 0.8)


func _queue_audience_log_close() -> void:
	call_deferred("_close_audience_log_if_pointer_left")


func _close_audience_log_if_pointer_left() -> void:
	var hovered := get_viewport().gui_get_hovered_control()
	var current: Node = hovered
	while current != null:
		if current == _zal_bar:
			return
		current = current.get_parent()
	_close_audience_log()


func _close_audience_log() -> void:
	if not _audience_log_panel.visible:
		return
	_audience_log_open = false
	_audience_log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _audience_log_tween != null:
		_audience_log_tween.kill()
	_audience_log_tween = create_tween().set_parallel(true)
	_audience_log_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_audience_log_tween.tween_property(_audience_log_panel, "position:y",
		_audience_log_closed_y, AUDIENCE_LOG_TWEEN_TIME)
	_audience_log_tween.tween_property(_audience_log_panel, "modulate:a", 0.0,
		AUDIENCE_LOG_TWEEN_TIME * 0.75)
	_audience_log_tween.chain().tween_callback(func() -> void:
		if not _audience_log_open:
			_audience_log_panel.visible = false
	)


func _on_strain_gui_input(event: InputEvent, side: String) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	if _emotion_log_open and _emotion_log_side == side:
		_close_emotion_log()
	else:
		_open_emotion_log(side)
	accept_event()


func _on_emotion_observed(side: String, result: Dictionary) -> void:
	if not side in [C.SIDE_YOU, C.SIDE_OPP]:
		return
	_append_emotion_history(side, _format_emotion_event(side, result))
	if _emotion_log_side == side:
		_update_emotion_summary(side)


func _on_emotion_linked(_source_side: String, responder_side: String,
	result: Dictionary) -> void:
	if not responder_side in [C.SIDE_YOU, C.SIDE_OPP]:
		return
	var kind := String(result.get("kind", "none"))
	if kind == "trigger":
		return  # полноценный ответ следом придёт через emotion_observed
	var subject := "ВЫ" if responder_side == C.SIDE_YOU else "ОППОНЕНТ"
	var accent := COL_YOU if responder_side == C.SIDE_YOU else COL_OPP
	if kind == "parry":
		var parry: Dictionary = result.get("parry", {})
		var source := "срыв оппонента" if responder_side == C.SIDE_YOU else "ваш срыв"
		_append_emotion_history(responder_side,
			"[color=#%s]↩ %s ПАРИРОВАЛ%s · «%s»[/color]\n[color=#%s]%s отбит без роста давления.[/color]" % [
				accent, subject, "И" if responder_side == C.SIDE_YOU else "",
				String(parry.get("title", "холодный ответ")), COL_DIM, source.capitalize()])
	elif kind == "absorb":
		var held := "ВЫ ВЫДЕРЖАЛИ" if responder_side == C.SIDE_YOU else "ОППОНЕНТ ВЫДЕРЖАЛ"
		_append_emotion_history(responder_side,
			"[color=#%s]○ %s ЧУЖОЙ СРЫВ[/color]\n[color=#%s]Без ответа · давление осталось %d/%d.[/color]" % [
				COL_DIM, held, COL_DIM, int(result.get("after", 0)),
				int(controller.emotion_state(responder_side).get("max", 6))])
	else:
		return
	if _emotion_log_side == responder_side:
		_update_emotion_summary(responder_side)


func _append_emotion_history(side: String, body: String) -> void:
	var index := int(_emotion_event_indices.get(side, -1)) + 1
	_emotion_event_indices[side] = index
	var history: Array = _emotion_histories.get(side, [])
	history.append("[color=#%s]%02d[/color]  %s" % [COL_DIM, index, body])
	_emotion_histories[side] = history
	if _emotion_log_side == side:
		_render_emotion_history(side)


func _format_emotion_start(side: String, state: Dictionary) -> String:
	var subject := "ВЫ СПОКОЙНЫ" if side == C.SIDE_YOU else "ОППОНЕНТ СПОКОЕН"
	return "[color=#%s]● %s[/color]  давление %d/%d · риск %d%%\n[color=#%s]Манера: %s[/color]" % [
		COL_GOLD, subject, int(state.get("strain", 0)), int(state.get("max", 6)),
		roundi(float(state.get("chance", 0.0)) * 100.0), COL_DIM,
		String(state.get("deck_label", "Эмоциональная колода"))]


func _format_emotion_event(side: String, result: Dictionary) -> String:
	var before := int(result.get("before", 0))
	var peak := int(result.get("peak", before))
	var after := int(result.get("after", peak))
	var chance := roundi(float(result.get("chance", 0.0)) * 100.0)
	var stimulus_id := String(result.get("stimulus", ""))
	var stimulus := _emotion_stimulus_label(stimulus_id)
	var reaction: Dictionary = result.get("reaction", {})
	var context: Dictionary = result.get("context", {})
	var cause := _emotion_cause_phrase(context)
	var outcome := _emotion_outcome_sentence(stimulus_id, String(context.get("target", "")))
	var accent := COL_YOU if side == C.SIDE_YOU else COL_OPP
	if not reaction.is_empty():
		var boiled := "ВЫ ВСКИПЕЛИ" if side == C.SIDE_YOU else "ОППОНЕНТ ВСКИПЕЛ"
		var chain_note := " в ответ" if int(result.get("chain_depth", 0)) > 0 else ""
		return "[color=#%s]⚡ %s%s %s[/color]\n[color=#%s]%s Давление %d → %d → %d · «%s» · разрядка −%d.[/color]" % [
			accent, boiled, chain_note, cause, COL_DIM, outcome, before, peak, after,
			String(reaction.get("title", "эмоциональный срыв")), maxi(0, peak - after)]
	var heading := "ВЫ НАПРЯГЛИСЬ" if side == C.SIDE_YOU else "ОППОНЕНТ НАПРЯГСЯ"
	accent = COL_GOLD if peak >= 4 else COL_DIM
	if chance > 0:
		heading = "ВЫ УДЕРЖАЛИСЬ" if side == C.SIDE_YOU else "ОППОНЕНТ УДЕРЖАЛСЯ"
	return "[color=#%s]◆ %s %s[/color]\n[color=#%s]%s Давление %d → %d · следующий риск %d%%.[/color]" % [
		accent, heading, cause, COL_DIM, outcome if outcome != "" else stimulus.capitalize(),
		before, after, chance]


static func _emotion_cause_phrase(context: Dictionary) -> String:
	var action := String(context.get("cause_name", "")).strip_edges()
	if action == "":
		return ""
	if String(context.get("cause_side", "")) == C.SIDE_YOU:
		return "после вашего приёма «%s»" % action
	return "после приёма оппонента «%s»" % action


static func _emotion_outcome_sentence(stimulus: String, target: String) -> String:
	var quoted := "«%s»" % target if target != "" else "позиция"
	match stimulus:
		"attack_stalled": return "Нажим на %s захлебнулся." % quoted
		"argument_lost": return "Аргумент вокруг %s продавлен." % quoted
		"frame_lost": return "Рамка %s развалилась." % quoted
		"captured": return "Рамку %s увели целиком." % quoted
		"dirty_hit": return "Прилетел грязный приём."
		"reaction_received": return "Чужая вспышка попала в нерв."
		_: return ""


static func _emotion_stimulus_label(stimulus: String) -> String:
	match stimulus:
		"attack_stalled": return "атака захлебнулась"
		"argument_lost": return "проигран обмен аргументами"
		"frame_lost": return "потеряна рамка"
		"captured": return "рамка захвачена"
		"dirty_hit": return "грязный приём"
		"reaction_received": return "чужой эмоциональный срыв"
		_: return "эмоциональный импульс" if stimulus == "" else stimulus.replace("_", " ")


func _update_emotion_summary(side: String) -> void:
	if _emotion_summary == null:
		return
	var state: Dictionary = controller.emotion_state(side)
	_emotion_summary.text = "ДАВЛЕНИЕ %d/%d  ·  РИСК %d%%\nСРЫВЫ %d  ·  ПАРИРОВКИ %d" % [
		int(state.get("strain", 0)), int(state.get("max", 6)),
		roundi(float(state.get("chance", 0.0)) * 100.0),
		int(state.get("reactions", 0)), int(state.get("parries", 0))]


func _open_emotion_log(side: String) -> void:
	var was_visible := _emotion_log_panel.visible
	_emotion_log_side = side
	_emotion_log_open = true
	_set_emotion_log_positions(side)
	_emotion_log_panel.position.y = (_you_strain if side == C.SIDE_YOU else _opp_strain).position.y
	if not was_visible:
		_emotion_log_panel.position.x = _emotion_log_closed_x
	_emotion_log_title.text = "ВАШИ ЭМОЦИИ" if side == C.SIDE_YOU else "ЭМОЦИИ ОППОНЕНТА"
	_emotion_log_title.add_theme_color_override("font_color",
		Color.html("#" + (COL_YOU if side == C.SIDE_YOU else COL_OPP)))
	_render_emotion_history(side)
	_update_emotion_summary(side)
	if _emotion_log_tween != null:
		_emotion_log_tween.kill()
	_emotion_log_panel.visible = true
	_emotion_log_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_emotion_log_tween = create_tween().set_parallel(true)
	_emotion_log_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_emotion_log_tween.tween_property(_emotion_log_panel, "position:x",
		_emotion_log_open_x, AUDIENCE_LOG_TWEEN_TIME)
	_emotion_log_tween.tween_property(_emotion_log_panel, "modulate:a", 1.0,
		AUDIENCE_LOG_TWEEN_TIME * 0.8)


func _close_emotion_log() -> void:
	if not _emotion_log_panel.visible:
		return
	_emotion_log_open = false
	_emotion_log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _emotion_log_tween != null:
		_emotion_log_tween.kill()
	_emotion_log_tween = create_tween().set_parallel(true)
	_emotion_log_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_emotion_log_tween.tween_property(_emotion_log_panel, "position:x",
		_emotion_log_closed_x, AUDIENCE_LOG_TWEEN_TIME)
	_emotion_log_tween.tween_property(_emotion_log_panel, "modulate:a", 0.0,
		AUDIENCE_LOG_TWEEN_TIME * 0.75)
	_emotion_log_tween.chain().tween_callback(func() -> void:
		if not _emotion_log_open:
			_emotion_log_panel.visible = false
	)


func _set_emotion_log_positions(side: String) -> void:
	var meter := _you_strain if side == C.SIDE_YOU else _opp_strain
	if side == C.SIDE_YOU:
		_emotion_log_open_x = meter.position.x + meter.size.x + OPP_EMOTION_LOG_GAP
		_emotion_log_closed_x = meter.position.x - _emotion_log_panel.size.x \
			+ OPP_EMOTION_LOG_CLOSED_REVEAL
	else:
		_emotion_log_open_x = meter.position.x - _emotion_log_panel.size.x \
			- OPP_EMOTION_LOG_GAP
		_emotion_log_closed_x = meter.position.x - OPP_EMOTION_LOG_CLOSED_REVEAL


func _render_emotion_history(side: String) -> void:
	_emotion_log_rt.text = "\n\n".join(_emotion_histories.get(side, []))
	_emotion_log_rt.call_deferred("scroll_to_line",
		maxi(0, _emotion_log_rt.get_line_count() - 1))


func _on_match_reported(report: Dictionary) -> void:
	_restart_btn.visible = true
	var profile: Dictionary = report.get("profile", {})
	var board: Dictionary = report.get("board", {})
	var audience: Dictionary = report.get("audience", {})
	var emotion: Dictionary = report.get("emotion", {})
	var you_emotion: Dictionary = emotion.get(C.SIDE_YOU, {})
	var opp_emotion: Dictionary = emotion.get(C.SIDE_OPP, {})
	var winner := String(report.get("winner", "draw"))
	_final_profile.text = "ПРОФИЛЬ · %s" % String(profile.get("label", "эксперимент"))
	_final_rule.text = String(report.get("formula", ""))
	match winner:
		"you":
			_final_winner.text = "ВЫ ПОБЕДИЛИ"
			_final_winner.add_theme_color_override("font_color", Color.html("#" + COL_YOU))
		"opp":
			_final_winner.text = "ПОБЕДИЛ ОППОНЕНТ"
			_final_winner.add_theme_color_override("font_color", Color.html("#" + COL_OPP))
		_:
			_final_winner.text = "НИЧЬЯ"
			_final_winner.add_theme_color_override("font_color", Color.html("#" + COL_DIM))
	_final_board_score.text = "B  %+d" % int(board.get("score", 0))
	_final_board_detail.text = "Рамки  ВЫ %d : %d ОПП  →  %+d\nТезисы ВЫ %d : %d ОПП  →  %+d" % [
		int(board.get("you_frames", 0)), int(board.get("opp_frames", 0)),
		int(board.get("frame_diff", 0)) * int(board.get("frame_weight", 1)),
		int(board.get("you_theses", 0)), int(board.get("opp_theses", 0)),
		int(board.get("thesis_diff", 0)) * int(board.get("thesis_weight", 1))]
	var lean := int(audience.get("lean", 0))
	var heat := int(audience.get("heat", 0))
	var decision_threshold := maxi(1, int(audience.get("decision_threshold", 1)))
	var crowd_winner := "draw"
	if absi(lean) >= decision_threshold:
		crowd_winner = C.SIDE_YOU if lean > 0 else C.SIDE_OPP
	_final_audience_score.text = "КРЕН  %+d" % lean
	var lean_text := "зал не выбрал сторону"
	if lean == 1:
		lean_text = "лёгкий крен к вам"
	elif lean == -1:
		lean_text = "лёгкий крен к оппоненту"
	elif crowd_winner == C.SIDE_YOU:
		lean_text = "зал выбрал вас"
	elif crowd_winner == C.SIDE_OPP:
		lean_text = "зал выбрал оппонента"
	_final_audience_detail.text = "АЗАРТ %d/%d\n%s" % [
		heat, int(audience.get("heat_max", 0)), lean_text]
	var you_strain := int(you_emotion.get("strain", 0))
	var opp_strain := int(opp_emotion.get("strain", 0))
	var you_reactions := int(you_emotion.get("reactions", 0))
	var opp_reactions := int(opp_emotion.get("reactions", 0))
	_final_emotion_score.text = "ВЫ %d  ·  %d ОПП" % [you_reactions, opp_reactions]
	_final_emotion_detail.text = "Давление осталось: ВЫ %d/%d · ОПП %d/%d\nФинальное состояние · вне счёта" % [
		you_strain, int(you_emotion.get("max", 6)), opp_strain,
		int(opp_emotion.get("max", 6))]
	var board_winner := String(report.get("board_winner", "draw"))
	var split := board_winner != "draw" and crowd_winner != "draw" \
		and board_winner != crowd_winner
	if split:
		_final_split.text = "РАСКОЛ: ДОСКА И ЗАЛ ВЫБРАЛИ РАЗНЫХ ОРАТОРОВ"
		_final_split.add_theme_color_override("font_color", Color.html("#" + COL_GOLD))
	elif crowd_winner == "draw":
		_final_split.text = "ЗАЛ НЕ ВЫБРАЛ СТОРОНУ"
		_final_split.add_theme_color_override("font_color", Color.html("#" + COL_DIM))
	elif board_winner == "draw":
		var hall_side := "К ВАМ" if crowd_winner == C.SIDE_YOU else "К ОППОНЕНТУ"
		_final_split.text = "ДОСКА: НИЧЬЯ · ЗАЛ СКЛОНИЛСЯ %s" % hall_side
		_final_split.add_theme_color_override("font_color", Color.html("#" + COL_GOLD))
	else:
		_final_split.text = "ДОСКА И ЗАЛ СОГЛАСНЫ"
		var agreement_color := COL_YOU if board_winner == C.SIDE_YOU else COL_OPP
		_final_split.add_theme_color_override("font_color", Color.html("#" + agreement_color))
	_final_verdict.text = String(report.get("verdict", ""))
	_final_description.text = String(profile.get("description", ""))
	_final_overlay.visible = true
	_refresh()


func _close_final_overlay() -> void:
	_final_overlay.visible = false


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 90:
		log_lines = log_lines.slice(log_lines.size() - 90, log_lines.size())


# ----------------------------------------------------------------- view -------

func _refresh() -> void:
	if model == null:
		return
	var you_n: int = model.score(C.SIDE_YOU)
	var opp_n: int = model.score(C.SIDE_OPP)
	var live_report: Dictionary = controller.outcome_report()
	var live_board: Dictionary = live_report.get("board", {})
	_score_label.text = "ДОСКА B %+d  ·  рамки %d:%d  ·  тезисы %d:%d  ·  РЕЗЕРВ U %d:%d  (опп:вы)" % [
		int(live_board.get("score", 0)), opp_n, you_n,
		int(live_board.get("opp_theses", 0)), int(live_board.get("you_theses", 0)),
		int(model.reserve_count(C.SIDE_OPP)), int(model.reserve_count(C.SIDE_YOU))]
	var audience: Dictionary = controller.audience_state()
	var z: int = int(audience.get("lean", model.zal()))
	var crowd_note := ""
	# «Счёт судьи» нужен только профилям с явным Crowd TKO; шатание теперь живёт на strain.
	if int(model.zal_ko) > 0:
		var sy := int(model.crowd_streak.get(C.SIDE_YOU, 0))
		var so := int(model.crowd_streak.get(C.SIDE_OPP, 0))
		if sy > 0:
			crowd_note = "  ·  ЗАЛ СКАНДИРУЕТ ЗА ВАС: %d/%d" % [sy, int(model.zal_hold)]
		elif so > 0:
			crowd_note = "  ·  ЗАЛ СКАНДИРУЕТ: %d/%d — ВЕРНИТЕ ЗАЛ!" % [so, int(model.zal_hold)]
	if String(audience.get("mode", "derived")) == "derived":
		_zal_label.text = "ЗАЛ: КРЕН %+d  (legacy: рамки + сила)%s" % [z, crowd_note]
	else:
		_zal_label.text = "ЗАЛ: КРЕН %+d  ·  АЗАРТ %d/%d%s" % [z,
			int(audience.get("heat", 0)), int(audience.get("heat_max", 0)), crowd_note]
	_update_bar(z)
	_update_emotion_hud()
	_update_status_hud()
	var input_mode := String(controller.input_mode())
	_rebuild_frames(_opp_row, board_lines_for_mode(model.sides[C.SIDE_OPP].lines,
		input_mode), false, _opp_sep0)
	_rebuild_frames(_you_row, board_lines_for_mode(model.sides[C.SIDE_YOU].lines,
		input_mode), true, _you_sep0)
	_rebuild_hand()
	_draw_count.text = str(model.sides[C.SIDE_YOU].draw.size())
	_update_controls()


## Стартовые рамки уже существуют в rules state для симметричной Базы 1:1, но до выбора
## игроком это ещё не сыгранные карты. Скрываем только presentation; модель не мутируем.
static func board_lines_for_mode(lines: Array, input_mode: String) -> Array:
	return [] if input_mode == "opening" else lines


func _update_emotion_hud() -> void:
	var player_state: Dictionary = controller.emotion_state(C.SIDE_YOU)
	_render_strain(player_state, _you_strain_bg,
		_you_strain_fill, _you_strain_label, "ВЫ", C.SIDE_YOU)
	var opponent_state: Dictionary = controller.emotion_state(C.SIDE_OPP)
	_render_strain(opponent_state, _opp_strain_bg,
		_opp_strain_fill, _opp_strain_label, "ОПП", C.SIDE_OPP)
	if _emotion_log_side != "":
		_update_emotion_summary(_emotion_log_side)


func _render_strain(state: Dictionary, bg: ColorRect, fill: ColorRect, label: Label,
	who: String, side: String) -> void:
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
	var reach := int(model.frame_capture_reach(side))
	if reach >= 2:
		status += " · ШАТ.≤%d" % reach
	label.text = "%s\n%d/%d\n%s" % [who, strain, maximum, status]


func _update_status_hud() -> void:
	if controller == null:
		return
	_rebuild_status_row(_you_status_row, controller.status_list(C.SIDE_YOU))
	_rebuild_status_row(_opp_status_row, controller.status_list(C.SIDE_OPP))


func _rebuild_status_row(row: Control, statuses: Array) -> void:
	for c in row.get_children():
		c.queue_free()
	for i in statuses.size():
		var icon := _status_icon(statuses[i])
		icon.position = Vector2(i * (STATUS_ICON_SIZE + STATUS_ICON_GAP), 0)
		row.add_child(icon)


const STATUS_DURABILITY_RU := {
	"fundamental": "навсегда", "base": "стартовый", "temporary": "временный",
}
const STATUS_SOURCE_RU := {
	"outgoing": "свой", "incoming": "от оппонента/условий",
}


## Круглая заглушка-иконка одного статуса: цвет по polarity, буква по label. Полное описание
## живёт в кастомном тултипе (status_icon.gd._make_custom_tooltip) — Godot сам показывает его
## у курсора по задержке наведения, пока не нужны арт-ассеты под конкретные перки.
func _status_icon(entry: Dictionary) -> Control:
	var perk := String(entry.get("polarity", "")) == "perk"
	var fill := Color.html(COL_YOU if perk else COL_RAZBOR)
	var panel := StatusIcon.new()
	panel.size = Vector2(STATUS_ICON_SIZE, STATUS_ICON_SIZE)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = fill.lightened(0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(STATUS_ICON_SIZE / 2.0))
	panel.add_theme_stylebox_override("panel", sb)
	var label := Label.new()
	label.text = String(entry.get("label", "?")).left(1).to_upper()
	label.size = panel.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.html("ffffff"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	panel.tooltip_text = _status_tooltip_text(entry, perk)
	return panel


func _status_tooltip_text(entry: Dictionary, perk: bool) -> String:
	var durability := String(entry.get("durability", ""))
	var duration_note := ""
	if durability == "temporary":
		duration_note = " (%d ход.)" % int(entry.get("remaining_turns", 0))
	return "%s\n%s · %s%s · %s" % [
		String(entry.get("label", "")),
		"перк" if perk else "дебаф",
		STATUS_DURABILITY_RU.get(durability, durability), duration_note,
		STATUS_SOURCE_RU.get(String(entry.get("source", "")), String(entry.get("source", "")))]


## Подсказка и кнопки клинча/отмены — из режима ввода контроллера.
func _update_controls() -> void:
	var mode := String(controller.input_mode())
	_hint_label.text = String(controller.hint_text)
	_cancel_btn.visible = mode == "target"
	if mode == "clinch_defend":
		var opener: bool = not model.clinch.is_empty() and \
			(model.clinch.get("sequence", []) as Array).size() == 1
		var sequence: Array = model.clinch.get("sequence", [])
		var incoming: Dictionary = sequence.back() if not sequence.is_empty() else {}
		var outcome := "украдёт" if bool(incoming.get("steals", false)) else "снимет"
		_clinch_btn.text = "Пропустить (исходная атака ударит в рамку)" if opener else \
			"Пропустить (эта карта %s тезис; цепь дойдёт до рамки)" % outcome
		_clinch_btn.visible = true
	elif mode == "clinch_attack":
		_clinch_btn.text = "Остановиться (ответный тезис закроет всю цепь)"
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
	var audience: Dictionary = controller.audience_state()
	var zmax := maxi(1, int(audience.get("lean_cap", C.ZAL_MAX)))
	var t := clampf(float(z) / float(zmax), -1.0, 1.0)
	var center := bar_x + bar_w / 2.0
	var mx := center + t * (bar_w / 2.0)
	_marker.position = Vector2(mx - 3.5, bar_y - 4.0)
	if z >= 0:
		_fill.position = Vector2(center, bar_y)
		_fill.size = Vector2(mx - center, bar_h)
		_fill.color = Color.html("#" + COL_YOU)
	else:
		_fill.position = Vector2(mx, bar_y)
		_fill.size = Vector2(center - mx, bar_h)
		_fill.color = Color.html("#" + COL_OPP)


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
	var side := C.SIDE_YOU if is_you else C.SIDE_OPP
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
	var side := C.SIDE_YOU if is_you else C.SIDE_OPP
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
	for i in razbors:
		# Старый стейт надёжно знает только объект первой атаки; эффект поздней карты
		# нельзя восстанавливать из агрегата без нарушения карточной семантики.
		var steals := bool(cl.get("init_steals", false)) if i == 0 else false
		fallback.append({"type": C.TYPE_RAZBOR, "steals": steals})
		if i < theses:
			fallback.append({"type": C.TYPE_TEZIS, "stolen": false})
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


## Однострочная подпись над рамкой раскрывается внутрь доски: у игрока вправо от левого
## края рамки, у зеркального ряда оппонента — влево от её правого края. Полная ширина
## текста намеренно не ограничена шириной группы: иначе исправленное обрезание просто
## превратилось бы в многоточие.
static func frame_tag_rect(frame_x: float, reverse: bool, text_width: float) -> Rect2:
	var width := maxf(ceilf(text_width) + 4.0, CARD_W)
	var x := frame_x + CARD_W - width if reverse else frame_x
	return Rect2(x, 0.0, width, 18.0)


func _layout_frame_tag(label: Label, frame_x: float, reverse: bool) -> void:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	# combined_minimum_size учитывает fallback-глифы — в том числе ⚡ у combo_bait.
	var text_width := maxf(label.get_combined_minimum_size().x,
		font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x)
	var rect := frame_tag_rect(frame_x, reverse, text_width)
	label.position = Vector2(rect.position.x, 8.0)
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if reverse \
		else HORIZONTAL_ALIGNMENT_LEFT


## The board reads the object stack when it exists. Defensive theses added by the
## active clinch live at its top but render in the clinch overlay, so the base frame
## gets only the prefix below them. Scalars are a fallback for legacy state only.
static func visible_thesis_tokens(line: Dictionary, contested_t_added: int = 0) -> Array:
	var hidden := maxi(0, contested_t_added)
	var raw_stack: Variant = line.get("thesis_stack", null)
	if raw_stack is Array:
		var stack: Array = raw_stack
		var visible_count := maxi(0, stack.size() - mini(hidden, stack.size()))
		var visible: Array = []
		for i in visible_count:
			visible.append(stack[i])
		return visible

	var total := maxi(0, int(line.get("theses", 0)) - hidden)
	var stolen := clampi(int(line.get("stolen", 0)), 0, total)
	var fallback: Array = []
	for i in total:
		fallback.append({
			"thesis_id": "",
			"stolen": i >= total - stolen,
		})
	return fallback


func _make_frame_group(line: Dictionary, is_you: bool, idx: int, gap: float,
	trailing_pad: float = FRAME_GROUP_PAD, reverse: bool = false) -> Control:
	var closed: bool = line.closed
	# Контест и счётчик ударов — прямо из стейта клинча в ядре (model.clinch).
	var cl: Dictionary = model.clinch
	var contested := false
	var razbors := 0
	if not cl.is_empty():
		var my_side := C.SIDE_YOU if is_you else C.SIDE_OPP
		contested = (int(cl.idx) == idx) and (String(cl.defender) == my_side)
		razbors = int(cl.r_count)
	var thesis_tokens := visible_thesis_tokens(line,
		int(cl.get("t_added", 0)) if contested else 0)
	var theses := thesis_tokens.size()
	var targetable: bool = String(controller.input_mode()) == "target" and not is_you
	# View reads exact object thickness and reach from the owner's emotional strain.
	# Temporary/permanent frame protection remains a separate eligibility flag.
	var owner := C.SIDE_YOU if is_you else C.SIDE_OPP
	var threat: Dictionary = controller.frame_threat(owner, idx)
	var shaky: bool = not contested and bool(threat.get("shaky", false))

	var shown := mini(theses, 8)
	var width := _group_width(theses, gap)
	var root := Control.new()
	root.custom_minimum_size = Vector2(maxf(width, CARD_W) + trailing_pad, CARD_H + 30.0)
	var y0 := 26.0
	if shaky:
		_start_wobble(root)

	# Карта-установка показывает claim (позицию-топик), если он назначен.
	var claim_txt: String = String(line.get("claim", line.name))
	var uc := _mkcard({"type": C.TYPE_USTANOVKA, "steals": false},
		COL_USTAN, closed, contested)
	uc.set_meta("board_card", true)
	uc.set_meta("board_role", "frame")
	uc.set_meta("frame_idx", idx)  ## драг-дроп руки (§ниже) хит-тестит рамки без завязки на pressed
	uc.position = Vector2(board_card_position_x(0.0, width, trailing_pad, reverse), y0)
	var frame_info := claim_txt
	var top_scheme := String(threat.get("top_scheme", ""))
	var combo_bait := bool(threat.get("combo_bait", false))
	if top_scheme != "":
		frame_info += "\n\nСВЕРХУ: %s" % top_scheme
		if combo_bait:
			frame_info += "\n\n⚡ В РУКЕ ЕСТЬ ОТКРЫВАЮЩИЙ ПРИЁМ"
	if shaky:
		frame_info += "\n\n⚠ ШАТАЕТСЯ · КРАЖА ДО %d\nНапряжение владельца %d/%d · толщина %d" % [
			int(threat.get("reach", 1)), int(threat.get("strain", 0)),
			int(threat.get("strain_max", 6)),
			int(threat.get("thickness", theses))]
		var warn := Label.new()
		warn.text = "ШАТАЕТСЯ · КРАЖА ДО %d" % int(threat.get("reach", 1))
		warn.add_theme_font_override("font", TAG_FONT)
		warn.add_theme_font_size_override("font_size", 10)
		warn.add_theme_color_override("font_color", Color.html("#" + COL_RAZBOR))
		warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(warn)
		_layout_frame_tag(warn, uc.position.x - 2.0, reverse)
	elif top_scheme != "":
		# Комбо §12: схема верхнего Тезиса читается прямо на рамке (шаткость приоритетнее —
		# оба лейбла делят одну строку над рамкой). combo_bait — та же золотая подсветка,
		# что и у правильного ответа в клинче (combo_answer_glow), для симметрии подсказки.
		var scheme_tag := Label.new()
		scheme_tag.text = ("⚡ " + top_scheme.to_upper()) if combo_bait else top_scheme.to_upper()
		scheme_tag.add_theme_font_override("font", TAG_FONT)
		scheme_tag.add_theme_font_size_override("font_size", 10)
		scheme_tag.add_theme_color_override("font_color",
			Color.html("#" + (COL_GOLD if combo_bait else COL_TEZIS)))
		scheme_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(scheme_tag)
		_layout_frame_tag(scheme_tag, uc.position.x - 2.0, reverse)
	if bool(threat.get("last_frame", false)) and bool(model.board_ko_enabled):
		frame_info += "\n\nЕсли рамка падёт: %s · резерв %d" % [
			("НОКАУТ" if bool(threat.get("lethal", false)) else "восстановление следующим ходом"),
			int(threat.get("reserve", 0))]
	if targetable:
		uc.disabled = false
		uc.pressed.connect(_on_target_pressed.bind(idx))
		var combo_note: String = controller.target_combo_note(idx)
		if combo_note != "":
			frame_info += "\n\n%s" % combo_note
		var spoken: String = controller.target_preview(idx)
		if spoken != "":
			frame_info += "\n\nСКАЖЕТЕ:\n%s" % spoken
	_attach_card_bubble(uc, "Рамка", frame_info,
		{"type": C.TYPE_USTANOVKA, "steals": false})
	root.add_child(uc)

	for j in shown:
		var thesis_token: Dictionary = thesis_tokens[j]
		var is_st := bool(thesis_token.get("stolen", false))
		# Украденный тезис сохраняет тезисную пиктограмму; золото живёт только в окантовке.
		var tc := _mkcard({"type": C.TYPE_TEZIS, "steals": false},
			(COL_GOLD if is_st else COL_TEZIS), closed, false)
		tc.set_meta("board_stolen", is_st)
		tc.set_meta("thesis_id", String(thesis_token.get("thesis_id", "")))
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
			var played_type := String(played.get("type", C.TYPE_RAZBOR))
			var is_theft := played_type == C.TYPE_RAZBOR and bool(played.get("steals", false))
			var is_stolen_thesis := played_type == C.TYPE_TEZIS and bool(played.get("stolen", false))
			var border_col := COL_TEZIS if played_type == C.TYPE_TEZIS else COL_RAZBOR
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
	b.add_theme_constant_override("icon_max_width", 38)
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
	var hand: Array = model.sides[C.SIDE_YOU].hand
	var recovery: Array = model.recovery_indices(C.SIDE_YOU) if mode == "reframe" else []
	var legal: Array = model.legal_types(C.SIDE_YOU) if mode == "move" else []
	for i in hand.size():
		var card: Dictionary = hand[i]
		var enabled := false
		match mode:
			"clinch_defend":
				enabled = model.clinch_card_legal(card)
			"clinch_attack":
				enabled = model.clinch_card_legal(card)
			"move":
				enabled = card.type in legal
			"reframe":
				enabled = i in recovery
		# Лицо карты: у ванильной — точная контекстная реплика; у ИМЕННОЙ (zal_run §2) —
		# имя и правило-твист. Для Разбора точная строка появляется на рамке после выбора карты,
		# потому что содержание зависит от цели.
		# Сам дизайн карты (слои/шрифты/размер) — шаблон ui/card/card.tscn, правится в редакторе.
		var is_named: bool = card.has("named")
		# Установки имеют собственные названия (Рамка / Тезис дня / Позиция), поэтому не
		# схлопываем их все в одинаковый заголовок «Установка».
		var title: String = String(card.get("name", "")) if is_named or \
			card.type == C.TYPE_USTANOVKA else nar.device_label(card)
		if bool(card.get("opening_reserve", false)):
			title = "Резервная рамка"
		var body: String = String(card.get("text", "")) if is_named else controller.hand_preview(i)
		if bool(card.get("opening_reserve", false)) and String(card.get("claim", "")) != "":
			body = "«%s»\n\nПУБЛИЧНЫЙ РЕЗЕРВ" % String(card.claim)
		var btn: Button = CardScene.instantiate()
		_hand_row.add_child(btn)  # в дерево ДО setup: слои шаблона резолвятся в _ready
		btn.setup(card, title, body, enabled)
		var bubble_title := title if is_named else "%s · %s" % [title, String(card.get("name", ""))]
		var bubble_body := String(card.get("text", "")) if is_named else "СКАЖЕТЕ:\n%s" % body
		if is_named:
			bubble_body = "Именной приём\n\n" + bubble_body
		if mode == "reframe" and not enabled and card.type == C.TYPE_USTANOVKA:
			bubble_body += "\n\nЭта рамка пришла после падения и сейчас не может спасти позицию."
		# Комбо §12: правильный ответ на открытый LINK светится золотом, но НЕ автоплей —
		# решение (и цена хранения финишера) остаются за игроком.
		if mode == "clinch_defend" and controller.combo_answer_glow(i):
			btn.self_modulate = Color.html("#" + COL_GOLD)
			bubble_body += "\n\n⚡ ПРАВИЛЬНЫЙ ОТВЕТ: закроет маршрут и вооружит комбо-ставку."
		if mode == "move" and controller.combo_opener_glow(i):
			btn.self_modulate = Color.html("#" + COL_GOLD)
			var opener_targets: Array = controller.combo_opener_targets(i)
			var target_bits: Array = []
			for t in opener_targets:
				var closes: String = "/".join(t.get("answer_schemes", []) as Array)
				target_bits.append("(%s) («%s») (закроет: %s)" % [
					String(t.get("scheme", "")), String(t.get("name", "")), closes])
			bubble_body += "\n\n⚡ ОТКРЫВАЕТ МАРШРУТ → %s" % ", ".join(target_bits)
		_attach_card_bubble(btn, bubble_title, bubble_body, card)
		_attach_hand_motion(btn)
		btn.pressed.connect(_on_hand_pressed.bind(i))
		btn.gui_input.connect(_on_hand_card_gui_input.bind(btn, i))
	_layout_hand()


## На нулевом ходе смысловые варианты выглядят как обычные карты-Установки в руке.
## Это presentation-only: контроллер по-прежнему не списывает U-карту и не двигает ход.
func _rebuild_opening_hand() -> void:
	for option in controller.opening_options():
		var axes: Array = nar.axis_tags(option.get("preferred_axes", []))
		var focus := "" if axes.is_empty() else "Фокус: %s" % " · ".join(axes)
		var card := {"type": C.TYPE_USTANOVKA,
			"name": "Активная рамка", "steals": false}
		var body := "«%s»" % String(option.get("text", ""))
		if focus != "":
			body += "\n\n" + focus
		var btn: Button = CardScene.instantiate()
		_hand_row.add_child(btn)
		btn.setup(card, "Активная рамка", body, true)
		var rule := "Не расходует карту или ход. Сила Базы остаётся 1. Одна из двух других рамок случайно станет публичным резервом."
		var bubble_body := "%s\n\n%s\n\n%s" % [
			"«%s»" % String(option.get("text", "")), focus, rule]
		_attach_card_bubble(btn, "Активная рамка", bubble_body, card)
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
	# get_meta(key, null) не глушит предупреждение "no meta with key" при первом наведении —
	# null неотличим от отсутствующего дефолта на уровне движка. has_meta() — без варнинга.
	var previous: Variant = card.get_meta("hand_tween") if card.has_meta("hand_tween") else null
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


## --- драг-дроп руки (второй способ; первый — клик-клик выше, не тронут) -------------------
##
## Порог движения отличает драг от клика: gui_input карты ловит только НАЖАТИЕ, дальнейшее
## движение мыши ловится в _input() всего экрана — иначе как только курсор уходит с исходной
## карты, её gui_input больше ничего не получает (сигнал живёт, пока курсор физически над
## узлом). Призрак — дубликат карты руки (card.duplicate(), без сигналов по умолчанию), летит
## поверх экрана; оригинал скрывается на время драга.
##
## play_hand() зовётся уже на СТАРТЕ драга — ровно то же самое, что делает клик по карте, для
## ЛЮБОГО режима (move/clinch_defend/clinch_attack/reframe). Дальше проверяем РЕЗУЛЬТАТ, а не
## гадаем по типу карты заранее: если контроллер ушёл в "target" — есть что отменить
## (cancel_targeting не трогает ни руку, ни доску) и куда донести дропом; если нет — ход уже
## отыгран (клинч/редеплой/тезис резолвятся немедленно, без отдельного таргетинга), и остаток
## драга — чисто косметическое долётывание призрака до точки отпускания.

func _on_hand_card_gui_input(event: InputEvent, card: Button, index: int) -> void:
	if _drag_active or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		if card.disabled:
			return
		_drag_pending = {"card": card, "index": index}
		_drag_start_global = get_global_mouse_position()
	else:
		_drag_pending = {}


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _drag_active:
			_update_drag_ghost(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		elif not _drag_pending.is_empty() and \
			(get_global_mouse_position() - _drag_start_global).length() > DRAG_THRESHOLD:
			_begin_drag()
			if _drag_active:
				_update_drag_ghost(get_global_mouse_position())  # не ждать следующего motion
			get_viewport().set_input_as_handled()
	elif _drag_active and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_end_drag(get_global_mouse_position())
			get_viewport().set_input_as_handled()


func _begin_drag() -> void:
	var card: Control = _drag_pending.card
	var index: int = _drag_pending.index
	_drag_pending = {}
	if not is_instance_valid(card):
		return
	_drag_active = true
	_drag_index = index
	_drag_hand_size = card.custom_minimum_size
	_drag_ghost = card.duplicate() as Control
	add_child(_drag_ghost)
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.z_index = 2000
	_drag_ghost.global_position = card.global_position
	card.visible = false
	controller.play_hand(index)
	_drag_kind = "targeted" if String(controller.input_mode()) == "target" else "committed"


func _update_drag_ghost(global_point: Vector2) -> void:
	if not is_instance_valid(_drag_ghost):
		return
	_drag_ghost.global_position = global_point - _drag_hand_size * 0.5
	if _drag_kind == "targeted":
		_update_drag_target_marker(global_point)


## Автонаведение: над своей рукой ничего не маркируем (сигнал «отпустишь тут — отмена»),
## иначе — ближайшая рамка оппонента, не точное попадание в её маленький хитбокс.
func _update_drag_target_marker(global_point: Vector2) -> void:
	var node: Button = null
	if not _is_drop_over_hand(global_point):
		node = _nearest_targetable_frame(global_point).get("node")
	if node == _drag_marked_frame:
		return
	_unmark_drag_target()
	if is_instance_valid(node):
		_mark_drag_target(node)


func _mark_drag_target(frame: Button) -> void:
	_drag_marked_frame = frame
	frame.pivot_offset = frame.size * 0.5
	var tw := frame.create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(frame, "scale", Vector2.ONE * DRAG_TARGET_MARK_SCALE, 0.12)
	tw.tween_property(frame, "self_modulate", DRAG_TARGET_MARK_COLOR, 0.12)


func _unmark_drag_target() -> void:
	var frame := _drag_marked_frame
	_drag_marked_frame = null
	_unmark_drag_target_node(frame)


func _unmark_drag_target_node(frame: Button) -> void:
	if not is_instance_valid(frame):
		return
	var tw := frame.create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(frame, "scale", Vector2.ONE, 0.1)
	tw.tween_property(frame, "self_modulate", Color.WHITE, 0.1)


func _end_drag(release_global: Vector2) -> void:
	var ghost := _drag_ghost
	var kind := _drag_kind
	var index := _drag_index
	_unmark_drag_target()
	_drag_ghost = null
	_drag_active = false
	_drag_kind = ""
	_drag_index = -1
	if kind == "targeted":
		# По запросу игрока — решение по ТОЧКЕ ОТПУСКАНИЯ, пересчитанной заново, а не по
		# истории маркера во время драга (тот остаётся только визуальной подсказкой на лету).
		var hit: Dictionary = {} if _is_drop_over_hand(release_global) else \
			_nearest_targetable_frame(release_global)
		if hit.is_empty():
			controller.cancel_targeting()
			_return_ghost_to_hand(ghost, index)
		else:
			_resolve_targeted_land(ghost, int(hit.idx), hit.rect)
	else:
		# "committed" — ход уже отыгран при старте драга; довести призрак до точки отпускания
		# и погасить, откатывать нечего.
		var target := Rect2(release_global - Vector2(CARD_W, CARD_H) * 0.5, Vector2(CARD_W, CARD_H))
		_land_ghost(ghost, target)


## choose_target тянет за собой весь _run_clinch. Поэтому призрак targeted-карты обязан
## закончить посадку ДО вызова контроллера: если хранить его до полного settlement, он снова
## появится только при возврате на общий план и визуально повторит уже сыгранную карту.
## Точный финальный состав рамки заранее неизвестен, зато выбранный rect известен в момент
## отпускания — туда и садится opener. Пока tween идёт, локальные клик/отмена цели заблокированы,
## чтобы тот же выбор нельзя было отправить контроллеру вторым путём.
func _resolve_targeted_land(ghost: Control, idx: int, target_rect: Rect2) -> void:
	_target_land_pending = true
	var landing := _land_ghost(ghost, target_rect)
	if landing != null:
		await landing.finished
	_target_land_pending = false
	await controller.choose_target(idx)

func _is_drop_over_hand(global_point: Vector2) -> bool:
	return _hand_row.get_global_rect().grow(24.0).has_point(global_point)


## Рамки оппонента — единственные кликабельные (targetable) в target-режиме; frame_idx
## записан в _make_frame_group специально для этого хит-теста, без завязки на pressed-сигнал.
## ВАЖНО: кнопка-рамка (uc) — не прямой ребёнок _opp_row, а внук (root-группа из
## _make_frame_group лежит между ними) — обходим на уровень глубже, не только прямых детей.
func _nearest_targetable_frame(global_point: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := INF
	for group in _opp_row.get_children():
		for child in (group as Node).get_children():
			if not (child is Button) or not child.has_meta("frame_idx"):
				continue
			var b := child as Button
			if b.disabled:
				continue
			var rect := b.get_global_rect()
			var d := rect.get_center().distance_to(global_point)
			if d < best_dist:
				best_dist = d
				best = {"idx": int(b.get_meta("frame_idx")), "rect": rect, "node": b}
	return best

func _land_ghost(ghost: Control, target_rect: Rect2) -> Tween:
	if not is_instance_valid(ghost):
		return null
	var target_scale := Vector2(
		target_rect.size.x / maxf(1.0, _drag_hand_size.x),
		target_rect.size.y / maxf(1.0, _drag_hand_size.y))
	var tw := ghost.create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(ghost, "global_position", target_rect.position, DRAG_GHOST_LAND_TIME)
	tw.tween_property(ghost, "scale", target_scale, DRAG_GHOST_LAND_TIME)
	tw.set_parallel(false)
	tw.tween_property(ghost, "modulate:a", 0.0, 0.1)
	tw.finished.connect(ghost.queue_free)
	return tw


## index может указывать на уже перестроенную руку (play_hand на старте targeted-драга уже
## перерисовал её в disabled-виде, cancel_targeting перерисует ещё раз) — карту в руке ищем
## заново по актуальным детям _hand_row, не по кэшированной ссылке.
func _return_ghost_to_hand(ghost: Control, index: int) -> void:
	if not is_instance_valid(ghost):
		return
	var live: Array = _hand_row.get_children().filter(func(c): return not c.is_queued_for_deletion())
	var target_pos := ghost.global_position
	if index >= 0 and index < live.size():
		var card := live[index] as Control
		card.visible = true
		target_pos = card.global_position
	var tw := ghost.create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "global_position", target_pos, DRAG_GHOST_CANCEL_TIME)
	tw.tween_property(ghost, "scale", Vector2.ONE, DRAG_GHOST_CANCEL_TIME)
	tw.set_parallel(false)
	tw.tween_callback(ghost.queue_free)


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
		C.TYPE_RAZBOR:
			border = Color.html("#" + (COL_GOLD if bool(card.get("steals", false)) else COL_RAZBOR))
		C.TYPE_USTANOVKA:
			border = Color.html("#" + COL_USTAN)
	_card_bubble.add_theme_stylebox_override("panel",
		_card_style(Color.html("#111722"), border, 2))
	_resize_card_bubble_to_body()
	_card_bubble.visible = true


## Тело описания — переменной длины (комбо-подсказки теперь могут перечислять несколько
## рамок), рамка тянется под текст вместо фиксированной высоты, которая его обрезала.
func _resize_card_bubble_to_body() -> void:
	var body_width := _card_bubble_body.offset_right - _card_bubble_body.offset_left
	var font: Font = _card_bubble_body.get_theme_font("font")
	var font_size := _card_bubble_body.get_theme_font_size("font_size")
	var needed_h: float = clampf(font.get_multiline_string_size(_card_bubble_body.text,
		HORIZONTAL_ALIGNMENT_LEFT, body_width, font_size).y, 24.0, 500.0)
	var body_bottom := _card_bubble_body.offset_top + needed_h + 6.0
	_card_bubble_body.offset_bottom = body_bottom
	_card_bubble.offset_bottom = _card_bubble.offset_top + body_bottom + 14.0


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


func _select_outcome_profile(i: int) -> void:
	var profiles: Array = controller.outcome_profile_list()
	if i < 0 or i >= profiles.size():
		return
	_close_menu()
	controller.select_outcome_profile(String((profiles[i] as Dictionary).id))


## Содержимое оверлея (без самого Control) — для перестройки отметки активной колоды.
func _build_menu_contents() -> void:
	var themes: Array = controller.theme_list()
	# Панель растёт по высоте вместе со списком колод, профилем исхода и настройками.
	var themes_bottom := 298.0 + float(themes.size()) * 38.0
	var outcome_top := themes_bottom + 10.0
	var settings_top := outcome_top + 72.0
	var panel_y := 90.0
	var panel_h := settings_top + 150.0 - panel_y

	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.07, 0.09, 0.82)
	dim.size = Vector2(1152, 648)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_overlay.add_child(dim)
	var panel := ColorRect.new()
	panel.color = Color.html("#1b1f27")
	panel.position = Vector2(356, panel_y)
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

	# --- ПРОФИЛЬ ИСХОДА: единый переключатель для ручной калибровки. ---
	_menu_label("УСЛОВИЯ ПОБЕДЫ", 376, outcome_top, 13, COL_DIM, 400)
	var profile_select := OptionButton.new()
	var outcome_profiles: Array = controller.outcome_profile_list()
	var active_profile := String(controller.active_outcome_profile_id())
	var active_index := 0
	for i in outcome_profiles.size():
		var profile: Dictionary = outcome_profiles[i]
		profile_select.add_item(String(profile.label))
		if String(profile.id) == active_profile:
			active_index = i
	profile_select.select(active_index)
	profile_select.position = Vector2(376, outcome_top + 24.0)
	profile_select.size = Vector2(400, 32)
	profile_select.add_theme_font_size_override("font_size", 12)
	profile_select.item_selected.connect(_select_outcome_profile)
	_menu_overlay.add_child(profile_select)

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
