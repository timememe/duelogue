extends SceneTree

## Headless smoke-тест нарративного слоя: полный матч AI-vs-AI → стенограмма в stdout.
## Зеркалит точки наррации из zal_narr.gd, но без UI/await (обе стороны — ИИ).
## Запуск: godot --headless --script res://duelogue/tools/narrative_smoke.gd

const ZalV3 := preload("res://duelogue/core/rules/rules_core.gd")  ## ядро правил (псевдоним сохранён)
const Ai := preload("res://duelogue/core/ai/ai.gd")
const NarEngine := preload("res://duelogue/core/narrative/narrative_engine.gd")
const PineappleTheme := preload("res://duelogue/core/narrative/themes/theme_pineapple.gd")
const ShawarmaTheme := preload("res://duelogue/core/narrative/themes/theme_shawarma.gd")
const EvangelionTheme := preload("res://duelogue/core/narrative/themes/theme_evangelion.gd")

const TX_PATH := "res://duelogue/tools/narrative_transcript_smoke.md"

var model: RefCounted
var nar: RefCounted
var ai: RefCounted
var match_id := 0
var _theme: Dictionary


func _init() -> void:
	model = ZalV3.new()
	nar = NarEngine.new()
	ai = Ai.new()
	# Чистим smoke-транскрипт перед прогоном.
	if FileAccess.file_exists(TX_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TX_PATH))
	# Обе темы через ОДИН движок — проверка модульности и fill-safe сборки.
	for spec in [{"t": PineappleTheme.data(), "base": 1000}, {"t": ShawarmaTheme.data(), "base": 2000}, {"t": EvangelionTheme.data(), "base": 3000}]:
		for run in 5:
			print("\n========== %s · МАТЧ %d ==========" % [spec.t.id, run + 1])
			_play_match(int(spec.base) + run, spec.t)
	quit()


func _play_match(seed: int, theme: Dictionary) -> void:
	seed(seed)
	var first := ZalV3.SIDE_YOU if randf() < 0.5 else ZalV3.SIDE_OPP
	match_id = seed
	model.reset(first, 3, 8, 9, 5, 1, 0, 2, 0, true, true)
	nar.start(theme, seed, {"you": "contra", "opp": "pro"})
	var draw0 := maxi(1, _draw_left())
	_tx_header(first)
	_narrate("ТЕМА: «%s». Первым: %s." % [nar.topic(), ("вы" if first == ZalV3.SIDE_YOU else "оппонент")])
	_say(ZalV3.SIDE_YOU, nar.open_line(ZalV3.SIDE_YOU, _claim_of(ZalV3.SIDE_YOU, model.sides[ZalV3.SIDE_YOU].lines[0])), "start you база")
	_say(ZalV3.SIDE_OPP, nar.open_line(ZalV3.SIDE_OPP, _claim_of(ZalV3.SIDE_OPP, model.sides[ZalV3.SIDE_OPP].lines[0])), "start opp база")

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
	var initc: Dictionary = model.remove_attack(attacker, true)
	var init_steals: bool = initc.get("steals", false)
	var line: Dictionary = model.sides[defender].lines[idx]
	var target_claim := _claim_of(defender, line)
	var is_callback: bool = line.closed
	var atk_word := "кража" if init_steals else "разбор"
	var cb := "←старая" if is_callback else ""
	_say(attacker, nar.refute_line(attacker, target_claim, _top_stmt(line), initc, is_callback),
		"t%d %s clinch→%s[%d] %s%s" % [model.turn_count, attacker, defender, idx, atk_word, cb])

	var t_added := 0
	var r_count := 1
	var atk_steals := 1 if init_steals else 0
	var guard := 0
	while guard < 40:
		guard += 1
		if model.has_card(defender, ZalV3.TYPE_TEZIS) and ai.def_will_clinch(model, defender, line):
			var dc: Dictionary = model.remove_card_of(defender, ZalV3.TYPE_TEZIS)
			line.theses = int(line.theses) + 1
			t_added += 1
			var stmt: Dictionary = nar.make_statement(defender, dc, _used_axes(line), "hold")
			_push_stmt(line, stmt)
			_say(defender, stmt.text, "    hold %s [%s]" % [defender, stmt.axis])
		else:
			break
		if model.has_card(attacker, ZalV3.TYPE_RAZBOR) and ai.atk_will_clinch(model, attacker, line):
			var ac: Dictionary = model.remove_attack(attacker, true)
			r_count += 1
			if ac.get("steals", false):
				atk_steals += 1
			_say(attacker, nar.press_line(attacker, _top_stmt(line), ac),
				"    press %s %s" % [attacker, ("кража" if ac.get("steals", false) else "разбор")])
		else:
			break

	var info := {"side": attacker, "type": ZalV3.TYPE_RAZBOR}
	model.clinch_finalize(attacker, defender, idx, t_added, r_count, info, atk_steals)
	var landed := r_count > t_added
	_narrate(nar.resolve_text(landed, info.get("removed", false), target_claim, int(info.get("stolen_count", 0)), not landed),
		"    resolve t%d r%d %s%s%s" % [t_added, r_count,
			("landed" if landed else "withstand"),
			(" removed" if info.get("removed", false) else ""),
			(" stolen=%d" % int(info.get("stolen_count", 0)) if int(info.get("stolen_count", 0)) > 0 else "")])
	if not info.get("removed", false):
		var stx: Array = line.get("statements", [])
		while stx.size() > int(line.theses):
			stx.pop_back()


func _narrate_move(info: Dictionary) -> void:
	if info.is_empty():
		return
	var side: String = info.side
	var card := {"type": info.type, "name": info.get("name", ""), "steals": false}
	match info.type:
		ZalV3.TYPE_TEZIS:
			var line: Dictionary = model.sides[side].lines[-1]
			_claim_of(side, line)
			var stmt: Dictionary = nar.make_statement(side, card, _used_axes(line), "assert")
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

func _used_axes(line: Dictionary) -> Array:
	var out: Array = []
	for s in line.get("statements", []):
		out.append(s.get("axis", ""))
	return out
