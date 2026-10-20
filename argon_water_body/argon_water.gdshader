shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

const vec2 WAVE_DIR_0 = vec2(0.924678, 0.380749);
const vec2 WAVE_DIR_1 = vec2(-0.451481, 0.892281);
const vec2 WAVE_DIR_2 = vec2(0.319222, -0.947680);
const int MAX_RIPPLES = 16;

uniform float water_time = 0.0;

group_uniforms Waves;
uniform float wave_amplitude : hint_range(0.0, 2.0, 0.01) = 0.14;
uniform float wave_frequency : hint_range(0.1, 10.0, 0.05) = 1.15;
uniform float wave_speed : hint_range(0.0, 10.0, 0.05) = 1.6;
uniform float wave_steepness : hint_range(0.0, 1.0, 0.01) = 0.45;

group_uniforms Ripples;
uniform float ripple_frequency : hint_range(1.0, 30.0, 0.5) = 10.0;
uniform float ripple_speed : hint_range(0.5, 15.0, 0.1) = 4.5;
uniform float ripple_decay : hint_range(0.1, 10.0, 0.1) = 1.8;
uniform float ripple_spatial_decay : hint_range(0.1, 5.0, 0.05) = 0.85;
uniform vec4 ripples[16];

group_uniforms Optics_HL2;
uniform vec4 shallow_color : source_color = vec4(0.11, 0.27, 0.29, 1.0);
uniform vec4 deep_color : source_color = vec4(0.02, 0.06, 0.08, 1.0);
uniform float beer_factor : hint_range(0.05, 5.0, 0.05) = 0.75;
uniform float max_visibility_depth : hint_range(0.5, 20.0, 0.5) = 5.5;
uniform float refraction_strength : hint_range(0.0, 0.2, 0.005) = 0.04;
uniform float fresnel_power : hint_range(1.0, 10.0, 0.1) = 5.0;
uniform float roughness_val : hint_range(0.0, 1.0, 0.01) = 0.05;
uniform float specular_val : hint_range(0.0, 1.0, 0.01) = 0.85;

group_uniforms Surface_Normals;
uniform sampler2D normal_map_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale : hint_range(0.0, 2.0, 0.05) = 0.45;
uniform float normal_uv_scale : hint_range(0.01, 2.0, 0.01) = 0.14;
uniform vec2 normal_scroll_a = vec2(0.035, 0.025);
uniform vec2 normal_scroll_b = vec2(-0.028, 0.032);

group_uniforms Foam_Destiny;
uniform sampler2D foam_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 foam_color : source_color = vec4(0.88, 0.94, 0.96, 1.0);
uniform float foam_edge_distance : hint_range(0.05, 2.0, 0.05) = 0.42;
uniform float foam_crest_threshold : hint_range(0.1, 1.5, 0.05) = 0.65;
uniform float foam_intensity : hint_range(0.0, 2.0, 0.05) = 0.85;
uniform float foam_uv_scale : hint_range(0.05, 2.0, 0.05) = 0.28;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

varying vec3 v_world_pos;
varying float v_wave_height;
varying float v_ripple_foam;

float eval_octave(
	vec2 xz,
	vec2 dir,
	float amp,
	float freq,
	float spd,
	float steep,
	float t,
	inout vec2 grad
) {
	float phase = dot(dir, xz) * freq + t * spd;
	float s = sin(phase);
	float c = cos(phase);
	float u = phase + steep * c;
	float du_dphase = 1.0 - steep * s;
	float dh_dphase = amp * cos(u) * du_dphase;
	grad += dir * (dh_dphase * freq);
	return amp * sin(u);
}

float eval_waves_and_ripples(
	vec2 xz,
	float t,
	out vec2 total_grad,
	out float ripple_foam_accum
) {
	total_grad = vec2(0.0);
	ripple_foam_accum = 0.0;
	float h = 0.0;

	h += eval_octave(
		xz, WAVE_DIR_0, wave_amplitude, wave_frequency,
		wave_speed, wave_steepness, t, total_grad
	);
	h += eval_octave(
		xz, WAVE_DIR_1, wave_amplitude * 0.5, wave_frequency * 1.85,
		wave_speed * 1.35, wave_steepness * 0.8, t, total_grad
	);
	h += eval_octave(
		xz, WAVE_DIR_2, wave_amplitude * 0.25, wave_frequency * 3.4,
		wave_speed * 1.75, wave_steepness * 0.6, t, total_grad
	);

	for (int i = 0; i < MAX_RIPPLES; i++) {
		vec4 r = ripples[i];
		if (r.w > 0.001) {
			float age = t - r.z;
			if (age >= 0.0 && age < 4.0) {
				vec2 delta = xz - r.xy;
				float dist = sqrt(dot(delta, delta) + 0.0001);
				float radius = age * ripple_speed;
				if (dist < radius) {
					float front = clamp(1.0 - dist / max(radius, 0.001), 0.0, 1.0);
					float env = r.w * exp(-age * ripple_decay) * exp(-dist * ripple_spatial_decay) * front;
					float r_phase = (dist - radius) * ripple_frequency;
					float sr = sin(r_phase);
					float cr = cos(r_phase);
					h += sr * env;
					vec2 r_dir = delta / dist;
					total_grad += r_dir * (cr * ripple_frequency * env);
					ripple_foam_accum += clamp(abs(sr) * env * 2.2, 0.0, 1.0);
				}
			}
		}
	}
	return h;
}

void vertex() {
	float t = water_time > 0.0 ? water_time : TIME;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (VERTEX.y > 0.0) {
		vec2 grad = vec2(0.0);
		float r_foam = 0.0;
		float h = eval_waves_and_ripples(world_pos.xz, t, grad, r_foam);
		VERTEX.y += h;
		world_pos.y += h;
		vec3 world_n = normalize(vec3(-grad.x, 1.0, -grad.y));
		vec3 world_t = normalize(vec3(1.0, grad.x, 0.0));
		vec3 world_b = normalize(cross(world_n, world_t));
		NORMAL = normalize((transpose(MODEL_MATRIX) * vec4(world_n, 0.0)).xyz);
		TANGENT = normalize((transpose(MODEL_MATRIX) * vec4(world_t, 0.0)).xyz);
		BINORMAL = normalize((transpose(MODEL_MATRIX) * vec4(world_b, 0.0)).xyz);
		v_wave_height = h;
		v_ripple_foam = clamp(r_foam, 0.0, 1.0);
	} else {
		v_wave_height = 0.0;
		v_ripple_foam = 0.0;
	}
	v_world_pos = world_pos;
}

void fragment() {
	float t = water_time > 0.0 ? water_time : TIME;
	vec2 uv_a = v_world_pos.xz * normal_uv_scale + normal_scroll_a * t;
	vec2 uv_b = v_world_pos.xz * (normal_uv_scale * 1.37) + normal_scroll_b * t;

	vec3 n_a = texture(normal_map_a, uv_a).rgb * 2.0 - 1.0;
	vec3 n_b = texture(normal_map_b, uv_b).rgb * 2.0 - 1.0;
	vec3 detail_n = normalize(vec3((n_a.xy + n_b.xy) * normal_scale, n_a.z * n_b.z));
	NORMAL_MAP = detail_n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	vec2 ref_ofs = detail_n.xy * refraction_strength;
	float raw_depth = texture(depth_texture, SCREEN_UV + ref_ofs).r;
	vec4 ndc = vec4((SCREEN_UV + ref_ofs) * 2.0 - 1.0, raw_depth, 1.0);
	vec4 view_p = INV_PROJECTION_MATRIX * ndc;
	view_p.xyz /= view_p.w;
	float linear_scene_depth = -view_p.z;
	float surface_depth = -VERTEX.z;
	float water_depth = linear_scene_depth - surface_depth;

	vec2 final_uv = SCREEN_UV + ref_ofs;
	if (water_depth < 0.0) {
		final_uv = SCREEN_UV;
		float fallback_raw = texture(depth_texture, SCREEN_UV).r;
		vec4 fb_ndc = vec4(SCREEN_UV * 2.0 - 1.0, fallback_raw, 1.0);
		vec4 fb_view = INV_PROJECTION_MATRIX * fb_ndc;
		fb_view.xyz /= fb_view.w;
		water_depth = max(-fb_view.z - surface_depth, 0.0);
	}

	vec3 screen_col = textureLod(screen_texture, final_uv, 0.0).rgb;
	float transmittance = exp(-water_depth * beer_factor);
	float depth_blend = clamp(water_depth / max(max_visibility_depth, 0.1), 0.0, 1.0);
	vec3 water_tint = mix(shallow_color.rgb, deep_color.rgb, depth_blend);
	vec3 refracted = mix(water_tint, screen_col * shallow_color.rgb, transmittance);

	vec2 f_uv1 = v_world_pos.xz * foam_uv_scale + normal_scroll_a * (t * 0.6);
	vec2 f_uv2 = v_world_pos.xz * (foam_uv_scale * 1.4) - normal_scroll_b * (t * 0.5);
	float f_noise = (texture(foam_noise, f_uv1).r + texture(foam_noise, f_uv2).r) * 0.5;

	float edge_factor = 1.0 - clamp(water_depth / max(foam_edge_distance, 0.01), 0.0, 1.0);
	float shore_foam = smoothstep(0.35, 0.78, edge_factor * (f_noise + 0.35));

	float max_amp = max(wave_amplitude * 1.75, 0.001);
	float norm_crest = clamp(v_wave_height / max_amp, 0.0, 1.0);
	float crest_foam = smoothstep(foam_crest_threshold, 1.0, norm_crest) * smoothstep(0.3, 0.8, f_noise);

	float ripple_foam = v_ripple_foam * smoothstep(0.25, 0.75, f_noise);
	float total_foam = clamp((shore_foam + crest_foam + ripple_foam) * foam_intensity, 0.0, 1.0);

	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - ndotv, fresnel_power);
	if (!FRONT_FACING) {
		fresnel = pow(1.0 - ndotv, 2.5);
	}

	vec3 surface_col = mix(refracted, deep_color.rgb * 0.45, fresnel * 0.55);
	ALBEDO = mix(surface_col, foam_color.rgb, total_foam);
	ROUGHNESS = mix(roughness_val, 0.75, total_foam);
	SPECULAR = mix(specular_val, 0.15, total_foam);
	METALLIC = mix(clamp(fresnel * 0.35, 0.0, 0.35), 0.0, total_foam);
}
