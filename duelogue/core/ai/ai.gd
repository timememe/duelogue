extends RefCounted

## DUELOGUE — ИИ (БОТ): политика поверх чистого ядра правил. Вынесено из zal_v3_model.gd.
## Все методы работают над ССЫЛКОЙ на rules_core (аргумент `r`) через его публичный API —
## ядро правил про ИИ ничего не знает. Здесь: выбор хода (pick), воля клинча (*_will_clinch),
## авто-разрешение клинча для сима (_auto_resolve) и полная симуляция матча (simulate).

const Cards := preload("res://duelogue/core/cards/card_types.gd")
const Grammar := preload("res://duelogue/core/cards/grammar.gd")
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

## Выбор хода ИИ по стилю. Возвращает {type, target?, named_index?, named_clinch?}.
## named_index >= 0 — розыгрыш ИМЕННОЙ карты руки (r.play_named либо клинч этой картой).
func pick(r: RefCounted, side: String, style: String) -> Dictionary:
	return _apply_named(r, side, _pick_base(r, side, style))


## Политика именных V1: стиль решил играть тип X и в руке есть именной приём базы X →
## играть его (замена 1:1 предполагает, что приём не слабее ванили; сим это и меряет).
## Тоньше (беречь под момент, считать доп. цели гиша) — следующая итерация.
func _apply_named(r: RefCounted, side: String, act: Dictionary) -> Dictionary:
	if act.is_empty():
		return act
	var hand: Array = r.sides[side].hand
	for i in hand.size():
		var c: Dictionary = hand[i]
		if String(c.get("named", "")) == "" or String(c.type) != String(act.type):
			continue
		# smart согласует ПРИРОДУ приёма-атаки с моментом (глупые стили жгут как есть):
		# кража-приём (чучело) — только под досягаемый захват (его порог = обычный + 1),
		# не-кража — не в момент кражи (не жжём окно захвата гишем/сократиком).
		if String(act.type) == TYPE_RAZBOR and String(style_of.get(side, "")) == "smart":
			var tgt := int(act.get("target", -1))
			if bool(c.get("steals", false)):
				var reach := int(r.capture_threshold(side)) + \
					maxi(0, int(c.get("capture_bonus", 0)))
				var named_target := _capturable_target_at_reach(r, side, reach)
				if named_target < 0:
					continue
				act["target"] = named_target
			elif atk_prefer_steal(r, side, r.other(side), tgt):
				continue
		act["named_index"] = i
		act["named_clinch"] = bool(c.get("clinch", false))
		return act
	return act


func _pick_base(r: RefCounted, side: String, style: String) -> Dictionary:
	if style == "smart":
		return _pick_smart(r, side)
	var legal: Array = r.legal_types(side)
	if legal.is_empty():
		return {}
	var opp: String = r.other(side)
	var opp_lines: Array = r.sides[opp].lines

	# 1. Настоящий летал: последняя рамка и нет публичного резерва в руке.
	if r.board_ko_enabled and legal.has(TYPE_RAZBOR) and opp_lines.size() == 1 \
			and int(opp_lines[0].theses) == 1 and r.reserve_count(opp) == 0:
		return {"type": TYPE_RAZBOR, "target": 0}

	# 2. Выживание: единственная хрупкая рамка — укрепить.
	var me: Dictionary = r.sides[side]
	if r.board_ko_enabled and me.lines.size() == 1 and int(me.lines[0].theses) <= 1 \
			and r.reserve_count(side) == 0:
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

	# 1. Летал: снести последнюю рамку, если в руке нет рамки для восстановления.
	if r.board_ko_enabled and legal.has(TYPE_RAZBOR) and opp_lines.size() == 1 \
			and int(opp_lines[0].theses) == 1 and r.reserve_count(opp) == 0:
		return {"type": TYPE_RAZBOR, "target": 0}

	# 2. Выживание: единственная рамка хрупкая → укрепить (защита от KO/захвата).
	if r.board_ko_enabled and my_lines.size() == 1 and int(my_lines[0].theses) <= 1 \
			and r.reserve_count(side) == 0:
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
	# Press бьёт точный T, но если его не накрыть, unwind освободит opener по рамке.
	# Поэтому смертельность исходной атаки остаётся актуальной на всей длине ралли.
	if r.board_ko_enabled and r.sides[defender].lines.size() == 1 \
			and int(r.clinch.get("opening_thickness", int(line.theses))) <= 1 \
			and r.reserve_count(defender) == 0:
		return true
	return randf() < 0.75


## Точная карта ответа на открытый LINK (мини-шаг ступени 4, §12 AI): защитник любого
## стиля закрывает известный маршрут правильной схемой, если она в руке. Окно — только
## первый ответ; -1 — правильной карты нет, играть как раньше (вслепую).
func def_answer_index(r: RefCounted, defender: String) -> int:
	if not r.clinch_active() or String(r.clinch.get("combo_state", "")) != "link":
		return -1
	if int(r.clinch.get("t_added", 0)) != 0:
		return -1
	var anchor_card: Dictionary = (r.clinch.get("opening_anchor", {}) as Dictionary) \
		.get("card", {})
	var sequence: Array = r.clinch.get("sequence", [])
	if sequence.is_empty():
		return -1
	var hand: Array = r.sides[defender].hand
	for i in hand.size():
		var card: Dictionary = hand[i]
		if not r.clinch_card_legal(card, "await_defend"):
			continue
		if Grammar.answers(anchor_card, sequence[0], card):
			return i
	return -1


func atk_will_clinch(r: RefCounted, attacker: String, line: Dictionary) -> bool:
	if String(style_of.get(attacker, "")) == "smart":
		return _smart_atk_will_clinch(r, attacker, line)
	# Press снимает точный T и тем самым может освободить всю цепь до opener.
	# Для обычного стиля решение всё ещё остаётся риском экономики руки.
	return randf() < 0.5

## Умная защита в клинче — по ЭКОНОМИКЕ РУКИ (ось мастерства из GDD §7), не по монетке.
func _smart_def_will_clinch(r: RefCounted, defender: String, line: Dictionary) -> bool:
	var theses := int(line.theses)
	var root_capture := bool(r.clinch.get("opening_capture_eligible", false))
	var root_lethal: bool = bool(r.board_ko_enabled) and r.sides[defender].lines.size() == 1 and \
		int(r.clinch.get("opening_thickness", theses)) <= 1 and r.reserve_count(defender) == 0
	# Потеря рамки = нокаут → держим обязательно на любом уровне стека: пропуск
	# освобождает все атаки ниже вплоть до opener.
	if root_lethal:
		return true
	var tez := _clinch_count(r, defender, "await_defend")
	if tez == 0:
		return false
	# Frozen-флаг принадлежит конкретному opener-объекту: обычный R на той же толщине
	# не превращается для AI в Кражу лишь из-за геометрии рамки.
	if root_capture:
		return true
	# Иначе держим только при запасе тезисов — не палим последнюю карту на дешёвую рамку.
	return tez >= 2


## Умное добивание: при ценном opener press последней картой оправдан, потому что
## exact T будет снят и весь стек развернётся до рамки. В обычной сцене сохраняем резерв.
func _smart_atk_will_clinch(r: RefCounted, attacker: String, line: Dictionary) -> bool:
	var atk := _clinch_count(r, attacker, "await_attack")
	if atk == 0:
		return false
	var root_capture := bool(r.clinch.get("opening_capture_eligible", false))
	var root_lethal: bool = bool(r.board_ko_enabled) and \
		r.sides[r.clinch.defender].lines.size() == 1 and \
		int(r.clinch.get("opening_thickness", int(line.theses))) <= 1 and \
		r.reserve_count(String(r.clinch.defender)) == 0
	if root_capture or root_lethal:
		return true
	return atk >= 2


## Тратить ли Кражу (а не обычный Разбор) в атаке по defender[idx]. Smart ХОЛДИТ Кражи:
## жжёт их только когда рамка в досягаемости захвата (тезисы <= порога) — редкая карта
## копится под поимку, а не сгорает на чип-атаках. Прочие стили жгут Кражу первой (как раньше).
## Аппроксимация консервативная: в клинче рамка может опуститься в досягаемость позже.
func atk_prefer_steal(r: RefCounted, attacker: String, defender: String, idx: int) -> bool:
	if String(style_of.get(attacker, "")) != "smart":
		return true
	# После ответного T следующая атака направлена уже в этот тезис, а не в рамку:
	# обычный Разбор приоритетнее; Кража тратится лишь при отсутствии другой атаки.
	if r.clinch_active() and String(r.clinch.get("phase", "")) == "await_attack":
		return false
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
	# Комбо-телеметрия сима: combo_events[] уже есть в info play_action/play_named/
	# play_redeploy (наружу напрямую) и в info["info"]["combo_events"] финала клинча —
	# просто читаем то, что ядро и так возвращает, ничего в ядре не меняя.
	var combo_log: Array = []
	var clinches := 0
	while not r.game_over and guard < max_turns:
		guard += 1
		var st: String = r.begin_turn(r.current)
		if st == "ko" or st == "crowd" or st == "end" or st == "over":
			break
		if st == "reframe":
			var recovery: Array = r.recovery_indices(r.current)
			if recovery.is_empty():
				break
			var redeploy_info: Dictionary = r.play_redeploy(r.current, int(recovery[0]))
			combo_log.append_array(redeploy_info.get("combo_events", []))
			r.advance()
			continue
		if st == "pass":
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
		var named_i := int(act.get("named_index", -1))
		if named_i >= 0 and not bool(act.get("named_clinch", false)):
			# Именной приём без клинча — единая точка ядра play_named.
			var inf: Dictionary = r.play_named(r.current, named_i, int(act.get("target", -1)))
			if inf.is_empty():  # нелегален (гонка условий) — ванильный фолбэк
				var fallback_info: Dictionary = r.play_action(r.current, act.type, act.get("target", -1))
				combo_log.append_array(fallback_info.get("combo_events", []))
			else:
				combo_log.append_array(inf.get("combo_events", []))
		elif act.type == TYPE_RAZBOR and r.clinch_enabled:
			# Клинч с волей обеих сторон (мехвариант play_action был только в симе).
			# named_i >= 0 — клинч именно этой картой (Сократический вопрос).
			clinches += 1
			var clinch_result: Dictionary = _auto_resolve(r, r.current, r.other(r.current),
				int(act.get("target", -1)), named_i)
			combo_log.append_array(
				(clinch_result.get("info", {}) as Dictionary).get("combo_events", []))
		else:
			var action_info: Dictionary = r.play_action(r.current, act.type, act.get("target", -1))
			combo_log.append_array(action_info.get("combo_events", []))
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
		"clinches": clinches,
		"combo_events": combo_log,
	}


## Авто-воля клинча для сима: скармливает решения клинч-автомату ядра, пока он не закроется.
## Тот же путь, что у интерактивного драйвера — один источник правды (rules_core.clinch_*).
## named_index >= 0 — клинч открывается именно этой картой руки (именной приём).
## Возвращает результат финального clinch_submit (несёт "info" на settlement) — нужен
## телеметрии сима (combo-частота); сам auto-resolve от этого не меняется.
func _auto_resolve(r: RefCounted, attacker: String, defender: String, idx: int, named_index: int = -1) -> Dictionary:
	var ctx: Dictionary = r.begin_clinch(attacker, defender, idx, atk_prefer_steal(r, attacker, defender, idx), named_index)
	if ctx.is_empty():
		return {}
	var line: Dictionary = r.sides[defender].lines[idx]
	var guard := 0
	var last: Dictionary = {}
	while r.clinch_active() and guard < 200:
		guard += 1
		var side: String = r.clinch_pending_side()
		if not r.clinch_can_act(side):
			last = r.clinch_submit("pass")
			continue
		# side == defender → фаза защиты (await_defend), иначе — добивание (await_attack).
		var play := def_will_clinch(r, side, line) if side == defender else atk_will_clinch(r, side, line)
		last = r.clinch_submit("play" if play else "pass", atk_prefer_steal(r, attacker, defender, idx))
	return last


# --- эвристики (читают только r.sides через публичный API) ---

func _hand_count(r: RefCounted, side: String, type: String) -> int:
	var n := 0
	for c in r.sides[side].hand:
		if c.type == type:
			n += 1
	return n


func _clinch_count(r: RefCounted, side: String, phase: String) -> int:
	if r.has_method("clinch_legal_count"):
		return int(r.clinch_legal_count(side, phase))
	return _hand_count(r, side, TYPE_TEZIS if phase == "await_defend" else TYPE_RAZBOR)


func _clinch_targets_frame(r: RefCounted) -> bool:
	if not r.clinch_active() or String(r.clinch.get("phase", "")) != "await_defend":
		return false
	var sequence: Array = r.clinch.get("sequence", [])
	return sequence.size() == 1


func _hand_has_steal(r: RefCounted, side: String) -> bool:
	for c in r.sides[side].hand:
		if c.type == TYPE_RAZBOR and bool(c.get("steals", false)):
			return true
	return false


## Индекс чужой рамки, которую можно ЗАХВАТИТЬ Кражей (тезисы <= порога захвата, не
## укреплена). Берём самую жирную из досягаемых (больше отнято). -1 если нет.
func _capturable_target(r: RefCounted, side: String) -> int:
	return _capturable_target_at_reach(r, side, int(r.capture_threshold(side)))


func _capturable_target_at_reach(r: RefCounted, side: String, reach: int) -> int:
	var lines: Array = r.sides[r.other(side)].lines
	var best := -1
	var best_theses := 0
	for i in lines.size():
		var t := int(lines[i].theses)
		if t <= reach and t > best_theses and not r.is_fortified(lines[i]) and \
				not bool(lines[i].get("braced", false)):
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
