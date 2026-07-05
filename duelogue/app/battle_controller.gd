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
const NarEngine := preload("res://duelogue/core/narrative/narrative_engine.gd")
const ReadingPace := preload("res://duelogue/core/narrative/reading_pace.gd")
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
const OPP_STYLE := "smart"
const AI_DELAY := 0.55
const CLINCH_STEP_DELAY := 0.45
const LOG_PATH := "res://duelogue/tools/playtest_log.jsonl"
const TX_PATH := "res://duelogue/tools/narrative_transcript.md"

signal _clinch_decided(decision: Dictionary)  ## внутр.: решение игрока в клинче (из play_hand/clinch_pass)

var model: RefCounted
var nar: RefCounted
var ai: RefCounted
var match_id := 0
var _epoch := 0          ## поколение матча; протухшие await прошлой партии выходят по нему
var _theme_data: Dictionary
var _mode := "locked"    ## ввод: locked | move | target | clinch_defend | clinch_attack
var _pending_steals := false
var hint_text := ""      ## подсказка для view (читается на board_changed)
var _gate_told := {}     ## какие уровни зал-гейта уже объяснены голосом зала (1 раз за матч)
var _judge_told := {}    ## последний озвученный «счёт судьи» по сторонам (наррация тиков TKO)
## Время «на прочитать» последнюю реплику (ReadingPace) — пейсинг ждёт минимум это перед
## следующим автоходом, чтобы мини-сцена реакции не обрывалась раньше срока (_wait_pace).
var _last_say_delay := 0.0


func _ready() -> void:
	model = RulesCore.new()
	nar = NarEngine.new()
	ai = Ai.new()
	_theme_data = ACTIVE_THEME.data()


# --- состояние для view (read-only) ---

func input_mode() -> String:
	return _mode

func theme_list() -> Array:
	var out: Array = []
	for t in THEMES:
		var td: Dictionary = t.data()
		out.append({"id": td.id, "topic": td.topic})
	return out

func active_theme_id() -> String:
	return String(_theme_data.get("id", ""))

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
	hint_text = ""
	# Разбудить зависший _ask_clinch прошлого матча — выйдет по epoch-guard, не тронув модель.
	_clinch_decided.emit({"act": "pass"})
	var first := SIDE_YOU if randf() < 0.5 else SIDE_OPP
	model.reset(first, DECK_U, DECK_T, DECK_R, HAND, BASE_THESES, KOMI, STEAL_CARDS, FORTIFY, CLINCH, CLINCH_FREEZE, CAPTURE, GATE_X, GATE_Y, 0, CAPTURE_LOOT, ZAL_KO, ZAL_HOLD)
	_gate_told = {}
	_judge_told = {}
	ai.set_style(SIDE_OPP, OPP_STYLE)
	match_id = int(Time.get_unix_time_from_system())
	nar.start(_theme_data, match_id, {"you": "contra", "opp": "pro"})
	EventBus.match_started.emit({
		"theme": nar.theme.id,
		"first": "you" if first == SIDE_YOU else "opp",
		"match_id": match_id,
	})
	_emit({
		"ev": "start", "ts": match_id,
		"first": "you" if first == SIDE_YOU else "opp",
		"ruleset": {"base": BASE_THESES, "steal_cards": STEAL_CARDS, "deck": "U%d T%d R%d" % [DECK_U, DECK_T, DECK_R], "freeze": CLINCH_FREEZE, "gate": "%d/%d" % [GATE_X, GATE_Y], "loot": CAPTURE_LOOT, "zal_ko": "%d/%d" % [ZAL_KO, ZAL_HOLD]},
		"theme": nar.theme.id,
	})
	_tx_header(first)
	_narrate("ТЕМА ДЕБАТОВ: «%s».  Слово первым: %s." % [nar.topic(), ("вы" if first == SIDE_YOU else "оппонент")])
	var yb := _claim_of(SIDE_YOU, model.sides[SIDE_YOU].lines[0])
	var ob := _claim_of(SIDE_OPP, model.sides[SIDE_OPP].lines[0])
	_say(SIDE_YOU, nar.open_line(SIDE_YOU, yb), "start you база")
	_say(SIDE_OPP, nar.open_line(SIDE_OPP, ob), "start opp база")
	_run_until_player()


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
			_show_end(); _changed(); return
		var st: String = model.begin_turn(model.current)
		_narrate_judge_count()
		if st == "ko" or st == "crowd" or st == "end" or st == "over":
			_show_end(); _changed(); return
		if st == "redeploy":
			var line: Dictionary = model.sides[model.current].lines[-1]
			var claim := _claim_of(model.current, line)
			_say(model.current, nar.redeploy_line(model.current, claim), "t%d %s redeploy (страховка)" % [model.turn_count, model.current], TYPE_USTANOVKA)
			var rev := {"ev": "redeploy", "side": model.current}
			rev.merge(_econ()); _emit(rev)
			model.advance(); _changed(); continue
		if st == "pass":
			_say(model.current, nar.pass_line(model.current), "t%d %s pass" % [model.turn_count, model.current])
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
		var act: Dictionary = ai.pick(model, SIDE_OPP, OPP_STYLE)
		if act.is_empty():
			model.sides[SIDE_OPP].passed = true
			model.advance(); continue
		if act.type == TYPE_RAZBOR:
			var tgt := int(act.get("target", -1))
			# Smart-бот холдит Кражи: жжёт только под досягаемый захват (ai.atk_prefer_steal).
			await _run_clinch(SIDE_OPP, SIDE_YOU, tgt, ai.atk_prefer_steal(model, SIDE_OPP, SIDE_YOU, tgt))
			if my_epoch != _epoch:
				return
		else:
			var info: Dictionary = model.play_action(SIDE_OPP, act.type)
			_log_action(info)
		model.advance()


# --- интенты игрока (зовёт view) ---

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
			_clinch_decided.emit({"act": "play", "steals": bool(card.get("steals", false))})
		return
	if _mode != "move":
		return
	match card.type:
		TYPE_TEZIS, TYPE_USTANOVKA:
			var info: Dictionary = model.play_action(SIDE_YOU, card.type)
			_log_action(info)
			model.advance()
			_run_until_player()
		TYPE_RAZBOR:
			if model.sides[SIDE_OPP].lines.is_empty():
				return
			_pending_steals = bool(card.get("steals", false))
			_mode = "target"
			hint_text = "%s: кликни рамку оппонента, которую атакуешь" % ("КРАЖА" if _pending_steals else "РАЗБОР")
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
	await _run_clinch(SIDE_YOU, SIDE_OPP, index, _pending_steals)
	if my_epoch != _epoch:
		return
	model.advance()
	_run_until_player()


func cancel_targeting() -> void:
	if _mode != "target":
		return
	_mode = "move"
	hint_text = ""
	_changed()


func clinch_pass() -> void:
	if _mode == "clinch_defend" or _mode == "clinch_attack":
		_clinch_decided.emit({"act": "pass"})


## Интерактивная воля клинча через стейт-API ядра. attacker инициирует разбором по defender[idx].
func _run_clinch(attacker: String, defender: String, idx: int, prefer_steal: bool) -> void:
	_mode = "locked"
	var my_epoch := _epoch
	if idx < 0 or idx >= model.sides[defender].lines.size():
		return
	var ctx: Dictionary = model.begin_clinch(attacker, defender, idx, prefer_steal)
	if ctx.is_empty():
		return
	var initc: Dictionary = ctx.card
	var init_steals: bool = initc.get("steals", false)
	var line: Dictionary = model.sides[defender].lines[idx]
	var target_claim := _claim_of(defender, line)
	var is_callback: bool = ctx.is_callback
	var atk_word := "кража" if init_steals else "разбор"
	var cb := "←старая" if is_callback else ""
	_say(attacker, nar.refute_line(attacker, target_claim, _top_stmt(line), initc, is_callback),
		"t%d %s clinch→%s[%d] %s%s" % [model.turn_count, attacker, defender, idx, atk_word, cb],
		TYPE_RAZBOR, init_steals)
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
		if side == SIDE_YOU:
			var d: Dictionary = await _ask_clinch("defend" if is_defend else "attack")
			if my_epoch != _epoch:
				return
			decision = String(d.get("act", "pass"))
			pref = bool(d.get("steals", false))
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
		var res: Dictionary = model.clinch_submit(decision, pref)
		match String(res.get("event", "")):
			"hold":
				var dc: Dictionary = res.card
				var stmt: Dictionary = nar.make_statement(defender, dc, _used_axes(line), "hold")
				_push_stmt(line, stmt)
				_say(defender, stmt.text, "    hold %s [%s]" % [defender, stmt.axis], TYPE_TEZIS)
				_changed()
			"press":
				var ac: Dictionary = res.card
				_say(attacker, nar.press_line(attacker, _top_stmt(line), ac),
					"    press %s %s" % [attacker, ("кража" if ac.get("steals", false) else "разбор")],
					TYPE_RAZBOR, bool(ac.get("steals", false)))
				_changed()
			"resolved":
				resolved = res
				break

	# Клинч закрыт.
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
	_changed()


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
	var reason := String(model.end_reason)
	var winner_s := "you" if model.winner == SIDE_YOU else ("opp" if model.winner == SIDE_OPP else "draw")
	var ev := {"ev": "end", "winner": winner_s, "reason": reason}
	ev.merge(_econ())
	_emit(ev)
	var verdict: String = nar.verdict_text(
		("you" if model.winner == SIDE_YOU else ("opp" if model.winner == SIDE_OPP else "")),
		reason, nar.stance_label(SIDE_YOU), nar.stance_label(SIDE_OPP))
	_narrate("⚖ " + verdict, "END %s winner=%s рамки %d:%d zal=%+d" % [
		reason, winner_s, model.score(SIDE_YOU), model.score(SIDE_OPP), model.zal()])
	EventBus.match_ended.emit(winner_s, reason, verdict)


# --------------------------------------------------------------- narrative ----

func _who(side: String) -> String:
	return "Вы" if side == SIDE_YOU else "Оппонент"


## Реплика стороны: в шину (для UI/персонажей) + в файловую стенограмму. card_type/steals —
## какой картой сказано (для выбора портрета-реакции по карте в character_core); "" — нет
## карты (пас/наррация), персонаж покажет нейтральный портрет.
func _say(side: String, text: String, tag: String = "", card_type: String = "", steals: bool = false) -> void:
	EventBus.utterance.emit(side, text, {
		"tag": tag, "stance": nar.stance_label(side),
		"card_type": card_type, "steals": steals,
	})
	_tx(tag, "%s (%s): %s" % [_who(side), nar.stance_label(side), text])
	_last_say_delay = ReadingPace.read_time(text)


## Пейсинг перед следующим автоходом: не короче base_delay, но и не короче времени дочитать
## только что сказанное (_last_say_delay) — иначе новая реплика/ход обрывает прошлую сцену
## реакции раньше, чем игрок успел её увидеть/прочитать.
func _wait_pace(base_delay: float) -> void:
	await get_tree().create_timer(maxf(base_delay, _last_say_delay)).timeout


## Авторская наррация (голос зала / ремарки).
func _narrate(text: String, tag: String = "") -> void:
	EventBus.narration.emit(text, {"tag": tag})
	_tx(tag, "· " + text)


func _changed() -> void:
	_maybe_narrate_gate()
	EventBus.board_changed.emit()


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
			var stmt: Dictionary = nar.make_statement(side, card, _used_axes(line), "assert")
			_push_stmt(line, stmt)
			_say(side, stmt.text, "t%d %s тезис[%s/%s]" % [model.turn_count, side, stmt.device, stmt.axis], TYPE_TEZIS)
		TYPE_USTANOVKA:
			var line: Dictionary = model.sides[side].lines[-1]
			var claim := _claim_of(side, line)
			_say(side, nar.open_line(side, claim, "open"), "t%d %s установка→рамка" % [model.turn_count, side], TYPE_USTANOVKA)
		TYPE_RAZBOR:
			pass  # атаки идут через клинч


func _count_razbor(side: String) -> int:
	var n := 0
	for c in model.sides[side].hand:
		if c.type == TYPE_RAZBOR:
			n += 1
	return n


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
