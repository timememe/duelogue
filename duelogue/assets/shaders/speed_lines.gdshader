shader_type canvas_item;

// DUELOGUE — направленные аниме-спидлайны: мягкие полосы вдоль uniform-вектора direction,
// с "энергией", бегущей вдоль них со скоростью speed. Фон — градиент edge_color (края,
// поперёк direction) → center_color (середина). progress (0..1) — общая видимость эффекта,
// её тянет reaction_scene.gd как вспышку (0→1→0). Настраиваемо: direction (куда "смотрят"
// и куда бежит энергия линий) и цвета (line_color / edge_color / center_color).

uniform vec2 direction = vec2(1.0, 0.0);       // направление полос и движения энергии вдоль них
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);    // цвет самих полос
uniform vec4 edge_color : source_color = vec4(0.05, 0.08, 0.35, 1.0);  // фон по краям (поперёк)
uniform vec4 center_color : source_color = vec4(0.55, 0.85, 1.0, 1.0); // фон в середине
uniform float line_density : hint_range(2.0, 60.0) = 18.0;  // сколько полос помещается поперёк
uniform float speed : hint_range(-10.0, 10.0) = 3.0;        // скорость "энергии" вдоль полос
uniform float softness : hint_range(0.0, 1.0) = 0.5;        // 0 = резкие тонкие линии, 1 = мягкое свечение

float hash1(float n) {
	return fract(sin(n * 127.1) * 43758.5453123);
}

void fragment() {
	vec2 dir = normalize(direction);
	vec2 perp = vec2(-dir.y, dir.x);
	vec2 centered = UV - 0.5;
	// Поправка аспекта — иначе полосы кривятся эллипсом на не-квадратном экране.
	float aspect = SCREEN_PIXEL_SIZE.y / max(0.0001, SCREEN_PIXEL_SIZE.x);
	vec2 corrected = vec2(centered.x * aspect, centered.y);

	float along = dot(corrected, dir);   // позиция вдоль направления полос
	float across = dot(corrected, perp); // позиция поперёк (какая это полоса)

	// Сами полосы: фиксированная синусоида поперёк — НЕ зависит от времени (полосы не "плывут"
	// поперёк своей же оси, только светятся/гаснут вдоль неё).
	float band_id = floor(across * line_density);
	float band_phase = hash1(band_id) * TAU;
	float band_wave = sin(across * line_density * TAU + band_phase);
	float sharpness = mix(28.0, 2.0, softness);
	float streak = pow(max(0.0, band_wave), sharpness);

	// Энергия бежит ВДОЛЬ полосы (по direction) со скоростью speed — вот это "вектор движения".
	float shimmer = 0.5 + 0.5 * sin(along * 6.0 - TIME * speed + band_phase);
	float bright_var = mix(0.35, 1.0, hash1(band_id + 5.3));  // у каждой полосы своя базовая яркость
	streak *= shimmer * bright_var;

	// Фон: мягкий градиент от edge_color по краям (поперёк) к center_color в середине.
	float center_gate = 1.0 - smoothstep(0.0, 0.65, abs(across));
	vec3 bg = mix(edge_color.rgb, center_color.rgb, center_gate);

	vec3 col = mix(bg, line_color.rgb, clamp(streak, 0.0, 1.0));
	COLOR = vec4(col, progress);
}
