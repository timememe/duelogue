extends RefCounted

## DUELOGUE — ЧИСТОЕ ЯДРО ВЫБОРА КАМЕРА-КАССЕТЫ v0.1. Решает КАКУЮ кассету показать для
## side×state — не решает, показывать ли вообще (это по-прежнему character_core/ReadingPace).
## Не знает тему, содержание реплики, исход боя. Данные кассет приходят снаружи через start()
## (как EmotionCore принимает deck_data) — каталог подменяем в тестах, не хардкодим импорт.
##
## Розыгрыш — МЕШОК (bag), не чистый random и не одноразовая колода как у реакций: перемешался
## → тянем без повторов, пока не кончится → пересобрался, с защитой от немедленного повтора
## последней вытянутой на границе пересборки (context/director_core_v0.1.md §3). Отдельный
## мешок на каждую пару (сторона × стейт) — кассеты одного стейта не делят очередь с другими.

var _cassettes: Array = []
var _bags := {}   ## "<side>:<state>" → {"queue": Array, "last_id": String}
var _rng := RandomNumberGenerator.new()


func start(cassette_data: Dictionary, seed_value: int, _sides: Array = ["you", "opp"]) -> void:
	_cassettes = (cassette_data.get("cassettes", []) as Array).duplicate(true)
	_bags = {}
	_rng.seed = seed_value


## Кассета для side×state, или {} если каталог не покрывает этот стейт — вызывающий код должен
## пережить пустой результат (например, остаться на раскладке без камерного акцента).
func draw(side: String, state: String) -> Dictionary:
	var eligible := _eligible_for(state)
	if eligible.is_empty():
		return {}
	var key := "%s:%s" % [side, state]
	if not _bags.has(key):
		_bags[key] = {"queue": [], "last_id": ""}
	var bag: Dictionary = _bags[key]
	var queue: Array = bag.queue
	if queue.is_empty():
		queue = _refilled_queue(eligible, String(bag.last_id))
	var cassette: Dictionary = queue.pop_front()
	bag.queue = queue
	bag.last_id = String(cassette.get("id", ""))
	return cassette


## weight разворачивается в повторы записи внутри мешка — простой и понятный способ взвесить
## bag-рандомайзер без отдельного алгоритма (weight=2 значит кассета встречается в мешке дважды
## за цикл, то есть выпадает вдвое чаще при прочих равных).
func _eligible_for(state: String) -> Array:
	var out: Array = []
	for cassette in _cassettes:
		var c: Dictionary = cassette
		if not (c.get("compatible_states", []) as Array).has(state):
			continue
		var copies := maxi(1, int(c.get("weight", 1)))
		for i in copies:
			out.append(c)
	return out


func _refilled_queue(eligible: Array, last_id: String) -> Array:
	var queue := eligible.duplicate(true)
	_shuffle(queue)
	if queue.size() > 1 and String(queue[0].get("id", "")) == last_id:
		var tmp = queue[0]
		queue[0] = queue[1]
		queue[1] = tmp
	return queue


func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp
