extends SceneTree

## Регрессия «карта = произнесённая реплика»:
## 1) preview не мутирует narrative state и совпадает с немедленным розыгрышем;
## 2) ядро списывает выбранный индекс, а не первую карту того же типа;
## 3) Передёрг не отвечает на чужую реплику словами «я такого не говорил»;
## 4) полные тезисы v0.4 остаются карточного размера.

const Cards := preload("res://duelogue/core/cards/card_types.gd")
const Deck := preload("res://duelogue/core/cards/deck.gd")
const Rules := preload("res://duelogue/core/rules/rules_core.gd")
const Nar := preload("res://duelogue/core/narrative/narrative_engine.gd")
const Pineapple := preload("res://duelogue/core/narrative/themes/theme_pineapple.gd")
const Evangelion := preload("res://duelogue/core/narrative/themes/theme_evangelion.gd")

var failures := 0


func _init() -> void:
	print("\n=== CONTEXT PREVIEW · SMOKE ===")
	_test_selected_card()
	_test_selected_clinch_cards()
	for theme in [Pineapple.data(), Evangelion.data()]:
		_test_exact_narrative(theme)
	if failures == 0:
		print("=== ИТОГ: OK ===")
		quit(0)
	else:
		print("=== ИТОГ: FAIL (%d) ===" % failures)
		quit(1)


func _side(hand: Array, lines: Array) -> Dictionary:
	return {"hand": hand, "lines": lines, "draw": [], "discard": [], "passed": false,
		"sw_used": 0}


func _test_selected_card() -> void:
	var rules := Rules.new()
	rules.sides = {
		"you": _side([Deck.make_card(Cards.TYPE_TEZIS, 0), Deck.make_card(Cards.TYPE_TEZIS, 4)],
			[{"theses": 1, "closed": false, "name": "База", "stolen": 0}]),
		"opp": _side([], [{"theses": 1, "closed": false, "name": "База", "stolen": 0}]),
	}
	var info: Dictionary = rules.play_action("you", Cards.TYPE_TEZIS, -1, 1)
	_check(String(info.name) == "Пример", "обычный ход списывает нажатую карту")
	_check(rules.sides.you.hand.size() == 1 and String(rules.sides.you.hand[0].name) == "Довод",
		"соседняя карта того же типа остаётся в руке")


func _test_selected_clinch_cards() -> void:
	var rules := Rules.new()
	var stolen_hold := Deck.make_card(Cards.TYPE_TEZIS, 4)
	stolen_hold["stolen"] = true
	rules.sides = {
		"you": _side([Deck.make_card(Cards.TYPE_RAZBOR, 1), Deck.make_card(Cards.TYPE_RAZBOR, 2)],
			[{"theses": 1, "closed": false, "name": "База", "stolen": 0}]),
		"opp": _side([Deck.make_card(Cards.TYPE_TEZIS, 0), stolen_hold],
			[{"theses": 2, "closed": false, "name": "База", "stolen": 0}]),
	}
	var opened: Dictionary = rules.begin_clinch("you", "opp", 0, false, 1)
	_check(String(opened.card.name) == "Контрпример", "клинч открывает нажатый Разбор")
	var held: Dictionary = rules.clinch_submit("play", false, 1)
	_check(String(held.card.name) == "Пример", "защита клинча тратит нажатый Тезис")
	_check(int(rules.sides.opp.lines[0].stolen) == 1,
		"украденный Тезис сохраняет золотой статус при защите клинча")
	var pressed: Dictionary = rules.clinch_submit("play", false, 0)
	_check(String(pressed.card.name) == "Передёрг", "добив клинча тратит нажатый Разбор")
	var sequence: Array = rules.clinch.get("sequence", [])
	_check(sequence.size() == 3 and String(sequence[0].type) == Cards.TYPE_RAZBOR and
		String(sequence[1].type) == Cards.TYPE_TEZIS and
		bool(sequence[1].get("stolen", false)) and String(sequence[2].type) == Cards.TYPE_RAZBOR,
		"клинч хранит визуальный порядок Разбор → Тезис → Разбор")


func _test_exact_narrative(theme: Dictionary) -> void:
	var nar := Nar.new()
	nar.start(theme, 20260712, {"you": "contra", "opp": "pro"})
	var frame: Dictionary = nar.select_headline("you", String(nar.headline_options("you", 1)[0].id))
	var lengths: Array = []
	var used: Array = []
	for i in 8:
		var card := Deck.make_card(Cards.TYPE_TEZIS, i)
		var preview: Dictionary = nar.preview_statement_exact("you", card, used, "assert", frame)
		var actual: Dictionary = nar.make_statement("you", card, used, "assert", frame)
		_check(String(preview.text) == String(actual.text), "%s: Тезис preview = микросцена" % theme.id)
		lengths.append(String(actual.text).length())
		used.append(String(actual.axis))
	var max_len := 0
	var total := 0
	for n in lengths:
		max_len = maxi(max_len, int(n))
		total += int(n)
	var avg := float(total) / float(lengths.size())
	print("  %s: тезисы avg %.1f · max %d знаков" % [theme.id, avg, max_len])
	_check(max_len <= 180 and avg <= 125.0, "%s: тезисы не превращаются в абзацы" % theme.id)

	var open_preview: Dictionary = nar.preview_next_open_exact("you")
	var headline: Dictionary = nar.next_headline_data("you")
	var open_actual := nar.open_line("you", String(headline.text), "open")
	_check(String(open_preview.headline.id) == String(headline.id) and String(open_preview.text) == open_actual,
		"%s: Установка preview = микросцена" % theme.id)

	var attack := Deck.make_card(Cards.TYPE_RAZBOR, 1) # Передёрг
	var axis: Dictionary = theme.axes[1]
	var target := {"axis": String(axis.id), "gist": String(axis.pro), "device": "Традиция"}
	var attack_preview: Dictionary = nar.preview_refute_exact("you", "чужая рамка", target,
		attack, false, {"preferred_axes": [String(axis.id)]})
	var attack_actual := nar.refute_line("you", "чужая рамка", target, attack, false,
		{"preferred_axes": [String(axis.id)]})
	_check(String(attack_preview.text) == attack_actual, "%s: Разбор preview = микросцена" % theme.id)
	var low := attack_actual.to_lower()
	_check(not low.contains("я такого не говорил") and not low.contains("не приписывай мне"),
		"%s: Передёрг семантически обращён к чужому тезису" % theme.id)
	# Второй добив после открытия — tier 3 (панч).
	nar.press_line("you", target, attack)
	var punch := nar.press_line("you", target, attack).to_lower()
	_check(not punch.contains("я такого не говорил") and not punch.contains("не приписывай мне"),
		"%s: панч Передёрга не путает говорящего" % theme.id)

	var attack_lengths: Array = []
	var schemes := ["Авторитет", "Статистика", "Пример", "Традиция",
		"Определение", "Здравый смысл", "Аналогия", "Эмоция"]
	for i in 8:
		var sample := Nar.new()
		sample.start(theme, 30300 + i, {"you": "contra", "opp": "pro"})
		var sample_axis: Dictionary = theme.axes[i % theme.axes.size()]
		var sample_target := {"axis": String(sample_axis.id), "gist": String(sample_axis.pro),
			"device": String(schemes[i])}
		var sample_card := Deck.make_card(Cards.TYPE_RAZBOR, i)
		var sample_line: String = sample.preview_refute_exact("you", "чужая рамка", sample_target,
			sample_card, false, {"preferred_axes": [String(sample_axis.id)]}).text
		attack_lengths.append(sample_line.length())
	var attack_max := 0
	var attack_total := 0
	for n in attack_lengths:
		attack_max = maxi(attack_max, int(n))
		attack_total += int(n)
	var attack_avg := float(attack_total) / float(attack_lengths.size())
	print("  %s: разборы avg %.1f · max %d знаков" % [theme.id, attack_avg, attack_max])
	_check(attack_max <= 155 and attack_avg <= 105.0,
		"%s: полные Разборы не превращаются в абзацы" % theme.id)


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % ["OK" if ok else "FAIL", label])
	if not ok:
		failures += 1
