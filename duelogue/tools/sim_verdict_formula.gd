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
			hand_index: int = -1) -> Dictionary:
		var attacker := String(clinch.get("attacker", ""))
		var defender := String(clinch.get("defender", ""))
		var was_press := decision == "play" and String(clinch.get("phase", "")) == "await_attack"
		var result: Dictionary = super.clinch_submit(decision, prefer_steal, hand_index)
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
	func _finish_clinch() -> Dictionary:
		var result: Dictionary = super._finish_clinch()
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
		if emotion != null:
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


## Сим-бот, осведомлённый о новой целевой функции 3Р+1Т+1З. Это НЕ production-ai:
## нужен, чтобы старая эвристика «ширина сначала» не подменяла тест нового вердикта.
class VerdictAi extends "res://duelogue/core/ai/ai.gd":
	const STYLE_VERDICT := "verdict"
	const STYLE_VERDICT_5 := "verdict5"
	const STYLE_VERDICT_9 := "verdict9"
	const STYLE_VERDICT_CALM := "verdict_calm"
	const STYLE_VERDICT_PROVOKE := "verdict_provoke"
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
		if String(style_of.get(attacker, "")) == STYLE_VERDICT_PROVOKE \
				and _v_strain(r, r.other(attacker)) >= 4:
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
			or style == STYLE_VERDICT_CALM or style == STYLE_VERDICT_PROVOKE

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
			_:
				return false


func _ready() -> void:
	_ai = VerdictAi.new()
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
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
		var fm := FormulaRules.new()
		fm.hall_cap = int(config.cap)
		fm.frame_weight = int(config.wf)
		fm.thesis_weight = int(config.wt)
		fm.hall_weight = int(config.wz)
		var gate_x := int(config.get("gate_x", GATE_X))
		var gate_y := int(config.get("gate_y", GATE_Y))
		fm.reset(first, U, T, R, HAND, BASE, KOMI, STEAL, FORT,
			CLINCH, FREEZE, CAPTURE, gate_x, gate_y, SW, LOOT, 0, 1)
		fm.configure_emotion(String(config.get("emotion_mode", "none")), emotion_seed,
			int(config.get("hall_per_clinch", 1)), int(config.get("scene_cap", 2)),
			String(config.get("pressure_mode", "each_pair")))
		fm.configure_crowd(config)
		var opening_hall := int(config.get("opening_hall", 0))
		if opening_hall != 0:
			fm.hall = opening_hall if first == Rules.SIDE_YOU else -opening_hall
			fm.clean_hall = fm.hall
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
