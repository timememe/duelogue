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

	# Содержательный HIT без записи ANSWER_OF — сильный Разбор, но LINK не открывает.
	var authority := _thesis("Авторитет")
	var source := _attack("Источник?")
	_check(Grammar.hit(authority, source) and not Grammar.has_route(authority, source),
		"HIT без записи ANSWER_OF не обещает ответа (неполный срез маршрутов честен)")

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
