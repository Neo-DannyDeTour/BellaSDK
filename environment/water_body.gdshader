shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx, depth_draw_always;

// --- GEOMETRY & TIME ---
group_uniforms Geometry_And_Time;
uniform float water_time = 0.0;
uniform vec3 water_size = vec3(10.0, 3.0, 10.0);
uniform bool show_side_walls = false;

// --- OPTICAL ABSORPTION & BEER'S LAW ---
group_uniforms Optical_Absorption;
uniform vec4 shallow_color : source_color = vec4(0.22, 0.65, 0.78, 1.0);
uniform vec4 deep_color : source_color = vec4(0.01, 0.05, 0.16, 1.0);
uniform vec3 absorption_coefficients = vec3(1.4, 0.42, 0.08);
uniform float depth_distance : hint_range(0.1, 50.0, 0.1) = 4.5;
uniform float beers_law : hint_range(0.1, 20.0, 0.1) = 2.2;

// --- GERSTNER WAVES ---
group_uniforms Gerstner_Waves;
uniform float wave_amplitude = 0.1;
uniform float wave_length = 4.5;
uniform float wave_speed = 1.4;
uniform float wave_steepness : hint_range(0.0, 1.0, 0.02) = 0.35;

// --- 3D INTERACTIVE RIPPLES ---
group_uniforms Interactive_Ripples;
const int MAX_RIPPLES = 16;
uniform vec4 ripples[16];
uniform float ripple_mesh_height = 0.22;
const float RIPPLE_SPEED = 3.0;
const float RIPPLE_WAVELENGTH = 1.0;
const float RIPPLE_LIFETIME = 2.5;

// --- SURFACE NORMALS & REORIENTED BLENDING ---
group_uniforms Normals_And_Details;
uniform sampler2D normal_map_1 : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D normal_map_2 : hint_normal, repeat_enable, filter_linear_mipmap;
uniform vec2 uv_scale = vec2(3.0, 3.0);
uniform float normal_bump_strength : hint_range(0.1, 4.0, 0.05) = 1.0;
uniform vec2 pan_speed_1 = vec2(0.025, 0.015);
uniform vec2 pan_speed_2 = vec2(-0.02, 0.03);

// --- REFLECTIONS & FRESNEL (HALF-LIFE 2 STYLE) ---
group_uniforms Reflections_And_Optics;
uniform bool enable_ssr = true;
uniform float ssr_max_distance : hint_range(0.5, 50.0, 0.5) = 25.0;
uniform float refraction_strength : hint_range(0.0, 0.1, 0.002) = 0.025;
uniform vec4 sky_reflection_tint : source_color = vec4(0.65, 0.82, 1.0, 1.0);
uniform float fresnel_base : hint_range(0.02, 0.5, 0.01) = 0.12;
uniform float fresnel_power : hint_range(1.0, 6.0, 0.1) = 3.5;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.025;
uniform float specular_strength : hint_range(0.0, 1.0, 0.01) = 0.8;
uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.12;

// --- SHORE & WAVE CREST FOAM ---
group_uniforms Foam;
uniform sampler2D foam_noise : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float foam_distance : hint_range(0.0, 2.0, 0.02) = 0.45;
uniform float crest_foam_threshold : hint_range(0.5, 1.2, 0.05) = 1.0;

// --- UNDERWATER CEILING ---
group_uniforms Underwater_View;
uniform vec4 underwater_ceiling_color : source_color = vec4(0.01, 0.07, 0.16, 1.0);

// --- SCREEN BUFFERS ---
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap, repeat_disable;

varying vec3 v_local_normal;
varying vec3 v_world_pos;
varying vec3 v_wave_normal;
varying float v_wave_height;

vec3 evaluate_gerstner_wave(vec2 dir, float amp, float len, float steep, vec2 pos, float time, inout vec3 wave_norm) {
	vec2 d = normalize(dir);
	float k = 6.2831853 / max(len, 0.01);
	float c = sqrt(9.8 / k);
	float phase = (d.x * pos.x + d.y * pos.y) * k + (time * c * 0.6);
	float q = steep / (k * amp * 3.0 + 0.0001);

	wave_norm.x -= d.x * k * amp * cos(phase);
	wave_norm.z -= d.y * k * amp * cos(phase);
	wave_norm.y -= q * k * amp * sin(phase);

	return vec3(-d.x * q * amp * cos(phase), amp * sin(phase), -d.y * q * amp * cos(phase));
}

float get_ripple_displacement(vec2 pos) {
	float total_h = 0.0;
	for (int i = 0; i < MAX_RIPPLES; i++) {
		float amp = ripples[i].w;
		if (amp <= 0.001) {
			continue;
		}

		vec2 center = ripples[i].xy;
		float elapsed = water_time - ripples[i].z;
		if (elapsed < 0.0 || elapsed > RIPPLE_LIFETIME) {
			continue;
		}

		float dist = distance(pos, center);
		float d_wave = dist - (elapsed * RIPPLE_SPEED);
		float spatial_envelope = exp(-0.5 * (d_wave * d_wave) / (RIPPLE_WAVELENGTH * 1.2));
		float time_decay = clamp(1.0 - (elapsed / RIPPLE_LIFETIME), 0.0, 1.0);
		float k = 6.2831853 / RIPPLE_WAVELENGTH;
		total_h += sin(k * d_wave) * amp * spatial_envelope * time_decay;
	}
	return total_h;
}

vec2 calculate_ripple_normals(vec2 pos) {
	vec2 total_grad = vec2(0.0);
	for (int i = 0; i < MAX_RIPPLES; i++) {
		float amp = ripples[i].w;
		if (amp <= 0.001) {
			continue;
		}

		vec2 center = ripples[i].xy;
		float elapsed = water_time - ripples[i].z;
		if (elapsed < 0.0 || elapsed > RIPPLE_LIFETIME) {
			continue;
		}

		float dist = distance(pos, center);
		float d_wave = dist - (elapsed * RIPPLE_SPEED);
		float spatial_envelope = exp(-0.5 * (d_wave * d_wave) / (RIPPLE_WAVELENGTH * 1.2));
		float time_decay = clamp(1.0 - (elapsed / RIPPLE_LIFETIME), 0.0, 1.0);
		float current_amp = amp * spatial_envelope * time_decay;
		float k = 6.2831853 / RIPPLE_WAVELENGTH;

		if (dist > 0.001) {
			vec2 dir = (pos - center) / dist;
			total_grad += dir * (k * cos(k * d_wave) * current_amp);
		}
	}
	return total_grad;
}

void vertex() {
	v_local_normal = NORMAL;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	if (NORMAL.y > 0.5) {
		float t = water_time * wave_speed;
		vec3 wave_norm_acc = vec3(0.0, 1.0, 0.0);

		vec3 gw1 = evaluate_gerstner_wave(vec2(1.0, 0.2), wave_amplitude, wave_length, wave_steepness, v_world_pos.xz, t, wave_norm_acc);
		vec3 gw2 = evaluate_gerstner_wave(vec2(-0.6, 0.8), wave_amplitude * 0.45, wave_length * 0.55, wave_steepness, v_world_pos.xz, t * 1.15, wave_norm_acc);
		vec3 gw3 = evaluate_gerstner_wave(vec2(0.3, -0.95), wave_amplitude * 0.2, wave_length * 0.35, wave_steepness, v_world_pos.xz, t * 0.8, wave_norm_acc);

		vec3 total_gw = gw1 + gw2 + gw3;
		float rip_disp = get_ripple_displacement(v_world_pos.xz) * ripple_mesh_height;

		VERTEX += total_gw + vec3(0.0, rip_disp, 0.0);
		v_world_pos += total_gw + vec3(0.0, rip_disp, 0.0);
		v_wave_height = total_gw.y + rip_disp;
		v_wave_normal = normalize(wave_norm_acc);
	} else {
		v_wave_height = 0.0;
		v_wave_normal = vec3(0.0, 1.0, 0.0);
	}
}

void fragment() {
	bool is_underwater = !FRONT_FACING;

	if (is_underwater) {
		if (v_local_normal.y < 0.5) {
			discard;
		}

		float view_dot = abs(dot(NORMAL, VIEW));
		float snells_window = smoothstep(0.08, 0.48, view_dot);
		vec2 ref_uv = clamp(SCREEN_UV + NORMAL.xy * 0.02 * snells_window, vec2(0.002), vec2(0.998));
		vec3 sky_view = textureLod(SCREEN_TEXTURE, ref_uv, 0.0).rgb;

		ALBEDO = mix(underwater_ceiling_color.rgb, sky_view, snells_window);
		ALPHA = 1.0;
		ROUGHNESS = 0.2;
		SPECULAR = 0.1;
	} else {
		if (v_local_normal.y < 0.5 && !show_side_walls) {
			discard;
		}

		// 1. Reoriented Normal Assembly
		vec2 surface_uv = (v_world_pos.xz / max(water_size.xz, vec2(1.0))) * uv_scale;
		vec2 uv_1 = surface_uv + water_time * pan_speed_1;
		vec2 uv_2 = surface_uv + water_time * pan_speed_2;

		vec3 n1 = texture(normal_map_1, uv_1).rgb * 2.0 - 1.0;
		vec3 n2 = texture(normal_map_2, uv_2).rgb * 2.0 - 1.0;
		vec3 micro_norm = normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
		micro_norm.xy *= normal_bump_strength;

		if (v_local_normal.y > 0.5) {
			vec2 rip_grad = calculate_ripple_normals(v_world_pos.xz);
			micro_norm.xy += rip_grad * 2.8;
		}
		micro_norm = normalize(micro_norm);

		vec3 world_normal = normalize(vec3(
			v_wave_normal.x + micro_norm.x,
			v_wave_normal.y * micro_norm.z,
			v_wave_normal.z + micro_norm.y
		));
		NORMAL = (VIEW_MATRIX * vec4(world_normal, 0.0)).xyz;

		// 2. Safe Refraction & Depth Calculation
		float raw_depth = textureLod(DEPTH_TEXTURE, SCREEN_UV, 0.0).r;
		vec4 ndc = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
		ndc.xyz /= ndc.w;
		float water_depth = max(0.0, -ndc.z - (-VERTEX.z));

		vec2 ref_offset = NORMAL.xy * refraction_strength * clamp(water_depth * 0.6, 0.0, 1.0);
		vec2 refr_uv = clamp(SCREEN_UV + ref_offset, vec2(0.002), vec2(0.998));

		float refr_raw_depth = textureLod(DEPTH_TEXTURE, refr_uv, 0.0).r;
		vec4 refr_ndc = INV_PROJECTION_MATRIX * vec4(refr_uv * 2.0 - 1.0, refr_raw_depth, 1.0);
		refr_ndc.xyz /= refr_ndc.w;
		if (-refr_ndc.z < -VERTEX.z) {
			refr_uv = SCREEN_UV;
		}

		float bg_r = textureLod(SCREEN_TEXTURE, clamp(refr_uv + ref_offset * 0.12, vec2(0.002), vec2(0.998)), 0.0).r;
		float bg_g = textureLod(SCREEN_TEXTURE, refr_uv, 0.0).g;
		float bg_b = textureLod(SCREEN_TEXTURE, clamp(refr_uv - ref_offset * 0.12, vec2(0.002), vec2(0.998)), 0.0).b;
		vec3 refracted_bg = vec3(bg_r, bg_g, bg_b);

		// 3. Beer-Lambert Absorption
		vec3 absorption = absorption_coefficients * beers_law;
		vec3 transmittance = exp(-absorption * (water_depth * 0.22));
		float depth_ratio = clamp(water_depth / max(depth_distance, 0.01), 0.0, 1.0);
		vec3 scattered_color = mix(shallow_color.rgb, deep_color.rgb, depth_ratio);
		vec3 underwater_scene = refracted_bg * transmittance + scattered_color * (vec3(1.0) - transmittance);

		// 4. Screen-Space Reflection Raymarch
		vec3 view_dir = normalize(-VERTEX);
		vec3 refl_dir = reflect(-view_dir, normalize(NORMAL));
		vec3 ssr_color = vec3(0.0);
		float ssr_weight = 0.0;

		if (enable_ssr && refl_dir.z < 0.0) {
			const int SSR_STEPS = 20; // 16 to 24 steps for clean 60 FPS performance
			float step_size = ssr_max_distance / float(SSR_STEPS);
			vec3 ray = VERTEX;

			for (int i = 1; i <= SSR_STEPS; i++) {
				ray += refl_dir * step_size;
				vec4 proj = PROJECTION_MATRIX * vec4(ray, 1.0);
				vec2 sample_uv = (proj.xy / proj.w) * 0.5 + 0.5;

				if (sample_uv.x < 0.002 || sample_uv.x > 0.998 || sample_uv.y < 0.002 || sample_uv.y > 0.998) {
					break;
				}

				float ray_depth_raw = textureLod(DEPTH_TEXTURE, sample_uv, 0.0).r;
				vec4 ray_ndc = INV_PROJECTION_MATRIX * vec4(sample_uv * 2.0 - 1.0, ray_depth_raw, 1.0);
				float sampled_z = ray_ndc.z / ray_ndc.w;
				float z_diff = sampled_z - ray.z;

				if (z_diff >= 0.0 && z_diff < step_size * 1.8) {
					vec2 edge_fade = smoothstep(vec2(0.0), vec2(0.15), sample_uv) * smoothstep(vec2(1.0), vec2(0.85), sample_uv);
					ssr_weight = edge_fade.x * edge_fade.y;
					ssr_color = textureLod(SCREEN_TEXTURE, sample_uv, 0.0).rgb;
					break;
				}
			}
		}

		// 5. Half-Life 2 Style Reflection Composite
		float ndotv = clamp(dot(normalize(NORMAL), view_dir), 0.0, 1.0);
		float fresnel = fresnel_base + (1.0 - fresnel_base) * pow(1.0 - ndotv, fresnel_power);
		vec3 env_reflection = mix(sky_reflection_tint.rgb, ssr_color, ssr_weight);
		vec3 surface_composite = mix(underwater_scene, env_reflection, fresnel);

		// 6. Shoreline & Crest Foam
		float shore_contact = 1.0 - smoothstep(0.0, max(foam_distance, 0.001), water_depth);
		float max_wave_h = wave_amplitude * (1.0 + 0.45 + 0.2);
		float crest_cutoff = max_wave_h * max(crest_foam_threshold, 0.85);
		float crest_foam = smoothstep(crest_cutoff, max_wave_h, v_wave_height);

		vec2 noise_uv = surface_uv * 3.5 + water_time * vec2(0.015, -0.012);
		float noise_tex = texture(foam_noise, noise_uv).r;
		float shore_foam = smoothstep(0.45, 0.7, shore_contact * (noise_tex * 1.2 + 0.1));
		float crest_bubbles = smoothstep(0.55, 0.85, crest_foam * (noise_tex * 1.8));
		float foam_blend = clamp(shore_foam + crest_bubbles, 0.0, 1.0);

		ALBEDO = mix(surface_composite, foam_color.rgb, foam_blend * foam_color.a);
		ROUGHNESS = mix(roughness, 0.65, foam_blend);
		SPECULAR = mix(specular_strength, 0.1, foam_blend);
		METALLIC = metallic;
	}
}
