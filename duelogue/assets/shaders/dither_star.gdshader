shader_type canvas_item;

// DUELOGUE — ДИЗЕР-ЗВЕЗДА: та же звёздная SDF-форма (угол → cos(spikes·θ)^sharpness → граница
// inner..outer radius) и тот же приём дизер-края, что даёт звезде combo_name_banner.gd
// (BURST_SHADER_CODE, Bayer 4×4) — здесь вынесена в отдельный ассет, чтобы использовать тот же
// «взрыв боевого комбо» как декоративный фоновый элемент (главное меню, витрина бойцов), не
// дублируя шейдер-код второй строкой во втором скрипте.
// Вращение — НЕ uniform, а поворот самой ноды (rotation_degrees), как и у баннера комбо: UV
// остаётся в локальном пространстве ноды, поворот ноды крутит уже отрисованную форму целиком,
// дизер-зерно не «плывёт» по экрану отдельно от звезды.

uniform vec4 burst_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outer_radius : hint_range(0.0, 1.0) = 0.46;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.27;
uniform float spikes : hint_range(1.0, 40.0) = 15.0;
uniform float sharpness : hint_range(1.0, 20.0) = 5.0;
uniform float edge_fade : hint_range(0.001, 0.08) = 0.015;

// Bayer 4×4 (та же матрица, что в combo_name_banner.gd) — вынесена в const-массив, тем же
// приёмом, что BAYER8 в dither.gdshader/fire_aura.gdshader/mood_bg.gdshader.
const float BAYER4[16] = {
	 0.0,  8.0,  2.0, 10.0,
	12.0,  4.0, 14.0,  6.0,
	 3.0, 11.0,  1.0,  9.0,
	15.0,  7.0, 13.0,  5.0
};

float bayer4(vec2 pixel) {
	ivec2 p = ivec2(mod(floor(pixel), 4.0));
	return (BAYER4[p.y * 4 + p.x] + 0.5) / 16.0;
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
