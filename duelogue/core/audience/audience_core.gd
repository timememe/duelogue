extends RefCounted

## Независимая короткая память аудитории.
## Не знает о картах, доске, победителе матча, UI или async. Получает уже осмысленные сцены.

var mode := "pendulum"
var lean := 0                    ## + в пользу YOU
var heat := 0
var lean_cap := 5
var heat_max := 3
var decision_threshold := 1
var valence_mode := "content_plus_conduct"

## Новый контракт: содержание и публичное поведение дают два независимых голоса.
var conduct_cap := 2
var surge_threshold := 3
var surge_alignment_min := 2
var surge_amplitude := 2
var surge_reset := 1

## Тихое охлаждение считается действиями: два тихих действия = один тихий раунд.
var quiet_cool := 1
var quiet_actions := 2
var lean_friction := 0

## Поля старого режима оставлены для сравнительного профиля vector_reaction.
var spectacle_threshold := 2
var heat_amplifies := true

var reaction_values := {}
var parry_value := 1
var moves := 0
var reversals := 0
var last_scene := {}
var _quiet_progress := 0
var _last_sign := 0


func reset(config: Dictionary = {}) -> void:
	mode = String(config.get("mode", "pendulum"))
	lean_cap = maxi(1, int(config.get("lean_cap", 5)))
	heat_max = maxi(0, int(config.get("heat_max", 3)))
	decision_threshold = maxi(1, int(config.get("decision_threshold", 1)))
	valence_mode = String(config.get("valence_mode", "content_plus_conduct"))
	conduct_cap = maxi(0, int(config.get("conduct_cap", 2)))
	surge_threshold = maxi(0, int(config.get("surge_threshold", 3)))
	surge_alignment_min = maxi(1, int(config.get("surge_alignment_min", 2)))
	surge_amplitude = maxi(1, int(config.get("surge_amplitude", 2)))
	surge_reset = clampi(int(config.get("surge_reset", 1)), 0, heat_max)
	quiet_cool = maxi(0, int(config.get("quiet_cool", 1)))
	quiet_actions = maxi(1, int(config.get("quiet_actions", 2)))
	lean_friction = maxi(0, int(config.get("lean_friction", 0)))
	spectacle_threshold = maxi(1, int(config.get("spectacle_threshold", 2)))
	heat_amplifies = bool(config.get("heat_amplifies", true))
	reaction_values = (config.get("reaction_values", {}) as Dictionary).duplicate(true)
	parry_value = int(config.get("parry_value", 1))
	lean = clampi(int(config.get("opening_lean", 0)), -lean_cap, lean_cap)
	heat = clampi(int(config.get("opening_heat", 0)), 0, heat_max)
	moves = 0
	reversals = 0
	last_scene = {}
	_quiet_progress = 0
	_last_sign = signi(lean)


func observe_quiet() -> Dictionary:
	if mode != "pendulum":
		return snapshot()
	_quiet_progress += 1
	if _quiet_progress >= quiet_actions:
		_quiet_progress = 0
		heat = maxi(0, heat - quiet_cool)
		_set_lean(_toward_zero(lean, lean_friction))
	return snapshot()


## content_side — победитель содержательной сцены ("you"/"opp"/"").
## content_strength — сила содержательного голоса, conduct_delta уже ориентирован на YOU.
## heat_gain нагревает только следующую сцену: текущая сцена читает Heat до своего события.
func resolve_scene(content_side: String, content_strength: int = 0, conduct_delta: int = 0,
	heat_gain: int = 0, reaction_seen: bool = false) -> Dictionary:
	if mode != "pendulum":
		return snapshot()
	_quiet_progress = 0
	var heat_before := heat
	if valence_mode == "content_plus_conduct":
		_resolve_content_plus_conduct(content_side, content_strength, conduct_delta,
			heat_gain, reaction_seen, heat_before)
	else:
		_resolve_legacy_scene(content_side, content_strength, conduct_delta, heat_gain,
			reaction_seen, heat_before)
	return snapshot()


func reaction_value(reaction_id: String, stimulus: String = "") -> int:
	var configured: Variant = reaction_values.get(reaction_id,
		reaction_values.get("default", 0))
	if configured is Dictionary:
		var by_stimulus := configured as Dictionary
		return int(by_stimulus.get(stimulus, by_stimulus.get("default", 0)))
	return int(configured)


func signed_reaction(side: String, reaction_id: String, stimulus: String = "") -> int:
	var relative := reaction_value(reaction_id, stimulus)
	return relative if side == "you" else -relative


func signed_parry(side: String) -> int:
	return parry_value if side == "you" else -parry_value


func snapshot(bias: int = 0) -> Dictionary:
	var effective_lean := clampi(lean + bias, -lean_cap, lean_cap)
	return {
		"mode": mode,
		"lean": effective_lean,
		"raw_lean": lean,
		"bias": bias,
		"lean_cap": lean_cap,
		"decision_threshold": decision_threshold,
		"heat": heat,
		"heat_max": heat_max,
		"quiet_progress": _quiet_progress,
		"quiet_actions": quiet_actions,
		"moves": moves,
		"reversals": reversals,
		"last_scene": last_scene.duplicate(true),
	}


func _resolve_content_plus_conduct(content_side: String, content_strength: int,
	conduct_delta: int, heat_gain: int, reaction_seen: bool, heat_before: int) -> void:
	var content_delta := _side_sign(content_side) * maxi(0, content_strength)
	var conduct_applied := clampi(conduct_delta, -conduct_cap, conduct_cap)
	var total := content_delta + conduct_applied
	var direction := signi(total)
	var votes_aligned := content_delta != 0 and conduct_applied != 0 \
		and signi(content_delta) == signi(conduct_applied)
	var surged := heat_before >= surge_threshold and votes_aligned \
		and absi(total) >= surge_alignment_min
	var amplitude := surge_amplitude if surged else 1
	if surged:
		heat = surge_reset
	else:
		heat = clampi(heat_before + heat_gain, 0, heat_max)
	var relaxed := _toward_zero(lean, lean_friction)
	var impulse := direction * amplitude
	_set_lean(clampi(relaxed + impulse, -lean_cap, lean_cap))
	last_scene = _scene_breakdown(content_side, content_strength, content_delta, conduct_delta,
		conduct_applied, total, direction, amplitude, impulse, heat_before, heat_gain,
		votes_aligned, surged, reaction_seen)


## Сравнительный путь прежней модели: реакция способна заменить голос содержания,
## а Heat сначала растёт и затем усиливает ту же самую сцену.
func _resolve_legacy_scene(content_side: String, content_strength: int, conduct_delta: int,
	heat_gain: int, reaction_seen: bool, heat_before: int) -> void:
	var content_delta := 0
	# Новый controller уже решил, является ли исход публично значимым; >0 сохраняет
	# прежний голос сцены, не заставляя его повторно проходить старый spectacle-порог.
	if content_strength > 0:
		content_delta = _side_sign(content_side)
	var conduct_applied := conduct_delta
	var direction := content_delta
	match valence_mode:
		"reaction_priority":
			if reaction_seen and conduct_delta != 0:
				direction = signi(conduct_delta)
		"spectacle_only":
			direction = signi(content_delta + conduct_delta)
		"every_scene":
			direction = signi(_side_sign(content_side) + conduct_delta)
	heat = clampi(heat_before + heat_gain, 0, heat_max)
	var amplitude := 1 + heat if heat_amplifies else 1
	var relaxed := _toward_zero(lean, lean_friction)
	var impulse := direction * amplitude
	_set_lean(clampi(relaxed + impulse, -lean_cap, lean_cap))
	last_scene = _scene_breakdown(content_side, content_strength, content_delta, conduct_delta,
		conduct_applied, content_delta + conduct_applied, direction, amplitude, impulse,
		heat_before, heat_gain, false, false, reaction_seen)


func _scene_breakdown(content_side: String, content_strength: int, content_delta: int,
	conduct_delta: int, conduct_applied: int, total: int, direction: int, amplitude: int,
	impulse: int, heat_before: int, heat_gain: int, votes_aligned: bool,
	surged: bool, reaction_seen: bool) -> Dictionary:
	return {
		"content_side": content_side,
		"content_strength": content_strength,
		"content_delta": content_delta,
		"conduct_delta": conduct_delta,
		"conduct_applied": conduct_applied,
		"total": total,
		"direction": direction,
		"amplitude": amplitude,
		"impulse": impulse,
		"heat_before": heat_before,
		"heat_gain": heat_gain,
		"heat_after": heat,
		"votes_aligned": votes_aligned,
		"surged": surged,
		"reaction_seen": reaction_seen,
	}


func _set_lean(value: int) -> void:
	var before := lean
	lean = clampi(value, -lean_cap, lean_cap)
	if lean != before:
		moves += 1
	var next_sign := signi(lean)
	if next_sign != 0 and _last_sign != 0 and next_sign != _last_sign:
		reversals += 1
	if next_sign != 0:
		_last_sign = next_sign


func _side_sign(side: String) -> int:
	return 1 if side == "you" else (-1 if side == "opp" else 0)


func _toward_zero(value: int, step: int) -> int:
	if value > 0:
		return maxi(0, value - step)
	if value < 0:
		return mini(0, value + step)
	return 0
