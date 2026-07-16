extends SceneTree

## Headless smoke-тест нарративного слоя: полный матч AI-vs-AI → стенограмма в stdout.
## Зеркалит точки наррации из zal_narr.gd, но без UI/await (обе стороны — ИИ).
## Запуск: godot --headless --script res://duelogue/tools/narrative_smoke.gd

const ZalV3 := preload("res://duelogue/core/rules/rules_core.gd")  ## ядро правил (псевдоним сохранён)
const Ai := preload("res://duelogue/core/ai/ai.gd")
const NarEngine := preload("res://duelogue/core/narrative/narrative_engine.gd")
const EmotionCore := preload("res://duelogue/core/emotion/emotion_core.gd")
const DefaultReactions := preload("res://duelogue/core/emotion/reaction_decks/volatile_default.gd")
const PineappleTheme := preload("res://duelogue/core/narrative/themes/theme_pineapple.gd")
const ShawarmaTheme := preload("res://duelogue/core/narrative/themes/theme_shawarma.gd")
const EvangelionTheme := preload("res://duelogue/core/narrative/themes/theme_evangelion.gd")

const TX_PATH := "res://duelogue/tools/narrative_transcript_smoke.md"
const MAX_REACTION_REPLIES := 2

var model: RefCounted
var nar: RefCounted
var ai: RefCounted
var emotion: RefCounted
var match_id := 0
var _theme: Dictionary
var _stdout_only := false
var _runs := 5
var _v04_only := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_stdout_only = args.has("--stdout-only")
	_v04_only = args.has("--v04-only")
	for arg in args:
		if String(arg).begins_with("--runs="):
			_runs = maxi(1, int(String(arg).trim_prefix("--runs=")))
	model = ZalV3.new()
	nar = NarEngine.new()
	ai = Ai.new()
	emotion = EmotionCore.new()
	# Чистим smoke-транскрипт перед прогоном.
	if not _stdout_only and FileAccess.file_exists(TX_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TX_PATH))
	# Обе темы через ОДИН движок — проверка модульности и fill-safe сборки.
	var specs := [{"t": PineappleTheme.data(), "base": 1000}, {"t": ShawarmaTheme.data(), "base": 2000}, {"t": EvangelionTheme.data(), "base": 3000}]
	if _v04_only:
		specs = [specs[0], specs[2]]
	for spec in specs:
		for run in _runs:
			print("\n========== %s · МАТЧ %d ==========" % [spec.t.id, run + 1])
			_play_match(int(spec.base) + run, spec.t)
	quit()


func _play_match(seed: int, theme: Dictionary) -> void:
	seed(seed)
	var first := ZalV3.SIDE_YOU if randf() < 0.5 else ZalV3.SIDE_OPP
	match_id = seed
	model.reset(first, 3, 8, 9, 5, 1, 0, 2, 0, true, true)
	nar.start(theme, seed, {"you": "contra", "opp": "pro"})
	emotion.start(DefaultReactions.data(), seed ^ 0x5EED, [ZalV3.SIDE_YOU, ZalV3.SIDE_OPP])
	var draw0 := maxi(1, _draw_left())
	_tx_header(first)
	_narrate("ТЕМА: «%s». Первым: %s." % [nar.topic(), ("вы" if first == ZalV3.SIDE_YOU else "оппонент")])
	_bind_claim(model.sides[ZalV3.SIDE_YOU].lines[0], nar.auto_headline(ZalV3.SIDE_YOU))
	_bind_claim(model.sides[ZalV3.SIDE_OPP].lines[0], nar.auto_headline(ZalV3.SIDE_OPP))
	for side in [first, model.other(first)]:
		_say(side, nar.open_line(side, _claim_of(side, model.sides[side].lines[0])), "start %s база" % side)

	var guard := 0
	while not model.game_over and guard < 300:
		guard += 1
		nar.update_heat(model.zal(), 1.0 - float(_draw_left()) / float(draw0))
		var side: String = model.current
		var st: String = model.begin_turn(side)
		if st == "ko" or st == "end" or st == "over":
			break
		if st == "redeploy":
			_say(side, nar.redeploy_line(side, _claim_of(side, model.sides[side].lines[-1])), "t%d %s redeploy (страховка)" % [model.turn_count, side])
			model.advance(); continue
		if st == "pass":
			_say(side, nar.pass_line(side), "t%d %s pass" % [model.turn_count, side])
			model.advance(); continue
		var act: Dictionary = ai.pick(model, side, "balanced")
		if act.is_empty():
			model.sides[side].passed = true
			model.advance(); continue
		if act.type == ZalV3.TYPE_RAZBOR:
			_auto_clinch(side, model.other(side), int(act.get("target", -1)))
		else:
			var info: Dictionary = model.play_action(side, act.type)
			_narrate_move(info)
		model.advance()

	_show_end()


func _auto_clinch(attacker: String, defender: String, idx: int) -> void:
	if idx < 0 or idx >= model.sides[defender].lines.size():
		return
	var started: Dictionary = model.begin_clinch(attacker, defender, idx, true)
	if started.is_empty():
		return
	var initc: Dictionary = started.card
	var init_steals: bool = initc.get("steals", false)
	var line: Dictionary = model.sides[defender].lines[idx]
	var target_claim := _claim_of(defender, line)
	var is_callback: bool = bool(started.get("is_callback", false))
	var atk_word := "кража" if init_steals else "разбор"
	var cb := "←старая" if is_callback else ""
	_say(attacker, nar.refute_line(attacker, target_claim, _top_stmt(line), initc, is_callback, line),
		"t%d %s clinch→%s[%d] %s%s" % [model.turn_count, attacker, defender, idx, atk_word, cb])

	var resolved: Dictionary = {}
	var guard := 0
	while model.clinch_active() and guard < 40:
		guard += 1
		var pending_side: String = model.clinch_pending_side()
		var is_defend: bool = pending_side == defender
		if not model.clinch_can_act(pending_side):
			resolved = model.clinch_submit("pass", true, -1, "exhausted")
			break
		var will_play: bool = ai.def_will_clinch(model, defender, line) if is_defend else \
			ai.atk_will_clinch(model, attacker, line)
		if not will_play:
			resolved = model.clinch_submit("pass")
			break
		var prefer: bool = true if is_defend else \
			bool(ai.atk_prefer_steal(model, attacker, defender, idx))
		var step: Dictionary = model.clinch_submit("play", prefer)
		match String(step.get("event", "")):
			"hold":
				var dc: Dictionary = step.card
				var stmt: Dictionary = nar.make_statement(defender, dc, _used_axes(line), "hold", line)
				stmt["thesis_id"] = String(dc.get("thesis_id", ""))
				_push_stmt(line, stmt)
				_say(defender, stmt.text, "    hold %s [%s]" % [defender, stmt.axis])
			"press":
				var ac: Dictionary = step.card
				_say(attacker, nar.press_line(attacker, _top_stmt(line), ac),
					"    press %s %s" % [attacker,
						("кража" if ac.get("steals", false) else "разбор")])
				_emotion_event(attacker, "clinch_pressure", 1, target_claim)
				_emotion_event(defender, "clinch_pressure", 1, target_claim)
			"resolved":
				resolved = step
				break
	if resolved.is_empty() and model.clinch_active():
		resolved = model.clinch_submit("pass", true, -1, "exhausted")
	var t_added := int(resolved.get("t_added", 0))
	var r_count := int(resolved.get("r_count", 1))
	var landed := bool(resolved.get("landed", r_count > t_added))
	var info: Dictionary = resolved.get("info", {})
	_narrate(nar.resolve_text(landed, info.get("removed", false), target_claim,
		int(info.get("stolen_count", 0)), not landed, info),
		"    resolve t%d r%d %s%s%s%s%s" % [t_added, r_count,
			("landed" if landed else "withstand"),
			(" removed" if info.get("removed", false) else ""),
			(" stolen=%d" % int(info.get("stolen_count", 0)) if int(info.get("stolen_count", 0)) > 0 else ""),
			(" captured" if info.get("captured", false) else ""),
			(" capture_blocked=%s" % String(info.get("capture_block_reason", "unknown"))
				if info.get("capture_blocked", false) else "")])
	if not info.get("removed", false):
		var stx: Array = line.get("statements", [])
		var removed_ids: Array = info.get("removed_thesis_ids", [])
		for si in range(stx.size() - 1, -1, -1):
			if removed_ids.has(String((stx[si] as Dictionary).get("thesis_id", ""))):
				stx.remove_at(si)
	var strained_side := defender if landed else attacker
	var stimulus := "attack_stalled"
	if landed:
		stimulus = "captured" if info.get("captured", false) else \
			("frame_lost" if info.get("removed", false) else "argument_lost")
	var intensity := 1 + (1 if info.get("removed", false) else 0)
	if info.get("captured", false):
		intensity += 1
	_emotion_event(strained_side, stimulus, mini(3, intensity), target_claim)


func _narrate_move(info: Dictionary) -> void:
	if info.is_empty():
		return
	var side: String = info.side
	var card := {"type": info.type, "name": info.get("name", ""), "steals": false}
	match info.type:
		ZalV3.TYPE_TEZIS:
			var line: Dictionary = model.sides[side].lines[-1]
			_claim_of(side, line)
			var stmt: Dictionary = nar.make_statement(side, card, _used_axes(line), "assert", line)
			stmt["thesis_id"] = String(info.get("thesis_id", ""))
			_push_stmt(line, stmt)
			_say(side, stmt.text, "t%d %s тезис[%s/%s]" % [model.turn_count, side, stmt.device, stmt.axis])
		ZalV3.TYPE_USTANOVKA:
			var line: Dictionary = model.sides[side].lines[-1]
			_say(side, nar.open_line(side, _claim_of(side, line), "open"), "t%d %s установка→рамка" % [model.turn_count, side])


func _show_end() -> void:
	var winner_s := "you" if model.winner == ZalV3.SIDE_YOU else ("opp" if model.winner == ZalV3.SIDE_OPP else "")
	_narrate("⚖ " + nar.verdict_text(winner_s, String(model.end_reason),
		nar.stance_label(ZalV3.SIDE_YOU), nar.stance_label(ZalV3.SIDE_OPP)),
		"END %s winner=%s рамки %d:%d zal=%+d" % [String(model.end_reason), winner_s,
			model.score(ZalV3.SIDE_YOU), model.score(ZalV3.SIDE_OPP), model.zal()])
	var ey: Dictionary = emotion.state(ZalV3.SIDE_YOU)
	var eo: Dictionary = emotion.state(ZalV3.SIDE_OPP)
	_narrate("ЭМОЦИИ: вы %d/6, реакций %d · оппонент %d/6, реакций %d." % [
		int(ey.strain), int(ey.reactions), int(eo.strain), int(eo.reactions)], "emotion summary")
	_narrate("СВЯЗКИ: парировок %d · ответных срывов %d." % [
		int(ey.parries) + int(eo.parries),
		int(ey.linked_reactions) + int(eo.linked_reactions)], "emotion links")


func _emotion_event(side: String, stimulus: String, intensity: int, target: String) -> void:
	var result: Dictionary = emotion.observe(side, stimulus, intensity, {"target": target})
	_emotion_result(result, target, 0)


func _emotion_result(result: Dictionary, target: String, chain_depth: int) -> void:
	var reaction: Dictionary = result.get("reaction", {})
	if reaction.is_empty():
		return
	var side := String(result.side)
	_say(side, String(reaction.text), "    reaction %s %s %d→%d→%d" % [
		side, String(reaction.id), int(result.before), int(result.peak), int(result.after)])
	if chain_depth >= MAX_REACTION_REPLIES:
		return
	var responder: String = String(model.other(side))
	var answer: Dictionary = emotion.answer_reaction(responder, {"target": target})
	if String(answer.get("kind", "")) == "parry":
		var parry: Dictionary = answer.parry
		_say(responder, String(parry.text), "    parry %s→%s %s" % [
			side, responder, String(parry.id)])
		return
	_emotion_result(answer, target, chain_depth + 1)


# --- helpers (зеркало zal_narr.gd) ---

func _draw_left() -> int:
	var n := 0
	for side in [ZalV3.SIDE_YOU, ZalV3.SIDE_OPP]:
		n += (model.sides[side].draw as Array).size()
	return n


func _who(side: String) -> String:
	return "Вы" if side == ZalV3.SIDE_YOU else "Оппонент"

func _say(side: String, text: String, tag: String = "") -> void:
	print("— %s (%s): %s" % [_who(side), nar.stance_label(side), text])
	_tx(tag, "%s (%s): %s" % [_who(side), nar.stance_label(side), text])

func _narrate(text: String, tag: String = "") -> void:
	print("  · %s" % text)
	_tx(tag, "· " + text)

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
	if _stdout_only:
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

func _claim_of(side: String, line: Dictionary) -> String:
	var c := String(line.get("claim", ""))
	if c == "":
		_bind_claim(line, nar.next_headline_data(side))
		c = String(line.get("claim", ""))
	return c

func _bind_claim(line: Dictionary, headline: Dictionary) -> void:
	line["claim_id"] = String(headline.get("id", ""))
	line["claim"] = String(headline.get("text", ""))
	line["preferred_axes"] = (headline.get("preferred_axes", []) as Array).duplicate()

func _push_stmt(line: Dictionary, stmt: Dictionary) -> void:
	if not line.has("statements"):
		line["statements"] = []
	line["statements"].append(stmt)

func _top_stmt(line: Dictionary) -> Dictionary:
	var st: Array = line.get("statements", [])
	return {} if st.is_empty() else st.back()

func _used_axes(line: Dictionary) -> Array:
	var out: Array = []
	for s in line.get("statements", []):
		out.append(s.get("axis", ""))
	return out
