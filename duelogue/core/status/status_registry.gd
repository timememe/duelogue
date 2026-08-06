extends RefCounted

## DUELOGUE — КАТАЛОГ ПЕРКОВ/ДЕБАФОВ (статусов) v0.1, фундамент (брейншторм-сессия).
## Только данные: что за статус, какой он прочности/источника, и что нести коннектору
## нужной системы. Реестр формы payload не знает и не проверяет — это дело коннектора
## (см. zal_status_bridge.gd); status_rules.gd занимается только жизненным циклом записи
## (apply/remove/tick), тоже не заглядывая внутрь payload.
##
## Разметка по двум осям, зафиксированная в сессии:
## - durability — фундаментальный (навсегда, не снимается) / основной (стартовый, может
##   быть изменён или снят) / временный (тикает, снимается сам);
## - source — исходящий (свой, без участия оппонента) / входящий (от оппонента или
##   внешних условий).
## Первый пилот подключён только к одной геймплейной системе — залу (rules_core.zal_bias),
## через target_system="zal" и payload={field:"zal_bias", value:int}. Другие системы
## (эмоции, колода, рука) получат СВОИ коннекторы со своей формой payload, когда до них
## дойдёт очередь — сознательно не унифицируем заранее.

const DURABILITY_FUNDAMENTAL := "fundamental"
const DURABILITY_BASE := "base"
const DURABILITY_TEMPORARY := "temporary"

const SOURCE_OUTGOING := "outgoing"
const SOURCE_INCOMING := "incoming"

const POLARITY_PERK := "perk"
const POLARITY_DEBUFF := "debuff"

## По одной записи на каждую из 6 ячеек durability×source — разметка-образец с прошлого
## шага брейншторма, все нацелены на "zal" (единственный подключённый коннектор пилота).
## "turns" читается только для DURABILITY_TEMPORARY.
const CATALOG := {
	"unbending": {
		"label": "Несгибаемый", "polarity": POLARITY_PERK,
		"durability": DURABILITY_FUNDAMENTAL, "source": SOURCE_OUTGOING,
		"target_system": "zal", "payload": {"field": "zal_bias", "value": 1},
	},
	"tainted_name": {
		"label": "Подмоченное имя", "polarity": POLARITY_DEBUFF,
		"durability": DURABILITY_FUNDAMENTAL, "source": SOURCE_INCOMING,
		"target_system": "zal", "payload": {"field": "zal_bias", "value": -1},
	},
	"prepared_opening": {
		"label": "Заготовленный аргумент", "polarity": POLARITY_PERK,
		"durability": DURABILITY_BASE, "source": SOURCE_OUTGOING,
		"target_system": "zal", "payload": {"field": "zal_bias", "value": 1},
	},
	"rumor_hit": {
		"label": "Подмочен слухами", "polarity": POLARITY_DEBUFF,
		"durability": DURABILITY_BASE, "source": SOURCE_INCOMING,
		"target_system": "zal", "payload": {"field": "zal_bias", "value": -1},
	},
	"ovation": {
		"label": "Овация", "polarity": POLARITY_PERK,
		"durability": DURABILITY_TEMPORARY, "source": SOURCE_OUTGOING,
		"target_system": "zal", "payload": {"field": "zal_bias", "value": 1}, "turns": 2,
	},
	"booed": {
		"label": "Освистан", "polarity": POLARITY_DEBUFF,
		"durability": DURABILITY_TEMPORARY, "source": SOURCE_INCOMING,
		"target_system": "zal", "payload": {"field": "zal_bias", "value": -1}, "turns": 2,
	},
}


static func has(id: String) -> bool:
	return CATALOG.has(id)


## Копия записи каталога — вызывающий код может её как угодно читать, не портя CATALOG.
static func get_entry(id: String) -> Dictionary:
	return (CATALOG.get(id, {}) as Dictionary).duplicate(true)
