shader_type canvas_item;

// DUELOGUE — дизер-материал ЭЛЕМЕНТА (ordered-дизеринг, Bayer 8×8). Вешается на конкретную
// ноду (сейчас — портрет reaction_scene; годится картам, актёрам, чему угодно) и квантует
// ЕЁ собственный цвет на color_levels ступеней чанками dither_px экранных пикселей.
// РЕЖИМ ТЕНЕЙ: dark_ceiling < 1 зернит только тона ТЕМНЕЕ порога (света остаются чистыми,
// штриховка живёт в тенях — скринтон-манга); dark_ceiling = 1.0 — дизерится весь элемент.
// Альфа проходит как есть (края арта не зернятся); fade сцены (modulate) уже вмешан во
// входной COLOR и квантуется вместе с цветом — исчезновение тоже ступенчато-ретро.

uniform float dither_px : hint_range(1.0, 8.0) = 2.0;     // размер чанка-«пикселя» зерна
uniform float color_levels : hint_range(2.0, 32.0) = 6.0; // ступеней цвета на канал
uniform float dark_ceiling : hint_range(0.0, 1.0) = 1.0;  // зернить тона темнее этого (1 = всё)
uniform float dark_soft : hint_range(0.0, 0.5) = 0.15;    // мягкость границы свет/тень
uniform float strength : hint_range(0.0, 1.0) = 1.0;      // общий подмес эффекта

// Классическая матрица Байера 8×8 (значения 0..63, рекурсия от M2=[[0,2],[3,1]]).
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
	vec4 base = COLOR; // текстура элемента × modulate
	float thr = bayer8(floor(FRAGCOORD.xy / dither_px));
	vec3 q = clamp(base.rgb, vec3(0.0), vec3(1.0)) * (color_levels - 1.0);
	vec3 dithered = (floor(q) + step(vec3(thr), fract(q))) / (color_levels - 1.0);
	// Зона теней: 1 в тёмных тонах, тает к порогу; при dark_ceiling=1.0 — весь элемент.
	// ds > 0 всегда: smoothstep с совпадающими краями (мягкость 0) — неопределённость GLSL.
	float lum = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	float ds = max(dark_soft, 0.001);
	float zone = 1.0 - smoothstep(dark_ceiling - ds, dark_ceiling + ds, lum);
	zone = max(zone, step(0.999, dark_ceiling));
	COLOR = vec4(mix(base.rgb, dithered, zone * strength), base.a);
}
