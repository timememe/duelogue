class_name CardInstance
extends RefCounted

var data: CardData
var uses_left: int
var from_discard: bool = false
var current_variant_index: int = 0


func _init(card_data: CardData = null) -> void:
	if card_data:
		data = card_data
		uses_left = card_data.max_uses


func get_text() -> String:
	if data.text_variants.size() > 0:
		var idx := clampi(current_variant_index, 0, data.text_variants.size() - 1)
		return data.text_variants[idx]
	return data.text


func use() -> bool:
	uses_left -= 1
	return uses_left <= 0


func is_used() -> bool:
	return uses_left <= 0


func clone() -> CardInstance:
	var inst := CardInstance.new(data)
	inst.from_discard = from_discard
	inst.current_variant_index = current_variant_index
	return inst
