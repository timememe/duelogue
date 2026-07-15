extends RefCounted

## Независимая короткая память аудитории.
## Не знает о картах, доске, победителе матча, UI или async. Получает уже осмысленные сцены.

var mode := "pendulum"
var lean := 0                    ## + в пользу YOU
var heat := 0
var lean_cap := 5
var heat_max := 3
var valence_mode := "reaction_priority"
var spectacle_threshold := 2
var quiet_cool := 1
var lean_friction := 0
var heat_amplifies := true
var reaction_values := {}
var parry_value := 1
var moves := 0
var reversals := 0
var _last_sign := 0


func reset(config: Dictionary = {}) -> void:
	mode = String(config.get("mode", "pendulum"))
	lean_cap = maxi(1, int(config.get("lean_cap", 5)))
	heat_max = maxi(0, int(config.get("heat_max", 3)))
	valence_mode = String(config.get("valence_mode", "reaction_priority"))
	spectacle_threshold = maxi(1, int(config.get("spectacle_threshold", 2)))
	quiet_cool = maxi(0, int(config.get("quiet_cool", 1)))
	lean_friction = maxi(0, int(config.get("lean_friction", 0)))
	heat_amplifies = bool(config.get("heat_amplifies", true))
	reaction_values = (config.get("reaction_values", {}) as Dictionary).duplicate(true)
	parry_value = int(config.get("parry_value", 1))
	lean = clampi(int(config.get("opening_lean", 0)), -lean_cap, lean_cap)
	heat = clampi(int(config.get("opening_heat", 0)), 0, heat_max)
	moves = 0
	reversals = 0
	_last_sign = signi(lean)


func observe_quiet() -> Dictionary:
	if mode != "pendulum":
		return snapshot()
	heat = maxi(0, heat - quiet_cool)
	_set_lean(_toward_zero(lean, lean_friction))
	return snapshot()


## public_side — победитель зрелищного исхода ("you"/"opp"/"").
## emotion_delta уже ориентирован на YOU; reaction_seen отличает тихую сцену от реакции 0.
func resolve_scene(public_side: String, spectacle: int, emotion_delta: int = 0,
	reaction_seen: bool = false) -> Dictionary:
	if mode != "pendulum":
		return snapshot()
	var public_delta := 0
	if spectacle >= spectacle_threshold:
		public_delta = 1 if public_side == "you" else (-1 if public_side == "opp" else 0)
	var valence := public_delta
	match valence_mode:
		"reaction_priority":
			if reaction_seen and emotion_delta != 0:
				valence = signi(emotion_delta)
		"spectacle_only":
			valence = signi(public_delta + emotion_delta)
		"every_scene":
			var scene_side := 1 if public_side == "you" else (-1 if public_side == "opp" else 0)
			valence = signi(scene_side + emotion_delta)
	heat = clampi(heat + spectacle - 1, 0, heat_max)
	var relaxed := _toward_zero(lean, lean_friction)
	var impulse := valence * (1 + heat if heat_amplifies else 1)
	_set_lean(clampi(relaxed + impulse, -lean_cap, lean_cap))
	return snapshot()


func reaction_value(reaction_id: String) -> int:
	return int(reaction_values.get(reaction_id, 0))


func signed_reaction(side: String, reaction_id: String) -> int:
	var relative := reaction_value(reaction_id)
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
		"heat": heat,
		"heat_max": heat_max,
		"moves": moves,
		"reversals": reversals,
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


func _toward_zero(value: int, step: int) -> int:
	if value > 0:
		return maxi(0, value - step)
	if value < 0:
		return mini(0, value + step)
	return 0
