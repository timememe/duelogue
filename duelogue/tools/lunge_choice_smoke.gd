extends Node

## Smoke «Выпада» (context/situational_cards_v0.1.md §3): чистый сборщик оффера
## core/cards/lunge_choice.gd. Без AI/UI/RulesCore — синтетический снимок клинча + рука.
## Ветку lunge_counter в clinch_submit проверяет battle_loop_rules_smoke.gd.
## Запуск:
##   Godot --headless --path . res://duelogue/tools/lunge_choice_smoke.tscn

const LungeChoice := preload("res://duelogue/core/cards/lunge_choice.gd")
const Grammar := preload("res://duelogue/core/cards/grammar.gd")

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("\n=== LUNGE CHOICE SMOKE ===")
	_check_inactive_without_link()
	_check_inactive_after_first_answer()
	_check_answer_plus_decoy()
	_check_steal_slot()
	_check_needs_two_slots()
	_check_decoy_never_frame()
	_check_decoy_distinct_from_answer()
	_check_route_name()
	print("=== LUNGE CHOICE: %s ===\n" % ("OK" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures += 1


## Синтетический протегированный Тезис нужной схемы.
func _thesis(scheme: String) -> Dictionary:
	return {"type": "T", "name": "T:" + scheme, "steals": false, "scheme": scheme,
		"combo_eligible": true}


## Синтетический протегированный Разбор нужного приёма.
func _attack(device: String) -> Dictionary:
	return {"type": "R", "name": "R:" + device, "steals": false, "device": device,
		"hook": String(Grammar.HOOK_OF.get(device, "")), "combo_eligible": true}


func _kraja() -> Dictionary:
	return {"type": "R", "name": "Кража", "steals": true, "combo_eligible": false}


func _frame() -> Dictionary:
	return {"type": "U", "name": "Установка", "steals": false}


## Клинч на открытом LINK: рамку с Тезисом схемы setup_scheme бьёт ⚡-Разбор device.
## Маршрут Авторитет+"Источник?" → answer_schemes ["Статистика"] (Grammar.ANSWER_OF).
func _link_clinch(setup_scheme: String, device: String) -> Dictionary:
	var opener := _attack(device)
	return {
		"combo_state": "link", "t_added": 0, "r_count": 1,
		"sequence": [opener],
		"opening_anchor": {"card": _thesis(setup_scheme)},
		"combo_route": {"combo_name": "Источник подтверждён"},
	}


func _check_inactive_without_link() -> void:
	var hand := [_thesis("Статистика"), _thesis("Эмоция")]
	var no_clinch: Dictionary = LungeChoice.offer({}, hand)
	var not_link := _link_clinch("Авторитет", "Источник?")
	not_link.combo_state = "none"
	var off: Dictionary = LungeChoice.offer(not_link, hand)
	_check(not bool(no_clinch.get("active", true)) and not bool(off.get("active", true)),
		"пустой клинч и combo_state!=link → оффер неактивен")


func _check_inactive_after_first_answer() -> void:
	var clinch := _link_clinch("Авторитет", "Источник?")
	clinch.t_added = 1   ## окно «Выпада» — только первый защитный ответ
	var off: Dictionary = LungeChoice.offer(clinch, [_thesis("Статистика"), _thesis("Эмоция")])
	_check(not bool(off.get("active", true)), "t_added>0 → оффер неактивен (окно закрыто)")


func _check_answer_plus_decoy() -> void:
	var clinch := _link_clinch("Авторитет", "Источник?")
	var hand := [_thesis("Эмоция"), _thesis("Статистика"), _thesis("Аналогия")]
	var off: Dictionary = LungeChoice.offer(clinch, hand)
	var ai := int(off.get("answer_index", -1))
	_check(bool(off.get("active", false)) and ai >= 0
		and String(hand[ai].get("scheme", "")) == "Статистика"
		and int(off.get("decoy_index", -1)) >= 0
		and int(off.get("steal_index", -1)) == -1,
		"link + карта-ответ + ещё Тезисы → active, answer=Статистика, decoy есть, steal нет")


func _check_steal_slot() -> void:
	var clinch := _link_clinch("Авторитет", "Источник?")
	var hand := [_thesis("Эмоция"), _kraja(), _thesis("Аналогия")]
	var off: Dictionary = LungeChoice.offer(clinch, hand)
	var si := int(off.get("steal_index", -1))
	_check(bool(off.get("active", false)) and si >= 0 and bool(hand[si].get("steals", false))
		and int(off.get("answer_index", -1)) == -1,
		"link + Кража в руке (без карты-ответа) → active, steal_index на Кражу")


func _check_needs_two_slots() -> void:
	var clinch := _link_clinch("Авторитет", "Источник?")
	## Только карта-ответ, больше ни Тезиса, ни Кражи → 1 слот → неактивен.
	var off: Dictionary = LungeChoice.offer(clinch, [_thesis("Статистика"), _frame()])
	_check(not bool(off.get("active", true)), "меньше 2 слотов (только ответ) → оффер неактивен")


func _check_decoy_never_frame() -> void:
	var clinch := _link_clinch("Авторитет", "Источник?")
	## Ответ + Кража + куча Установок: decoy обязан остаться -1 (рамкой не жертвуем),
	## оффер всё равно active за счёт answer+steal.
	var hand := [_thesis("Статистика"), _kraja(), _frame(), _frame()]
	var off: Dictionary = LungeChoice.offer(clinch, hand)
	_check(bool(off.get("active", false)) and int(off.get("decoy_index", -1)) == -1
		and int(off.get("answer_index", -1)) >= 0 and int(off.get("steal_index", -1)) >= 0,
		"decoy никогда не Установка: только рамки в остатке → decoy=-1, active по answer+steal")


func _check_decoy_distinct_from_answer() -> void:
	var clinch := _link_clinch("Авторитет", "Источник?")
	## Две карты схемы-ответа: одна уходит в answer, decoy обязан взять другую, не ту же.
	var hand := [_thesis("Статистика"), _thesis("Статистика"), _thesis("Эмоция")]
	var off: Dictionary = LungeChoice.offer(clinch, hand)
	var ai := int(off.get("answer_index", -1))
	var di := int(off.get("decoy_index", -1))
	_check(ai >= 0 and di >= 0 and ai != di, "decoy_index != answer_index")


func _check_route_name() -> void:
	var clinch := _link_clinch("Авторитет", "Источник?")
	var off: Dictionary = LungeChoice.offer(clinch,
		[_thesis("Статистика"), _thesis("Эмоция")])
	_check(String(off.get("route_name", "")) == "Источник подтверждён",
		"route_name берётся из combo_route.combo_name")
