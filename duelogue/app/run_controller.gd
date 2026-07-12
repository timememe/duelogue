extends Node

## DUELOGUE — КОНТРОЛЛЕР ЗАБЕГА («Сезон», спека context/zal_run_v0.1.md). Единственный
## владелец ПОТОКА забега: генерит карту акта, открывает/закрывает комнаты и передаёт
## интенты чистому run_rules. Эмитит run_* в EventBus; сцена карты
## (run_map_screen) — чистый view поверх, шлёт сюда интенты.
##
## Инвариант §8.1 «ядро боя не знает о забеге»: боёвкой остаётся battle_controller —
## забег лишь ГОТОВИТ ему конфиг (battle_config: составы/тумблеры/мета-входы §3/тема/стороны)
## и читает отчёт {winner, end_reason, final_zal, fee}. Пока настоящая боевая сцена не
## подключена, экран карты шлёт такие же отчёты кнопками ручного мета-плейтеста.

const RoomTypes := preload("res://duelogue/core/run/room_types.gd")
const RunMap := preload("res://duelogue/core/run/run_map.gd")
const RunState := preload("res://duelogue/core/run/run_state.gd")
const RunRules := preload("res://duelogue/core/run/run_rules.gd")
const RunEvents := preload("res://duelogue/core/run/run_events.gd")
## Боевой контроллер НЕ инстанцируется — отсюда читаются только его константы,
## чтобы battle_config не дублировал числа ядра («константы становятся полем конфига», §8.1).
const BattleController := preload("res://duelogue/app/battle_controller.gd")

# --- Константы сезона (мини-забег для плейтестов; крутятся здесь) ---
const ACTS_TOTAL := 3
const LAYERS_PER_ACT := 6     ## слоёв в акте, включая передышку и босса (~6 комнат на путь)
const LANES_MIN := 2
const LANES_MAX := 4

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
	state.reputation = RunRules.REP_START
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


## Закрыть НЕ-событийную комнату. Старый win/lose-маршрут сохранён для smoke и переводится
## в полноценный отчёт боя с тестовым залом ±5. UI ручного теста зовёт resolve_battle прямо.
func resolve_room(room_outcome := "done") -> void:
	if state.over or not state.room_open:
		return
	var nd: Dictionary = state.node(state.current_id)
	if nd.type == RoomTypes.ROOM_EVENT:
		return
	if RoomTypes.is_battle(nd.type):
		resolve_battle({
			"winner": "you" if room_outcome == "win" else "opp",
			"end_reason": "manual_stub",
			"final_zal": 5 if room_outcome == "win" else -5,
		})
		return
	_finish_room(nd, room_outcome, {"kind": "room", "ok": true}, "")


## Единственный вход отчёта боевой комнаты в мета-ядро. Настоящий battle_controller позже
## пришлёт тот же словарь; сейчас его формирует панель ручного теста карты.
func resolve_battle(report: Dictionary) -> void:
	if state.over or not state.room_open:
		return
	var nd: Dictionary = state.node(state.current_id)
	if not RoomTypes.is_battle(String(nd.get("type", ""))):
		return
	var full_report := report.duplicate(true)
	full_report["fee"] = int((nd.engagement as Dictionary).get("fee", 0))
	var settlement := RunRules.settle_battle(state, full_report)
	if not bool(settlement.get("ok", false)):
		return
	var winner := String(settlement.winner)
	var room_outcome := "win" if winner == "you" else ("lose" if winner == "opp" else "draw")
	_finish_room(nd, room_outcome, {"kind": "battle", "settlement": settlement}, "")


## Доступность выбора для view: стоимость и эффект проверяются вместе (включая наличие
## горящей страховки для clear_defeat). Возвращает {ok, reason}.
func event_choice_status(choice_index: int) -> Dictionary:
	if state.over or not state.room_open:
		return {"ok": false, "reason": "Комната уже закрыта."}
	var nd: Dictionary = state.node(state.current_id)
	if nd.type != RoomTypes.ROOM_EVENT:
		return {"ok": false, "reason": "Это не событие."}
	var choices: Array = RunEvents.get_event(String(nd.event_id)).get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		return {"ok": false, "reason": "Нет такого выбора."}
	var ch: Dictionary = choices[choice_index]
	return RunRules.validate_transaction(state, ch.get("cost", {}), ch.get("effects", {}))


## Выбор в событии: атомарная стоимость+эффекты через run_rules, затем закрытие комнаты.
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
	var transaction := RunRules.apply_transaction(state, ch.get("cost", {}), ch.get("effects", {}))
	if not bool(transaction.get("ok", false)):
		return
	_finish_room(nd, "choice_%d" % choice_index,
		{"kind": "event", "transaction": transaction}, String(ch.get("outro", "")))


## Сервис Кулуаров/Подготовки для ручного мета-плейтеста. Не закрывает комнату: после
## покупки игрок нажимает «Уйти». Позже станет обычной транзакцией контента комнаты.
func purchase_clear_mark(currency: String) -> Dictionary:
	if state.over or not state.room_open:
		return {"ok": false, "reason": "Нет открытой комнаты."}
	var nd: Dictionary = state.node(state.current_id)
	if not [RoomTypes.ROOM_SHOP, RoomTypes.ROOM_PREP].has(String(nd.type)):
		return {"ok": false, "reason": "Очистка доступна в Кулуарах или Подготовке."}
	var result := RunRules.clear_defeat_mark(state, currency)
	if bool(result.get("ok", false)):
		_changed()
	return result


func clear_mark_status(currency: String) -> Dictionary:
	var cost := {"fee": RunRules.CLEAR_MARK_FEE} if currency == "fee" else {"rep": RunRules.CLEAR_MARK_REP}
	return RunRules.validate_transaction(state, cost, {"clear_defeat": 1})


## Общее закрытие комнаты: запись пути → сигнал → терминальные/актовые правила потока.
func _finish_room(nd: Dictionary, room_outcome: String, result: Dictionary, outro: String) -> void:
	state.resolve(room_outcome)
	EventBus.room_resolved.emit({
		"node_id": int(nd.id), "type": String(nd.type),
		"outcome": room_outcome, "result": result, "outro": outro,
	})
	if RunRules.is_run_failed(state):
		_end_run("defeated")
		return
	# Финал акта закрыт → следующий акт. Проигрыш босса до четвёртого поражения — контент.
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
		"defeat_marks": state.defeat_marks,
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
