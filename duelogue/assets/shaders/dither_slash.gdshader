shader_type canvas_item;

// DUELOGUE × «Персона-крой»: диагонально срезанная плашка (шеврон/параллелограмм внутри
// прямоугольного Control) — левый и правый край КАЖДЫЙ едут по X пропорционально (1-UV.y).
// skew_right=0 держит правый край вертикальным (классический «шеврон» с косым носом слева —
// командные полосы в духе Persona 3/4/5); skew_left=skew_right даёт настоящий параллелограмм
// (для отдельно стоящей плашки-акцента, не пришвартованной к краю контейнера).
// Заливка — НЕ флэт: два тона (accent_color у переднего/левого края шириной accent_width,
// дальше fill_color) квантованы тем же Байер 8×8 приёмом, что dither.gdshader/dither_star.gdshader
// — скринтон-зерно живёт на самой плашке, а не только маскирует антиалиас диагонального края
// (край СПЕЦИАЛЬНО остаётся резким/аliased — retro-графичный рез, тот же вкус, что и dither.gdshader
// не сглаживает свою дизер-границу).

uniform vec4 fill_color : source_color = vec4(0.07, 0.08, 0.11, 1.0);
uniform vec4 accent_color : source_color = vec4(0.25, 0.55, 1.0, 1.0);
uniform float skew_left : hint_range(-0.6, 0.6) = 0.14;
uniform float skew_right : hint_range(-0.6, 0.6) = 0.0;
uniform float accent_width : hint_range(0.0, 0.4) = 0.05;
uniform float color_levels : hint_range(2.0, 32.0) = 5.0;
uniform float dither_px : hint_range(1.0, 8.0) = 2.0;

// Классическая матрица Байера 8×8 — тот же const-массив, что в dither.gdshader.
const float BAYER8[64] = {
	 0.0, 32.0,  8.0, 40.0,  2.0, 34.0, 10.0, 42.0,
	48.0, 16.0, 56.0, 24.0, 50.0, 18.0, 58.0, 26.0,
	12.0, 44.0,  4.0, 36.0, 14.0, 46.0,  6.0, 38.0,
	60.0, 28.0, 52.0, 20.0, 62.0, 30.0, 54.0, 22.0,
	 3.0, 35.0, 11.0, 43.0,  1.0, 33.0,  9.0, 41.0,
	51.0, 19.0, 59.0, 27.0, 49.0, 17.0, 57.0, 25.0,
	15.0, 47.0,  7.0, 39.0, 13.0, 45.0,  5.0, 37.0,
	63.0, 31.0, 55.0, 23.0, 61.0, 29.0, 53.0, 21.0
};

float bayer8(vec2 cell) {
	int x = int(mod(cell.x, 8.0));
	int y = int(mod(cell.y, 8.0));
	return (BAYER8[y * 8 + x] + 0.5) / 64.0;
}

void fragment() {
	float left_edge = skew_left * (1.0 - UV.y);
	float right_edge = 1.0 - skew_right * (1.0 - UV.y);
	if (UV.x < left_edge || UV.x > right_edge) {
		discard;
	}
	vec3 base = (UV.x < left_edge + accent_width) ? accent_color.rgb : fill_color.rgb;
	float thr = bayer8(floor(FRAGCOORD.xy / dither_px));
	vec3 q = base * (color_levels - 1.0);
	vec3 dithered = (floor(q) + step(vec3(thr), fract(q))) / (color_levels - 1.0);
	COLOR = vec4(dithered, 1.0);
}
