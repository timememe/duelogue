extends RefCounted

## DUELOGUE — КОННЕКТОР СТАТУСОВ ↔ ЗАЛ, фундамент пилота перков/дебафов v0.1.
## Единственное место, которое знает форму payload для target_system="zal"
## ({field:"zal_bias", value:int}) — ни status_rules.gd, ни StatusRegistry её не
## интерпретируют, только хранят и раздают как есть.
##
## rules_core остаётся слепым к статусам: получает готовое число через отдельное поле
## model.status_zal_bias (rules_core.gd, рядом с zal_bias), которое пишет ТОЛЬКО этот
## мост — само ядро его не трогает, только читает в zal().
##
## Намеренно не унифицирован с будущими коннекторами других систем (эмоции/колода/рука):
## каждая система получит свой мост со своей формой payload, когда до неё дойдёт очередь.
## Общий здесь — только status_rules.gd (бухгалтерия записей), не форма эффекта.

const StatusRules := preload("res://duelogue/core/status/status_rules.gd")

const TARGET_SYSTEM := "zal"
const FIELD_ZAL_BIAS := "zal_bias"


## Сумма value статусов ОДНОЙ стороны, нацеленных на zal_bias.
static func _side_delta(state: Dictionary, side: String) -> int:
	var total := 0
	for record in StatusRules.active_for(state, side, TARGET_SYSTEM):
		var payload: Dictionary = record.get("payload", {})
		if String(payload.get("field", "")) == FIELD_ZAL_BIAS:
			total += int(payload.get("value", 0))
	return total


## zal_bias ядра — один общий скаляр "+ в пользу you" (rules_core.gd :84-86), поэтому
## вклад opp вычитается из вклада you, а не хранится отдельным числом по стороне.
static func compute(state: Dictionary, side_you: String, side_opp: String) -> int:
	return _side_delta(state, side_you) - _side_delta(state, side_opp)


## Пересчитать и записать в существующую модель. Вызывать на старте боя и на каждый
## begin_turn — model.status_zal_bias сам по себе не меняется, только этим мостом.
static func apply_to_model(state: Dictionary, model: RefCounted,
		side_you: String, side_opp: String) -> void:
	model.status_zal_bias = compute(state, side_you, side_opp)
