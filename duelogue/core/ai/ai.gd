extends RefCounted

## DUELOGUE — ИИ (БОТ): политика поверх чистого ядра правил. Вынесено из zal_v3_model.gd.
## Все методы работают над ССЫЛКОЙ на rules_core (аргумент `r`) через его публичный API —
## ядро правил про ИИ ничего не знает. Здесь: выбор хода (pick), воля клинча (*_will_clinch),
## авто-разрешение клинча для сима (_auto_resolve) и полная симуляция матча (simulate).

const Cards := preload("res://duelogue/core/cards/card_types.gd")
const TYPE_TEZIS := Cards.TYPE_TEZIS
const TYPE_RAZBOR := Cards.TYPE_RAZBOR
const TYPE_USTANOVKA := Cards.TYPE_USTANOVKA
const SIDE_YOU := Cards.SIDE_YOU
const SIDE_OPP := Cards.SIDE_OPP

## Стиль по стороне — чтобы клинч-воля знала, умная ли сторона. "" — дефолт/монетка.
var style_of := {}


func set_style(side: String, style: String) -> void:
	style_of[side] = style


# ----------------------------------------------------------------- выбор хода --

## Выбор хода ИИ по стилю. Возвращает {type, target?}.
func pick(r: RefCounted, side: String, style: String) -> Dictionary:
	if style == "smart":
		return _pick_smart(r, side)
	var legal: Array = r.legal_types(side)
	if legal.is_empty():
		return {}
	var opp: String = r.other(side)
	var opp_lines: Array = r.sides[opp].lines

	# 1. Летальный разбор (снять последнюю рамку оппонента).
	if legal.has(TYPE_RAZBOR) and opp_lines.size() == 1 and int(opp_lines[0].theses) == 1:
		return {"type": TYPE_RAZBOR, "target": 0}

	# 2. Выживание: единственная хрупкая рамка — укрепить.
	var me: Dictionary = r.sides[side]
	if me.lines.size() == 1 and int(me.lines[0].theses) <= 1:
		if legal.has(TYPE_TEZIS):
			return {"type": TYPE_TEZIS}
		if legal.has(TYPE_USTANOVKA):
			return {"type": TYPE_USTANOVKA}

	# 3. По стилю.
	for pref in _style_order(style):
		if pref == TYPE_RAZBOR and legal.has(TYPE_RAZBOR):
			var t := _razbor_target(r, side)
			if t >= 0:
				return {"type": TYPE_RAZBOR, "target": t}
		elif legal.has(pref):
			return {"type": pref}
	return {"type": legal[0]}


## Умный бот: играет ось мастерства (GDD §7) — захват, защита от захвата, teardown под
## отставание, иначе строит ширину. Клинч-решения экономные (см. _smart_*_will_clinch).
func _pick_smart(r: RefCounted, side: String) -> Dictionary:
	var legal: Array = r.legal_types(side)
	if legal.is_empty():
		return {}
	var opp: String = r.other(side)
	var opp_lines: Array = r.sides[opp].lines
	var my_lines: Array = r.sides[side].lines

	# 1. Летал: снести последнюю рамку оппонента (нокаут).
	if legal.has(TYPE_RAZBOR) and opp_lines.size() == 1 and int(opp_lines[0].theses) == 1:
		return {"type": TYPE_RAZBOR, "target": 0}

	# 2. Выживание: единственная рамка хрупкая → укрепить (защита от KO/захвата).
	if my_lines.size() == 1 and int(my_lines[0].theses) <= 1:
		if legal.has(TYPE_TEZIS):
			return {"type": TYPE_TEZIS}
		if legal.has(TYPE_USTANOVKA):
			return {"type": TYPE_USTANOVKA}

	# 3. Капитализировать захват: чужая рамка на 1 тезисе + Кража в руке → забрать (+2 к счёту).
	if r.capture_mode > 0 and legal.has(TYPE_RAZBOR) and _hand_has_steal(r, side):
		var cap_t := _capturable_target(r, side)
		if cap_t >= 0:
			return {"type": TYPE_RAZBOR, "target": cap_t}

	# 4. Защита от захвата: довести активную рамку выше порога захвата оппонента (при
	# зал-гейте порог плавает с креном — лидеру надо держать рамки толще).
	if r.capture_mode > 0 and legal.has(TYPE_TEZIS):
		var active: Dictionary = my_lines[-1]
		if not active.closed and int(active.theses) <= r.capture_threshold(opp):
			return {"type": TYPE_TEZIS}

	# 5. Отстаю по ширине → давить teardown: грызть лучшую чужую цель.
	if r.score(side) < r.score(opp) and legal.has(TYPE_RAZBOR):
		var t := _razbor_target(r, side)
		if t >= 0:
			return {"type": TYPE_RAZBOR, "target": t}

	# 6. Иначе строю ширину (она напрямую к победе); запас тезисов держит экономику.
	if legal.has(TYPE_USTANOVKA):
		return {"type": TYPE_USTANOVKA}
	if legal.has(TYPE_TEZIS):
		return {"type": TYPE_TEZIS}
	if legal.has(TYPE_RAZBOR):
		var t2 := _razbor_target(r, side)
		if t2 >= 0:
			return {"type": TYPE_RAZBOR, "target": t2}
	return {"type": legal[0]}


# --------------------------------------------------------------- воля клинча ---

func def_will_clinch(r: RefCounted, defender: String, line: Dictionary) -> bool:
	if String(style_of.get(defender, "")) == "smart":
		return _smart_def_will_clinch(r, defender, line)
	# Обязательно защищаем, если потеря рамки = нокаут.
	if r.sides[defender].lines.size() == 1 and int(line.theses) <= 1:
		return true
	return randf() < 0.75


func atk_will_clinch(r: RefCounted, attacker: String, line: Dictionary) -> bool:
	if String(style_of.get(attacker, "")) == "smart":
		return _smart_atk_will_clinch(r, attacker, line)
	# Дожимаем охотнее, если рамка вот-вот падёт.
	if int(line.theses) <= 1:
		return true
	return randf() < 0.5


## Умная защита в клинче — по ЭКОНОМИКЕ РУКИ (ось мастерства из GDD §7), не по монетке.
func _smart_def_will_clinch(r: RefCounted, defender: String, line: Dictionary) -> bool:
	var theses := int(line.theses)
	# Потеря рамки = нокаут → держим обязательно.
	if r.sides[defender].lines.size() == 1 and theses <= 1:
		return true
	var tez := _hand_count(r, defender, TYPE_TEZIS)
	if tez == 0:
		return false
	# Рамка в досягаемости захвата (порог атакующего с учётом зал-гейта) — тянем вверх.
	if r.capture_mode > 0 and theses <= r.capture_threshold(r.other(defender)):
		return true
	# Иначе держим только при запасе тезисов — не палим последнюю карту на дешёвую рамку.
	return tez >= 2


## Умное добивание — дожимаем, только когда это окупается и есть запас атак.
func _smart_atk_will_clinch(r: RefCounted, attacker: String, line: Dictionary) -> bool:
	var atk := _hand_count(r, attacker, TYPE_RAZBOR)
	if atk == 0:
		return false
	# Рамка вот-вот падёт (а с Кражей — ещё и захват) → добиваем.
	if int(line.theses) <= 1:
		return true
	# Дожимать дальше — только при запасе атак.
	return atk >= 2


## Тратить ли Кражу (а не обычный Разбор) в атаке по defender[idx]. Smart ХОЛДИТ Кражи:
## жжёт их только когда рамка в досягаемости захвата (тезисы <= порога) — редкая карта
## копится под поимку, а не сгорает на чип-атаках. Прочие стили жгут Кражу первой (как раньше).
## Аппроксимация консервативная: в клинче рамка может опуститься в досягаемость позже.
func atk_prefer_steal(r: RefCounted, attacker: String, defender: String, idx: int) -> bool:
	if String(style_of.get(attacker, "")) != "smart":
		return true
	var dl: Array = r.sides[defender].lines
	if idx < 0 or idx >= dl.size():
		return true
	return int(dl[idx].theses) <= int(r.capture_threshold(attacker))


# ----------------------------------------------------------- сим и авто-клинч --

## Полный матч ИИ vs ИИ (порт zal_v3_model.simulate). Возвращает результат + динамику лида.
func simulate(r: RefCounted, style_you: String, style_opp: String, max_turns: int = 400) -> Dictionary:
	style_of[SIDE_YOU] = style_you
	style_of[SIDE_OPP] = style_opp
	var guard := 0
	var diffs: Array[int] = []
	var atk_flags: Array[bool] = []  # был ли ход атакой (интерактивность по ходам)
	while not r.game_over and guard < max_turns:
		guard += 1
		var st: String = r.begin_turn(r.current)
		if st == "ko" or st == "crowd" or st == "end" or st == "over":
			break
		if st == "redeploy" or st == "pass":
			r.advance()
			continue
		var style := style_you if r.current == SIDE_YOU else style_opp
		var act := pick(r, r.current, style)
		if act.is_empty():
			r.sides[r.current].passed = true
			if r.sides[r.other(r.current)].passed:
				r._end_by_decision()
				break
			r.advance()
			continue
		if act.type == TYPE_RAZBOR and r.clinch_enabled:
			# Клинч с волей обеих сторон (мехвариант play_action был только в симе).
			_auto_resolve(r, r.current, r.other(r.current), int(act.get("target", -1)))
			r.turn_count += 1
		else:
			r.play_action(r.current, act.type, act.get("target", -1))
		diffs.append(r.score(SIDE_YOU) - r.score(SIDE_OPP))
		atk_flags.append(String(act.type) == TYPE_RAZBOR)
		r.advance()
	if not r.game_over:
		r._end_by_decision()
	return {
		"winner": r.winner,
		"reason": r.end_reason,
		"turns": r.turn_count,
		"score_you": r.score(SIDE_YOU),
		"score_opp": r.score(SIDE_OPP),
		"lead_changes": _count_lead_changes(diffs),
		"decision_frac": _decision_frac(diffs, r.winner),
		"tail_interaction": _tail_interaction(atk_flags),
		"sw_draws": int(r.sides[SIDE_YOU].get("sw_used", 0)) + int(r.sides[SIDE_OPP].get("sw_used", 0)),
		"captures": int(r.captures),
		"capture_theses": int(r.capture_theses),
	}


## Авто-воля клинча для сима: скармливает решения клинч-автомату ядра, пока он не закроется.
## Тот же путь, что у интерактивного драйвера — один источник правды (rules_core.clinch_*).
func _auto_resolve(r: RefCounted, attacker: String, defender: String, idx: int) -> void:
	var ctx: Dictionary = r.begin_clinch(attacker, defender, idx, atk_prefer_steal(r, attacker, defender, idx))
	if ctx.is_empty():
		return
	var line: Dictionary = r.sides[defender].lines[idx]
	var guard := 0
	while r.clinch_active() and guard < 200:
		guard += 1
		var side: String = r.clinch_pending_side()
		if not r.clinch_can_act(side):
			r.clinch_submit("pass")
			continue
		# side == defender → фаза защиты (await_defend), иначе — добивание (await_attack).
		var play := def_will_clinch(r, side, line) if side == defender else atk_will_clinch(r, side, line)
		r.clinch_submit("play" if play else "pass", atk_prefer_steal(r, attacker, defender, idx))


# --- эвристики (читают только r.sides через публичный API) ---

func _hand_count(r: RefCounted, side: String, type: String) -> int:
	var n := 0
	for c in r.sides[side].hand:
		if c.type == type:
			n += 1
	return n


func _hand_has_steal(r: RefCounted, side: String) -> bool:
	for c in r.sides[side].hand:
		if c.type == TYPE_RAZBOR and bool(c.get("steals", false)):
			return true
	return false


## Индекс чужой рамки, которую можно ЗАХВАТИТЬ Кражей (тезисы <= порога захвата, не
## укреплена). Берём самую жирную из досягаемых (больше отнято). -1 если нет.
func _capturable_target(r: RefCounted, side: String) -> int:
	var thresh: int = r.capture_threshold(side)
	var lines: Array = r.sides[r.other(side)].lines
	var best := -1
	var best_theses := 0
	for i in lines.size():
		var t := int(lines[i].theses)
		if t <= thresh and t > best_theses and not r.is_fortified(lines[i]):
			best = i
			best_theses = t
	return best


## Лучшая цель для разбора: снять последнюю рамку (KO) > убрать 1-тезисную рамку >
## грызть самую жирную закрытую (неремонтопригодную) > грызть самую жирную.
func _razbor_target(r: RefCounted, side: String) -> int:
	var lines: Array = r.sides[r.other(side)].lines
	if lines.is_empty():
		return -1
	if lines.size() == 1 and int(lines[0].theses) == 1:
		return 0
	var best := -1
	var best_score := -1.0
	for i in lines.size():
		var ln: Dictionary = lines[i]
		var sc := 0.0
		if int(ln.theses) == 1:
			sc = 100.0
		else:
			sc = float(ln.theses)
			if ln.closed:
				sc += 0.5
		# Укреплённая рамка — плохая цель: кража отскакивает, а сама она глубокая.
		if r.is_fortified(ln):
			sc -= 50.0
		if sc > best_score:
			best_score = sc
			best = i
	return best


func _style_order(style: String) -> Array:
	match style:
		"wide": return [TYPE_USTANOVKA, TYPE_TEZIS, TYPE_RAZBOR]
		"tall": return [TYPE_TEZIS, TYPE_USTANOVKA, TYPE_RAZBOR]
		"aggro": return [TYPE_RAZBOR, TYPE_TEZIS, TYPE_USTANOVKA]
		"defensive": return [TYPE_TEZIS, TYPE_RAZBOR, TYPE_USTANOVKA]
		_:
			var opts := [TYPE_TEZIS, TYPE_RAZBOR, TYPE_USTANOVKA]
			opts.shuffle()
			return opts


# --- метрики динамики лида (диагностика «статичности» исхода) ---

## Число смен лидера: переходы знака диффа (нули — «ничейный» лид — пропускаем).
func _count_lead_changes(diffs: Array[int]) -> int:
	var changes := 0
	var last_sign := 0
	for d in diffs:
		var s := signi(d)
		if s != 0 and s != last_sign:
			if last_sign != 0:
				changes += 1
			last_sign = s
	return changes


## Интерактивность хвоста: доля АТАК среди ходов последней трети партии. Прямой градусник
## «пассивного хвоста»: 0 — финал = сольный сброс строительных карт, выше — финал дерётся.
func _tail_interaction(flags: Array[bool]) -> float:
	if flags.is_empty():
		return 0.0
	var start := flags.size() * 2 / 3
	var n := flags.size() - start
	if n <= 0:
		return 0.0
	var hits := 0
	for i in range(start, flags.size()):
		if flags[i]:
			hits += 1
	return float(hits) / float(n)


## Доля партии до «точки решения»: последний момент, когда победитель НЕ был строго впереди.
func _decision_frac(diffs: Array[int], win: String) -> float:
	if win == "" or diffs.is_empty():
		return 1.0
	var sign := 1 if win == SIDE_YOU else -1
	var last_not_ahead := -1
	for i in diffs.size():
		if diffs[i] * sign <= 0:
			last_not_ahead = i
	return float(last_not_ahead + 1) / float(diffs.size())
