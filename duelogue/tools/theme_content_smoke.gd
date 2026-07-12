extends SceneTree

## Theme v0.4 smoke: ананас + Evangelion должны дать каждой из восьми схем настоящий
## support-atom и минимум две формулировки взгляда. Шаурма намеренно остаётся v0.3 fallback.
## Запуск: godot --headless --script res://duelogue/tools/theme_content_smoke.gd

const Cards := preload("res://duelogue/core/cards/card_types.gd")
const Deck := preload("res://duelogue/core/cards/deck.gd")
const NarEngine := preload("res://duelogue/core/narrative/narrative_engine.gd")
const PineappleTheme := preload("res://duelogue/core/narrative/themes/theme_pineapple.gd")
const EvangelionTheme := preload("res://duelogue/core/narrative/themes/theme_evangelion.gd")

var failures := 0


func _init() -> void:
	print("\n=== THEME CONTENT v0.4 · SMOKE ===")
	for theme in [PineappleTheme.data(), EvangelionTheme.data()]:
		_validate_theme(theme)
		_sample_deck(theme)
		_sample_attacks(theme)
	if failures == 0:
		print("=== ИТОГ: OK ===")
		quit(0)
	else:
		print("=== ИТОГ: FAIL (%d) ===" % failures)
		quit(1)


func _validate_theme(theme: Dictionary) -> void:
	for axis in theme.axes:
		for pole in ["contra", "pro"]:
			var takes: Array = axis.get("takes", {}).get(pole, [])
			_check(takes.size() >= 2, "%s/%s/%s: ≥2 takes" % [theme.id, axis.id, pole])
			var supports: Dictionary = axis.get("supports", {}).get(pole, {})
			_check(not supports.is_empty(), "%s/%s/%s: supports есть" % [theme.id, axis.id, pole])
			for kind in supports:
				for value in supports[kind]:
					var s := String(value)
					_check(s != "" and not s.ends_with(".") and not s.ends_with("!") and not s.ends_with("?"),
						"%s/%s/%s/%s: fill-safe atom" % [theme.id, axis.id, pole, kind])


func _sample_deck(theme: Dictionary) -> void:
	print("\n--- %s ---" % theme.topic)
	for side in ["you", "opp"]:
		var nar := NarEngine.new()
		nar.start(theme, 20260711 + (0 if side == "you" else 1), {"you": "contra", "opp": "pro"})
		print("  [%s]" % nar.stance_label(side))
		for i in 8:
			var card := Deck.make_card(Cards.TYPE_TEZIS, i)
			var stmt: Dictionary = nar.make_statement(side, card, [], "assert")
			_check(String(stmt.get("support_kind", "")) != "",
				"%s/%s/%s: схема получила support" % [theme.id, side, stmt.device])
			print("    %-14s · %-10s/%-10s · %s" % [stmt.device, stmt.axis,
				stmt.support_kind, stmt.text])


func _sample_attacks(theme: Dictionary) -> void:
	print("  [содержательные атаки]")
	var cases := [
		{"axis": "balance" if theme.id == "pineapple" else "arc", "scheme": "Статистика", "card_i": 2},
		{"axis": "identity" if theme.id == "pineapple" else "design", "scheme": "Аналогия", "card_i": 6},
		{"axis": "tradition" if theme.id == "pineapple" else "arc", "scheme": "Традиция", "card_i": 3},
	]
	for spec in cases:
		var nar := NarEngine.new()
		nar.start(theme, 9090 + int(spec.card_i), {"you": "contra", "opp": "pro"})
		var axis: Dictionary
		for candidate in theme.axes:
			if String(candidate.id) == String(spec.axis):
				axis = candidate
				break
		var target := {"axis": String(axis.id), "gist": String(axis.pro), "device": String(spec.scheme)}
		var card := Deck.make_card(Cards.TYPE_RAZBOR, int(spec.card_i))
		var line := nar.refute_line("you", "чужая рамка", target, card, false)
		print("    %-17s · %s" % [nar.device_label(card), line])
		_check(not line.contains("завтра — норма") and not line.contains("под запрет"),
			"%s/%s: атака использует typed support" % [theme.id, nar.device_label(card)])


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL · " + label)
