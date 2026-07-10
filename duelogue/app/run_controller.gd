extends Node

## DUELOGUE — КОНТРОЛЛЕР ЗАБЕГА («Сезон», спека context/zal_run_v0.1.md). Единственный
## владелец потока забега: генерит карту акта, ведёт позицию/ресурсы дистанции, открывает
## и закрывает комнаты, применяет правила слоя. Эмитит run_* в EventBus; сцена карты
## (run_map_screen) — чистый view поверх, шлёт сюда интенты.
##
## Инвариант §8.1 «ядро боя не знает о забеге»: боёвкой остаётся battle_controller —
## забег лишь ГОТОВИТ ему конфиг (battle_config: составы/тумблеры/мета-входы §3/тема/стороны)
## и будет читать отчёт (winner, end_reason, статистика). Пока бой из карты не запускается
## (лестница §9: сначала скелет слоя) — боевые комнаты закрываются заглушками исходов
## resolve_room("win"/"lose"), у которых уже работают правила дистанции.

const RoomTypes := preload("res://duelogue/core/run/room_types.gd")
const RunMap := preload("res://duelogue/core/run/run_map.gd")
const RunState := preload("res://duelogue/core/run/run_state.gd")
const RunEvents := preload("res://duelogue/core/run/run_events.gd")
## Боевой контроллер НЕ инстанцируется — отсюда читаются только его константы,
## чтобы battle_config не дублировал числа ядра («константы становятся полем конфига», §8.1).
const BattleController := preload("res://duelogue/app/battle_controller.gd")

# --- Константы сезона (мини-забег для плейтестов; крутятся здесь) ---
const ACTS_TOTAL := 3
const LAYERS_PER_ACT := 6     ## слоёв в акте, включая передышку и босса (~6 комнат на путь)
const LANES_MIN := 2
const LANES_MAX := 4
const REP_START := 5          ## репутация — «HP кампании» (§4); 0 = «отменён»
const REP_LOSS_DEFEAT := 2    ## цена поражения в дебатах (§10.4: не смерть — удар по карьере)

## Пул оппонентов для афиш (§6): имя × стиль ИИ (стили — параметры ai.gd, §5).
const OPP_POOL := [
	{"name": "Шеф", "style": "tall"},
	{"name": "Блогер", "style": "aggro"},
	{"name": "Стример", "style": "wide"},
	{"name": "Колумнист", "style": "balanced"},
	{"name": "Адвокат", "style": "smart"},
]
## Боссы актов — бестиарий §5 (твисты-тумблеры rules_core подключатся на шаге 2 лестницы §9).
const BOSS_POOL := [
	{"name": "Догматик", "style": "smart", "twist": "fortify"},
	{"name": "Демагог", "style": "smart", "twist": "second_wind"},
	{"name": "Популист", "style": "smart", "twist": "zal_tko"},
]

var state: RefCounted


func _ready() -> void:
	state = RunState.new()


# ------------------------------------------------------------- забег ----------

func start_run(run_seed := -1) -> void:
	state = RunState.new()
	state.run_seed = run_seed if run_seed >= 0 else randi() % 1000000
	state.acts_total = ACTS_TOTAL
	state.reputation = REP_START
	_gen_act_map()
	EventBus.run_started.emit({
		"seed": state.run_seed, "act": state.act, "acts_total": state.acts_total,
	})
	_changed()


## Карта акта детерминирована (сид забега + акт) и генерится по одному акту —
## позже между актами встанет выбор пути/передышка без переделки генератора.
func _gen_act_map() -> void:
	state.map = RunMap.generate({
		"seed": state.run_seed,
		"act": state.act,
		"layers": LAYERS_PER_ACT,
		"lanes_min": LANES_MIN,
		"lanes_max": LANES_MAX,
		"themes": _theme_pool(),
		"opps": OPP_POOL,
		"bosses": [BOSS_POOL[(state.act - 1) % BOSS_POOL.size()]],
		"events": RunEvents.pool(),
	})
	state.current_id = -1
	state.room_open = false


## Пул тем для афиш — те же данные, что играет боёвка (id + топик, без инстанса контроллера).
func _theme_pool() -> Array:
	var out: Array = []
	for t in BattleController.THEMES:
		var td: Dictionary = t.data()
		out.append({"id": td.id, "topic": td.topic})
	return out


# ------------------------------------------------------------ комнаты ---------

## Интент карты: шагнуть в достижимый узел. Открывает комнату (панель у view).
func enter_node(id: int) -> void:
	if state.over or state.room_open:
		return
	if not state.reachable_ids().has(id):
		return
	state.enter(id)
	EventBus.room_entered.emit(state.node(id))
	_changed()


## Закрыть НЕ-событийную комнату. Боевые: outcome "win"/"lose" (пока заглушки вместо
## боя); кулуары/подготовка: "done". События закрываются только через event_choice.
func resolve_room(room_outcome := "done") -> void:
	if state.over or not state.room_open:
		return
	var nd: Dictionary = state.node(state.current_id)
	if nd.type == RoomTypes.ROOM_EVENT:
		return
	var fx := {}
	if RoomTypes.is_battle(nd.type):
		if room_outcome == "win":
			fx = {"fee": int((nd.engagement as Dictionary).get("fee", 0))}
		else:
			fx = {"rep": -REP_LOSS_DEFEAT}
	_close_room(nd, room_outcome, fx, "")


## Выбор в событии: применить эффекты выбранного варианта и закрыть комнату.
func event_choice(choice_index: int) -> void:
	if state.over or not state.room_open:
		return
	var nd: Dictionary = state.node(state.current_id)
	if nd.type != RoomTypes.ROOM_EVENT:
		return
	var ev := RunEvents.get_event(String(nd.event_id))
	var choices: Array = ev.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		return
	var ch: Dictionary = choices[choice_index]
	_close_room(nd, "choice_%d" % choice_index, ch.get("effects", {}), String(ch.get("outro", "")))


## Общее закрытие комнаты: эффекты → запись пути → сигнал → правила дистанции.
func _close_room(nd: Dictionary, room_outcome: String, fx: Dictionary, outro: String) -> void:
	state.apply_effects(fx)
	state.resolve(room_outcome)
	EventBus.room_resolved.emit({
		"node_id": int(nd.id), "type": String(nd.type),
		"outcome": room_outcome, "effects": fx, "outro": outro,
	})
	# Правила дистанции (§4): выгоревшая репутация = «отменён», конец забега.
	if state.reputation <= 0:
		_end_run("cancelled")
		return
	# Финал акта закрыт → следующий акт. Проигрыш боссу (при живой репутации) тоже двигает
	# сезон дальше — развилка §10.4 решена в пользу «поражение — контент»; ветка
	# реабилитации ляжет сюда позже.
	if nd.type == RoomTypes.ROOM_BOSS:
		_advance_act()
		return
	_changed()


func _advance_act() -> void:
	if state.act >= state.acts_total:
		_end_run("victory")
		return
	state.act += 1
	_gen_act_map()
	EventBus.act_advanced.emit(state.act)
	_changed()


func _end_run(run_outcome: String) -> void:
	state.over = true
	state.outcome = run_outcome
	EventBus.run_ended.emit(run_outcome, {
		"act": state.act, "rooms": state.path.size(),
		"reputation": state.reputation, "fees": state.fees,
	})
	_changed()


func abandon_run() -> void:
	if not state.over:
		_end_run("abandoned")


# ------------------------------------------------------ шов боя (§8.1) --------

## Конфиг боя для текущей боевой комнаты — ЕДИНСТВЕННОЕ, что забег передаст боёвке.
## Числа читаются из констант battle_controller (не дублируются); ангажемент узла даёт
## тему/сторону/оппонента, мета-входы §3 (крен/заготовка/порядок колоды) пока нулевые.
## Подключение: шаг 1–2 лестницы §9 — battle_controller примет этот словарь конфигом.
func battle_config() -> Dictionary:
	var nd: Dictionary = state.node(state.current_id)
	if not RoomTypes.is_battle(String(nd.get("type", ""))):
		return {}
	var eng: Dictionary = nd.engagement
	return {
		"theme": eng.theme,
		"you_side": eng.side,                       # сторона игрока по контракту (pro/contra)
		"opp_name": eng.opp_name,
		"opp_style": eng.opp_style,
		"boss_twist": eng.twist,                    # спец-правило босса (§5; пока метка)
		"deck": {
			"u": BattleController.DECK_U, "t": BattleController.DECK_T,
			"r": BattleController.DECK_R, "steals": BattleController.STEAL_CARDS,
			"hand": BattleController.HAND,
		},
		"tumblers": {
			"gate_x": BattleController.GATE_X, "gate_y": BattleController.GATE_Y,
			"capture_loot": BattleController.CAPTURE_LOOT,
			"zal_ko": BattleController.ZAL_KO, "zal_hold": BattleController.ZAL_HOLD,
		},
		"start": {"zal_bias": 0, "board": [], "deck_order": []},  # мета-входы §3
	}


func _changed() -> void:
	EventBus.run_map_changed.emit()
