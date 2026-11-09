shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 body_color : source_color = vec4(0.80, 0.77, 0.69, 1.0);
uniform vec4 top_iron_color : source_color = vec4(0.14, 0.11, 0.09, 1.0);
uniform vec4 rust_color : source_color = vec4(0.28, 0.18, 0.12, 1.0);
uniform vec4 burner_ring_color : source_color = vec4(0.38, 0.37, 0.35, 1.0);
uniform vec4 burner_hole_color : source_color = vec4(0.08, 0.07, 0.06, 1.0);
instance uniform float grime_amount : hint_range(0.0, 1.0) = 0.65;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i + vec2(0.0, 0.0)), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float octagon_sdf(vec2 p, float r) {
	const vec3 k = vec3(-0.9238795325, 0.3826834323, 0.4142135623);
	p = abs(p);
	p -= 2.0 * min(dot(vec2(k.x, k.y), p), 0.0) * vec2(k.x, k.y);
	p -= 2.0 * min(dot(vec2(-k.x, k.y), p), 0.0) * vec2(-k.x, k.y);
	p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
	return length(p) * sign(p.y);
}

void fragment() {
	// UV.y < 0.5 = Side body enamel; UV.y >= 0.5 = Top cast-iron plate & trim
	if (UV.y < 0.5) {
		vec2 side_uv = vec2(UV.x, UV.y * 2.0);
		float streaks = noise2d(vec2(side_uv.x * 36.0, side_uv.y * 4.0));
		float fine = noise2d(side_uv * 48.0);
		float edge_dirt = pow(abs(side_uv.y - 0.5) * 2.0, 2.2);
		float rust_mask = clamp(
			(edge_dirt * 0.75 + (1.0 - streaks) * 0.35) * grime_amount,
			0.0,
			1.0
		);

		vec3 col = mix(body_color.rgb * (0.88 + 0.15 * fine), rust_color.rgb, rust_mask);
		ALBEDO = col;
		ROUGHNESS = mix(0.55, 0.92, rust_mask);
		METALLIC = 0.05;
	} else {
		vec2 top_uv = vec2(UV.x, (UV.y - 0.5) * 2.0);
		float rust_n = noise2d(top_uv * 28.0);
		vec3 col = mix(top_iron_color.rgb, rust_color.rgb, rust_n * 0.55 * grime_amount);
		float rough = 0.88;
		float metal = 0.25;

		// 4 octagonal burners mapped on top face (UV.y >= 0.55)
		if (UV.y > 0.54) {
			vec2 aspect_uv = vec2(top_uv.x * 1.54, top_uv.y);
			vec2 centers[4] = vec2[4](
				vec2(0.43, 0.28),
				vec2(1.11, 0.28),
				vec2(0.43, 0.72),
				vec2(1.11, 0.72)
			);

			for (int i = 0; i < 4; i++) {
				float d_outer = octagon_sdf(aspect_uv - centers[i], 0.145);
				float d_inner = octagon_sdf(aspect_uv - centers[i], 0.06);
				if (d_inner < 0.0) {
					col = burner_hole_color.rgb;
					rough = 0.95;
					metal = 0.05;
				} else if (d_outer < 0.0) {
					col = mix(burner_ring_color.rgb, rust_color.rgb, rust_n * 0.35);
					rough = 0.65;
					metal = 0.45;
				}
			}
		}

		ALBEDO = col;
		ROUGHNESS = rough;
		METALLIC = metal;
	}
}
