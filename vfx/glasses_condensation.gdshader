shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float full_lens_fog : hint_range(0.0, 1.0) = 0.0;
uniform float edge_condensation : hint_range(0.0, 1.0) = 0.0;
uniform vec4 vapor_tint : source_color = vec4(0.86, 0.9, 0.94, 1.0);
uniform float max_blur_lod : hint_range(0.0, 4.5) = 2.6;
uniform float droplet_density : hint_range(0.0, 2.0) = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2d(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 3; i++) {
		v += a * value_noise2d(p);
		p = p * 2.13 + vec2(13.7, 29.1);
		a *= 0.45;
	}
	return v;
}

// Signed distance to a rounded dual-lens glasses contour with a subtle center nose-bridge.
float glasses_rim_mask(vec2 uv) {
	vec2 centered = uv - vec2(0.5);
	vec2 lens_uv = vec2(abs(centered.x) - 0.24, centered.y * 1.15);
	vec2 q = abs(lens_uv) - vec2(0.21, 0.36);
	float lens_dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.14;

	// Subtle nose bridge arch near center-top of the lenses.
	float bridge_arch = exp(-pow(centered.x * 9.5, 2.0)) * smoothstep(-0.18, 0.28, -centered.y) * 0.28;
	float radial_edge = smoothstep(-0.22, 0.06, lens_dist);
	return clamp(max(radial_edge, bridge_arch), 0.0, 1.0);
}

void fragment() {
	float total_activity = max(full_lens_fog, edge_condensation);
	if (total_activity <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 0.0001), 1.0);
		vec2 aspect_uv = SCREEN_UV * aspect;

		float rim_contour = glasses_rim_mask(UV);
		float vapor_noise = fbm2d(aspect_uv * 4.5 + vec2(0.0, -TIME * 0.08));

		// Combine persistent edge condensation rim with full-lens entry flash.
		float edge_mask = smoothstep(0.18, 0.88, rim_contour + (vapor_noise - 0.5) * 0.26) * edge_condensation;
		float center_flash = smoothstep(0.0, 1.0, full_lens_fog) * (0.78 + 0.22 * vapor_noise);
		float fog_coverage = clamp(max(edge_mask, center_flash), 0.0, 1.0);

		// Procedural micro-condensation beads across the fogged regions.
		vec2 total_refraction = vec2(0.0);
		float bead_specular = 0.0;

		for (float layer = 1.0; layer <= 2.0; layer += 1.0) {
			float grid_scale = mix(18.0, 34.0, layer - 1.0);
			vec2 grid_uv = aspect_uv * grid_scale;
			vec2 cell_id = floor(grid_uv);
			vec2 local_uv = fract(grid_uv) - vec2(0.5);

			float seed_a = hash21(cell_id + layer * 7.13);
			float seed_b = hash21(cell_id + layer * 19.37);
			vec2 bead_center = (vec2(seed_a, seed_b) - vec2(0.5)) * 0.48;
			vec2 delta = local_uv - bead_center;

			// Slight vertical teardrop elongation on larger beads.
			delta.y *= mix(0.85, 1.15, seed_a);
			float dist = length(delta);
			float radius = mix(0.14, 0.34, seed_b) * droplet_density;

			float appear_thresh = hash21(cell_id + vec2(3.7, 11.2));
			float bead_active = smoothstep(appear_thresh * 0.75, appear_thresh * 0.75 + 0.2, fog_coverage);

			if (dist < radius && bead_active > 0.001) {
				float bead_mask = smoothstep(radius, radius * 0.55, dist) * bead_active;
				float nz = sqrt(max(0.0, radius * radius - dist * dist));
				vec3 normal = normalize(vec3(delta.x, delta.y, nz * 0.75));

				total_refraction += normal.xy * bead_mask * 0.032;
				float spec = pow(max(dot(normal, normalize(vec3(0.35, -0.45, 0.82))), 0.0), 40.0);
				bead_specular += spec * bead_mask * 0.65;
			}
		}

		// Subtle vapor breath distortion + mipmap frosted blur.
		vec2 vapor_warp = (vec2(vapor_noise, fbm2d(aspect_uv * 6.0 + 9.4)) - vec2(0.5)) * 0.006 * fog_coverage;
		vec2 sample_uv = clamp(SCREEN_UV - total_refraction + vapor_warp, vec2(0.001), vec2(0.999));
		float lod = fog_coverage * max_blur_lod;

		vec3 blurred_scene = textureLod(screen_tex, sample_uv, lod).rgb;
		float milky_scatter = fog_coverage * (0.28 + 0.18 * vapor_noise);
		vec3 final_rgb = mix(blurred_scene, vapor_tint.rgb, clamp(milky_scatter, 0.0, 0.55)) + vec3(bead_specular);

		float alpha_out = smoothstep(0.0, 0.12, fog_coverage);
		COLOR = vec4(final_rgb, alpha_out);
	}
}
