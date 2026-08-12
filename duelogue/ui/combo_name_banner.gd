extends Control

## DUELOGUE — БАННЕР НАЗВАНИЯ КОМБО (2026-07-23, Ace Attorney-стиль «OBJECTION!»). 2.06 секунды,
## ДО обычной сцены-реплики владельца (character_core секвенирует show_combo → show_utterance).
## Намеренно НЕ часть reaction_scene: это не реакция персонажа, а нейтральный эффект самой игры
## поверх всей сцены — доска/рука остаются видны вокруг вспышки.
##
## Нейминг (правка 2026-07-23, пользователь): ГАРД/ТРАП ничего не говорят о том, выиграл ли
## ИГРОК — цвет держится строго на стороне-победителе (зелёный "вы"/оранжевый "опп", те же
## тона, что у BarYouLabel/BarOppLabel в debate_screen.tscn), а не на архетипе паттерна. Кто
## победил не подписан текстом отдельно (правка 2026-07-23 #2) — цвет звезды уже читается
## однозначно, дублирующая подпись только шумит.
## Обе надписи набраны тем же Sofia Sans Condensed Black wght=900, что имя приёма в реакции;
## имя комбо всегда UPPERCASE, но в отличие от reaction-сцены текст баннера не наклоняется.
##
## Звезда — не Polygon2D (правка 2026-07-23 #2), а ColorRect с процедурным canvas_item-шейдером:
## звёздный SDF по углу (cos(spikes·θ) в степени sharpness) + дизер-край тем же приёмом Bayer4,
## что Shader_board_dither/Shader_hand_dither в debate_screen.tscn — тот же почерк проекта
## (aниме-стиль «ступенчатый дизер-край», см. память visual-style), просто применённый к звезде,
## а не к прямоугольнику/лучу.

const COMBO_FONT := preload("res://duelogue/assets/fonts/SofiaSansCondensed-Black.tres")

const YOU_COLOR := Color(0.4353, 0.8118, 0.498)   # тот же зелёный, что BarYouLabel
const OPP_COLOR := Color(0.851, 0.549, 0.298)     # тот же оранжевый, что BarOppLabel
const NAME_SIZE := Vector2(1000.0, 260.0)
const KICKER_SIZE := Vector2(900.0, 44.0)
const BURST_SIZE := Vector2(820.0, 820.0)

## Боевой канон и единый список ручек для combo_banner_lab.gd. Лаба мутирует настоящий
## ComboNameBanner через apply_tuning(), а «Скопировать» выдаёт эти же свойства.
const CANON_TUNING := {
	"burst_outer_frac": 0.395,
	"burst_inner_frac": 0.275,
	"burst_spikes": 6.0,
	"burst_sharpness": 5.8,
	"burst_edge_fade": 0.055,
	"burst_rotation_deg": 0.0,
	"back_layer_enabled": true,
	"back_layer_scale": 1.52,
	"back_layer_spikes": 16.0,
	"back_layer_sharpness": 3.6,
	"back_layer_rotation_offset_deg": 0.0,
	"back_layer_alpha": 0.75,
	"back_layer_tone": -0.18,
	"back_layer_offset": Vector2.ZERO,
	"anim_start_scale": 0.15,
	"anim_out_scale": 1.25,
	"anim_in_rotation_delta_deg": -18.0,
	"anim_out_rotation_delta_deg": 10.0,
	"anim_back_delay": 0.06,
	"anim_punch_in": 0.2,
	"anim_hold": 1.5,
	"anim_punch_out": 0.3,
}
const TUNING_KEYS := [
	"burst_outer_frac", "burst_inner_frac", "burst_spikes", "burst_sharpness",
	"burst_edge_fade", "burst_rotation_deg", "back_layer_enabled", "back_layer_scale",
	"back_layer_spikes", "back_layer_sharpness", "back_layer_rotation_offset_deg",
	"back_layer_alpha", "back_layer_tone", "back_layer_offset", "anim_start_scale",
	"anim_out_scale", "anim_in_rotation_delta_deg", "anim_out_rotation_delta_deg",
	"anim_back_delay", "anim_punch_in", "anim_hold", "anim_punch_out",
]

@export_group("Burst Shape")
@export_range(0.05, 0.75, 0.005) var burst_outer_frac := 0.395
@export_range(0.01, 0.70, 0.005) var burst_inner_frac := 0.275
@export_range(2.0, 40.0, 1.0) var burst_spikes := 6.0
@export_range(1.0, 20.0, 0.1) var burst_sharpness := 5.8
@export_range(0.001, 0.08, 0.001) var burst_edge_fade := 0.055
@export_range(-45.0, 45.0, 0.5) var burst_rotation_deg := 0.0

@export_group("Back Layer")
@export var back_layer_enabled := true
@export_range(0.5, 2.0, 0.01) var back_layer_scale := 1.52
@export_range(2.0, 40.0, 1.0) var back_layer_spikes := 16.0
@export_range(1.0, 20.0, 0.1) var back_layer_sharpness := 3.6
@export_range(-90.0, 90.0, 0.5) var back_layer_rotation_offset_deg := 0.0
@export_range(0.0, 1.0, 0.01) var back_layer_alpha := 0.75
@export_range(-1.0, 1.0, 0.01) var back_layer_tone := -0.18
@export var back_layer_offset := Vector2.ZERO

@export_group("Animation")
@export_range(0.01, 1.0, 0.01) var anim_start_scale := 0.15
@export_range(1.0, 2.0, 0.01) var anim_out_scale := 1.25
@export_range(-180.0, 180.0, 0.5) var anim_in_rotation_delta_deg := -18.0
@export_range(-180.0, 180.0, 0.5) var anim_out_rotation_delta_deg := 10.0
@export_range(0.0, 0.5, 0.01) var anim_back_delay := 0.06
@export_range(0.05, 1.0, 0.01) var anim_punch_in := 0.2
@export_range(0.0, 3.0, 0.05) var anim_hold := 1.5
@export_range(0.05, 1.0, 0.01) var anim_punch_out := 0.3

const BURST_SHADER_CODE := """
shader_type canvas_item;

uniform vec4 burst_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outer_radius : hint_range(0.0, 1.0) = 0.46;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.27;
uniform float spikes : hint_range(1.0, 40.0) = 15.0;
uniform float sharpness : hint_range(1.0, 20.0) = 5.0;
uniform float edge_fade : hint_range(0.001, 0.08) = 0.015;

float bayer4(vec2 pixel) {
	ivec2 p = ivec2(mod(floor(pixel), 4.0));
	float value = 0.0;
	if (p.y == 0) {
		value = p.x == 0 ? 0.0 : (p.x == 1 ? 8.0 : (p.x == 2 ? 2.0 : 10.0));
	} else if (p.y == 1) {
		value = p.x == 0 ? 12.0 : (p.x == 1 ? 4.0 : (p.x == 2 ? 14.0 : 6.0));
	} else if (p.y == 2) {
		value = p.x == 0 ? 3.0 : (p.x == 1 ? 11.0 : (p.x == 2 ? 1.0 : 9.0));
	} else {
		value = p.x == 0 ? 15.0 : (p.x == 1 ? 7.0 : (p.x == 2 ? 13.0 : 5.0));
	}
	return (value + 0.5) / 16.0;
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered);
	float angle = atan(centered.y, centered.x);
	float spike_wave = pow(abs(cos(angle * spikes * 0.5)), sharpness);
	float boundary = mix(inner_radius, outer_radius, spike_wave);
	float coverage = smoothstep(boundary + edge_fade, boundary - edge_fade, dist);
	float dither = step(bayer4(FRAGCOORD.xy / 2.0), coverage);
	COLOR = vec4(burst_color.rgb, burst_color.a * dither);
}
"""

var _burst_back: ColorRect
var _burst_back_mat: ShaderMaterial
var _burst: ColorRect
var _burst_mat: ShaderMaterial
var _kicker: Label   ## "КОМБО!" — над именем
var _label: Label    ## «Название комбо» — крупно, в центре
var _gen := 0  ## генерация; новый show_combo инвалидирует ожидающие await прошлого вызова
var _active_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_nodes()


func _ensure_nodes() -> void:
	if _burst != null:
		return
	var shader := Shader.new()
	shader.code = BURST_SHADER_CODE
	_burst_back_mat = ShaderMaterial.new()
	_burst_back_mat.shader = shader
	_burst_back = _make_burst(_burst_back_mat)
	_burst_mat = ShaderMaterial.new()
	_burst_mat.shader = shader
	_burst = _make_burst(_burst_mat)
	_kicker = _make_label(KICKER_SIZE, 28, Color.WHITE)
	_label = _make_label(NAME_SIZE, 68, Color.WHITE)
	_burst_back.visible = false
	_burst.visible = false
	_kicker.visible = false
	_label.visible = false
	_apply_shape_to_materials()


func _make_burst(mat: ShaderMaterial) -> ColorRect:
	var burst := ColorRect.new()
	burst.material = mat
	burst.size = BURST_SIZE
	burst.pivot_offset = BURST_SIZE / 2.0
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(burst)
	return burst


func _make_label(box_size: Vector2, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", COMBO_FONT)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size = box_size
	l.pivot_offset = box_size / 2.0
	l.rotation_degrees = 0.0
	add_child(l)
	return l


func tuning_snapshot() -> Dictionary:
	var result := {}
	for key: String in TUNING_KEYS:
		result[key] = get(key)
	return result


func apply_tuning(values: Dictionary) -> void:
	for key: String in TUNING_KEYS:
		if values.has(key):
			set(key, values[key])
	if _burst != null:
		_apply_shape_to_materials()


func _apply_shape_to_materials() -> void:
	_set_shape(_burst_mat, burst_spikes, burst_sharpness)
	_set_shape(_burst_back_mat, back_layer_spikes, back_layer_sharpness)


func _set_shape(mat: ShaderMaterial, spikes: float, sharpness: float) -> void:
	mat.set_shader_parameter("outer_radius", burst_outer_frac)
	mat.set_shader_parameter("inner_radius", minf(burst_inner_frac, burst_outer_frac - 0.005))
	mat.set_shader_parameter("spikes", spikes)
	mat.set_shader_parameter("sharpness", sharpness)
	mat.set_shader_parameter("edge_fade", burst_edge_fade)


func _back_color(front_color: Color) -> Color:
	var result := front_color.lightened(back_layer_tone) if back_layer_tone >= 0.0 \
		else front_color.darkened(-back_layer_tone)
	result.a = back_layer_alpha
	return result


func _layout_combo(combo_name: String, winner_side: String) -> void:
	_apply_shape_to_materials()
	var color := YOU_COLOR if winner_side == "you" else OPP_COLOR
	_burst_mat.set_shader_parameter("burst_color", color)
	_burst_back_mat.set_shader_parameter("burst_color", _back_color(color))
	var center := size / 2.0 - BURST_SIZE / 2.0
	_burst.position = center
	_burst.rotation_degrees = burst_rotation_deg
	_burst_back.position = center + back_layer_offset
	_burst_back.rotation_degrees = burst_rotation_deg + back_layer_rotation_offset_deg
	_kicker.text = "КОМБО!"
	_kicker.add_theme_color_override("font_color", color)
	_kicker.position = size / 2.0 + Vector2(-KICKER_SIZE.x / 2.0, -140.0)
	_label.text = combo_name.to_upper()
	_label.position = size / 2.0 - NAME_SIZE / 2.0
	_kicker.rotation_degrees = 0.0
	_label.rotation_degrees = 0.0


func _target_scale(node: Control) -> Vector2:
	return Vector2.ONE * back_layer_scale if node == _burst_back else Vector2.ONE


func _base_rotation(node: Control) -> float:
	if node == _burst:
		return burst_rotation_deg
	if node == _burst_back:
		return burst_rotation_deg + back_layer_rotation_offset_deg
	return 0.0


func _visible_nodes() -> Array[Control]:
	var nodes: Array[Control] = [_burst, _kicker, _label]
	if back_layer_enabled:
		nodes.push_front(_burst_back)
	return nodes


## Нетвиновое состояние для лаборатории: реальные материалы/слои/лейблы ComboNameBanner,
## но сразу в позе покоя. Любая шкала может перерисовать его без двухсекундного ожидания.
func show_static_preview(combo_name: String, winner_side: String) -> void:
	_ensure_nodes()
	_gen += 1
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	visible = true
	_layout_combo(combo_name, winner_side)
	_burst_back.visible = back_layer_enabled
	for node: Control in _visible_nodes():
		node.modulate.a = 1.0
		node.scale = _target_scale(node)
		node.rotation_degrees = _base_rotation(node)
		node.visible = true


func hide_preview() -> void:
	_gen += 1
	if _active_tween:
		_active_tween.kill()
		_active_tween = null
	for node in [_burst_back, _burst, _kicker, _label]:
		if node != null:
			node.visible = false
	visible = false


## Панч-ин с перелётом (TRANS_BACK/EASE_OUT) → пауза → панч-аут с фейдом. Боевые дефолты
## anim_back_delay/punch_in/hold/punch_out зеркалят ReadingPace.BANNER_* и дают 2.06 секунды;
## при переносе из лаборатории новых времён синхронизировать ReadingPace. winner_side —
## "you"/"opp": красит только звезду и кикер, без дублирующей подписи победителя.
func show_combo(combo_name: String, winner_side: String) -> void:
	_ensure_nodes()
	_gen += 1
	var my_gen := _gen
	if _active_tween:
		_active_tween.kill()
	visible = true
	_layout_combo(combo_name, winner_side)
	_burst_back.visible = back_layer_enabled
	var nodes := _visible_nodes()
	for node: Control in nodes:
		node.modulate.a = 1.0
		node.scale = _target_scale(node) * anim_start_scale
		node.rotation_degrees = _base_rotation(node)
		if node == _burst or node == _burst_back:
			node.rotation_degrees += anim_in_rotation_delta_deg
		node.visible = true
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	for node: Control in nodes:
		var delay := anim_back_delay if node == _burst_back else 0.0
		_active_tween.tween_property(node, "scale", _target_scale(node), anim_punch_in) \
			.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if node == _burst or node == _burst_back:
			_active_tween.tween_property(node, "rotation_degrees", _base_rotation(node),
				anim_punch_in).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await _active_tween.finished
	if my_gen != _gen:
		return
	await get_tree().create_timer(anim_hold).timeout
	if my_gen != _gen:
		return
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	for node: Control in nodes:
		_active_tween.tween_property(node, "scale", _target_scale(node) * anim_out_scale,
			anim_punch_out)
		_active_tween.tween_property(node, "modulate:a", 0.0, anim_punch_out)
		if node == _burst or node == _burst_back:
			_active_tween.tween_property(node, "rotation_degrees",
				_base_rotation(node) + anim_out_rotation_delta_deg, anim_punch_out)
	await _active_tween.finished
	if my_gen != _gen:
		return
	for node: Control in nodes:
		node.visible = false
	_burst_back.visible = false
	visible = false
