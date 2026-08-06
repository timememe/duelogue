extends Node

## DUELOGUE — GENERIC PATTERN BUILDER PROBE (feasibility-прототип, план см.
## .claude/plans/snappy-foraging-papert.md): сверяет
## combo_pattern_builder.build_guard()/build_trap() поле-в-поле с руками написанными
## P_DOMAIN_MATCH_GUARD/TRAP и P_MECHANISM_SHOWN(_ANALOGY)_GUARD/TRAP
## (combo_register.gd) — доказательство, что generic-генератор воспроизводит ту же
## форму, что и текущие константы, для обоих структурных случаев каталога (одна
## answer-схема / две answer-схемы на один route_id).
##
## combo_name передаётся из самой эталонной константы (а не транскрибируется руками) —
## это флейвор-текст, не то, что генератор обязан угадывать; проверяется структурная
## форма (arbitration/seed/path/where/claim), а не авторство названия.
##
## Изолирован: не трогает A3_CATALOG/RESERVED_A3_CATALOG и не подключается к боевому
## runtime. Отдельно проверяет specificity="any" — сравнивать не с чем (это новое
## поведение), проверяется только структурная валидность.
## Запуск: res://duelogue/tools/combo_pattern_builder_probe.tscn, F6 (или headless).

const ComboRegister := preload("res://duelogue/core/rules/combo_register.gd")
const Builder := preload("res://duelogue/core/rules/combo_pattern_builder.gd")

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("\n=== COMBO PATTERN BUILDER PROBE ===")
	_check_equivalent("domain_match_guard",
		Builder.build_guard("domain_match_guard", "Авторитет", "уместность", "Определение",
			ComboRegister.P_DOMAIN_MATCH_GUARD.combo_name),
		ComboRegister.P_DOMAIN_MATCH_GUARD)
	_check_equivalent("domain_match_trap",
		Builder.build_trap("domain_match_trap", "Авторитет", "уместность", "Определение",
			ComboRegister.P_DOMAIN_MATCH_TRAP.combo_name),
		ComboRegister.P_DOMAIN_MATCH_TRAP)
	_check_equivalent("mechanism_shown_guard",
		Builder.build_guard("mechanism_shown_guard", "Статистика", "связь", "Пример",
			ComboRegister.P_MECHANISM_SHOWN_GUARD.combo_name),
		ComboRegister.P_MECHANISM_SHOWN_GUARD)
	_check_equivalent("mechanism_shown_trap",
		Builder.build_trap("mechanism_shown_trap", "Статистика", "связь", "Пример",
			ComboRegister.P_MECHANISM_SHOWN_TRAP.combo_name),
		ComboRegister.P_MECHANISM_SHOWN_TRAP)
	_check_equivalent("mechanism_shown_analogy_guard",
		Builder.build_guard("mechanism_shown_analogy_guard", "Статистика", "связь", "Аналогия",
			ComboRegister.P_MECHANISM_SHOWN_ANALOGY_GUARD.combo_name),
		ComboRegister.P_MECHANISM_SHOWN_ANALOGY_GUARD)
	_check_equivalent("mechanism_shown_analogy_trap",
		Builder.build_trap("mechanism_shown_analogy_trap", "Статистика", "связь", "Аналогия",
			ComboRegister.P_MECHANISM_SHOWN_ANALOGY_TRAP.combo_name),
		ComboRegister.P_MECHANISM_SHOWN_ANALOGY_TRAP)
	_check_any_specificity()
	print("=== COMBO PATTERN BUILDER PROBE: %s ===\n" % (
		"OK" if failures == 0 else "FAIL (%d)" % failures))
	get_tree().call_deferred("quit", 0 if failures == 0 else 1)


## Сверяет всё, кроме "id" (ярлык на константе, не влияет на матчинг/арбитраж) —
## family/topology/combo_name/scope/arbitration/seed/path/where/claim обязаны совпасть
## побайтово с руками написанной константой.
func _check_equivalent(label: String, built: Dictionary, reference: Dictionary) -> void:
	for key in ["family", "topology", "combo_name", "scope", "arbitration", "seed", "path",
			"where", "claim"]:
		var ok: bool = built.get(key) == reference.get(key)
		_check(ok, "%s: поле %s совпадает с эталоном" % [label, key])


func _check_any_specificity() -> void:
	var built := Builder.build_guard("probe_any_guard", "Авторитет", "уместность", "Определение",
		"Проба: любая схема", "any")
	var reply_card: Dictionary = built.path[1].card
	_check(String(reply_card.get("type", "")) == "T" and not reply_card.has("scheme"),
		"specificity=any: $reply не несёт scheme (любой Тезис годится)")
	_check(built.claim.owner == "B" and built.arbitration.channel == "clinch",
		"specificity=any: форма паттерна (owner/channel) не пострадала")


func _check(ok: bool, label: String) -> void:
	print("  %s · %s" % [label, "OK" if ok else "FAIL"])
	if not ok:
		failures += 1
