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
	_test_shared_situational_pool()
	_test_state_and_reaction()
	_test_reaction_relation()
	_test_finite_independent_decks()
	_test_snap()
	_test_relieve()
	_test_extended_range_and_breakdown()
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
		"clinch_pressure", "reaction_received", "situational_hit"]
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
		_check(not (card.get("hand_templates", []) as Array).is_empty(),
			"%s имеет текст осознанной карты из той же темы" % id)
		for hand_line in card.get("hand_templates", []):
			_check(String(hand_line).length() <= 150,
				"%s/hand помещается на карту в руке" % id)
		var templates: Dictionary = card.get("templates", {})
		for stimulus in stimuli:
			_check(templates.has(stimulus) and not (templates[stimulus] as Array).is_empty(),
				"%s покрывает stimulus %s" % [id, stimulus])
			for line in templates.get(stimulus, []):
				_check(String(line).length() <= 150,
					"%s/%s помещается в микросцену" % [id, stimulus])


func _test_shared_situational_pool() -> void:
	var core := EmotionCore.new()
	core.start(DefaultDeck.data(), 20260831, ["you", "opp"])
	var before := int(core.state("you").draw_left)
	var card: Dictionary = core.draw_situational("you", "единая колода", 2)
	_check(not card.is_empty() and String(card.text).find("{target}") < 0,
		"осознанная карта реализуется из reaction-definition и получает контекст")
	var after := core.state("you")
	_check(int(after.draw_left) == before - 1 and int(after.discarded) == 1 and
		int(after.situational_draws) == 1,
		"карта руки изымается из того же конечного draw/discard, что автосрыв")
	_check(String(card.id) in ["sarcastic_applause", "cold_laugh", "audience_check"],
		"на раннем накале доступны только лёгкие реакции min_strain=2")


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

	# Большая intensity гарантированно упирается в cooldown-потолок (MAX_STRAIN-1) независимо
	# от того, сколько именно vent снял предыдущий вытянутый card — тот же приём, что раньше
	# работал на масштабе 0..6, просто пересчитан под расширенный диапазон (§8).
	var cooled: Dictionary = core.observe("you", "argument_lost", EmotionCore.MAX_STRAIN, {}, 0.0)
	_check((cooled.reaction as Dictionary).is_empty(),
		"cooldown защищает от частокола реакций даже при roll=0")
	_check(int(cooled.peak) < EmotionCore.MAX_STRAIN,
		"во время cooldown шкала не показывает ложный потолок")
	_check(int(cooled.peak) == EmotionCore.MAX_STRAIN - 1,
		"cooldown-потолок держит строго на MAX_STRAIN-1")
	# intensity=0: чистая проверка «шанс уже гарантирован» без риска зацепить breakdown
	# (potolok+1 читался бы как КО, а не как обычная гарантированная реакция).
	var after_cooldown: Dictionary = core.observe("you", "clinch_pressure", 0, {}, 0.0)
	_check(int(after_cooldown.peak) == EmotionCore.MAX_STRAIN - 1 and
		not (after_cooldown.reaction as Dictionary).is_empty() and
		not bool(after_cooldown.breakdown),
		"после разрядки достижение горячей зоны снова гарантирует обычную реакцию, не КО")


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


func _test_snap() -> void:
	var core := EmotionCore.new()
	core.start(DefaultDeck.data(), 456, ["you", "opp"])
	_check(not core.can_snap("you"), "кнопка недоступна на пустой шкале")

	core.observe("you", "argument_lost", 4, {}, 0.99)
	_check(not core.can_snap("you"), "кнопка недоступна ниже порога (4/6)")

	core.observe("you", "argument_lost", 1, {}, 0.99)
	_check(int(core.state("you").strain) == EmotionCore.SNAP_THRESHOLD,
		"шкала дошла ровно до порога кнопки")
	_check(core.can_snap("you"), "кнопка доступна на пороге (5/6)")
	_check(bool(core.state("you").can_snap), "state() отражает доступность кнопки")

	var empty_snap: Dictionary = EmotionCore.new().snap("you")
	_check(empty_snap.is_empty(), "snap() без предварительного start()/can_snap возвращает {}")

	var result: Dictionary = core.snap("you", {"target": "проверочная рамка"})
	_check(int(result.before) == EmotionCore.SNAP_THRESHOLD and int(result.after) == 0,
		"снап гарантированно и полностью сбрасывает шкалу")
	_check(float(result.chance) == 1.0 and float(result.roll) == 0.0,
		"снап возвращает форму observe() для переиспользования _resolve_emotion_result")
	var reaction: Dictionary = result.reaction
	_check(not reaction.is_empty() and int(reaction.vent) == EmotionCore.SNAP_THRESHOLD,
		"снап венти всю накопленную шкалу, а не частично как обычная карта")
	_check(String(reaction.text).find("{target}") < 0, "контекстный слот заполнен")
	_check(int(core.state("you").snaps) == 1, "счётчик снапов обновлён")
	_check(not core.can_snap("you"),
		"сразу после снапа кнопка недоступна — тот же cooldown, что у обычной реакции")

	var again: Dictionary = core.snap("you")
	_check(again.is_empty(), "повторный снап во время cooldown нелегален и возвращает {}")


## emotion_reactions.md v0.5 §7 «Трение и исход»: relieve() — sibling snap() в другую сторону,
## явное облегчение без карты/шанса/броска. Проверяет только контракт ядра; кто и почему зовёт
## relieve() (клинч, победа) решает battle_controller, не тестируется здесь.
func _test_relieve() -> void:
	var empty_relief: Dictionary = EmotionCore.new().relieve("you", 3)
	_check(empty_relief.is_empty(), "relieve() без предварительного start() возвращает {}")

	var core := EmotionCore.new()
	core.start(DefaultDeck.data(), 789, ["you", "opp"])
	var raised: Dictionary = core.observe("you", "argument_lost", 5, {}, 0.99)
	_check(int(raised.after) == 5 and (raised.reaction as Dictionary).is_empty(),
		"подготовка: шкала поднята без карты (высокий roll)")

	var result: Dictionary = core.relieve("you", 2)
	_check(int(result.before) == 5 and int(result.after) == 3 and int(result.delta) == -2,
		"relieve() снижает strain ровно на amount")
	_check(String(result.stimulus) == "relief",
		"relieve() без явного stimulus подписывается как relief")
	_check((result.reaction as Dictionary).is_empty() and float(result.chance) == 0.0 and
		float(result.roll) == -1.0, "relieve() никогда не бросает и не тянет карту")
	_check(int(core.state("you").strain) == 3, "state() видит облегчённую шкалу")

	var draw_before := int(core.state("you").draw_left)
	var labeled: Dictionary = core.relieve("you", 1, "clinch_won")
	_check(String(labeled.stimulus) == "clinch_won",
		"relieve() принимает произвольный stimulus-лейбл")
	_check(int(core.state("you").draw_left) == draw_before,
		"relieve() не трогает реакционную колоду")

	var floored: Dictionary = core.relieve("you", 999)
	_check(int(floored.after) == 0, "relieve() не уводит strain ниже нуля")

	var zero: Dictionary = core.relieve("opp", 5)
	_check(int(zero.before) == 0 and int(zero.after) == 0,
		"relieve() на нулевой шкале — безопасный no-op")


## situational_cards_v0.1 §8: шкала растянута на две зоны (самообладание/раздражение),
## КО на потолке. Проверяет расширенный диапазон, шов-без-стены и терминальный breakdown.
func _test_extended_range_and_breakdown() -> void:
	_check(EmotionCore.MAX_STRAIN == 12 and EmotionCore.ZONE_WIDTH == 6,
		"шкала растянута на 12 при ширине зоны 6")
	var curve := EmotionCore.new()
	for strain in range(EmotionCore.ZONE_WIDTH, EmotionCore.MAX_STRAIN + 1):
		_check(curve.chance_for(strain) == 1.0,
			"раздражение держит гарантированный триггер на strain %d" % strain)

	var core := EmotionCore.new()
	core.start(DefaultDeck.data(), 2026, ["you", "opp"])
	var mid: Dictionary = core.observe("you", "argument_lost", 4, {}, 1.0)
	_check(int(mid.peak) == 4 and not bool(mid.breakdown), "на 4/12 срыва ещё нет")
	var mid_state := core.state("you")
	_check(int(mid_state.composure) == 2 and int(mid_state.irritation) == 0,
		"4/12 читается как самообладание 2/6")

	var spill: Dictionary = core.observe("you", "argument_lost", 5, {}, 1.0)
	_check(int(spill.peak) == 9 and not bool(spill.breakdown),
		"один стимул перепрыгивает шов из самообладания в раздражение за шаг")
	var spill_state := core.state("you")
	_check(int(spill_state.composure) == 0 and int(spill_state.irritation) == 3,
		"9/12 читается как раздражение 3/6")

	var relief: Dictionary = core.observe("you", "reaction_received", 0, {}, 0.0)
	_check(not (relief.reaction as Dictionary).is_empty() and int(relief.after) < int(relief.peak),
		"гарантированная реакция вентит раздражение так же, как самообладание")
	var relief_state := core.state("you")
	if int(relief_state.strain) <= EmotionCore.ZONE_WIDTH:
		_check(int(relief_state.irritation) == 0,
			"вент увёл достаточно глубоко — раздражение снова 0")
	else:
		_check(int(relief_state.irritation) < 3, "вент хотя бы частично отступил из раздражения")

	var brink := EmotionCore.new()
	brink.start(DefaultDeck.data(), 2027, ["you", "opp"])
	brink.observe("you", "argument_lost", 6, {}, 1.0)
	brink.observe("you", "argument_lost", 5, {}, 1.0)
	var ko: Dictionary = brink.observe("you", "argument_lost", 1, {}, 1.0)
	_check(bool(ko.breakdown) and int(ko.peak) == EmotionCore.MAX_STRAIN,
		"12/12 раздражения — гарантированный эмоц. КО")
	_check(int(ko.after) == EmotionCore.MAX_STRAIN,
		"на КО шкала остаётся на потолке — вентить уже нечего")
	_check(not (ko.reaction as Dictionary).is_empty() and
		String((ko.reaction as Dictionary).mood) == "breakdown",
		"КО возвращает терминальную реплику, а не обычную карту")
	_check(bool(brink.state("you").breakdown), "state() тоже видит breakdown=true")


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % ["OK" if ok else "FAIL", label])
	if not ok:
		failures += 1
