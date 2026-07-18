extends Node

## Ступень 1 комбо-лестницы (combo_grammar_v0.2 §13.1): онтология и чистый matcher БЕЗ
## механики. Проверяет тегирование фабрики, функции §3 на синтетических картах, сторожей
## §12 и эквивалентность полей карты старым name-мапам нарратива (ванильная регрессия).
## Запуск:
##   Godot --headless --path . res://duelogue/tools/combo_grammar_smoke.tscn

const RulesCore := preload("res://duelogue/core/rules/rules_core.gd")
const Deck := preload("res://duelogue/core/cards/deck.gd")
const Grammar := preload("res://duelogue/core/cards/grammar.gd")
const NarEngine := preload("res://duelogue/core/narrative/narrative_engine.gd")
const AiCore := preload("res://duelogue/core/ai/ai.gd")

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("\n=== COMBO GRAMMAR SMOKE ===")
	_check_factory_tagging()
	_check_matcher_routes()
	_check_guards()
	_check_narrative_equivalence()
	_check_fields_survive_zones()
	_check_state_machine()
	print("=== COMBO GRAMMAR: %s ===\n" % ("OK" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures += 1


## Синтетический протегированный Тезис нужной схемы (как его создала бы фабрика).
func _thesis(scheme: String) -> Dictionary:
	return {"type": Deck.TYPE_TEZIS, "name": "T:" + scheme, "steals": false,
		"scheme": scheme, "suit": String(Grammar.SUIT_OF.get(scheme, "")),
		"combo_eligible": true}


## Синтетический протегированный Разбор нужного приёма.
func _attack(device: String) -> Dictionary:
	return {"type": Deck.TYPE_RAZBOR, "name": "R:" + device, "steals": false,
		"device": device, "hook": String(Grammar.HOOK_OF.get(device, "")),
		"combo_eligible": true}


func _check_factory_tagging() -> void:
	var side: Dictionary = Deck.build_side(3, 8, 9, 1, 2, 5)
	var all_cards: Array = []
	all_cards.append_array(side.hand)
	all_cards.append_array(side.draw)
	var t_ok := true
	var r_ok := true
	var kraja_ok := true
	var u_ok := true
	for raw in all_cards:
		var card: Dictionary = raw
		match String(card.get("type", "")):
			Deck.TYPE_TEZIS:
				t_ok = t_ok and bool(card.get("combo_eligible", false)) \
					and Grammar.SUIT_OF.has(String(card.get("scheme", ""))) \
					and String(card.get("suit", "")) == \
						String(Grammar.SUIT_OF.get(String(card.get("scheme", "")), "?"))
			Deck.TYPE_RAZBOR:
				if bool(card.get("steals", false)):
					kraja_ok = kraja_ok and not bool(card.get("combo_eligible", false)) \
						and not card.has("hook")
				else:
					r_ok = r_ok and bool(card.get("combo_eligible", false)) \
						and Grammar.HOOK_OF.has(String(card.get("device", ""))) \
						and String(card.get("hook", "")) == \
							String(Grammar.HOOK_OF.get(String(card.get("device", "")), "?"))
			Deck.TYPE_USTANOVKA:
				u_ok = u_ok and not bool(card.get("combo_eligible", false))
	_check(t_ok, "каждый Тезис колоды протегирован scheme+suit и combo_eligible")
	_check(r_ok, "каждый обычный Разбор протегирован device+hook и combo_eligible")
	_check(kraja_ok, "Кража — присвоение, не зацепка: без hook и без combo_eligible")
	_check(u_ok, "Установки в грамматику не входят")
	var filler: Dictionary = Deck.filler_thesis()
	_check(not bool(filler.get("combo_eligible", true)) and not filler.has("scheme"),
		"технический тезис Базы без схемы: рамка не становится случайной схемой")


func _check_matcher_routes() -> void:
	# Три маршрута §5: setup → правильная зацепка → правильный ответ.
	var routes := [
		["Аналогия", "Контрпример", "Авторитет", "exception_noted"],
		["Традиция", "Софизм?", "Определение", "borders_restored"],
		["Эмоция", "Не в кассу", "Пример", "about_people"],
	]
	var all_ok := true
	for spec in routes:
		var setup: Dictionary = _thesis(spec[0])
		var opener: Dictionary = _attack(String(Grammar.CARD_DEVICE.get(spec[1], spec[1])))
		var answer: Dictionary = _thesis(spec[2])
		var r: Dictionary = Grammar.route(setup, opener)
		all_ok = all_ok and Grammar.hit(setup, opener) and Grammar.has_route(setup, opener) \
			and String(r.get("route_id", "")) == String(spec[3]) \
			and Grammar.answers(setup, opener, answer) \
			and Grammar.triple(setup, opener, answer)
	_check(all_ok, "три маршрута §5 собираются: HIT → ROUTE → ANSWERS → TRIPLE")

	# Полный каталог: КАЖДАЯ содержательная пара OPEN_HOOKS имеет маршрут с валидными
	# схемами ответов, route_id уникальны и каждая схема хотя бы где-то является ответом —
	# любая карта обоймы участвует в комбо той или иной стороной.
	var full := true
	var route_ids := {}
	var answer_cover := {}
	var pair_count := 0
	for scheme in Grammar.OPEN_HOOKS:
		for hook in Grammar.OPEN_HOOKS[scheme]:
			pair_count += 1
			var rec: Dictionary = (Grammar.ANSWER_OF.get(scheme, {}) as Dictionary) \
				.get(hook, {})
			full = full and not rec.is_empty()
			var rid := String(rec.get("route_id", ""))
			full = full and rid != "" and not route_ids.has(rid) and \
				String(rec.get("combo_name", "")) != ""
			route_ids[rid] = true
			var answer_list: Array = rec.get("answer_schemes", [])
			full = full and not answer_list.is_empty()
			for ans in answer_list:
				full = full and Grammar.SUIT_OF.has(String(ans))
				answer_cover[String(ans)] = true
	full = full and pair_count == 20 and route_ids.size() == 20 and \
		answer_cover.size() == Grammar.SUIT_OF.size()
	_check(full, "полный каталог: 20 пар покрыты, route_id уникальны, все схемы бывают ответом")

	# MISS: зацепка не берёт схему — маршрута нет тем более.
	var tradition := _thesis("Традиция")
	var counterexample := _attack("Контрпример")
	_check(not Grammar.hit(tradition, counterexample) and
		not Grammar.has_route(tradition, counterexample),
		"MISS: закрытая зацепка не образует ни HIT, ни маршрут")

	# Неправильный ответ на открытый маршрут — ANSWERS false (незакрытый LINK будущего).
	var analogy := _thesis("Аналогия")
	var opener_ce := _attack("Контрпример")
	_check(Grammar.has_route(analogy, opener_ce) and
		not Grammar.answers(analogy, opener_ce, _thesis("Статистика")),
		"неправильная схема ответа не закрывает маршрут")


func _check_guards() -> void:
	# Сторож §12: combo_eligible=false не входит в matcher, даже с полями схемы.
	var fake_base := {"type": Deck.TYPE_TEZIS, "name": "База", "scheme": "Аналогия",
		"combo_eligible": false}
	var opener := _attack("Контрпример")
	_check(not Grammar.hit(fake_base, opener),
		"combo_eligible=false никогда не входит в matcher (даже с полем схемы)")

	# Кража и безхуковый Разбор («И что?» будущего сет-листа) не открывают грамматику.
	var kraja := {"type": Deck.TYPE_RAZBOR, "name": "Кража", "steals": true}
	var safe_poke := {"type": Deck.TYPE_RAZBOR, "name": "И что?", "steals": false,
		"combo_eligible": false}
	var analogy := _thesis("Аналогия")
	_check(Grammar.hook_of(kraja) == "" and not Grammar.hit(analogy, kraja) and
		Grammar.hook_of(safe_poke) == "" and not Grammar.hit(analogy, safe_poke),
		"Кража и safe poke без зацепки не открывают LINK")

	# Ответ чужого типа (Разбор вместо Тезиса) не может закрыть маршрут.
	var opener_ce := _attack("Контрпример")
	_check(not Grammar.answers(analogy, opener_ce, _attack("Источник?")),
		"закрыть маршрут может только Тезис-ответ")


func _check_narrative_equivalence() -> void:
	# Поле карты и старый name-fallback дают ОДИН приём для каждого имени колоды —
	# ванильные реплики не меняются (ступень 1 без изменений поведения).
	var nar: RefCounted = NarEngine.new()
	var all_equal := true
	for i in Deck.TEZIS_NAMES.size():
		var tagged: Dictionary = Deck.make_card(Deck.TYPE_TEZIS, i)
		var bare := {"type": Deck.TYPE_TEZIS, "name": tagged.name, "steals": false}
		all_equal = all_equal and nar.device_label(tagged) == nar.device_label(bare)
	for i in Deck.RAZBOR_NAMES.size():
		var tagged: Dictionary = Deck.make_card(Deck.TYPE_RAZBOR, i)
		var bare := {"type": Deck.TYPE_RAZBOR, "name": tagged.name, "steals": false}
		all_equal = all_equal and nar.device_label(tagged) == nar.device_label(bare)
	_check(all_equal, "поле карты ≡ name-fallback для всех имён колоды (реплики прежние)")


## Модель со включённым клинчем (те же параметры, что боевой смоук).
func _combo_model() -> RefCounted:
	var model := RulesCore.new()
	model.reset(RulesCore.SIDE_YOU, 3, 8, 9, 5, 1, 0, 2, 0, true, true,
		1, 2, 4, 0, 1, 0, 1, true)
	return model


func _plain_line(name: String) -> Dictionary:
	return {"theses": 1, "closed": false, "name": name, "stolen": 0}


## Рамка с протегированным setup-Тезисом сверху (§2: верхняя карта — публичный довод).
func _setup_frame(scheme: String, thesis_id: String) -> Dictionary:
	var top := _thesis(scheme)
	top["thesis_id"] = thesis_id
	return {"theses": 1, "closed": false, "name": "Setup", "stolen": 0,
		"thesis_stack": [top]}


## Собрать доску сценария §9: атакующий YOU с заготовленной рукой против setup-рамки.
func _scenario(setup_scheme: String, you_hand: Array, opp_hand: Array) -> RefCounted:
	var model := _combo_model()
	model.sides[RulesCore.SIDE_YOU].lines = [_plain_line("Атакующий")]
	model.sides[RulesCore.SIDE_OPP].lines = [
		_setup_frame(setup_scheme, "setup_top"), _plain_line("Тыл")]
	model.sides[RulesCore.SIDE_YOU].hand = you_hand
	model.sides[RulesCore.SIDE_YOU].draw = []
	model.sides[RulesCore.SIDE_OPP].hand = opp_hand
	model.sides[RulesCore.SIDE_OPP].draw = []
	model.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, false, 0)
	return model


## Машина состояний §4 на сценариях бумаги A0 (§9). Payoff пока не применяется:
## проверяем только LINK/ARMED/CONFIRMED/BREAK, owner, exact closer и телеметрию.
func _check_state_machine() -> void:
	# Сценарий 1 — минимальная тройка: LINK → правильный ответ → ARMED → пас → CONFIRMED.
	var s1: RefCounted = _scenario("Аналогия", [_attack("Контрпример")], [_thesis("Авторитет")])
	var s1_link: bool = String(s1.clinch.get("combo_state", "")) == "link"
	var s1_hold: Dictionary = s1.clinch_submit("play", false, 0)
	var s1_armed: bool = String(s1.clinch.get("combo_state", "")) == "armed" and \
		String(s1.clinch.get("combo_owner", "")) == RulesCore.SIDE_OPP and \
		String(s1.clinch.get("closer_thesis_id", "")) == String(s1_hold.get("thesis_id", ""))
	var s1_info: Dictionary = s1.clinch_submit("pass").get("info", {})
	_check(s1_link and s1_armed and
		String(s1_info.get("combo_result", "")) == "confirmed" and
		String(s1_info.get("combo_owner", "")) == RulesCore.SIDE_OPP and
		String(s1_info.get("combo_name", "")) == "Исключение учтено" and
		String(s1_info.get("combo_route_id", "")) == "exception_noted" and
		String((s1_info.get("opening_anchor", {}) as Dictionary).get(
			"thesis_id", "")) == "setup_top",
		"сценарий 1: LINK → ARMED → CONFIRMED; owner и exact closer зафиксированы")

	# Сценарий 2 — незакрытый LINK: неправильный ответ не вооружает, комбо нет.
	var s2: RefCounted = _scenario("Аналогия", [_attack("Контрпример")], [_thesis("Статистика")])
	s2.clinch_submit("play", false, 0)
	var s2_link_kept: bool = String(s2.clinch.get("combo_state", "")) == "link"
	var s2_info: Dictionary = s2.clinch_submit("pass").get("info", {})
	_check(s2_link_kept and String(s2_info.get("combo_result", "")) == "none" and
		String(s2_info.get("combo_state", "")) == "link",
		"сценарий 2: неправильный ответ оставляет незакрытый LINK — комбо не считается")

	# Сценарий 3 — dropped combo: атакующий перестоял ARMED, exact closer снят → BREAK.
	var s3: RefCounted = _scenario("Аналогия",
		[_attack("Контрпример"), _attack("Источник?")], [_thesis("Авторитет")])
	s3.clinch_submit("play", false, 0)
	s3.clinch_submit("play", false, 0)
	var s3_resolved: Dictionary = s3.clinch_submit("pass")
	var s3_info: Dictionary = s3_resolved.get("info", {})
	var s3_seq: Array = s3_info.get("resolved_sequence", [])
	_check(String(s3_info.get("combo_result", "")) == "break" and
		bool(s3_resolved.get("landed", false)) and
		String((s3_seq[1] as Dictionary).get("result", "")) == "removed",
		"сценарий 3: перестоял ARMED — exact closer снят, ставка сгорает в BREAK")

	# Сценарий 4 — донести финишер: доп. обычный T защищает ставку, owner не переписан.
	var s4: RefCounted = _scenario("Аналогия",
		[_attack("Контрпример"), _attack("Источник?")],
		[_thesis("Авторитет"), _thesis("Статистика")])
	var s4_hold: Dictionary = s4.clinch_submit("play", false, 0)
	s4.clinch_submit("play", false, 0)
	s4.clinch_submit("play", false, 0)
	var s4_closer_kept: bool = String(s4.clinch.get("closer_thesis_id", "")) == \
		String(s4_hold.get("thesis_id", ""))
	var s4_info: Dictionary = s4.clinch_submit("pass").get("info", {})
	_check(s4_closer_kept and String(s4_info.get("combo_result", "")) == "confirmed" and
		String(s4_info.get("combo_owner", "")) == RulesCore.SIDE_OPP,
		"сценарий 4: вложенный T доносит ставку — CONFIRMED, owner остаётся у финишера")

	# Сторожа §12 на машине: Кража не открывает LINK; техтезис сверху гасит anchor;
	# HIT без маршрута ANSWER_OF остаётся сильным Разбором без LINK.
	var g1: RefCounted = _scenario("Аналогия",
		[{"type": Deck.TYPE_RAZBOR, "name": "Кража", "steals": true}], [])
	var g1_none: bool = String(g1.clinch.get("combo_state", "")) == "none"
	g1.clinch_submit("pass")
	var g2 := _combo_model()
	g2.sides[RulesCore.SIDE_YOU].lines = [_plain_line("Атакующий")]
	var buried := _setup_frame("Аналогия", "buried_scheme")
	var filler: Dictionary = Deck.filler_thesis()
	filler["thesis_id"] = "filler_top"
	(buried.thesis_stack as Array).append(filler)
	buried["theses"] = 2
	g2.sides[RulesCore.SIDE_OPP].lines = [buried, _plain_line("Тыл")]
	g2.sides[RulesCore.SIDE_YOU].hand = [_attack("Контрпример")]
	g2.sides[RulesCore.SIDE_YOU].draw = []
	g2.sides[RulesCore.SIDE_OPP].hand = []
	g2.sides[RulesCore.SIDE_OPP].draw = []
	g2.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, false, 0)
	var g2_no_anchor: bool = (g2.clinch.get("opening_anchor", {}) as Dictionary).is_empty() \
		and String(g2.clinch.get("combo_state", "")) == "none"
	g2.clinch_submit("pass")
	var g3: RefCounted = _scenario("Аналогия", [_attack("Передёрг")], [])
	var g3_anchor: Dictionary = g3.clinch.get("opening_anchor", {})
	var g3_miss_no_link: bool = not g3_anchor.is_empty() and \
		not bool(g3_anchor.get("hit", true)) and \
		String(g3.clinch.get("combo_state", "")) == "none"
	g3.clinch_submit("pass")
	_check(g1_none and g2_no_anchor and g3_miss_no_link,
		"сторожа: Кража, техтезис и MISS-зацепка не открывают LINK")

	# Мини-шаг ступени 4: ИИ-защитник выбирает exact правильный ответ на открытый LINK.
	var picker: RefCounted = AiCore.new()
	var s5: RefCounted = _scenario("Аналогия", [_attack("Контрпример")],
		[_thesis("Статистика"), _thesis("Авторитет")])
	var pick: int = picker.def_answer_index(s5, RulesCore.SIDE_OPP)
	s5.clinch_submit("play", false, pick)
	var s5_armed: bool = String(s5.clinch.get("combo_state", "")) == "armed"
	s5.clinch_submit("pass")
	_check(pick == 1 and s5_armed,
		"ИИ-защитник закрывает LINK exact правильной картой и вооружает ставку")


func _check_fields_survive_zones() -> void:
	# Сторож §12: карта сохраняет scheme/hook во всех зонах — рука → рамка → кража на
	# чужую доску → снятие в сброс. Поля читаются с exact объекта в каждой точке.
	var model := RulesCore.new()
	model.reset(RulesCore.SIDE_YOU, 3, 8, 9, 5, 1, 0, 2, 0, true, true,
		1, 2, 4, 0, 1, 0, 1, true)
	model.sides[RulesCore.SIDE_YOU].lines = [
		{"theses": 1, "closed": false, "name": "Атакующий", "stolen": 0}]
	model.sides[RulesCore.SIDE_OPP].lines = [
		{"theses": 1, "closed": false, "name": "Цель", "stolen": 0},
		{"theses": 1, "closed": false, "name": "Тыл", "stolen": 0}]
	var defense := _thesis("Авторитет")
	model.sides[RulesCore.SIDE_YOU].hand = [
		{"type": Deck.TYPE_RAZBOR, "name": "Кража", "steals": true},
		{"type": Deck.TYPE_RAZBOR, "name": "Кража", "steals": true}]
	model.sides[RulesCore.SIDE_YOU].draw = []
	model.sides[RulesCore.SIDE_OPP].hand = [defense]
	model.sides[RulesCore.SIDE_OPP].draw = []
	model.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, true, 0)
	var hold: Dictionary = model.clinch_submit("play", false, 0)
	var on_frame: Dictionary = model.sides[RulesCore.SIDE_OPP].lines[0].thesis_stack[-1]
	var frame_keeps: bool = String(on_frame.get("scheme", "")) == "Авторитет" and \
		bool(on_frame.get("combo_eligible", false))
	model.clinch_submit("play", true, 0)
	model.clinch_submit("pass")
	# Пресс-Кража украла exact ответ на активную рамку вора: поля целы и там.
	var loot: Dictionary = model.sides[RulesCore.SIDE_YOU].lines[-1].thesis_stack[-1]
	var loot_keeps: bool = String(loot.get("thesis_id", "")) == \
		String(hold.get("thesis_id", "")) and \
		String(loot.get("scheme", "")) == "Авторитет" and \
		String(loot.get("suit", "")) == "ethos" and bool(loot.get("combo_eligible", false))
	_check(frame_keeps and loot_keeps,
		"scheme/suit/eligible живут на exact объекте: рука → рамка → кража на чужую доску")
