shader_type spatial;
render_mode unshaded, cull_disabled;

instance uniform vec4 base_color : source_color = vec4(0.05, 0.05, 0.05, 1.0);
instance uniform vec4 ribbon_color_a : source_color = vec4(0.2, 0.6, 1.0, 1.0);
instance uniform vec4 ribbon_color_b : source_color = vec4(1.0, 0.3, 0.6, 1.0);
instance uniform float emission_energy : hint_range(0.0, 16.0, 0.1) = 3.0;
instance uniform float zoom : hint_range(1.0, 200.0, 0.1) = 20.0;
instance uniform float wave_crop : hint_range(0.1, 1.0, 0.01) = 0.8;
instance uniform float brightness : hint_range(0.1, 3.0, 0.01) = 1.0;
instance uniform float speed : hint_range(0.0, 10.0, 0.01) = 1.0;
instance uniform int iterations : hint_range(1, 30) = 5;
instance uniform float frq_start : hint_range(0.1, 50.0, 0.01) = 20.0;
instance uniform float frq_coef : hint_range(0.1, 2.0, 0.01) = 1.0;
instance uniform float alpha_threshold : hint_range(0.0, 1.0, 0.01) = 0.0;
instance uniform float aspect_ratio : hint_range(0.1, 10.0, 0.01) = 2.0;

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= aspect_ratio;

	vec3 color = base_color.rgb;
	float current_time = TIME * speed;
	float frq = max(frq_start, 0.1);
	int safe_iter = clamp(iterations, 1, 30);

	for (int i = 0; i < safe_iter; i++) {
		uv.y += sin(uv.x * 4.0 + current_time) / frq;
		uv.x += cos(uv.y * 8.0 + current_time) / frq;
		frq = max(frq * frq_coef, 0.05);
	}

	float safe_crop = max(wave_crop, 0.1);
	float inv_abs_y = 1.0 - abs(uv.y);
	float hard_limit = step(safe_crop, inv_abs_y);
	float soft_limit = smoothstep(safe_crop, safe_crop + 0.1, inv_abs_y);

	float grad_t = clamp((uv.x / max(aspect_ratio, 0.01)) + 0.5, 0.0, 1.0);
	vec3 tint = mix(ribbon_color_a.rgb, ribbon_color_b.rgb, grad_t);
	color += tint * brightness * soft_limit;

	float wave = sin(uv.y * zoom) * 0.5 + 0.5;
	wave = 1.0 - smoothstep(0.0, 0.5, wave);
	wave *= hard_limit;

	color *= wave;

	float avg = (color.r + color.g + color.b) * 0.333333;
	ALBEDO = color * (1.0 + emission_energy * 0.5);
	ALPHA = avg < alpha_threshold ? 0.0 : 1.0;
	ALPHA_SCISSOR_THRESHOLD = alpha_threshold > 0.0 ? 0.5 : 0.0;
}
