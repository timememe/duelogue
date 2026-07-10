extends Node

## ЗАБЕГ v0.1 — СИМ-ПРОВЕРКИ ПЕРЕД КОДОМ (спека zal_run_v0.1 §11): как ядро боя ляжет на
## полурогаликовый слой и какие ручки нужны геймлупу в первую очередь. Пять свипов:
##   A. Цена +1 карты (§11.1) — довод «колода-обойма: добор = чит, награда = ЗАМЕНА» (§1)
##   B. Стартовый крен зала (§11.2) — мета-вход репутации (§3.1, §4): сколько стоит крен
##   C. Стартовая заготовка (§11.3) — комната подготовки: не возвращает ли монетку 1-го хода
##   D. Края коридоров слотов (§11.4) — рамки свободы замен (§1: слоты-коридоры по типам)
##   E. Боссы-тумблеры vs smart-прокси игрока (§11.5) — бестиарий §5: есть ли контрплей
##      БЕЗ сюжетной карты-слабости
## Мета-входы и по-сторонние тумблеры навешаны сим-сабклассом MetaRules ПОВЕРХ ядра — само
## ядро правил не тронуто (инвариант §8.1); сим доказывает, каким ручкам становиться полями
## конфига battle_controller. Запуск: sim_run_layer.tscn (F6) или headless:
##   Godot --headless --path . res://duelogue/tools/sim_run_layer.tscn

const Rules := preload("res://duelogue/core/rules/rules_core.gd")
const Deck := preload("res://duelogue/core/cards/deck.gd")
const Ai := preload("res://duelogue/core/ai/ai.gd")

@export var matches_per_cell: int = 300

# --- Канон партии (= battle_controller / sim_tail; GDD v0.3.2) ---
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
const ZAL_KO := 10
const ZAL_HOLD := 3
const HAND := 5
const U := 3
const T := 8
const R := 9

var _ai: RefCounted


## Сим-обвязка: мета-входы забега (§3) и по-сторонние тумблеры боссов (§5) поверх ядра.
## В ядре зал — производная доски, поэтому «стартовый крен» здесь = ПОСТОЯННОЕ смещение
## стрелки (зал так и читает всю партию со сдвигом); тающий крен — отдельная итерация.
class MetaRules extends "res://duelogue/core/rules/rules_core.gd":
	var zal_bias := 0     ## крен зала: + в пользу YOU, − против (§3.1)
	var fort_side := ""   ## Догматик: рамки этой стороны укреплены при силе >= fort_at
	var fort_at := 0
	var sw_side := ""     ## Демагог: у стороны свой лимит «второго дыхания» (-1 = ∞)
	var sw_n := 0
	var ko_side := ""     ## Популист: у стороны свой порог TKO «унёс зал»
	var ko_at := 0
	var ko_hold := 1

	func zal() -> int:
		return clampi(super.zal() + zal_bias, -ZAL_MAX, ZAL_MAX)

	func is_fortified(line: Dictionary) -> bool:
		if fort_side == "":
			return super.is_fortified(line)
		if _owner_of(line) != fort_side:
			return false
		return int(line.theses) + int(line.get("stolen", 0)) >= fort_at

	func _owner_of(line: Dictionary) -> String:
		for side in [SIDE_YOU, SIDE_OPP]:
			for ln in sides[side].lines:
				if is_same(ln, line):
					return side
		return ""

	func _try_second_wind(s: Dictionary) -> void:
		if sw_side != "" and is_same(s, sides[sw_side]):
			var saved := second_wind
			second_wind = sw_n
			super._try_second_wind(s)
			second_wind = saved
			return
		super._try_second_wind(s)

	func begin_turn(side: String) -> String:
		if ko_side == "" or side != ko_side:
			return super.begin_turn(side)
		var saved_ko := zal_ko
		var saved_hold := zal_hold
		zal_ko = ko_at
		zal_hold = ko_hold
		var st := super.begin_turn(side)
		zal_ko = saved_ko
		zal_hold = saved_hold
		return st


func _ready() -> void:
	_ai = Ai.new()
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	print("\n=== ЗАБЕГ v0.1 · СИМЫ СЛОЯ (§11; канон: гейт %d/%d, лут=всё, TKO %d/%d, колода U%d T%d R%d; матчей/ячейку=%d) ===" % [
		GATE_X, GATE_Y, ZAL_KO, ZAL_HOLD, U, T, R, matches_per_cell])
	_sim_a_card_price()
	_sim_b_zal_bias()
	_sim_c_prep_board()
	_sim_d_corridors()
	_sim_e_bosses()
	print("\n=== КОНЕЦ (%.1f c) ===\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit()


func _new_match(first: String) -> MetaRules:
	var m := MetaRules.new()
	m.reset(first, U, T, R, HAND, BASE, KOMI, STEAL, FORT,
		CLINCH, FREEZE, CAPTURE, GATE_X, GATE_Y, SW, LOOT, ZAL_KO, ZAL_HOLD)
	return m


## Одна ячейка свипа: matches_per_cell матчей, tweak(m) правит модель после reset.
## fixed_first — зафиксировать первый ход (""= монетка). Печатает строку, возвращает метрики.
func _cell(label: String, style_you: String, style_opp: String, tweak: Callable, fixed_first := "") -> Dictionary:
	var wins_you := 0
	var ko := 0
	var crowd := 0
	var dec := 0
	var draw := 0
	var turns_sum := 0
	var caps_sum := 0
	for i in matches_per_cell:
		var first := fixed_first
		if first == "":
			first = Rules.SIDE_YOU if randf() < 0.5 else Rules.SIDE_OPP
		var m := _new_match(first)
		tweak.call(m)
		var res: Dictionary = _ai.simulate(m, style_you, style_opp)
		if String(res.winner) == Rules.SIDE_YOU:
			wins_you += 1
		match String(res.reason):
			"knockout": ko += 1
			"crowd": crowd += 1
			"decision": dec += 1
			"draw": draw += 1
		turns_sum += int(res.turns)
		caps_sum += int(res.captures)
	var n := float(matches_per_cell)
	var out := {
		"win": float(wins_you) / n * 100.0,
		"ko": float(ko) / n * 100.0, "crowd": float(crowd) / n * 100.0,
		"dec": float(dec) / n * 100.0, "draw": float(draw) / n * 100.0,
		"turns": float(turns_sum) / n, "caps": float(caps_sum) / n,
	}
	print("%-26s | %5.1f%% | %4.0f%% %5.0f%% %4.0f%% %4.0f%% | %5.1f | %4.2f" % [
		label, out.win, out.ko, out.crowd, out.dec, out.draw, out.turns, out.caps])
	return out


func _header() -> void:
	print("%-26s | win%%Ы | нок толпа реш нич | ходов | капч" % "конфиг")


func _noop(_m: RefCounted) -> void:
	pass


# --- A. Цена карты (§11.1): оппонент получает колоду 20+k, игрок — канон 20 ---

func _sim_a_card_price() -> void:
	print("\n--- A. ЦЕНА КАРТЫ (§11.1): opp раздут до 20+k, you=20; smart vs smart ---")
	_header()
	_cell("база 20 vs 20", "smart", "smart", _noop)
	_cell("20 vs 21 (+1 Тезис)", "smart", "smart",
		func(m: RefCounted) -> void: m.sides[Rules.SIDE_OPP] = Deck.build_side(U, T + 1, R, BASE, STEAL, HAND))
	_cell("20 vs 21 (+1 Разбор)", "smart", "smart",
		func(m: RefCounted) -> void: m.sides[Rules.SIDE_OPP] = Deck.build_side(U, T, R + 1, BASE, STEAL, HAND))
	_cell("20 vs 21 (+1 Установка)", "smart", "smart",
		func(m: RefCounted) -> void: m.sides[Rules.SIDE_OPP] = Deck.build_side(U + 1, T, R, BASE, STEAL, HAND))
	_cell("20 vs 22 (+Т+Р)", "smart", "smart",
		func(m: RefCounted) -> void: m.sides[Rules.SIDE_OPP] = Deck.build_side(U, T + 1, R + 1, BASE, STEAL, HAND))
	_cell("20 vs 25 (+2Т+2Р+1У)", "smart", "smart",
		func(m: RefCounted) -> void: m.sides[Rules.SIDE_OPP] = Deck.build_side(U + 1, T + 2, R + 2, BASE, STEAL, HAND))
	print("Вопрос: сколько винрейта стоит +1 карта (прайс кулуаров; довод «награда = ЗАМЕНА, не добор»).")


# --- B. Стартовый крен зала (§11.2): мета-вход репутации ---

func _sim_b_zal_bias() -> void:
	print("\n--- B. СТАРТОВЫЙ КРЕН ЗАЛА (§11.2): смещение стрелки; минус = зал ПРОТИВ игрока ---")
	for style in ["smart", "balanced"]:
		print("  · зеркало %s vs %s:" % [style, style])
		_header()
		for bias in [-6, -4, -2, 0, 2, 4, 6]:
			var b: int = bias
			_cell("крен %+d" % b, style, style,
				func(m: RefCounted) -> void: m.zal_bias = b)
	print("Вопрос: винрейт при крене −2/−4 (порог «злой зал» для репутации §4); гейт-комебек")
	print("        должен смягчать (капчи растут у андердога), TKO-толпа не должна взлетать.")


# --- C. Стартовая заготовка (§11.3): рамка с форой vs монетка первого хода ---

func _sim_c_prep_board() -> void:
	print("\n--- C. ЗАГОТОВКА (§11.3): +k тезисов на стартовую Базу; первый ход ФИКС за you ---")
	_header()
	_cell("база (you первый)", "smart", "smart", _noop, Rules.SIDE_YOU)
	_cell("+1 тезис you (первый)", "smart", "smart",
		func(m: RefCounted) -> void: m.sides[Rules.SIDE_YOU].lines[0].theses += 1, Rules.SIDE_YOU)
	_cell("+2 тезиса you (первый)", "smart", "smart",
		func(m: RefCounted) -> void: m.sides[Rules.SIDE_YOU].lines[0].theses += 2, Rules.SIDE_YOU)
	_cell("+1 тезис opp (второй)", "smart", "smart",
		func(m: RefCounted) -> void: m.sides[Rules.SIDE_OPP].lines[0].theses += 1, Rules.SIDE_YOU)
	_cell("+2 тезиса opp (второй)", "smart", "smart",
		func(m: RefCounted) -> void: m.sides[Rules.SIDE_OPP].lines[0].theses += 2, Rules.SIDE_YOU)
	print("Вопрос: не даёт ли заготовка первому ходу «монетку» (>60%); заодно — компенсирует ли")
	print("        +1/+2 второй ход (готовая калибровка коми и цены награды «Подготовки»).")


# --- D. Края коридоров слотов (§11.4): экстремальные обоймы (все — 20 карт) ---

func _sim_d_corridors() -> void:
	print("\n--- D. КРАЯ КОРИДОРОВ (§11.4): opp с экстремальной обоймой 20 vs канон-you; smart ---")
	_header()
	_cell("канон 3/8/9 (контроль)", "smart", "smart", _noop)
	_cell("max-атаки 3/5/12", "smart", "smart",
		func(m: RefCounted) -> void: m.sides[Rules.SIDE_OPP] = Deck.build_side(3, 5, 12, BASE, STEAL, HAND))
	_cell("max-тезисы 3/12/5", "smart", "smart",
		func(m: RefCounted) -> void: m.sides[Rules.SIDE_OPP] = Deck.build_side(3, 12, 5, BASE, STEAL, HAND))
	_cell("max-ширина 6/8/6", "smart", "smart",
		func(m: RefCounted) -> void: m.sides[Rules.SIDE_OPP] = Deck.build_side(6, 8, 6, BASE, STEAL, HAND))
	_cell("min-установки 1/10/9", "smart", "smart",
		func(m: RefCounted) -> void: m.sides[Rules.SIDE_OPP] = Deck.build_side(1, 10, 9, BASE, STEAL, HAND))
	_cell("кражи 4 из 9 атак", "smart", "smart",
		func(m: RefCounted) -> void: m.sides[Rules.SIDE_OPP] = Deck.build_side(U, T, R, BASE, 4, HAND))
	_cell("кражи 0 (без поимок)", "smart", "smart",
		func(m: RefCounted) -> void: m.sides[Rules.SIDE_OPP] = Deck.build_side(U, T, R, BASE, 0, HAND))
	print("Вопрос: где край коридора ломает баланс (доминанта >60%% или провал <40%%) — это")
	print("        рамки слотов для «замены» (§1: атаки ~7–11, установки ~2–5, кражи ~1–4).")


# --- E. Боссы-тумблеры (§11.5): игрок-прокси smart vs бестиарий §5 ---

func _sim_e_bosses() -> void:
	print("\n--- E. БОССЫ (§11.5): you=smart (канон) vs босс с тумблером; БЕЗ карты-слабости ---")
	_header()
	_cell("контроль: smart без твиста", "smart", "smart", _noop)
	_cell("Догматик tall (форт>=3)", "smart", "tall",
		func(m: RefCounted) -> void:
			m.fort_side = Rules.SIDE_OPP
			m.fort_at = 3)
	_cell("Догматик smart (форт>=3)", "smart", "smart",
		func(m: RefCounted) -> void:
			m.fort_side = Rules.SIDE_OPP
			m.fort_at = 3)
	_cell("Демагог bal (сброс=∞)", "smart", "balanced",
		func(m: RefCounted) -> void:
			m.sw_side = Rules.SIDE_OPP
			m.sw_n = -1)
	_cell("Демагог smart (сброс=∞)", "smart", "smart",
		func(m: RefCounted) -> void:
			m.sw_side = Rules.SIDE_OPP
			m.sw_n = -1)
	_cell("Популист wide (TKO 7/1)", "smart", "wide",
		func(m: RefCounted) -> void:
			m.ko_side = Rules.SIDE_OPP
			m.ko_at = 7
			m.ko_hold = 1)
	_cell("Популист smart (TKO 7/1)", "smart", "smart",
		func(m: RefCounted) -> void:
			m.ko_side = Rules.SIDE_OPP
			m.ko_at = 7
			m.ko_hold = 1)
	print("Вопрос: винрейт игрока 30–45%% = честная элитка/босс; <25%% — без сюжетной")
	print("        карты-слабости не обойтись (спека: слабость облегчает, не единственный ключ).")
