extends Control

## DUELOGUE — БАННЕР НАЗВАНИЯ КОМБО (2026-07-23, Ace Attorney-стиль «OBJECTION!»). 2 секунды,
## ДО обычной сцены-реплики владельца (character_core секвенирует show_combo → show_utterance).
## Намеренно НЕ часть reaction_scene: это не реакция персонажа, а нейтральный эффект самой игры
## поверх всей сцены — доска/рука остаются видны вокруг вспышки.
##
## Нейминг (правка 2026-07-23, пользователь): ГАРД/ТРАП ничего не говорят о том, выиграл ли
## ИГРОК — цвет держится строго на стороне-победителе (зелёный "вы"/оранжевый "опп", те же
## тона, что у BarYouLabel/BarOppLabel в debate_screen.tscn), а не на архетипе паттерна. Кто
## победил не подписан текстом отдельно (правка 2026-07-23 #2) — цвет звезды уже читается
## однозначно, дублирующая подпись только шумит.
##
## Звезда — не Polygon2D (правка 2026-07-23 #2), а ColorRect с процедурным canvas_item-шейдером:
## звёздный SDF по углу (cos(spikes·θ) в степени sharpness) + дизер-край тем же приёмом Bayer4,
## что Shader_board_dither/Shader_hand_dither в debate_screen.tscn — тот же почерк проекта
## (aниме-стиль «ступенчатый дизер-край», см. память visual-style), просто применённый к звезде,
## а не к прямоугольнику/лучу.

const ReadingPace := preload("res://duelogue/core/narrative/reading_pace.gd")

const YOU_COLOR := Color(0.4353, 0.8118, 0.498)   # тот же зелёный, что BarYouLabel
const OPP_COLOR := Color(0.851, 0.549, 0.298)     # тот же оранжевый, что BarOppLabel
const NAME_SIZE := Vector2(1000.0, 260.0)
const KICKER_SIZE := Vector2(900.0, 44.0)
const BURST_SIZE := Vector2(820.0, 820.0)
const BURST_OUTER_FRAC := 0.46   ## доля от половины BURST_SIZE — внешние шипы
const BURST_INNER_FRAC := 0.27   ## доля от половины BURST_SIZE — внутренние впадины
const BURST_SPIKES := 15.0
const BURST_SHARPNESS := 5.0     ## выше = уже шипы (ближе к звезде, дальше от «цветка»)
const BURST_EDGE_FADE := 0.015   ## ширина дизер-полосы в UV-долях

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

var _burst: ColorRect
var _burst_mat: ShaderMaterial
var _kicker: Label   ## "КОМБО СРАБОТАЛО!" — над именем
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
	_burst_mat = ShaderMaterial.new()
	_burst_mat.shader = shader
	_burst_mat.set_shader_parameter("outer_radius", BURST_OUTER_FRAC)
	_burst_mat.set_shader_parameter("inner_radius", BURST_INNER_FRAC)
	_burst_mat.set_shader_parameter("spikes", BURST_SPIKES)
	_burst_mat.set_shader_parameter("sharpness", BURST_SHARPNESS)
	_burst_mat.set_shader_parameter("edge_fade", BURST_EDGE_FADE)
	_burst = ColorRect.new()
	_burst.material = _burst_mat
	_burst.size = BURST_SIZE
	_burst.pivot_offset = BURST_SIZE / 2.0
	_burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_burst)
	_kicker = _make_label(KICKER_SIZE, 28, Color.WHITE)
	_label = _make_label(NAME_SIZE, 68, Color.WHITE)
	_burst.visible = false
	_kicker.visible = false
	_label.visible = false


func _make_label(box_size: Vector2, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size = box_size
	l.pivot_offset = box_size / 2.0
	add_child(l)
	return l


## Панч-ин с перелётом (TRANS_BACK/EASE_OUT) → пауза → панч-аут с фейдом. 2 секунды суммарно
## (ReadingPace.BANNER_*). winner_side — "you"/"opp": красит только звезду и кикер — победитель
## читается по цвету, отдельная подпись «ПОБЕДИТЕЛЬ: …» больше не дублирует то же самое.
func show_combo(combo_name: String, winner_side: String) -> void:
	_ensure_nodes()
	_gen += 1
	var my_gen := _gen
	visible = true
	var color := YOU_COLOR if winner_side == "you" else OPP_COLOR
	_burst_mat.set_shader_parameter("burst_color", color)
	_burst.position = size / 2.0 - BURST_SIZE / 2.0
	_burst.rotation = deg_to_rad(-6.0)
	_kicker.text = "КОМБО СРАБОТАЛО!"
	_kicker.add_theme_color_override("font_color", color)
	_kicker.position = size / 2.0 + Vector2(-KICKER_SIZE.x / 2.0, -140.0)
	_label.text = combo_name
	_label.position = size / 2.0 - NAME_SIZE / 2.0
	for n in [_burst, _kicker, _label]:
		n.modulate.a = 1.0
		n.scale = Vector2(0.15, 0.15)
		n.visible = true
	if _active_tween:
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	for n in [_burst, _kicker, _label]:
		_active_tween.tween_property(n, "scale", Vector2.ONE, ReadingPace.BANNER_PUNCH_IN) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await _active_tween.finished
	if my_gen != _gen:
		return
	await get_tree().create_timer(ReadingPace.BANNER_HOLD).timeout
	if my_gen != _gen:
		return
	_active_tween = create_tween()
	_active_tween.set_parallel(true)
	for n in [_burst, _kicker, _label]:
		_active_tween.tween_property(n, "scale", Vector2(1.25, 1.25), ReadingPace.BANNER_PUNCH_OUT)
		_active_tween.tween_property(n, "modulate:a", 0.0, ReadingPace.BANNER_PUNCH_OUT)
	await _active_tween.finished
	if my_gen != _gen:
		return
	for n in [_burst, _kicker, _label]:
		n.visible = false
	visible = false
