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
const EmotionCore := preload("res://duelogue/core/emotion/emotion_core.gd")
const DefaultReactions := preload("res://duelogue/core/emotion/reaction_decks/volatile_default.gd")
const ProductionOutcomeProfiles := preload("res://duelogue/core/outcome/outcome_profiles.gd")

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

# Цепочка «доска → напряжение → реакция → зал». Все варианты сохраняют 3Р+1Т,
# независимый зал ±5 и один публичный расчёт после полного завершения клинча.
const EMOTION_CONFIGS := [
	{"id": "emotion_clean", "label": "только клинч", "cap": 5, "wf": 3, "wt": 1,
		"wz": 1, "emotion_mode": "none", "hall_per_clinch": 1, "scene_cap": 2},
	{"id": "emotion_punish", "label": "каждый срыв = штраф", "cap": 5, "wf": 3, "wt": 1,
		"wz": 1, "emotion_mode": "punish", "hall_per_clinch": 1, "scene_cap": 2},
	{"id": "emotion_cards", "label": "эффект напечатан на карте", "cap": 5, "wf": 3, "wt": 1,
		"wz": 1, "emotion_mode": "cards", "hall_per_clinch": 1, "scene_cap": 2},
	{"id": "emotion_only", "label": "только реакции", "cap": 5, "wf": 3, "wt": 1,
		"wz": 1, "emotion_mode": "cards", "hall_per_clinch": 0, "scene_cap": 2},
	{"id": "emotion_punish_vote", "label": "штраф, один голос/сцена", "cap": 5,
		"wf": 3, "wt": 1, "wz": 1, "emotion_mode": "punish", "hall_per_clinch": 1,
		"scene_cap": 1},
	{"id": "emotion_cards_vote", "label": "карты, один голос/сцена", "cap": 5,
		"wf": 3, "wt": 1, "wz": 1, "emotion_mode": "cards", "hall_per_clinch": 1,
		"scene_cap": 1},
	{"id": "emotion_observe", "label": "реакции видны, эффект 0", "cap": 5,
		"wf": 3, "wt": 1, "wz": 1, "emotion_mode": "observe", "hall_per_clinch": 1,
		"scene_cap": 2},
]

# Векторный исход: доска определяет логический результат, зал хранит отдельные Lean/Heat.
# Во всех вариантах эмоциональный контракт одинаков; меняется только память аудитории.
const CROWD_CONFIGS := [
	{"id": "crowd_reaction_priority_control", "label": "control: emotion reframes spectacle", "cap": 5, "wf": 3, "wt": 1,
		"wz": 1, "emotion_mode": "cards", "hall_per_clinch": 1, "scene_cap": 2,
		"pressure_mode": "outcome_weighted", "crowd_mode": "pendulum", "verdict_mode": "board",
		"crowd_valence_mode": "reaction_priority", "lean_friction": 0, "heat_amplifies": true,
		"gate_x": 0, "gate_y": 0},
	{"id": "crowd_spectacle", "label": "spectacle valence only", "cap": 5, "wf": 3, "wt": 1,
		"wz": 1, "emotion_mode": "cards", "hall_per_clinch": 1, "scene_cap": 2,
		"pressure_mode": "outcome_weighted", "crowd_mode": "pendulum", "verdict_mode": "board",
		"crowd_valence_mode": "spectacle_only", "lean_friction": 0, "heat_amplifies": true,
		"gate_x": 0, "gate_y": 0},
	{"id": "crowd_spectacle_fade", "label": "spectacle valence + fade", "cap": 5, "wf": 3, "wt": 1,
		"wz": 1, "emotion_mode": "cards", "hall_per_clinch": 1, "scene_cap": 2,
		"pressure_mode": "outcome_weighted", "crowd_mode": "pendulum", "verdict_mode": "board",
		"crowd_valence_mode": "spectacle_only", "lean_friction": 1, "heat_amplifies": true,
		"gate_x": 0, "gate_y": 0},
	{"id": "crowd_ledger", "label": "копилка Lean", "cap": 5, "wf": 3, "wt": 1,
		"wz": 1, "emotion_mode": "cards", "hall_per_clinch": 1, "scene_cap": 2,
		"pressure_mode": "outcome_weighted", "crowd_mode": "ledger", "verdict_mode": "board",
		"gate_x": 0, "gate_y": 0},
	{"id": "crowd_flat", "label": "маятник без Heat-усиления", "cap": 5, "wf": 3, "wt": 1,
		"wz": 1, "emotion_mode": "cards", "hall_per_clinch": 1, "scene_cap": 2,
		"pressure_mode": "outcome_weighted", "crowd_mode": "pendulum", "verdict_mode": "board",
		"lean_friction": 1, "heat_amplifies": false, "gate_x": 0, "gate_y": 0},
	{"id": "crowd_pendulum", "label": "маятник Lean×Heat", "cap": 5, "wf": 3, "wt": 1,
		"wz": 1, "emotion_mode": "cards", "hall_per_clinch": 1, "scene_cap": 2,
		"pressure_mode": "outcome_weighted", "crowd_mode": "pendulum", "verdict_mode": "board",
		"lean_friction": 1, "heat_amplifies": true, "gate_x": 0, "gate_y": 0},
	{"id": "crowd_sticky", "label": "маятник без трения", "cap": 5, "wf": 3, "wt": 1,
		"wz": 1, "emotion_mode": "cards", "hall_per_clinch": 1, "scene_cap": 2,
		"pressure_mode": "outcome_weighted", "crowd_mode": "pendulum", "verdict_mode": "board",
		"lean_friction": 0, "heat_amplifies": true, "gate_x": 0, "gate_y": 0},
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
	var emotion_mode := "none"
	var hall_per_clinch := 1
	var scene_cap := 2
	var pressure_mode := "each_pair"
	var crowd_mode := "ledger"
	var crowd_valence_mode := "every_scene"
	var verdict_mode := "additive"
	var heat := 0
	var heat_max := 3
	var lean_friction := 1
	var heat_amplifies := true
	var reaction_values := {}
	var parry_value := 1
	var decision_threshold := 1
	var conduct_cap := 2
	var surge_threshold := 3
	var surge_alignment_min := 2
	var surge_amplitude := 2
	var surge_reset := 1
	var quiet_actions_required := 0
	var quiet_cool := 0
	var emotion: RefCounted
	var clean_hall := 0               ## контрфакт на той же доске: только голоса клинчей
	var clean_heat := 0
	var final_clean_hall := 0
	var final_clean_margin := 0
	var final_heat := 0
	var final_mandate := 0
	var fallback_margin := 0
	var _pending_emotion_delta := 0   ## копится внутри сцены, применяется один раз после неё
	var _pending_spectacle := 0
	var _pressure_rounds := 0
	var _last_crowd_sign := 0
	var _quiet_actions_seen := 0
	var _clean_quiet_actions_seen := 0
	var scenes := 0
	var emotion_scenes := 0
	var scene_cap_hits := 0
	var reactions := 0
	var parries := 0
	var linked_reactions := 0
	var reaction_rewards := 0
	var reaction_penalties := 0
	var reaction_neutral := 0
	var base_hall_raw := 0
	var emotion_hall_raw := 0
	var emotion_hall_abs := 0
	var emotion_aligns_winner := 0
	var crowd_reversals := 0
	var crowd_moves := 0

	func configure_emotion(mode: String, seed_value: int, p_hall_per_clinch: int = 1,
			p_scene_cap: int = 2, p_pressure_mode: String = "each_pair") -> void:
		emotion_mode = mode
		hall_per_clinch = p_hall_per_clinch
		scene_cap = maxi(1, p_scene_cap)
		pressure_mode = p_pressure_mode
		clean_hall = hall
		if emotion_mode == "none":
			emotion = null
			return
		emotion = EmotionCore.new()
		emotion.start(DefaultReactions.data(), seed_value, [SIDE_YOU, SIDE_OPP])

	## Диагностический шов agency-actions: перед КАЖДЫМ решением обе RNG-ветки получают
	## seed, вычисленный только из initial seed и ordinal решения. Это не меняет ruleset:
	## обычные симы сюда не заходят. Ветвление альтернатив не сдвигает будущие броски лишь
	## потому, что одна ветка сделала другое число rand-вызовов на прошлом решении.
	func agency_reseed(seed_value: int) -> void:
		seed(seed_value)
		if emotion == null:
			return
		var emotion_rng: Variant = emotion.get("_rng")
		if emotion_rng is RandomNumberGenerator:
			(emotion_rng as RandomNumberGenerator).seed = seed_value ^ 0x45D9F3B

	func configure_crowd(config: Dictionary) -> void:
		crowd_mode = String(config.get("crowd_mode", "ledger"))
		crowd_valence_mode = String(config.get("crowd_valence_mode", "every_scene"))
		verdict_mode = String(config.get("verdict_mode", "additive"))
		heat_max = maxi(1, int(config.get("heat_max", 3)))
		lean_friction = maxi(0, int(config.get("lean_friction", 1)))
		heat_amplifies = bool(config.get("heat_amplifies", true))
		reaction_values = (config.get("reaction_values", {}) as Dictionary).duplicate(true)
		parry_value = int(config.get("parry_value", 1))
		decision_threshold = maxi(1, int(config.get("decision_threshold", 1)))
		conduct_cap = maxi(0, int(config.get("conduct_cap", 2)))
		surge_threshold = clampi(int(config.get("surge_threshold", heat_max)), 0, heat_max)
		surge_alignment_min = maxi(1, int(config.get("surge_alignment_min", 2)))
		surge_amplitude = maxi(1, int(config.get("surge_amplitude", 2)))
		surge_reset = clampi(int(config.get("surge_reset", 1)), 0, heat_max)
		quiet_actions_required = maxi(0, int(config.get("quiet_actions", 0)))
		quiet_cool = maxi(0, int(config.get("quiet_cool", 0)))
		heat = clampi(int(config.get("opening_heat", 0)), 0, heat_max)
		clean_heat = heat

	func emotion_state(side: String) -> Dictionary:
		if emotion == null:
			return {}
		return emotion.state(side)

	func zal() -> int:
		if hall_cap <= 0:
			return 0
		return clampi(hall + zal_bias, -hall_cap, hall_cap)

	func board_weight(side: String) -> int:
		return frame_weight * score(side) + thesis_weight * shine(side)

	func ai_margin(side: String) -> int:
		var opp := other(side)
		var board_for_side := board_weight(side) - board_weight(opp)
		var lean_for_side := zal() if side == SIDE_YOU else -zal()
		match verdict_mode:
			"board":
				return board_for_side
			"mandate":
				return board_for_side + signi(lean_for_side) * heat
			_:
				return board_for_side + hall_weight * lean_for_side

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

	func play_action(side: String, type: String, target: int = -1,
			hand_index: int = -1) -> Dictionary:
		var result: Dictionary = super.play_action(side, type, target, hand_index)
		# Обычная выкладка меняет только доску. Для маятника это тихая сцена: накал и
		# старый крен постепенно затухают, но нового направления публика не получает.
		if crowd_mode == "pendulum" and type != TYPE_RAZBOR and not result.is_empty():
			if crowd_valence_mode == "content_plus_conduct":
				_observe_quiet_action(false)
				_observe_quiet_action(true)
			else:
				_settle_pendulum(0, 0, false)
				_settle_pendulum(0, 0, true)
		return result

	## Новая сцена начинает чистую транзакцию зала. Давление внутри клинча может породить
	## реакции, но их публичный эффект применится только после полного исхода обмена.
	func begin_clinch(attacker: String, defender: String, idx: int, prefer_steal: bool,
			hand_index: int = -1) -> Dictionary:
		_pending_emotion_delta = 0
		_pending_spectacle = 0
		_pressure_rounds = 0
		return super.begin_clinch(attacker, defender, idx, prefer_steal, hand_index)

	func clinch_submit(decision: String, prefer_steal: bool = true,
			hand_index: int = -1, stop_reason: String = "voluntary") -> Dictionary:
		var attacker := String(clinch.get("attacker", ""))
		var defender := String(clinch.get("defender", ""))
		var was_press := decision == "play" and String(clinch.get("phase", "")) == "await_attack"
		var result: Dictionary = super.clinch_submit(decision, prefer_steal, hand_index,
			stop_reason)
		if was_press and String(result.get("event", "")) == "press":
			if emotion != null and (pressure_mode == "each_pair" \
					or pressure_mode == "once" and _pressure_rounds == 0):
				# Полная пара «защита → новый нажим»: обеим сторонам +1 напряжения.
				_observe_emotion(attacker, "clinch_pressure", 1)
				_observe_emotion(defender, "clinch_pressure", 1)
			_pressure_rounds += 1
		return result

	## Один завершённый публичный обмен = базовый голос победителю плюс видимые эффекты
	## реакционных карт. Вся сцена коммитится в зал один раз, с публичным капом ±scene_cap.
	func _finish_clinch(stop_reason: String = "voluntary", stopped_side: String = "",
			forced_winner_side: String = "") -> Dictionary:
		var result: Dictionary = super._finish_clinch(stop_reason, stopped_side,
			forced_winner_side)
		if String(result.get("event", "")) != "resolved" or hall_cap <= 0:
			return result
		var exchange_winner := String(result.attacker) if bool(result.landed) else String(result.defender)
		var loser := String(result.defender) if bool(result.landed) else String(result.attacker)
		var winner_sign := 1 if exchange_winner == SIDE_YOU else -1
		var base_delta := winner_sign * hall_per_clinch
		var info: Dictionary = result.get("info", {})
		var content_scene := bool(info.get("removed", false)) \
				or bool(info.get("captured", false)) or _pressure_rounds > 0
		var base_spectacle := 2 if content_scene else 1
		var public_base_delta := base_delta
		if crowd_mode == "pendulum":
			if crowd_valence_mode == "content_plus_conduct":
				public_base_delta = base_delta if content_scene else 0
			elif crowd_valence_mode in ["spectacle_only", "reaction_priority"] \
					and base_spectacle < 2:
				public_base_delta = 0
		# Production controller treats a voluntary failed press as a strategic stop,
		# not an emotional loss (battle_controller.gd::_resolve_clinch). Keep the
		# measurement adapter on the same contract.
		if emotion != null and (bool(result.landed) or stop_reason != "voluntary"):
			var stimulus := "attack_stalled"
			if bool(result.landed):
				stimulus = "captured" if bool(info.get("captured", false)) else \
					("frame_lost" if bool(info.get("removed", false)) else "argument_lost")
			var intensity := 1 + int(bool(info.get("removed", false))) \
				+ int(bool(info.get("captured", false)))
			if pressure_mode == "outcome_weighted" and _pressure_rounds > 0:
				intensity += 1
			_observe_emotion(loser, stimulus, mini(3, intensity))

		scenes += 1
		base_hall_raw += public_base_delta
		if _pending_emotion_delta != 0:
			emotion_scenes += 1
			if signi(_pending_emotion_delta) == winner_sign:
				emotion_aligns_winner += 1
		var raw_scene_delta := public_base_delta + _pending_emotion_delta
		var scene_delta := raw_scene_delta
		var conduct_vote := _pending_emotion_delta
		if crowd_mode == "pendulum" and crowd_valence_mode == "content_plus_conduct":
			if absi(_pending_emotion_delta) > conduct_cap:
				scene_cap_hits += 1
			conduct_vote = clampi(_pending_emotion_delta, -conduct_cap, conduct_cap)
			scene_delta = public_base_delta + conduct_vote
		else:
			if crowd_mode == "pendulum" and crowd_valence_mode == "reaction_priority" \
					and _pending_emotion_delta != 0:
				raw_scene_delta = _pending_emotion_delta
			if absi(raw_scene_delta) > scene_cap:
				scene_cap_hits += 1
			scene_delta = clampi(raw_scene_delta, -scene_cap, scene_cap)
		if crowd_mode == "pendulum":
			if crowd_valence_mode == "content_plus_conduct":
				_settle_content_plus_conduct(public_base_delta, 0,
					int(content_scene), true)
				var reaction_event := _pending_spectacle > 0
				_settle_content_plus_conduct(public_base_delta, conduct_vote,
					int(content_scene or reaction_event), false)
			else:
				_settle_pendulum(signi(public_base_delta), base_spectacle, true)
				_settle_pendulum(signi(scene_delta), maxi(base_spectacle, _pending_spectacle), false)
		else:
			clean_hall = clampi(clean_hall + base_delta, -hall_cap, hall_cap)
			hall = clampi(hall + scene_delta, -hall_cap, hall_cap)
		_pending_emotion_delta = 0
		_pending_spectacle = 0
		return result

	## Production crowd contract: content and conduct cast separate votes. The current
	## event reads pre-event Heat; only two non-zero, co-directed votes surge by two.
	func _settle_content_plus_conduct(content_vote: int, conduct_vote: int, heat_gain: int,
			use_clean: bool) -> void:
		var old_lean := clean_hall if use_clean else hall
		var current_heat := clean_heat if use_clean else heat
		var scene_score := content_vote + conduct_vote
		var votes_aligned := content_vote != 0 and conduct_vote != 0 \
			and signi(content_vote) == signi(conduct_vote)
		var surged := current_heat >= surge_threshold \
			and votes_aligned and absi(scene_score) >= surge_alignment_min
		var amplitude := surge_amplitude if surged else 1
		var relaxed := _toward_zero(old_lean, lean_friction)
		var next_lean := clampi(relaxed + signi(scene_score) * amplitude,
			-hall_cap, hall_cap)
		var next_heat := surge_reset if surged else \
			clampi(current_heat + maxi(0, heat_gain), 0, heat_max)
		if use_clean:
			clean_hall = next_lean
			clean_heat = next_heat
			_clean_quiet_actions_seen = 0
			return
		if next_lean != old_lean:
			crowd_moves += 1
		var next_sign := signi(next_lean)
		if next_sign != 0 and _last_crowd_sign != 0 and next_sign != _last_crowd_sign:
			crowd_reversals += 1
		if next_sign != 0:
			_last_crowd_sign = next_sign
		hall = next_lean
		heat = next_heat
		_quiet_actions_seen = 0

	func _observe_quiet_action(use_clean: bool) -> void:
		if quiet_actions_required <= 0 or quiet_cool <= 0:
			return
		var seen := _clean_quiet_actions_seen if use_clean else _quiet_actions_seen
		seen += 1
		if seen < quiet_actions_required:
			if use_clean:
				_clean_quiet_actions_seen = seen
			else:
				_quiet_actions_seen = seen
			return
		if use_clean:
			clean_heat = maxi(0, clean_heat - quiet_cool)
			_clean_quiet_actions_seen = 0
		else:
			heat = maxi(0, heat - quiet_cool)
			_quiet_actions_seen = 0

	func _settle_pendulum(direction: int, spectacle: int, use_clean: bool) -> void:
		var old_lean := clean_hall if use_clean else hall
		var current_heat := clean_heat if use_clean else heat
		current_heat = clampi(current_heat + spectacle - 1, 0, heat_max)
		var relaxed := _toward_zero(old_lean, lean_friction)
		var impulse := direction * (1 + current_heat if heat_amplifies else 1)
		var next_lean := clampi(relaxed + impulse, -hall_cap, hall_cap)
		if use_clean:
			clean_hall = next_lean
			clean_heat = current_heat
			return
		if next_lean != old_lean:
			crowd_moves += 1
		var next_sign := signi(next_lean)
		if next_sign != 0 and _last_crowd_sign != 0 and next_sign != _last_crowd_sign:
			crowd_reversals += 1
		if next_sign != 0:
			_last_crowd_sign = next_sign
		hall = next_lean
		heat = current_heat

	func _toward_zero(value: int, step: int) -> int:
		if value > 0:
			return maxi(0, value - step)
		if value < 0:
			return mini(0, value + step)
		return 0

	func _observe_emotion(side: String, stimulus: String, intensity: int) -> void:
		if emotion == null or side == "":
			return
		var result: Dictionary = emotion.observe(side, stimulus, intensity, {})
		_consume_reaction(result, 0)

	func _consume_reaction(result: Dictionary, depth: int) -> void:
		var reaction: Dictionary = result.get("reaction", {})
		if reaction.is_empty():
			return
		var reactor := String(result.get("side", ""))
		_pending_spectacle = maxi(_pending_spectacle,
			_reaction_spectacle(String(reaction.get("id", ""))))
		reactions += 1
		if depth > 0:
			linked_reactions += 1
		var stimulus := String(result.get("stimulus", reaction.get("stimulus", "")))
		var relative_effect := _reaction_effect(String(reaction.get("id", "")), stimulus)
		if relative_effect > 0:
			reaction_rewards += 1
		elif relative_effect < 0:
			reaction_penalties += 1
		else:
			reaction_neutral += 1
		_add_emotion_hall(_signed_for_side(reactor, relative_effect))
		if depth >= 2:
			return
		var responder := other(reactor)
		var answer: Dictionary = emotion.answer_reaction(responder, {})
		match String(answer.get("kind", "none")):
			"parry":
				parries += 1
				_pending_spectacle = maxi(_pending_spectacle, 1)
				_add_emotion_hall(_signed_for_side(responder, _parry_effect()))
			"trigger":
				_consume_reaction(answer, depth + 1)

	func _reaction_effect(reaction_id: String, stimulus: String = "") -> int:
		if emotion_mode == "punish":
			return -1
		if emotion_mode != "cards":
			return 0
		if reaction_values.has(reaction_id) or reaction_values.has("default"):
			var configured: Variant = reaction_values.get(reaction_id,
				reaction_values.get("default", 0))
			if configured is Dictionary:
				var values := configured as Dictionary
				if stimulus != "" and values.has(stimulus):
					return int(values[stimulus])
				var stimulus_values: Variant = values.get("stimulus", {})
				if stimulus_values is Dictionary and stimulus != "" \
						and (stimulus_values as Dictionary).has(stimulus):
					return int((stimulus_values as Dictionary)[stimulus])
				return int(values.get("default", 0))
			return int(configured)
		match reaction_id:
			"audience_check", "snap":
				return 1
			"personal_jab", "crack":
				return -1
			_:
				return 0

	func _reaction_spectacle(reaction_id: String) -> int:
		match reaction_id:
			"audience_check", "snap", "personal_jab", "crack":
				return 2
			_:
				return 1

	func _parry_effect() -> int:
		return 0 if emotion_mode == "observe" else parry_value

	func _signed_for_side(side: String, relative_effect: int) -> int:
		return relative_effect if side == SIDE_YOU else -relative_effect

	func _add_emotion_hall(delta: int) -> void:
		_pending_emotion_delta += delta
		emotion_hall_raw += delta
		emotion_hall_abs += absi(delta)

	## ЕДИНСТВЕННЫЙ вердикт: знак (вес доски + независимый зал).
	func _end_by_decision() -> void:
		game_over = true
		final_board_diff = board_weight(SIDE_YOU) - board_weight(SIDE_OPP)
		final_hall = zal()
		final_heat = heat
		final_mandate = signi(final_hall) * final_heat
		fallback_margin = final_board_diff + final_mandate
		final_clean_hall = clampi(clean_hall + zal_bias, -hall_cap, hall_cap)
		var clean_mandate := signi(final_clean_hall) * clean_heat
		match verdict_mode:
			"board":
				final_margin = final_board_diff
				final_clean_margin = final_board_diff
			"mandate":
				final_margin = fallback_margin
				final_clean_margin = final_board_diff + clean_mandate
			_:
				final_margin = final_board_diff + hall_weight * final_hall
				final_clean_margin = final_board_diff + hall_weight * final_clean_hall
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


## Измерительный адаптер production-контракта KO / резерва / audience-only wobble.
##
## 1. В стартовой H5 можно гарантировать ровно одну Установку: это публичный резерв,
##    занимающий обычный слот руки. Остальные Установки возвращаются в добор.
## 2. Потеря последней рамки снимает snapshot руки ДО refill. Установка в snapshot даёт
##    redeploy целым следующим ходом; отсутствие Установки немедленно завершает матч KO.
## 3. Толстая рамка шатается только по snapshot начала клинча. Ответный T гасит сам
##    opener-Кражу; любой поздний press целится уже в этот T и не проверяет рамку повторно.
##
## Мехрезолв не дублируется: наследник только считает
## диагностику, чтобы balance-suite проверял тот же RulesCore, что живая битва.
class ReserveKoRules extends FormulaRules:
	var snapshot_ko_enabled := true
	var guaranteed_reserve_enabled := true
	var wobble_enabled := true
	var knockdowns := 0
	var reserve_saves := 0
	var redeploys := 0
	var snapshot_kos := 0
	var early_kos := 0
	var ko_action_sum := 0
	var wobble_windows := 0
	var wobble_reach_2 := 0
	var wobble_reach_3 := 0
	var wobble_reach_4 := 0
	var thick_attempts := 0
	var thick_captures := 0
	var thick_attempts_behind := 0
	var thick_attempts_tied := 0
	var thick_attempts_ahead := 0
	var thick_captures_behind := 0
	var thick_captures_tied := 0
	var thick_captures_ahead := 0
	var four_captures := 0
	var defense_denials := 0
	var telegraphed_captures := 0
	var untelegraphed_captures := 0
	var voluntary_stalls := 0
	var exhausted_stalls := 0
	var capture_at_1 := 0
	var capture_at_2 := 0
	var capture_at_3 := 0
	var capture_at_4 := 0
	var capture_at_5_plus := 0

	var _scene_initial_thickness := 0
	var _scene_reach := 1
	var _scene_board_relation := 0

	func configure_candidate(config: Dictionary) -> void:
		snapshot_ko_enabled = bool(config.get("snapshot_ko", true))
		guaranteed_reserve_enabled = bool(config.get("guaranteed_reserve", true))
		wobble_enabled = bool(config.get("wobble", true))
		board_ko_enabled = snapshot_ko_enabled
		gate_x = int(config.get("gate_x", 2)) if wobble_enabled else 0
		gate_y = int(config.get("gate_y", 4)) if wobble_enabled else 0

	## Opening уже выставил Базу. Из U3 оставляем в H5 ровно одну рамку и четыре
	## не-рамки; выбор тематического имени механически нейтрален для этого полигона.
	func prepare_opening_reserves() -> void:
		if not guaranteed_reserve_enabled:
			return
		for side in [SIDE_YOU, SIDE_OPP]:
			Deck.prepare_opening_reserve(sides[side], hand_size)

	func begin_turn(side: String) -> String:
		if not snapshot_ko_enabled:
			return super.begin_turn(side)
		if game_over:
			return "over"
		var s: Dictionary = sides[side]
		for ln in s.lines:
			if ln.get("braced", false):
				ln.braced = false
		if s.lines.is_empty():
			if recovery_pending(side) and not recovery_indices(side).is_empty():
				s.passed = false
				return "reframe"
			_finish(other(side), "knockout")
			return "ko"
		_try_second_wind(s)
		if legal_types(side).is_empty():
			s.passed = true
			if sides[other(side)].passed:
				_end_by_decision()
				return "end"
			return "pass"
		s.passed = false
		return "ok"

	func play_redeploy(side: String, hand_index: int) -> Dictionary:
		var result: Dictionary = super.play_redeploy(side, hand_index)
		if not result.is_empty():
			redeploys += 1
		return result

	func capture_threshold(side: String) -> int:
		if clinch_active() and String(clinch.get("attacker", "")) == side:
			return int(clinch.get("capture_reach", 1))
		# Between scenes AI reads current public Lean. Inside a clinch it reads the
		# frozen reach above, so later audience reactions are not retroactive.
		return super.capture_threshold(side)

	## Snapshot берётся до снятия первой атаки и до любых реакций текущей сцены.
	func begin_clinch(attacker: String, defender: String, idx: int, prefer_steal: bool,
			hand_index: int = -1) -> Dictionary:
		_scene_initial_thickness = 0
		_scene_board_relation = signi(score(attacker) - score(defender))
		if idx >= 0 and idx < sides[defender].lines.size():
			_scene_initial_thickness = int(sides[defender].lines[idx].theses)
		var result: Dictionary = super.begin_clinch(attacker, defender, idx, prefer_steal,
			hand_index)
		if result.is_empty():
			_clear_scene_snapshot()
		else:
			_scene_reach = int(clinch.get("capture_reach", 1))
		return result

	func _finish_clinch(stop_reason: String = "voluntary", stopped_side: String = "",
			forced_winner_side: String = "") -> Dictionary:
		var initial := _scene_initial_thickness
		var reach := _scene_reach
		var result: Dictionary = super._finish_clinch(stop_reason, stopped_side,
			forced_winner_side)
		if String(result.get("event", "")) == "resolved":
			var info: Dictionary = result.get("info", {})
			if String(info.get("stop_reason", result.get("stop_reason", "voluntary"))) == "exhausted":
				exhausted_stalls += 1
			else:
				voluntary_stalls += 1
			if bool(info.get("last_frame_lost", false)):
				knockdowns += 1
				if bool(info.get("recovery_pending", false)):
					reserve_saves += 1
				elif bool(info.get("knockout", false)):
					snapshot_kos += 1
					ko_action_sum += turn_count
					if turn_count <= 3:
						early_kos += 1
			if reach > 1:
				wobble_windows += 1
				match reach:
					2: wobble_reach_2 += 1
					3: wobble_reach_3 += 1
					4: wobble_reach_4 += 1
			if wobble_enabled and initial > 1 and initial <= reach \
					and (bool(info.get("capture_attempted", false)) \
						or bool(info.get("parried_capture", false))):
				thick_attempts += 1
				match _scene_board_relation:
					-1: thick_attempts_behind += 1
					0: thick_attempts_tied += 1
					1: thick_attempts_ahead += 1
				if bool(info.get("captured", false)):
					thick_captures += 1
					match _scene_board_relation:
						-1: thick_captures_behind += 1
						0: thick_captures_tied += 1
						1: thick_captures_ahead += 1
					if initial >= 4:
						four_captures += 1
				elif bool(info.get("parried_capture", false)) \
						or bool(info.get("capture_blocked", false)):
					defense_denials += 1
			if bool(info.get("captured", false)):
				if bool(info.get("capture_attempted", false)) \
						and int(info.get("protected_thickness", initial)) <= reach:
					telegraphed_captures += 1
				else:
					untelegraphed_captures += 1
				match initial:
					1: capture_at_1 += 1
					2: capture_at_2 += 1
					3: capture_at_3 += 1
					4: capture_at_4 += 1
					_: capture_at_5_plus += 1
		if game_over and end_reason == "knockout":
			_record_terminal_board()
		_clear_scene_snapshot()
		return result

	func _record_terminal_board() -> void:
		final_board_diff = board_weight(SIDE_YOU) - board_weight(SIDE_OPP)
		final_hall = zal()
		final_heat = heat
		final_mandate = signi(final_hall) * final_heat
		fallback_margin = final_board_diff + final_mandate
		final_clean_hall = clampi(clean_hall + zal_bias, -hall_cap, hall_cap)
		var clean_mandate := signi(final_clean_hall) * clean_heat
		match verdict_mode:
			"board":
				final_margin = final_board_diff
				final_clean_margin = final_board_diff
			"mandate":
				final_margin = fallback_margin
				final_clean_margin = final_board_diff + clean_mandate
			_:
				final_margin = final_board_diff + hall_weight * final_hall
				final_clean_margin = final_board_diff + hall_weight * final_clean_hall
		old_decision_winner = _old_winner_on_this_board()

	func _clear_scene_snapshot() -> void:
		_scene_initial_thickness = 0
		_scene_reach = 1
		_scene_board_relation = 0

	func candidate_metrics() -> Dictionary:
		return {
			"knockdowns": knockdowns, "reserve_saves": reserve_saves,
			"redeploys": redeploys, "snapshot_kos": snapshot_kos,
			"early_kos": early_kos, "ko_action_sum": ko_action_sum,
			"wobble_windows": wobble_windows, "wobble_reach_2": wobble_reach_2,
			"wobble_reach_3": wobble_reach_3, "wobble_reach_4": wobble_reach_4,
			"thick_attempts": thick_attempts, "thick_captures": thick_captures,
			"thick_attempts_behind": thick_attempts_behind,
			"thick_attempts_tied": thick_attempts_tied,
			"thick_attempts_ahead": thick_attempts_ahead,
			"thick_captures_behind": thick_captures_behind,
			"thick_captures_tied": thick_captures_tied,
			"thick_captures_ahead": thick_captures_ahead,
			"four_captures": four_captures, "defense_denials": defense_denials,
			"telegraphed_captures": telegraphed_captures,
			"untelegraphed_captures": untelegraphed_captures,
			"voluntary_stalls": voluntary_stalls, "exhausted_stalls": exhausted_stalls,
			"capture_at_1": capture_at_1, "capture_at_2": capture_at_2,
			"capture_at_3": capture_at_3, "capture_at_4": capture_at_4,
			"capture_at_5_plus": capture_at_5_plus,
		}


## Сим-бот, осведомлённый о новой целевой функции 3Р+1Т+1З. Это НЕ production-ai:
## нужен, чтобы старая эвристика «ширина сначала» не подменяла тест нового вердикта.
class VerdictAi extends "res://duelogue/core/ai/ai.gd":
	const STYLE_VERDICT := "verdict"
	const STYLE_VERDICT_5 := "verdict5"
	const STYLE_VERDICT_9 := "verdict9"
	const STYLE_VERDICT_CALM := "verdict_calm"
	const STYLE_VERDICT_PROVOKE := "verdict_provoke"
	const STYLE_VERDICT_RESERVE := "verdict_reserve"
	## Нижний якорь лестницы навыка: выбирает легальный ход «монеткой». Псевдослучайность
	## берётся из хеша состояния, а не из глобального RNG, поэтому политика остаётся
	## детерминированной и парные контрфактуалы по колоде остаются сопоставимыми.
	const STYLE_COINFLIP := "coinflip"
	const W_FRAME := 3

	## Теневой замер ширины пространства решений: сколько точек, где основная политика
	## вообще расходится с эталонной. Тень только читает состояние и ничего не меняет.
	var shadow_style := ""
	var shadow_side := ""
	var shadow_total := 0
	var shadow_same_type := 0
	var shadow_same_full := 0
	var _in_shadow := false

	func reset_shadow(side: String, style: String) -> void:
		shadow_side = side
		shadow_style = style
		shadow_total = 0
		shadow_same_type = 0
		shadow_same_full = 0

	func pick(r: RefCounted, side: String, style: String) -> Dictionary:
		var act := _pick_dispatch(r, side, style)
		if not _in_shadow and shadow_style != "" and side == shadow_side \
				and not act.is_empty():
			_in_shadow = true
			var shadow := _pick_dispatch(r, side, shadow_style)
			_in_shadow = false
			if not shadow.is_empty():
				shadow_total += 1
				if String(shadow.type) == String(act.type):
					shadow_same_type += 1
					if int(shadow.get("target", -1)) == int(act.get("target", -1)):
						shadow_same_full += 1
		return act

	func _pick_dispatch(r: RefCounted, side: String, style: String) -> Dictionary:
		if style == STYLE_COINFLIP:
			return _pick_coinflip(r, side)
		if not _is_verdict_style(style):
			return super.pick(r, side, style)
		return _apply_named(r, side, _pick_verdict(r, side, style))

	func _pick_coinflip(r: RefCounted, side: String) -> Dictionary:
		var legal: Array = r.legal_types(side)
		if legal.is_empty():
			return {}
		var salt := int(r.turn_count) * 2654435761 + (0 if side == SIDE_YOU else 40503)
		salt += int(r.sides[side].hand.size()) * 97 + int(r.score(side)) * 7
		var noise := _state_hash(salt)
		var act := {"type": legal[noise % legal.size()]}
		if String(act.type) == TYPE_RAZBOR:
			var lines: Array = r.sides[r.other(side)].lines
			if lines.is_empty():
				return {}
			act["target"] = _state_hash(salt + 17) % lines.size()
		return act

	func _state_hash(value: int) -> int:
		var x := value & 0x7FFFFFFF
		x = ((x >> 16) ^ x) * 0x45D9F3B
		x = ((x >> 16) ^ x) * 0x45D9F3B
		return ((x >> 16) ^ x) & 0x7FFFFFFF

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

		# Контрольный эксплойт: если оппонент уже близок к срыву, провокатор предпочитает
		# открыть клинч. Если это стабильно сильнее обычной verdict-политики, эмоция стала
		# скрытой второй атакой, а не рискованным социальным слоем.
		if style == STYLE_VERDICT_PROVOKE and legal.has(TYPE_RAZBOR) \
				and _v_strain(r, opp) >= 4:
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
		var holds_last_reserve := style == STYLE_VERDICT_RESERVE \
			and _v_hand_count(r, side, TYPE_USTANOVKA) <= 1 and not mine.is_empty()
		if legal.has(TYPE_USTANOVKA) and not holds_last_reserve:
			return {"type": TYPE_USTANOVKA}
		if legal.has(TYPE_TEZIS):
			return {"type": TYPE_TEZIS}
		if legal.has(TYPE_RAZBOR) and target >= 0:
			return {"type": TYPE_RAZBOR, "target": target}
		# Если кроме последнего резерва ничего не осталось, вечный пас хуже осознанного риска.
		if legal.has(TYPE_USTANOVKA):
			return {"type": TYPE_USTANOVKA}
		return {"type": legal[0]}

	func def_will_clinch(r: RefCounted, defender: String, line: Dictionary) -> bool:
		if not _is_verdict_style(String(style_of.get(defender, ""))):
			return super.def_will_clinch(r, defender, line)
		var tez := _v_clinch_count(r, defender, "await_defend")
		if tez == 0:
			return false
		var frame_target := _clinch_targets_frame(r)
		# Захват переводит вес дважды — но угрозой является конкретная opener-Кража,
		# а не любая R-карта на рамке той же толщины.
		if frame_target and bool(r.clinch.get("opening_capture_eligible", false)):
			return true
		# Последняя позиция не является KO, но без неё оставшиеся Тезисы становятся мёртвыми.
		if frame_target and r.sides[defender].lines.size() == 1 and int(line.theses) <= 1:
			return true
		# Дешёвую рамку не перекармливаем последним Тезисом; дорогую/закрытую сохраняем.
		var line_value := W_FRAME + int(line.theses)
		return tez >= 2 or line_value >= 6 or bool(line.get("closed", false)) and tez >= 1

	func atk_will_clinch(r: RefCounted, attacker: String, line: Dictionary) -> bool:
		if not _is_verdict_style(String(style_of.get(attacker, ""))):
			return super.atk_will_clinch(r, attacker, line)
		var atk := _v_clinch_count(r, attacker, "await_attack")
		if atk == 0:
			return false
		if String(style_of.get(attacker, "")) == STYLE_VERDICT_PROVOKE \
				and _v_strain(r, r.other(attacker)) >= 4:
			return true
		# В минусе принимаем риск; в плюсе нужен резерв, чтобы не отдать зал пустым ралли.
		if _v_margin(r, attacker) < 0:
			return true
		return atk >= 2

	func atk_prefer_steal(r: RefCounted, attacker: String, defender: String, idx: int) -> bool:
		if not _is_verdict_style(String(style_of.get(attacker, ""))):
			return super.atk_prefer_steal(r, attacker, defender, idx)
		if r.clinch_active() and String(r.clinch.get("phase", "")) == "await_attack":
			return false
		var lines: Array = r.sides[defender].lines
		if idx < 0 or idx >= lines.size():
			return false
		return int(lines[idx].theses) <= int(r.capture_threshold(attacker))

	func _v_margin(r: RefCounted, side: String) -> int:
		if r.has_method("ai_margin"):
			return int(r.ai_margin(side))
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

	func _v_clinch_count(r: RefCounted, side: String, phase: String) -> int:
		if r.has_method("clinch_legal_count"):
			return int(r.clinch_legal_count(side, phase))
		return _v_hand_count(r, side, TYPE_TEZIS if phase == "await_defend" else TYPE_RAZBOR)

	func _v_has_steal(r: RefCounted, side: String) -> bool:
		for card in r.sides[side].hand:
			if String(card.type) == TYPE_RAZBOR and bool(card.get("steals", false)):
				return true
		return false

	func _v_strain(r: RefCounted, side: String) -> int:
		if not r.has_method("emotion_state"):
			return 0
		return int(r.emotion_state(side).get("strain", 0))

	func _is_verdict_style(style: String) -> bool:
		return style == STYLE_VERDICT or style == STYLE_VERDICT_5 or style == STYLE_VERDICT_9 \
			or style == STYLE_VERDICT_CALM or style == STYLE_VERDICT_PROVOKE \
			or style == STYLE_VERDICT_RESERVE

	func _deficit_attack(style: String, margin: int) -> bool:
		match style:
			STYLE_VERDICT:
				return margin < 0
			STYLE_VERDICT_5:
				return margin <= -5
			STYLE_VERDICT_9:
				return margin <= -9
			STYLE_VERDICT_PROVOKE:
				return margin < 0
			STYLE_VERDICT_RESERVE:
				return margin < 0
			_:
				return false


func _ready() -> void:
	_ai = VerdictAi.new()
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	if OS.get_cmdline_user_args().has("--agency-actions"):
		print("\n=== АГЕНТНОСТЬ ДЕЙСТВИЙ · EXACT LEGAL COUNTERFACTUALS ===")
		_agency_actions_suite()
		print("\nПроверки инвариантов: %s" % ("OK" if _failures == 0 else "ОШИБОК: %d" % _failures))
		print("=== КОНЕЦ (%.1f c) ===\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
		get_tree().quit(0 if _failures == 0 else 1)
		return
	if OS.get_cmdline_user_args().has("--draw-luck"):
		print("\n=== УДАЧА ВЫБОРКИ КОЛОДЫ · ФАКТОРНЫЙ И КОНТРФАКТУАЛЬНЫЙ АУДИТ ===")
		_draw_luck_suite()
		print("\nПроверки инвариантов: %s" % ("OK" if _failures == 0 else "ОШИБОК: %d" % _failures))
		print("=== КОНЕЦ (%.1f c) ===\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
		get_tree().quit(0 if _failures == 0 else 1)
		return
	if OS.get_cmdline_user_args().has("--skill-ladder"):
		print("\n=== ЛЕСТНИЦА НАВЫКА · СИГНАЛ РЕШЕНИЙ ПРОТИВ ШУМА ВЫБОРКИ ===")
		_skill_ladder_suite()
		print("\nПроверки инвариантов: %s" % ("OK" if _failures == 0 else "ОШИБОК: %d" % _failures))
		print("=== КОНЕЦ (%.1f c) ===\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
		get_tree().quit(0 if _failures == 0 else 1)
		return
	if OS.get_cmdline_user_args().has("--late-game"):
		print("\n=== ФИНАЛЬНАЯ ТРЕТЬ · КАМБЭКИ И ТОЧКА НЕОБРАТИМОСТИ ===")
		_late_game_suite()
		print("\nПроверки инвариантов: %s" % ("OK" if _failures == 0 else "ОШИБОК: %d" % _failures))
		print("=== КОНЕЦ (%.1f c) ===\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
		get_tree().quit(0 if _failures == 0 else 1)
		return
	if OS.get_cmdline_user_args().has("--ko-wobble"):
		print("\n=== SNAPSHOT KO · РЕЗЕРВ РАМКИ · ШАТАНИЕ ===")
		_ko_wobble_suite()
		print("\nПроверки инвариантов: %s" % ("OK" if _failures == 0 else "ОШИБОК: %d" % _failures))
		print("=== КОНЕЦ (%.1f c) ===\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
		get_tree().quit(0 if _failures == 0 else 1)
		return
	if OS.get_cmdline_user_args().has("--emotion-candidate"):
		print("\n=== ЕДИНЫЙ ВЕРДИКТ · КАНДИДАТ ЭМОЦИОНАЛЬНОГО ЗАЛА ===")
		_emotion_candidate_suite()
		print("\nПроверки инвариантов: %s" % ("OK" if _failures == 0 else "ОШИБОК: %d" % _failures))
		print("=== КОНЕЦ (%.1f c) ===\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
		get_tree().quit(0 if _failures == 0 else 1)
		return
	if OS.get_cmdline_user_args().has("--crowd-pendulum"):
		print("\n=== ЕДИНЫЙ ВЕРДИКТ · ДОСКА И ЗАЛ КАК РАЗНЫЕ ИСХОДЫ ===")
		_crowd_pendulum_suite()
		print("\nПроверки инвариантов: %s" % ("OK" if _failures == 0 else "ОШИБОК: %d" % _failures))
		print("=== КОНЕЦ (%.1f c) ===\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
		get_tree().quit(0 if _failures == 0 else 1)
		return
	if OS.get_cmdline_user_args().has("--emotion-pressure"):
		print("\n=== ЕДИНЫЙ ВЕРДИКТ · ЧАСТОТА ЭМОЦИОНАЛЬНОГО ДАВЛЕНИЯ ===")
		_emotion_pressure_suite()
		print("\nПроверки инвариантов: %s" % ("OK" if _failures == 0 else "ОШИБОК: %d" % _failures))
		print("=== КОНЕЦ (%.1f c) ===\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
		get_tree().quit(0 if _failures == 0 else 1)
		return
	if OS.get_cmdline_user_args().has("--emotion-chain"):
		print("\n=== ЕДИНЫЙ ВЕРДИКТ · ДОСКА → ЭМОЦИЯ → ЗАЛ ===")
		_emotion_chain_suite()
		print("\nПроверки инвариантов: %s" % ("OK" if _failures == 0 else "ОШИБОК: %d" % _failures))
		print("=== КОНЕЦ (%.1f c) ===\n" % ((Time.get_ticks_msec() - t0) / 1000.0))
		get_tree().quit(0 if _failures == 0 else 1)
		return
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

func _new_match(config: Dictionary, first: String, deck_you: Dictionary = {},
		deck_opp: Dictionary = {}, emotion_seed: int = 0) -> RefCounted:
	var m: RefCounted
	if String(config.id) == "old":
		m = Rules.new()
		m.reset(first, U, T, R, HAND, BASE, KOMI, STEAL, FORT,
			CLINCH, FREEZE, CAPTURE, GATE_X, GATE_Y, SW, LOOT, OLD_ZAL_KO, OLD_ZAL_HOLD)
	else:
		var fm: RefCounted
		if bool(config.get("snapshot_ko", false)) or bool(config.get("wobble", false)) \
				or bool(config.get("guaranteed_reserve", false)):
			fm = ReserveKoRules.new()
		else:
			fm = FormulaRules.new()
		fm.hall_cap = int(config.cap)
		fm.frame_weight = int(config.wf)
		fm.thesis_weight = int(config.wt)
		fm.hall_weight = int(config.wz)
		var gate_x := int(config.get("gate_x", GATE_X))
		var gate_y := int(config.get("gate_y", GATE_Y))
		fm.reset(first, U, T, R, HAND, BASE, KOMI, STEAL, FORT,
			CLINCH, FREEZE, CAPTURE, gate_x, gate_y, SW, LOOT, 0, 1,
			bool(config.get("snapshot_ko", false)))
		fm.configure_emotion(String(config.get("emotion_mode", "none")), emotion_seed,
			int(config.get("hall_per_clinch", 1)), int(config.get("scene_cap", 2)),
			String(config.get("pressure_mode", "each_pair")))
		fm.configure_crowd(config)
		if fm.has_method("configure_candidate"):
			fm.configure_candidate(config)
		var opening_hall := int(config.get("opening_hall", 0))
		if opening_hall != 0:
			fm.hall = opening_hall if first == Rules.SIDE_YOU else -opening_hall
			fm.clean_hall = fm.hall
		m = fm
	if not deck_you.is_empty():
		m.sides[Rules.SIDE_YOU] = _build_side(deck_you)
		# build_side() кладёт на Базу только scalar theses. Production-controller после
		# override материализует exact thesis objects тем же публичным методом; без этого
		# deck-archetype suites сравнивали разные контракты и «канон vs канон» был смещён.
		m.seed_starting_theses(Rules.SIDE_YOU)
	if not deck_opp.is_empty():
		m.sides[Rules.SIDE_OPP] = _build_side(deck_opp)
		m.seed_starting_theses(Rules.SIDE_OPP)
	if m.has_method("prepare_opening_reserves"):
		m.prepare_opening_reserves()
	return m


func _build_side(comp: Dictionary) -> Dictionary:
	return Deck.build_side(int(comp.u), int(comp.t), int(comp.r), BASE,
		mini(int(comp.get("steals", STEAL)), int(comp.r)), HAND)


func _seed_for(i: int, salt: int) -> void:
	seed(_seed_value(i, salt))


func _seed_value(i: int, salt: int) -> int:
	return BASE_SEED + i * 104729 + salt * 1009


# ------------------------------------------------------------------ метрики ---

func _blank_metrics() -> Dictionary:
	return {
		"wins_you": 0, "wins_opp": 0, "draws": 0, "first_wins": 0, "decisive": 0,
		"turns": 0, "captures": 0, "capture_theses": 0,
		"board_diff_abs": 0, "hall_abs": 0, "margin_abs": 0, "hall_sum": 0,
		"hall_saturated": 0, "old_disagree": 0, "tall_wins": 0, "wide_wins": 0,
		"hall_overturns": 0, "hall_breaks_board_tie": 0, "zero_frame_wins": 0,
		"clean_hall_abs": 0, "emotion_terminal_flips": 0,
		"scenes": 0, "emotion_scenes": 0, "scene_cap_hits": 0,
		"reactions": 0, "parries": 0, "linked_reactions": 0,
		"reaction_rewards": 0, "reaction_penalties": 0, "reaction_neutral": 0,
		"emotion_hall_raw": 0, "emotion_hall_abs": 0, "emotion_aligns_winner": 0,
		"heat_sum": 0, "heat_high": 0, "crowd_reversals": 0, "crowd_moves": 0,
		"logic_aligned": 0, "logic_split": 0, "crowd_neutral": 0, "logic_draw": 0,
		"strict_aligned": 0, "strict_split": 0, "strict_neutral": 0,
		"mandate_reclass": 0,
		"corr_n": 0, "corr_x": 0.0, "corr_y": 0.0,
		"corr_x2": 0.0, "corr_y2": 0.0, "corr_xy": 0.0,
		"board_counts": {}, "crowd_states_by_board": {},
	}


func _run_cell(config: Dictionary, style_you: String, style_opp: String, matches: int,
		deck_you: Dictionary = {}, deck_opp: Dictionary = {}, salt: int = 0) -> Dictionary:
	var out := _blank_metrics()
	for i in matches:
		_seed_for(i, salt)
		var first := Rules.SIDE_YOU if i % 2 == 0 else Rules.SIDE_OPP
		var m := _new_match(config, first, deck_you, deck_opp,
			_seed_value(i, salt) ^ 0x5EEDC0DE)
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
	out.clean_hall_abs += absi(int(m.final_clean_hall))
	out.scenes += int(m.scenes)
	out.emotion_scenes += int(m.emotion_scenes)
	out.scene_cap_hits += int(m.scene_cap_hits)
	out.reactions += int(m.reactions)
	out.parries += int(m.parries)
	out.linked_reactions += int(m.linked_reactions)
	out.reaction_rewards += int(m.reaction_rewards)
	out.reaction_penalties += int(m.reaction_penalties)
	out.reaction_neutral += int(m.reaction_neutral)
	out.emotion_hall_raw += int(m.emotion_hall_raw)
	out.emotion_hall_abs += int(m.emotion_hall_abs)
	out.emotion_aligns_winner += int(m.emotion_aligns_winner)
	out.heat_sum += int(m.final_heat)
	out.heat_high += int(int(m.final_heat) >= 2)
	out.crowd_reversals += int(m.crowd_reversals)
	out.crowd_moves += int(m.crowd_moves)
	var logic_sign := signi(board_diff)
	var crowd_sign := signi(hall) if absi(hall) >= int(m.decision_threshold) else 0
	if logic_sign == 0:
		out.logic_draw += 1
	else:
		var strict_crowd_sign := signi(hall) if absi(hall) >= 2 else 0
		if strict_crowd_sign == 0:
			out.strict_neutral += 1
		elif logic_sign == strict_crowd_sign:
			out.strict_aligned += 1
		else:
			out.strict_split += 1
		if crowd_sign == 0:
			out.crowd_neutral += 1
		elif logic_sign == crowd_sign:
			out.logic_aligned += 1
		else:
			out.logic_split += 1
	if logic_sign != 0 and signi(int(m.fallback_margin)) != logic_sign:
		out.mandate_reclass += 1
	out.corr_n += 1
	out.corr_x += float(board_diff)
	out.corr_y += float(hall)
	out.corr_x2 += float(board_diff * board_diff)
	out.corr_y2 += float(hall * hall)
	out.corr_xy += float(board_diff * hall)
	var board_key := str(board_diff)
	out.board_counts[board_key] = int(out.board_counts.get(board_key, 0)) + 1
	var state_key := "%d/%d" % [hall, int(m.final_heat)]
	var states: Dictionary = out.crowd_states_by_board.get(board_key, {})
	states[state_key] = true
	out.crowd_states_by_board[board_key] = states
	if signi(int(m.final_clean_margin)) != signi(margin):
		out.emotion_terminal_flips += 1
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
	var expected_margin := board_diff + int(m.hall_weight) * hall
	var expected_clean_margin := board_diff + int(m.hall_weight) * int(m.final_clean_hall)
	match String(m.verdict_mode):
		"board":
			expected_margin = board_diff
			expected_clean_margin = board_diff
		"mandate":
			expected_margin = board_diff + signi(hall) * int(m.final_heat)
			expected_clean_margin = board_diff + signi(int(m.final_clean_hall)) * int(m.clean_heat)
	if margin != expected_margin:
		_failures += 1
	if (margin > 0 and win != Rules.SIDE_YOU) or (margin < 0 and win != Rules.SIDE_OPP) \
			or (margin == 0 and win != ""):
		_failures += 1
	if int(m.hall_cap) >= 0 and absi(hall) > int(m.hall_cap):
		_failures += 1
	if int(m.reactions) != int(m.reaction_rewards) + int(m.reaction_penalties) \
			+ int(m.reaction_neutral):
		_failures += 1
	if int(m.final_clean_margin) != expected_clean_margin:
		_failures += 1
	if int(m.final_heat) < 0 or int(m.final_heat) > int(m.heat_max):
		_failures += 1
	if String(m.end_reason) == "knockout" or String(m.end_reason) == "crowd":
		_failures += 1


func _pct(n: int, d: int) -> float:
	return float(n) / float(maxi(1, d)) * 100.0


func _winrate(m: Dictionary) -> float:
	return float(m.wins_you) / float(maxi(1, int(m.decisive)))


func _correlation(m: Dictionary) -> float:
	var n := float(m.corr_n)
	var denominator := sqrt(maxf(0.0,
		(n * float(m.corr_x2) - float(m.corr_x) * float(m.corr_x))
		* (n * float(m.corr_y2) - float(m.corr_y) * float(m.corr_y))))
	if denominator <= 0.000001:
		return 0.0
	return (n * float(m.corr_xy) - float(m.corr_x) * float(m.corr_y)) / denominator


func _modal_board_diversity(m: Dictionary) -> Dictionary:
	var best_key := ""
	var best_count := -1
	for key in m.board_counts:
		var count := int(m.board_counts[key])
		if count > best_count:
			best_count = count
			best_key = String(key)
	var states: Dictionary = m.crowd_states_by_board.get(best_key, {})
	return {"board": best_key, "matches": maxi(0, best_count), "states": states.size()}


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


# ---------------------------------------------- доска → эмоция → независимый зал ---

func _emotion_chain_suite() -> void:
	var n := mirror_matches
	print("Условия: fixed K2, verdict-aware бот, содержание 3Р+1Т, независимый зал ±5,")
	print("один коммит зала после всей сцены; сравниваются пределы ±2 и один голос ±1.")
	print("%d матчей/ячейку." % n)
	print("Карточная индексация: Поиск свидетелей/Вспышка +1 реактору;")
	print("Переход на личности/Трещина −1; прочие реакции 0; холодная парировка +1.\n")

	print("--- A. ЗЕРКАЛО: сколько победы реально несут эмоции ---")
	print("%-28s | 1-й ход ничьи ходы капч | |H| реакц парир | Eсцен Eflip Scap | + / − / 0" % "индексация")
	for ci in EMOTION_CONFIGS.size():
		var config: Dictionary = EMOTION_CONFIGS[ci]
		var m := _run_cell(config, "verdict", "verdict", n, {}, {}, 1200 + ci)
		var reactions_n := int(m.reactions)
		print("%-28s | %7.1f%% %4.1f%% %4.1f %4.2f | %3.1f %5.2f %5.2f | %5.1f%% %5.1f%% %4.1f%% | %2.0f/%2.0f/%2.0f" % [
			String(config.label), _pct(int(m.first_wins), int(m.decisive)),
			_pct(int(m.draws), n), float(m.turns) / n, float(m.captures) / n,
			float(m.hall_abs) / n, float(reactions_n) / n, float(m.parries) / n,
			_pct(int(m.emotion_scenes), int(m.scenes)),
			_pct(int(m.emotion_terminal_flips), n), _pct(int(m.scene_cap_hits), int(m.scenes)),
			_pct(int(m.reaction_rewards), reactions_n), _pct(int(m.reaction_penalties), reactions_n),
			_pct(int(m.reaction_neutral), reactions_n)])
	print("Eсцен — сцены с ненулевым эмоциональным вкладом; Eflip — знак финального V")
	print("отличается от контрфакта на той же доске с одним лишь голосом за клинч;")
	print("Scap — сырой итог сцены пришлось срезать заданным публичным капом ±1/±2.\n")

	print("--- B. СТОРОЖ ПРОВОКАЦИИ: сознательно дожимать нагретого оппонента ---")
	print("%-28s | provoke vs normal | реакции/матч | парировки/матч | эмоц. вклад/матч" % "индексация")
	for ci in EMOTION_CONFIGS.size():
		var config: Dictionary = EMOTION_CONFIGS[ci]
		var a := _run_cell(config, "verdict_provoke", "verdict", n, {}, {}, 1250 + ci)
		var b := _run_cell(config, "verdict", "verdict_provoke", n, {}, {}, 1250 + ci)
		var provoke_wr := (_winrate(a) + (1.0 - _winrate(b))) * 50.0
		print("%-28s | %16.1f%% | %12.2f | %14.2f | %15.2f" % [
			String(config.label), provoke_wr,
			float(int(a.reactions) + int(b.reactions)) / float(2 * n),
			float(int(a.parries) + int(b.parries)) / float(2 * n),
			float(int(a.emotion_hall_abs) + int(b.emotion_hall_abs)) / float(2 * n)])
	print("Абсолютные >55% сами по себе не доказывают вторую атаку: шкала может быть полезным")
	print("информационным сигналом. Чистый механический эффект изолирует --emotion-pressure.\n")

	print("--- C. ОБРАТНАЯ СВЯЗЬ ЗАЛ → ДОСКА: comeback-гейт ---")
	print("%-10s | 1-й ход | ничьи | захваты | |H| | Eflip | Scap" % "гейт")
	for gate in [[0, 0], [2, 4]]:
		var config: Dictionary = EMOTION_CONFIGS[5].duplicate(true)
		config["gate_x"] = int(gate[0])
		config["gate_y"] = int(gate[1])
		var m := _run_cell(config, "verdict", "verdict", n, {}, {}, 1300)
		var label := "выкл" if int(gate[0]) == 0 else "2/4"
		print("%-10s | %7.1f%% | %5.1f%% | %7.2f | %3.1f | %5.1f%% | %4.1f%%" % [
			label, _pct(int(m.first_wins), int(m.decisive)), _pct(int(m.draws), n),
			float(m.captures) / n, float(m.hall_abs) / n,
			_pct(int(m.emotion_terminal_flips), n), _pct(int(m.scene_cap_hits), int(m.scenes))])
	print("Сторож: гейт не должен сам создавать инициативу вне 45–55% или резко поднимать")
	print("частоту эмоциональной переклассификации исхода.\n")

	var decks := [
		{"label": "канон 3/8/9", "u": 3, "t": 8, "r": 9, "steals": 2},
		{"label": "глубина 2/12/6", "u": 2, "t": 12, "r": 6, "steals": 2},
		{"label": "ширина 5/7/8", "u": 5, "t": 7, "r": 8, "steals": 2},
		{"label": "разбор 2/6/12", "u": 2, "t": 6, "r": 12, "steals": 2},
		{"label": "смешанная 4/9/7", "u": 4, "t": 9, "r": 7, "steals": 2},
	]
	print("--- D. АРХЕТИПЫ: карточная индексация, verdict vs verdict ---")
	print("%-22s | винрейт против канона | реакции | Eflip" % "обойма YOU")
	for di in decks.size():
		var comp: Dictionary = decks[di]
		var m := _run_cell(EMOTION_CONFIGS[5], "verdict", "verdict", deck_matches,
			comp, {}, 1350 + di)
		print("%-22s | %20.1f%% | %7.2f | %5.1f%%" % [String(comp.label),
			_winrate(m) * 100.0, float(m.reactions) / deck_matches,
			_pct(int(m.emotion_terminal_flips), deck_matches)])
	print("Сторож: эмоции не должны вытолкнуть конструктивный архетип за 40–60%; если wide")
	print("остаётся ниже, это прежний блокер захвата/инициативы, а не повод крутить эмоции.\n")


func _emotion_pressure_suite() -> void:
	var n := mirror_matches * 3 if OS.get_cmdline_user_args().has("--long") else mirror_matches
	var modes := [
		{"id": "each_pair", "label": "каждая полная пара"},
		{"id": "once", "label": "только первая пара"},
		{"id": "outcome", "label": "только итог клинча"},
		{"id": "outcome_weighted", "label": "затяжной итог +1"},
	]
	print("Условия: карточная индексация, предел сцены ±2, остальное фиксировано;")
	print("%d матчей/ячейку на одинаковых сериях сидов.\n" % n)
	print("%-22s | реакц | Eflip | 1-й ход | provoke cards | provoke effect0 | Δмеханики" % "нагрев")
	for mi in modes.size():
		var mode: Dictionary = modes[mi]
		var config: Dictionary = EMOTION_CONFIGS[2].duplicate(true)
		config["pressure_mode"] = String(mode.id)
		var mirror := _run_cell(config, "verdict", "verdict", n, {}, {}, 1400 + mi)
		var a := _run_cell(config, "verdict_provoke", "verdict", n, {}, {}, 1420 + mi)
		var b := _run_cell(config, "verdict", "verdict_provoke", n, {}, {}, 1420 + mi)
		var provoke_wr := (_winrate(a) + (1.0 - _winrate(b))) * 50.0
		var control: Dictionary = EMOTION_CONFIGS[6].duplicate(true)
		control["pressure_mode"] = String(mode.id)
		var ca := _run_cell(control, "verdict_provoke", "verdict", n, {}, {}, 1420 + mi)
		var cb := _run_cell(control, "verdict", "verdict_provoke", n, {}, {}, 1420 + mi)
		var control_wr := (_winrate(ca) + (1.0 - _winrate(cb))) * 50.0
		print("%-22s | %5.2f | %5.1f%% | %7.1f%% | %13.1f%% | %14.1f%% | %+8.1f пп" % [
			String(mode.label), float(mirror.reactions) / n,
			_pct(int(mirror.emotion_terminal_flips), n),
			_pct(int(mirror.first_wins), int(mirror.decisive)), provoke_wr, control_wr,
			provoke_wr - control_wr])
	print("Сторож темпа: ориентир 4–6 реакций за матч; Eflip должен оставаться заметным, но")
	print("не становиться главной формулой победы. Δмеханики сравнивает карточный эффект с")
	print("теми же публичными шкалами и provoke-политикой, но нулевым эффектом реакций на зал.\n")


func _crowd_config(config_id: String) -> Dictionary:
	if config_id == "crowd_reaction_frame":
		return _production_crowd_config()
	for config in CROWD_CONFIGS:
		if String(config.id) == config_id:
			return config.duplicate(true)
	return CROWD_CONFIGS[0].duplicate(true)


## Адаптер production-профиля к старому плоскому формату сим-полигона. Калибровочные числа
## живут в одном реестре; сим остаётся свободен добавлять контрольные модели рядом.
func _production_crowd_config(profile_id: String = "") -> Dictionary:
	var selected_profile_id := profile_id.strip_edges()
	if selected_profile_id == "":
		selected_profile_id = String(ProductionOutcomeProfiles.DEFAULT_ID)
	var profile: Dictionary = ProductionOutcomeProfiles.get_profile(selected_profile_id)
	var board: Dictionary = profile.get("board", {})
	var audience_config: Dictionary = profile.get("audience", {})
	var links: Dictionary = profile.get("links", {})
	var victory: Dictionary = profile.get("victory", {})
	return {
		"id": "crowd_reaction_frame",
		"profile_id": String(profile.get("id", selected_profile_id)),
		"selected_production": true,
		"label": "prod: %s" % String(profile.get("label", selected_profile_id)),
		"cap": int(audience_config.get("lean_cap", 5)),
		"wf": int(board.get("frame_weight", 3)),
		"wt": int(board.get("thesis_weight", 1)), "wz": 1,
		"emotion_mode": "cards", "hall_per_clinch": 1,
		"scene_cap": int(audience_config.get("conduct_cap", 2)),
		"pressure_mode": "outcome_weighted",
		"crowd_mode": String(audience_config.get("mode", "pendulum")),
		"verdict_mode": String(victory.get("mode", "board")),
		"crowd_valence_mode": String(audience_config.get("valence_mode", "content_plus_conduct")),
		"decision_threshold": int(audience_config.get("decision_threshold", 1)),
		"conduct_cap": int(audience_config.get("conduct_cap", 2)),
		"surge_threshold": int(audience_config.get("surge_threshold",
			audience_config.get("heat_max", 3))),
		"surge_alignment_min": int(audience_config.get("surge_alignment_min", 2)),
		"surge_amplitude": int(audience_config.get("surge_amplitude", 2)),
		"surge_reset": int(audience_config.get("surge_reset", 1)),
		"quiet_actions": int(audience_config.get("quiet_actions", 2)),
		"quiet_cool": int(audience_config.get("quiet_cool", 1)),
		"lean_friction": int(audience_config.get("lean_friction", 0)),
		"heat_max": int(audience_config.get("heat_max", 3)),
		"heat_amplifies": bool(audience_config.get("heat_amplifies", true)),
		"opening_heat": int(audience_config.get("opening_heat", 0)),
		"reaction_values": (audience_config.get("reaction_values", {}) as Dictionary).duplicate(true),
		"parry_value": int(audience_config.get("parry_value", 1)),
		"gate_x": int(links.get("gate_x", 0)), "gate_y": int(links.get("gate_y", 0)),
	}


func _crowd_pendulum_suite() -> void:
	var n := mirror_matches * 3 if OS.get_cmdline_user_args().has("--long") else mirror_matches
	var production_config := _production_crowd_config()
	var production_threshold := maxi(1, int(production_config.get("decision_threshold", 1)))
	print("Контракт: Board B = 3·Δрамки + Δтезисы. Он один определяет победителя дебатов.")
	print("Audience scene = content + conduct (conduct cap ±2); content votes only on removed/captured/extended.")
	print("Lean normally moves 1. Only pre-event Heat=3 plus aligned non-zero content and conduct moves 2, then resets Heat to 1;")
	var neutral_rule := "only Lean=0 is neutral" if production_threshold == 1 else \
		"|Lean|<%d is neutral" % production_threshold
	print("otherwise the public event adds Heat after its move. Two quiet actions cool 1; %s.\n" % neutral_rule)

	print("--- A. НАКОПИТЕЛЬ ПРОТИВ МАЯТНИКА, %d ОДИНАКОВЫХ СИДОВ ---" % n)
	print("%-29s | |Lean| | Heat | H≥2 | развор. | corr(B,L) | вместе | раскол | нейтр. | fallback | B*:сост." % "модель зала")
	var reference: Dictionary = {}
	var selected: Dictionary = {}
	var configs_to_test: Array = [production_config]
	if not OS.get_cmdline_user_args().has("--selected-only"):
		configs_to_test.append_array(CROWD_CONFIGS)
	for ci in configs_to_test.size():
		var raw_config: Dictionary = configs_to_test[ci]
		var config: Dictionary = raw_config.duplicate(true)
		var m := _run_cell(config, "verdict", "verdict", n, {}, {}, 1600)
		var diversity := _modal_board_diversity(m)
		var logic_decisive := n - int(m.logic_draw)
		print("%-29s | %6.2f | %4.2f | %4.1f%% | %7.2f | %+9.3f | %5.1f%% | %5.1f%% | %5.1f%% | %7.1f%% | %s:%d" % [
			String(config.label), float(m.hall_abs) / n, float(m.heat_sum) / n,
			_pct(int(m.heat_high), n), float(m.crowd_reversals) / n, _correlation(m),
			_pct(int(m.logic_aligned), logic_decisive), _pct(int(m.logic_split), logic_decisive),
			_pct(int(m.crowd_neutral), logic_decisive), _pct(int(m.mandate_reclass), logic_decisive),
			String(diversity.board), int(diversity.states)])
		if reference.is_empty():
			reference = m
		elif m.board_counts != reference.board_counts or int(m.turns) != int(reference.turns) \
				or int(m.captures) != int(reference.captures):
			_failures += 1
		if bool(config.get("selected_production", false)):
			selected = m
	print("B*:сост. — число разных финальных Lean/Heat при самом частом одинаковом счёте доски.")
	print("fallback — сколько логических исходов изменил бы диагностический счёт B + sign(Lean)·Heat.")
	print("Инвариант A: при выключенном гейте все модели оставляют доску и длину партий идентичными.\n")

	print("--- B. ОБРАТНАЯ СВЯЗЬ ЗАЛ → ДОСКА ---")
	print("%-10s | 1-й ход | ничьи B | захваты | |Lean| | Heat | раскол | corr(B,L)" % "гейт")
	for gate in [[0, 0], [2, 4]]:
		var config: Dictionary = _crowd_config("crowd_reaction_frame")
		config["gate_x"] = int(gate[0])
		config["gate_y"] = int(gate[1])
		var m := _run_cell(config, "verdict", "verdict", n, {}, {}, 1650)
		var logic_decisive := n - int(m.logic_draw)
		var label := "выкл" if int(gate[0]) == 0 else "2/4"
		print("%-10s | %7.1f%% | %7.1f%% | %7.2f | %6.2f | %4.2f | %5.1f%% | %+9.3f" % [
			label, _pct(int(m.first_wins), int(m.decisive)), _pct(int(m.logic_draw), n),
			float(m.captures) / n, float(m.hall_abs) / n, float(m.heat_sum) / n,
			_pct(int(m.logic_split), logic_decisive), _correlation(m)])
	print("Здесь победителя всё ещё определяет только B; гейт проверяет лишь косвенное влияние зала на доступность захвата.\n")

	print("--- C. ПРОВОКАЦИЯ: ЛОГИЧЕСКИЙ И ПУБЛИЧНЫЙ РЕЗУЛЬТАТ ---")
	print("%-21s | победы в дебатах | Lean к провокатору | Heat | реакции" % "индексация реакций")
	for mode in ["cards", "observe"]:
		var config: Dictionary = _crowd_config("crowd_reaction_frame")
		config["emotion_mode"] = mode
		var a := _run_cell(config, "verdict_provoke", "verdict", n, {}, {}, 1700)
		var b := _run_cell(config, "verdict", "verdict_provoke", n, {}, {}, 1700)
		var provoke_board_wr := (_winrate(a) + (1.0 - _winrate(b))) * 50.0
		var provoke_lean := float(int(a.hall_sum) - int(b.hall_sum)) / float(2 * n)
		var avg_heat := float(int(a.heat_sum) + int(b.heat_sum)) / float(2 * n)
		var avg_reactions := float(int(a.reactions) + int(b.reactions)) / float(2 * n)
		var label := "эффект карт −1/0/+1" if mode == "cards" else "эффект карт = 0"
		print("%-21s | %15.1f%% | %+16.2f | %4.2f | %7.2f" % [
			label, provoke_board_wr, provoke_lean, avg_heat, avg_reactions])
	print("Разность строк изолирует публичную цену/выгоду напечатанных реакций: доска при этом остаётся самостоятельным исходом.\n")

	if not selected.is_empty():
		var resolved := int(selected.logic_aligned) + int(selected.logic_split) + int(selected.crowd_neutral)
		print("Сводка выбранного маятника: %.1f%% согласованных, %.1f%% расколотых, %.1f%% нейтральных" % [
			_pct(int(selected.logic_aligned), resolved), _pct(int(selected.logic_split), resolved),
			_pct(int(selected.crowd_neutral), resolved)])
		var strict_resolved := int(selected.strict_aligned) + int(selected.strict_split) \
			+ int(selected.strict_neutral)
		print("Для сравнения при пороге 2: %.1f%% согласованных, %.1f%% расколотых, %.1f%% нейтральных" % [
			_pct(int(selected.strict_aligned), strict_resolved), _pct(int(selected.strict_split), strict_resolved),
			_pct(int(selected.strict_neutral), strict_resolved)])
		print("среди партий с логическим победителем; %.2f разворота зала за матч, corr(B,Lean)=%+.3f." % [
			float(selected.crowd_reversals) / n, _correlation(selected)])


# --------------------------------------- snapshot KO + резерв + шатание рамок ---

func _candidate_config(label: String, snapshot_ko: bool, reserve: bool,
		wobble: bool) -> Dictionary:
	var config := _production_crowd_config()
	config["id"] = "ko_wobble_candidate" if snapshot_ko or reserve or wobble \
		else "ko_wobble_reference"
	config["label"] = label
	config["selected_production"] = false
	# 2 — публичный Lean-порог нового composure gate; старый второй порог не используется.
	config["gate_x"] = 2 if wobble else 0
	config["gate_y"] = 4 if wobble else 0
	config["snapshot_ko"] = snapshot_ko
	config["guaranteed_reserve"] = reserve
	config["wobble"] = wobble
	return config


func _blank_candidate_metrics() -> Dictionary:
	return {
		"wins_you": 0, "wins_opp": 0, "draws": 0, "first_wins": 0, "decisive": 0,
		"turns": 0, "guard_hits": 0, "captures": 0, "capture_theses": 0,
		"hall_abs": 0, "heat_sum": 0,
		"knockdowns": 0, "reserve_saves": 0, "redeploys": 0,
		"snapshot_kos": 0, "early_kos": 0, "ko_action_sum": 0,
		"wobble_windows": 0, "wobble_reach_2": 0, "wobble_reach_3": 0,
		"wobble_reach_4": 0, "thick_attempts": 0, "thick_captures": 0,
		"thick_attempts_behind": 0, "thick_attempts_tied": 0,
		"thick_attempts_ahead": 0, "thick_captures_behind": 0,
		"thick_captures_tied": 0, "thick_captures_ahead": 0,
		"four_captures": 0, "defense_denials": 0,
		"telegraphed_captures": 0, "untelegraphed_captures": 0,
		"voluntary_stalls": 0, "exhausted_stalls": 0,
		"capture_at_1": 0, "capture_at_2": 0, "capture_at_3": 0,
		"capture_at_4": 0, "capture_at_5_plus": 0,
	}


func _run_candidate_cell(config: Dictionary, style_you: String, style_opp: String,
		matches: int, deck_you: Dictionary = {}, deck_opp: Dictionary = {},
		salt: int = 0) -> Dictionary:
	var out := _blank_candidate_metrics()
	for i in matches:
		_seed_for(i, salt)
		var first := Rules.SIDE_YOU if i % 2 == 0 else Rules.SIDE_OPP
		var m := _new_match(config, first, deck_you, deck_opp,
			_seed_value(i, salt) ^ 0x5EEDC0DE)
		var result: Dictionary = _ai.simulate(m, style_you, style_opp)
		var win := String(result.winner)
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
		out.turns += int(result.turns)
		out.guard_hits += int(int(result.turns) >= 400)
		out.captures += int(result.captures)
		out.capture_theses += int(result.capture_theses)
		out.hall_abs += absi(int(m.final_hall))
		out.heat_sum += int(m.final_heat)
		if m.has_method("candidate_metrics"):
			var diagnostics: Dictionary = m.candidate_metrics()
			for key in diagnostics:
				out[key] = int(out.get(key, 0)) + int(diagnostics[key])

	if int(out.early_kos) > int(out.snapshot_kos) \
			or int(out.redeploys) > int(out.reserve_saves) \
			or int(out.thick_captures) > int(out.thick_attempts) \
			or int(out.four_captures) > int(out.thick_captures):
		_failures += 1
	if int(out.thick_attempts_behind) + int(out.thick_attempts_tied) + \
			int(out.thick_attempts_ahead) != int(out.thick_attempts) or \
			int(out.thick_captures_behind) + int(out.thick_captures_tied) + \
			int(out.thick_captures_ahead) != int(out.thick_captures):
		_failures += 1
	if bool(config.get("snapshot_ko", false)) or bool(config.get("wobble", false)) \
			or bool(config.get("guaranteed_reserve", false)):
		var histogram_total := int(out.capture_at_1) + int(out.capture_at_2) \
			+ int(out.capture_at_3) + int(out.capture_at_4) + int(out.capture_at_5_plus)
		if int(out.untelegraphed_captures) != 0 or histogram_total != int(out.captures) \
				or int(out.telegraphed_captures) != int(out.captures):
			_failures += 1
	return out


func _candidate_winrate(m: Dictionary) -> float:
	var n := int(m.wins_you) + int(m.wins_opp) + int(m.draws)
	return 0.5 if n == 0 else (float(m.wins_you) + 0.5 * float(m.draws)) / float(n)


func _candidate_pair_rate(a: Dictionary, b: Dictionary) -> float:
	# A: тестируемая политика/колода играет YOU; B: она играет OPP.
	return (_candidate_winrate(a) + (1.0 - _candidate_winrate(b))) * 50.0


func _ko_wobble_suite() -> void:
	var quick := OS.get_cmdline_user_args().has("--quick")
	var n := mini(mirror_matches, 300) if quick else mirror_matches
	var dn := mini(deck_matches, 250) if quick else deck_matches
	if OS.get_cmdline_user_args().has("--long") and not quick:
		n *= 3
		dn *= 3

	print("Контракт: H5 = 1 гарантированная Установка + 4 боевые карты; резерв можно сыграть.")
	print("Последняя рамка: snapshot руки до refill → U = redeploy всем следующим ходом, иначе KO.")
	print("Шатание snapshot начала клинча: Lean к владельцу 0–1/2/3/4+ → reach 1/2/3/4.")
	print("Heat, strain и положение по доске reach не меняют; ответный T гасит opener.\n")

	var rows := [
		{"label": "без KO, random H5", "config": _candidate_config("reference", false, false, false),
			"style": "verdict"},
		{"label": "snapshot KO, random", "config": _candidate_config("snapshot", true, false, false),
			"style": "verdict"},
		{"label": "KO + reserve, spend", "config": _candidate_config("reserve", true, true, false),
			"style": "verdict"},
		{"label": "KO + wobble, spend", "config": _candidate_config("candidate", true, true, true),
			"style": "verdict"},
		{"label": "KO + wobble, hold", "config": _candidate_config("candidate", true, true, true),
			"style": "verdict_reserve"},
	]
	var results: Array = []
	print("--- A. ЗЕРКАЛО, %d МАТЧЕЙ/СТРОКУ ---" % n)
	print("%-24s | 1-й ход | KO | ран≤3 | ход KO | ходы | паден. | спас. | refrm | cap" % "вариант")
	for ri in rows.size():
		var row: Dictionary = rows[ri]
		var m := _run_candidate_cell(row.config, row.style, row.style, n, {}, {}, 2000 + ri)
		results.append(m)
		var avg_ko_action := float(m.ko_action_sum) / float(maxi(1, int(m.snapshot_kos)))
		print("%-24s | %7.1f%% | %4.1f%% | %5.1f%% | %6.1f | %4.1f | %6.2f | %5.2f | %5.2f | %4.2f" % [
			String(row.label), _pct(int(m.first_wins), int(m.decisive)),
			_pct(int(m.snapshot_kos), n), _pct(int(m.early_kos), n), avg_ko_action,
			float(m.turns) / n, float(m.knockdowns) / n, float(m.reserve_saves) / n,
			float(m.redeploys) / n, float(m.captures) / n])
	print("Ранний KO считается на 1–3-м полном действии; ход восстановления входит в длину матча.\n")

	print("--- B. ДОСЯГАЕМОСТЬ ШАТАНИЯ ---")
	print("%-24s | окон/матч | reach 2/3/4 | попытки >1 | трофеи >1 | def deny | cap4" % "вариант")
	for ri in rows.size():
		var row: Dictionary = rows[ri]
		var m: Dictionary = results[ri]
		print("%-24s | %9.3f | %4d/%4d/%3d | %10.3f | %9.3f | %8.3f | %4d" % [
			String(row.label), float(m.wobble_windows) / n, int(m.wobble_reach_2),
			int(m.wobble_reach_3), int(m.wobble_reach_4), float(m.thick_attempts) / n,
			float(m.thick_captures) / n, float(m.defense_denials) / n,
			int(m.four_captures)])
	print("Окно — любой открытый клинч с reach>1; попытка — Кража прямо в исходно толстую")
	print("рамку в reach; def deny — ответный Тезис погасил именно эту карту Кражи.\n")
	print("%-24s | thick attempts B/T/A | thick captures B/T/A" % "вариант")
	for ri in rows.size():
		var row: Dictionary = rows[ri]
		var m: Dictionary = results[ri]
		print("%-24s | %6d/%d/%d | %6d/%d/%d" % [
			String(row.label), int(m.thick_attempts_behind), int(m.thick_attempts_tied),
			int(m.thick_attempts_ahead), int(m.thick_captures_behind),
			int(m.thick_captures_tied), int(m.thick_captures_ahead)])
	print("B/T/A = атакующий отстаёт / равен / впереди по числу рамок в момент opener.\n")
	print("%-24s | tele/untele | толщина cap 1/2/3/4/5+ | stop vol/exh" % "вариант")
	for ri in range(1, rows.size()):
		var row: Dictionary = rows[ri]
		var m: Dictionary = results[ri]
		print("%-24s | %4d/%-6d | %4d/%4d/%4d/%4d/%-3d | %6.2f/%5.2f" % [
			String(row.label), int(m.telegraphed_captures), int(m.untelegraphed_captures),
			int(m.capture_at_1), int(m.capture_at_2), int(m.capture_at_3),
			int(m.capture_at_4), int(m.capture_at_5_plus),
			float(m.voluntary_stalls) / n, float(m.exhausted_stalls) / n])
	print("tele = непогашенная Кража целилась прямо в рамку при thickness ≤ snapshot reach; untele должен оставаться 0.\n")

	var candidate := _candidate_config("candidate", true, true, true)
	var hold_you := _run_candidate_cell(candidate, "verdict_reserve", "verdict", n, {}, {}, 2100)
	var hold_opp := _run_candidate_cell(candidate, "verdict", "verdict_reserve", n, {}, {}, 2100)
	print("--- C. ЦЕНА ЭКОНОМИКИ РУКИ ---")
	print("hold против spend, парно по обеим сторонам: %.1f%% побед hold" % [
		_candidate_pair_rate(hold_you, hold_opp)])
	print("hold сохраняет последнюю U, пока есть другой легальный глагол; spend строит ширину как текущий бот.\n")

	var decks := [
		{"label": "канон 3/8/9", "u": 3, "t": 8, "r": 9, "steals": 2},
		{"label": "глубина 2/12/6", "u": 2, "t": 12, "r": 6, "steals": 2},
		{"label": "ширина 5/7/8", "u": 5, "t": 7, "r": 8, "steals": 2},
		{"label": "разбор 2/6/12", "u": 2, "t": 6, "r": 12, "steals": 2},
		{"label": "смешанная 4/9/7", "u": 4, "t": 9, "r": 7, "steals": 2},
	]
	print("--- D. ОБОЙМЫ ПРОТИВ КАНОНА, HOLD-ПОЛИТИКА, %d×2 ---" % dn)
	print("%-20s | winrate | KO | ран≤3 | cap | thick cap | cap4" % "тестируемая обойма")
	for di in decks.size():
		var deck: Dictionary = decks[di]
		var a := _run_candidate_cell(candidate, "verdict_reserve", "verdict_reserve", dn,
			deck, {}, 2200 + di)
		var b := _run_candidate_cell(candidate, "verdict_reserve", "verdict_reserve", dn,
			{}, deck, 2200 + di)
		var total_matches := 2 * dn
		print("%-20s | %6.1f%% | %4.1f%% | %5.1f%% | %4.2f | %9.3f | %4d" % [
			String(deck.label), _candidate_pair_rate(a, b),
			_pct(int(a.snapshot_kos) + int(b.snapshot_kos), total_matches),
			_pct(int(a.early_kos) + int(b.early_kos), total_matches),
			float(int(a.captures) + int(b.captures)) / total_matches,
			float(int(a.thick_captures) + int(b.thick_captures)) / total_matches,
			int(a.capture_at_4) + int(b.capture_at_4)])
	print("Сторожа гипотезы: KO 10–25%; ранний KO ≤5%; первый ход 45–55%; cap4 только через")
	print("публичное окно reach=4. Выход за коридор — результат теста, не авто-подгонка правил.\n")

	print("--- E. СТИЛИ ПРОТИВ HOLD-КАНДИДАТА, %d×2 ---" % dn)
	print("%-10s | paired win | KO | ран≤3 | cap | thick cap | cap4" % "стиль")
	for si in ["wide", "aggro"]:
		var a := _run_candidate_cell(candidate, si, "verdict_reserve", dn, {}, {},
			2300 + (0 if si == "wide" else 1))
		var b := _run_candidate_cell(candidate, "verdict_reserve", si, dn, {}, {},
			2300 + (0 if si == "wide" else 1))
		var total_matches := 2 * dn
		print("%-10s | %9.1f%% | %4.1f%% | %5.1f%% | %4.2f | %9.3f | %4d" % [
			si, _candidate_pair_rate(a, b),
			_pct(int(a.snapshot_kos) + int(b.snapshot_kos), total_matches),
			_pct(int(a.early_kos) + int(b.early_kos), total_matches),
			float(int(a.captures) + int(b.captures)) / total_matches,
			float(int(a.thick_captures) + int(b.thick_captures)) / total_matches,
			int(a.capture_at_4) + int(b.capture_at_4)])
	var guard_hits := 0
	for m in results:
		guard_hits += int((m as Dictionary).guard_hits)
	guard_hits += int(hold_you.guard_hits) + int(hold_opp.guard_hits)
	print("\nGuard 400 действий: %d срабатываний в зеркалах/проверке политик." % guard_hits)


func _emotion_candidate_suite() -> void:
	var config: Dictionary = EMOTION_CONFIGS[2].duplicate(true)
	config["pressure_mode"] = "outcome_weighted"
	var n := mirror_matches
	print("Кандидат: 3Р+1Т+H; H ±5; победитель клинча даёт базовый ±1; карточный")
	print("эмоэффект −1/0/+1; сцена максимум ±2; длинное поражение получает +1 интенсивности.\n")

	print("--- A. ГЕЙТ ---")
	print("%-10s | 1-й ход | ничьи | реакции | захваты | |H| | Eflip" % "гейт")
	for gate in [[0, 0], [2, 4]]:
		var cell_config: Dictionary = config.duplicate(true)
		cell_config["gate_x"] = int(gate[0])
		cell_config["gate_y"] = int(gate[1])
		var m := _run_cell(cell_config, "verdict", "verdict", n, {}, {}, 1500)
		var label := "выкл" if int(gate[0]) == 0 else "2/4"
		print("%-10s | %7.1f%% | %5.1f%% | %7.2f | %7.2f | %3.1f | %5.1f%%" % [
			label, _pct(int(m.first_wins), int(m.decisive)), _pct(int(m.draws), n),
			float(m.reactions) / n, float(m.captures) / n, float(m.hall_abs) / n,
			_pct(int(m.emotion_terminal_flips), n)])

	var decks := [
		{"label": "канон 3/8/9", "u": 3, "t": 8, "r": 9, "steals": 2},
		{"label": "глубина 2/12/6", "u": 2, "t": 12, "r": 6, "steals": 2},
		{"label": "ширина 5/7/8", "u": 5, "t": 7, "r": 8, "steals": 2},
		{"label": "разбор 2/6/12", "u": 2, "t": 6, "r": 12, "steals": 2},
		{"label": "смешанная 4/9/7", "u": 4, "t": 9, "r": 7, "steals": 2},
	]
	print("\n--- B. АРХЕТИПЫ ПРОТИВ КАНОНА ---")
	print("%-22s | без эмоций | кандидат | Δэмоций | реакции | Eflip" % "обойма YOU")
	for di in decks.size():
		var comp: Dictionary = decks[di]
		var clean := _run_cell(EMOTION_CONFIGS[0], "verdict", "verdict", deck_matches,
			comp, {}, 1520 + di)
		var m := _run_cell(config, "verdict", "verdict", deck_matches, comp, {}, 1520 + di)
		var clean_wr := _winrate(clean) * 100.0
		var candidate_wr := _winrate(m) * 100.0
		print("%-22s | %9.1f%% | %8.1f%% | %+8.1f пп | %7.2f | %5.1f%%" % [String(comp.label),
			clean_wr, candidate_wr, candidate_wr - clean_wr, float(m.reactions) / deck_matches,
			_pct(int(m.emotion_terminal_flips), deck_matches)])
	print("Сторож кандидата: важна Δэмоций; абсолютные initiative/wide — прежние отдельные")
	print("блокеры формулы/захвата, которые этот слой не обязан и не должен маскировать.\n")


# ----------------------------------------- финальная треть / comeback audit ---

func _late_game_suite() -> void:
	var quick := OS.get_cmdline_user_args().has("--quick")
	var n := mini(mirror_matches, 300) if quick else mirror_matches
	if OS.get_cmdline_user_args().has("--long") and not quick:
		n *= 3
	var production := _candidate_config("production", true, true, true)
	var no_gate := _candidate_config("production_no_gate", true, true, false)
	var rows := [
		{"label": "prod full · hold", "config": production,
			"style": "verdict_reserve", "payoff": true},
		{"label": "prod без combo payoff", "config": production,
			"style": "verdict_reserve", "payoff": false},
		{"label": "prod без crowd gate", "config": no_gate,
			"style": "verdict_reserve", "payoff": true},
		{"label": "prod full · smart", "config": production,
			"style": "smart", "payoff": true},
		{"label": "prod full · balanced", "config": production,
			"style": "balanced", "payoff": true},
	]
	var results: Array = []
	print("Production: B=3·Δрамки+Δтезисы, snapshot KO, публичный резерв U,")
	print("независимый Audience → gate 2/4, текущий A3/combo-каталог и payoff.")
	print("Старый ориентир 0.61 считал рамки; поэтому ниже рядом стоят lock Р (legacy)")
	print("и lock B (фактический текущий вердикт). %d одинаковых сидов/строку.\n" % n)
	print("--- A. КОГДА ИСХОД ПЕРЕСТАЁТ БЫТЬ ОБРАТИМЫМ ---")
	print("%-25s | нич | KO | ходы | lock Р | lock B | B≥2/3 | лидер@.61 проигр. | лидер@.67 проигр." % "вариант")
	for ri in rows.size():
		var row: Dictionary = rows[ri]
		var m := _run_late_cell(row.config, String(row.style), n, bool(row.payoff), 2600)
		results.append(m)
		print("%-25s |%4.1f%%|%4.1f%%| %5.1f | %6.3f | %6.3f | %6.1f%% | %6.1f%% (%4d) | %6.1f%% (%4d)" % [
			String(row.label), _pct(int(m.draws), int(m.matches)),
			_pct(int(m.knockouts), int(m.matches)),
			float(m.actions) / float(maxi(1, int(m.matches))),
			_average(m.frame_locks), _average(m.board_locks),
			_pct(int(m.board_lock_late), int(m.decisive)),
			_pct(int(m.at61_wrong), int(m.at61_leaders)), int(m.at61_leaders),
			_pct(int(m.tail_wrong), int(m.tail_leaders)), int(m.tail_leaders)])
	print("lock = последний момент, когда будущий победитель ещё не был строго впереди.")
	print("«лидер проигр.» — прямой шанс камбэка из ненулевого отставания на срезе.\n")

	print("--- B. ЧТО ПРОИСХОДИТ ПОСЛЕ 2/3 ---")
	print("%-25s | ничья@2/3 | лидер терял + | переворот | смена лида | ΔB/ход | атаки | cap | combo V" % "вариант")
	for ri in rows.size():
		var row: Dictionary = rows[ri]
		var m: Dictionary = results[ri]
		print("%-25s | %9.1f%% | %12.1f%% | %8.1f%% | %9.1f%% | %7.1f%% | %5.1f%% |%4.2f | %7.3f" % [
			String(row.label), _pct(int(m.tail_tied), int(m.decisive)),
			_pct(int(m.tail_pressure), int(m.tail_dynamic_leaders)),
			_pct(int(m.tail_reversal), int(m.tail_dynamic_leaders)),
			_pct(int(m.tail_lead_switch), int(m.matches)),
			_pct(int(m.tail_changed_actions), int(m.tail_actions)),
			_pct(int(m.tail_attacks), int(m.tail_actions)),
			float(m.tail_captures) / float(maxi(1, int(m.matches))),
			float(m.tail_combo_verdicts) / float(maxi(1, int(m.matches)))])
	print("«лидер терял +» включает возврат хотя бы в ничью; «переворот» — уход в минус.")
	print("ΔB/ход — доля поздних действий, реально изменивших итоговый board margin.\n")

	print("--- C. РАСПРЕДЕЛЕНИЕ LOCK B (P50 / P75 / P90) ---")
	for ri in rows.size():
		var row: Dictionary = rows[ri]
		var m: Dictionary = results[ri]
		print("%-25s | %.3f / %.3f / %.3f" % [
			String(row.label), _percentile(m.board_locks, 0.50),
			_percentile(m.board_locks, 0.75), _percentile(m.board_locks, 0.90)])


func _run_late_cell(config: Dictionary, style: String, matches: int,
		payoff_enabled: bool, salt: int) -> Dictionary:
	var out := _blank_late_metrics()
	for i in matches:
		_seed_for(i, salt)
		var first := Rules.SIDE_YOU if i % 2 == 0 else Rules.SIDE_OPP
		var m := _new_match(config, first, {}, {},
			_seed_value(i, salt) ^ 0x5EEDC0DE)
		m.combo_payoff_enabled = payoff_enabled
		var res: Dictionary = _ai.simulate(m, style, style)
		var trace: Array = res.get("trajectory", [])
		if trace.is_empty():
			continue
		out.matches += 1
		out.actions += trace.size()
		var winner := String(res.get("winner", ""))
		if String(res.get("reason", "")) == "knockout":
			out.knockouts += 1
		if winner == "":
			out.draws += 1
		else:
			out.decisive += 1
			var frame_lock := _trace_lock_frac(trace, winner, "frame_diff")
			var board_lock := _trace_lock_frac(trace, winner, "board_margin")
			(out.frame_locks as Array).append(frame_lock)
			(out.board_locks as Array).append(board_lock)
			if board_lock >= 2.0 / 3.0:
				out.board_lock_late += 1
			_collect_checkpoint(out, trace, winner, 0.61, "at61")
			_collect_checkpoint(out, trace, winner, 2.0 / 3.0, "tail")
		_collect_tail_dynamics(out, trace)
	return out


func _blank_late_metrics() -> Dictionary:
	return {
		"matches": 0, "decisive": 0, "draws": 0, "knockouts": 0, "actions": 0,
		"frame_locks": [], "board_locks": [], "board_lock_late": 0,
		"at61_leaders": 0, "at61_wrong": 0, "at61_tied": 0,
		"tail_leaders": 0, "tail_wrong": 0, "tail_tied": 0,
		"tail_dynamic_leaders": 0,
		"tail_pressure": 0, "tail_reversal": 0, "tail_lead_switch": 0,
		"tail_actions": 0, "tail_changed_actions": 0, "tail_attacks": 0,
		"tail_captures": 0, "tail_combo_verdicts": 0,
	}


func _collect_checkpoint(out: Dictionary, trace: Array, winner: String,
		fraction: float, prefix: String) -> void:
	var idx := _fraction_index(trace.size(), fraction)
	var margin := int((trace[idx] as Dictionary).get("board_margin", 0))
	if margin == 0:
		out["%s_tied" % prefix] = int(out.get("%s_tied" % prefix, 0)) + 1
		return
	out["%s_leaders" % prefix] = int(out.get("%s_leaders" % prefix, 0)) + 1
	var winner_sign := 1 if winner == Rules.SIDE_YOU else -1
	if signi(margin) != winner_sign:
		out["%s_wrong" % prefix] = int(out.get("%s_wrong" % prefix, 0)) + 1


func _collect_tail_dynamics(out: Dictionary, trace: Array) -> void:
	var idx := _fraction_index(trace.size(), 2.0 / 3.0)
	var start: Dictionary = trace[idx]
	var start_margin := int(start.get("board_margin", 0))
	var start_sign := signi(start_margin)
	if start_sign != 0:
		out.tail_dynamic_leaders += 1
	var lost_positive := false
	var reversed := false
	var lead_switch := false
	var last_nonzero := start_sign
	for j in range(idx + 1, trace.size()):
		var previous: Dictionary = trace[j - 1]
		var point: Dictionary = trace[j]
		var margin := int(point.get("board_margin", 0))
		var point_sign := signi(margin)
		out.tail_actions += 1
		if margin != int(previous.get("board_margin", 0)):
			out.tail_changed_actions += 1
		if bool(point.get("attack", false)):
			out.tail_attacks += 1
		if start_sign != 0 and margin * start_sign <= 0:
			lost_positive = true
		if start_sign != 0 and margin * start_sign < 0:
			reversed = true
		if point_sign != 0:
			if last_nonzero != 0 and point_sign != last_nonzero:
				lead_switch = true
			last_nonzero = point_sign
	if start_sign != 0 and lost_positive:
		out.tail_pressure += 1
	if start_sign != 0 and reversed:
		out.tail_reversal += 1
	if lead_switch:
		out.tail_lead_switch += 1
	var finish: Dictionary = trace[-1]
	out.tail_captures += maxi(0, int(finish.get("captures", 0)) -
		int(start.get("captures", 0)))
	out.tail_combo_verdicts += maxi(0, int(finish.get("combo_verdicts", 0)) -
		int(start.get("combo_verdicts", 0)))


func _trace_lock_frac(trace: Array, winner: String, key: String) -> float:
	if trace.is_empty() or winner == "":
		return 1.0
	var winner_sign := 1 if winner == Rules.SIDE_YOU else -1
	var last_not_ahead := -1
	for i in trace.size():
		if int((trace[i] as Dictionary).get(key, 0)) * winner_sign <= 0:
			last_not_ahead = i
	return float(last_not_ahead + 1) / float(trace.size())


func _fraction_index(size: int, fraction: float) -> int:
	return clampi(ceili(float(size) * fraction) - 1, 0, size - 1)


func _average(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += float(value)
	return total / float(values.size())


func _percentile(values: Array, quantile: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var idx := clampi(roundi(float(sorted.size() - 1) * quantile), 0, sorted.size() - 1)
	return float(sorted[idx])


# ------------------------------------------ аудит удачи порядка основной колоды ---

func _draw_luck_suite() -> void:
	var quick := OS.get_cmdline_user_args().has("--quick")
	var blocks := 150 if quick else 600
	var counterfactual_pairs := 250 if quick else 1000
	var skill_gap_blocks := 250 if quick else 2000
	if OS.get_cmdline_user_args().has("--long") and not quick:
		blocks *= 3
		counterfactual_pairs *= 3
		skill_gap_blocks *= 3
	var production := _candidate_config("draw_luck_production", true, true, true)
	var styles := ["verdict_reserve", "smart"]
	var labels := {
		"verdict_reserve": "hold-reserve",
		"smart": "production smart",
	}
	var factorial_results := {}

	print("Production: U3/T8/R9, H5 = 1 гарантированная U + 4 действия, K2,")
	print("B=3·Δрамки+Δтезисы, snapshot KO, Audience gate 2/4, текущие combo.")
	print("Политики сами детерминированы; post-deal RNG используется только случайным T рамки,")
	print("а эмоции имеют отдельный seed. Это позволяет парно фиксировать остальные источники.\n")
	if OS.get_cmdline_user_args().has("--skill-gap-only"):
		_print_skill_gap_section(production, skill_gap_blocks)
		return
	if OS.get_cmdline_user_args().has("--counterfactual-only"):
		_print_draw_counterfactual_section(production, counterfactual_pairs)
		return

	print("--- A. ФАКТОРНЫЙ 2×2×2: DRAW-PACKAGE × EMOTION × INITIATIVE ---")
	print("%-18s | draw Shapley | emotion | initiative | полностью стабильных блоков" % "политика")
	for si in styles.size():
		var style: String = styles[si]
		var result := _run_luck_factorial(production, style, blocks, 3100 + si * 200)
		factorial_results[style] = result
		var shares: Dictionary = _luck_shapley(result.ss)
		print("%-18s | %11.1f%% | %7.1f%% | %10.1f%% | %8.1f%%" % [
			String(labels[style]), float(shares.deck) * 100.0,
			float(shares.emotion) * 100.0, float(shares.initiative) * 100.0,
			_pct(int(result.stable_blocks), int(result.blocks))])
	print("Shapley делит пополам/на троих взаимодействия факторов; три доли суммируются в 100%.")
	print("Это доля чувствительности результата, а не буквальная «доля заслуги» победителя.\n")

	print("--- B. ПРЯМАЯ ЧУВСТВИТЕЛЬНОСТЬ: МЕНЯЕМ ОДИН ФАКТОР ---")
	print("%-18s | фактор     | вердикт изменился | strict flip / все | flip / решит. | пар решит." % "политика")
	for style in styles:
		var result: Dictionary = factorial_results[style]
		for item in [
			["draw package", result.deck_pairs],
			["эмоции", result.emotion_pairs],
			["первый ход", result.initiative_pairs],
		]:
			var pair: Dictionary = item[1]
			print("%-18s | %-10s | %16.1f%% | %17.1f%% | %12.1f%% | %9d" % [
				String(labels[style]), String(item[0]),
				_pct(int(pair.changed), int(pair.comparisons)),
				_pct(int(pair.flips), int(pair.comparisons)),
				_pct(int(pair.flips), int(pair.both_decisive)),
				int(pair.both_decisive)])
	print("strict flip / все = YOU↔OPP среди всех пар; соседняя колонка условна на двух решительных исходах.\n")

	print("  Односторонний redraw при полностью фиксированном сопернике:")
	print("%-18s | вердикт изменился | strict flip / все | flip / решит. | пар решит." % "политика")
	for si in styles.size():
		var style: String = styles[si]
		var one_side := _run_one_side_redraw(production, style, counterfactual_pairs,
			3450 + si * 100)
		print("%-18s | %16.1f%% | %17.1f%% | %12.1f%% | %9d" % [
			String(labels[style]), _pct(int(one_side.changed), int(one_side.comparisons)),
			_pct(int(one_side.flips), int(one_side.comparisons)),
			_pct(int(one_side.flips), int(one_side.both_decisive)),
			int(one_side.both_decisive)])
	print("Здесь перетасовывается пакет только одного игрока; колода соперника, первый ход,")
	print("эмоции и runtime seed случайных T остаются теми же.\n")

	print("--- C. ЧТО В СТАРТОВОЙ/РАННЕЙ ВЫБОРКЕ ПРЕДСКАЗЫВАЕТ ПОБЕДУ ---")
	print("%-18s | больше R в H5 | больше K в H5 | K лежит ближе | больше R в H5+top3 | больше U в H5+top3" % "политика")
	for style in styles:
		var features: Dictionary = (factorial_results[style] as Dictionary).features
		print("%-18s | %13.1f%% | %13.1f%% | %15.1f%% | %19.1f%% | %19.1f%%" % [
			String(labels[style]),
			_advantage_rate(features.opening_r),
			_advantage_rate(features.opening_steals),
			_advantage_rate(features.first_steal),
			_advantage_rate(features.early_r),
			_advantage_rate(features.early_u)])
	print("Значение — винрейт стороны с большим показателем, только когда показатели различались.")
	print("K = Кража; top3 = три верхние карты initial draw, не обязательно три фактических добора:")
	print("новая U может раньше случайно изъять из draw один T.\n")
	for style in styles:
		print("  %s — ΔR стартовой руки (YOU−OPP):" % String(labels[style]))
		_print_opening_r_bins((factorial_results[style] as Dictionary).features)

	_print_draw_counterfactual_section(production, counterfactual_pairs)
	_print_skill_gap_section(production, skill_gap_blocks)


func _print_draw_counterfactual_section(production: Dictionary, pairs: int) -> void:
	print("\n--- D. ГДЕ ИМЕННО СИДИТ DRAW-RNG: СТАРТОВАЯ РУКА ИЛИ ХВОСТ ---")
	var counterfactual := _run_draw_counterfactuals(production, "verdict_reserve",
		pairs, 3700)
	print("%-24s | вердикт изменился | strict flip / все | flip / решит. | пар решит." % "контрфактуал")
	for item in [
		["весь main-deck RNG", counterfactual.full_draw],
		["H5 та же, только tail", counterfactual.tail_only],
		["H5 та же, tail + seed-T", counterfactual.tail_plus_frame],
		["весь порядок тот же, seed-T", counterfactual.frame_seed],
		["весь draw тот же, эмоции", counterfactual.emotion],
		["весь draw тот же, 1-й ход", counterfactual.initiative],
	]:
		var pair: Dictionary = item[1]
		print("%-24s | %16.1f%% | %17.1f%% | %12.1f%% | %9d" % [
			String(item[0]), _pct(int(pair.changed), int(pair.comparisons)),
			_pct(int(pair.flips), int(pair.comparisons)),
			_pct(int(pair.flips), int(pair.both_decisive)), int(pair.both_decisive)])
	print("Чистый tail-reroll сохраняет exact H5, стартовые тезисы, резерв и post-deal seed;")
	print("меняется только неувиденная draw-стопка. Следующая строка дополнительно меняет seed")
	print("случайного T новой рамки; seed-T меняет только его при одинаковом порядке карт.")
	print("Эффекты взаимодействуют, поэтому эти проценты нельзя складывать или вычитать.\n")


func _print_skill_gap_section(production: Dictionary, blocks: int) -> void:
	print("\n--- E. МОЖЕТ ЛИ REDRAW ПЕРЕБИТЬ МАЛЫЙ ЗАЗОР ПОЛИТИКИ ---")
	var result := _run_skill_gap_redraw(production, blocks, 3900)
	var weak_utility := (float(result.weak_wins) + 0.5 * float(result.draws)) / \
		float(maxi(1, int(result.matches)))
	var rescue_denominator := 2 * int(result.stable_strong) + int(result.flips)
	print("hold-reserve против spend-reserve (`verdict`), роли и первый ход сбалансированы.")
	print("hold-reserve utility: %.1f%%; redraw слабой стороны меняет вердикт: %.1f%%." % [
		(1.0 - weak_utility) * 100.0,
		_pct(int(result.changed), int(result.comparisons))])
	print("Strict YOU↔OPP flip: %.1f%% всех блоков; %.1f%% среди двух решительных исходов." % [
		_pct(int(result.flips), int(result.comparisons)),
		_pct(int(result.flips), int(result.both_decisive))])
	print("Устойчиво сильная / устойчиво слабая: %.1f%% / %.1f%% решительных блоков;" % [
		_pct(int(result.stable_strong), int(result.both_decisive)),
		_pct(int(result.stable_weak), int(result.both_decisive))])
	print("если случайно выбранная раздача слабой стороны проиграла, альтернативная спасает")
	print("до прямой победы в %.1f%% решительных случаев." % [
		_pct(int(result.flips), rescue_denominator)])
	print("Это тест малого искусственного skill-gap между двумя deterministic sim-политиками,")
	print("а не оценка разницы между сильным и слабым человеком.\n")


func _run_skill_gap_redraw(config: Dictionary, blocks: int, salt: int) -> Dictionary:
	var out := _blank_pair_metrics()
	out.merge({
		"matches": 0, "weak_wins": 0, "strong_wins": 0, "draws": 0,
		"stable_strong": 0, "stable_weak": 0,
	})
	for i in blocks:
		var weak_side := Rules.SIDE_YOU if i % 4 < 2 else Rules.SIDE_OPP
		var strong_side := Rules.SIDE_OPP if weak_side == Rules.SIDE_YOU else Rules.SIDE_YOU
		var first := Rules.SIDE_YOU if i % 2 == 0 else Rules.SIDE_OPP
		var emotion_seed := _seed_value(i, salt + 101) ^ 0x5EEDC0DE
		var play_seed := _seed_value(i, salt + 211)

		seed(_seed_value(i, salt))
		var strong_source := _new_match(config, first, {}, {}, emotion_seed)
		seed(_seed_value(i, salt + 31))
		var weak_a_source := _new_match(config, first, {}, {}, emotion_seed)
		seed(_seed_value(i, salt + 47))
		var weak_b_source := _new_match(config, first, {}, {}, emotion_seed)
		var sides_a := {
			strong_side: strong_source.sides[strong_side].duplicate(true),
			weak_side: weak_a_source.sides[weak_side].duplicate(true),
		}
		var sides_b := {
			strong_side: strong_source.sides[strong_side].duplicate(true),
			weak_side: weak_b_source.sides[weak_side].duplicate(true),
		}
		var style_you := "verdict" if weak_side == Rules.SIDE_YOU else "verdict_reserve"
		var style_opp := "verdict" if weak_side == Rules.SIDE_OPP else "verdict_reserve"

		var match_a := _match_from_snapshot(config, first, sides_a,
			emotion_seed, _seed_value(i, salt + 501))
		seed(play_seed)
		var result_a: Dictionary = _ai.simulate(match_a, style_you, style_opp)
		var value_a := _outcome_for_side(String(result_a.get("winner", "")), weak_side)

		var match_b := _match_from_snapshot(config, first, sides_b,
			emotion_seed, _seed_value(i, salt + 502))
		seed(play_seed)
		var result_b: Dictionary = _ai.simulate(match_b, style_you, style_opp)
		var value_b := _outcome_for_side(String(result_b.get("winner", "")), weak_side)

		_collect_pair_values(out, value_a, value_b)
		for value in [value_a, value_b]:
			out.matches += 1
			if value > 0:
				out.weak_wins += 1
			elif value < 0:
				out.strong_wins += 1
			else:
				out.draws += 1
		if value_a == -1 and value_b == -1:
			out.stable_strong += 1
		elif value_a == 1 and value_b == 1:
			out.stable_weak += 1
	return out


func _outcome_for_side(winner: String, side: String) -> int:
	return 1 if winner == side else (-1 if winner != "" else 0)


func _run_luck_factorial(config: Dictionary, style: String, blocks: int,
		salt: int) -> Dictionary:
	var ss := {}
	for mask in range(1, 8):
		ss[mask] = 0.0
	var out := {
		"blocks": blocks, "stable_blocks": 0, "ss": ss,
		"deck_pairs": _blank_pair_metrics(),
		"emotion_pairs": _blank_pair_metrics(),
		"initiative_pairs": _blank_pair_metrics(),
		"features": _blank_opening_features(),
	}
	for block in blocks:
		var outcomes: Array = []
		outcomes.resize(8)
		var unique := {}
		# Два независимо подготовленных production-пакета: стартовый настоящий T,
		# H5 после reserve и полный остаток draw. D меняет только владельцев A/B.
		seed(_seed_value(block, salt))
		var source_a := _new_match(config, Rules.SIDE_YOU, {}, {},
			_seed_value(block, salt + 701))
		var package_a: Dictionary = source_a.sides[Rules.SIDE_YOU].duplicate(true)
		seed(_seed_value(block, salt + 31))
		var source_b := _new_match(config, Rules.SIDE_YOU, {}, {},
			_seed_value(block, salt + 702))
		var package_b: Dictionary = source_b.sides[Rules.SIDE_OPP].duplicate(true)
		var play_seed := _seed_value(block, salt + 211)
		for deck_level in 2:
			for emotion_level in 2:
				var emotion_seed := _seed_value(block, salt + 101 + emotion_level * 37) \
					^ 0x5EEDC0DE
				for initiative_level in 2:
					var first := Rules.SIDE_YOU if initiative_level == 0 else Rules.SIDE_OPP
					var assigned := {
						Rules.SIDE_YOU: (package_a if deck_level == 0 else package_b),
						Rules.SIDE_OPP: (package_b if deck_level == 0 else package_a),
					}
					var m := _match_from_snapshot(config, first, assigned,
						emotion_seed, _seed_value(block, salt + 501))
					var capture_features := emotion_level == 0 and \
						initiative_level == ((block + deck_level) % 2)
					var opening := _opening_feature_delta(m.sides) if capture_features else {}
					# Runtime seed-T фиксирован между D/E/I: фактор D — только prepared draw.
					seed(play_seed)
					var res: Dictionary = _ai.simulate(m, style, style)
					var value := _outcome_value(String(res.get("winner", "")))
					outcomes[_factor_index(deck_level, emotion_level, initiative_level)] = value
					unique[value] = true
					if capture_features:
						_collect_opening_feature_result(out.features, opening, value,
							first == Rules.SIDE_YOU)
		if unique.size() == 1:
			out.stable_blocks += 1
		for mask in range(1, 8):
			var coefficient := 0.0
			for deck_level in 2:
				for emotion_level in 2:
					for initiative_level in 2:
						var factor_sign := 1
						if (mask & 1) != 0:
							factor_sign *= 1 if deck_level == 1 else -1
						if (mask & 2) != 0:
							factor_sign *= 1 if emotion_level == 1 else -1
						if (mask & 4) != 0:
							factor_sign *= 1 if initiative_level == 1 else -1
						coefficient += float(outcomes[
							_factor_index(deck_level, emotion_level, initiative_level)]) \
							* float(factor_sign)
			coefficient /= 8.0
			out.ss[mask] = float(out.ss[mask]) + coefficient * coefficient
		for emotion_level in 2:
			for initiative_level in 2:
				_collect_pair_values(out.deck_pairs,
					int(outcomes[_factor_index(0, emotion_level, initiative_level)]),
					int(outcomes[_factor_index(1, emotion_level, initiative_level)]))
		for deck_level in 2:
			for initiative_level in 2:
				_collect_pair_values(out.emotion_pairs,
					int(outcomes[_factor_index(deck_level, 0, initiative_level)]),
					int(outcomes[_factor_index(deck_level, 1, initiative_level)]))
		for deck_level in 2:
			for emotion_level in 2:
				_collect_pair_values(out.initiative_pairs,
					int(outcomes[_factor_index(deck_level, emotion_level, 0)]),
					int(outcomes[_factor_index(deck_level, emotion_level, 1)]))
	return out


func _run_one_side_redraw(config: Dictionary, style: String, pairs: int,
		salt: int) -> Dictionary:
	var out := _blank_pair_metrics()
	for i in pairs:
		var first := Rules.SIDE_YOU if i % 2 == 0 else Rules.SIDE_OPP
		var emotion_seed := _seed_value(i, salt + 101) ^ 0x5EEDC0DE
		var play_seed := _seed_value(i, salt + 211)

		# Один базовый контекст и по одному независимому redraw для каждой стороны.
		# Источник строится с тем же first, чтобы сохранить production-коми в Базе.
		seed(_seed_value(i, salt))
		var base_source := _new_match(config, first, {}, {}, emotion_seed)
		var base_sides: Dictionary = base_source.sides.duplicate(true)

		seed(_seed_value(i, salt + 31))
		var alternate_you_source := _new_match(config, first, {}, {}, emotion_seed)
		var you_redraw_sides: Dictionary = base_sides.duplicate(true)
		you_redraw_sides[Rules.SIDE_YOU] = \
			alternate_you_source.sides[Rules.SIDE_YOU].duplicate(true)

		seed(_seed_value(i, salt + 47))
		var alternate_opp_source := _new_match(config, first, {}, {}, emotion_seed)
		var opp_redraw_sides: Dictionary = base_sides.duplicate(true)
		opp_redraw_sides[Rules.SIDE_OPP] = \
			alternate_opp_source.sides[Rules.SIDE_OPP].duplicate(true)

		var baseline := _match_from_snapshot(config, first, base_sides,
			emotion_seed, _seed_value(i, salt + 501))
		seed(play_seed)
		var baseline_result: Dictionary = _ai.simulate(baseline, style, style)
		var baseline_value := _outcome_value(String(baseline_result.get("winner", "")))

		var you_redraw := _match_from_snapshot(config, first, you_redraw_sides,
			emotion_seed, _seed_value(i, salt + 502))
		seed(play_seed)
		var you_redraw_result: Dictionary = _ai.simulate(you_redraw, style, style)
		_collect_pair_values(out, baseline_value,
			_outcome_value(String(you_redraw_result.get("winner", ""))))

		var opp_redraw := _match_from_snapshot(config, first, opp_redraw_sides,
			emotion_seed, _seed_value(i, salt + 503))
		seed(play_seed)
		var opp_redraw_result: Dictionary = _ai.simulate(opp_redraw, style, style)
		_collect_pair_values(out, baseline_value,
			_outcome_value(String(opp_redraw_result.get("winner", ""))))
	return out


func _luck_shapley(ss: Dictionary) -> Dictionary:
	var total := 0.0
	for mask in range(1, 8):
		total += float(ss.get(mask, 0.0))
	if total <= 0.0:
		return {"deck": 0.0, "emotion": 0.0, "initiative": 0.0}
	var deck := float(ss[1]) + 0.5 * float(ss[3]) + 0.5 * float(ss[5]) \
		+ float(ss[7]) / 3.0
	var emotion := float(ss[2]) + 0.5 * float(ss[3]) + 0.5 * float(ss[6]) \
		+ float(ss[7]) / 3.0
	var initiative := float(ss[4]) + 0.5 * float(ss[5]) + 0.5 * float(ss[6]) \
		+ float(ss[7]) / 3.0
	return {
		"deck": deck / total,
		"emotion": emotion / total,
		"initiative": initiative / total,
	}


func _factor_index(deck_level: int, emotion_level: int, initiative_level: int) -> int:
	return deck_level * 4 + emotion_level * 2 + initiative_level


func _outcome_value(winner: String) -> int:
	return 1 if winner == Rules.SIDE_YOU else (-1 if winner == Rules.SIDE_OPP else 0)


func _blank_pair_metrics() -> Dictionary:
	return {
		"comparisons": 0, "changed": 0, "both_decisive": 0,
		"flips": 0, "draw_touched": 0,
	}


func _collect_pair_values(out: Dictionary, a: int, b: int) -> void:
	out.comparisons += 1
	if a != b:
		out.changed += 1
	if a == 0 or b == 0:
		out.draw_touched += 1
	else:
		out.both_decisive += 1
		if a != b:
			out.flips += 1


func _blank_opening_features() -> Dictionary:
	return {
		"matches": 0, "decisive": 0, "draws": 0, "first_wins": 0,
		"opening_r": _blank_advantage(), "opening_steals": _blank_advantage(),
		"first_steal": _blank_advantage(), "early_r": _blank_advantage(),
		"early_u": _blank_advantage(), "r_bins": {},
	}


func _blank_advantage() -> Dictionary:
	return {"opportunities": 0, "advantage_wins": 0, "ties": 0}


func _opening_feature_delta(sides: Dictionary) -> Dictionary:
	var you: Dictionary = _side_opening_features(sides[Rules.SIDE_YOU])
	var opp: Dictionary = _side_opening_features(sides[Rules.SIDE_OPP])
	return {
		"opening_r": int(you.opening_r) - int(opp.opening_r),
		"opening_steals": int(you.opening_steals) - int(opp.opening_steals),
		# Меньшая глубина лучше, поэтому положительный знак означает преимущество YOU.
		"first_steal": int(opp.first_steal_depth) - int(you.first_steal_depth),
		"early_r": int(you.early_r) - int(opp.early_r),
		"early_u": int(you.early_u) - int(opp.early_u),
	}


func _side_opening_features(side: Dictionary) -> Dictionary:
	var hand: Array = side.get("hand", [])
	var draw: Array = side.get("draw", [])
	var opening_r := 0
	var opening_steals := 0
	var first_steal_depth := 999
	for card_raw in hand:
		var card: Dictionary = card_raw
		if String(card.get("type", "")) == Rules.TYPE_RAZBOR:
			opening_r += 1
		if bool(card.get("steals", false)):
			opening_steals += 1
			first_steal_depth = 0
	if first_steal_depth > 0:
		for depth in draw.size():
			var card: Dictionary = draw[draw.size() - 1 - depth]
			if bool(card.get("steals", false)):
				first_steal_depth = depth + 1
				break
	var early_cards: Array = hand.duplicate()
	for depth in mini(3, draw.size()):
		early_cards.append(draw[draw.size() - 1 - depth])
	var early_r := 0
	var early_u := 0
	for card_raw in early_cards:
		var card: Dictionary = card_raw
		match String(card.get("type", "")):
			Rules.TYPE_RAZBOR: early_r += 1
			Rules.TYPE_USTANOVKA: early_u += 1
	return {
		"opening_r": opening_r,
		"opening_steals": opening_steals,
		"first_steal_depth": first_steal_depth,
		"early_r": early_r,
		"early_u": early_u,
	}


func _collect_opening_feature_result(out: Dictionary, deltas: Dictionary,
		outcome: int, first_you: bool) -> void:
	out.matches += 1
	if outcome == 0:
		out.draws += 1
		return
	out.decisive += 1
	if outcome == (1 if first_you else -1):
		out.first_wins += 1
	for key in ["opening_r", "opening_steals", "first_steal", "early_r", "early_u"]:
		_collect_advantage(out[key], int(deltas[key]), outcome)
	var r_key := str(int(deltas.opening_r))
	if not (out.r_bins as Dictionary).has(r_key):
		out.r_bins[r_key] = {"n": 0, "you_wins": 0}
	out.r_bins[r_key].n = int(out.r_bins[r_key].n) + 1
	if outcome > 0:
		out.r_bins[r_key].you_wins = int(out.r_bins[r_key].you_wins) + 1


func _collect_advantage(out: Dictionary, delta: int, outcome: int) -> void:
	if delta == 0:
		out.ties += 1
		return
	out.opportunities += 1
	if signi(delta) == outcome:
		out.advantage_wins += 1


func _advantage_rate(metric: Dictionary) -> float:
	return _pct(int(metric.advantage_wins), int(metric.opportunities))


func _print_opening_r_bins(features: Dictionary) -> void:
	var keys := (features.r_bins as Dictionary).keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	var pieces: Array = []
	for key in keys:
		var bin: Dictionary = features.r_bins[key]
		pieces.append("%+d:%4.0f%%(n=%d)" % [
			int(key), _pct(int(bin.you_wins), int(bin.n)), int(bin.n)])
	print("    " + " · ".join(pieces))


func _run_draw_counterfactuals(config: Dictionary, style: String, pairs: int,
		salt: int) -> Dictionary:
	var out := {
		"full_draw": _blank_pair_metrics(),
		"tail_only": _blank_pair_metrics(),
		"tail_plus_frame": _blank_pair_metrics(),
		"frame_seed": _blank_pair_metrics(),
		"emotion": _blank_pair_metrics(),
		"initiative": _blank_pair_metrics(),
	}
	for i in pairs:
		var first := Rules.SIDE_YOU if i % 2 == 0 else Rules.SIDE_OPP
		var deck_seed := _seed_value(i, salt)
		var play_seed := _seed_value(i, salt + 211)
		var emotion_seed := _seed_value(i, salt + 101) ^ 0x5EEDC0DE
		seed(deck_seed)
		var baseline := _new_match(config, first, {}, {}, emotion_seed)
		var sides_snapshot: Dictionary = baseline.sides.duplicate(true)
		seed(play_seed)
		var base_result: Dictionary = _ai.simulate(baseline, style, style)
		var base_value := _outcome_value(String(base_result.get("winner", "")))

		seed(_seed_value(i, salt + 31))
		var full_reroll := _new_match(config, first, {}, {}, emotion_seed)
		# Isolate the rebuilt deck package: runtime frame-T RNG must stay paired.
		seed(play_seed)
		var full_result: Dictionary = _ai.simulate(full_reroll, style, style)
		_collect_pair_values(out.full_draw, base_value,
			_outcome_value(String(full_result.get("winner", ""))))

		var tail_only := _match_from_snapshot(config, first, sides_snapshot,
			emotion_seed, _seed_value(i, salt + 401))
		seed(_seed_value(i, salt + 47))
		for side in [Rules.SIDE_YOU, Rules.SIDE_OPP]:
			(tail_only.sides[side].draw as Array).shuffle()
		seed(play_seed)
		var tail_only_result: Dictionary = _ai.simulate(tail_only, style, style)
		_collect_pair_values(out.tail_only, base_value,
			_outcome_value(String(tail_only_result.get("winner", ""))))

		var tail_plus_frame := _match_from_snapshot(config, first, sides_snapshot,
			emotion_seed, _seed_value(i, salt + 405))
		seed(_seed_value(i, salt + 47))
		for side in [Rules.SIDE_YOU, Rules.SIDE_OPP]:
			(tail_plus_frame.sides[side].draw as Array).shuffle()
		seed(_seed_value(i, salt + 258))
		var tail_plus_frame_result: Dictionary = _ai.simulate(tail_plus_frame,
			style, style)
		_collect_pair_values(out.tail_plus_frame, base_value,
			_outcome_value(String(tail_plus_frame_result.get("winner", ""))))

		var frame_seed_reroll := _match_from_snapshot(config, first, sides_snapshot,
			emotion_seed, _seed_value(i, salt + 404))
		seed(_seed_value(i, salt + 259))
		var frame_seed_result: Dictionary = _ai.simulate(frame_seed_reroll, style, style)
		_collect_pair_values(out.frame_seed, base_value,
			_outcome_value(String(frame_seed_result.get("winner", ""))))

		var emotion_reroll := _match_from_snapshot(config, first, sides_snapshot,
			_seed_value(i, salt + 137) ^ 0x5EEDC0DE, _seed_value(i, salt + 402))
		seed(play_seed)
		var emotion_result: Dictionary = _ai.simulate(emotion_reroll, style, style)
		_collect_pair_values(out.emotion, base_value,
			_outcome_value(String(emotion_result.get("winner", ""))))

		var other_first := Rules.SIDE_OPP if first == Rules.SIDE_YOU else Rules.SIDE_YOU
		var initiative_reroll := _match_from_snapshot(config, other_first, sides_snapshot,
			emotion_seed, _seed_value(i, salt + 403))
		seed(play_seed)
		var initiative_result: Dictionary = _ai.simulate(initiative_reroll, style, style)
		_collect_pair_values(out.initiative, base_value,
			_outcome_value(String(initiative_result.get("winner", ""))))
	return out


func _match_from_snapshot(config: Dictionary, first: String, sides_snapshot: Dictionary,
		emotion_seed: int, setup_seed: int) -> RefCounted:
	seed(setup_seed)
	var m := _new_match(config, first, {}, {}, emotion_seed)
	m.sides = sides_snapshot.duplicate(true)
	return m


# ------------------------------------------------- лестница навыка vs удача ---

## Аудит 2026-07-27 мерил чувствительность к колоде ТОЛЬКО в зеркале одинаковых
## детерминированных политик. Там исход по построению является функцией асимметричных
## случайных входов — больше свободных переменных нет, поэтому высокий flip почти
## тавтологичен. Здесь мерится отношение сигнал/шум: сколько винрейта вообще способна
## купить разница политик и как flip падает по мере роста этой разницы.
func _skill_ladder_suite() -> void:
	var quick := OS.get_cmdline_user_args().has("--quick")
	var ladder_matches := 300 if quick else 1200
	var redraw_pairs := 200 if quick else 900
	if OS.get_cmdline_user_args().has("--long") and not quick:
		ladder_matches *= 2
		redraw_pairs *= 2
	var production := _candidate_config("skill_ladder_production", true, true, true)
	var ladder := ["coinflip", "aggro", "wide", "tall", "balanced", "smart",
		"verdict", "verdict_reserve"]

	print("Production-контракт тот же, что в draw-luck: U3/T8/R9, H5, K2, B=3Р+1Т,")
	print("snapshot KO, публичный резерв, Audience gate 2/4, текущие combo.")
	print("Каждая пара играет обе роли на ОДНИХ и тех же seed — раздачи спарены,")
	print("меняются только политики. coinflip — детерминированный выбор легального хода.\n")

	if OS.get_cmdline_user_args().has("--agreement-only"):
		_print_agreement_section(production, ladder_matches)
		return

	print("--- A. ЛЕСТНИЦА: СКОЛЬКО ВИНРЕЙТА ПОКУПАЕТ ПОЛИТИКА ---")
	print("Ячейка — винрейт политики СТРОКИ против политики СТОЛБЦА, роли сбалансированы.")
	var header := "%-16s" % "политика"
	for style in ladder:
		header += " | %7s" % style.substr(0, 7)
	print(header + " |  средн.")
	var pair_rates := {}
	for ai in ladder.size():
		var row := "%-16s" % ladder[ai]
		var sum := 0.0
		var count := 0
		for bi in ladder.size():
			if ai == bi:
				row += " | %6s " % "—"
				continue
			var key := "%d:%d" % [mini(ai, bi), maxi(ai, bi)]
			if not pair_rates.has(key):
				pair_rates[key] = _run_ladder_pair(production, ladder[mini(ai, bi)],
					ladder[maxi(ai, bi)], ladder_matches, 4200 + mini(ai, bi) * 40 + maxi(ai, bi))
			var rate: float = float(pair_rates[key])
			if ai > bi:
				rate = 100.0 - rate
			row += " | %6.1f%%" % rate
			sum += rate
			count += 1
		print(row + " | %6.1f%%" % (sum / float(maxi(1, count))))
	print("\nЭто потолок навыка в текущем ruleset: разброс строки «средн.» показывает,")
	print("насколько вообще качество решений отделимо от раздачи.\n")

	print("--- B. FLIP ПАДАЕТ ЛИ С РОСТОМ ЗАЗОРА НАВЫКА ---")
	print("Односторонний redraw при фиксированном сопернике, но политики РАЗНЫЕ.")
	print("%-30s | винрейт A | strict/all | strict/решит. | матчей до 95%%" % "пара A против B")
	var gap_pairs := [
		["verdict_reserve", "verdict_reserve"],
		["verdict_reserve", "verdict"],
		["verdict_reserve", "smart"],
		["verdict_reserve", "balanced"],
		["verdict_reserve", "tall"],
		["verdict_reserve", "aggro"],
		["verdict_reserve", "coinflip"],
		["smart", "coinflip"],
	]
	for gi in gap_pairs.size():
		var pair: Array = gap_pairs[gi]
		var result := _run_gap_redraw(production, String(pair[0]), String(pair[1]),
			redraw_pairs, 4700 + gi * 60)
		var winrate := float(result.a_winrate)
		var flip_all := _pct(int(result.flips), int(result.comparisons))
		var flip_decisive := _pct(int(result.flips), int(result.both_decisive))
		var label := "%s vs %s" % [pair[0], pair[1]]
		print("%-30s | %8.1f%% | %10.1f%% | %13.1f%% | %13s" % [
			label, winrate, flip_all, flip_decisive, _format_detect(winrate)])
	print("\nstrict/all и strict/решит. имеют разные знаменатели; с mirror flip из")
	print("другого suite напрямую сравнивается только strict/all. Матрица показывает")
	print("matchup-структуру, а не линейную лестницу навыка; близкие значения требуют")
	print("более длинного прогона.\n")

	_print_agreement_section(production, ladder_matches)


func _print_agreement_section(production: Dictionary, ladder_matches: int) -> void:
	print("\n--- C. ШИРИНА ПРОСТРАНСТВА РЕШЕНИЙ ---")
	print("Доля точек решения, где основная политика выбирает ТО ЖЕ, что и эталонная.")
	print("Если расхождений почти нет, «навык» в текущем ruleset нечему выражать,")
	print("и раздача остаётся единственной свободной переменной.")
	print("%-34s | точек решения | тот же тип | тип и цель" % "основная / эталон")
	for probe in [
		["verdict_reserve", "aggro"],
		["verdict_reserve", "smart"],
		["verdict_reserve", "coinflip"],
		["smart", "aggro"],
	]:
		var agreement := _run_shadow_agreement(production, String(probe[0]),
			String(probe[1]), maxi(60, ladder_matches / 4), 5400)
		print("%-34s | %13d | %9.1f%% | %10.1f%%" % [
			"%s / %s" % [probe[0], probe[1]], int(agreement.total),
			_pct(int(agreement.same_type), int(agreement.total)),
			_pct(int(agreement.same_full), int(agreement.total))])
	print("")


func _run_ladder_pair(config: Dictionary, style_a: String, style_b: String,
		matches: int, salt: int) -> float:
	# Один и тот же salt в обеих ориентациях: раздачи и первый ход идентичны,
	# различаются только политики сторон. Это парный дизайн, а не два независимых прогона.
	# Харнесс именно candidate: _run_cell проверяет инвариант «матч кончается счётом»,
	# который production-конфиг со snapshot KO нарушает by design.
	var a_you := _run_candidate_cell(config, style_a, style_b, matches, {}, {}, salt)
	var a_opp := _run_candidate_cell(config, style_b, style_a, matches, {}, {}, salt)
	var n_you := int(a_you.wins_you) + int(a_you.wins_opp) + int(a_you.draws)
	var n_opp := int(a_opp.wins_you) + int(a_opp.wins_opp) + int(a_opp.draws)
	var rate_you := 0.5 if n_you == 0 else \
		(float(a_you.wins_you) + 0.5 * float(a_you.draws)) / float(n_you)
	var rate_opp := 0.5 if n_opp == 0 else \
		(float(a_opp.wins_opp) + 0.5 * float(a_opp.draws)) / float(n_opp)
	return (rate_you + rate_opp) * 50.0


func _run_gap_redraw(config: Dictionary, style_a: String, style_b: String,
		pairs: int, salt: int) -> Dictionary:
	var out := _blank_pair_metrics()
	var a_score := 0.0
	var a_matches := 0
	for i in pairs:
		# Первый ход и назначение политик балансируются независимо: 2×2 на каждые
		# четыре блока, чтобы ни коми Базы, ни роль не смещали винрейт A.
		var first := Rules.SIDE_YOU if i % 2 == 0 else Rules.SIDE_OPP
		var a_side := Rules.SIDE_YOU if (i / 2) % 2 == 0 else Rules.SIDE_OPP
		var style_you := style_a if a_side == Rules.SIDE_YOU else style_b
		var style_opp := style_b if a_side == Rules.SIDE_YOU else style_a
		var emotion_seed := _seed_value(i, salt + 101) ^ 0x5EEDC0DE
		var play_seed := _seed_value(i, salt + 211)

		seed(_seed_value(i, salt))
		var base_source := _new_match(config, first, {}, {}, emotion_seed)
		var base_sides: Dictionary = base_source.sides.duplicate(true)

		seed(_seed_value(i, salt + 31))
		var alt_you_source := _new_match(config, first, {}, {}, emotion_seed)
		var you_sides: Dictionary = base_sides.duplicate(true)
		you_sides[Rules.SIDE_YOU] = alt_you_source.sides[Rules.SIDE_YOU].duplicate(true)

		seed(_seed_value(i, salt + 47))
		var alt_opp_source := _new_match(config, first, {}, {}, emotion_seed)
		var opp_sides: Dictionary = base_sides.duplicate(true)
		opp_sides[Rules.SIDE_OPP] = alt_opp_source.sides[Rules.SIDE_OPP].duplicate(true)

		var baseline := _match_from_snapshot(config, first, base_sides,
			emotion_seed, _seed_value(i, salt + 501))
		seed(play_seed)
		var base_result: Dictionary = _ai.simulate(baseline, style_you, style_opp)
		var base_winner := String(base_result.get("winner", ""))
		var base_value := _outcome_value(base_winner)
		a_matches += 1
		a_score += 1.0 if base_winner == a_side else (0.5 if base_winner == "" else 0.0)

		var you_redraw := _match_from_snapshot(config, first, you_sides,
			emotion_seed, _seed_value(i, salt + 502))
		seed(play_seed)
		var you_result: Dictionary = _ai.simulate(you_redraw, style_you, style_opp)
		_collect_pair_values(out, base_value,
			_outcome_value(String(you_result.get("winner", ""))))

		var opp_redraw := _match_from_snapshot(config, first, opp_sides,
			emotion_seed, _seed_value(i, salt + 503))
		seed(play_seed)
		var opp_result: Dictionary = _ai.simulate(opp_redraw, style_you, style_opp)
		_collect_pair_values(out, base_value,
			_outcome_value(String(opp_result.get("winner", ""))))
	out["a_winrate"] = 50.0 if a_matches == 0 else a_score / float(a_matches) * 100.0
	return out


## Сколько матчей нужно, чтобы двусторонний 95%-тест отличил сильную политику от слабой.
func _format_detect(winrate_pct: float) -> String:
	var edge: float = absf(winrate_pct - 50.0) / 100.0
	if edge < 0.005:
		return "не отличима"
	var n: float = pow(0.98 / edge, 2.0)
	if n > 99999.0:
		return "> 99 999"
	return "%d" % int(round(n))


## Прогоняет обычное зеркало основной политики и на каждом её ходе спрашивает, что
## выбрала бы эталонная. Тень не влияет на матч: сравниваются только решения.
func _run_shadow_agreement(config: Dictionary, style: String, shadow: String,
		matches: int, salt: int) -> Dictionary:
	_ai.reset_shadow(Rules.SIDE_YOU, shadow)
	for i in matches:
		_seed_for(i, salt)
		var first := Rules.SIDE_YOU if i % 2 == 0 else Rules.SIDE_OPP
		var m := _new_match(config, first, {}, {}, _seed_value(i, salt) ^ 0x5EEDC0DE)
		_ai.simulate(m, style, style)
	var out := {
		"total": _ai.shadow_total,
		"same_type": _ai.shadow_same_type,
		"same_full": _ai.shadow_same_full,
	}
	_ai.reset_shadow("", "")
	return out


# --------------------------------------- exact-action agency diagnostics ---

## Не новая механика, а диагностический runner production-контракта. Baseline играет
## детерминированный verdict_reserve, но в каждой точке перечисляются ФИЗИЧЕСКИЕ
## альтернативы: exact hand_index × target; в клинче — pass + exact legal card.
## Каждая альтернатива ветвится ровно один раз, затем обе стороны снова следуют baseline.
func _agency_actions_suite() -> void:
	var quick := OS.get_cmdline_user_args().has("--quick")
	var matches := 8 if quick else 250
	if OS.get_cmdline_user_args().has("--long") and not quick:
		matches = 500
	var production := _candidate_config("agency_actions_production", true, true, true)
	var aggregate := {
		"all": _blank_agency_row(),
		"main": _blank_agency_row(),
		"clinch": _blank_agency_row(),
		"thirds": [_blank_agency_row(), _blank_agency_row(), _blank_agency_row()],
		"matches": 0,
		"baseline_replay_mismatch": 0,
		"branch_prefix_mismatch": 0,
		"invalid_branches": 0,
		"guard_hits": 0,
	}

	print("Production: U3/T8/R9, H5=1 reserve U+4, K2, B=3Р+1Т, snapshot KO,")
	print("Audience gate 2/4, emotion cards, A3/combo payoff; policy=verdict_reserve.")
	print("Каждый branch стартует из одного initial snapshot. Перед ordinal N обе RNG-ветки")
	print("получают hash(match_seed, N): branch не наследует случайный сдвиг прошлого выбора.")
	print("quick=%s, initial snapshots=%d.\n" % [str(quick), matches])

	var symmetry := _agency_canon_symmetry_invariant(production, quick)
	print("--- 0. PRODUCTION SETUP / SYMMETRY INVARIANT ---")
	print("canon override mirror: YOU %.1f%%, first %.1f%%; materialized Bases: %s; n=%d" % [
		float(symmetry.you_rate), float(symmetry.first_rate),
		"OK" if bool(symmetry.materialized) else "FAIL", int(symmetry.matches)])
	if not bool(symmetry.ok):
		_failures += 1
		print("FAIL: canon-vs-canon вышел за широкий симметрийный коридор 35–65%%.")
	print("")

	for i in matches:
		var first := Rules.SIDE_YOU if i % 2 == 0 else Rules.SIDE_OPP
		var deck_seed := _seed_value(i, 6100)
		var emotion_seed := _seed_value(i, 6111) ^ 0x5EEDC0DE
		var setup_seed := _seed_value(i, 6122)
		var run_seed := _seed_value(i, 6133)
		seed(deck_seed)
		var source := _new_match(production, first, {}, {}, emotion_seed)
		var initial_sides: Dictionary = source.sides.duplicate(true)

		var baseline := _agency_run(production, first, initial_sides, emotion_seed,
			setup_seed, run_seed)
		var replay := _agency_run(production, first, initial_sides, emotion_seed,
			setup_seed, run_seed)
		aggregate.matches += 1
		if String(baseline.signature) != String(replay.signature):
			aggregate.baseline_replay_mismatch += 1
		if bool(baseline.guard_hit) or bool(replay.guard_hit):
			aggregate.guard_hits += 1
		var baseline_value := _outcome_value(String(baseline.winner))
		var nodes: Array = baseline.nodes
		var total_nodes := nodes.size()
		for ni in total_nodes:
			var node: Dictionary = nodes[ni]
			node["third"] = mini(2, int(float(ni) * 3.0 / float(maxi(1, total_nodes))))
			node["winner_sensitive"] = false
			node["tested_alternatives"] = 0
			node["changed_alternatives"] = 0
			node["strict_flips"] = 0
			node["both_decisive"] = 0
			var selected_key := String(node.selected_key)
			for option_value in node.options:
				var option: Dictionary = option_value
				var alternative_key := String(option.key)
				if alternative_key == selected_key:
					continue
				var branch := _agency_run(production, first, initial_sides, emotion_seed,
					setup_seed, run_seed, baseline.script, ni, alternative_key)
				if bool(branch.prefix_mismatch):
					aggregate.branch_prefix_mismatch += 1
					continue
				if bool(branch.invalid):
					aggregate.invalid_branches += 1
					continue
				if bool(branch.guard_hit):
					aggregate.guard_hits += 1
				var branch_value := _outcome_value(String(branch.winner))
				node.tested_alternatives += 1
				if branch_value != baseline_value:
					node.winner_sensitive = true
					node.changed_alternatives += 1
				if baseline_value != 0 and branch_value != 0:
					node.both_decisive += 1
					if baseline_value == -branch_value:
						node.strict_flips += 1
			_agency_collect_node(aggregate.all, node)
			_agency_collect_node(aggregate[String(node.phase)], node)
			_agency_collect_node(aggregate.thirds[int(node.third)], node)

	print("--- A. ГДЕ ВООБЩЕ ЕСТЬ ВЫБОР ---")
	print("%-12s | nodes | 1 option | >=2 options | winner-sensitive | alt verdict Δ | strict flip/all | strict/decisive" % "срез")
	_print_agency_row("все", aggregate.all)
	_print_agency_row("main", aggregate.main)
	_print_agency_row("clinch", aggregate.clinch)
	print("")

	print("--- B. ПО ТРЕТЯМ BASELINE DECISION ORDINAL ---")
	for ti in 3:
		_print_agency_row(["первая", "средняя", "финальная"][ti],
			aggregate.thirds[ti])
	print("")

	print("--- C. REPLAY / BRANCH INVARIANTS ---")
	print("baseline replay mismatch: %d/%d; prefix mismatch: %d; invalid branches: %d; guard hits: %d" % [
		int(aggregate.baseline_replay_mismatch), int(aggregate.matches),
		int(aggregate.branch_prefix_mismatch), int(aggregate.invalid_branches),
		int(aggregate.guard_hits)])
	if int(aggregate.baseline_replay_mismatch) > 0 \
			or int(aggregate.branch_prefix_mismatch) > 0 \
			or int(aggregate.invalid_branches) > 0 \
			or int(aggregate.guard_hits) > 0:
		_failures += 1
	print("winner-sensitive node = хотя бы одна exact альтернатива дала иной тернарный")
	print("вердикт; strict flip = YOU↔OPP, ничья не считается. Треть — ordinal baseline,")
	print("не нормализованная длительность counterfactual branch.")


func _blank_agency_row() -> Dictionary:
	return {
		"nodes": 0, "one_option": 0, "multi_option": 0,
		"winner_sensitive": 0, "alternatives": 0,
		"changed_alternatives": 0, "strict_flips": 0, "both_decisive": 0,
	}


func _agency_collect_node(row: Dictionary, node: Dictionary) -> void:
	row.nodes += 1
	if int((node.options as Array).size()) <= 1:
		row.one_option += 1
	else:
		row.multi_option += 1
	if bool(node.winner_sensitive):
		row.winner_sensitive += 1
	row.alternatives += int(node.tested_alternatives)
	row.changed_alternatives += int(node.changed_alternatives)
	row.strict_flips += int(node.strict_flips)
	row.both_decisive += int(node.both_decisive)


func _print_agency_row(label: String, row: Dictionary) -> void:
	print("%-12s | %5d | %8.1f%% | %11.1f%% | %15.1f%% | %12.1f%% | %14.1f%% | %14.1f%%" % [
		label, int(row.nodes),
		_pct(int(row.one_option), int(row.nodes)),
		_pct(int(row.multi_option), int(row.nodes)),
		_pct(int(row.winner_sensitive), int(row.nodes)),
		_pct(int(row.changed_alternatives), int(row.alternatives)),
		_pct(int(row.strict_flips), int(row.alternatives)),
		_pct(int(row.strict_flips), int(row.both_decisive))])


## Полный exact-action match. replay_script форсирует только префикс ДО branch_ordinal;
## сама альтернатива задаётся branch_key, а после неё снова включается verdict_reserve.
func _agency_run(config: Dictionary, first: String, initial_sides: Dictionary,
		emotion_seed: int, setup_seed: int, run_seed: int,
		replay_script: Array = [], branch_ordinal: int = -1,
		branch_key: String = "") -> Dictionary:
	var m := _match_from_snapshot(config, first, initial_sides, emotion_seed, setup_seed)
	_ai.set_style(Rules.SIDE_YOU, "verdict_reserve")
	_ai.set_style(Rules.SIDE_OPP, "verdict_reserve")
	var nodes: Array = []
	var script: Array = []
	var signature_parts: Array = []
	var ordinal := 0
	var guard := 0
	var prefix_mismatch := false
	var invalid := false
	while not m.game_over and guard < 1200:
		guard += 1
		_agency_reseed(m, _agency_keyed_seed(run_seed, ordinal))
		if m.clinch_active():
			var clinch_options := _agency_clinch_options(m)
			var clinch_key := _agency_select_key(m, clinch_options, replay_script,
				branch_ordinal, branch_key, ordinal, true)
			if clinch_key == "" or not _agency_has_key(clinch_options, clinch_key):
				prefix_mismatch = ordinal < branch_ordinal
				invalid = not prefix_mismatch
				break
			var clinch_node := _agency_node(m, "clinch", ordinal, clinch_options,
				clinch_key)
			nodes.append(clinch_node)
			script.append(clinch_key)
			signature_parts.append("%s>%s" % [_agency_state_hash(m), clinch_key])
			var was_active: bool = bool(m.clinch_active())
			if not _agency_apply_option(m, _agency_option_for_key(clinch_options,
					clinch_key)):
				invalid = true
				break
			ordinal += 1
			if was_active and not m.clinch_active() and not m.game_over:
				m.advance()
			continue

		var status: String = m.begin_turn(m.current)
		if status == "ko" or status == "crowd" or status == "end" or status == "over":
			break
		var main_options := _agency_main_options(m, status)
		if main_options.is_empty():
			invalid = true
			break
		var main_key := _agency_select_key(m, main_options, replay_script,
			branch_ordinal, branch_key, ordinal, false)
		if main_key == "" or not _agency_has_key(main_options, main_key):
			prefix_mismatch = ordinal < branch_ordinal
			invalid = not prefix_mismatch
			break
		var main_node := _agency_node(m, "main", ordinal, main_options, main_key)
		nodes.append(main_node)
		script.append(main_key)
		signature_parts.append("%s>%s" % [_agency_state_hash(m), main_key])
		var selected := _agency_option_for_key(main_options, main_key)
		if not _agency_apply_option(m, selected):
			invalid = true
			break
		ordinal += 1
		if String(selected.kind) == "open_clinch":
			if not m.clinch_active() and not m.game_over:
				invalid = true
				break
		elif not m.game_over:
			m.advance()
	if not m.game_over:
		m._end_by_decision()
	var guard_hit := guard >= 1200
	signature_parts.append("%s|%s|%s" % [
		_agency_state_hash(m), String(m.winner), String(m.end_reason)])
	return {
		"winner": String(m.winner), "reason": String(m.end_reason),
		"nodes": nodes, "script": script,
		"signature": "#".join(signature_parts),
		"prefix_mismatch": prefix_mismatch, "invalid": invalid,
		"guard_hit": guard_hit,
	}


func _agency_node(m: RefCounted, phase: String, ordinal: int,
		options: Array, selected_key: String) -> Dictionary:
	return {
		"phase": phase, "ordinal": ordinal,
		"side": String(m.clinch_pending_side()) if phase == "clinch" else String(m.current),
		"options": options.duplicate(true), "selected_key": selected_key,
	}


func _agency_main_options(m: RefCounted, status: String) -> Array:
	var out: Array = []
	var side := String(m.current)
	if status == "pass":
		out.append(_agency_option("turn_pass", "", -1, -1, {}))
		return out
	if status == "reframe":
		for hand_index in m.recovery_indices(side):
			var recovery_card: Dictionary = m.sides[side].hand[int(hand_index)]
			out.append(_agency_option("reframe", Rules.TYPE_USTANOVKA,
				int(hand_index), -1, recovery_card))
		return out
	var legal: Array = m.legal_types(side)
	var hand: Array = m.sides[side].hand
	var opp_lines: Array = m.sides[m.other(side)].lines
	for hand_index in hand.size():
		var card: Dictionary = hand[hand_index]
		var type := String(card.get("type", ""))
		if not legal.has(type):
			continue
		var named_id := String(card.get("named", ""))
		if type == Rules.TYPE_RAZBOR:
			for target in opp_lines.size():
				var kind := "main"
				if bool(m.clinch_enabled):
					kind = "open_clinch" if named_id == "" \
						or bool(card.get("clinch", false)) else "named"
				elif named_id != "":
					kind = "named"
				out.append(_agency_option(kind, type, hand_index, target, card))
		else:
			var kind := "named" if named_id != "" else "main"
			out.append(_agency_option(kind, type, hand_index, -1, card))
	return out


func _agency_clinch_options(m: RefCounted) -> Array:
	var out: Array = [_agency_option("clinch_pass", "", -1, -1, {})]
	var side := String(m.clinch_pending_side())
	var phase := String(m.clinch.get("phase", ""))
	if not m.clinch_can_act(side):
		return out
	for hand_index in m.clinch_legal_indices(side, phase):
		var card: Dictionary = m.sides[side].hand[int(hand_index)]
		out.append(_agency_option("clinch_play", String(card.get("type", "")),
			int(hand_index), -1, card))
	return out


func _agency_option(kind: String, type: String, hand_index: int,
		target: int, card: Dictionary) -> Dictionary:
	var card_copy := card.duplicate(true)
	var key := "%s|%s|%d|%d|%s" % [
		kind, type, hand_index, target, _agency_card_key(card_copy)]
	return {
		"kind": kind, "type": type, "hand_index": hand_index,
		"target": target, "card": card_copy, "key": key,
	}


func _agency_select_key(m: RefCounted, options: Array, replay_script: Array,
		branch_ordinal: int, branch_key: String, ordinal: int,
		in_clinch: bool) -> String:
	if branch_ordinal >= 0 and ordinal < branch_ordinal:
		if ordinal >= replay_script.size():
			return ""
		return String(replay_script[ordinal])
	if branch_ordinal >= 0 and ordinal == branch_ordinal:
		return branch_key
	return _agency_policy_clinch_key(m, options) if in_clinch \
		else _agency_policy_main_key(m, options)


func _agency_policy_main_key(m: RefCounted, options: Array) -> String:
	if options.size() == 1:
		return String((options[0] as Dictionary).key)
	if String((options[0] as Dictionary).kind) == "reframe":
		return String((options[0] as Dictionary).key)
	var side := String(m.current)
	var act: Dictionary = _ai.pick(m, side, "verdict_reserve")
	if act.is_empty():
		return ""
	var type := String(act.get("type", ""))
	var target := int(act.get("target", -1))
	var named_index := int(act.get("named_index", -1))
	if named_index >= 0:
		var named_kind := "open_clinch" if bool(act.get("named_clinch", false)) else "named"
		for option_value in options:
			var option: Dictionary = option_value
			if String(option.kind) == named_kind and int(option.hand_index) == named_index \
					and (target < 0 or int(option.target) == target):
				return String(option.key)
	var candidates: Array = []
	for option_value in options:
		var option: Dictionary = option_value
		if String(option.type) != type:
			continue
		if target >= 0 and int(option.target) != target:
			continue
		if String((option.card as Dictionary).get("named", "")) != "":
			continue
		candidates.append(option)
	if candidates.is_empty():
		for option_value in options:
			var option: Dictionary = option_value
			if String(option.type) == type and (target < 0 or int(option.target) == target):
				candidates.append(option)
	if candidates.is_empty():
		return ""
	if type == Rules.TYPE_RAZBOR:
		var prefer: bool = bool(_ai.atk_prefer_steal(m, side, m.other(side),
			int((candidates[0] as Dictionary).target)))
		for option_value in candidates:
			var option: Dictionary = option_value
			if bool((option.card as Dictionary).get("steals", false)) == prefer:
				return String(option.key)
	return String((candidates[0] as Dictionary).key)


func _agency_policy_clinch_key(m: RefCounted, options: Array) -> String:
	var pass_key := String((options[0] as Dictionary).key)
	if options.size() <= 1:
		return pass_key
	var side := String(m.clinch_pending_side())
	var attacker := String(m.clinch.get("attacker", ""))
	var defender := String(m.clinch.get("defender", ""))
	var idx := int(m.clinch.get("idx", -1))
	if idx < 0 or idx >= m.sides[defender].lines.size():
		return pass_key
	var line: Dictionary = m.sides[defender].lines[idx]
	var play: bool = bool(_ai.def_will_clinch(m, side, line) if side == defender \
		else _ai.atk_will_clinch(m, side, line))
	if not play:
		return pass_key
	if side == defender:
		var answer_index := int(_ai.def_answer_index(m, side))
		if answer_index >= 0:
			for option_value in options:
				var option: Dictionary = option_value
				if int(option.hand_index) == answer_index:
					return String(option.key)
	else:
		var prefer: bool = bool(_ai.atk_prefer_steal(m, attacker, defender, idx))
		for option_value in options:
			var option: Dictionary = option_value
			if String(option.kind) == "clinch_play" \
					and bool((option.card as Dictionary).get("steals", false)) == prefer:
				return String(option.key)
	for option_value in options:
		var option: Dictionary = option_value
		if String(option.kind) == "clinch_play":
			return String(option.key)
	return pass_key


func _agency_apply_option(m: RefCounted, option: Dictionary) -> bool:
	var kind := String(option.kind)
	var side := String(m.clinch_pending_side()) if kind.begins_with("clinch_") \
		else String(m.current)
	match kind:
		"turn_pass":
			return true
		"reframe":
			return not m.play_redeploy(side, int(option.hand_index)).is_empty()
		"main":
			return not m.play_action(side, String(option.type), int(option.target),
				int(option.hand_index)).is_empty()
		"named":
			return not m.play_named(side, int(option.hand_index),
				int(option.target)).is_empty()
		"open_clinch":
			var card: Dictionary = option.card
			return not m.begin_clinch(side, m.other(side), int(option.target),
				bool(card.get("steals", false)), int(option.hand_index)).is_empty()
		"clinch_pass":
			return not m.clinch_submit("pass").is_empty()
		"clinch_play":
			var card: Dictionary = option.card
			return not m.clinch_submit("play", bool(card.get("steals", false)),
				int(option.hand_index)).is_empty()
	return false


func _agency_has_key(options: Array, key: String) -> bool:
	for option_value in options:
		if String((option_value as Dictionary).key) == key:
			return true
	return false


func _agency_option_for_key(options: Array, key: String) -> Dictionary:
	for option_value in options:
		var option: Dictionary = option_value
		if String(option.key) == key:
			return option
	return {}


func _agency_reseed(m: RefCounted, seed_value: int) -> void:
	if m.has_method("agency_reseed"):
		m.agency_reseed(seed_value)
	else:
		seed(seed_value)


func _agency_keyed_seed(run_seed: int, ordinal: int) -> int:
	var value: int = (run_seed ^ (ordinal + 1) * 0x9E3779B1) & 0x7FFFFFFF
	value = (((value >> 16) ^ value) * 0x45D9F3B) & 0x7FFFFFFF
	value = (((value >> 16) ^ value) * 0x45D9F3B) & 0x7FFFFFFF
	return ((value >> 16) ^ value) & 0x7FFFFFFF


func _agency_state_hash(m: RefCounted) -> String:
	var state := {
		"current": String(m.current), "turn": int(m.turn_count),
		"game_over": bool(m.game_over), "winner": String(m.winner),
		"reason": String(m.end_reason), "hall": int(m.hall), "heat": int(m.heat),
		"captures": int(m.captures), "capture_theses": int(m.capture_theses),
		"crowd_streak": m.crowd_streak.duplicate(true),
		"named_played": m.named_played.duplicate(true),
		"sides": m.sides.duplicate(true), "clinch": m.clinch.duplicate(true),
		"emotion_you": m.emotion_state(Rules.SIDE_YOU).duplicate(true),
		"emotion_opp": m.emotion_state(Rules.SIDE_OPP).duplicate(true),
		"serials": [
			int(m.get("_thesis_serial")), int(m.get("_frame_serial")),
			int(m.get("_action_serial")), int(m.get("_play_serial")),
			int(m.get("_relation_serial")),
		],
	}
	return str(hash(JSON.stringify(state)))


func _agency_card_key(card: Dictionary) -> String:
	if card.is_empty():
		return "-"
	return "%s/%s/%s/%s/%s/%s/%s/%s" % [
		String(card.get("type", "")), String(card.get("name", "")),
		String(card.get("named", "")), str(bool(card.get("steals", false))),
		String(card.get("scheme", "")), String(card.get("suit", "")),
		String(card.get("hook", "")), String(card.get("claim_id", "")),
	]


## Regression для найденного setup-bug: custom deck override обязан получить exact
## стартовый thesis object ДО opening reserve. Широкий 35–65% коридор ловит прежние
## ~75%, но не превращает небольшой quick в статистический баланс-сертификат.
func _agency_canon_symmetry_invariant(config: Dictionary, quick: bool) -> Dictionary:
	var canon := {"u": U, "t": T, "r": R, "steals": STEAL}
	var materialized := true
	seed(_seed_value(0, 6200))
	var probe := _new_match(config, Rules.SIDE_YOU, canon, canon,
		_seed_value(0, 6201) ^ 0x5EEDC0DE)
	for side in [Rules.SIDE_YOU, Rules.SIDE_OPP]:
		var lines: Array = probe.sides[side].lines
		if lines.is_empty() or (lines[0] as Dictionary).get("thesis_stack", []).size() != BASE:
			materialized = false
	var n := 120 if quick else 400
	var mirror := _run_candidate_cell(config, "verdict_reserve", "verdict_reserve",
		n, canon, canon, 6210)
	var decisive := int(mirror.wins_you) + int(mirror.wins_opp)
	var you_rate := _pct(int(mirror.wins_you), decisive)
	var first_rate := _pct(int(mirror.first_wins), int(mirror.decisive))
	return {
		"matches": n, "materialized": materialized,
		"you_rate": you_rate, "first_rate": first_rate,
		"ok": materialized and you_rate >= 35.0 and you_rate <= 65.0 \
			and first_rate >= 35.0 and first_rate <= 65.0,
	}
