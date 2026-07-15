extends RefCounted

## Чистый финальный читатель трёх самостоятельных систем.
## Ничего не мутирует: один и тот же снимок можно прогнать через несколько victory-профилей.

const SIDE_YOU := "you"
const SIDE_OPP := "opp"


func board_snapshot(model: RefCounted, profile: Dictionary) -> Dictionary:
	var config: Dictionary = profile.get("board", {})
	var frame_weight := int(config.get("frame_weight", 3))
	var thesis_weight := int(config.get("thesis_weight", 1))
	var you_frames := int(model.score(SIDE_YOU))
	var opp_frames := int(model.score(SIDE_OPP))
	var you_theses := int(model.shine(SIDE_YOU))
	var opp_theses := int(model.shine(SIDE_OPP))
	var frame_diff := you_frames - opp_frames
	var thesis_diff := you_theses - opp_theses
	return {
		"you_frames": you_frames, "opp_frames": opp_frames, "frame_diff": frame_diff,
		"you_theses": you_theses, "opp_theses": opp_theses, "thesis_diff": thesis_diff,
		"frame_weight": frame_weight, "thesis_weight": thesis_weight,
		"score": frame_weight * frame_diff + thesis_weight * thesis_diff,
	}


func evaluate(model: RefCounted, audience: Dictionary, emotions: Dictionary,
	profile: Dictionary) -> Dictionary:
	var board := board_snapshot(model, profile)
	var victory: Dictionary = profile.get("victory", {})
	var links: Dictionary = profile.get("links", {})
	var mode := String(victory.get("mode", "board"))
	var lean := int(audience.get("lean", 0))
	var heat := int(audience.get("heat", 0))
	var board_score := int(board.score)
	var audience_component := 0
	var margin := board_score
	var formula := "B = %d·Δрамки + %d·Δтезисы" % [int(board.frame_weight), int(board.thesis_weight)]
	match mode:
		"mandate":
			audience_component = signi(lean) * heat
			margin = board_score + audience_component
			formula += "; итог = B + sign(Lean)·Heat"
		"additive":
			audience_component = roundi(float(lean) * float(victory.get("audience_weight", 1)))
			margin = board_score + audience_component
			formula += "; итог = B + Lean"
		"legacy":
			formula = "Legacy: ширина; при равенстве — производный зал"
		_:
			formula += "; победитель = sign(B)"

	var terminal_reason := String(model.end_reason)
	var winner := "draw"
	var reason := "draw"
	var decisive_source := "board"
	var keep_terminal := terminal_reason == "knockout" and bool(
		(profile.get("terminal", {}) as Dictionary).get("board_ko", true))
	keep_terminal = keep_terminal or terminal_reason == "crowd" and int(links.get("crowd_ko", 0)) > 0
	if mode == "legacy" or keep_terminal:
		winner = _public_winner(String(model.winner))
		reason = terminal_reason
		decisive_source = "legacy" if mode == "legacy" else terminal_reason
	else:
		winner = _winner_from_margin(margin)
		reason = "verdict" if winner != "draw" else "draw"
		decisive_source = "board" if mode == "board" else "combined"

	var board_winner := _winner_from_margin(board_score)
	var crowd_winner := _winner_from_margin(lean)
	var you_emotion: Dictionary = emotions.get(SIDE_YOU, {})
	var opp_emotion: Dictionary = emotions.get(SIDE_OPP, {})
	return {
		"profile": {
			"id": String(profile.get("id", "")),
			"label": String(profile.get("label", "Профиль")),
			"description": String(profile.get("description", "")),
		},
		"winner": winner,
		"reason": reason,
		"decisive_source": decisive_source,
		"mode": mode,
		"formula": formula,
		"margin": margin,
		"board": board,
		"audience": audience.duplicate(true),
		"audience_component": audience_component,
		"emotion": {
			SIDE_YOU: you_emotion.duplicate(true),
			SIDE_OPP: opp_emotion.duplicate(true),
			"strain_diff": int(you_emotion.get("strain", 0)) - int(opp_emotion.get("strain", 0)),
		},
		"board_winner": board_winner,
		"crowd_winner": crowd_winner,
		"split": board_winner != "draw" and crowd_winner != "draw" and board_winner != crowd_winner,
	}


func verdict_text(report: Dictionary, you_label: String, opp_label: String) -> String:
	var winner := String(report.get("winner", "draw"))
	var board: Dictionary = report.get("board", {})
	var audience: Dictionary = report.get("audience", {})
	var lean := int(audience.get("lean", 0))
	var heat := int(audience.get("heat", 0))
	var audience_tail := "зал остался нейтрален"
	if lean > 0:
		audience_tail = "зал склоняется к вам"
	elif lean < 0:
		audience_tail = "зал склоняется к оппоненту"
	audience_tail += ", накал %d/%d" % [heat, int(audience.get("heat_max", 0))]
	if winner == "draw":
		return "Логический счёт равен (%+d); %s." % [int(board.get("score", 0)), audience_tail]
	var label := you_label if winner == SIDE_YOU else opp_label
	var split_note := " Итог расколот." if bool(report.get("split", false)) else ""
	return "Побеждает «%s» при итоговом перевесе %+d; %s.%s" % [
		label, int(report.get("margin", 0)), audience_tail, split_note]


func _winner_from_margin(margin: int) -> String:
	return SIDE_YOU if margin > 0 else (SIDE_OPP if margin < 0 else "draw")


func _public_winner(core_winner: String) -> String:
	return core_winner if core_winner in [SIDE_YOU, SIDE_OPP] else "draw"
