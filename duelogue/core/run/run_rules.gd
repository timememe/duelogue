extends RefCounted

## DUELOGUE — ЧИСТОЕ ЯДРО ПРАВИЛ ЗАБЕГА («Сезон»).
## Единственный источник мета-экономики: репутация, гонорары, страховки поражений,
## атомарные стоимости событий и терминальное условие четвёртого поражения.
##
## Никаких Node/EventBus/UI/async, карты и случайного контента. Методы получают RunState
## и обычные словари, детерминированно меняют состояние и возвращают подробный отчёт —
## один и тот же путь используют run_controller, smoke и headless-симуляторы.

const REP_MIN := -50.0
const REP_MAX := 50.0
const REP_START := 0.0

## Первые три поражения зажигают страховки и пропускают дальше; четвёртое завершает run.
const DEFEAT_MARKS_MAX := 3

## Первые калибровочные цены (zal_run §4.2): по одной точке за покупку.
const CLEAR_MARK_FEE := 6
const CLEAR_MARK_REP := 10.0


## Финальный зал -> репутация. Если формальный исход и знак зала согласны — весь Z,
## если противоречат — Z/2. Ничья ядра имеет zal=0 и даёт 0.
static func reputation_delta(winner: String, final_zal: float) -> float:
	match winner:
		"you":
			return final_zal if final_zal >= 0.0 else final_zal * 0.5
		"opp":
			return final_zal if final_zal <= 0.0 else final_zal * 0.5
		"draw":
			return 0.0
	return 0.0


static func crowd_agrees(winner: String, final_zal: float) -> bool:
	if winner == "draw":
		return is_zero_approx(final_zal)
	return (winner == "you" and final_zal >= 0.0) or \
		(winner == "opp" and final_zal <= 0.0)


## Единственная точка расчёта итогов боевой комнаты.
## report: {winner: you|opp|draw, end_reason, final_zal, fee}.
static func settle_battle(state: RefCounted, report: Dictionary) -> Dictionary:
	if state.over:
		return {"ok": false, "reason": "run_over"}
	var winner := String(report.get("winner", ""))
	if not ["you", "opp", "draw"].has(winner):
		return {"ok": false, "reason": "invalid_winner"}

	var final_zal := float(report.get("final_zal", 0.0))
	var delta := reputation_delta(winner, final_zal)
	var rep_result := apply_reputation_delta(state, delta)
	var marks_before := int(state.defeat_marks)
	var mark_added := false
	var run_failed := false

	if winner == "opp":
		if state.defeat_marks < DEFEAT_MARKS_MAX:
			state.defeat_marks += 1
			mark_added = true
		else:
			# Три страховки уже горят: четвёртое поражение завершает сезон.
			state.over = true
			state.outcome = "defeated"
			run_failed = true

	var fees_before := int(state.fees)
	if winner == "you":
		state.fees += maxi(0, int(report.get("fee", 0)))

	return {
		"ok": true,
		"winner": winner,
		"end_reason": String(report.get("end_reason", "")),
		"final_zal": final_zal,
		"crowd_agrees": crowd_agrees(winner, final_zal),
		"reputation_before": rep_result.before,
		"reputation_delta": delta,
		"reputation_after": rep_result.after,
		"reputation_overflow": rep_result.overflow,
		"defeat_marks_before": marks_before,
		"defeat_mark_added": mark_added,
		"defeat_marks": int(state.defeat_marks),
		"run_failed": run_failed,
		"fee_delta": int(state.fees) - fees_before,
		"fees": int(state.fees),
	}


## Последствие (не покупка): может упереться в кап, избыток забывается.
static func apply_reputation_delta(state: RefCounted, delta: float) -> Dictionary:
	var before := float(state.reputation)
	var raw := before + delta
	var after := clampf(raw, REP_MIN, REP_MAX)
	state.reputation = after
	return {
		"before": before,
		"delta": delta,
		"raw": raw,
		"after": after,
		# signed: +N сгорело выше +50, -N — ниже -50
		"overflow": raw - after,
	}


## Проверить всю сделку ДО списания. cost хранит положительные суммы {fee, rep};
## effects — последствия {fee, rep, clear_defeat}. Покупка ниже нижнего капа запрещена.
static func validate_transaction(state: RefCounted, cost: Dictionary, effects: Dictionary) -> Dictionary:
	if state.over:
		return {"ok": false, "reason": "Забег уже завершён."}
	var fee_cost := maxi(0, int(cost.get("fee", 0)))
	var rep_cost := maxf(0.0, float(cost.get("rep", 0.0)))
	if int(state.fees) < fee_cost:
		return {"ok": false, "reason": "Нужно %d гонораров, у вас %d." % [fee_cost, int(state.fees)]}
	if float(state.reputation) - rep_cost < REP_MIN:
		return {"ok": false, "reason": "Не хватает репутационного запаса: цена %.1f уведёт ниже −50." % rep_cost}
	var clear_n := maxi(0, int(effects.get("clear_defeat", 0)))
	if clear_n > int(state.defeat_marks):
		return {"ok": false, "reason": "Нет горящей точки поражения для очистки."}
	return {"ok": true, "reason": ""}


static func can_afford(state: RefCounted, cost: Dictionary, effects: Dictionary = {}) -> bool:
	return bool(validate_transaction(state, cost, effects).ok)


## Атомарная сделка: сначала полная валидация, потом стоимость и эффекты одним переходом.
static func apply_transaction(state: RefCounted, cost: Dictionary, effects: Dictionary) -> Dictionary:
	var valid := validate_transaction(state, cost, effects)
	if not bool(valid.ok):
		return {"ok": false, "reason": String(valid.reason)}

	var rep_before := float(state.reputation)
	var fees_before := int(state.fees)
	var marks_before := int(state.defeat_marks)
	var fee_cost := maxi(0, int(cost.get("fee", 0)))
	var rep_cost := maxf(0.0, float(cost.get("rep", 0.0)))

	state.fees -= fee_cost
	# Стоимость уже проверена: она не может переполнить нижний кап и списывается целиком.
	state.reputation -= rep_cost

	# Доход/штраф события. Отрицательный fee здесь — последствие, а не покупка; дно 0.
	state.fees = maxi(0, int(state.fees) + int(effects.get("fee", 0)))
	var rep_effect := float(effects.get("rep", 0.0))
	var rep_result := apply_reputation_delta(state, rep_effect)
	var clear_n := maxi(0, int(effects.get("clear_defeat", 0)))
	state.defeat_marks = maxi(0, int(state.defeat_marks) - clear_n)

	return {
		"ok": true,
		"reason": "",
		"cost": cost.duplicate(true),
		"effects": effects.duplicate(true),
		"reputation_before": rep_before,
		"reputation_delta": float(state.reputation) - rep_before,
		"reputation_after": float(state.reputation),
		"reputation_overflow": rep_result.overflow,
		"fee_before": fees_before,
		"fee_delta": int(state.fees) - fees_before,
		"fees": int(state.fees),
		"defeat_marks_before": marks_before,
		"defeat_marks_cleared": marks_before - int(state.defeat_marks),
		"defeat_marks": int(state.defeat_marks),
	}


static func clear_defeat_mark(state: RefCounted, currency: String) -> Dictionary:
	match currency:
		"fee":
			return apply_transaction(state, {"fee": CLEAR_MARK_FEE}, {"clear_defeat": 1})
		"rep":
			return apply_transaction(state, {"rep": CLEAR_MARK_REP}, {"clear_defeat": 1})
	return {"ok": false, "reason": "Неизвестный способ оплаты."}


static func is_run_failed(state: RefCounted) -> bool:
	return bool(state.over) and String(state.outcome) == "defeated"
