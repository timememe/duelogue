extends SceneTree

## Чистый smoke эмоционального ядра: шкала, вероятность, конечная субколода, разрядка,
## cooldown, независимость копий сторон и тематическая независимость текста.
## Запуск: godot --headless --script res://duelogue/tools/emotion_smoke.gd

const EmotionCore := preload("res://duelogue/core/emotion/emotion_core.gd")
const DefaultDeck := preload("res://duelogue/core/emotion/reaction_decks/volatile_default.gd")

var failures := 0


func _init() -> void:
	print("\n=== EMOTION CORE · SMOKE ===")
	_test_curve()
	_test_deck_contract()
	_test_state_and_reaction()
	_test_reaction_relation()
	_test_finite_independent_decks()
	print("=== ИТОГ: %s ===" % ("OK" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)


func _test_curve() -> void:
	var core := EmotionCore.new()
	var last := -1.0
	for strain in EmotionCore.MAX_STRAIN + 1:
		var p: float = core.chance_for(strain)
		_check(p >= last, "вероятность монотонна на %d/6" % strain)
		last = p
	_check(core.chance_for(0) == 0.0 and core.chance_for(6) == 1.0,
		"края шкалы: спокойно 0%, максимум 100%")


func _test_deck_contract() -> void:
	var data := DefaultDeck.data()
	var seen := {}
	var stimuli := ["argument_lost", "frame_lost", "captured", "attack_stalled", "dirty_hit",
		"clinch_pressure", "reaction_received"]
	var parry_seen := {}
	_check(not (data.parries as Array).is_empty(), "архетип задаёт спокойные парировки")
	for raw_parry in data.parries:
		var parry: Dictionary = raw_parry
		var parry_id := String(parry.get("id", ""))
		_check(parry_id != "" and not parry_seen.has(parry_id),
			"у парировки уникальный id: %s" % parry_id)
		parry_seen[parry_id] = true
		_check(String(parry.get("text", "")).length() <= 150,
			"парировка %s помещается в микросцену" % parry_id)
	for raw in data.cards:
		var card: Dictionary = raw
		var id := String(card.get("id", ""))
		_check(id != "" and not seen.has(id), "у реакции уникальный id: %s" % id)
		seen[id] = true
		var templates: Dictionary = card.get("templates", {})
		for stimulus in stimuli:
			_check(templates.has(stimulus) and not (templates[stimulus] as Array).is_empty(),
				"%s покрывает stimulus %s" % [id, stimulus])
			for line in templates.get(stimulus, []):
				_check(String(line).length() <= 150,
					"%s/%s помещается в микросцену" % [id, stimulus])


func _test_state_and_reaction() -> void:
	var core := EmotionCore.new()
	core.start(DefaultDeck.data(), 20260713, ["you", "opp"])
	var low: Dictionary = core.observe("you", "argument_lost", 3,
		{"target": "проверочная рамка"}, 0.99)
	_check(int(low.before) == 0 and int(low.peak) == 3 and int(low.after) == 3,
		"стимул накапливает напряжение без ложной реакции")
	_check((low.reaction as Dictionary).is_empty(), "roll выше шанса не вызывает срыв")

	var burst: Dictionary = core.observe("you", "frame_lost", 3,
		{"target": "проверочная рамка"}, 0.99)
	var reaction: Dictionary = burst.reaction
	_check(int(burst.peak) == 6 and not reaction.is_empty(),
		"на максимуме реакция гарантирована")
	_check(int(burst.after) < int(burst.peak), "реакция разряжает шкалу")
	_check(String(reaction.text).find("{target}") < 0, "контекстный слот заполнен")
	_check(int(core.state("you").reactions) == 1, "счётчик реакций обновлён")

	var cooled: Dictionary = core.observe("you", "argument_lost", 3, {}, 0.0)
	_check((cooled.reaction as Dictionary).is_empty(),
		"cooldown защищает от частокола реакций даже при roll=0")
	_check(int(cooled.peak) < EmotionCore.MAX_STRAIN,
		"во время cooldown шкала не показывает ложные 6/6")
	var after_cooldown: Dictionary = core.observe("you", "clinch_pressure", 1, {}, 0.0)
	_check(int(after_cooldown.peak) == EmotionCore.MAX_STRAIN and
		not (after_cooldown.reaction as Dictionary).is_empty(),
		"после разрядки достижение 6/6 снова гарантирует реакцию")


func _test_reaction_relation() -> void:
	var calm := EmotionCore.new()
	calm.start(DefaultDeck.data(), 120, ["you", "opp"])
	var calm_draw := int(calm.state("opp").draw_left)
	var parry: Dictionary = calm.answer_reaction("opp", {"target": "проверочная рамка"}, 0.0)
	_check(String(parry.kind) == "parry" and not (parry.parry as Dictionary).is_empty(),
		"спокойная сторона парирует чужой срыв")
	_check(int(calm.state("opp").strain) == 0 and int(calm.state("opp").draw_left) == calm_draw,
		"парировка не нагревает шкалу и не тратит реакционную карту")
	_check(int(calm.state("opp").parries) == 1,
		"ядро считает спокойные ответы отдельно от срывов")
	_check(String((parry.parry as Dictionary).text).find("{target}") < 0,
		"парировка получает контекст цели")

	var warm := EmotionCore.new()
	warm.start(DefaultDeck.data(), 121, ["you", "opp"])
	warm.observe("opp", "argument_lost", 2, {}, 0.99)
	var pressure: Dictionary = warm.answer_reaction("opp", {}, 0.99)
	_check(String(pressure.kind) == "absorb" and int(pressure.delta) == 0 and
		int(pressure.after) == 2,
		"середина шкалы выдерживает чужой срыв без самоподогрева")

	var hot := EmotionCore.new()
	hot.start(DefaultDeck.data(), 122, ["you", "opp"])
	hot.observe("opp", "argument_lost", 4, {}, 0.99)
	var triggered: Dictionary = hot.answer_reaction("opp", {"target": "проверочная рамка"}, 0.0)
	_check(String(triggered.kind) == "trigger" and int(triggered.delta) == 1 and
		int(triggered.peak) == 5,
		"на 4/6 чужой срыв даёт вероятностный триггер")
	_check(not (triggered.reaction as Dictionary).is_empty() and
		String((triggered.reaction as Dictionary).stimulus) == "reaction_received",
		"триггер вытаскивает контекстную карту ответа")
	_check(int(hot.state("opp").linked_reactions) == 1,
		"ядро считает ответные срывы отдельно")

	var brink := EmotionCore.new()
	brink.start(DefaultDeck.data(), 123, ["you", "opp"])
	brink.observe("opp", "argument_lost", 5, {}, 0.99)
	var guaranteed: Dictionary = brink.answer_reaction("opp", {}, 0.99)
	_check(String(guaranteed.kind) == "trigger" and int(guaranteed.peak) == 6,
		"на 5/6 чужой срыв гарантированно запускает ответ")


func _test_finite_independent_decks() -> void:
	var core := EmotionCore.new()
	var data := DefaultDeck.data()
	var deck_size := (data.cards as Array).size()
	core.start(data, 77, ["you", "opp"])
	var before_opp := int(core.state("opp").draw_left)
	# Две проверки: первая копит до 6, вторая гарантированно берёт одну карту.
	core.observe("you", "captured", 3, {}, 0.99)
	var got: Dictionary = core.observe("you", "captured", 3, {}, 0.99)
	_check(not (got.reaction as Dictionary).is_empty(), "из субколоды взята карта")
	_check(int(core.state("you").draw_left) == deck_size - 1,
		"субколода конечна: карта ушла из добора")
	_check(int(core.state("opp").draw_left) == before_opp,
		"у сторон независимые копии субколоды")


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % ["OK" if ok else "FAIL", label])
	if not ok:
		failures += 1
