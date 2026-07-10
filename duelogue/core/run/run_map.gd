extends RefCounted

## DUELOGUE — ГЕНЕРАТОР КАРТЫ АКТА (слой забега, zal_run_v0.1 §6–7). Чистый, без состояния
## (статические методы), детерминированный: весь сезон воспроизводится одним сидом
## (сид забега + акт-соль) — важно для будущих симов слоя и багрепортов.
##
## Карта акта — слоёный DAG слева направо: слой = колонка, узел = комната-ангажемент.
## Рёбра строятся МОНОТОННЫМИ ОКНАМИ (окна целей соседних узлов не перехлёстываются назад),
## поэтому пути не пересекаются визуально, каждый узел имеет вход и выход — связность
## гарантирована построением. Валидатор ниже — страховка будущих правок генератора.
##
## Узел: {id, layer, lane, lanes, type, next: [ids], engagement: {}, event_id: ""}.
## Ангажемент (афиша §6): {theme, topic, side, opp_name, opp_style, fee, twist}.

const RoomTypes := preload("res://duelogue/core/run/room_types.gd")

## Веса типов для средних слоёв (края акта типизируются правилами, не весами).
const TYPE_WEIGHTS := {
	RoomTypes.ROOM_EFIR: 40,
	RoomTypes.ROOM_EVENT: 20,
	RoomTypes.ROOM_ELITE: 14,
	RoomTypes.ROOM_SHOP: 13,
	RoomTypes.ROOM_PREP: 13,
}
const ELITE_MIN_LAYER := 2      ## именитые не раньше этого слоя (разгон акта)
const FORK_CHANCE := 0.35       ## шанс второго ребра в соседнее окно (развилки-ромбы)
const PREP_PREBOSS_CHANCE := 0.6  ## передышка перед боссом: подготовка, иначе кулуары


## cfg: {seed, act, layers, lanes_min, lanes_max, themes: [{id, topic}],
##       opps: [{name, style}], bosses: [{name, style, twist}], events: [ids]}
static func generate(cfg: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	var run_seed := int(cfg.get("seed", 0))
	var act := int(cfg.get("act", 1))
	rng.seed = run_seed * 1000003 + act  # акт-соль: один сид → весь сезон
	var layers := int(cfg.get("layers", 6))
	var lanes_min := int(cfg.get("lanes_min", 2))
	var lanes_max := int(cfg.get("lanes_max", 4))

	# 1) Размеры слоёв: вход узкий (читаемый старт), середина дышит, босс один.
	var sizes: Array = []
	for l in layers:
		if l == layers - 1:
			sizes.append(1)
		elif l == 0:
			sizes.append(rng.randi_range(2, mini(3, lanes_max)))
		else:
			sizes.append(rng.randi_range(lanes_min, lanes_max))

	# 2) Узлы.
	var nodes := {}
	var grid: Array = []  # grid[layer][lane] → id
	var next_id := 0
	for l in layers:
		var row: Array = []
		for lane in int(sizes[l]):
			nodes[next_id] = {
				"id": next_id, "layer": l, "lane": lane, "lanes": int(sizes[l]),
				"type": "", "next": [], "engagement": {}, "event_id": "",
			}
			row.append(next_id)
			next_id += 1
		grid.append(row)

	# 3) Рёбра: окна floor(i·m/n)..floor((i+1)·m/n) тайлят следующий слой без пересечений
	#    и покрывают его целиком; FORK_CHANCE добавляет граничный узел соседнего окна
	#    (монотонность не рвётся — получаются ромбы-развилки).
	for l in layers - 1:
		var n := int(sizes[l])
		var m := int(sizes[l + 1])
		for i in n:
			var lo := floori(float(i) * m / n)
			var hi := floori(float(i + 1) * m / n)
			if hi <= lo:
				hi = lo + 1  # вырожденное окно при сжатии слоя: минимум одна цель
			var targets: Array = []
			for t in range(lo, hi):
				targets.append(t)
			if hi < m and rng.randf() < FORK_CHANCE:
				targets.append(hi)
			for t in targets:
				(nodes[grid[l][i]].next as Array).append(grid[l + 1][t])

	# 4) Типизация: слой 0 — вводные эфиры, последний — босс, предпоследний — передышка;
	#    середина — веса с ограничениями (см. _pick_type).
	var parents := _parents_of(nodes)
	for l in layers:
		for lane in int(sizes[l]):
			var nd: Dictionary = nodes[grid[l][lane]]
			if l == 0:
				nd.type = RoomTypes.ROOM_EFIR
			elif l == layers - 1:
				nd.type = RoomTypes.ROOM_BOSS
			elif l == layers - 2:
				nd.type = RoomTypes.ROOM_PREP if rng.randf() < PREP_PREBOSS_CHANCE else RoomTypes.ROOM_SHOP
			else:
				nd.type = _pick_type(rng, l, nd.id, nodes, parents)

	# 5) Контент узлов: афиши боевых комнат, события — из пула.
	var events: Array = cfg.get("events", [])
	for id in nodes:
		var nd: Dictionary = nodes[id]
		if RoomTypes.is_battle(nd.type):
			nd.engagement = _engagement(rng, nd.type, cfg)
		elif nd.type == RoomTypes.ROOM_EVENT and not events.is_empty():
			nd.event_id = String(events[rng.randi_range(0, events.size() - 1)])

	return {"act": act, "seed": run_seed, "layers": layers, "sizes": sizes, "nodes": nodes}


## Взвешенный тип среднего слоя. Ограничения: элитки не раньше ELITE_MIN_LAYER;
## не-боевой тип не повторяет тип ни одного прямого родителя (нет «двух кулуаров подряд»
## на одном пути). Если фильтр съел всё — эфир (бой всегда уместен).
static func _pick_type(rng: RandomNumberGenerator, layer: int, id: int, nodes: Dictionary, parents: Dictionary) -> String:
	var parent_types := {}
	for pid in parents.get(id, []):
		parent_types[nodes[pid].type] = true
	var pool: Array = []
	var weights: Array = []
	var total := 0
	for type in TYPE_WEIGHTS:
		if type == RoomTypes.ROOM_ELITE and layer < ELITE_MIN_LAYER:
			continue
		if not RoomTypes.is_battle(type) and parent_types.has(type):
			continue
		pool.append(type)
		total += int(TYPE_WEIGHTS[type])
		weights.append(total)
	if pool.is_empty():
		return RoomTypes.ROOM_EFIR
	var roll := rng.randi_range(1, total)
	for i in pool.size():
		if roll <= int(weights[i]):
			return pool[i]
	return RoomTypes.ROOM_EFIR


## Афиша ангажемента (§6): тема × сторона (контрактом, развилка §10.3) × оппонент × гонорар.
## Твист босса — поле под бестиарий §5 (тумблеры подключаются на шаге 2 лестницы §9).
static func _engagement(rng: RandomNumberGenerator, type: String, cfg: Dictionary) -> Dictionary:
	var themes: Array = cfg.get("themes", [{"id": "none", "topic": "—"}])
	var th: Dictionary = themes[rng.randi_range(0, themes.size() - 1)]
	var opp := {}
	var fee := 0
	match type:
		RoomTypes.ROOM_BOSS:
			var bosses: Array = cfg.get("bosses", [{"name": "Босс", "style": "smart", "twist": ""}])
			opp = bosses[rng.randi_range(0, bosses.size() - 1)]
			fee = 6
		RoomTypes.ROOM_ELITE:
			var elites: Array = cfg.get("opps", [{"name": "Оппонент", "style": "balanced"}])
			opp = elites[rng.randi_range(0, elites.size() - 1)]
			fee = rng.randi_range(4, 5)
		_:
			var opps: Array = cfg.get("opps", [{"name": "Оппонент", "style": "balanced"}])
			opp = opps[rng.randi_range(0, opps.size() - 1)]
			fee = rng.randi_range(2, 3)
	return {
		"theme": String(th.get("id", "")),
		"topic": String(th.get("topic", "")),
		"side": "pro" if rng.randf() < 0.5 else "contra",
		"opp_name": String(opp.get("name", "")),
		"opp_style": String(opp.get("style", "balanced")),
		"fee": fee,
		"twist": String(opp.get("twist", "")),
	}


## Обратные рёбра: id → [ids родителей].
static func _parents_of(nodes: Dictionary) -> Dictionary:
	var parents := {}
	for id in nodes:
		for t in nodes[id].next:
			if not parents.has(t):
				parents[t] = []
			(parents[t] as Array).append(id)
	return parents


## Страховочный валидатор карты → список строк-ошибок (пусто = ок).
## Проверяет то, что генератор обязан гарантировать построением.
static func validate(map: Dictionary) -> Array:
	var errs: Array = []
	var nodes: Dictionary = map.get("nodes", {})
	var layers := int(map.get("layers", 0))
	if nodes.is_empty():
		return ["карта пуста"]
	# Босс ровно один, и он в последнем слое.
	var boss_ids: Array = []
	for id in nodes:
		var nd: Dictionary = nodes[id]
		if nd.type == RoomTypes.ROOM_BOSS:
			boss_ids.append(id)
			if int(nd.layer) != layers - 1:
				errs.append("босс %d не в последнем слое" % id)
	if boss_ids.size() != 1:
		errs.append("боссов %d (ожидался 1)" % boss_ids.size())
	# Рёбра: только в следующий слой, цели существуют.
	for id in nodes:
		var nd: Dictionary = nodes[id]
		for t in nd.next:
			if not nodes.has(t):
				errs.append("узел %d → несуществующий %d" % [id, t])
			elif int(nodes[t].layer) != int(nd.layer) + 1:
				errs.append("ребро %d→%d не в соседний слой" % [id, t])
	# Достижимость: каждый узел достижим со старта И достигает босса.
	var from_start := _reach(nodes, _layer_ids(nodes, 0), false)
	var to_boss := _reach(nodes, boss_ids, true)
	for id in nodes:
		if not from_start.has(id):
			errs.append("узел %d недостижим со старта" % id)
		if not to_boss.has(id):
			errs.append("из узла %d недостижим босс" % id)
	# Контент: у боевых — афиша, у событий — id события.
	for id in nodes:
		var nd: Dictionary = nodes[id]
		if RoomTypes.is_battle(nd.type) and (nd.engagement as Dictionary).is_empty():
			errs.append("боевой узел %d без ангажемента" % id)
		if nd.type == RoomTypes.ROOM_EVENT and String(nd.event_id) == "":
			errs.append("событие %d без event_id" % id)
	return errs


static func _layer_ids(nodes: Dictionary, layer: int) -> Array:
	var out: Array = []
	for id in nodes:
		if int(nodes[id].layer) == layer:
			out.append(id)
	out.sort()
	return out


## BFS по next (reverse=false) или по родителям (reverse=true) от множества seeds.
static func _reach(nodes: Dictionary, seeds: Array, reverse: bool) -> Dictionary:
	var edges := _parents_of(nodes) if reverse else {}
	var seen := {}
	var queue := seeds.duplicate()
	while not queue.is_empty():
		var id = queue.pop_front()
		if seen.has(id):
			continue
		seen[id] = true
		var outs: Array = edges.get(id, []) if reverse else (nodes[id].next as Array)
		for t in outs:
			if not seen.has(t):
				queue.append(t)
	return seen
