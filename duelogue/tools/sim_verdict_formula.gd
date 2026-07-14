extends Node

## ИЗОЛИРОВАННЫЙ СИМ-ПОЛИГОН единого вердикта. Производственный rules_core НЕ меняет.
##
## Проверяем гипотезу и прозрачный свип веса рамки:
##   вес стороны P = wР * рамки + все стоящие тезисы, wР = 1/2/3;
##   итоговый перевес V = P_you - P_opp + независимый зал;
##   знак V определяет победителя (точный 0 пока оставляем ничьёй, чтобы измерить частоту;
##   правило burden of proof — отдельное решение после данных).
##
## Независимый зал в тесте:
##   +1 победителю каждого завершённого клинча, с публичным капом;
##   обычная выкладка карт его НЕ двигает — её уже считает доска;
##   зал-гейт читает эту независимую шкалу;
##   захват не получает отдельного бонуса зала сверх победы в клинче.
##
## В FormulaRules отключены самостоятельные KO/TKO. Ноль рамок — P=0, но сторона может
## продолжать Разбором/Кражей или поставить новую Установку. Матч заканчивается единым
## вердиктом, когда обе стороны больше не могут сделать легального действия.
##
## Запуск:
##   Godot --headless --path . res://duelogue/tools/sim_verdict_formula.tscn

const Rules := preload("res://duelogue/core/rules/rules_core.gd")
const Deck := preload("res://duelogue/core/cards/deck.gd")
const Ai := preload("res://duelogue/core/ai/ai.gd")

@export var mirror_matches: int = 1200
@export var field_matches: int = 350
@export var deck_matches: int = 900

# Канон текущей партии.
const BASE := 1
const KOMI := 0
const STEAL := 2
const FORT := 0
const CLINCH := true
const FREEZE := true
const CAPTURE := 1
const GATE_X := 2
const GATE_Y := 4
const SW := 0
const LOOT := 1
const OLD_ZAL_KO := 10
const OLD_ZAL_HOLD := 3
const HAND := 5
const U := 3
const T := 8
const R := 9

const BASE_SEED := 0xD0E109
const STYLES := ["tall", "wide", "aggro", "balanced", "smart"]
const CONFIGS := [
	{"id": "old", "label": "текущий KO/TKO/ширина", "cap": -1, "wf": 0, "wt": 0, "wz": 0},
	{"id": "board11", "label": "формула 1Р+1Т, без зала", "cap": 0, "wf": 1, "wt": 1, "wz": 0},
	{"id": "sum111", "label": "формула 1Р+1Т+1З", "cap": 5, "wf": 1, "wt": 1, "wz": 1},
	{"id": "sum211", "label": "формула 2Р+1Т+1З", "cap": 5, "wf": 2, "wt": 1, "wz": 1},
	{"id": "sum311", "label": "формула 3Р+1Т+1З", "cap": 5, "wf": 3, "wt": 1, "wz": 1},
]

var _ai: RefCounted
var _failures := 0


## Симуляционный наследник: только новая терминальная логика и независимый зал.
class FormulaRules extends "res://duelogue/core/rules/rules_core.gd":
	var hall := 0                     ## + в пользу YOU
	var hall_cap := 5
	var frame_weight := 1
	var thesis_weight := 1
	var hall_weight := 1
	var final_board_diff := 0         ## P_you - P_opp
	var final_hall := 0
	var final_margin := 0             ## V
	var old_decision_winner := ""     ## кто выиграл бы на ЭТОЙ доске по ширине→старому залу

	func zal() -> int:
		if hall_cap <= 0:
			return 0
		return clampi(hall + zal_bias, -hall_cap, hall_cap)

	func board_weight(side: String) -> int:
		return frame_weight * score(side) + thesis_weight * shine(side)

	## Нет отдельного KO/TKO и нет автоматического redeploy. Если легальных глаголов нет,
	## сторона пасует даже при картах в руке (например, остались лишь Тезисы без рамки).
	func begin_turn(side: String) -> String:
		if game_over:
			return "over"
		var s: Dictionary = sides[side]
		for ln in s.lines:
			if ln.get("braced", false):
				ln.braced = false
		_try_second_wind(s)
		if legal_types(side).is_empty():
			s.passed = true
			if sides[other(side)].passed:
				_end_by_decision()
				return "end"
			return "pass"
		s.passed = false
		return "ok"

	## Один завершённый публичный обмен = один пункт впечатления победителю обмена.
	func _finish_clinch() -> Dictionary:
		var result: Dictionary = super._finish_clinch()
		if String(result.get("event", "")) == "resolved" and hall_cap > 0:
			var exchange_winner := String(result.attacker) if bool(result.landed) else String(result.defender)
			var delta := 1 if exchange_winner == SIDE_YOU else -1
			hall = clampi(hall + delta, -hall_cap, hall_cap)
		return result

	## ЕДИНСТВЕННЫЙ вердикт: знак (вес доски + независимый зал).
	func _end_by_decision() -> void:
		game_over = true
		final_board_diff = board_weight(SIDE_YOU) - board_weight(SIDE_OPP)
		final_hall = zal()
		final_margin = final_board_diff + hall_weight * final_hall
		old_decision_winner = _old_winner_on_this_board()
		if final_margin > 0:
			winner = SIDE_YOU
			end_reason = "verdict"
		elif final_margin < 0:
			winner = SIDE_OPP
			end_reason = "verdict"
		else:
			winner = ""
			end_reason = "draw"

	func _old_winner_on_this_board() -> String:
		var frame_diff := score(SIDE_YOU) - score(SIDE_OPP)
		if frame_diff > 0:
			return SIDE_YOU
		if frame_diff < 0:
			return SIDE_OPP
		# При равенстве ширины старый производный зал эквивалентен разнице тезисов.
		var thesis_diff := shine(SIDE_YOU) - shine(SIDE_OPP)
		if thesis_diff > 0:
			return SIDE_YOU
		if thesis_diff < 0:
			return SIDE_OPP
		return ""


## Сим-бот, осведомлённый о новой целевой функции 3Р+1Т+1З. Это НЕ production-ai:
## нужен, чтобы старая эвристика «ширина сначала» не подменяла тест нового вердикта.
class VerdictAi extends "res://duelogue/core/ai/ai.gd":
	const STYLE_VERDICT := "verdict"
	const STYLE_VERDICT_5 := "verdict5"
	const STYLE_VERDICT_9 := "verdict9"
	const STYLE_VERDICT_CALM := "verdict_calm"
	const W_FRAME := 3

	func pick(r: RefCounted, side: String, style: String) -> Dictionary:
		if not _is_verdict_style(style):
			return super.pick(r, side, style)
		return _apply_named(r, side, _pick_verdict(r, side, style))

	func _pick_verdict(r: RefCounted, side: String, style: String) -> Dictionary:
		var legal: Array = r.legal_types(side)
		if legal.is_empty():
			return {}
		var opp: String = r.other(side)
		var mine: Array = r.sides[side].lines
		var theirs: Array = r.sides[opp].lines

		# Без собственной позиции Тезисы мертвы, но матч не проигран: сначала вернуться
		# Установкой; если её нет — продолжать teardown Разбором.
		if mine.is_empty():
			if legal.has(TYPE_USTANOVKA):
				return {"type": TYPE_USTANOVKA}
			if legal.has(TYPE_RAZBOR):
				return {"type": TYPE_RAZBOR, "target": _verdict_target(r, side)}

		# Максимальная конверсия: доступный захват Кражей. K2 фиксированы системно, бот
		# холдит их до этого окна (atk_prefer_steal ниже).
		if legal.has(TYPE_RAZBOR) and _v_has_steal(r, side):
			var cap_target := _v_capture_target(r, side)
			if cap_target >= 0:
				return {"type": TYPE_RAZBOR, "target": cap_target}

		# Активная рамка ниже порога чужого захвата: один Тезис защищает как минимум
		# W_FRAME+1 собственных очков от двойного переноса.
		if not mine.is_empty() and legal.has(TYPE_TEZIS):
			var active: Dictionary = mine[-1]
			if int(active.theses) <= int(r.capture_threshold(opp)):
				return {"type": TYPE_TEZIS}

		var target := _verdict_target(r, side)
		# Рамка на последнем тезисе стоит 4 очка: teardown приоритетнее обычной стройки.
		if legal.has(TYPE_RAZBOR) and target >= 0 and int(theirs[target].theses) <= 1:
			return {"type": TYPE_RAZBOR, "target": target}

		var margin := _v_margin(r, side)
		# Отстающий обязан уменьшать чужой вес; лидер сначала капитализирует рамки/тезисы.
		if _deficit_attack(style, margin) and legal.has(TYPE_RAZBOR) and target >= 0:
			return {"type": TYPE_RAZBOR, "target": target}
		if legal.has(TYPE_USTANOVKA):
			return {"type": TYPE_USTANOVKA}
		if legal.has(TYPE_TEZIS):
			return {"type": TYPE_TEZIS}
		if legal.has(TYPE_RAZBOR) and target >= 0:
			return {"type": TYPE_RAZBOR, "target": target}
		return {"type": legal[0]}

	func def_will_clinch(r: RefCounted, defender: String, line: Dictionary) -> bool:
		if not _is_verdict_style(String(style_of.get(defender, ""))):
			return super.def_will_clinch(r, defender, line)
		var tez := _v_hand_count(r, defender, TYPE_TEZIS)
		if tez == 0:
			return false
		var attacker: String = String(r.other(defender))
		# Захват переводит вес дважды — такое окно закрывается обязательно.
		if int(line.theses) <= int(r.capture_threshold(attacker)):
			return true
		# Последняя позиция не является KO, но без неё оставшиеся Тезисы становятся мёртвыми.
		if r.sides[defender].lines.size() == 1:
			return true
		# Дешёвую рамку не перекармливаем последним Тезисом; дорогую/закрытую сохраняем.
		var line_value := W_FRAME + int(line.theses)
		return tez >= 2 or line_value >= 6 or bool(line.get("closed", false)) and tez >= 1

	func atk_will_clinch(r: RefCounted, attacker: String, line: Dictionary) -> bool:
		if not _is_verdict_style(String(style_of.get(attacker, ""))):
			return super.atk_will_clinch(r, attacker, line)
		var atk := _v_hand_count(r, attacker, TYPE_RAZBOR)
		if atk == 0:
			return false
		if int(line.theses) <= 1:
			return true
		# Активная Кража и досягаемая рамка оправдывают дожим даже последней атакой.
		if int(r.clinch.get("atk_steals", 0)) > 0 \
				and int(line.theses) <= int(r.capture_threshold(attacker)):
			return true
		# В минусе принимаем риск; в плюсе нужен резерв, чтобы не отдать зал пустым ралли.
		if _v_margin(r, attacker) < 0:
			return true
		return atk >= 2

	func atk_prefer_steal(r: RefCounted, attacker: String, defender: String, idx: int) -> bool:
		if not _is_verdict_style(String(style_of.get(attacker, ""))):
			return super.atk_prefer_steal(r, attacker, defender, idx)
		var lines: Array = r.sides[defender].lines
		if idx < 0 or idx >= lines.size():
			return false
		return int(lines[idx].theses) <= int(r.capture_threshold(attacker))

	func _v_margin(r: RefCounted, side: String) -> int:
		var opp: String = String(r.other(side))
		var raw := W_FRAME * (int(r.score(side)) - int(r.score(opp))) \
			+ int(r.shine(side)) - int(r.shine(opp))
		var hall_for_side := int(r.zal()) if side == SIDE_YOU else -int(r.zal())
		return raw + hall_for_side

	func _verdict_target(r: RefCounted, side: String) -> int:
		var lines: Array = r.sides[r.other(side)].lines
		var best := -1
		var best_score := -999999.0
		for i in lines.size():
			var ln: Dictionary = lines[i]
			var theses := int(ln.theses)
			var value := W_FRAME + theses
			# Выбираем лучший вес на требуемое число успешных чипов; закрытая рамка чуть
			# привлекательнее, потому что её нельзя усиливать обычным собственным ходом.
			var efficiency := float(value) / float(maxi(1, theses))
			if theses == 1:
				efficiency += 10.0
			if bool(ln.get("closed", false)):
				efficiency += 0.25
			if efficiency > best_score:
				best_score = efficiency
				best = i
		return best

	func _v_capture_target(r: RefCounted, side: String) -> int:
		var threshold := int(r.capture_threshold(side))
		var lines: Array = r.sides[r.other(side)].lines
		var best := -1
		var best_value := -1
		for i in lines.size():
			var ln: Dictionary = lines[i]
			if int(ln.theses) > threshold or r.is_fortified(ln) or ln.get("braced", false):
				continue
			var value := W_FRAME + int(ln.theses)
			if value > best_value:
				best_value = value
				best = i
		return best

	func _v_hand_count(r: RefCounted, side: String, type: String) -> int:
		var n := 0
		for card in r.sides[side].hand:
			if String(card.type) == type:
				n += 1
		return n

	func _v_has_steal(r: RefCounted, side: String) -> bool:
		for card in r.sides[side].hand:
			if String(card.type) == TYPE_RAZBOR and bool(card.get("steals", false)):
				return true
		return false

	func _is_verdict_style(style: String) -> bool:
		return style == STYLE_VERDICT or style == STYLE_VERDICT_5 or style == STYLE_VERDICT_9 \
			or style == STYLE_VERDICT_CALM

	func _deficit_attack(style: String, margin: int) -> bool:
		match style:
			STYLE_VERDICT:
				return margin < 0
			STYLE_VERDICT_5:
				return margin <= -5
			STYLE_VERDICT_9:
				return margin <= -9
			_:
				return false


func _ready() -> void:
	_ai = VerdictAi.new()
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	if OS.get_cmdline_user_args().has("--policy-threshold"):
		print("\n=== ЕДИНЫЙ ВЕРДИКТ · ПОРОГ РЕАКТИВНОГО TEARDOWN ===")
		_policy_threshold_suite()
		print("\nПроверки инвариантов: %s" % ("OK" if _failures == 0 else "ОШИБОК: %d" % _failures))
		print("=== КОНЕЦ (%.1f c) ===\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
		get_tree().quit(0 if _failures == 0 else 1)
		return
	if OS.get_cmdline_user_args().has("--gate-only"):
		print("\n=== ЕДИНЫЙ ВЕРДИКТ · СЦЕПКА НЕЗАВИСИМОГО ЗАЛА С ГЕЙТОМ ===")
		_gate_suite()
		print("\nПроверки инвариантов: %s" % ("OK" if _failures == 0 else "ОШИБОК: %d" % _failures))
		print("=== КОНЕЦ (%.1f c) ===\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
		get_tree().quit(0 if _failures == 0 else 1)
		return
	if OS.get_cmdline_user_args().has("--initiative-only"):
		print("\n=== ЕДИНЫЙ ВЕРДИКТ · СВИП ПЕРВОГО СЛОВА ===")
		_initiative_suite()
		print("\nПроверки инвариантов: %s" % ("OK" if _failures == 0 else "ОШИБОК: %d" % _failures))
		print("=== КОНЕЦ (%.1f c) ===\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
		get_tree().quit(0 if _failures == 0 else 1)
		return
	if OS.get_cmdline_user_args().has("--verdict-ai"):
		print("\n=== ЕДИНЫЙ ВЕРДИКТ · FIXED K2 + VERDICT-AWARE BOT ===")
		_verdict_ai_suite()
		print("\nПроверки инвариантов: %s" % ("OK" if _failures == 0 else "ОШИБОК: %d" % _failures))
		print("=== КОНЕЦ (%.1f c) ===\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
		get_tree().quit(0 if _failures == 0 else 1)
		return
	if OS.get_cmdline_user_args().has("--capture-only"):
		print("\n=== ЕДИНЫЙ ВЕРДИКТ · ЧУВСТВИТЕЛЬНОСТЬ К КРАЖАМ ===")
		_capture_suite()
		print("\nПроверки инвариантов: %s" % ("OK" if _failures == 0 else "ОШИБОК: %d" % _failures))
		print("=== КОНЕЦ (%.1f c) ===\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
		get_tree().quit(0 if _failures == 0 else 1)
		return
	print("\n=== ЕДИНЫЙ ВЕРДИКТ · ИЗОЛИРОВАННЫЙ СИМ (U%d T%d R%d, гейт %d/%d, лут=всё) ===" % [
		U, T, R, GATE_X, GATE_Y])
	print("Формула: V = wР·Δрамки + 1·Δтезисы + 1·независимый зал")
	print("Зал: ±1 победителю клинча, кап ±5. Свип wР=1/2/3. Точный V=0 пока ничья.\n")

	_mirror_suite()
	_field_suite()
	_matrix_hall5()
	_deck_suite()
	_capture_suite()

	print("\nПроверки инвариантов: %s" % ("OK" if _failures == 0 else "ОШИБОК: %d" % _failures))
	print("=== КОНЕЦ (%.1f c) ===\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit(0 if _failures == 0 else 1)


# ----------------------------------------------------------------- создание ---

func _new_match(config: Dictionary, first: String, deck_you: Dictionary = {}, deck_opp: Dictionary = {}) -> RefCounted:
	var m: RefCounted
	if String(config.id) == "old":
		m = Rules.new()
		m.reset(first, U, T, R, HAND, BASE, KOMI, STEAL, FORT,
			CLINCH, FREEZE, CAPTURE, GATE_X, GATE_Y, SW, LOOT, OLD_ZAL_KO, OLD_ZAL_HOLD)
	else:
		var fm := FormulaRules.new()
		fm.hall_cap = int(config.cap)
		fm.frame_weight = int(config.wf)
		fm.thesis_weight = int(config.wt)
		fm.hall_weight = int(config.wz)
		var gate_x := int(config.get("gate_x", GATE_X))
		var gate_y := int(config.get("gate_y", GATE_Y))
		fm.reset(first, U, T, R, HAND, BASE, KOMI, STEAL, FORT,
			CLINCH, FREEZE, CAPTURE, gate_x, gate_y, SW, LOOT, 0, 1)
		var opening_hall := int(config.get("opening_hall", 0))
		if opening_hall != 0:
			fm.hall = opening_hall if first == Rules.SIDE_YOU else -opening_hall
		m = fm
	if not deck_you.is_empty():
		m.sides[Rules.SIDE_YOU] = _build_side(deck_you)
	if not deck_opp.is_empty():
		m.sides[Rules.SIDE_OPP] = _build_side(deck_opp)
	return m


func _build_side(comp: Dictionary) -> Dictionary:
	return Deck.build_side(int(comp.u), int(comp.t), int(comp.r), BASE,
		mini(int(comp.get("steals", STEAL)), int(comp.r)), HAND)


func _seed_for(i: int, salt: int) -> void:
	seed(BASE_SEED + i * 104729 + salt * 1009)


# ------------------------------------------------------------------ метрики ---

func _blank_metrics() -> Dictionary:
	return {
		"wins_you": 0, "wins_opp": 0, "draws": 0, "first_wins": 0, "decisive": 0,
		"turns": 0, "captures": 0, "capture_theses": 0,
		"board_diff_abs": 0, "hall_abs": 0, "margin_abs": 0, "hall_sum": 0,
		"hall_saturated": 0, "old_disagree": 0, "tall_wins": 0, "wide_wins": 0,
		"hall_overturns": 0, "hall_breaks_board_tie": 0, "zero_frame_wins": 0,
	}


func _run_cell(config: Dictionary, style_you: String, style_opp: String, matches: int,
		deck_you: Dictionary = {}, deck_opp: Dictionary = {}, salt: int = 0) -> Dictionary:
	var out := _blank_metrics()
	for i in matches:
		_seed_for(i, salt)
		var first := Rules.SIDE_YOU if i % 2 == 0 else Rules.SIDE_OPP
		var m := _new_match(config, first, deck_you, deck_opp)
		var res: Dictionary = _ai.simulate(m, style_you, style_opp)
		var win := String(res.winner)
		if win == Rules.SIDE_YOU:
			out.wins_you += 1
		elif win == Rules.SIDE_OPP:
			out.wins_opp += 1
		else:
			out.draws += 1
		if win != "":
			out.decisive += 1
			if win == first:
				out.first_wins += 1
		out.turns += int(res.turns)
		out.captures += int(res.captures)
		out.capture_theses += int(m.capture_theses)

		if String(config.id) != "old":
			_collect_formula_metrics(out, m)
	return out


func _collect_formula_metrics(out: Dictionary, m: RefCounted) -> void:
	var board_diff := int(m.final_board_diff)
	var hall := int(m.final_hall)
	var margin := int(m.final_margin)
	var win := String(m.winner)
	out.board_diff_abs += absi(board_diff)
	out.hall_abs += absi(hall)
	out.margin_abs += absi(margin)
	out.hall_sum += hall
	if int(m.hall_cap) > 0 and absi(hall) >= int(m.hall_cap):
		out.hall_saturated += 1
	if win != String(m.old_decision_winner):
		out.old_disagree += 1

	var frame_diff: int = int(m.score(Rules.SIDE_YOU)) - int(m.score(Rules.SIDE_OPP))
	var thesis_diff: int = int(m.shine(Rules.SIDE_YOU)) - int(m.shine(Rules.SIDE_OPP))
	var sign_win := 1 if win == Rules.SIDE_YOU else (-1 if win == Rules.SIDE_OPP else 0)
	if sign_win != 0:
		if frame_diff * sign_win < 0 and thesis_diff * sign_win > 0:
			out.tall_wins += 1
		if frame_diff * sign_win > 0 and thesis_diff * sign_win < 0:
			out.wide_wins += 1
		if board_diff * sign_win < 0:
			out.hall_overturns += 1
		if board_diff == 0 and hall * sign_win > 0:
			out.hall_breaks_board_tie += 1
		if m.score(win) == 0:
			out.zero_frame_wins += 1

	# Инварианты самой формулы.
	if margin != board_diff + int(m.hall_weight) * hall:
		_failures += 1
	if (margin > 0 and win != Rules.SIDE_YOU) or (margin < 0 and win != Rules.SIDE_OPP) \
			or (margin == 0 and win != ""):
		_failures += 1
	if int(m.hall_cap) >= 0 and absi(hall) > int(m.hall_cap):
		_failures += 1
	if String(m.end_reason) == "knockout" or String(m.end_reason) == "crowd":
		_failures += 1


func _pct(n: int, d: int) -> float:
	return float(n) / float(maxi(1, d)) * 100.0


func _winrate(m: Dictionary) -> float:
	return float(m.wins_you) / float(maxi(1, int(m.decisive)))


# --------------------------------------------------------------- зеркало ------

func _mirror_suite() -> void:
	print("--- 1. SMART-ЗЕРКАЛО: здоровье формулы и цена независимого зала (%d матчей) ---" % mirror_matches)
	print("%-29s | winЫ 1йход нич | ходы капч | |B| |Z| |V| | Δстар | tall wide Zflip Ztie Zcap" % "правило")
	for config in CONFIGS:
		var m := _run_cell(config, "smart", "smart", mirror_matches, {}, {}, 11)
		if String(config.id) == "old":
			print("%-29s | %4.1f%% %5.1f%% %3.1f%% | %4.1f %4.2f |  —   —   —  |   —     —    —    —    —    —" % [
				String(config.label), _pct(int(m.wins_you), mirror_matches),
				_pct(int(m.first_wins), int(m.decisive)), _pct(int(m.draws), mirror_matches),
				float(m.turns) / mirror_matches, float(m.captures) / mirror_matches])
			continue
		print("%-29s | %4.1f%% %5.1f%% %3.1f%% | %4.1f %4.2f | %3.1f %3.1f %3.1f | %5.1f%% %4.1f%% %4.1f%% %4.1f%% %4.1f%% %4.1f%%" % [
			String(config.label), _pct(int(m.wins_you), mirror_matches),
			_pct(int(m.first_wins), int(m.decisive)), _pct(int(m.draws), mirror_matches),
			float(m.turns) / mirror_matches, float(m.captures) / mirror_matches,
			float(m.board_diff_abs) / mirror_matches, float(m.hall_abs) / mirror_matches,
			float(m.margin_abs) / mirror_matches, _pct(int(m.old_disagree), mirror_matches),
			_pct(int(m.tall_wins), int(m.decisive)), _pct(int(m.wide_wins), int(m.decisive)),
			_pct(int(m.hall_overturns), int(m.decisive)), _pct(int(m.hall_breaks_board_tie), int(m.decisive)),
			_pct(int(m.hall_saturated), mirror_matches)])
		if int(m.captures) > 0:
			var avg_capture_theses := float(m.capture_theses) / float(m.captures)
			var cap_weight := float(config.wf) + float(config.wt) * avg_capture_theses
			print("    средний вес захваченной рамки %.2f → средний свинг перевеса %.2f" % [cap_weight, cap_weight * 2.0])
	print("Чтение: Δстар — новый победитель расходится со старым решением ширина→глубина;")
	print("tall/wide — победитель уступал соответственно по рамкам/тезисам; Zflip — зал перевернул")
	print("уже ненулевой перевес доски; Ztie — зал решил равную по весу доску; Zcap — упёрся в кап.\n")


# ------------------------------------------------------------- поле стилей ----

func _field_suite() -> void:
	print("--- 2. ПОЛЕ СТИЛЕЙ: средний винрейт против четырёх остальных (%d/пара) ---" % field_matches)
	print("%-29s | tall wide aggr  bal SMART | разброс" % "правило")
	for config in CONFIGS:
		var rates := {}
		for s in STYLES:
			var sum := 0.0
			for o in STYLES:
				if o == s:
					continue
				var salt := 100 + STYLES.find(s) * 10 + STYLES.find(o)
				var m := _run_cell(config, s, o, field_matches, {}, {}, salt)
				sum += _winrate(m)
			rates[s] = sum / float(STYLES.size() - 1)
		var vals: Array = rates.values()
		var lo := float(vals.min())
		var hi := float(vals.max())
		print("%-29s | %4.0f%% %4.0f%% %4.0f%% %4.0f%% %4.0f%% | %4.0f пп" % [
			String(config.label), float(rates.tall) * 100.0, float(rates.wide) * 100.0,
			float(rates.aggro) * 100.0, float(rates.balanced) * 100.0,
			float(rates.smart) * 100.0, (hi - lo) * 100.0])
	print("Сторож: формула не должна делать tall или wide единственной доминантой; smart-бот,")
	print("однако, всё ещё обучен старому приоритету ширины — это консервативный, не финальный тест.\n")


func _matrix_hall5() -> void:
	var config: Dictionary = CONFIGS[2]
	print("--- 3. МАТРИЦА СТИЛЕЙ для формулы 1Р+1Т+1З (строка YOU против столбца OPP) ---")
	var header := "%10s" % ""
	for col in STYLES:
		header += " %8s" % col
	print(header)
	for ri in STYLES.size():
		var row_style: String = STYLES[ri]
		var line := "%10s" % row_style
		for ci in STYLES.size():
			var col_style: String = STYLES[ci]
			var m := _run_cell(config, row_style, col_style, field_matches, {}, {}, 300 + ri * 10 + ci)
			line += " %7.0f%%" % (_winrate(m) * 100.0)
		print(line)
	print("")


# ------------------------------------------------------- составы обоймы -------

func _deck_suite() -> void:
	var decks := [
		{"label": "канон 3/8/9", "u": 3, "t": 8, "r": 9, "steals": 2},
		{"label": "глубина 2/12/6", "u": 2, "t": 12, "r": 6, "steals": 2},
		{"label": "ширина 5/7/8", "u": 5, "t": 7, "r": 8, "steals": 2},
		{"label": "разбор 2/6/12", "u": 2, "t": 6, "r": 12, "steals": 2},
		{"label": "смешанная 4/9/7", "u": 4, "t": 9, "r": 7, "steals": 2},
	]
	print("--- 4. АРХЕТИПЫ ОБОЙМЫ: выбранная YOU против канона OPP, smart (%d матчей) ---" % deck_matches)
	print("%-22s | старые | 1Р+1Т+1З | 2Р+1Т+1З | 3Р+1Т+1З" % "обойма YOU")
	for i in decks.size():
		var comp: Dictionary = decks[i]
		var old := _run_cell(CONFIGS[0], "smart", "smart", deck_matches, comp, {}, 500 + i)
		var formula1 := _run_cell(CONFIGS[2], "smart", "smart", deck_matches, comp, {}, 500 + i)
		var formula2 := _run_cell(CONFIGS[3], "smart", "smart", deck_matches, comp, {}, 500 + i)
		var formula3 := _run_cell(CONFIGS[4], "smart", "smart", deck_matches, comp, {}, 500 + i)
		var old_wr := _winrate(old) * 100.0
		print("%-22s | %5.1f%% | %8.1f%% | %8.1f%% | %8.1f%%" % [
			String(comp.label), old_wr, _winrate(formula1) * 100.0,
			_winrate(formula2) * 100.0, _winrate(formula3) * 100.0])
	print("Сторож: край >60%% или <40%% против канона — формула сама по себе не балансит")
	print("составы и требует коридоров/цен карт либо иной экономики.\n")


func _capture_suite() -> void:
	print("--- 5. ЧУВСТВИТЕЛЬНОСТЬ К КРАЖАМ: YOU K0…K4 против канона K2, smart (%d матчей) ---" % deck_matches)
	print("%-12s | старые условия | 3Р+1Т+1З | дельта к K2 новой формулы" % "Кражи YOU")
	var baseline_formula := 0.0
	var rows: Array = []
	for steals in range(0, 5):
		var comp := {"u": U, "t": T, "r": R, "steals": steals}
		var old := _run_cell(CONFIGS[0], "smart", "smart", deck_matches, comp, {}, 800 + steals)
		var formula := _run_cell(CONFIGS[4], "smart", "smart", deck_matches, comp, {}, 800 + steals)
		var fwr := _winrate(formula) * 100.0
		if steals == STEAL:
			baseline_formula = fwr
		rows.append({"steals": steals, "old": _winrate(old) * 100.0, "formula": fwr})
	for row in rows:
		print("K%-11d | %8.1f%%       | %8.1f%% | %+8.1f пп" % [
			int(row.steals), float(row.old), float(row.formula), float(row.formula) - baseline_formula])
	print("Сторож: шаг одной Кражи желательно держать в пределах ~5–7 пп; более крутая")
	print("лестница означает, что двойной перенос веса рамки диктует состав обоймы.\n")


func _verdict_ai_suite() -> void:
	var config: Dictionary = CONFIGS[4]  # 3Р+1Т+1З, зал±5
	var n := deck_matches
	print("Условия: формула 3Р+1Т+1З; обе обоймы всегда содержат ровно K2; %d матчей/ячейку.\n" % n)

	print("--- A. ЗЕРКАЛО НОВОЙ ПОЛИТИКИ ---")
	var mirror := _run_cell(config, "verdict", "verdict", n, {}, {}, 900)
	print("verdict vs verdict: YOU %.1f%% | 1-й ход %.1f%% | ничьи %.1f%% | ходы %.1f | захваты %.2f" % [
		_pct(int(mirror.wins_you), n), _pct(int(mirror.first_wins), int(mirror.decisive)),
		_pct(int(mirror.draws), n), float(mirror.turns) / n, float(mirror.captures) / n])
	print("исходы: новый≠старого %.1f%% | tall-win %.1f%% | wide-win %.1f%% | Zflip %.1f%% | Ztie %.1f%%" % [
		_pct(int(mirror.old_disagree), n), _pct(int(mirror.tall_wins), int(mirror.decisive)),
		_pct(int(mirror.wide_wins), int(mirror.decisive)),
		_pct(int(mirror.hall_overturns), int(mirror.decisive)),
		_pct(int(mirror.hall_breaks_board_tie), int(mirror.decisive))])

	print("\n--- B. PAIRED POLICY DUEL: новая эвристика против старого smart ---")
	var v_you := _run_cell(config, "verdict", "smart", n, {}, {}, 910)
	var s_you := _run_cell(config, "smart", "verdict", n, {}, {}, 910)
	var v_as_you := _winrate(v_you)
	var v_as_opp := 1.0 - _winrate(s_you)
	var paired_v := (v_as_you + v_as_opp) * 0.5
	print("verdict как YOU: %.1f%% | verdict как OPP: %.1f%% | среднее: %.1f%%" % [
		v_as_you * 100.0, v_as_opp * 100.0, paired_v * 100.0])
	print("Сторож: >55%% означает, что новая политика действительно читает новую цель;")
	print("<50%% — эвристика хуже старого smart и не годится для выводов о потолке.")

	print("\n--- C. VERDICT ПРОТИВ СТАРЫХ СТИЛЕЙ (обе ориентации мест) ---")
	print("%-10s | V как YOU | V как OPP | среднее" % "соперник")
	for oi in STYLES.size():
		var opp_style: String = STYLES[oi]
		var a := _run_cell(config, "verdict", opp_style, n, {}, {}, 930 + oi)
		var b := _run_cell(config, opp_style, "verdict", n, {}, {}, 930 + oi)
		var va := _winrate(a)
		var vb := 1.0 - _winrate(b)
		print("%-10s | %7.1f%% | %7.1f%% | %7.1f%%" % [opp_style, va * 100.0, vb * 100.0,
			(va + vb) * 50.0])

	var decks := [
		{"label": "канон 3/8/9", "u": 3, "t": 8, "r": 9, "steals": 2},
		{"label": "глубина 2/12/6", "u": 2, "t": 12, "r": 6, "steals": 2},
		{"label": "ширина 5/7/8", "u": 5, "t": 7, "r": 8, "steals": 2},
		{"label": "разбор 2/6/12", "u": 2, "t": 6, "r": 12, "steals": 2},
		{"label": "смешанная 4/9/7", "u": 4, "t": 9, "r": 7, "steals": 2},
	]
	print("\n--- D. ОБОЙМЫ С FIXED K2: verdict-пилот с обеих сторон ---")
	print("%-22s | винрейт против канона" % "обойма YOU")
	for i in decks.size():
		var comp: Dictionary = decks[i]
		var m := _run_cell(config, "verdict", "verdict", n, comp, {}, 960 + i)
		print("%-22s | %7.1f%%" % [String(comp.label), _winrate(m) * 100.0])
	print("Сторож: все конструктивные архетипы желательно удержать в 40–60%%; выход за коридор")
	print("означает, что одной фиксации K2 недостаточно.\n")


func _initiative_suite() -> void:
	var n := mirror_matches
	print("Условия: verdict vs verdict, fixed K2, формула 3Р+1Т+1З, %d матчей/ячейку." % n)
	print("Значение — публичный стартовый зал относительно стороны первого слова; минус")
	print("делает первого андердогом и одновременно расширяет его порог Кражи через гейт.\n")
	print("%-12s | 1-й ход | ничьи | YOU wins | ходы | захваты | Zcap" % "старт. зал")
	for bonus in range(-4, 3):
		var config: Dictionary = CONFIGS[4].duplicate(true)
		config["opening_hall"] = bonus
		var m := _run_cell(config, "verdict", "verdict", n, {}, {}, 990)
		print("зал %+d       | %7.1f%% | %5.1f%% | %7.1f%% | %5.1f | %7.2f | %4.1f%%" % [
			bonus, _pct(int(m.first_wins), int(m.decisive)), _pct(int(m.draws), n),
			_pct(int(m.wins_you), n), float(m.turns) / n, float(m.captures) / n,
			_pct(int(m.hall_saturated), n)])
	print("Сторож: первый ход 45–55%% без заметного роста капа/доминанты. Если баланс даёт")
	print("только ОТРИЦАТЕЛЬНЫЙ зал, стартовый bias — не лечение: он вскрывает сцепку зал→гейт.\n")


func _gate_suite() -> void:
	var gates := [[0, 0], [3, 5], [2, 4]]
	var n := mirror_matches
	print("Условия: verdict vs verdict, fixed K2, 3Р+1Т+1З, стартовый зал 0.")
	print("Меняется только порог захвата, читающий независимый зал.\n")
	print("%-10s | 1-й ход | ничьи | ходы | захваты | Zflip | tall | wide" % "гейт")
	for gi in gates.size():
		var gate: Array = gates[gi]
		var config: Dictionary = CONFIGS[4].duplicate(true)
		config["gate_x"] = int(gate[0])
		config["gate_y"] = int(gate[1])
		var m := _run_cell(config, "verdict", "verdict", n, {}, {}, 1030)
		var label := "выкл" if int(gate[0]) == 0 else "%d/%d" % [int(gate[0]), int(gate[1])]
		print("%-10s | %7.1f%% | %5.1f%% | %5.1f | %7.2f | %5.1f%% | %4.1f%% | %4.1f%%" % [
			label, _pct(int(m.first_wins), int(m.decisive)), _pct(int(m.draws), n),
			float(m.turns) / n, float(m.captures) / n,
			_pct(int(m.hall_overturns), int(m.decisive)), _pct(int(m.tall_wins), int(m.decisive)),
			_pct(int(m.wide_wins), int(m.decisive))])

	var decks := [
		{"label": "глубина 2/12/6", "u": 2, "t": 12, "r": 6, "steals": 2},
		{"label": "ширина 5/7/8", "u": 5, "t": 7, "r": 8, "steals": 2},
		{"label": "разбор 2/6/12", "u": 2, "t": 6, "r": 12, "steals": 2},
	]
	print("\nАрхетип YOU против канона OPP под теми же гейтами (%d матчей):" % deck_matches)
	print("%-20s | гейт выкл | гейт 3/5 | гейт 2/4" % "обойма")
	for di in decks.size():
		var comp: Dictionary = decks[di]
		var rates: Array = []
		for gi in gates.size():
			var gate: Array = gates[gi]
			var config: Dictionary = CONFIGS[4].duplicate(true)
			config["gate_x"] = int(gate[0])
			config["gate_y"] = int(gate[1])
			var m := _run_cell(config, "verdict", "verdict", deck_matches, comp, {}, 1060 + di)
			rates.append(_winrate(m) * 100.0)
		print("%-20s | %8.1f%% | %8.1f%% | %8.1f%%" % [String(comp.label),
			float(rates[0]), float(rates[1]), float(rates[2])])
	print("Сторож: если отключение гейта возвращает инициативу и wide в коридор, независимый зал")
	print("не может одновременно быть финальным судьёй и источником порога захвата.\n")


func _policy_threshold_suite() -> void:
	var config: Dictionary = CONFIGS[4]
	var styles := ["verdict", "verdict5", "verdict9", "verdict_calm"]
	var labels := {
		"verdict": "минус <0",
		"verdict5": "минус ≤−5",
		"verdict9": "минус ≤−9",
		"verdict_calm": "не реагирует",
	}
	var wide := {"u": 5, "t": 7, "r": 8, "steals": 2}
	var n := mirror_matches
	print("Условия: fixed K2, 3Р+1Т+1З, гейт 2/4. Меняется только порог, при котором")
	print("бот из-за текущего отрицательного V предпочитает Разбор стройке.\n")
	print("%-14s | 1-й ход | ничьи | против smart | wide→canon | ходы | капч" % "реакция")
	for si in styles.size():
		var style: String = styles[si]
		var mirror := _run_cell(config, style, style, n, {}, {}, 1100 + si)
		var a := _run_cell(config, style, "smart", deck_matches, {}, {}, 1120 + si)
		var b := _run_cell(config, "smart", style, deck_matches, {}, {}, 1120 + si)
		var vs_smart := (_winrate(a) + (1.0 - _winrate(b))) * 50.0
		var wide_m := _run_cell(config, style, style, deck_matches, wide, {}, 1140 + si)
		print("%-14s | %7.1f%% | %5.1f%% | %10.1f%% | %10.1f%% | %5.1f | %4.2f" % [
			String(labels[style]), _pct(int(mirror.first_wins), int(mirror.decisive)),
			_pct(int(mirror.draws), n), vs_smart, _winrate(wide_m) * 100.0,
			float(mirror.turns) / n, float(mirror.captures) / n])
	print("Сторож: ищем одновременно 45–55%% первого хода, преимущество над старым smart и")
	print("wide не ниже 40%%. Если коридоры несовместимы, простой heuristic-bot не даёт ответа")
	print("о балансе формулы — нужен lookahead/MCTS или ручной парный плейтест.\n")
