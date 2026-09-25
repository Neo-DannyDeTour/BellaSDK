shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.05, 0.05, 0.05, 1.0);
uniform vec4 ribbon_color_a : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform vec4 ribbon_color_b : source_color = vec4(1.0, 0.3, 0.6, 1.0);

uniform float zoom : hint_range(1.0, 200.0, 0.1) = 20.0;
uniform float wave_crop : hint_range(0.1, 1.0, 0.01) = 0.8;
uniform float brightness : hint_range(0.1, 3.0, 0.01) = 1.0;
uniform float speed : hint_range(0.0, 10.0, 0.01) = 1.0;
uniform int iterations : hint_range(1, 30) = 5;
uniform float frq_start : hint_range(0.1, 50.0, 0.01) = 20.0;
uniform float frq_coef : hint_range(0.1, 2.0, 0.01) = 1.0;
uniform float alpha_threshold : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float custom_time : hint_range(-1.0, 100000.0, 0.01) = -1.0;

void fragment() {
	vec2 uv = UV - 0.5;
	vec3 color = base_color.rgb;

	float current_time = (custom_time >= 0.0 ? custom_time : TIME) * speed;
	float frq = frq_start;

	for (int i = 0; i < iterations; i++) {
		uv.y += sin(uv.x * 4.0 + current_time) / frq;
		uv.x += cos(uv.y * 8.0 + current_time) / frq;
		frq *= frq_coef;
	}

	float safe_crop = max(wave_crop, 0.1);
	float hard_limit = step(safe_crop, 1.0 - abs(uv.y));
	float soft_limit = smoothstep(
		safe_crop,
		safe_crop + 0.1,
		1.0 - abs(uv.y)
	);

	vec3 tint = mix(
		ribbon_color_a.rgb,
		ribbon_color_b.rgb,
		clamp(uv.x + 0.5, 0.0, 1.0)
	);
	color += tint * brightness * soft_limit;

	float wave = sin(uv.y * zoom) * 0.5 + 0.5;
	wave = 1.0 - smoothstep(0.0, 0.5, wave);
	wave *= hard_limit;

	color *= wave;

	float avg = (color.r + color.g + color.b) / 3.0;
	COLOR = vec4(color, avg < alpha_threshold ? 0.0 : 1.0);
}
