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
	var production := OutcomeProfiles.get_profile(OutcomeProfiles.DEFAULT_ID)
	_check(String(production.id) == "combat_cohesion" and OutcomeProfiles.all().size() >= 7 and
		String(OutcomeProfiles.get_profile("missing_profile").id) == "combat_cohesion",
		"новый связный боевой профиль выбран production-default и fallback")
	_check(bool((production.terminal as Dictionary).board_ko) and
		int((production.links as Dictionary).gate_x) == 2 and
		int((production.links as Dictionary).gate_y) == 4 and
		not (production.links as Dictionary).has("composure_gate") and
		String((production.victory as Dictionary).mode) == "board",
		"production-профиль включает KO и публичное audience-only шатание 2/3/4")
	var vector := OutcomeProfiles.get_profile("vector_conduct")
	_check(String((vector.victory as Dictionary).mode) == "board" and
		String((vector.audience as Dictionary).valence_mode) == "content_plus_conduct" and
		int((vector.audience as Dictionary).decision_threshold) == 1,
		"векторный профиль разделяет победу и аудиторию")
	var old_vector := OutcomeProfiles.get_profile("vector_reaction")
	_check(String((old_vector.audience as Dictionary).valence_mode) == "reaction_priority" and
		int((old_vector.audience as Dictionary).decision_threshold) == 1,
		"прежний реакционный маятник сохранён отдельным сравнительным профилем")

	var audience := AudienceCore.new()
	audience.reset(vector.audience)
	var cold_scene := audience.resolve_scene("you", 1, 0, 1, false)
	var cold_breakdown: Dictionary = cold_scene.last_scene
	_check(int(audience.lean) == 1 and int(audience.heat) == 1 and
		int(cold_breakdown.heat_before) == 0 and int(cold_breakdown.amplitude) == 1,
		"холодная содержательная сцена сдвигает Lean на один и греет только следующую")
	audience.observe_quiet()
	_check(int(audience.lean) == 1 and int(audience.heat) == 1,
		"одно тихое действие ещё не выдаёт охлаждение за полный раунд")
	audience.observe_quiet()
	_check(int(audience.lean) == 1 and int(audience.heat) == 0,
		"два тихих действия остужают Heat, не переписывая Lean")
	audience.reset(vector.audience)
	var cancelled := audience.resolve_scene("opp", 1, 1, 1, true)
	_check(int(audience.lean) == 0 and int(cancelled.last_scene.total) == 0 and
		int(cancelled.last_scene.impulse) == 0,
		"хорошее поведение проигравшего отменяет публичный ущерб, но не крадёт сцену")
	_check(audience.reaction_value("audience_check", "argument_lost") == 0 and
		audience.reaction_value("audience_check", "dirty_hit") == 1 and
		audience.signed_reaction("opp", "audience_check", "captured") == -1 and
		audience.reaction_value("cold_laugh", "captured") == 0,
		"реакции читают stimulus/default, а не получают универсальный авторский знак")
	var hot_config: Dictionary = (vector.audience as Dictionary).duplicate(true)
	hot_config["opening_heat"] = 3
	audience.reset(hot_config)
	var hot_content_only := audience.resolve_scene("you", 1, 0, 1, false)
	_check(int(audience.lean) == 1 and int(audience.heat) == 3 and
		not bool(hot_content_only.last_scene.surged),
		"полный Heat не удваивает один содержательный голос без поддержки поведения")
	audience.reset(hot_config)
	var hot_conduct_only := audience.resolve_scene("", 0, 2, 1, true)
	_check(int(audience.lean) == 1 and int(audience.heat) == 3 and
		not bool(hot_conduct_only.last_scene.surged),
		"полный Heat не удваивает один голос поведения без содержательного исхода")
	audience.reset(hot_config)
	var surged := audience.resolve_scene("you", 1, 1, 1, true)
	_check(int(audience.lean) == 2 and int(audience.heat) == 1 and
		bool(surged.last_scene.votes_aligned) and bool(surged.last_scene.surged) and
		int(surged.last_scene.amplitude) == 2,
		"полный Heat усиливает только согласованную сцену и после всплеска сбрасывается")
	audience.reset(old_vector.audience)
	audience.resolve_scene("you", 1, 0, 1, false)
	_check(int(audience.lean) == 2 and int(audience.heat) == 1,
		"сравнительный профиль сохраняет самоусиление прежнего маятника")

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
	var crowd := {
		"lean": -4, "lean_cap": 5, "decision_threshold": 1,
		"heat": 3, "heat_max": 3,
	}
	var report := evaluator.evaluate(model, crowd, emotions, vector)
	_check(int((report.board as Dictionary).score) == 4 and String(report.winner) == "you",
		"победителя векторного профиля определяет только B=3ΔР+ΔТ")
	_check(bool(report.split) and String(report.crowd_winner) == "opp",
		"противоположный зал сохраняется отдельным расколотым итогом")
	var mild_crowd := crowd.duplicate(true)
	mild_crowd["lean"] = -1
	var mild_split := evaluator.evaluate(model, mild_crowd, emotions, vector)
	_check(String(mild_split.crowd_winner) == "opp" and bool(mild_split.split),
		"любой ненулевой крен сохраняет матрицу четырёх исходов")
	var undecided_crowd := crowd.duplicate(true)
	undecided_crowd["lean"] = 0
	var undecided := evaluator.evaluate(model, undecided_crowd, emotions, vector)
	_check(String(undecided.crowd_winner) == "draw" and not bool(undecided.split),
		"только ровный Lean 0 оставляет зал без стороны")
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
	_check(model.zal() == -4 and model.capture_threshold(RulesCore.SIDE_YOU) == 4,
		"RulesCore читает независимый публичный Lean как reach 1/2/3/4")

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
	_check("КРЕН  -4" in String(ui.get_node("%FinalAudienceScore").text),
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
	# start_match будит старый await клинча. Его continuation не должен затереть новый
	# opening-режим уже после рестарта/смены профиля.
	ui.controller._ask_clinch("defend")
	ui.controller.start_match()
	await get_tree().process_frame
	_check(String(ui.controller.input_mode()) == "opening",
		"протухший await клинча не блокирует ввод новой партии")
	ui.queue_free()

	print("=== OUTCOME ARCHITECTURE: %s ===" % ("OK" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures += 1
