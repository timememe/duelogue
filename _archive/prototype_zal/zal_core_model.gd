extends RefCounted

## DUELOGUE — модель сухого ядра «ЗАЛ» v0.2.
## Спека: context/zal_core_v0.2.md. Чистая логика без UI.
## Используется сценой zal_core.gd (ручная игра) и zal_core_sim.gd (AI vs AI метрики).
## НЕ зависит от основного движка (core/, autoloads/).

# --- Константы тюнинга (раздел 8 спеки) ---
const ROOM_MAX := 9
const TURN_CAP := 24
const BASE_SWAY := 2
const CHAIN_CAP := 3
const PAIR_BONUS := 4
const HAND_SIZE := 5
const KOMI := 1               ## стартовое смещение зала в пользу ходящего вторым

const SIDE_YOU := "you"
const SIDE_OPP := "opp"

const STANCE_COLD := "cold"
const STANCE_HOT := "hot"

## DECK_SIZE = 12: 6 cold / 6 hot, без дублей (раздел 3 спеки).
const CARDS := [
	{"id": "false_dilemma", "name": "Ложная дилемма", "stance": "cold", "quote": "Либо с нами, либо нет"},
	{"id": "straw_man", "name": "Соломенное чучело", "stance": "cold", "quote": "Ты предлагаешь всё снести?"},
	{"id": "reductio", "name": "Reductio ad absurdum", "stance": "cold", "quote": "Доведём до абсурда"},
	{"id": "counterexample", "name": "Контрпример", "stance": "cold", "quote": "А вот случай иной"},
	{"id": "authority", "name": "К авторитету", "stance": "cold", "quote": "Это доказано наукой"},
	{"id": "clarification", "name": "Уточнение", "stance": "cold", "quote": "Определимся с терминами"},
	{"id": "ad_hominem", "name": "Ad hominem", "stance": "hot", "quote": "Что ты понимаешь?"},
	{"id": "ad_populum", "name": "Ad populum", "stance": "hot", "quote": "Все это понимают"},
	{"id": "sarcasm", "name": "Сарказм", "stance": "hot", "quote": "Ну да, гениально"},
	{"id": "anecdote", "name": "Личная история", "stance": "hot", "quote": "У меня было так же"},
	{"id": "slippery_slope", "name": "Скользкая дорожка", "stance": "hot", "quote": "Дальше — только хуже"},
	{"id": "hyperbole", "name": "Гипербола", "stance": "hot", "quote": "Это катастрофа!"},
]

## PAIR_COUNT = 3: пара живёт внутри одной стихии (раздел 5 спеки).
const PAIRS := [
	{"a": "Уточнение", "b": "Reductio ad absurdum", "name": "Логический капкан", "col": "4c7cd9"},
	{"a": "Личная история", "b": "Гипербола", "name": "Эмоциональный шквал", "col": "d9594c"},
	{"a": "Ad populum", "b": "Ad hominem", "name": "Двойной охват", "col": "d9594c"},
]

var room := 0                 ## [-ROOM_MAX..+ROOM_MAX], плюс — сторона игрока
var half_turns := 0           ## сыграно карт обеими сторонами суммарно
var sudden_death := false     ## кап исчерпан при зале 0 — следующий качок решает
var game_over := false
var winner := ""              ## SIDE_YOU | SIDE_OPP
var end_reason := ""          ## "edge" | "cap" | "sudden_death"
var next_side := SIDE_YOU
var sides := {}               ## side -> {draw, hand, discard, thread, chain, chain_stance, pairs_fired}


func reset(first_side: String) -> void:
	# Коми: компенсация темпа — маркер стартует на 1 в сторону ходящего вторым.
	room = -KOMI if first_side == SIDE_YOU else KOMI
	half_turns = 0
	sudden_death = false
	game_over = false
	winner = ""
	end_reason = ""
	next_side = first_side
	sides = {
		SIDE_YOU: _new_side_state(),
		SIDE_OPP: _new_side_state(),
	}


func full_turns() -> int:
	return half_turns / 2


func other(side: String) -> String:
	return SIDE_OPP if side == SIDE_YOU else SIDE_YOU


## Предпросмотр хода БЕЗ мутации состояния. Источник истины для UI-цифры на карте
## и ghost-маркера: play() использует тот же расчёт, расхождение невозможно.
func preview(side: String, hand_index: int) -> Dictionary:
	var s: Dictionary = sides[side]
	if hand_index < 0 or hand_index >= s.hand.size():
		return {}
	return _compute_play(s, s.hand[hand_index])


## Сыграть карту. Возвращает результат для лога/метрик:
## {card, chain, bonus, base_swing, total_swing, pair, pair_fired, room_before, room_after}
func play(side: String, hand_index: int) -> Dictionary:
	if game_over:
		return {}
	var s: Dictionary = sides[side]
	if hand_index < 0 or hand_index >= s.hand.size():
		return {}
	var card: Dictionary = s.hand[hand_index]
	var calc := _compute_play(s, card)

	s.hand.remove_at(hand_index)
	s.chain = calc.chain
	s.chain_stance = String(card["stance"])
	s.thread.append(card)

	var room_before := room
	_apply_swing(side, calc.base_swing)
	# Бонус пары не начисляется, если базовый качок уже выиграл партию.
	var pair_fired: bool = not calc.pair.is_empty() and not game_over
	if pair_fired:
		s.pairs_fired += 1
		_apply_swing(side, PAIR_BONUS)

	s.discard.append(card)
	_draw_one(s)

	half_turns += 1
	next_side = other(side)

	if not game_over and sudden_death and room != 0:
		_finish(SIDE_YOU if room > 0 else SIDE_OPP, "sudden_death")
	if not game_over and half_turns >= TURN_CAP * 2:
		_resolve_cap()

	calc["pair_fired"] = pair_fired
	calc["room_before"] = room_before
	calc["room_after"] = room
	return calc


## Пара карты (карта — половинка A или B), иначе пустой словарь.
func pair_of(card: Dictionary) -> Dictionary:
	for p in PAIRS:
		if String(p["a"]) == String(card["name"]) or String(p["b"]) == String(card["name"]):
			return p
	return {}


func partner_name(card: Dictionary) -> String:
	var p := pair_of(card)
	if p.is_empty():
		return ""
	return String(p["b"]) if String(p["a"]) == String(card["name"]) else String(p["a"])


## Где сейчас партнёр пары: "hand" | "draw" | "discard" | "" (карта без пары).
func partner_location(side: String, card: Dictionary) -> String:
	var partner := partner_name(card)
	if partner == "":
		return ""
	var s: Dictionary = sides[side]
	for zone in ["hand", "draw", "discard"]:
		for c in s[zone]:
			if String(c["name"]) == partner:
				return zone
	return ""


## true, если карта прямо сейчас завершит именную пару.
func pair_ready(side: String, card: Dictionary) -> bool:
	return not _pair_completed_by(sides[side], card).is_empty()


## AI: завершить пару сейчас > лучший качок + задел под пару − сжигание второй половины.
func ai_choose(side: String) -> int:
	var s: Dictionary = sides[side]
	if s.hand.is_empty():
		return -1
	for i in s.hand.size():
		if not _pair_completed_by(s, s.hand[i]).is_empty():
			return i
	var best := 0
	var best_score := -INF
	for i in s.hand.size():
		var card: Dictionary = s.hand[i]
		var calc := _compute_play(s, card)
		var score := float(calc.total_swing)
		var p := pair_of(card)
		if not p.is_empty() and _hand_has(s, partner_name(card)):
			if String(p["a"]) == String(card["name"]):
				score += 1.5  # сыграть A — заделать пару на следующий свой ход
			else:
				score -= 1.0  # не сжигай B, пока A в руке
		score += randf() * 0.8
		if score > best_score:
			best_score = score
			best = i
	return best


# --- внутреннее ---

func _new_side_state() -> Dictionary:
	var draw: Array = CARDS.duplicate()
	draw.shuffle()
	var hand: Array = []
	for i in HAND_SIZE:
		hand.append(draw.pop_back())
	return {
		"draw": draw,
		"hand": hand,
		"discard": [],
		"thread": [],
		"chain": 0,
		"chain_stance": "",
		"pairs_fired": 0,
	}


func _compute_play(s: Dictionary, card: Dictionary) -> Dictionary:
	var chain := 1
	if s.chain_stance == String(card["stance"]):
		chain = int(s.chain) + 1
	var bonus: int = mini(chain - 1, CHAIN_CAP)
	var pair := _pair_completed_by(s, card)
	var base_swing: int = BASE_SWAY + bonus
	var total: int = base_swing + (PAIR_BONUS if not pair.is_empty() else 0)
	return {
		"card": card,
		"chain": chain,
		"bonus": bonus,
		"pair": pair,
		"base_swing": base_swing,
		"total_swing": total,
	}


func _pair_completed_by(s: Dictionary, card: Dictionary) -> Dictionary:
	if s.thread.is_empty():
		return {}
	var prev_name := String(s.thread[-1]["name"])
	for p in PAIRS:
		if String(p["a"]) == prev_name and String(p["b"]) == String(card["name"]):
			return p
	return {}


func _apply_swing(side: String, amount: int) -> void:
	var delta := amount if side == SIDE_YOU else -amount
	room = clampi(room + delta, -ROOM_MAX, ROOM_MAX)
	if game_over:
		return
	if room >= ROOM_MAX:
		_finish(SIDE_YOU, "edge")
	elif room <= -ROOM_MAX:
		_finish(SIDE_OPP, "edge")


func _resolve_cap() -> void:
	if room > 0:
		_finish(SIDE_YOU, "cap")
	elif room < 0:
		_finish(SIDE_OPP, "cap")
	else:
		sudden_death = true


func _finish(win_side: String, reason: String) -> void:
	game_over = true
	winner = win_side
	end_reason = reason


func _draw_one(s: Dictionary) -> void:
	if s.draw.is_empty():
		# Решафл StS: сброс становится добором.
		s.draw = s.discard
		s.discard = []
		s.draw.shuffle()
	if not s.draw.is_empty():
		s.hand.append(s.draw.pop_back())


func _hand_has(s: Dictionary, card_name: String) -> bool:
	for c in s.hand:
		if String(c["name"]) == card_name:
			return true
	return false
