shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Volume & Geometry
uniform vec3 water_size = vec3(1.0, 1.0, 1.0);
uniform bool show_side_walls = false;

// Wave Simulation
uniform float water_time = 0.0;
uniform float wave_amplitude = 0.1;
uniform float wave_length = 4.5;
uniform float wave_speed = 1.4;
uniform float wave_steepness = 0.35;
uniform float gerstner_horizontal_scale = 0.45;
uniform float ripple_mesh_height = 0.22;
uniform float ripple_size = 1.0;
uniform vec4 ripples[16];

// Optics, Absorption & HL2 Fog
uniform vec4 shallow_color : source_color = vec4(0.22, 0.65, 0.78, 1.0);
uniform vec4 deep_color : source_color = vec4(0.01, 0.05, 0.16, 1.0);
uniform vec4 underwater_ceiling_color : source_color = vec4(0.0, 0.1, 0.2, 1.0);
uniform float underwater_fog_begin = 0.5;
uniform float underwater_fog_end = 28.0;
uniform vec3 absorption_coefficients = vec3(1.4, 0.42, 0.08);
uniform vec3 depth_color_consumption = vec3(22.0, 133.0, 168.0);
uniform float depth_distance = 4.5;
uniform float beers_law = 2.2;
uniform vec4 crest_color : source_color = vec4(0.0, 0.65, 0.85, 1.0);
uniform float crest_glow_intensity = 0.25;
uniform float aerated_foam_glow = 0.45;
uniform float caustics_intensity = 0.45;
uniform float caustics_scale = 0.65;

// Reflections & Surface Detail
uniform bool enable_ssr = true;
uniform float ssr_max_distance = 4.5;
uniform float refraction_strength = 0.025;
uniform float chromatic_aberration = 0.015;
uniform vec4 sky_reflection_tint : source_color = vec4(0.65, 0.82, 1.0, 1.0);
uniform float fresnel_base = 0.02;
uniform float fresnel_power = 4.5;
uniform float roughness = 0.03;
uniform float specular_strength = 0.6;
uniform float metallic = 0.0;
uniform vec2 uv_scale = vec2(2.0, 2.0);
uniform float normal_bump_strength = 1.6;
uniform vec2 pan_speed_1 = vec2(0.1, 0.01);
uniform vec2 pan_speed_2 = vec2(-0.015, 0.025);

// Foam
uniform sampler2D foam_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 foam_color : source_color = vec4(0.92, 0.96, 1.0, 1.0);
uniform float foam_distance = 0.35;
uniform float crest_foam_threshold = 0.72;

varying vec3 v_world_pos;
varying vec2 v_macro_slope;
varying float v_wave_height;
varying float v_is_top_face;

const float TAU_CONST = 6.28318530718;

// 8 aperiodic wave directions, irrational wavelength ratios, and golden-angle phases
const vec2 MACRO_DIRS[8] = vec2[8](
	vec2(0.848, 0.530),
	vec2(-0.422, 0.906),
	vec2(0.259, -0.966),
	vec2(-0.934, -0.358),
	vec2(0.616, -0.788),
	vec2(-0.174, 0.985),
	vec2(0.978, -0.208),
	vec2(-0.743, 0.669)
);
const float MACRO_AMP_SCALES[8] = float[8](0.36, 0.25, 0.17, 0.12, 0.08, 0.055, 0.038, 0.025);
const float MACRO_LEN_SCALES[8] = float[8](1.00, 0.73, 0.51, 0.37, 0.26, 0.19, 0.13, 0.09);
const float MACRO_SPD_SCALES[8] = float[8](1.00, 1.17, 1.38, 1.61, 1.89, 2.18, 2.53, 2.94);
const float MACRO_PHASES[8] = float[8](0.00, 2.39996, 4.79992, 0.91670, 3.31666, 5.71662, 1.83340, 4.23336);

// 2D rotation helper to break axis alignment on all procedural octaves
vec2 rotate2d(vec2 p, float a) {
	float s = sin(a);
	float c = cos(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Isotropic 8-wave sharp-crest capillary interference + domain-warped cross-chop (zero X/Z grid)
vec2 compute_capillary_slope(vec2 xz, float dist) {
	vec2 wind_bias = normalize(pan_speed_1 + pan_speed_2 + vec2(0.001));
	float freq_base = 5.4 * max(uv_scale.x, 0.25);
	float speed_base = 2.5 * max(wave_speed, 0.2);

	// Dual rotated domain warp so capillary wave packets curve and break naturally
	vec2 w1 = rotate2d(xz, 0.61) * 1.35 + vec2(water_time * 0.65, -water_time * 0.52);
	vec2 w2 = rotate2d(xz, 2.18) * 2.75 + vec2(-water_time * 0.85, water_time * 0.71);
	vec2 warp = (vec2(sin(w1.y) + cos(w2.y), cos(w1.x) + sin(w2.x))) * 0.28;

	vec2 slope = vec2(0.0);
	float freq = freq_base;
	float amp = 0.115;
	float spd = speed_base;
	float angle = 0.43;

	for (int i = 0; i < 8; i++) {
		vec2 dir = normalize(vec2(cos(angle), sin(angle)) + wind_bias * 0.2);
		float phase = dot(dir, xz + warp) * freq + water_time * spd + float(i) * 2.39996;
		float s = sin(phase);
		float c = cos(phase);
		float w = exp(s - 1.0);
		slope += dir * (amp * freq * w * c);

		// Secondary rotated harmonic packet (71 deg offset) so cells never form squares
		vec2 dir2 = rotate2d(dir, 1.24);
		float phase2 = dot(dir2, xz - warp * 0.85) * (freq * 1.17) - water_time * (spd * 0.91) + float(i) * 1.73;
		float w2_crest = exp(sin(phase2) - 1.0);
		slope += dir2 * (amp * 0.72 * freq * w2_crest * cos(phase2));

		angle += 2.39996323;
		freq *= 1.23;
		amp *= 0.77;
		spd *= 1.13;
	}

	float micro_atten = max(exp(-dist * 0.022), 0.01);
	return slope * normal_bump_strength * micro_atten;
}

// 8-wave golden-angle trochoidal/Gerstner cascade (matches CPU get_wave_height_at_pos)
vec3 evaluate_wave_cascade(vec2 xz, out vec2 gerstner_xz) {
	float h = 0.0;
	vec2 slope = vec2(0.0);
	gerstner_xz = vec2(0.0);

	// Slow organic wave-group envelope modulation so swells rise & fade aperiodically
	vec2 env_p1 = rotate2d(xz, 0.52) * (0.42 / max(wave_length, 0.5)) + vec2(water_time * 0.12, -water_time * 0.09);
	vec2 env_p2 = rotate2d(xz, 1.94) * (0.67 / max(wave_length, 0.5)) + vec2(-water_time * 0.08, water_time * 0.14);
	float group_env = 0.72 + 0.28 * sin(env_p1.x + cos(env_p1.y)) * cos(env_p2.y - sin(env_p2.x));

	float stp_base = clamp(wave_steepness, 0.0, 2.0) * 0.45;

	for (int i = 0; i < 8; i++) {
		float amp = wave_amplitude * MACRO_AMP_SCALES[i] * group_env;
		float wl = max(wave_length * MACRO_LEN_SCALES[i], 0.05);
		float k = TAU_CONST / wl;
		float spd = wave_speed * MACRO_SPD_SCALES[i];
		float stp = stp_base * (1.0 - float(i) * 0.07);
		vec2 d = MACRO_DIRS[i];

		float theta = dot(d, xz) * k + water_time * spd * k + MACRO_PHASES[i];
		float s1 = sin(theta);
		float c1 = cos(theta);
		float s2 = sin(2.0 * theta);
		float c2 = cos(2.0 * theta);

		h += amp * (s1 + 0.5 * stp * s2);
		float d_h = amp * k * (c1 + stp * c2);
		slope += d * d_h;
		gerstner_xz -= d * (amp * stp * gerstner_horizontal_scale * c1);
	}
	return vec3(h, slope.x, slope.y);
}

// Returns vec3(height_y, slope_dx, slope_dz) for 16-slot interactive ripples
vec3 evaluate_ripples(vec2 xz, bool include_capillary) {
	float total_h = 0.0;
	vec2 total_slope = vec2(0.0);
	float r_scale = max(ripple_size, 0.1);
	float speed = 3.2 * r_scale;
	float sigma = 0.45 * r_scale;
	float k = 14.0 / r_scale;

	for (int i = 0; i < 16; i++) {
		vec4 r = ripples[i];
		if (r.w <= 0.0001) {
			continue;
		}
		float age = water_time - r.z;
		if (age < 0.0 || age > 4.5) {
			continue;
		}
		vec2 delta = xz - r.xy;
		float dist = length(delta);
		float radius = age * speed;
		float diff = dist - radius;
		float env = exp(-(diff * diff) / (2.0 * sigma * sigma));
		float decay = exp(-age * 1.15) * (1.0 - age / 4.5);
		float amp = r.w * ripple_mesh_height * decay;
		float phase = diff * k;
		float h = amp * env * cos(phase);
		total_h += h;

		if (dist > 0.001) {
			vec2 dir = delta / dist;
			float d_env = -diff / (sigma * sigma);
			float d_cos = -k * sin(phase);
			float dh_dr = amp * env * (d_env * cos(phase) + d_cos);
			if (include_capillary) {
				dh_dr += amp * env * (-k * 2.3 * sin(phase * 2.3)) * 0.35;
			}
			total_slope += dir * dh_dr;
		}
	}
	return vec3(total_h, total_slope.x, total_slope.y);
}

void vertex() {
	v_is_top_face = step(0.5, NORMAL.y);

	vec3 scaled_vertex = VERTEX * water_size;
	vec4 world_base = MODEL_MATRIX * vec4(scaled_vertex, 1.0);

	vec2 gerstner_xz = vec2(0.0);
	vec3 wave_data = evaluate_wave_cascade(world_base.xz, gerstner_xz);
	vec3 ripple_data = evaluate_ripples(world_base.xz, false);

	float disp_y = wave_data.x + ripple_data.x;
	float top_mask = step(-0.01, VERTEX.y);
	if (top_mask > 0.5) {
		world_base.xz += gerstner_xz;
		world_base.xyz += MODEL_MATRIX[1].xyz * disp_y;
	}

	VERTEX = (inverse(MODEL_MATRIX) * world_base).xyz;
	v_world_pos = world_base.xyz;
	v_wave_height = disp_y;
	v_macro_slope = wave_data.yz + ripple_data.yz;
}

// Isotropic multi-angle cellular interference caustics (no X/Z square grid)
float compute_caustics(vec2 world_xz) {
	float sc = caustics_scale * 2.4;
	vec2 p0 = rotate2d(world_xz, 0.31) * sc + vec2(water_time * 0.45, -water_time * 0.32);
	vec2 p1 = rotate2d(world_xz, 1.48) * (sc * 1.29) + vec2(-water_time * 0.38, water_time * 0.51);
	vec2 p2 = rotate2d(world_xz, 2.71) * (sc * 1.67) + vec2(water_time * 0.29, water_time * 0.41);

	float w0 = abs(sin(p0.x + cos(p0.y * 1.15)) + cos(p0.y + sin(p0.x * 1.15)));
	float w1 = abs(sin(p1.x + cos(p1.y * 1.15)) + cos(p1.y + sin(p1.x * 1.15)));
	float w2 = abs(sin(p2.x + cos(p2.y * 1.15)) + cos(p2.y + sin(p2.x * 1.15)));

	float ridge = min(min(w0, w1), w2);
	float c = pow(clamp(1.0 - ridge * 0.75, 0.0, 1.0), 4.5);
	return c * caustics_intensity;
}

// Directional sky dome + horizon scatter fallback when SSR misses
vec3 evaluate_sky_fallback(vec3 world_refl_dir) {
	float up = clamp(world_refl_dir.y, 0.0, 1.0);
	vec3 horizon = mix(sky_reflection_tint.rgb, vec3(0.88, 0.94, 1.0), 0.45);
	vec3 zenith = sky_reflection_tint.rgb * vec3(0.48, 0.68, 0.95);
	vec3 sky = mix(horizon, zenith, pow(up, 0.55));
	// Soft upper-hemisphere cloud/sky luminance variation
	vec2 sky_uv = world_refl_dir.xz / max(world_refl_dir.y + 0.35, 0.15);
	float cloud = 0.5 + 0.5 * sin(sky_uv.x * 1.4 + water_time * 0.04) * cos(sky_uv.y * 1.4 - water_time * 0.03);
	return sky * mix(0.88, 1.12, cloud * up);
}

vec3 raymarch_ssr(
	vec3 view_pos,
	vec3 view_normal,
	vec3 world_refl_dir,
	mat4 proj_matrix,
	mat4 inv_proj,
	out float hit_alpha
) {
	hit_alpha = 0.0;
	vec3 sky_col = evaluate_sky_fallback(world_refl_dir);
	if (!enable_ssr) {
		return sky_col;
	}
	vec3 view_dir = normalize(view_pos);
	vec3 refl_dir = reflect(view_dir, view_normal);
	if (refl_dir.z >= 0.05) {
		return sky_col;
	}

	float step_len = ssr_max_distance / 12.0;
	vec3 ray_pos = view_pos + view_normal * 0.04;

	for (int i = 0; i < 12; i++) {
		ray_pos += refl_dir * step_len;
		vec4 clip = proj_matrix * vec4(ray_pos, 1.0);
		if (clip.w <= 0.001) {
			break;
		}
		vec2 uv = (clip.xy / clip.w) * 0.5 + 0.5;
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			break;
		}
		float raw_depth = textureLod(depth_texture, uv, 0.0).r;
		if (raw_depth >= 0.9999) {
			continue;
		}
		vec4 scene_ndc = vec4(uv * 2.0 - 1.0, raw_depth, 1.0);
		vec4 scene_view = inv_proj * scene_ndc;
		scene_view.xyz /= scene_view.w;

		float depth_delta = ray_pos.z - scene_view.z;
		if (depth_delta > 0.02 && depth_delta < step_len * 2.2) {
			vec2 edge_dist = min(uv, 1.0 - uv);
			float edge_fade = smoothstep(0.0, 0.12, min(edge_dist.x, edge_dist.y));
			float step_fade = 1.0 - float(i) / 12.0;
			hit_alpha = edge_fade * step_fade;
			return textureLod(screen_texture, uv, roughness * 3.0).rgb;
		}
	}
	return sky_col;
}

void fragment() {
	if (!show_side_walls && FRONT_FACING && v_is_top_face < 0.5) {
		discard;
	}

	float view_dist = length(VERTEX);
	vec2 sample_xz = v_is_top_face > 0.5
		? v_world_pos.xz
		: (v_world_pos.xz + vec2(v_world_pos.y * 0.7, -v_world_pos.y * 0.7));

	vec2 dummy_g = vec2(0.0);
	vec3 pixel_wave = evaluate_wave_cascade(sample_xz, dummy_g)
		+ evaluate_ripples(sample_xz, true);

	float macro_atten = max(exp(-view_dist * 0.008), 0.15);
	vec2 macro_slope = pixel_wave.yz * macro_atten;
	vec2 micro_slope = compute_capillary_slope(sample_xz, view_dist);
	vec2 total_slope = macro_slope + micro_slope;

	vec3 world_normal = normalize(vec3(-total_slope.x, 1.0, -total_slope.y));
	if (v_is_top_face < 0.5) {
		vec3 geom_world_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		world_normal = normalize(geom_world_n + vec3(total_slope.x, 0.0, total_slope.y) * 0.35);
	}
	if (!FRONT_FACING) {
		world_normal = -world_normal;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

	// Linear scene depth reconstruction
	float raw_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	scene_view.xyz /= scene_view.w;
	float surface_linear_depth = -VERTEX.z;
	float scene_linear_depth = -scene_view.z;
	float water_depth_diff = max(scene_linear_depth - surface_linear_depth, 0.0);

	if (!FRONT_FACING) {
		float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float snell_mask = smoothstep(0.52, 0.72, ndotv);

		vec2 refract_offset = NORMAL.xy * refraction_strength * 1.5;
		vec2 uv_r = clamp(SCREEN_UV + refract_offset * (1.0 + chromatic_aberration), 0.001, 0.999);
		vec2 uv_g = clamp(SCREEN_UV + refract_offset, 0.001, 0.999);
		vec2 uv_b = clamp(SCREEN_UV + refract_offset * (1.0 - chromatic_aberration), 0.001, 0.999);
		vec3 sky_refract = vec3(
			textureLod(screen_texture, uv_r, 0.0).r,
			textureLod(screen_texture, uv_g, 0.0).g,
			textureLod(screen_texture, uv_b, 0.0).b
		);

		vec3 tir_color = mix(deep_color.rgb, underwater_ceiling_color.rgb, 0.65);
		vec3 ceiling_col = mix(tir_color, sky_refract, snell_mask);

		float lin_fog = clamp(
			(view_dist - underwater_fog_begin) / max(underwater_fog_end - underwater_fog_begin, 0.1),
			0.0,
			1.0
		);
		float fog_factor = mix(lin_fog, lin_fog * lin_fog, 0.35);
		vec3 hl2_fog_col = mix(deep_color.rgb, underwater_ceiling_color.rgb, 0.5);

		ALBEDO = mix(ceiling_col, hl2_fog_col, fog_factor);
		ROUGHNESS = roughness;
		METALLIC = 0.0;
		SPECULAR = specular_strength * 0.5;
		ALPHA = 1.0;
	} else {
		float depth_fade = clamp(water_depth_diff * 0.5, 0.0, 1.0);
		vec2 refract_offset = NORMAL.xy * refraction_strength * depth_fade;
		vec2 uv_r = clamp(SCREEN_UV + refract_offset * (1.0 + chromatic_aberration), 0.001, 0.999);
		vec2 uv_g = clamp(SCREEN_UV + refract_offset, 0.001, 0.999);
		vec2 uv_b = clamp(SCREEN_UV + refract_offset * (1.0 - chromatic_aberration), 0.001, 0.999);

		float refr_raw_depth = textureLod(depth_texture, uv_g, 0.0).r;
		vec4 refr_view = INV_PROJECTION_MATRIX * vec4(uv_g * 2.0 - 1.0, refr_raw_depth, 1.0);
		refr_view.xyz /= refr_view.w;
		float refracted_linear_depth = -refr_view.z;

		float optical_depth = max(refracted_linear_depth - surface_linear_depth, 0.0);
		if (refracted_linear_depth < surface_linear_depth) {
			uv_r = SCREEN_UV;
			uv_g = SCREEN_UV;
			uv_b = SCREEN_UV;
			optical_depth = water_depth_diff;
			refr_view = scene_view;
		}

		vec3 screen_col = vec3(
			textureLod(screen_texture, uv_r, 0.0).r,
			textureLod(screen_texture, uv_g, 0.0).g,
			textureLod(screen_texture, uv_b, 0.0).b
		);

		if (refr_raw_depth < 0.9999 && optical_depth > 0.01) {
			vec3 scene_world = (INV_VIEW_MATRIX * vec4(refr_view.xyz, 1.0)).xyz;
			float c_val = compute_caustics(scene_world.xz);
			float c_atten = exp(-optical_depth * 0.35) * smoothstep(0.0, 0.25, optical_depth);
			screen_col += shallow_color.rgb * c_val * c_atten;
		}

		float scaled_depth = optical_depth / max(depth_distance, 0.1);
		vec3 beers_transmittance = exp(-absorption_coefficients * scaled_depth * beers_law);
		vec3 channel_fade = vec3(
			1.0 - smoothstep(0.0, max(depth_color_consumption.r, 0.1), optical_depth),
			1.0 - smoothstep(0.0, max(depth_color_consumption.g, 0.1), optical_depth),
			1.0 - smoothstep(0.0, max(depth_color_consumption.b, 0.1), optical_depth)
		);
		vec3 transmittance = beers_transmittance * mix(vec3(1.0), channel_fade, 0.45);
		float scatter_blend = exp(-scaled_depth * beers_law);
		vec3 volume_scatter = mix(deep_color.rgb, shallow_color.rgb, scatter_blend);
		vec3 refracted_water = mix(volume_scatter, screen_col * transmittance * 0.85, clamp(transmittance, 0.0, 1.0));

		float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float f0_pbr = 0.02;
		float pbr_fresnel = f0_pbr + (max(1.0 - roughness, f0_pbr) - f0_pbr) * pow(1.0 - ndotv, 5.0);
		float custom_fresnel = fresnel_base + (1.0 - fresnel_base) * pow(1.0 - ndotv, fresnel_power);
		float fresnel = clamp(max(pbr_fresnel, custom_fresnel * 0.85), 0.0, 1.0);

		vec3 world_view = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		vec3 world_refl = reflect(-world_view, world_normal);
		float ssr_hit = 0.0;
		vec3 ssr_color = raymarch_ssr(
			VERTEX,
			NORMAL,
			world_refl,
			PROJECTION_MATRIX,
			INV_PROJECTION_MATRIX,
			ssr_hit
		);
		vec3 sky_fallback = evaluate_sky_fallback(world_refl);
		vec3 reflection_col = mix(sky_fallback, ssr_color, ssr_hit);

		vec3 water_col = mix(refracted_water, reflection_col, fresnel);

		// Aperiodic turbulent foam & crest breakup (no glowing blobs on every peak)
		vec2 f_rot1 = rotate2d(sample_xz, 0.41) * uv_scale * 0.35 + vec2(water_time * 0.03, -water_time * 0.02);
		vec2 f_rot2 = rotate2d(sample_xz, 2.07) * uv_scale * 0.62 + vec2(-water_time * 0.025, water_time * 0.035);
		float foam_pattern = mix(texture(foam_noise, f_rot1).r, texture(foam_noise, f_rot2).r, 0.5);

		float shore_ratio = (v_is_top_face > 0.5)
			? (1.0 - clamp(water_depth_diff / max(foam_distance, 0.001), 0.0, 1.0))
			: 0.0;
		float shore_foam = smoothstep(0.35, 0.85, shore_ratio * (0.55 + foam_pattern * 0.75));

		float slope_steepness = length(macro_slope);
		float norm_crest = clamp(v_wave_height / max(wave_amplitude * 0.85, 0.01), 0.0, 2.0);
		float crest_mask = smoothstep(crest_foam_threshold, crest_foam_threshold + 0.55, norm_crest * (0.55 + foam_pattern * 0.75))
			* smoothstep(0.08, 0.35, slope_steepness);
		float crest_foam = crest_mask * smoothstep(0.45, 0.8, foam_pattern);

		float ripple_delta = length(pixel_wave.yz - v_macro_slope);
		float ripple_foam = smoothstep(0.25, 0.95, ripple_delta * 0.6) * smoothstep(0.3, 0.7, foam_pattern);

		float total_foam = clamp((shore_foam + crest_foam + ripple_foam) * foam_color.a, 0.0, 1.0);
		if (v_is_top_face < 0.5) {
			total_foam = 0.0;
		}

		// Subtle SSS restricted to thin turbulent wave peaks rather than every wave dome
		float crest_sss = crest_mask * crest_glow_intensity;
		float foam_sss = total_foam * aerated_foam_glow;
		vec3 final_albedo = mix(water_col, foam_color.rgb, total_foam);
		final_albedo += crest_color.rgb * (crest_sss * 0.22 + foam_sss * 0.28);

		ALBEDO = final_albedo;
		EMISSION = crest_color.rgb * (crest_sss * 0.08 + foam_sss * 0.14);
		ROUGHNESS = mix(roughness, 0.65, total_foam);
		METALLIC = metallic * (1.0 - total_foam);
		SPECULAR = specular_strength;

		if (!show_side_walls && v_is_top_face > 0.5) {
			ALPHA = smoothstep(0.0, 0.25, water_depth_diff);
		} else {
			ALPHA = 1.0;
		}
	}
}

void light() {
	vec3 h = normalize(LIGHT + VIEW);
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float ndoth = max(dot(NORMAL, h), 0.0);
	float ndotv = max(dot(NORMAL, VIEW), 0.001);
	float vdoth = max(dot(VIEW, h), 0.0);

	float a = max(ROUGHNESS * ROUGHNESS, 0.002);
	float a2 = a * a;
	float denom = (ndoth * ndoth * (a2 - 1.0) + 1.0);
	float d = a2 / (3.14159265 * denom * denom);

	float k = ((ROUGHNESS + 1.0) * (ROUGHNESS + 1.0)) / 8.0;
	float g_v = ndotv / (ndotv * (1.0 - k) + k);
	float g_l = ndotl / (ndotl * (1.0 - k) + k);
	float g = g_v * g_l;

	float f0 = mix(0.02, 0.8, METALLIC);
	float f = f0 + (1.0 - f0) * pow(1.0 - vdoth, 5.0);

	float spec = (d * g * f) / max(4.0 * ndotv * ndotl, 0.001);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * ndotl * spec * specular_strength * 2.0;

	float backscatter = pow(clamp(dot(LIGHT, -VIEW), 0.0, 1.0), 4.0) * g_v;
	vec3 sss_term = crest_color.rgb * backscatter * crest_glow_intensity * 0.5;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (ALBEDO * ndotl + sss_term);
}
