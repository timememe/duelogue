extends Node

## DUELOGUE — КОНТРОЛЛЕР ДЕБАТНОЙ БИТВЫ. Единственный владелец потока партии и async/пейсинга
## (поэтому корутины не накладываются). Держит ядро правил, бота и нарратив; ведёт ход и клинч,
## эмитит события в EventBus. UI и будущие ядра сцены/персонажей только подписываются на шину.
## Самодостаточен и инстанцируем — будущий run/карта-забега сможет им владеть как одной боёвкой.
##
## Клинч идёт через СТЕЙТ-API ядра (begin_clinch/clinch_submit) — тот же путь, что у сим-бота.
## Async только здесь: ходы ИИ с таймером пейсинга, пауза на решении игрока (await _clinch_decided).

const RulesCore := preload("res://duelogue/core/rules/rules_core.gd")
const Ai := preload("res://duelogue/core/ai/ai.gd")
const NamedCards := preload("res://duelogue/core/cards/named_cards.gd")
const DeckLib := preload("res://duelogue/core/cards/deck.gd")
const NarEngine := preload("res://duelogue/core/narrative/narrative_engine.gd")
const ReadingPace := preload("res://duelogue/core/narrative/reading_pace.gd")
const EmotionCore := preload("res://duelogue/core/emotion/emotion_core.gd")
const DefaultReactions := preload("res://duelogue/core/emotion/reaction_decks/volatile_default.gd")
const AudienceCore := preload("res://duelogue/core/audience/audience_core.gd")
const OutcomeProfiles := preload("res://duelogue/core/outcome/outcome_profiles.gd")
const OutcomeEvaluator := preload("res://duelogue/core/outcome/outcome_evaluator.gd")
const PineappleTheme := preload("res://duelogue/core/narrative/themes/theme_pineapple.gd")
const ShawarmaTheme := preload("res://duelogue/core/narrative/themes/theme_shawarma.gd")
const EvangelionTheme := preload("res://duelogue/core/narrative/themes/theme_evangelion.gd")
const THEMES := [PineappleTheme, ShawarmaTheme, EvangelionTheme]
const ACTIVE_THEME := PineappleTheme

const SIDE_YOU := RulesCore.SIDE_YOU
const SIDE_OPP := RulesCore.SIDE_OPP
const TYPE_TEZIS := RulesCore.TYPE_TEZIS
const TYPE_RAZBOR := RulesCore.TYPE_RAZBOR
const TYPE_USTANOVKA := RulesCore.TYPE_USTANOVKA

# --- Константы партии (откалибровано симуляцией) ---
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
const CAPTURE := 1
## Зал-гейт 2A (сим 2026-07-02, zal_core_v0.3 §9.2): крен зала ПРОТИВ тебя поднимает порог
## захвата Кражей — при крене >= GATE_X шатаются чужие рамки с <=2 тезисами, >= GATE_Y — с <=3.
## Фикшен: «фаворит под прицелом» — толпа любит поимку. 2/4 — виднее в живой партии (3/6 — fallback).
const GATE_X := 2
const GATE_Y := 4
## Добыча захвата (реш. игрока, сим 2026-07-02): рамка переходит СО ВСЕМИ стоящими тезисами —
## «забрал действующую рамку — забрал её силу в глазах зала». Сим: баланс не тронут (жирные
## захваты редки — защита выше порога работает), aggro чуть подтянут.
const CAPTURE_LOOT := 1
## Зал-нокаут «унёс зал» (сим §9.4): крен >= ZAL_KO, доживший до начала твоего хода
## ZAL_HOLD раз подряд («счёт судьи»), выигрывает партию. 10/3 — толпа ~16% исходов у smart,
## мета цела; шкала бара сжата до ±ZAL_KO (край бара = черта TKO). На плейтесте.
const ZAL_KO := 10
const ZAL_HOLD := 3
const OPP_STYLE := "smart"  ## fallback, если профиль недоступен; иначе — Profile.settings
## Мягкий нарративный биас стартовой рамки оппонента. На числа боя не влияет.
const OPENING_APPEAL_BY_STYLE := {
	"aggro": "pathos", "wide": "ethos", "tall": "logos",
	"balanced": "", "smart": "logos",
}
## Именные приёмы оппонента (у игрока — из Profile.deck.named, редактор колоды).
const NAMED_OPP := []
const AI_DELAY := 0.55
const CLINCH_STEP_DELAY := 0.45
## Начальная реакция + максимум два звена ответа. Cooldown почти всегда гасит второе звено,
## но жёсткий cap сохраняет безопасность при будущих архетипах с другой разрядкой.
const MAX_REACTION_REPLIES := 2
const LOG_PATH := "res://duelogue/tools/playtest_log.jsonl"
const TX_PATH := "res://duelogue/tools/narrative_transcript.md"

signal _clinch_decided(decision: Dictionary)  ## внутр.: решение игрока в клинче (из play_hand/clinch_pass)

var model: RefCounted
var nar: RefCounted
var ai: RefCounted
var emotion: RefCounted
var audience: RefCounted
var outcome: RefCounted
var match_id := 0
var logging_enabled := true     ## smoke/preview могут выключить файловые побочные эффекты
var _epoch := 0          ## поколение матча; протухшие await прошлой партии выходят по нему
var _theme_data: Dictionary
var _mode := "locked"    ## ввод: locked | opening | move | target | clinch_defend | clinch_attack
var _pending_steals := false
var _pending_hand := -1   ## индекс обычного Разбора, ждущего выбора рамки
var _pending_named := -1  ## индекс ИМЕННОЙ карты руки, ждущей выбора цели (-1 — нет)
var _opp_style := OPP_STYLE  ## стиль оппонента текущего матча (из Profile.settings)
var hint_text := ""      ## подсказка для view (читается на board_changed)
var _gate_told := {}     ## какие уровни зал-гейта уже объяснены голосом зала (1 раз за матч)
var _judge_told := {}    ## последний озвученный «счёт судьи» по сторонам (наррация тиков TKO)
## Момент (сек, Time.get_ticks_msec), когда текущая катсцена реплики/исхода ДОИГРАЕТ
## (ReadingPace.scene_time — единые часы с reaction_scene). _say и _wait_pace держат этот
## рубеж: следующая реплика, автоход или финал никогда не обрывают идущую сцену.
var _say_until := 0.0
## Стартовый суммарный добор обеих сторон — для фазы дебатов (израсходованная доля = таймер).
var _draw0 := 1
var _first_side := SIDE_YOU
var _outcome_profile: Dictionary = {}
var _audience_emotion_delta := 0
var _audience_reaction_seen := false


func _ready() -> void:
	model = RulesCore.new()
	nar = NarEngine.new()
	ai = Ai.new()
	emotion = EmotionCore.new()
	audience = AudienceCore.new()
	outcome = OutcomeEvaluator.new()
	_theme_data = ACTIVE_THEME.data()
	_outcome_profile = OutcomeProfiles.get_profile(_profile_outcome_id())


## Обойма игрока из профиля (autoload Profile; редактор колоды). Fallback — канон констант.
func _player_deck() -> Dictionary:
	var prof := get_node_or_null("/root/Profile")
	if prof != null and prof.deck is Dictionary and not (prof.deck as Dictionary).is_empty():
		return prof.deck
	return {"u": DECK_U, "t": DECK_T, "r": DECK_R, "steals": STEAL_CARDS, "named": []}


func _profile_opp_style() -> String:
	var prof := get_node_or_null("/root/Profile")
	if prof != null:
		return String(prof.settings.get("opp_style", OPP_STYLE))
	return OPP_STYLE


func _profile_outcome_id() -> String:
	var prof := get_node_or_null("/root/Profile")
	if prof != null:
		return String(prof.settings.get("outcome_profile", OutcomeProfiles.DEFAULT_ID))
	return OutcomeProfiles.DEFAULT_ID


# --- состояние для view (read-only) ---

func input_mode() -> String:
	return _mode


## Точная реплика карты в ТЕКУЩЕМ состоянии доски. Нарративный preview прогоняет настоящий
## сборщик и откатывает его state, поэтому немедленный розыгрыш даст ту же строку.
func hand_preview(index: int) -> String:
	var hand: Array = model.sides[SIDE_YOU].hand
	if index < 0 or index >= hand.size():
		return ""
	var card: Dictionary = hand[index]
	if card.has("named"):
		return String(card.get("text", ""))
	match _mode:
		"move":
			if card.type == TYPE_TEZIS and not model.sides[SIDE_YOU].lines.is_empty():
				var line: Dictionary = model.sides[SIDE_YOU].lines[-1]
				return String(nar.preview_statement_exact(SIDE_YOU, card, _used_axes(line),
					"assert", line).text)
			if card.type == TYPE_USTANOVKA:
				var headline := installation_option(index)
				return String(nar.preview_open_exact(SIDE_YOU, headline).text)
			if card.type == TYPE_RAZBOR:
				return "Выберите рамку: точная реплика показана при наведении на цель."
		"target":
			if index == _pending_hand:
				return "Наведите на рамку оппонента, чтобы увидеть точную реплику."
		"clinch_defend", "clinch_attack":
			if model.clinch.is_empty():
				return nar.preview_text(SIDE_YOU, card)
			var line: Dictionary = model.sides[String(model.clinch.defender)].lines[int(model.clinch.idx)]
			if _mode == "clinch_defend" and card.type == TYPE_TEZIS:
				return String(nar.preview_statement_exact(SIDE_YOU, card, _used_axes(line),
					"hold", line).text)
			if _mode == "clinch_attack" and card.type == TYPE_RAZBOR:
				return String(nar.preview_press_exact(SIDE_YOU, _top_stmt(line), card).text)
	return nar.preview_text(SIDE_YOU, card)


## Каждая Установка в руке показывает отдельную ещё не разыгранную рамку. Позиция считается
## среди U-карт, а не по абсолютному индексу руки: после розыгрыша выбранная рамка исчезает,
## и оставшиеся карты продолжают указывать на разные свободные варианты.
func installation_option(index: int) -> Dictionary:
	var hand: Array = model.sides[SIDE_YOU].hand
	if index < 0 or index >= hand.size() or String(hand[index].type) != TYPE_USTANOVKA:
		return {}
	var installation_index := 0
	for i in index:
		if String(hand[i].type) == TYPE_USTANOVKA:
			installation_index += 1
	var options: Array = nar.headline_options(SIDE_YOU)
	if options.is_empty():
		return {}
	return (options[installation_index % options.size()] as Dictionary).duplicate(true)


## Во время выбора цели точная атака живёт на самой рамке: разные цели закономерно дают
## разные реплики. Клик по рамке затем использует ту же конкретную карту руки.
func target_preview(index: int) -> String:
	if _mode != "target" or index < 0 or index >= model.sides[SIDE_OPP].lines.size():
		return ""
	var hand: Array = model.sides[SIDE_YOU].hand
	var hand_index := _pending_hand if _pending_hand >= 0 else _pending_named
	if hand_index < 0 or hand_index >= hand.size():
		return ""
	var card: Dictionary = hand[hand_index]
	if card.has("named") and not bool(card.get("clinch", false)):
		return ""
	var line: Dictionary = model.sides[SIDE_OPP].lines[index]
	var claim := String(line.get("claim", line.get("name", "")))
	return String(nar.preview_refute_exact(SIDE_YOU, claim, _top_stmt(line), card,
		bool(line.get("closed", false)), line).text)

func theme_list() -> Array:
	var out: Array = []
	for t in THEMES:
		var td: Dictionary = t.data()
		out.append({"id": td.id, "topic": td.topic})
	return out

func active_theme_id() -> String:
	return String(_theme_data.get("id", ""))


## Read-only снимок накопительного напряжения для view. Само значение strain не входит в
## счёт; только случившаяся реакция может стать отдельным событием AudienceCore по профилю.
func emotion_state(side: String) -> Dictionary:
	return emotion.state(side) if emotion != null else {}


func audience_state() -> Dictionary:
	if model == null or audience == null:
		return {}
	var config: Dictionary = _outcome_profile.get("audience", {})
	if String(config.get("mode", "derived")) == "derived":
		return {
			"mode": "derived", "lean": int(model.zal()), "raw_lean": int(model.zal()),
			"bias": 0, "lean_cap": int(config.get("lean_cap", RulesCore.ZAL_MAX)),
			"heat": 0, "heat_max": 0, "moves": 0, "reversals": 0,
		}
	return audience.snapshot(int(model.zal_bias))


func outcome_profile_list() -> Array:
	var out: Array = []
	for profile in OutcomeProfiles.all():
		out.append({
			"id": String(profile.id), "label": String(profile.label),
			"description": String(profile.description),
		})
	return out


func active_outcome_profile_id() -> String:
	return String(_outcome_profile.get("id", OutcomeProfiles.DEFAULT_ID))


func active_outcome_profile() -> Dictionary:
	return _outcome_profile.duplicate(true)


## Чистый снимок для тестов, debug-UI и финального окна. Можно вызывать до конца матча.
func outcome_report() -> Dictionary:
	if model == null or outcome == null:
		return {}
	return outcome.evaluate(model, audience_state(), {
		SIDE_YOU: emotion_state(SIDE_YOU), SIDE_OPP: emotion_state(SIDE_OPP),
	}, _outcome_profile)


## Профиль — контракт целого матча, поэтому переключение сразу начинает новую партию.
func select_outcome_profile(profile_id: String) -> void:
	if not OutcomeProfiles.has_profile(profile_id):
		return
	_outcome_profile = OutcomeProfiles.get_profile(profile_id)
	var prof := get_node_or_null("/root/Profile")
	if prof != null:
		prof.set_setting("outcome_profile", profile_id)
	start_match()


## Три смысловые рамки для opening-фазы. Это не карты руки и не расход действия.
func opening_options() -> Array:
	if nar == null or _mode != "opening":
		return []
	return nar.headline_options(SIDE_YOU, 3)

func select_theme(i: int) -> void:
	if i < 0 or i >= THEMES.size():
		return
	_theme_data = THEMES[i].data()
	start_match()


# ------------------------------------------------------------- match ----------

func start_match() -> void:
	_epoch += 1  # инвалидируем незавершённые await прошлого матча
	_mode = "locked"
	_pending_steals = false
	_pending_hand = -1
	_pending_named = -1
	hint_text = ""
	# Разбудить зависший _ask_clinch прошлого матча — выйдет по epoch-guard, не тронув модель.
	_clinch_decided.emit({"act": "pass"})
	_outcome_profile = OutcomeProfiles.get_profile(_profile_outcome_id())
	var links: Dictionary = _outcome_profile.get("links", {})
	var terminal: Dictionary = _outcome_profile.get("terminal", {})
	var audience_config: Dictionary = _outcome_profile.get("audience", {})
	_first_side = SIDE_YOU if randf() < 0.5 else SIDE_OPP
	model.reset(_first_side, DECK_U, DECK_T, DECK_R, HAND, BASE_THESES, KOMI, STEAL_CARDS,
		FORTIFY, CLINCH, CLINCH_FREEZE, CAPTURE, int(links.get("gate_x", 0)),
		int(links.get("gate_y", 0)), 0, CAPTURE_LOOT, int(links.get("crowd_ko", 0)),
		int(links.get("crowd_hold", 1)), bool(terminal.get("board_ko", true)))
	audience.reset(audience_config)
	var independent_audience := String(audience_config.get("mode", "derived")) == "pendulum"
	model.set_external_zal(int(audience.lean), independent_audience,
		int(audience_config.get("lean_cap", RulesCore.ZAL_MAX)))
	_audience_emotion_delta = 0
	_audience_reaction_seen = false
	# Сторона игрока пересобирается из ПРОФИЛЯ (редактор колоды): счётчики + именные
	# заменой. Оппонент остаётся каноном констант (асимметрия — сознательный полигон).
	var d := _player_deck()
	model.sides[SIDE_YOU] = DeckLib.build_side(int(d.u), int(d.t), int(d.r), BASE_THESES, int(d.steals), HAND)
	NamedCards.inject(model.sides[SIDE_YOU], d.get("named", []))
	NamedCards.inject(model.sides[SIDE_OPP], NAMED_OPP)
	_gate_told = {}
	_judge_told = {}
	_opp_style = _profile_opp_style()
	ai.set_style(SIDE_OPP, _opp_style)
	match_id = int(Time.get_unix_time_from_system())
	nar.start(_theme_data, match_id, {"you": "contra", "opp": "pro"})
	emotion.start(DefaultReactions.data(), match_id ^ 0x5EED, [SIDE_YOU, SIDE_OPP])
	_draw0 = maxi(1, _draw_left())
	_mode = "opening"
	hint_text = "Выберите стартовую рамку — она направит первые доводы, но не изменит силу Базы"
	EventBus.match_started.emit({
		"theme": nar.theme.id,
		"first": "you" if _first_side == SIDE_YOU else "opp",
		"match_id": match_id,
		"outcome_profile": active_outcome_profile(),
	})
	EventBus.audience_changed.emit(audience_state())
	_emit({
		"ev": "start", "ts": match_id,
		"first": "you" if _first_side == SIDE_YOU else "opp",
		"ruleset": {"base": BASE_THESES, "steal_cards": int(d.steals), "deck": "U%d T%d R%d" % [int(d.u), int(d.t), int(d.r)], "named": ", ".join(d.get("named", [])), "opp_style": _opp_style, "freeze": CLINCH_FREEZE, "gate": "%d/%d" % [int(links.get("gate_x", 0)), int(links.get("gate_y", 0))], "loot": CAPTURE_LOOT, "zal_ko": "%d/%d" % [int(links.get("crowd_ko", 0)), int(links.get("crowd_hold", 1))], "outcome_profile": active_outcome_profile_id()},
		"theme": nar.theme.id,
	})
	_tx_header(_first_side)
	_narrate("ТЕМА ДЕБАТОВ: «%s».  Слово первым: %s." % [nar.topic(), ("вы" if _first_side == SIDE_YOU else "оппонент")])
	_changed()


func restart() -> void:
	start_match()


# --------------------------------------------------------------- flow ---------

func _run_until_player() -> void:
	_mode = "locked"
	var my_epoch := _epoch
	while true:
		if my_epoch != _epoch:
			return
		if model.game_over:
			await _show_end(); _changed(); return
		var st: String = model.begin_turn(model.current)
		_narrate_judge_count()
		if st == "ko" or st == "crowd" or st == "end" or st == "over":
			await _show_end(); _changed(); return
		if st == "redeploy":
			var line: Dictionary = model.sides[model.current].lines[-1]
			var claim := _claim_of(model.current, line)
			await _say(model.current, nar.redeploy_line(model.current, claim), "t%d %s redeploy (страховка)" % [model.turn_count, model.current], TYPE_USTANOVKA, false, nar.last_mood())
			if my_epoch != _epoch:
				return
			var rev := {"ev": "redeploy", "side": model.current}
			rev.merge(_econ()); _emit(rev)
			model.advance(); _changed(); continue
		if st == "pass":
			await _say(model.current, nar.pass_line(model.current), "t%d %s pass" % [model.turn_count, model.current], "", false, nar.last_mood())
			if my_epoch != _epoch:
				return
			var pev := {"ev": "pass", "side": model.current}
			pev.merge(_econ()); _emit(pev)
			model.advance(); _changed(); continue
		# st == "ok"
		EventBus.turn_changed.emit(model.current)
		if model.current == SIDE_YOU:
			_mode = "move"
			hint_text = ""
			_changed()
			return
		# --- ход оппонента ---
		_changed()
		await _wait_pace(AI_DELAY)
		if my_epoch != _epoch:
			return
		if model.game_over:
			continue
		var act: Dictionary = ai.pick(model, SIDE_OPP, _opp_style)
		if act.is_empty():
			model.sides[SIDE_OPP].passed = true
			model.advance(); continue
		var named_i := int(act.get("named_index", -1))
		if named_i >= 0 and not bool(act.get("named_clinch", false)):
			# Именной приём оппонента без клинча — выстрел через play_named.
			var ncard: Dictionary = model.sides[SIDE_OPP].hand[named_i].duplicate()
			var ninfo: Dictionary = model.play_named(SIDE_OPP, named_i, int(act.get("target", -1)))
			if ninfo.is_empty():
				var info0: Dictionary = model.play_action(SIDE_OPP, act.type, int(act.get("target", -1)))
				await _log_action(info0)
			else:
				await _log_named(SIDE_OPP, ncard, ninfo)
			if my_epoch != _epoch:
				return
		elif act.type == TYPE_RAZBOR:
			var tgt := int(act.get("target", -1))
			# Smart-бот холдит Кражи: жжёт только под досягаемый захват (ai.atk_prefer_steal).
			# named_i — клинч именной картой (сократик).
			await _run_clinch(SIDE_OPP, SIDE_YOU, tgt, ai.atk_prefer_steal(model, SIDE_OPP, SIDE_YOU, tgt), named_i)
			if my_epoch != _epoch:
				return
		else:
			var info: Dictionary = model.play_action(SIDE_OPP, act.type)
			await _log_action(info)
			if my_epoch != _epoch:
				return
		model.advance()


# --- интенты игрока (зовёт view) ---

## Opening-фаза: выбрать СМЫСЛ бесплатной стартовой Базы. Карта, ход и состав колоды
## не расходуются; после фиксации обе стороны произносят рамки в порядке первого слова.
func choose_opening(headline_id: String) -> void:
	if _mode != "opening":
		return
	var yours: Dictionary = nar.select_headline(SIDE_YOU, headline_id)
	if yours.is_empty():
		return
	var opp_appeal := String(OPENING_APPEAL_BY_STYLE.get(_opp_style, ""))
	var theirs: Dictionary = nar.auto_headline(SIDE_OPP, opp_appeal)
	if theirs.is_empty():
		return
	_bind_claim(model.sides[SIDE_YOU].lines[0], yours)
	_bind_claim(model.sides[SIDE_OPP].lines[0], theirs)
	_mode = "locked"
	hint_text = ""
	for side in [SIDE_YOU, SIDE_OPP]:
		var line: Dictionary = model.sides[side].lines[0]
		var ev := {"ev": "opening", "side": side, "claim_id": String(line.get("claim_id", "")),
			"claim": String(line.get("claim", "")), "preferred_axes": line.get("preferred_axes", [])}
		ev.merge(_econ())
		_emit(ev)
	_changed()
	_present_openings()


func _present_openings() -> void:
	var my_epoch := _epoch
	for side in [_first_side, model.other(_first_side)]:
		var line: Dictionary = model.sides[side].lines[0]
		var claim := _claim_of(side, line)
		await _say(side, nar.open_line(side, claim), "start %s база[%s]" % [side, String(line.get("claim_id", ""))],
			TYPE_USTANOVKA, false, nar.last_mood())
		if my_epoch != _epoch:
			return
	_run_until_player()


func play_hand(index: int) -> void:
	if model.game_over:
		return
	var hand: Array = model.sides[SIDE_YOU].hand
	if index < 0 or index >= hand.size():
		return
	var card: Dictionary = hand[index]
	# Реактивный выбор в клинче.
	if _mode == "clinch_defend" or _mode == "clinch_attack":
		var want := TYPE_TEZIS if _mode == "clinch_defend" else TYPE_RAZBOR
		if card.type == want:
			_clinch_decided.emit({"act": "play", "steals": bool(card.get("steals", false)),
				"hand_index": index})
		return
	if _mode != "move":
		return
	# Именной приём: свой маршрут (точный индекс карты; часть приёмов бьёт без клинча).
	if card.has("named"):
		if bool(card.get("targeted", false)):
			if model.sides[SIDE_OPP].lines.is_empty():
				return
			_pending_named = index
			_pending_steals = bool(card.get("steals", false))
			_mode = "target"
			hint_text = "«%s»: кликни рамку оппонента — цель приёма" % String(card.name)
			_changed()
		else:
			_play_named_move(index, -1)
		return
	match card.type:
		TYPE_TEZIS, TYPE_USTANOVKA:
			var my_epoch := _epoch
			# Запоминаем смысл ДО удаления карты и добора замены: после мутации руки её
			# порядковый номер среди Установок уже мог бы указывать на другой headline.
			var installation := installation_option(index) if card.type == TYPE_USTANOVKA else {}
			_mode = "locked"  # ввод закрыт, пока реплика хода в очереди презентации
			var info: Dictionary = model.play_action(SIDE_YOU, card.type, -1, index)
			if card.type == TYPE_USTANOVKA and not installation.is_empty():
				var selected: Dictionary = nar.select_headline(SIDE_YOU, String(installation.id))
				if not selected.is_empty():
					_bind_claim(model.sides[SIDE_YOU].lines[-1], selected)
			await _log_action(info)
			if my_epoch != _epoch:
				return
			model.advance()
			_run_until_player()
		TYPE_RAZBOR:
			if model.sides[SIDE_OPP].lines.is_empty():
				return
			_pending_steals = bool(card.get("steals", false))
			_pending_hand = index
			_mode = "target"
			hint_text = "%s: наведи на рамку, чтобы увидеть точную реплику; кликни для атаки" % ("КРАЖА" if _pending_steals else "РАЗБОР")
			# Кража по шатающейся рамке (тезисов <= твоего порога захвата) берёт её целиком.
			if _pending_steals:
				var th: int = model.capture_threshold(SIDE_YOU)
				for ln in model.sides[SIDE_OPP].lines:
					if int(ln.theses) <= th:
						hint_text += "  ·  шатающуюся (≤%d тез.) заберёте ЦЕЛИКОМ" % th
						break
			_changed()


func choose_target(index: int) -> void:
	if _mode != "target":
		return
	var my_epoch := _epoch
	_mode = "locked"
	hint_text = ""
	# Цель для именного приёма: клинчевый (сократик) идёт в ралли ИМЕННО этой картой,
	# остальные — выстрелом через play_named.
	if _pending_named >= 0:
		var ni := _pending_named
		_pending_named = -1
		var hand: Array = model.sides[SIDE_YOU].hand
		if ni < hand.size() and bool(hand[ni].get("clinch", false)):
			await _run_clinch(SIDE_YOU, SIDE_OPP, index, _pending_steals, ni)
			if my_epoch != _epoch:
				return
			model.advance()
			_run_until_player()
		else:
			_play_named_move(ni, index)
		return
	var hand_index := _pending_hand
	_pending_hand = -1
	await _run_clinch(SIDE_YOU, SIDE_OPP, index, _pending_steals, hand_index)
	if my_epoch != _epoch:
		return
	model.advance()
	_run_until_player()


func cancel_targeting() -> void:
	if _mode != "target":
		return
	_mode = "move"
	_pending_hand = -1
	_pending_named = -1
	hint_text = ""
	_changed()


func clinch_pass() -> void:
	if _mode == "clinch_defend" or _mode == "clinch_attack":
		_clinch_decided.emit({"act": "pass"})


## Интерактивная воля клинча через стейт-API ядра. attacker инициирует разбором по defender[idx].
## named_index >= 0 — клинч открывается именно этой картой руки (именной приём, напр. сократик).
func _run_clinch(attacker: String, defender: String, idx: int, prefer_steal: bool, named_index: int = -1) -> void:
	_mode = "locked"
	var my_epoch := _epoch
	if idx < 0 or idx >= model.sides[defender].lines.size():
		return
	_begin_audience_scene()
	var ctx: Dictionary = model.begin_clinch(attacker, defender, idx, prefer_steal, named_index)
	if ctx.is_empty():
		return
	var initc: Dictionary = ctx.card
	var init_steals: bool = initc.get("steals", false)
	var line: Dictionary = model.sides[defender].lines[idx]
	var target_claim := _claim_of(defender, line)
	var is_callback: bool = ctx.is_callback
	var atk_word := "кража" if init_steals else "разбор"
	var cb := "←старая" if is_callback else ""
	await _say(attacker, nar.refute_line(attacker, target_claim, _top_stmt(line), initc, is_callback, line),
		"t%d %s clinch→%s[%d] %s%s" % [model.turn_count, attacker, defender, idx, atk_word, cb],
		TYPE_RAZBOR, init_steals, nar.last_mood())
	if my_epoch != _epoch:
		return
	EventBus.clinch_started.emit(attacker, defender, idx)
	_changed()
	if attacker == SIDE_OPP:
		await _wait_pace(CLINCH_STEP_DELAY)
		if my_epoch != _epoch:
			return

	var atk_left_at_finish := -1
	var resolved: Dictionary = {}
	var guard := 0
	while model.clinch_active() and guard < 200:
		guard += 1
		var side: String = model.clinch_pending_side()
		var is_defend := side == defender
		# Сторона не может действовать → её пас закрывает клинч.
		if not model.clinch_can_act(side):
			if not is_defend and attacker == SIDE_YOU:
				hint_text = "Рамку отстояли — добить нечем (нет карт атаки в руке)"
				_changed()
				await _wait_pace(CLINCH_STEP_DELAY)
				if my_epoch != _epoch:
					return
			if not is_defend:
				atk_left_at_finish = _count_razbor(attacker)
			resolved = model.clinch_submit("pass")
			break
		# Решение текущей стороны.
		var decision := "pass"
		var pref := true
		var chosen_hand_index := -1
		if side == SIDE_YOU:
			var d: Dictionary = await _ask_clinch("defend" if is_defend else "attack")
			if my_epoch != _epoch:
				return
			decision = String(d.get("act", "pass"))
			pref = bool(d.get("steals", false))
			chosen_hand_index = int(d.get("hand_index", -1))
		else:
			var will: bool = ai.def_will_clinch(model, side, line) if is_defend else ai.atk_will_clinch(model, side, line)
			decision = "play" if will else "pass"
			if not is_defend:
				pref = ai.atk_prefer_steal(model, side, defender, idx)
			await _wait_pace(CLINCH_STEP_DELAY)
			if my_epoch != _epoch:
				return
		if not is_defend:
			atk_left_at_finish = _count_razbor(attacker)
		var res: Dictionary = model.clinch_submit(decision, pref, chosen_hand_index)
		match String(res.get("event", "")):
			"hold":
				var dc: Dictionary = res.card
				var stmt: Dictionary = nar.make_statement(defender, dc, _used_axes(line), "hold", line)
				_push_stmt(line, stmt)
				await _say(defender, stmt.text, "    hold %s [%s]" % [defender, stmt.axis], TYPE_TEZIS, false, nar.last_mood())
				if my_epoch != _epoch:
					return
				_changed()
			"press":
				var ac: Dictionary = res.card
				await _say(attacker, nar.press_line(attacker, _top_stmt(line), ac),
					"    press %s %s" % [attacker, ("кража" if ac.get("steals", false) else "разбор")],
					TYPE_RAZBOR, bool(ac.get("steals", false)), nar.last_mood())
				if my_epoch != _epoch:
					return
				_changed()
				# Полная пара «защита → новый нажим» означает, что клинч затянулся. Само
				# продолжение нагревает ОБЕ стороны и может вызвать срыв прямо внутри ралли.
				await _emotion_clinch_round(attacker, defender, target_claim)
				if my_epoch != _epoch:
					return
			"resolved":
				resolved = res
				break

	# Клинч закрыт. Последняя реплика ралли доигрывает ДО вердикта зала и вспышки исхода —
	# нокаут/захват больше не съедают финальное высказывание.
	await _wait_pace(0.0)
	if my_epoch != _epoch:
		return
	var info: Dictionary = resolved.get("info", {"side": attacker, "type": TYPE_RAZBOR})
	var t_added := int(resolved.get("t_added", 0))
	var r_count := int(resolved.get("r_count", 1))
	var landed := bool(resolved.get("landed", r_count > t_added))
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
	EventBus.clinch_resolved.emit(ev)
	if landed:
		# Рамка пробита — «яркий исход» для мини-сцены реакции (спидлайны на защитнике).
		EventBus.impact.emit(defender, "removed" if info.get("removed", false) else "landed")
		_say_until = _now() + ReadingPace.impact_time()  # вспышку тоже не обрываем
	_changed()
	# Эмоция читает уже ЗАКРЫТЫЙ исход клинча и не вмешивается в его автомат. Реагирует
	# проигравшая сторона: защитник после пробития или атакующий после неудачного дожима.
	var strained_side := defender if landed else attacker
	var stimulus := "attack_stalled"
	if landed:
		stimulus = "captured" if info.get("captured", false) else \
			("frame_lost" if info.get("removed", false) else "argument_lost")
	var intensity := 1
	if info.get("removed", false):
		intensity += 1
	if info.get("captured", false):
		intensity += 1
	await _emotion_event(strained_side, stimulus, mini(3, intensity), {"target": target_claim})
	var public_side := attacker if landed else defender
	var spectacle := 2 if info.get("removed", false) or info.get("captured", false) \
		or t_added > 0 or r_count > 1 or _audience_reaction_seen else 1
	_settle_audience_scene(public_side, spectacle)


func _ask_clinch(mode: String) -> Dictionary:
	_mode = "clinch_" + mode
	if mode == "defend":
		hint_text = "КЛИНЧ! Бьют вашу рамку — сыграйте ТЕЗИС в защиту, или «Пропустить»"
	else:
		hint_text = "КЛИНЧ! Добейте РАЗБОРОМ или КРАЖЕЙ, или «Остановиться»"
	_changed()
	var d: Dictionary = await _clinch_decided
	_mode = "locked"
	hint_text = ""
	_changed()
	return d


# --------------------------------------------------------------- end ----------

func _show_end() -> void:
	_mode = "locked"
	# Финал ждёт хвост презентации: последняя реплика/вспышка доигрывает, потом вердикт.
	var my_epoch := _epoch
	await _wait_pace(0.0)
	if my_epoch != _epoch:
		return
	var report: Dictionary = outcome_report()
	var winner_s := String(report.get("winner", "draw"))
	var reason := String(report.get("reason", "draw"))
	model.winner = winner_s if winner_s in [SIDE_YOU, SIDE_OPP] else ""
	model.end_reason = reason
	var verdict: String
	if String(report.get("mode", "")) == "legacy":
		verdict = nar.verdict_text(
			("you" if model.winner == SIDE_YOU else ("opp" if model.winner == SIDE_OPP else "")),
			reason, nar.stance_label(SIDE_YOU), nar.stance_label(SIDE_OPP))
	else:
		verdict = outcome.verdict_text(report, nar.stance_label(SIDE_YOU),
			nar.stance_label(SIDE_OPP))
	report["verdict"] = verdict
	var ev := {"ev": "end", "winner": winner_s, "reason": reason,
		"outcome_profile": active_outcome_profile_id(), "report": report}
	ev.merge(_econ())
	_emit(ev)
	_narrate("⚖ " + verdict, "END %s winner=%s B=%+d Lean=%+d Heat=%d profile=%s" % [
		reason, winner_s, int((report.board as Dictionary).score),
		int((report.audience as Dictionary).lean), int((report.audience as Dictionary).heat),
		active_outcome_profile_id()])
	EventBus.match_reported.emit(report)
	EventBus.match_ended.emit(winner_s, reason, verdict)


# --------------------------------------------------------------- narrative ----

func _who(side: String) -> String:
	return "Вы" if side == SIDE_YOU else "Оппонент"


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


## Сколько ещё доигрывает текущая катсцена (0 — сцена закончилась).
func _pace_left() -> float:
	return maxf(0.0, _say_until - _now())


## Реплика стороны: в шину (для UI/персонажей) + в файловую стенограмму. card_type/steals —
## какой картой сказано; mood — стейт-реакция говорящего (nar.last_mood(), контракт §16) —
## по нему character_core выбирает портрет/позу; "" — фолбэк по типу карты.
## ПОСЛЕДОВАТЕЛЬНАЯ: (1) доска обновляется ПЕРВОЙ (ход виден до крупного плана — сцена
## стартует после BOARD_BEAT в character_core), (2) хвост предыдущей сцены ДОЖИДАЕМСЯ —
## реплики никогда не убивают друг друга. Вызывать строго с await.
func _say(side: String, text: String, tag: String = "", card_type: String = "", steals: bool = false,
	mood: String = "", extra_meta: Dictionary = {}) -> void:
	var my_epoch := _epoch
	_changed()  # ход лёг на доску — игрок видит его ДО катсцены
	var left := _pace_left()
	if left > 0.0:
		await get_tree().create_timer(left).timeout
		if my_epoch != _epoch:
			return
	var meta := {
		"tag": tag, "stance": nar.stance_label(side),
		"card_type": card_type, "steals": steals, "mood": mood,
	}
	meta.merge(extra_meta, true)
	EventBus.utterance.emit(side, text, meta)
	_tx(tag, "%s (%s): %s" % [_who(side), nar.stance_label(side), text])
	_say_until = _now() + ReadingPace.scene_time(text)


## Пейсинг перед следующим автоматическим действием: не короче base_delay И не раньше,
## чем доиграет текущая катсцена (единые часы ReadingPace — сцены не обрываются).
func _wait_pace(base_delay: float) -> void:
	await get_tree().create_timer(maxf(base_delay, _pace_left())).timeout


## Авторская наррация (голос зала / ремарки).
func _narrate(text: String, tag: String = "") -> void:
	EventBus.narration.emit(text, {"tag": tag})
	_tx(tag, "· " + text)


## Один stimulus → рост шкалы → возможно, одна непроизвольная реплика и ограниченный ответ
## второй шкалы. Внутри цепочки model не мутируется; после всей сцены контроллер одним
## коммитом может передать её публичную валентность независимому AudienceCore.
func _emotion_event(side: String, stimulus: String, intensity: int,
	context: Dictionary = {}) -> Dictionary:
	if emotion == null:
		return {}
	var result: Dictionary = emotion.observe(side, stimulus, intensity, context)
	if result.is_empty():
		return result
	await _resolve_emotion_result(result, context, 0, "", "event")
	return result


func _resolve_emotion_result(result: Dictionary, context: Dictionary, chain_depth: int,
	source_side: String, link_kind: String) -> void:
	var my_epoch := _epoch
	var side := String(result.side)
	var stimulus := String(result.stimulus)
	var reaction: Dictionary = result.get("reaction", {})
	var ev := {
		"ev": "emotion", "side": side, "stimulus": stimulus,
		"before": int(result.before), "peak": int(result.peak), "after": int(result.after),
		"delta": int(result.delta), "chance": float(result.chance),
		"roll": float(result.roll), "reaction": String(reaction.get("id", "")),
		"reaction_title": String(reaction.get("title", "")),
		"reaction_draw_left": int(result.draw_left),
		"link_kind": link_kind, "source_side": source_side, "chain_depth": chain_depth,
	}
	ev.merge(_econ())
	_emit(ev)
	EventBus.emotion_changed.emit(side, emotion.state(side))
	_changed()
	if reaction.is_empty():
		return
	_record_audience_reaction(side, String(reaction.get("id", "")))
	EventBus.emotion_reacted.emit(side, reaction)
	await _say(side, String(reaction.text), "    reaction %s %s %d→%d→%d" % [
		side, String(reaction.id), int(result.before), int(result.peak), int(result.after)],
		"", false, String(reaction.get("mood", "burst")), {
			"reaction": true,
			"reaction_kind": "counter_burst" if chain_depth > 0 else "burst",
			"reaction_id": String(reaction.id),
			"reaction_title": String(reaction.title),
			"reaction_source": source_side,
			"reaction_chain_depth": chain_depth,
			"strain": int(result.after),
		})
	if my_epoch != _epoch:
		return
	if chain_depth < MAX_REACTION_REPLIES:
		await _answer_emotional_reaction(side, context, chain_depth + 1)


func _answer_emotional_reaction(source_side: String, context: Dictionary,
	chain_depth: int) -> void:
	var responder: String = String(model.other(source_side))
	var answer: Dictionary = emotion.answer_reaction(responder, context)
	if answer.is_empty():
		return
	var kind := String(answer.get("kind", "none"))
	EventBus.emotion_linked.emit(source_side, responder, answer)
	if kind == "parry":
		var parry: Dictionary = answer.get("parry", {})
		_record_audience_parry(responder)
		var ev := {
			"ev": "emotion_link", "kind": "parry", "source_side": source_side,
			"side": responder, "before": int(answer.before), "after": int(answer.after),
			"parry": String(parry.get("id", "")), "chain_depth": chain_depth,
		}
		ev.merge(_econ())
		_emit(ev)
		await _say(responder, String(parry.text), "    parry %s→%s %s" % [
			source_side, responder, String(parry.id)], "", false,
			String(parry.get("mood", "swagger")), {
				"reaction_response": true,
				"reaction_kind": "parry",
				"reaction_id": String(parry.id),
				"reaction_title": String(parry.title),
				"reaction_source": source_side,
				"reaction_chain_depth": chain_depth,
			})
		return  # спокойная парировка закрывает эмоциональный обмен
	# absorb остаётся немым; trigger содержит полноценную карту и продолжит цепь.
	await _resolve_emotion_result(answer, context, chain_depth, source_side, kind)


## Один завершённый раунд затянувшегося клинча: обоим +1. Последовательный вызов сохраняет
## читаемость двух возможных реакций и не создаёт между ними механической связи/каскада.
func _emotion_clinch_round(attacker: String, defender: String, target: String) -> void:
	await _emotion_event(attacker, "clinch_pressure", 1, {"target": target})
	await _emotion_event(defender, "clinch_pressure", 1, {"target": target})


# ------------------------------------------------------ audience / outcome ---

func _begin_audience_scene() -> void:
	_audience_emotion_delta = 0
	_audience_reaction_seen = false


func _record_audience_reaction(side: String, reaction_id: String) -> void:
	if audience == null:
		return
	_audience_reaction_seen = true
	_audience_emotion_delta += int(audience.signed_reaction(side, reaction_id))


func _record_audience_parry(side: String) -> void:
	if audience == null:
		return
	_audience_reaction_seen = true
	_audience_emotion_delta += int(audience.signed_parry(side))


func _settle_audience_scene(public_side: String, spectacle: int) -> void:
	if audience == null:
		return
	audience.resolve_scene(public_side, spectacle, _audience_emotion_delta,
		_audience_reaction_seen)
	_sync_audience()
	_begin_audience_scene()


func _audience_quiet() -> void:
	if audience == null:
		return
	audience.observe_quiet()
	_sync_audience()


func _sync_audience() -> void:
	var config: Dictionary = _outcome_profile.get("audience", {})
	if model != null and String(config.get("mode", "derived")) == "pendulum":
		model.set_external_zal(int(audience.lean), true,
			int(config.get("lean_cap", RulesCore.ZAL_MAX)))
	EventBus.audience_changed.emit(audience_state())
	_changed()


func _changed() -> void:
	# Накал для нарратива (§14.5/14.7): крен зала + фаза (израсходованный добор = таймер).
	if model != null and nar != null and not nar.theme.is_empty():
		nar.update_heat(model.zal(), 1.0 - float(_draw_left()) / float(_draw0))
	_maybe_narrate_gate()
	EventBus.board_changed.emit()


func _draw_left() -> int:
	var n := 0
	for side in [SIDE_YOU, SIDE_OPP]:
		n += (model.sides[side].draw as Array).size()
	return n


## «Счёт судьи» зал-нокаута: крен у черты дожил до начала хода лидера — тик счёта (1/3, 2/3…).
## Озвучиваем каждый тик (событие редкое и драматичное) и сброс счёта (спасение поимкой).
func _narrate_judge_count() -> void:
	if model.zal_ko <= 0:
		return
	for side in [SIDE_YOU, SIDE_OPP]:
		var n := int(model.crowd_streak.get(side, 0))
		var last := int(_judge_told.get(side, 0))
		if n > 0 and n != last:
			if n >= model.zal_hold:
				break  # финальный тик озвучит вердикт (_show_end)
			var who := "ВАС" if side == SIDE_YOU else "ОППОНЕНТА"
			var warn := "" if side == SIDE_YOU else " Верните зал — поимка качнёт стрелку!"
			_narrate("⚖ ЗАЛ СКАНДИРУЕТ за %s — счёт судьи: %d/%d.%s" % [who, n, model.zal_hold, warn],
				"judge %s %d/%d" % [side, n, model.zal_hold])
		elif n == 0 and last > 0:
			_narrate("⚖ Стрелка вернулась из-за черты — счёт судьи сброшен.", "judge %s reset" % side)
		_judge_told[side] = n


## Обучение зал-гейту голосом зала: ПЕРВЫЙ раз за матч, когда крен открывает стороне
## уровень захвата 2/3, — объясняем правило ремаркой. Постоянная индикация — на доске
## (шатающиеся рамки) и на баре (риски порогов); это только событие-телеграф.
func _maybe_narrate_gate() -> void:
	if model == null or model.gate_x <= 0 or model.game_over:
		return
	for side in [SIDE_YOU, SIDE_OPP]:
		var lvl: int = model.capture_threshold(side)   # сила захвата side (он — отстающий)
		if lvl < 2:
			continue
		var key := "%s%d" % [side, lvl]
		if _gate_told.has(key):
			continue
		_gate_told[key] = true
		var txt: String
		if side == SIDE_YOU:
			txt = ("Зал закормлен успехом оппонента — его рамки с %d тезисами и тоньше ШАТАЮТСЯ: ваша Кража заберёт такую целиком." % lvl) \
				if lvl == 2 else \
				("Зал жаждет поимки фаворита — даже рамки оппонента с %d тезисами шатаются под вашей Кражей!" % lvl)
		else:
			txt = ("Вы — фаворит зала, а фаворит под прицелом: ваши рамки с %d тезисами и тоньше ШАТАЮТСЯ — Кража оппонента может забрать их целиком." % lvl) \
				if lvl == 2 else \
				("Зал пресыщен вами — шатаются уже и ваши рамки с %d тезисами. Толпа любит поимку!" % lvl)
		_narrate("⚖ " + txt, "gate %s→%d" % [side, lvl])


## Ход без клинча (Тезис на свою рамку / Установка). Зовётся для обеих сторон.
## Async: реплика хода идёт через последовательный _say — вызывать с await.
func _log_action(info: Dictionary) -> void:
	if info.is_empty():
		return
	var ev := {"ev": "move", "side": info.side, "type": info.type, "name": info.get("name", "")}
	ev.merge(_econ())
	_emit(ev)
	var side: String = info.side
	var card := {"type": info.type, "name": info.get("name", ""), "steals": false}
	match info.type:
		TYPE_TEZIS:
			var line: Dictionary = model.sides[side].lines[-1]
			_claim_of(side, line)  # рамке нужна headline-позиция (топик)
			var stmt: Dictionary = nar.make_statement(side, card, _used_axes(line), "assert", line)
			_push_stmt(line, stmt)
			await _say(side, stmt.text, "t%d %s тезис[%s/%s]" % [model.turn_count, side, stmt.device, stmt.axis], TYPE_TEZIS, false, nar.last_mood())
		TYPE_USTANOVKA:
			var line: Dictionary = model.sides[side].lines[-1]
			var claim := _claim_of(side, line)
			await _say(side, nar.open_line(side, claim, "open"), "t%d %s установка→рамка" % [model.turn_count, side], TYPE_USTANOVKA, false, nar.last_mood())
		TYPE_RAZBOR:
			pass  # атаки идут через клинч
	if String(info.type) in [TYPE_TEZIS, TYPE_USTANOVKA]:
		_audience_quiet()


## Розыгрыш ИМЕННОГО приёма игроком (не-клинчевые твисты; сократик идёт через _run_clinch).
func _play_named_move(hand_index: int, target: int) -> void:
	var my_epoch := _epoch
	_mode = "locked"
	hint_text = ""
	var hand: Array = model.sides[SIDE_YOU].hand
	if hand_index < 0 or hand_index >= hand.size():
		_mode = "move"
		return
	var card: Dictionary = hand[hand_index].duplicate()
	var info: Dictionary = model.play_named(SIDE_YOU, hand_index, target)
	if info.is_empty():
		_mode = "move"
		_changed()
		return
	await _log_named(SIDE_YOU, card, info)
	if my_epoch != _epoch:
		return
	model.advance()
	_run_until_player()


## Наррация и лог именного хода. Реплики приёмов пока служебные (голос ремарки, не темы) —
## тематические реплики твистов появятся отдельной итерацией нарратива.
func _log_named(side: String, card: Dictionary, info: Dictionary) -> void:
	_begin_audience_scene()
	var ev := {"ev": "named", "side": side, "id": String(info.get("named", "")),
		"name": String(card.get("name", "")), "removed": info.get("removed", false),
		"captured": info.get("captured", false)}
	ev.merge(_econ())
	_emit(ev)
	var fx := ""
	match String(info.get("named", "")):
		"gish_gallop":
			fx = "лавина доводов накрывает сразу две рамки — отвечать некогда"
		"ad_hominem":
			fx = "удар ниже пояса: рамка трещит, но зал морщится (крен −1 на вас)"
		"strawman":
			fx = ("чучело сработало — рамка выхвачена целиком (добыча похудела на тезис)"
				if info.get("captured", false) else "подмена тезиса — и он уже в чужих руках")
		"burden_shift":
			fx = "бремя доказательства переброшено — эту рамку теперь не выхватить"
		"axiom":
			fx = "постулат поставлен: два тезиса разом, но обсуждению не подлежит"
		_:
			fx = "приём разыгран"
	await _say(side, "«%s» — %s." % [String(card.get("name", "")), fx],
		"t%d %s ИМЕННОЙ %s" % [model.turn_count, side, String(info.get("named", ""))],
		String(card.get("type", "")), bool(card.get("steals", false)), "")
	# Грязный/присваивающий выстрел может вызвать реакцию цели, но сама реакция пока не
	# меняет эффект именной карты. Остальные именные строители эмоциональное ядро не трогают.
	var stimulus := ""
	var intensity := 0
	match String(info.get("named", "")):
		"ad_hominem":
			stimulus = "dirty_hit"
			intensity = 2
		"gish_gallop":
			stimulus = "frame_lost" if info.get("removed", false) else "argument_lost"
			intensity = 2 if info.get("removed", false) else 1
		"strawman":
			stimulus = "captured" if info.get("captured", false) else "argument_lost"
			intensity = 3 if info.get("captured", false) else 1
	if stimulus != "":
		await _emotion_event(model.other(side), stimulus, intensity, {
			"target": String(info.get("target_name", "эта позиция")),
		})
	var spectacular := bool(info.get("removed", false)) or bool(info.get("captured", false)) \
		or _audience_reaction_seen
	_settle_audience_scene(side if spectacular else "", 2 if spectacular else 0)


func _count_razbor(side: String) -> int:
	var n := 0
	for c in model.sides[side].hand:
		if c.type == TYPE_RAZBOR:
			n += 1
	return n


## Приколоть выбранную смысловую позицию и её мягкий биас осей к механической рамке.
func _bind_claim(line: Dictionary, headline: Dictionary) -> void:
	line["claim_id"] = String(headline.get("id", ""))
	line["claim"] = String(headline.get("text", ""))
	line["preferred_axes"] = (headline.get("preferred_axes", []) as Array).duplicate()


## Ленивое назначение claim обычной Установке после opening-фазы. Топик приколот к рамке.
func _claim_of(side: String, line: Dictionary) -> String:
	var c := String(line.get("claim", ""))
	if c == "":
		var headline: Dictionary = nar.next_headline_data(side)
		_bind_claim(line, headline)
		c = String(line.get("claim", ""))
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


# --- общий транскрипт (нарратив ↔ действия в одном файле, в порядке исполнения) ---

func _tx_header(first: String) -> void:
	_tx_write("")
	_tx_write("=".repeat(72))
	_tx_write("МАТЧ %d · тема «%s» · вы=%s · опп=%s · первым=%s · %s" % [
		match_id, nar.topic(), nar.stance_label(SIDE_YOU), nar.stance_label(SIDE_OPP),
		("вы" if first == SIDE_YOU else "оппонент"), Time.get_datetime_string_from_system(true, true)])
	_tx_write("-".repeat(72))


func _tx(tag: String, body: String) -> void:
	if tag == "":
		_tx_write(body)
	else:
		_tx_write("%-30s %s" % ["[" + tag + "]", body])


func _tx_write(s: String) -> void:
	if not logging_enabled:
		return
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


# --- запись катки (JSONL) ---

func _econ() -> Dictionary:
	var y: Dictionary = model.sides[SIDE_YOU]
	var o: Dictionary = model.sides[SIDE_OPP]
	return {
		"turn": model.turn_count,
		"you_frames": model.score(SIDE_YOU),
		"opp_frames": model.score(SIDE_OPP),
		"zal": model.zal(),
		"you_hand": y.hand.size(), "opp_hand": o.hand.size(),
		"you_deck": y.draw.size(), "opp_deck": o.draw.size(),
	}


func _emit(d: Dictionary) -> void:
	if not logging_enabled:
		return
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
