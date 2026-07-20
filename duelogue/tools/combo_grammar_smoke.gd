extends Node

## Smoke комбо-лестницы: текущие онтология/matcher/state-machine v0.2 плюс test-only
## A3 fixture-probe из combo_a3_topologies_v0.1 поверх настоящего RulesCore. Его
## exchange-словарь не является production state и не подключён к боевому runtime.
## Также проверяет фабричное тегирование, сторожей и
## эквивалентность полей карты старым name-мапам нарратива (ванильная регрессия).
## Запуск:
##   Godot --headless --path . res://duelogue/tools/combo_grammar_smoke.tscn

const RulesCore := preload("res://duelogue/core/rules/rules_core.gd")
const Deck := preload("res://duelogue/core/cards/deck.gd")
const Grammar := preload("res://duelogue/core/cards/grammar.gd")
const NarEngine := preload("res://duelogue/core/narrative/narrative_engine.gd")
const AiCore := preload("res://duelogue/core/ai/ai.gd")
const A3Probe := preload("res://duelogue/tools/a3_exchange_probe.gd")

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
	_check_a3_topology_probe()
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


# --- A3 v0.1: test-only exchange поверх настоящей физики RulesCore. ---

func _tagged(card: Dictionary, tags: Dictionary) -> Dictionary:
	var out: Dictionary = card.duplicate(true)
	out.merge(tags, true)
	return out


func _a3_r(device: String, tags: Dictionary = {}) -> Dictionary:
	var out := _tagged(_attack(device), {
		"target_frame_ref": "frame_a3",
		"target_claim_ref": "claim_a3",
		"argumentative_thread_id": "thread_a3",
	})
	out.merge(tags, true)
	return out


func _a3_press(device: String, tags: Dictionary = {}) -> Dictionary:
	var out := _a3_r(device, {"target_step": 1})
	out.merge(tags, true)
	return out


func _a3_t(scheme: String, verdict: String, tags: Dictionary = {}) -> Dictionary:
	var out := _tagged(_thesis(scheme), {
		"semantic_verdict": verdict,
		"argumentative_thread_id": "thread_a3",
		"answers_step": 0,
		"supports_claim_ref": "claim_a3",
	})
	out.merge(tags, true)
	return out


func _a3_setup(scheme: String) -> Dictionary:
	var top := _thesis(scheme)
	top["thesis_id"] = "setup_a3"
	return top


func _a3_technical_setup() -> Dictionary:
	var top: Dictionary = Deck.filler_thesis()
	top["thesis_id"] = "technical_a3"
	return top


func _a3_scenario(top: Dictionary, you_hand: Array, opp_hand: Array) -> RefCounted:
	var model := _combo_model()
	model.sides[RulesCore.SIDE_YOU].lines = [_plain_line("Атакующий")]
	model.sides[RulesCore.SIDE_OPP].lines = [{
		"theses": 1,
		"closed": false,
		"name": "A3 target",
		"stolen": 0,
		"frame_id": "frame_a3",
		"claim_id": "claim_a3",
		"thesis_stack": [top.duplicate(true)],
	}, _plain_line("Тыл")]
	model.sides[RulesCore.SIDE_YOU].hand = you_hand
	model.sides[RulesCore.SIDE_YOU].draw = []
	model.sides[RulesCore.SIDE_OPP].hand = opp_hand
	model.sides[RulesCore.SIDE_OPP].draw = []
	model.begin_clinch(RulesCore.SIDE_YOU, RulesCore.SIDE_OPP, 0, false, 0)
	return model


func _a3_observe(model: RefCounted) -> Dictionary:
	return A3Probe.observe(model.clinch.get("opening_anchor", {}),
		model.clinch.get("sequence", []), RulesCore.SIDE_YOU, RulesCore.SIDE_OPP)


func _a3_frame_ids(model: RefCounted) -> Array:
	var ids: Array = []
	for raw in model.sides[RulesCore.SIDE_OPP].lines:
		var line: Dictionary = raw
		if String(line.get("frame_id", "")) != "frame_a3":
			continue
		for card_raw in line.get("thesis_stack", []):
			ids.append(String((card_raw as Dictionary).get("thesis_id", "")))
	return ids


func _a3_finish(model: RefCounted, exchange: Dictionary) -> Dictionary:
	var resolved: Dictionary = model.clinch_submit("pass")
	var info: Dictionary = resolved.get("info", {})
	return {
		"runtime": info,
		"probe": A3Probe.settle(exchange, info, _a3_frame_ids(model)),
		"resolved": resolved,
	}


func _false_independence_t1(extra: Dictionary = {}) -> Dictionary:
	var tags := {
		"a3_trap_route_id": "false_independence",
		"claimed_independent": true,
		"independent_support": false,
	}
	tags.merge(extra, true)
	return _a3_t("Статистика", "SPRUNG", tags)


func _p01_t1() -> Dictionary:
	return _a3_t("Авторитет", "UNRESOLVED", {
		"authority_subtype": "expert",
		"authority_domain": "economics",
		"domain_covers_claim": false,
	})


func _p01_r2() -> Dictionary:
	return _a3_press("Не в кассу", {"challenge_role": "domain_relevance"})


func _check_a3_topology_probe() -> void:
	print("\n--- A3 TOPOLOGY MECHANICS PROBE ---")
	_check_a3_guard()
	_check_a3_trap_both_outcomes()
	_check_a3_contested_both_outcomes()
	_check_a3_rtr_without_anchor()
	_check_a3_rtr_parried()
	_check_a3_upgrade_no_fallback()
	_check_a3_semantic_misses()
	_check_a3_no_sliding_window()


func _check_a3_guard() -> void:
	var t1 := _a3_t("Статистика", "DEFENDED", {
		"a3_guard_route_id": "source_backed",
		"independent_support": true,
	})
	var model := _a3_scenario(_a3_setup("Авторитет"), [_a3_r("Источник?")], [t1])
	model.clinch_submit("play", false, 0)
	var exchange := _a3_observe(model)
	var outcome := _a3_finish(model, exchange)
	var runtime: Dictionary = outcome.runtime
	var probe: Dictionary = outcome.probe
	_check(not (exchange.get("defender_claim", {}) as Dictionary).is_empty() and
		String(probe.get("result", "")) == A3Probe.RESULT_GUARD and
		String(probe.get("owner", "")) == RulesCore.SIDE_OPP and
		int(probe.get("payoff_count", 0)) == 1 and
		String(runtime.get("combo_result", "")) == "confirmed",
		"A3 E1 GUARD: новый exchange и текущий runtime согласны — D защищает exact T₁")


func _check_a3_trap_both_outcomes() -> void:
	var win := _a3_scenario(_a3_setup("Авторитет"),
		[_a3_r("Источник?"), _a3_press("Источник?")], [_false_independence_t1()])
	win.clinch_submit("play", false, 0)
	var armed := _a3_observe(win)
	win.clinch_submit("play", false, 0)
	var win_exchange := _a3_observe(win)
	var win_out := _a3_finish(win, win_exchange)
	var win_probe: Dictionary = win_out.probe
	var win_runtime: Dictionary = win_out.runtime

	var parried := _a3_scenario(_a3_setup("Авторитет"),
		[_a3_r("Источник?"), _a3_press("Источник?")],
		[_false_independence_t1(), _thesis("Определение")])
	parried.clinch_submit("play", false, 0)
	parried.clinch_submit("play", false, 0)
	var parried_exchange := _a3_observe(parried)
	parried.clinch_submit("play", false, 0)
	var parried_out := _a3_finish(parried, parried_exchange)
	var parried_probe: Dictionary = parried_out.probe

	_check(not (armed.get("attacker_claim", {}) as Dictionary).is_empty() and
		String(win_probe.get("result", "")) == A3Probe.RESULT_TRAP and
		String(win_probe.get("owner", "")) == RulesCore.SIDE_YOU and
		int(win_probe.get("payoff_count", 0)) == 1 and
		String(win_runtime.get("combo_result", "")) == "break" and
		String(parried_probe.get("result", "")) == A3Probe.RESULT_ALL_BREAK and
		int(parried_probe.get("payoff_count", 0)) == 0,
		"A3 E2/E3 TRAP: A забирает ловушку, обычный T₃ честно ломает её без смены owner")


func _contested_t1() -> Dictionary:
	return _a3_t("Определение", "CONTESTED", {
		"a3_guard_route_id": "shared_core",
		"a3_trap_route_id": "redrawn_similarity",
		"a3_guard_basis_subclaim_ref": "core",
		"a3_trap_basis_subclaim_ref": "qualifier",
		"semantic_bases": [
			{"id": "core", "role": "shared_core", "predeclared": true,
				"independently_grounded": true, "relevant_to_claim": true},
			{"id": "qualifier", "role": "scope_qualifier", "post_hoc": true,
				"independently_grounded": false, "relevant_to_claim": false},
		],
	})


func _check_a3_contested_both_outcomes() -> void:
	var d_model := _a3_scenario(_a3_setup("Аналогия"),
		[_a3_r("Ложная аналогия")], [_contested_t1()])
	d_model.clinch_submit("play", false, 0)
	var d_exchange := _a3_observe(d_model)
	var d_out := _a3_finish(d_model, d_exchange)
	var d_probe: Dictionary = d_out.probe

	var a_model := _a3_scenario(_a3_setup("Аналогия"),
		[_a3_r("Ложная аналогия"),
			_a3_press("Передёрг", {"targets_subclaim_ref": "qualifier"})],
		[_contested_t1()])
	a_model.clinch_submit("play", false, 0)
	a_model.clinch_submit("play", false, 0)
	var a_exchange := _a3_observe(a_model)
	var a_out := _a3_finish(a_model, a_exchange)
	var a_probe: Dictionary = a_out.probe

	_check(not (d_exchange.get("defender_claim", {}) as Dictionary).is_empty() and
		not (d_exchange.get("attacker_claim", {}) as Dictionary).is_empty() and
		String(d_probe.get("result", "")) == A3Probe.RESULT_GUARD and
		String(d_probe.get("winning_basis_subclaim_ref", "")) == "core" and
		String(a_probe.get("result", "")) == A3Probe.RESULT_TRAP and
		String(a_probe.get("winning_basis_subclaim_ref", "")) == "qualifier" and
		int(d_probe.get("payoff_count", 0)) == 1 and int(a_probe.get("payoff_count", 0)) == 1,
		"A3 E4 CONTESTED: одна TRT-вилка платит ровно одной стороне по exact subclaim")


func _check_a3_rtr_without_anchor() -> void:
	var model := _a3_scenario(_a3_technical_setup(),
		[_a3_r("Источник?"), _p01_r2()], [_p01_t1()])
	var watch := _a3_observe(model)
	var no_anchor: bool = (model.clinch.get("opening_anchor", {}) as Dictionary).is_empty()
	model.clinch_submit("play", false, 0)
	var link := _a3_observe(model)
	model.clinch_submit("play", false, 0)
	var armed := _a3_observe(model)
	var outcome := _a3_finish(model, armed)
	var runtime: Dictionary = outcome.runtime
	var probe: Dictionary = outcome.probe

	# Отдельно портим exact effect уже полученного реального sequence: winner недостаточен.
	var bad_info: Dictionary = runtime.duplicate(true)
	var bad_sequence: Array = bad_info.get("resolved_sequence", []).duplicate(true)
	bad_sequence[2]["effect"] = "no_target"
	bad_sequence[2]["affected_thesis_id"] = ""
	bad_info["resolved_sequence"] = bad_sequence
	var bad_probe: Dictionary = A3Probe.settle(armed, bad_info, _a3_frame_ids(model))

	_check(no_anchor and String(watch.get("rtr_state", "")) == "watch" and
		String(link.get("rtr_state", "")) == "link" and
		String(armed.get("rtr_state", "")) == "armed" and
		String(probe.get("result", "")) == A3Probe.RESULT_PRESSURE and
		String(probe.get("route_id", "")) == "P-01" and
		String(runtime.get("combo_result", "")) == "none" and
		String(bad_probe.get("result", "")) == A3Probe.RESULT_ALL_BREAK,
		"A3 E6/E10 RTR: WATCH→LINK→ARMED без T₀-схемы; no_target не получает payoff")


func _check_a3_rtr_parried() -> void:
	var model := _a3_scenario(_a3_technical_setup(),
		[_a3_r("Источник?"), _p01_r2()], [_p01_t1(), _thesis("Определение")])
	model.clinch_submit("play", false, 0)
	model.clinch_submit("play", false, 0)
	var armed := _a3_observe(model)
	model.clinch_submit("play", false, 0)
	var outcome := _a3_finish(model, armed)
	var runtime: Dictionary = outcome.runtime
	var probe: Dictionary = outcome.probe
	var seq: Array = runtime.get("resolved_sequence", [])
	_check(String(armed.get("rtr_state", "")) == "armed" and seq.size() == 4 and
		String((seq[2] as Dictionary).get("result", "")) == "parried" and
		String(probe.get("result", "")) == A3Probe.RESULT_ALL_BREAK and
		int(probe.get("payoff_count", 0)) == 0,
		"A3 E8 RTR parry: обычный T₃ оставляет R₂ parried и сжигает PRESSURE")


func _p06_t1() -> Dictionary:
	return _false_independence_t1({
		"supplies_source_for_step": 0,
		"dataset_ref": "dataset_a",
		"method_ref": "method_a",
		"evidence_role": "causal",
		"causal_claim_ref": "claim_a3",
	})


func _p06_r2() -> Dictionary:
	return _a3_press("Корреляция", {"challenge_role": "correlation_to_cause"})


func _check_a3_upgrade_no_fallback() -> void:
	var win := _a3_scenario(_a3_setup("Авторитет"),
		[_a3_r("Источник?"), _p06_r2()], [_p06_t1()])
	win.clinch_submit("play", false, 0)
	var trap := _a3_observe(win)
	win.clinch_submit("play", false, 0)
	var upgraded := _a3_observe(win)
	var win_out := _a3_finish(win, upgraded)
	var win_probe: Dictionary = win_out.probe

	var parried := _a3_scenario(_a3_setup("Авторитет"),
		[_a3_r("Источник?"), _p06_r2()], [_p06_t1(), _thesis("Определение")])
	parried.clinch_submit("play", false, 0)
	parried.clinch_submit("play", false, 0)
	var parried_upgrade := _a3_observe(parried)
	parried.clinch_submit("play", false, 0)
	var parried_out := _a3_finish(parried, parried_upgrade)
	var parried_probe: Dictionary = parried_out.probe
	var suppressed: Array = upgraded.get("suppressed_claims", [])
	var parried_suppressed: Array = parried_probe.get("suppressed_claims", [])

	_check(String((trap.get("attacker_claim", {}) as Dictionary).get("topology", "")) ==
			"trt_trap" and String((upgraded.get("attacker_claim", {}) as Dictionary).get(
			"topology", "")) == "rtr_pressure" and suppressed.size() == 1 and
		String((suppressed[0] as Dictionary).get("state", "")) == "SUPPRESSED_UPGRADED" and
		String(win_probe.get("result", "")) == A3Probe.RESULT_PRESSURE and
		int(win_probe.get("payoff_count", 0)) == 1 and
		String(parried_probe.get("result", "")) == A3Probe.RESULT_ALL_BREAK and
		parried_suppressed.size() == 1 and int(parried_probe.get("payoff_count", 0)) == 0,
		"A3 E9 upgrade: RTR заменяет TRAP; после parry старый payoff не возвращается")


func _check_a3_semantic_misses() -> void:
	var unresolved_t1 := _a3_t("Статистика", "UNRESOLVED")
	var unresolved := _a3_scenario(_a3_setup("Авторитет"),
		[_a3_r("Источник?")], [unresolved_t1])
	unresolved.clinch_submit("play", false, 0)
	var unresolved_exchange := _a3_observe(unresolved)
	var unresolved_out := _a3_finish(unresolved, unresolved_exchange)
	var unresolved_probe: Dictionary = unresolved_out.probe
	var unresolved_runtime: Dictionary = unresolved_out.runtime

	var wrong_thread_t1 := _p01_t1()
	wrong_thread_t1["argumentative_thread_id"] = "other_thread"
	var wrong_r2 := _p01_r2()
	wrong_r2["argumentative_thread_id"] = "other_thread"
	var wrong_thread := _a3_scenario(_a3_technical_setup(),
		[_a3_r("Источник?"), wrong_r2], [wrong_thread_t1])
	wrong_thread.clinch_submit("play", false, 0)
	wrong_thread.clinch_submit("play", false, 0)
	var miss_exchange := _a3_observe(wrong_thread)
	var miss_out := _a3_finish(wrong_thread, miss_exchange)
	var miss_probe: Dictionary = miss_out.probe

	_check(String(unresolved_runtime.get("combo_result", "")) == "confirmed" and
		String(unresolved_probe.get("result", "")) == A3Probe.RESULT_UNRESOLVED and
		String(miss_probe.get("result", "")) == A3Probe.RESULT_NO_CLAIM and
		String(miss_exchange.get("rtr_state", "")) == "miss",
		"A3 E5/E7 semantics: неизвестность ≠ BREAK, смена thread ≠ PRESSURE")


func _check_a3_no_sliding_window() -> void:
	var model := _a3_scenario(_a3_technical_setup(),
		[_a3_r("Источник?"), _p01_r2(), _a3_press("Источник?")],
		[_p01_t1(), _thesis("Определение")])
	model.clinch_submit("play", false, 0)
	model.clinch_submit("play", false, 0)
	model.clinch_submit("play", false, 0)
	model.clinch_submit("play", false, 0)
	var locked := _a3_observe(model)
	var outcome := _a3_finish(model, locked)
	var probe: Dictionary = outcome.probe
	var live_claims: Array = probe.get("claims", [])

	# Отдельный прогон: первое окно MISS, зато поздние R₂–T₃–R₄ сами выглядят как P-01.
	# First-window policy обязана проигнорировать их полностью, а не просто не удвоить proc.
	var late_t3 := _p01_t1()
	late_t3["answers_step"] = 2
	var late_r4 := _p01_r2()
	late_r4["target_step"] = 3
	var late := _a3_scenario(_a3_technical_setup(),
		[_a3_r("Контрпример"), _a3_press("Источник?"), late_r4],
		[_a3_t("Пример", "UNRESOLVED"), late_t3])
	late.clinch_submit("play", false, 0)
	late.clinch_submit("play", false, 0)
	late.clinch_submit("play", false, 0)
	late.clinch_submit("play", false, 0)
	var late_sequence: Array = late.clinch.get("sequence", [])
	var late_pattern_visible: bool = late_sequence.size() == 5 and \
		Grammar.hook_of(late_sequence[2]) == "источник" and \
		String((late_sequence[3] as Dictionary).get("scheme", "")) == "Авторитет" and \
		int((late_sequence[3] as Dictionary).get("answers_step", -1)) == 2 and \
		Grammar.hook_of(late_sequence[4]) == "уместность" and \
		int((late_sequence[4] as Dictionary).get("target_step", -1)) == 3
	var late_locked := _a3_observe(late)
	var late_out := _a3_finish(late, late_locked)
	var late_probe: Dictionary = late_out.probe
	_check(bool(locked.get("window_locked", false)) and
		String(locked.get("rtr_state", "")) == "armed" and
		(locked.get("defender_claim", {}) as Dictionary).is_empty() and
		not (locked.get("attacker_claim", {}) as Dictionary).is_empty() and
		live_claims.size() == 1 and int(probe.get("payoff_count", 0)) == 1 and
		String(probe.get("result", "")) == A3Probe.RESULT_PRESSURE and
		late_pattern_visible and String(late_locked.get("rtr_state", "")) == "miss" and
		String(late_probe.get("result", "")) == A3Probe.RESULT_NO_CLAIM and
		int(late_probe.get("payoff_count", 0)) == 0,
		"A3 E11 first-window only: R₄ не удваивает proc, поздний валидный RTR не открывается")
