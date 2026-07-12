extends SceneTree

## Чистый smoke opening-фазы: структурные headline, выбор без повтора и семантический
## bias первой реплики. Не создаёт BattleController, поэтому не пишет игровые логи.
## Запуск: godot --headless --script res://duelogue/tools/opening_smoke.gd

const Cards := preload("res://duelogue/core/cards/card_types.gd")
const NarEngine := preload("res://duelogue/core/narrative/narrative_engine.gd")
const PineappleTheme := preload("res://duelogue/core/narrative/themes/theme_pineapple.gd")
const ShawarmaTheme := preload("res://duelogue/core/narrative/themes/theme_shawarma.gd")
const EvangelionTheme := preload("res://duelogue/core/narrative/themes/theme_evangelion.gd")

var failures := 0


func _init() -> void:
	print("\n=== OPENING · SMOKE ===")
	for theme in [PineappleTheme.data(), ShawarmaTheme.data(), EvangelionTheme.data()]:
		_check_theme(theme)
	_check_ui_contract()
	if failures == 0:
		print("=== ИТОГ: OK ===")
		quit(0)
	else:
		print("=== ИТОГ: FAIL (%d) ===" % failures)
		quit(1)


func _check_theme(theme: Dictionary) -> void:
	var nar := NarEngine.new()
	nar.start(theme, 20260711, {"you": "contra", "opp": "pro"})
	var options: Array = nar.headline_options("you", 3)
	_check(options.size() == 3, "%s: игрок видит 3 рамки" % theme.id)
	if options.size() < 2:
		return
	var selected: Dictionary = nar.select_headline("you", String(options[1].id))
	_check(not selected.is_empty(), "%s: рамка выбирается по id" % theme.id)
	var next: Dictionary = nar.next_headline_data("you")
	_check(String(next.get("id", "")) != String(selected.get("id", "")),
		"%s: следующая Установка не повторяет opening" % theme.id)

	var preferred: Array = selected.get("preferred_axes", [])
	var statement: Dictionary = nar.make_statement("you",
		{"type": Cards.TYPE_TEZIS, "name": "Довод", "steals": false}, [], "assert", selected)
	_check(preferred.has(String(statement.get("axis", ""))),
		"%s: первый довод следует выбранной рамке" % theme.id)
	_check(nar.axis_tags(preferred).size() > 0, "%s: UI получает читаемые теги осей" % theme.id)

	var auto: Dictionary = nar.auto_headline("opp", "logos")
	_check(not auto.is_empty(), "%s: оппонент получает рамку автоматически" % theme.id)
	var preview := nar.preview_text("you",
		{"type": Cards.TYPE_USTANOVKA, "name": "Рамка", "steals": false})
	_check(preview != "" and not preview.contains("preferred_axes"),
		"%s: превью Установки читает структурный headline" % theme.id)


func _check_ui_contract() -> void:
	var scene_text := FileAccess.get_file_as_string("res://duelogue/ui/debate_screen.tscn")
	_check(not scene_text.contains("OpeningOverlay"),
		"UI: отдельного opening-окна больше нет")
	_check(scene_text.contains("name=\"CardInfoBubble\"") and scene_text.contains("visible = false"),
		"UI: фиксированный card-info bubble существует и скрыт по умолчанию")
	_check(scene_text.contains("name=\"CardInfoBody\"") and scene_text.contains("autowrap_mode = 3"),
		"UI: текст бабла переносится по словам")


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures += 1
