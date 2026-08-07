shader_type canvas_item;

// DUELOGUE — «ОГОНЬ ЗАПАЛА» v2: волюметрический fbm-огонь позади персонажа на общем плане
// (stage.tscn, Actors), обмазанный тем же Байер 8×8 дизером, что dither.gdshader/mood_bg —
// ступенчатые цветовые полосы + зернёный дизером край, не гладкий градиент.
// Ядро турбулентности — domain-warped FBM (value-noise, не текстура): образ взят с разбора
// https://www.willdoenlen.com/blog/realistic-fire-shader (fbm(p + warp(p)), вертикальный
// снос координаты семплирования во времени = пламя "течёт" вверх), НЕ буквальный порт —
// value-noise вместо gradient-noise (дешевле, без доп. текстур), и альфа не зашита в 1.0,
// а честно тянется из плотности поля × intensity, чтобы фон был прозрачным, а не чёрным.
// intensity 0 = потушено (альфа честно 0); 1 = пик — выше (reach), шире (width), плотнее
// (density_bias) и быстрее (speed) одновременно = «объём и частота» растут вместе со шкалой
// эмоции. v2.1: контур тоже дребезжит, не только заливка внутри него — left/right/top-границы
// огибающей смещаются собственными fbm-семплами (edge_flicker), силуэт рвётся неровными
// языками вместо статичного конуса; подошва заглушена (anchor), ноги пламени не гуляют.
// Коннектор — stage_core.gd, слушает EventBus.emotion_changed.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;      // 0 = потушено, 1 = пик (strain/max стороны)
uniform vec4 color_ember : source_color = vec4(0.35, 0.06, 0.03, 1.0);  // холодный край/низкий heat
uniform vec4 color_mid : source_color = vec4(0.92, 0.35, 0.06, 1.0);    // рабочее пламя
uniform vec4 color_hot : source_color = vec4(1.0, 0.75, 0.15, 0.92);    // яркое пламя у подошвы; .a = пик альфы
uniform vec4 color_core : source_color = vec4(1.0, 0.96, 0.78, 1.0);    // раскалённое ядро (только на пике heat×intensity)

uniform float noise_scale : hint_range(0.5, 10.0) = 3.2;   // масштаб турбулентности (больше = мельче языки)
uniform float warp_strength : hint_range(0.0, 4.0) = 1.1;  // сила искажения domain-warp

uniform float base_speed : hint_range(0.05, 4.0) = 0.5;    // скорость подъёма/пляски на intensity=0
uniform float max_speed : hint_range(0.05, 8.0) = 2.2;     // скорость подъёма/пляски на intensity=1 («частота»)
uniform float base_reach : hint_range(0.0, 1.0) = 0.5;     // высота пламени на intensity=0 (доля рамки)
uniform float max_reach : hint_range(0.0, 1.0) = 0.98;     // высота пламени на intensity=1 («объём»)
uniform float base_width : hint_range(0.0, 1.0) = 0.34;    // ширина у подошвы на intensity=0 (доля рамки)
uniform float max_width : hint_range(0.0, 1.0) = 0.62;     // ширина у подошвы на intensity=1 («объём»)
uniform float max_density_bias : hint_range(0.0, 0.6) = 0.22; // на пике толкает поле плотнее (меньше дыр)
uniform float edge_soft : hint_range(0.0, 0.3) = 0.05;     // мягкость краевого спада ширины/верха

uniform float base_edge_flicker : hint_range(0.0, 0.3) = 0.02; // дребезг контура на intensity=0 (доля ширины рамки)
uniform float max_edge_flicker : hint_range(0.0, 0.3) = 0.12;  // дребезг контура на intensity=1 — силуэт рвётся языками
uniform float edge_flicker_scale : hint_range(0.5, 8.0) = 2.5; // масштаб волн дребезга по высоте/ширине

uniform float flame_levels : hint_range(2.0, 16.0) = 6.0;  // ступеней посадки поля (посветеризация)
uniform float dither_px : hint_range(1.0, 8.0) = 2.0;      // чанк-«пиксель» зерна Байер-дизера

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

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Value-noise (билинейная интерполяция хэша по углам ячейки) — дешёвая замена gradient-noise
// оригинала, та же качественная турбулентность без текстур-ассетов.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

const int FBM_OCTAVES = 4;
// Поворот на октаву (IQ-приём) — сбивает решётчатые артефакты, которые иначе тянутся от
// осей value-noise на всех октавах разом.
const mat2 FBM_ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < FBM_OCTAVES; i++) {
		sum += amp * vnoise(p);
		p = FBM_ROT * p * 2.02;
		amp *= 0.5;
	}
	return sum;
}

void fragment() {
	float speed = mix(base_speed, max_speed, intensity);
	float reach = mix(base_reach, max_reach, intensity);
	float width = mix(base_width, max_width, intensity);
	float density_bias = max_density_bias * intensity;
	float flicker = mix(base_edge_flicker, max_edge_flicker, intensity);

	float rise = 1.0 - UV.y;  // 0 у подошвы рамки (там нога актёра), 1 у верхнего края рамки
	vec2 p = vec2((UV.x - 0.5) * noise_scale, rise * noise_scale * 1.4 - TIME * speed);

	// Domain warp: поле искажает само себя через два вспомогательных fbm-семпла — вместо
	// прямых слоёв шума получаются "языки"/завихрения, а не просто мутные пятна.
	vec2 warp = vec2(
		fbm(p + vec2(0.0, 1.7)),
		fbm(p + vec2(5.2, -3.1) - TIME * speed * 0.15));
	float f = fbm(p + warp * warp_strength);
	f = clamp(f + density_bias, 0.0, 1.0);

	// Дребезг контура: тот же fbm, но по (высота/ширина, время) — левый край, правый край и
	// макушка сдвигаются по ОТДЕЛЬНЫМ семплам (разные сдвиги координат), поэтому силуэт рвётся
	// неровными языками, а не дышит одним синхронным пульсом. anchor гасит дребезг у самой
	// подошвы — ноги пламени стоят на месте, шевелится тело и макушка.
	float anchor = smoothstep(0.0, 0.15, rise);
	float wobble_l = (fbm(vec2(rise * edge_flicker_scale, TIME * speed * 0.8)) - 0.5) * 2.0 * flicker * anchor;
	float wobble_r = (fbm(vec2(rise * edge_flicker_scale + 23.4, TIME * speed * 0.8 - 11.1)) - 0.5) * 2.0 * flicker * anchor;
	float tip_wobble = (fbm(vec2(UV.x * edge_flicker_scale * 2.0 + 7.7, TIME * speed * 0.8 + 3.3)) - 0.5) * 2.0 * flicker;

	// Огибающая силуэта: у подошвы шире, к верху сужается и гаснет — ширина/высота растут
	// вместе с intensity, это и есть "объём". Левая/правая граница и макушка смещены на
	// wobble_l/wobble_r/tip_wobble — дребезжит сама ГРАНИЦА, не только заполнение внутри неё.
	float dx = UV.x - 0.5;
	float taper = mix(width, width * 0.16, smoothstep(0.0, 1.0, rise / max(reach, 0.001)));
	float half_taper = taper * 0.5;
	float boundary_l = -half_taper - wobble_l;
	float boundary_r = half_taper + wobble_r;
	float edge_l = smoothstep(boundary_l, boundary_l + edge_soft, dx);
	float edge_r = 1.0 - smoothstep(boundary_r - edge_soft, boundary_r, dx);
	float edge = edge_l * edge_r;
	float top_boundary = reach + tip_wobble;
	float top_fade = 1.0 - smoothstep(top_boundary * 0.75, top_boundary, rise);
	float envelope = edge * top_fade;

	float shape = clamp(f * envelope, 0.0, 1.0);

	// Дизер: тот же Байер-приём, что в dither.gdshader — поле квантуется на flame_levels
	// ступеней, край рассыпается зерном вместо гладкого сглаживания (ретро-манера проекта).
	float thr = bayer8(floor(FRAGCOORD.xy / dither_px));
	float q = shape * (flame_levels - 1.0);
	float shape_q = (floor(q) + step(thr, fract(q))) / (flame_levels - 1.0);

	// Палитра по локальному "жару": intensity дополнительно толкает по градиенту вверх —
	// на пике даже периферия языка читается горячее, не только сильнее светится.
	float heat = clamp(shape_q * mix(0.85, 1.35, intensity), 0.0, 1.0);
	vec3 col = mix(color_ember.rgb, color_mid.rgb, smoothstep(0.0, 0.45, heat));
	col = mix(col, color_hot.rgb, smoothstep(0.4, 0.75, heat));
	col = mix(col, color_core.rgb, smoothstep(0.75, 1.0, heat));

	// Альфа честно из плотности поля × intensity — на intensity=0 нулевая, не чёрная
	// подложка: сзади должен быть виден фон сцены, а не прямоугольник.
	COLOR = vec4(col, shape_q * intensity * color_hot.a);
}
