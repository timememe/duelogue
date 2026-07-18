extends RefCounted

## DUELOGUE — КОЛОДА: фабрика карт, имена приёмов, сборка стартовой стороны и добор.
## Чистая, без состояния (статические методы). Читает только общий контракт card_types.
## Вынесено из zal_v3_model.gd (_new_side / _mk / _refill + *_NAMES).

const C := preload("res://duelogue/core/cards/card_types.gd")
const Grammar := preload("res://duelogue/core/cards/grammar.gd")
const TYPE_TEZIS := C.TYPE_TEZIS
const TYPE_RAZBOR := C.TYPE_RAZBOR
const TYPE_USTANOVKA := C.TYPE_USTANOVKA

const TEZIS_NAMES := ["Довод", "Контрфакт", "Аргумент", "Уточнение", "Пример", "Ссылка", "Факт", "Логика"]
const RAZBOR_NAMES := ["Не в кассу", "Передёрг", "Контрпример", "Софизм?", "Источник?", "Подмена", "Мимо", "А докажи"]
const USTANOVKA_NAMES := ["Рамка", "Тезис дня", "Позиция", "Постулат", "Принцип", "Аксиома"]


## Карта колоды по типу и порядковому индексу (имя берётся по кругу из *_NAMES).
## Карта рождается уже протегированной онтологией (grammar.gd): scheme/suit у Тезиса,
## device/hook у Разбора — авторитет данных на самой карте, а не пересчёт по имени.
static func make_card(type: String, i: int) -> Dictionary:
	var nm := ""
	match type:
		TYPE_TEZIS: nm = TEZIS_NAMES[i % TEZIS_NAMES.size()]
		TYPE_RAZBOR: nm = RAZBOR_NAMES[i % RAZBOR_NAMES.size()]
		TYPE_USTANOVKA: nm = USTANOVKA_NAMES[i % USTANOVKA_NAMES.size()]
	var card := {"type": type, "name": nm, "steals": false}
	match type:
		TYPE_TEZIS:
			var scheme := String(Grammar.CARD_SCHEME.get(nm, ""))
			if scheme != "":
				card["scheme"] = scheme
				card["suit"] = String(Grammar.SUIT_OF.get(scheme, ""))
				card["combo_eligible"] = true
		TYPE_RAZBOR:
			var device := String(Grammar.CARD_DEVICE.get(nm, ""))
			if device != "":
				card["device"] = device
				card["hook"] = String(Grammar.HOOK_OF.get(device, ""))
				card["combo_eligible"] = true
	return card


## Технический тезис без карты (стартовые тезисы Базы, ленивые токены стека). Схемы НЕТ
## и combo_eligible=false осознанно (§1.3 грамматики): иначе каждая База случайно стала бы
## конкретной схемой и начала собирать маршруты. Имя совпадает с прежним фабричным.
static func filler_thesis() -> Dictionary:
	return {"type": TYPE_TEZIS, "name": TEZIS_NAMES[0], "steals": false,
		"combo_eligible": false}


## Нейтральный safe poke «И что?» (§5 combo_grammar_v0.2): обычный эффект Разбора, но
## зацепки НЕТ — LINK не открывает и финишер не получает. Осознанный отказ атакующего от
## комбо-потенциала. device задан только голосу нарратива (процедурная манера).
static func safe_poke() -> Dictionary:
	return {"type": TYPE_RAZBOR, "name": "И что?", "steals": false,
		"device": "Не в кассу", "combo_eligible": false}


## Собрать сторону: колода (n_t тезисов, n_r атак из них steal_cards Краж, n_u установок),
## стартовая рамка «База» с base_theses тезисов, пустая рука добитая до hand_size.
static func build_side(n_u: int, n_t: int, n_r: int, base_theses: int, steal_cards: int, hand_size: int) -> Dictionary:
	var draw: Array = []
	for i in n_t:
		draw.append(make_card(TYPE_TEZIS, i))
	# Карты атаки: часть — Кражи (steals), остальные — обычные Разборы.
	var n_steal := clampi(steal_cards, 0, n_r)
	var n_plain := n_r - n_steal
	for i in n_plain:
		draw.append(make_card(TYPE_RAZBOR, i))
	for i in n_steal:
		draw.append({"type": TYPE_RAZBOR, "name": "Кража", "steals": true})
	for i in n_u:
		draw.append(make_card(TYPE_USTANOVKA, i))
	draw.shuffle()
	var s := {
		"lines": [{"theses": maxi(1, base_theses), "closed": false, "name": "База", "stolen": 0}],
		"hand": [],
		"draw": draw,
		"discard": [],   # публичная стопка: потраченные атаки, сбитые тезисы, павшие рамки
		"sw_used": 0,    # сколько раз сторона брала «второе дыхание» из сброса
		"passed": false,
		"recovery_pending": false,
	}
	refill(s, hand_size)
	return s


## Opening с осознанной страховкой: ровно одна уже существующая Установка гарантированно
## остаётся в стартовой руке и занимает обычный слот. Остальные стартовые карты берутся
## только из T/R; оставшиеся U возвращаются в добор ПОСЛЕ раздачи. Размер и состав обоймы
## не меняются — меняется лишь стартовый порядок. Возвращает саму карту резерва либо {}.
static func prepare_opening_reserve(side: Dictionary, hand_size: int) -> Dictionary:
	var pool: Array = []
	pool.append_array(side.get("hand", []))
	pool.append_array(side.get("draw", []))
	var frames: Array = []
	var actions: Array = []
	for raw in pool:
		var card: Dictionary = raw
		card.erase("opening_reserve")
		card.erase("recovery_ready")
		if String(card.get("type", "")) == TYPE_USTANOVKA:
			frames.append(card)
		else:
			actions.append(card)
	frames.shuffle()
	actions.shuffle()
	var hand: Array = []
	var reserve := {}
	if not frames.is_empty() and hand_size > 0:
		reserve = frames.pop_back()
		reserve["opening_reserve"] = true
		hand.append(reserve)
	while hand.size() < hand_size and not actions.is_empty():
		hand.append(actions.pop_back())
	# Нестандартная маленькая обойма может не набрать H только действиями — тогда добиваем
	# оставшимися рамками, не создавая новых карт из воздуха.
	while hand.size() < hand_size and not frames.is_empty():
		hand.append(frames.pop_back())
	var draw: Array = []
	draw.append_array(actions)
	draw.append_array(frames)
	draw.shuffle()
	side["hand"] = hand
	side["draw"] = draw
	side["recovery_pending"] = false
	return reserve


## Добор стороны до hand_size из её колоды (тянет с конца — колода уже перетасована).
static func refill(side: Dictionary, hand_size: int) -> void:
	while side.hand.size() < hand_size and not side.draw.is_empty():
		side.hand.append(side.draw.pop_back())
