shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 smoke_color : source_color = vec4(0.78, 0.80, 0.83, 0.55);
uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform float swirl_speed : hint_range(0.0, 5.0) = 0.85;
uniform float softness : hint_range(0.05, 0.5) = 0.35;
uniform float proximity_fade_distance : hint_range(0.05, 2.0) = 0.35;

varying vec4 v_custom;

void vertex() {
	float seed_a = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	float seed_b = fract(sin(float(INSTANCE_ID) * 78.233) * 43758.5453);
	v_custom = vec4(INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.y, seed_a, seed_b);

	// Non-uniform aspect stretch per puff to break circular symmetry
	float scale_x = length(MODEL_MATRIX[0].xyz) * mix(0.78, 1.32, seed_a);
	float scale_y = length(MODEL_MATRIX[1].xyz) * mix(0.85, 1.38, seed_b);
	float scale_z = length(MODEL_MATRIX[2].xyz);

	// Preserve per-particle roll angle from INSTANCE_CUSTOM.x
	float angle = INSTANCE_CUSTOM.x;
	float s = sin(angle);
	float c = cos(angle);
	mat2 rot = mat2(vec2(c, s), vec2(-s, c));
	VERTEX.xy = rot * (VERTEX.xy * vec2(scale_x, scale_y));

	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(INV_VIEW_MATRIX[0].xyz), 0.0),
		vec4(normalize(INV_VIEW_MATRIX[1].xyz), 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz) * scale_z, 0.0),
		MODEL_MATRIX[3]
	);
}

void fragment() {
	float life_phase = clamp(v_custom.y, 0.0, 1.0);
	vec2 seed_offset = vec2(v_custom.z * 7.13, v_custom.w * 11.47);

	// First-pass low-frequency domain warp
	vec2 base_uv = UV * 1.15 + seed_offset;
	vec2 flow_a = vec2(TIME * swirl_speed * 0.09, -TIME * swirl_speed * 0.14);
	vec2 flow_b = vec2(-TIME * swirl_speed * 0.11, -TIME * swirl_speed * 0.08);
	float warp_x = texture(noise_texture, base_uv + flow_a).r - 0.5;
	float warp_y = texture(noise_texture, base_uv * 1.35 + vec2(0.37, 0.61) + flow_b).r - 0.5;
	vec2 domain_warp = vec2(warp_x, warp_y) * (0.55 + life_phase * 0.25);

	// Second-pass multi-octave noise sampling for irregular billowing lobes
	vec2 warped_uv = UV + domain_warp;
	float plume_core = texture(noise_texture, warped_uv * 1.1 + seed_offset + flow_a * 0.6).r;
	float plume_wisps = texture(noise_texture, warped_uv * 2.35 - seed_offset + flow_b * 1.3).r;
	float cellular_erosion = texture(noise_texture, (UV - domain_warp * 0.6) * 1.85 + seed_offset * 0.5).r;

	// Asymmetric, non-round coordinate distortion (creates stretched tendrils & lobes)
	vec2 p = (UV - vec2(0.5)) * 2.0;
	p.x += sin(p.y * 2.6 + v_custom.z * TAU) * 0.32 + warp_x * 0.55;
	p.y += cos(p.x * 2.2 + v_custom.w * TAU) * 0.28 + warp_y * 0.55;

	// Chebyshev quad-border safety guard so warped lobes never clip hard against quad edges
	float border_dist = max(abs(UV.x - 0.5), abs(UV.y - 0.5)) * 2.0;
	float quad_guard = smoothstep(0.98, 0.62, border_dist);

	// Carve irregular silhouette from domain-warped FBM & cellular erosion
	float organic_field = (plume_core * 0.55 + plume_wisps * 0.30 + cellular_erosion * 0.25);
	float irregular_falloff = clamp(1.0 - dot(p, p) * 0.58, 0.0, 1.0);
	float erosion_threshold = mix(0.22, 0.48, life_phase * (1.0 - softness * 0.5));
	float smoke_density = smoothstep(
		erosion_threshold,
		erosion_threshold + 0.38,
		organic_field * irregular_falloff
	) * quad_guard;

	// Internal volumetric grey sculpting: dark charcoal cores/undersides -> light ash wisps/tops
	float self_shadow = clamp(smoke_density * 0.65 + (1.0 - UV.y) * 0.35, 0.0, 1.0);
	float wisp_highlight = smoothstep(0.25, 0.78, plume_wisps) * UV.y;
	vec3 base_grey = COLOR.rgb * smoke_color.rgb;
	vec3 dark_fold_grey = base_grey * vec3(0.42, 0.44, 0.47);
	vec3 light_edge_grey = min(base_grey * vec3(1.32, 1.34, 1.36) + vec3(0.08), vec3(0.96));
	vec3 final_grey = mix(light_edge_grey, dark_fold_grey, self_shadow);
	final_grey = mix(final_grey, light_edge_grey, wisp_highlight * 0.45);

	// Soft depth proximity fade against floor and ventilator blades
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	float pixel_dist = (-upos.z / upos.w) + VERTEX.z;
	float proximity_fade = clamp(smoothstep(0.0, proximity_fade_distance, pixel_dist), 0.0, 1.0);

	ALBEDO = final_grey;
	ALPHA = clamp(smoke_density * smoke_color.a * COLOR.a * proximity_fade, 0.0, 1.0);
}
