shader_type canvas_item;
render_mode unshaded, blend_disabled;

group_uniforms Wipe_State;
uniform float wipe_progress : hint_range(0.0, 1.5, 0.001) = 0.0;
uniform float wash_intensity : hint_range(0.0, 1.0, 0.001) = 0.3;
uniform float visibility : hint_range(0.0, 1.0, 0.001) = 1.0;

group_uniforms Liquid_Optics;
uniform float distortion_strength : hint_range(0.0, 0.15, 0.001) = 0.052;
uniform float meniscus_strength : hint_range(0.0, 0.15, 0.001) = 0.068;
uniform float chromatic_aberration : hint_range(0.0, 0.5, 0.001) = 0.025;
uniform float flow_speed : hint_range(0.1, 8.0, 0.05) = 1.35;
uniform float ripple_scale : hint_range(1.0, 12.0, 0.1) = 4.8;
uniform float specular_intensity : hint_range(0.0, 1.5, 0.01) = 0.32;
uniform vec4 water_tint : source_color = vec4(0.62, 0.86, 0.92, 0.14);

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
}

float gradient_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(hash22(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
	float b = dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 0.5 + 0.5;
}

// Evaluates constant-speed BioShock-style domain-warped water sheet heightfield
float sample_liquid_height(vec2 uv, float t) {
	vec2 flow_a = vec2(0.08 * t, -t * 1.15);
	vec2 flow_b = vec2(-0.06 * t, -t * 0.78);

	float warp_x = gradient_noise(uv * (ripple_scale * 0.65) + flow_a * 0.6) - 0.5;
	float warp_y = gradient_noise(uv * (ripple_scale * 0.85) + flow_b * 0.8 + 7.3) - 0.5;
	vec2 warped_uv = uv + vec2(warp_x, warp_y) * 0.32;

	// Primary and secondary travelling surface ripples
	float wave_a = gradient_noise(warped_uv * ripple_scale + flow_a);
	float wave_b = gradient_noise(warped_uv * (ripple_scale * 1.85) + flow_b + vec2(3.7, 9.1));

	// Vertical Dishonored-style rivulet streams
	vec2 stream_uv = vec2(warped_uv.x * ripple_scale * 1.35, warped_uv.y * 1.5 - t * 1.35);
	float rivulets = smoothstep(0.25, 0.85, gradient_noise(stream_uv));

	// High-frequency capillary surface ripples
	float micro_ripples = sin(
		warped_uv.y * 26.0 - t * 9.0 + wave_a * 6.2831
	) * 0.5 + 0.5;

	return (wave_a * 0.45 + wave_b * 0.30 + rivulets * 0.35) + micro_ripples * 0.12;
}

void fragment() {
	float strength_mult = clamp(visibility * wash_intensity, 0.0, 1.0);
	if (strength_mult <= 0.0001 || wipe_progress >= 1.495) {
		COLOR = vec4(textureLod(screen_texture, SCREEN_UV, 0.0).rgb, 1.0);
	} else {
		vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 0.0001), 1.0);
		vec2 uv = SCREEN_UV * aspect;
		float t = TIME * flow_speed;

		// Uneven hanging liquid fingers along the falling meniscus curtain
		float finger_coarse = gradient_noise(vec2(uv.x * 2.8, TIME * 0.35));
		float finger_fine = gradient_noise(vec2(uv.x * 7.5, TIME * 0.6 + 4.2));
		float column_lag = (finger_coarse * 0.68 + finger_fine * 0.32) * 0.36;

		float wipe_active = step(0.001, wipe_progress);
		float curtain_y = mix(-0.25, wipe_progress * 1.28 - column_lag, wipe_active);
		float signed_dist = SCREEN_UV.y - curtain_y;

		// 1. Main water sheet mask below the falling curtain (1.0 everywhere during wash)
		float sheet_mask = mix(1.0, smoothstep(-0.025, 0.055, signed_dist), wipe_active);

		// 2. Thick refractive meniscus ridge along the tearing boundary
		float meniscus_band = exp(-pow(signed_dist / 0.038, 2.0)) * wipe_active;
		float finger_slope = dFdx(column_lag) * 18.0;

		// 3. Trailing droplets and rivulet beads above the main curtain
		float trail_zone = smoothstep(-0.48, -0.01, signed_dist) * (1.0 - sheet_mask) * wipe_active;
		vec2 bead_uv = vec2(uv.x * 9.5, uv.y * 5.5 - t * 0.9);
		float bead_field = smoothstep(0.62, 0.88, gradient_noise(bead_uv));
		float trail_mask = bead_field * trail_zone;

		// Analytical finite-difference normal from the domain-warped liquid heightfield
		float eps = 0.006;
		float h_c = sample_liquid_height(uv, t);
		float h_x = sample_liquid_height(uv + vec2(eps, 0.0), t);
		float h_y = sample_liquid_height(uv + vec2(0.0, eps), t);
		vec2 sheet_norm = vec2(h_c - h_x, h_c - h_y) / eps;

		// Meniscus normal bulges strongly downward (+Y) and follows finger curvature
		vec2 meniscus_norm = vec2(
			finger_slope + sheet_norm.x * 0.6,
			(signed_dist / 0.038) * 1.85 + 0.65
		);

		float total_coverage = clamp(sheet_mask + meniscus_band + trail_mask, 0.0, 1.0) * strength_mult;
		vec2 refract_offset = (
			sheet_norm * (sheet_mask + trail_mask * 0.85) * distortion_strength
			+ meniscus_norm * meniscus_band * meniscus_strength
		) * total_coverage;

		// Chromatic aberration split along liquid normal vector (0 offset when dry -> crisp screen)
		vec2 uv_r = clamp(SCREEN_UV + refract_offset * (1.0 + chromatic_aberration), 0.001, 0.999);
		vec2 uv_g = clamp(SCREEN_UV + refract_offset, 0.001, 0.999);
		vec2 uv_b = clamp(SCREEN_UV + refract_offset * (1.0 - chromatic_aberration), 0.001, 0.999);

		float mip_lod = clamp(length(refract_offset) * 14.0, 0.0, 2.0);
		float r = textureLod(screen_texture, uv_r, mip_lod).r;
		float g = textureLod(screen_texture, uv_g, mip_lod).g;
		float b = textureLod(screen_texture, uv_b, mip_lod).b;
		vec3 refracted_rgb = vec3(r, g, b);

		// Fake-normal specular rim sheen on steep liquid ridges and meniscus lip
		float norm_mag = length(refract_offset) / max(distortion_strength * strength_mult, 0.0001);
		float top_light = clamp(-refract_offset.y * 18.0 + refract_offset.x * 8.0 + 0.35, 0.0, 1.0);
		float rim_spec = (
			smoothstep(0.35, 1.2, norm_mag) * top_light * specular_intensity
			+ meniscus_band * 0.22
		) * total_coverage;

		// Subtle teal absorption inside thick wave crests
		float crest_thickness = clamp(h_c * sheet_mask + meniscus_band * 0.85, 0.0, 1.0);
		vec3 tinted_rgb = mix(
			refracted_rgb,
			water_tint.rgb * (dot(refracted_rgb, vec3(0.299, 0.587, 0.114)) + 0.25),
			crest_thickness * water_tint.a * total_coverage
		);

		// blend_disabled + alpha 1.0 guarantees 100% replacement of underlying viewport (0 ghosting)
		vec3 final_rgb = tinted_rgb + vec3(0.88, 0.96, 1.0) * rim_spec;
		COLOR = vec4(final_rgb, 1.0);
	}
}
