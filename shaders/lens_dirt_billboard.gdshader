shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D dirt_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

uniform float falloff_power : hint_range(0.5, 8.0) = 2.0;
uniform float vignette_inner : hint_range(0.0, 1.0) = 0.4;
uniform float vignette_outer : hint_range(0.1, 2.0) = 1.1;
uniform float dirt_strength : hint_range(0.0, 5.0) = 2.0;
uniform float proximity_fade_distance : hint_range(0.01, 5.0) = 0.5;
uniform float distance_fade_min : hint_range(0.0, 10.0) = 0.0;
uniform float distance_fade_max : hint_range(0.0, 20.0) = 0.0;

instance uniform vec4 light_color : source_color = vec4(1.0, 0.9, 0.7, 1.0);
instance uniform float intensity : hint_range(0.0, 1.0) = 0.01;

void vertex() {
	// Full camera-facing billboard preserving instance/node scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(normalize(INV_VIEW_MATRIX[0].xyz), 0.0),
			vec4(normalize(INV_VIEW_MATRIX[1].xyz), 0.0),
			vec4(normalize(INV_VIEW_MATRIX[2].xyz), 0.0),
			MODEL_MATRIX[3]
	);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0)
	);
}

void fragment() {
	// 1. Aspect-corrected screen-space coordinates.
	float aspect = VIEWPORT_SIZE.x / max(VIEWPORT_SIZE.y, 1.0);
	vec2 center_uv = (SCREEN_UV - vec2(0.5)) * vec2(aspect, 1.0);
	float radial_dist = length(center_uv * 2.0);

	// 2. Clear-center vignette mask (0.0 in center, ramps up toward screen edges).
	float vignette = pow(
			smoothstep(vignette_inner, vignette_outer, radial_dist),
			falloff_power
	);

	// 3. Aspect-corrected screen-space lens dirt lookup.
	vec2 dirt_uv = center_uv + 0.5;
	vec3 dirt_sample = texture(dirt_texture, dirt_uv).rgb;

	// 4. Linear depth proximity fade (softens clipping against geometry).
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	float scene_depth = -upos.z / upos.w;
	float fragment_depth = -VERTEX.z;
	float proximity_fade = clamp(
			(scene_depth - fragment_depth) / proximity_fade_distance,
			0.0,
			1.0
	);

	// 5. View-space near-camera fade.
	float dist_fade = 1.0;
	if (distance_fade_max > distance_fade_min) {
		dist_fade = smoothstep(
				distance_fade_min,
				distance_fade_max,
				fragment_depth
		);
	}

	vec3 combined_mask = dirt_sample * dirt_strength * vignette;
	ALBEDO = light_color.rgb * combined_mask * intensity * proximity_fade * dist_fade;
}
