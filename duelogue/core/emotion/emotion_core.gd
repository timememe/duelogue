extends RefCounted

## DUELOGUE — ЧИСТОЕ ЯДРО ЭМОЦИОНАЛЬНОГО НАПРЯЖЕНИЯ v0.1.
##
## Вход: уже разрешённый боевой stimulus + интенсивность. Выход: новое состояние шкалы и,
## возможно, одна карта из конечной субколоды реакций. Ядро НЕ знает о теме, картах основной
## колоды, зале, рамках, UI и async; v0.1 не имеет механических последствий для боя.
##
## У каждой стороны своя шкала и своя копия одной data-колоды. Срыв вероятностный, но
## телеграфируемый шкалой; после реакции напряжение разряжается, карта уходит в сброс,
## следующая эмоциональная проверка защищена cooldown — частокол реплик не возникает.

const MAX_STRAIN := 6
const CHANCE_BY_STRAIN := [0.0, 0.0, 0.05, 0.15, 0.30, 0.55, 1.0]

var deck_id := ""
var deck_label := ""
var _deck_cards: Array = []
var _states := {}
var _rng := RandomNumberGenerator.new()


func start(deck_data: Dictionary, seed_value: int, sides: Array = ["you", "opp"]) -> void:
	deck_id = String(deck_data.get("id", "reactions"))
	deck_label = String(deck_data.get("label", deck_id))
	_deck_cards = (deck_data.get("cards", []) as Array).duplicate(true)
	_states = {}
	_rng.seed = seed_value
	for side in sides:
		var draw := _deck_cards.duplicate(true)
		_shuffle(draw)
		_states[String(side)] = {
			"strain": 0,
			"draw": draw,
			"discard": [],
			"cooldown": 0,
			"reactions": 0,
		}


func chance_for(strain: int) -> float:
	return float(CHANCE_BY_STRAIN[clampi(strain, 0, MAX_STRAIN)])


func state(side: String) -> Dictionary:
	if not _states.has(side):
		return {
			"strain": 0, "max": MAX_STRAIN, "chance": 0.0,
			"draw_left": 0, "discarded": 0, "cooldown": 0, "reactions": 0,
			"deck_id": deck_id, "deck_label": deck_label,
		}
	var s: Dictionary = _states[side]
	return {
		"strain": int(s.strain),
		"max": MAX_STRAIN,
		"chance": chance_for(int(s.strain)),
		"draw_left": (s.draw as Array).size(),
		"discarded": (s.discard as Array).size(),
		"cooldown": int(s.cooldown),
		"reactions": int(s.reactions),
		"deck_id": deck_id,
		"deck_label": deck_label,
	}


## Зарегистрировать эмоциональный стимул. roll_override ∈ [0,1] позволяет симулятору
## воспроизводимо проверять политику вероятности; отрицательное значение использует RNG.
## Возвращает:
## {before, peak, after, delta, chance, roll, stimulus, reaction, cooldown, exhausted}.
func observe(side: String, stimulus: String, intensity: int = 1,
	context: Dictionary = {}, roll_override: float = -1.0) -> Dictionary:
	if not _states.has(side):
		return {}
	var s: Dictionary = _states[side]
	var before := int(s.strain)
	var delta := clampi(intensity, 0, MAX_STRAIN)
	var was_cooling := int(s.cooldown) > 0
	# Пока идёт одно-событийная разрядка, напряжение продолжает расти, но визуально не
	# достигает 6/6. Так полный столб всегда означает немедленный гарантированный срыв,
	# а не скрыто заблокированный cooldown.
	var cap := MAX_STRAIN - 1 if was_cooling else MAX_STRAIN
	s.strain = clampi(before + delta, 0, cap)
	var peak := int(s.strain)
	var chance := 0.0 if was_cooling else chance_for(peak)
	if was_cooling:
		s.cooldown = int(s.cooldown) - 1
	var roll := clampf(roll_override, 0.0, 1.0) if roll_override >= 0.0 else _rng.randf()
	var reaction := {}
	if not was_cooling and roll < chance:
		var idx := _eligible_index(s.draw, stimulus, peak)
		if idx >= 0:
			var card: Dictionary = (s.draw as Array)[idx]
			(s.draw as Array).remove_at(idx)
			(s.discard as Array).append(card)
			reaction = _realize(card, stimulus, context)
			var vent := maxi(0, int(card.get("vent", 3)))
			s.strain = maxi(0, int(s.strain) - vent)
			s.cooldown = 1
			s.reactions = int(s.reactions) + 1
	return {
		"side": side,
		"stimulus": stimulus,
		"before": before,
		"peak": peak,
		"after": int(s.strain),
		"delta": delta,
		"chance": chance,
		"roll": roll,
		"reaction": reaction,
		"cooldown": int(s.cooldown),
		"exhausted": (s.draw as Array).is_empty(),
		"draw_left": (s.draw as Array).size(),
	}


func _eligible_index(draw: Array, stimulus: String, strain: int) -> int:
	for i in draw.size():
		var card: Dictionary = draw[i]
		if int(card.get("min_strain", 0)) > strain:
			continue
		var templates: Dictionary = card.get("templates", {})
		if templates.has(stimulus) or templates.has("*"):
			return i
	return -1


func _realize(card: Dictionary, stimulus: String, context: Dictionary) -> Dictionary:
	var templates: Dictionary = card.get("templates", {})
	var pool: Array = templates.get(stimulus, templates.get("*", []))
	if pool.is_empty():
		return {}
	var text := String(pool[_rng.randi_range(0, pool.size() - 1)])
	var target := String(context.get("target", "эта позиция")).strip_edges()
	if target == "":
		target = "эта позиция"
	text = text.replace("{target}", target)
	return {
		"id": String(card.get("id", "reaction")),
		"title": String(card.get("title", "Реакция")),
		"text": text,
		"mood": String(card.get("mood", "burst")),
		"vent": int(card.get("vent", 3)),
		"stimulus": stimulus,
	}


func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp
