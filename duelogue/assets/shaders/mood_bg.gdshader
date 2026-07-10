shader_type canvas_item;

// DUELOGUE — живой фон высказывания (крупный план reaction_scene): АНИМЕ-СПИДЛАЙНЫ.
// Три слоя (снизу вверх): гладкий градиент цвета СТОРОНЫ → ЛУЧ ПО ЦЕНТРУ (широкий световой
// столб вдоль направления, край растворяется мягким крупнозернистым дизером ступеней) →
// штрихи-«веретёна» (длинные, сужаются к концам; у ряда своя фаза/темп/ТОЛЩИНА в диапазоне
// thick_min..thick_max — толщина разная в пределах одного эффекта). Дизер линий живёт в них
// самих: тело жирное и резкое, края/хвосты рассыпаются порогом Байера 8×8.
// Пластику калибрует профиль MOOD_FX в reaction_scene.gd по meta.mood (контракт §16).
// Дефолты — откалиброванные «комфортные» значения (fx_lab, 2026-07-09): ячейка вдоль 0.5,
// мазок 0.42..1, рядов 25..42, скорость от 1, толщина 0.3..0.8.

uniform vec2 direction = vec2(1.0, 0.0);      // куда «смотрят» штрихи и летит энергия
uniform float line_intensity : hint_range(0.0, 1.0) = 0.5; // мощность: плотность/яркость зерна линий
uniform vec4 line_color_a : source_color = vec4(1.0, 0.97, 0.88, 1.0); // перелив: цвет А
uniform vec4 line_color_b : source_color = vec4(0.75, 0.8, 0.85, 1.0); // перелив: цвет Б
uniform vec4 edge_color : source_color = vec4(0.02, 0.05, 0.045, 1.0);  // фон по краям (поперёк)
uniform vec4 center_color : source_color = vec4(0.086, 0.2, 0.15, 1.0); // фон в середине
uniform float line_density : hint_range(2.0, 60.0) = 30.0; // рядов штрихов поперёк (комфорт 25..42)
uniform float speed : hint_range(-10.0, 10.0) = 2.0;       // скорость полёта штрихов (комфорт от 1)
uniform float dash_scale : hint_range(0.25, 8.0) = 0.5;    // ячеек вдоль: МЕНЬШЕ = ДЛИННЕЕ (канон 0.5)
uniform float line_fill : hint_range(0.05, 1.0) = 0.6;     // доля ячейки под штрихом (комфорт 0.42..1)
uniform float thick_min : hint_range(0.05, 1.0) = 0.3;     // толщина: низ разброса по рядам
uniform float thick_max : hint_range(0.05, 1.0) = 0.8;     // толщина: верх разброса по рядам
uniform float dither_px : hint_range(1.0, 8.0) = 2.0;      // чанк-«пиксель» зерна линий

uniform vec4 beam_color : source_color = vec4(0.5, 0.6, 0.55, 1.0); // цвет луча (ставит сцена)
uniform float beam_strength : hint_range(0.0, 1.0) = 0.4;  // сила луча (масштабируется мощностью)
uniform float beam_width : hint_range(0.05, 1.0) = 0.32;   // полуширина луча поперёк
uniform float beam_grain : hint_range(1.0, 12.0) = 4.0;    // крупное зерно мягкого края луча
uniform float beam_levels : hint_range(2.0, 12.0) = 5.0;   // ступеней градиента луча

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

float hash1(float n) {
	return fract(sin(n * 127.1) * 43758.5453123);
}

void fragment() {
	vec2 dir = normalize(direction);
	vec2 perp = vec2(-dir.y, dir.x);
	vec2 centered = UV - 0.5;
	// Поправка аспекта — иначе штрихи кривятся эллипсом на не-квадратном экране.
	float aspect = SCREEN_PIXEL_SIZE.y / max(0.0001, SCREEN_PIXEL_SIZE.x);
	vec2 corrected = vec2(centered.x * aspect, centered.y);

	float along = dot(corrected, dir);   // позиция вдоль полёта
	float across = dot(corrected, perp); // позиция поперёк (какой это ряд)

	// Фон гладкий: градиент от edge_color (края поперёк) к center_color (середина).
	float center_gate = 1.0 - smoothstep(0.0, 0.65, abs(across));
	vec3 bg = mix(edge_color.rgb, center_color.rgb, center_gate);

	// ЛУЧ ПО ЦЕНТРУ (позади штрихов): широкий световой столб вдоль направления. Край не
	// гладкий: маска квантуется на beam_levels ступеней, порог Байера КРУПНЫМ зерном
	// beam_grain размывает границы ступеней — ретро-градиент лесенкой, как в аниме-фонах.
	float beam = 1.0 - smoothstep(0.0, max(beam_width, 0.001), abs(across));
	beam *= beam_strength * (0.35 + 0.65 * line_intensity);
	float bthr = bayer8(floor(FRAGCOORD.xy / beam_grain));
	float bq = beam * beam_levels;
	beam = clamp((floor(bq) + step(bthr, fract(bq))) / beam_levels, 0.0, 1.0);
	bg = mix(bg, beam_color.rgb, beam);

	// Ряды поперёк: у каждого свои фаза, темп, толщина и яркость — живая рука, не гребёнка.
	float rows = across * line_density;
	float row = floor(rows);
	float frow = fract(rows) - 0.5;
	float r1 = hash1(row * 1.37 + 3.1);
	float r2 = hash1(row * 2.11 + 7.9);

	// Штрихи вдоль: ячейки dash_scale; движение со speed (у ряда своя вариация темпа).
	float t = along * dash_scale - TIME * speed * (0.7 + 0.6 * r1) - r1 * 19.7;
	float cell_i = floor(t);
	float ft = fract(t);
	float seed = hash1(row * 13.7 + cell_i * 4.3);
	// Не каждая ячейка несёт штрих (рваный ритм), длина мазка у каждого своя.
	float on = step(seed, 0.85);
	float len = line_fill * (0.45 + 0.55 * seed);
	float in_dash = step(ft, len);
	float u = clamp(ft / max(len, 0.001), 0.0, 1.0);
	// Веретено: штрих сужается и гаснет к обоим концам (профиль мазка пера).
	float spindle = pow(sin(u * PI), 0.65) * in_dash;

	// Толщина: у каждого ряда СВОЯ в диапазоне thick_min..thick_max × веретено (кончики тоньше).
	float w = mix(thick_min, thick_max, r2) * 0.5 * (0.35 + 0.65 * spindle);
	float body = 1.0 - smoothstep(w * 0.4, w, abs(frow)); // мягкий профиль — его и растворит дизер
	float bright = mix(0.55, 1.0, hash1(row * 5.3 + cell_i * 9.1));
	float streak = spindle * body * bright * on * line_intensity;

	// Перелив цвета, бегущий вдоль штрихов (A ↔ B).
	float hue_run = 0.5 + 0.5 * sin(along * 2.5 - TIME * speed * 0.6 + r1 * TAU);
	vec3 line_col = mix(line_color_a.rgb, line_color_b.rgb, hue_run);

	// Дизер линий: порог Байера по чанкам dither_px — бинарный штрих, края/хвосты в зерно.
	float thr = bayer8(floor(FRAGCOORD.xy / dither_px));
	float m = step(thr, streak);

	COLOR = vec4(mix(bg, line_col, m), 1.0);
}
