shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_atlas : hint_normal, filter_linear_mipmap, repeat_disable;
uniform vec2 atlas_grid = vec2(4.0, 4.0);
uniform float soft_particle_distance : hint_range(0.05, 3.0) = 0.85;
uniform float near_fade_distance : hint_range(0.1, 3.0) = 0.75;
uniform float scatter_strength : hint_range(0.0, 2.0) = 0.65;
uniform float wrap_diffuse_bias : hint_range(0.0, 1.0) = 0.78;
uniform float ambient_floor : hint_range(0.0, 0.5) = 0.10;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.20;
instance uniform vec4 tint_color : source_color = vec4(0.32, 0.30, 0.28, 1.0);
instance uniform float density_scale : hint_range(0.0, 2.0) = 1.0;
instance uniform float erosion_bias : hint_range(-0.5, 0.5) = 0.0;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

varying float v_lifetime_ratio;
varying vec2 v_cell_uv;
varying float v_spin_angle;

void vertex() {
	v_lifetime_ratio = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_spin_angle = INSTANCE_CUSTOM.x;

	vec2 grid = max(atlas_grid, vec2(1.0));
	float cell_count = grid.x * grid.y;
	float cell_idx = (INSTANCE_CUSTOM.z > 0.0001)
		? floor(mod(INSTANCE_CUSTOM.z * cell_count, cell_count))
		: mod(float(INSTANCE_ID), cell_count);
	float col = mod(cell_idx, grid.x);
	float row = floor(cell_idx / grid.x);
	v_cell_uv = (vec2(col, row) + UV) / grid;

	vec3 scale_vec = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz)
	);

	float s = sin(v_spin_angle);
	float c = cos(v_spin_angle);

	// Camera-facing billboard preserving particle scale and Z-axis spin.
	mat4 mat_world = mat4(
		normalize(INV_VIEW_MATRIX[0]),
		normalize(INV_VIEW_MATRIX[1]),
		normalize(INV_VIEW_MATRIX[2]),
		MODEL_MATRIX[3]
	);
	mat_world = mat_world * mat4(
		vec4(c * scale_vec.x, -s * scale_vec.x, 0.0, 0.0),
		vec4(s * scale_vec.y, c * scale_vec.y, 0.0, 0.0),
		vec4(0.0, 0.0, scale_vec.z, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
}

void fragment() {
	vec4 atlas_col = texture(albedo_atlas, v_cell_uv);
	vec3 n_map = texture(normal_atlas, v_cell_uv).xyz * 2.0 - 1.0;

	// Subtle macro-lobe view-space normal blended toward flat billboard (zero plastic creases).
	vec2 n_xy = n_map.xy;
	float cs = cos(v_spin_angle);
	float sn = sin(v_spin_angle);
	vec2 rot_xy = vec2(n_xy.x * cs + n_xy.y * sn, -n_xy.x * sn + n_xy.y * cs);
	vec3 lobe_normal = normalize(vec3(rot_xy, max(0.25, n_map.z)));
	NORMAL = normalize(mix(vec3(0.0, 0.0, 1.0), lobe_normal, clamp(normal_strength, 0.0, 1.0)));

	vec3 smoke_rgb = atlas_col.rgb * tint_color.rgb * COLOR.rgb;
	ALBEDO = smoke_rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = smoke_rgb * ambient_floor;

	// Depth soft-particle fade against walls/ceilings + camera near-plane fade.
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	float scene_depth = -upos.z / upos.w;
	float depth_fade = smoothstep(
		0.0,
		1.0,
		clamp((scene_depth + VERTEX.z) / max(soft_particle_distance, 0.001), 0.0, 1.0)
	);
	float near_fade = smoothstep(
		0.0,
		1.0,
		clamp(-VERTEX.z / max(near_fade_distance, 0.001), 0.0, 1.0)
	);

	// Ultra-soft misty dissolution over particle lifetime (no hard cutout rim).
	float life_env = smoothstep(0.0, 0.18, v_lifetime_ratio)
			* (1.0 - smoothstep(0.52, 1.0, v_lifetime_ratio));
	float soft_density = clamp(
		atlas_col.a - smoothstep(0.45, 1.0, v_lifetime_ratio) * 0.25 + erosion_bias * 0.25,
		0.0,
		1.0
	);
	float alpha_out = soft_density * life_env * density_scale * COLOR.a * tint_color.a;
	ALPHA = clamp(alpha_out * depth_fade * near_fade, 0.0, 1.0);
}

void light() {
	float n_dot_l = dot(NORMAL, LIGHT);
	float lambert = max(n_dot_l, 0.0);
	float half_lambert = mix(0.45, 1.0, n_dot_l * 0.5 + 0.5);
	float wrap_diffuse = mix(lambert, half_lambert, wrap_diffuse_bias);
	float forward_scatter = pow(max(dot(-VIEW, LIGHT), 0.0), 2.5) * scatter_strength;

	DIFFUSE_LIGHT += (wrap_diffuse + forward_scatter)
		* LIGHT_COLOR * ATTENUATION * 0.31830988;
}
