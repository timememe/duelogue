class_name ScalesBar
extends Control

## Bidirectional bar visualizing the scales meter. Fills right (blue) when the
## player is ahead, left (red) when the opponent is. Tick marks for each step.
## Call set_scales(value, max_value) on change; widget redraws automatically.

const PLAYER_COLOR := Color(0.30, 0.62, 1.0)
const OPPONENT_COLOR := Color(1.0, 0.36, 0.36)
const TRACK_COLOR := Color(0.16, 0.17, 0.22)
const TRACK_BORDER := Color(0.42, 0.44, 0.52, 0.75)
const CENTER_COLOR := Color(0.92, 0.92, 0.95)
const TICK_COLOR := Color(0.55, 0.57, 0.65, 0.55)
const EDGE_GLOW := Color(1.0, 0.85, 0.32, 0.5) ## Tint when scales hit ±max (1 step from point)

var value: int = 0
var max_value: int = 3


func _ready() -> void:
	custom_minimum_size = Vector2(180, 22)


func set_scales(v: int, m: int = 3) -> void:
	value = clampi(v, -m, m)
	max_value = maxi(1, m)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var center_x := w * 0.5
	var half_w := w * 0.5

	# Track background
	draw_rect(Rect2(Vector2.ZERO, size), TRACK_COLOR, true)

	# Filled portion from center toward indicator
	if value > 0:
		var fill_w := (float(value) / max_value) * half_w
		var color := PLAYER_COLOR if value < max_value else PLAYER_COLOR.lerp(EDGE_GLOW, 0.45)
		draw_rect(Rect2(Vector2(center_x, 2), Vector2(fill_w, h - 4)), color, true)
	elif value < 0:
		var fill_w := (float(-value) / max_value) * half_w
		var color := OPPONENT_COLOR if -value < max_value else OPPONENT_COLOR.lerp(EDGE_GLOW, 0.45)
		draw_rect(Rect2(Vector2(center_x - fill_w, 2), Vector2(fill_w, h - 4)), color, true)

	# Tick marks at each integer level
	for i in range(-max_value, max_value + 1):
		if i == 0:
			continue
		var x: float = center_x + (float(i) / max_value) * half_w
		draw_line(Vector2(x, h * 0.68), Vector2(x, h - 2), TICK_COLOR, 1)

	# Center divider on top of fill
	draw_line(Vector2(center_x, 1), Vector2(center_x, h - 1), CENTER_COLOR, 2)

	# Border
	draw_rect(Rect2(Vector2.ZERO, size), TRACK_BORDER, false, 1)
