shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 closed_color : source_color = vec4(0.95, 0.12, 0.18, 1.0);
uniform vec4 closed_core_color : source_color = vec4(1.0, 0.78, 0.78, 1.0);
uniform vec4 open_color : source_color = vec4(0.18, 0.95, 0.42, 1.0);
uniform vec4 open_core_color : source_color = vec4(0.82, 1.0, 0.88, 1.0);

uniform float open_blend : hint_range(0.0, 1.0) = 0.0;
uniform float energy_level : hint_range(0.0, 1.0) = 1.0;
uniform float caustic_intensity : hint_range(0.0, 4.0) = 1.75;
uniform float sphere_ripple_strength : hint_range(0.0, 4.0) = 1.35;
uniform float ripple_frequency : hint_range(5.0, 80.0) = 40.0;
uniform float aspect_ratio = 0.75;
uniform float arch_spring_ratio : hint_range(0.3, 0.95) = 0.70;
uniform float proximity_fade_distance : hint_range(0.01, 2.0) = 0.35;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

vec2 hash2(vec2 p) {
	return fract(
		sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453
	);
}

float voronoi_caustics(vec2 uv, float time) {
	vec2 i_uv = floor(uv);
	vec2 f_uv = fract(uv);
	float m_dist1 = 8.0;
	float m_dist2 = 8.0;

	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = hash2(i_uv + neighbor);
			point = 0.5 + 0.5 * sin(time + 6.283185 * point);
			vec2 diff = neighbor + point - f_uv;
			float dist = length(diff);

			if (dist < m_dist1) {
				m_dist2 = m_dist1;
				m_dist1 = dist;
			} else if (dist < m_dist2) {
				m_dist2 = dist;
			}
		}
	}
	float edge = m_dist2 - m_dist1;
	return pow(clamp(1.0 - edge * 2.1, 0.0, 1.0), 2.8);
}

float emitter_wave(vec2 uv, vec2 emitter_uv, float time) {
	vec2 delta = (uv - emitter_uv) * vec2(aspect_ratio, 1.0);
	float dist = length(delta);
	float rings = sin(dist * ripple_frequency - time * 6.5) * 0.5 + 0.5;
	rings = pow(rings, 2.2);
	float falloff = exp(-dist * 3.6);
	return rings * falloff;
}

void fragment() {
	if (energy_level <= 0.001) {
		ALPHA = 0.0;
	} else {
		vec2 uv = vec2(UV.x, 1.0 - UV.y);
		float t = TIME;

		// Pointed Gothic arch mask matching the physical stone voussoirs
		float half_span = 0.5;
		if (uv.y > arch_spring_ratio) {
			float ny = clamp((uv.y - arch_spring_ratio) / (1.0 - arch_spring_ratio), 0.0, 1.0);
			half_span = 0.5 * (1.0 - pow(ny, 1.45));
		}
		float dist_from_center = abs(uv.x - 0.5);
		float arch_mask = 1.0 - smoothstep(half_span - 0.025, half_span, dist_from_center);
		float arch_rim = smoothstep(half_span - 0.08, half_span - 0.015, dist_from_center) * arch_mask;

		// 6-Emitter concentric sphere waves aligned to pillar emitter heights
		float y1 = 0.22 * arch_spring_ratio;
		float y2 = 0.50 * arch_spring_ratio;
		float y3 = 0.78 * arch_spring_ratio;

		float e_l1 = emitter_wave(uv, vec2(0.0, y1), t);
		float e_l2 = emitter_wave(uv, vec2(0.0, y2), t);
		float e_l3 = emitter_wave(uv, vec2(0.0, y3), t);
		float e_r1 = emitter_wave(uv, vec2(1.0, y1), t);
		float e_r2 = emitter_wave(uv, vec2(1.0, y2), t);
		float e_r3 = emitter_wave(uv, vec2(1.0, y3), t);

		float spheres = (e_l1 + e_l2 + e_l3 + e_r1 + e_r2 + e_r3) * sphere_ripple_strength;

		// Dual-layer swirling caustics
		vec2 warp = vec2(
			sin(uv.y * 5.5 + t * 0.75) * 0.07,
			cos(uv.x * 5.5 - t * 0.65) * 0.07
		);
		vec2 uv_scale1 = vec2(3.6 * aspect_ratio, 3.6);
		vec2 uv_scale2 = vec2(6.2 * aspect_ratio, 6.2);
		float c1 = voronoi_caustics(
			(uv + warp) * uv_scale1 + vec2(t * 0.11, -t * 0.16),
			t * 1.15
		);
		float c2 = voronoi_caustics(
			(uv - warp) * uv_scale2 + vec2(-t * 0.14, t * 0.20),
			t * 1.65
		);
		float caustics = (c1 * 0.65 + c2 * 0.45) * caustic_intensity * energy_level;

		// Soft intersection glow using depth texture
		float depth_raw = texture(depth_texture, SCREEN_UV).r;
		vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
		float pixel_dist = abs((upos.xyz / upos.w).z - VERTEX.z);
		float contact_glow = clamp(1.0 - pixel_dist / proximity_fade_distance, 0.0, 1.0);

		float edge_collapse = mix(smoothstep(0.35, 0.0, 0.5 - dist_from_center), 1.0, energy_level);
		float bottom_fade = smoothstep(0.0, 0.06, uv.y);
		float base_haze = (0.14 + arch_rim * 0.35 + contact_glow * 0.45) * bottom_fade;

		float combined = (base_haze + caustics + spheres) * arch_mask * edge_collapse * energy_level;
		float hot_mask = clamp(caustics * 0.55 + spheres * 0.5 + contact_glow * 0.4, 0.0, 1.0);

		vec3 active_base = mix(closed_color.rgb, open_color.rgb, open_blend);
		vec3 active_core = mix(closed_core_color.rgb, open_core_color.rgb, open_blend);
		vec3 col = mix(active_base, active_core, hot_mask);

		// Slightly more translucent when open (eldritch green) so players see they can pass
		float state_alpha_scale = mix(0.86, 0.68, open_blend);
		ALBEDO = col * (1.25 + combined * 1.5);
		ALPHA = clamp(combined * state_alpha_scale, 0.0, 0.96);
	}
}
