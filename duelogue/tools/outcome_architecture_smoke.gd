extends Node

const RulesCore := preload("res://duelogue/core/rules/rules_core.gd")
const AudienceCore := preload("res://duelogue/core/audience/audience_core.gd")
const OutcomeProfiles := preload("res://duelogue/core/outcome/outcome_profiles.gd")
const OutcomeEvaluator := preload("res://duelogue/core/outcome/outcome_evaluator.gd")
const DebateScreen := preload("res://duelogue/ui/debate_screen.tscn")

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var vector := OutcomeProfiles.get_profile("vector_reaction")
	_check(String(vector.id) == "vector_reaction" and OutcomeProfiles.all().size() >= 5,
		"профили — данные и доступны тестам")
	_check(String((vector.victory as Dictionary).mode) == "board" and
		String((vector.audience as Dictionary).mode) == "pendulum",
		"векторный профиль разделяет победу и аудиторию")

	var audience := AudienceCore.new()
	audience.reset(vector.audience)
	audience.resolve_scene("you", 2, 0, false)
	_check(int(audience.lean) == 2 and int(audience.heat) == 1,
		"зрелище сначала нагревает и усиливает Lean")
	audience.observe_quiet()
	_check(int(audience.lean) == 2 and int(audience.heat) == 0,
		"тихий ход остужает Heat, не переписывая Lean")
	audience.reset(vector.audience)
	audience.resolve_scene("you", 2, -1, true)
	_check(int(audience.lean) == -2,
		"ненейтральная реакция переосмысляет логический исход сцены")

	var model := RulesCore.new()
	model.reset(RulesCore.SIDE_YOU, 3, 8, 9, 5, 1, 0, 2, 0, true, true, 1,
		0, 0, 0, 1, 0, 1, false)
	model.sides[RulesCore.SIDE_YOU].lines = [
		{"theses": 2, "closed": true, "stolen": 0},
		{"theses": 1, "closed": false, "stolen": 0},
	]
	model.sides[RulesCore.SIDE_OPP].lines = [
		{"theses": 2, "closed": false, "stolen": 0},
	]
	model.game_over = true
	model.end_reason = "decision"
	model.winner = RulesCore.SIDE_OPP  # старый итог намеренно противоположен новой доске
	var evaluator := OutcomeEvaluator.new()
	var emotions := {
		"you": {"strain": 5, "max": 6},
		"opp": {"strain": 1, "max": 6},
	}
	var crowd := {"lean": -4, "lean_cap": 5, "heat": 3, "heat_max": 3}
	var report := evaluator.evaluate(model, crowd, emotions, vector)
	_check(int((report.board as Dictionary).score) == 4 and String(report.winner) == "you",
		"победителя векторного профиля определяет только B=3ΔР+ΔТ")
	_check(bool(report.split) and String(report.crowd_winner) == "opp",
		"противоположный зал сохраняется отдельным расколотым итогом")
	_check(int((report.emotion as Dictionary).strain_diff) == 4,
		"финал регистрирует обе шкалы раздражения, не теряя их состояния")
	var legacy := evaluator.evaluate(model, crowd, emotions,
		OutcomeProfiles.get_profile("legacy"))
	_check(String(legacy.winner) == "opp" and String(legacy.reason) == "decision",
		"Legacy-профиль сохраняет уже вынесенный старый вердикт")

	# Та же доска и тот же зал читаются другой формулой без мутации трёх систем.
	model.sides[RulesCore.SIDE_YOU].lines = [{"theses": 2, "closed": false, "stolen": 0}]
	model.sides[RulesCore.SIDE_OPP].lines = [{"theses": 1, "closed": false, "stolen": 0}]
	var mandate := evaluator.evaluate(model, crowd, emotions,
		OutcomeProfiles.get_profile("mandate_diagnostic"))
	_check(int(mandate.margin) == -2 and String(mandate.winner) == "opp",
		"диагностический профиль B+sign(Lean)×Heat переключается данными")

	model.capture_mode = 1
	model.gate_x = 2
	model.gate_y = 4
	model.set_external_zal(-4, true)
	_check(model.zal() == -4 and model.capture_threshold(RulesCore.SIDE_YOU) == 3,
		"RulesCore читает независимый зал через прежний API гейта")

	# Без board-KO сторона без рамки может продолжить Разбором и дождаться общего вердикта.
	model.game_over = false
	model.current = RulesCore.SIDE_YOU
	model.board_ko_enabled = false
	model.sides[RulesCore.SIDE_YOU].lines = []
	model.sides[RulesCore.SIDE_YOU].hand = [{"type": RulesCore.TYPE_RAZBOR}]
	model.sides[RulesCore.SIDE_YOU].draw = []
	model.sides[RulesCore.SIDE_OPP].lines = [{"theses": 1, "closed": false, "stolen": 0}]
	_check(model.begin_turn(RulesCore.SIDE_YOU) == "ok" and not model.game_over,
		"терминальный нокаут последней рамки конфигурируется профилем")

	# Scene-authored окно действительно принимает полный отчёт.
	report["verdict"] = evaluator.verdict_text(report, "контра", "про")
	var ui := DebateScreen.instantiate()
	ui.playtest_logging_enabled = false
	add_child(ui)
	ui._on_match_reported(report)
	_check(bool(ui.get_node("%FinalOverlay").visible), "финальный протокол открывается")
	_check("B  +4" in String(ui.get_node("%FinalBoardScore").text),
		"финальное окно показывает прозрачный счёт доски")
	_check("LEAN  -4" in String(ui.get_node("%FinalAudienceScore").text),
		"финальное окно не смешивает зал с доской")
	var screenshot_args := OS.get_cmdline_user_args()
	if screenshot_args.has("--menu-screenshot"):
		ui._close_final_overlay()
		ui._open_menu()
	if screenshot_args.has("--screenshot") or screenshot_args.has("--menu-screenshot"):
		await get_tree().process_frame
		await get_tree().process_frame
		var preview_path := "user://outcome_menu_preview.png" if screenshot_args.has(
			"--menu-screenshot") else "user://outcome_final_preview.png"
		var viewport_texture := get_viewport().get_texture()
		if viewport_texture != null:
			viewport_texture.get_image().save_png(preview_path)
			print("PREVIEW: %s" % ProjectSettings.globalize_path(preview_path))
	ui.queue_free()

	print("=== OUTCOME ARCHITECTURE: %s ===" % ("OK" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures += 1
