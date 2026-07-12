extends Node

## Изолированный тест связки «финальный зал -> репутация -> текущие run-события».
## Боевые правила не меняет. Одна и та же выборка из 20 smart-vs-smart боёв затем
## проигрывается тремя политиками выбора событий, чтобы сравнение было честным.

const Rules := preload("res://duelogue/core/rules/rules_core.gd")
const Ai := preload("res://duelogue/core/ai/ai.gd")
const RunEvents := preload("res://duelogue/core/run/run_events.gd")
const RunRules := preload("res://duelogue/core/run/run_rules.gd")

const MATCHES := 20
const DEFAULT_TEST_SEED := 20260710
const START_REP2 := 0    # нейтральная репутация 0.0
const REP_MIN2 := -100   # -50.0, в полуочках: 1 unit = 0.5 репутации
const REP_MAX2 := 100    # +50.0
const BATTLE_FEE := 3   # обычный «Эфир» текущего run-слоя даёт 2-3; берём верхнюю границу

const U := 3
const T := 8
const R := 9
const HAND := 5
const BASE := 1
const KOMI := 0
const STEALS := 2
const FORTIFY := 0
const CLINCH := true
const FREEZE := true
const CAPTURE := 1
const GATE_X := 2
const GATE_Y := 4
const SECOND_WIND := 0
const CAPTURE_LOOT := 1
const ZAL_KO := 10
const ZAL_HOLD := 3

## Стресс-расклад: событие после каждого третьего боя. Используются все три события,
## которые сейчас реально есть в RunEvents; повторения показывают накопительный эффект.
const EVENT_AFTER := {
	3: "scandal_interview",
	6: "kuluar_whisper",
	9: "old_rival",
	12: "scandal_interview",
	15: "old_rival",
	18: "kuluar_whisper",
}
const POLICIES := ["safe", "greedy", "random"]

var _test_seed := DEFAULT_TEST_SEED


func _ready() -> void:
	await get_tree().process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seed="):
			_test_seed = int(arg.trim_prefix("seed="))
	seed(_test_seed)
	var battles := _simulate_battles()
	_print_battles(battles)
	for policy in POLICIES:
		_replay_policy(battles, policy)
	print("\n=== КОНЕЦ ТЕСТА РЕПУТАЦИИ ===\n")
	get_tree().quit()


## Формула обсуждения, без округления:
## - знак зала согласен с формальным исходом -> весь Z;
## - противоречит исходу -> Z/2.
## Возвращаем полуочки репутации, поэтому весь Z = 2*Z units, половина = Z units.
func _rep_delta2(winner: String, zal: int) -> Dictionary:
	return {
		"delta2": roundi(RunRules.reputation_delta(winner, float(zal)) * 2.0),
		"aligned": RunRules.crowd_agrees(winner, float(zal)),
	}


func _simulate_battles() -> Array:
	var out: Array = []
	for i in MATCHES:
		var model := Rules.new()
		var first := Rules.SIDE_YOU if i % 2 == 0 else Rules.SIDE_OPP
		model.reset(first, U, T, R, HAND, BASE, KOMI, STEALS, FORTIFY,
			CLINCH, FREEZE, CAPTURE, GATE_X, GATE_Y, SECOND_WIND,
			CAPTURE_LOOT, ZAL_KO, ZAL_HOLD)
		var ai := Ai.new()
		var result: Dictionary = ai.simulate(model, "smart", "smart")
		var winner := "you" if String(result.winner) == Rules.SIDE_YOU else \
			("opp" if String(result.winner) == Rules.SIDE_OPP else "draw")
		var zal := int(model.zal())
		var settlement := _rep_delta2(winner, zal)
		out.append({
			"n": i + 1,
			"winner": winner,
			"reason": String(result.reason),
			"zal": zal,
			"turns": int(result.turns),
			"delta2": int(settlement.delta2),
			"aligned": bool(settlement.aligned),
		})
	return out


func _print_battles(battles: Array) -> void:
	print("\n=== РЕПУТАЦИЯ · %d БОЁВ + ТЕКУЩИЕ СОБЫТИЯ ===" % MATCHES)
	print("сид=%d · smart vs smart · канон U3 T8 R9 · зал без изменений · репутация -50…+50, старт 0" % _test_seed)
	print("\n--- Общая выборка боёв (одна для всех политик событий) ---")
	print(" # | исход | причина   | зал | соглас. | Δреп | ходов")
	var contradictions := 0
	var beyond_ten := 0
	var delta_sum2 := 0
	var abs_z_sum := 0
	for b in battles:
		if not bool(b.aligned):
			contradictions += 1
		if absi(int(b.zal)) > 10:
			beyond_ten += 1
		delta_sum2 += int(b.delta2)
		abs_z_sum += absi(int(b.zal))
		print("%2d | %-5s | %-9s | %+3d | %-7s | %+5s | %d" % [
			int(b.n), String(b.winner), String(b.reason), int(b.zal),
			("да" if bool(b.aligned) else "НЕТ"), _rep_str(int(b.delta2)), int(b.turns)])
	print("  итого боёв: Δреп %s · средний |зал| %.2f · противоречий исход/зал %d/%d · |зал|>10: %d" % [
		_rep_str(delta_sum2), float(abs_z_sum) / float(battles.size()),
		contradictions, battles.size(), beyond_ten])


func _replay_policy(battles: Array, policy: String) -> void:
	var rep2 := START_REP2
	var fees := 0
	var event_delta2 := 0
	var min_rep2 := rep2
	var max_rep2 := rep2
	var burned_high2 := 0
	var burned_low2 := 0
	var high_hits := 0
	var low_hits := 0
	var losses := 0
	var losses_first_ten := 0
	var third_loss := {}
	var fourth_loss := {}
	var actions: Array = []
	var cap_moments: Array = []
	var random_rng := RandomNumberGenerator.new()
	random_rng.seed = _test_seed + 1000 + POLICIES.find(policy) * 997

	for b in battles:
		var before_battle := rep2
		var battle_apply := _apply_rep(rep2, int(b.delta2))
		rep2 = int(battle_apply.value)
		burned_high2 += int(battle_apply.burned_high)
		burned_low2 += int(battle_apply.burned_low)
		if rep2 == REP_MAX2 and before_battle != REP_MAX2:
			high_hits += 1
		if rep2 == REP_MIN2 and before_battle != REP_MIN2:
			low_hits += 1
		if int(battle_apply.burned_high) > 0 or int(battle_apply.burned_low) > 0:
			cap_moments.append("после боя %02d: репутация %s, сгорело %s" % [
				int(b.n), _rep_str(rep2),
				_rep_str(int(battle_apply.burned_high) + int(battle_apply.burned_low))])
		if String(b.winner) == "you":
			fees += BATTLE_FEE
		elif String(b.winner) == "opp":
			losses += 1
			if int(b.n) <= 10:
				losses_first_ten += 1
			if losses == 3:
				third_loss = {"match": int(b.n), "rep2": rep2, "fees": fees, "zal": int(b.zal)}
			elif losses == 4:
				fourth_loss = {"match": int(b.n), "rep2": rep2, "fees": fees, "zal": int(b.zal)}
		min_rep2 = mini(min_rep2, rep2)
		max_rep2 = maxi(max_rep2, rep2)

		var n := int(b.n)
		if EVENT_AFTER.has(n):
			var event_id := String(EVENT_AFTER[n])
			var ev: Dictionary = RunEvents.get_event(event_id)
			var choice_i := _pick_choice(ev, fees, policy, random_rng)
			var choice: Dictionary = (ev.get("choices", []) as Array)[choice_i]
			var cost: Dictionary = choice.get("cost", {})
			var fx: Dictionary = choice.get("effects", {})
			var rep_fx2 := 2 * int(fx.get("rep", 0)) - roundi(float(cost.get("rep", 0.0)) * 2.0)
			var before_event := rep2
			var event_apply := _apply_rep(rep2, rep_fx2)
			rep2 = int(event_apply.value)
			burned_high2 += int(event_apply.burned_high)
			burned_low2 += int(event_apply.burned_low)
			if rep2 == REP_MAX2 and before_event != REP_MAX2:
				high_hits += 1
			if rep2 == REP_MIN2 and before_event != REP_MIN2:
				low_hits += 1
			event_delta2 += rep_fx2
			fees -= int(cost.get("fee", 0))
			fees += int(fx.get("fee", 0))
			min_rep2 = mini(min_rep2, rep2)
			max_rep2 = maxi(max_rep2, rep2)
			actions.append("после %02d: %s -> «%s» (%s реп, %+d гонорар)" % [
				n, String(ev.get("title", event_id)), String(choice.label),
				_rep_str(rep_fx2), int(fx.get("fee", 0)) - int(cost.get("fee", 0))])

	print("\n--- Политика событий: %s ---" % _policy_label(policy))
	for a in actions:
		print("  " + String(a))
	for moment in cap_moments:
		print("  КАП: " + String(moment))
	print("  итог после %d боёв: репутация %s · номинальный вклад событий %s · гонорары %d" % [
		MATCHES, _rep_str(rep2), _rep_str(event_delta2), fees])
	print("  диапазон траектории: %s…%s · входов в +50: %d · входов в -50: %d" % [
		_rep_str(min_rep2), _rep_str(max_rep2), high_hits, low_hits])
	print("  забыто за верхним капом: %s · забыто за нижним капом: %s" % [
		_rep_str(burned_high2), _rep_str(burned_low2)])
	print("  формальных поражений: %d (за первые 10 боёв: %d)" % [losses, losses_first_ten])
	if not third_loss.is_empty():
		print("  3-е поражение: бой %d · зал %+d · репутация %s · гонорары %d" % [
			int(third_loss.match), int(third_loss.zal), _rep_str(int(third_loss.rep2)), int(third_loss.fees)])
	if not fourth_loss.is_empty():
		print("  4-е поражение: бой %d · зал %+d · репутация %s · гонорары %d" % [
			int(fourth_loss.match), int(fourth_loss.zal), _rep_str(int(fourth_loss.rep2)), int(fourth_loss.fees)])
	print("  минимум очисток одной точки для 20 боёв: %d (если вылет на 3-й) / %d (если вылет на 4-й)" % [
		maxi(0, losses - 2), maxi(0, losses - 3)])
	print("  минимум очисток для первых 10 боёв: %d / %d" % [
		maxi(0, losses_first_ten - 2), maxi(0, losses_first_ten - 3)])


func _apply_rep(current2: int, delta2: int) -> Dictionary:
	var raw := current2 + delta2
	return {
		"value": clampi(raw, REP_MIN2, REP_MAX2),
		"burned_high": maxi(0, raw - REP_MAX2),
		"burned_low": maxi(0, REP_MIN2 - raw),
	}


func _pick_choice(ev: Dictionary, fees: int, policy: String, rng: RandomNumberGenerator) -> int:
	var choices: Array = ev.get("choices", [])
	var legal: Array = []
	for i in choices.size():
		var choice: Dictionary = choices[i]
		var cost: Dictionary = choice.get("cost", {})
		if fees < int(cost.get("fee", 0)):
			continue
		legal.append(i)
	if legal.is_empty():
		return 0
	if policy == "random":
		return int(legal[rng.randi_range(0, legal.size() - 1)])
	var best_i := int(legal[0])
	var best_primary := -999999
	var best_secondary := -999999
	for i in legal:
		var choice: Dictionary = choices[int(i)]
		var cost: Dictionary = choice.get("cost", {})
		var fx: Dictionary = choice.get("effects", {})
		var rep_v := int(fx.get("rep", 0)) - int(cost.get("rep", 0))
		var fee_v := int(fx.get("fee", 0)) - int(cost.get("fee", 0))
		var primary := rep_v if policy == "safe" else fee_v
		var secondary := fee_v if policy == "safe" else rep_v
		if primary > best_primary or (primary == best_primary and secondary > best_secondary):
			best_primary = primary
			best_secondary = secondary
			best_i = int(i)
	return best_i


func _rep_str(units2: int) -> String:
	var sign_prefix := "-" if units2 < 0 else ""
	var a := absi(units2)
	return "%s%d.%d" % [sign_prefix, a / 2, 5 if a % 2 == 1 else 0]


func _policy_label(policy: String) -> String:
	match policy:
		"safe": return "осторожная (сначала репутация)"
		"greedy": return "жадная (сначала гонорар)"
		_: return "случайная среди доступных вариантов"
