shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform vec4 base_interior_color : source_color = vec4(0.08, 0.24, 0.68, 0.42);
uniform vec4 base_edge_color : source_color = vec4(0.35, 0.78, 1.0, 0.95);
uniform vec4 hit_interior_color : source_color = vec4(0.85, 0.12, 0.38, 0.65);
uniform vec4 hit_edge_color : source_color = vec4(1.0, 0.35, 0.45, 1.0);
uniform vec4 rim_glow_color : source_color = vec4(1.0, 0.72, 0.62, 1.0);

uniform float edge_start : hint_range(0.5, 0.95) = 0.78;
uniform float edge_end : hint_range(0.8, 1.0) = 0.94;
uniform float emission_energy : hint_range(0.5, 10.0) = 3.2;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.6;
uniform float fresnel_intensity : hint_range(0.0, 5.0) = 2.4;
uniform float refraction_strength : hint_range(0.0, 0.1) = 0.022;

instance uniform float hit_intensity : hint_range(0.0, 1.0) = 0.0;
instance uniform float damage_ratio : hint_range(0.0, 1.0) = 0.0;
instance uniform float opacity : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_normal;
varying vec3 world_view;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_view = normalize(CAMERA_POSITION_WORLD - world_pos);
}

void fragment() {
	float edge_dist = UV.x;
	if (edge_dist > edge_end || opacity <= 0.001) {
		discard;
	}

	float border_mask = smoothstep(edge_start - 0.06, edge_start + 0.02, edge_dist);
	float heat = clamp(max(hit_intensity, damage_ratio * 0.65), 0.0, 1.0);

	vec4 interior_col = mix(base_interior_color, hit_interior_color, heat);
	vec4 edge_col = mix(base_edge_color, hit_edge_color, heat);
	vec4 tile_col = mix(interior_col, edge_col, border_mask);

	float ndotv = abs(dot(normalize(world_normal), normalize(world_view)));
	float fresnel = pow(clamp(1.0 - ndotv, 0.0, 1.0), fresnel_power) * fresnel_intensity;

	float glow_boost = 1.0 + (hit_intensity * 2.2) + (border_mask * 1.4);
	vec3 shield_rgb = tile_col.rgb * emission_energy * glow_boost;
	shield_rgb += rim_glow_color.rgb * fresnel * emission_energy;

	float edge_weight = max(border_mask, clamp(fresnel * 0.5, 0.0, 1.0));
	vec2 refract_offset = NORMAL.xy * edge_weight * refraction_strength * opacity;
	vec3 refracted_bg = textureLod(screen_texture, SCREEN_UV + refract_offset, 0.0).rgb;

	float surface_alpha = clamp(tile_col.a + (border_mask * 0.45) + (fresnel * 0.35), 0.0, 1.0);
	ALBEDO = mix(refracted_bg, shield_rgb, surface_alpha);
	ALPHA = opacity;
}
