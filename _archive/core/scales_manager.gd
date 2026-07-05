class_name ScalesManager
extends RefCounted

signal scales_changed(old_value: int, new_value: int)
signal point_scored(is_player: bool, new_points: int)

const SCALES_MAX := 3
const SCALES_MIN := -3

var scales: int = 0


## Apply damage to a stat. Returns overflow that goes to scales.
## is_player_target: true, если цель урона — игрок, тогда весы сдвигаются вниз.
## Also flags `knockdown` when stat transitions from >0 to <=0 in this hit —
## caller should reward a point via award_knockdown_point and reset the stat.
func apply_damage_with_scales(target: CharacterStats, stat_name: StringName, damage: int, is_player_target: bool) -> Dictionary:
	if damage <= 0:
		return {"actual_damage": 0, "overflow": 0, "scales_shift": 0, "knockdown": false}

	var current_hp: int = target.logic if stat_name == &"logic" else target.emotion
	var result := {"actual_damage": 0, "overflow": 0, "scales_shift": 0, "knockdown": false}

	if current_hp > 0:
		var actual := mini(damage, current_hp)
		var overflow := damage - actual
		target.apply_stat_change(stat_name, -actual)
		result.actual_damage = actual

		var new_hp: int = target.logic if stat_name == &"logic" else target.emotion
		if new_hp <= 0:
			result.knockdown = true

		if overflow > 0:
			result.overflow = overflow
			var shift := -overflow if is_player_target else overflow
			_shift_scales(shift)
			result.scales_shift = shift
	else:
		# HP already 0 or below, all damage goes to scales (no second knockdown)
		var shift := -damage if is_player_target else damage
		_shift_scales(shift)
		result.overflow = damage
		result.scales_shift = shift

	return result


## Awards a knockdown point to `scorer` and resets the depleted stat on `target`
## to its current max (respecting any event penalties). Emits point_scored.
func award_knockdown_point(scorer: CharacterStats, target: CharacterStats, scorer_is_player: bool, stat_name: StringName) -> void:
	scorer.points += 1
	if stat_name == &"logic":
		target.logic = target.max_logic
	elif stat_name == &"emotion":
		target.emotion = target.max_emotion
	point_scored.emit(scorer_is_player, scorer.points)


func check_points(player: CharacterStats, enemy: CharacterStats) -> bool:
	if scales >= SCALES_MAX:
		player.points += 1
		var old := scales
		scales = 0
		scales_changed.emit(old, 0)
		point_scored.emit(true, player.points)
		return true
	elif scales <= SCALES_MIN:
		enemy.points += 1
		var old := scales
		scales = 0
		scales_changed.emit(old, 0)
		point_scored.emit(false, enemy.points)
		return true
	return false


func check_victory(player: CharacterStats, enemy: CharacterStats) -> int:
	## Returns: 0 = no victory, 1 = player wins, -1 = enemy wins
	if player.points >= 3:
		return 1
	if enemy.points >= 3:
		return -1
	return 0


func reset() -> void:
	scales = 0


func set_scales(value: int) -> void:
	var old := scales
	scales = clampi(value, SCALES_MIN, SCALES_MAX)
	if old != scales:
		scales_changed.emit(old, scales)


func _shift_scales(amount: int) -> void:
	var old := scales
	scales = clampi(scales + amount, SCALES_MIN, SCALES_MAX)
	if old != scales:
		scales_changed.emit(old, scales)
