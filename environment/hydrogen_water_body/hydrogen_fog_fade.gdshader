shader_type fog;

#include "res://environment/fog_fade_common.gdshaderinc"

uniform float base_density = 0.12;
uniform vec4 albedo : source_color = vec4(0.04, 0.14, 0.24, 1.0);
uniform vec4 emission : source_color = vec4(0.0, 0.03, 0.06, 1.0);
uniform float height_falloff = 0.0;
uniform float edge_fade = 0.15;
uniform sampler3D density_texture : hint_default_white;
uniform bool use_density_texture = false;
uniform vec3 texture_scale = vec3(0.2);

uniform vec3 camera_pos = vec3(0.0);
uniform vec3 camera_forward = vec3(0.0, 0.0, -1.0);
uniform float fade_plane_dist = 3.0;
uniform float near_fog_ratio = 0.45;
uniform float fade_sharpness = 0.35;

void fog() {
	float edge_atten = fog_fade_box_edge(UVW, edge_fade);
	float height_atten = fog_fade_height_exp(
		height_falloff,
		max(1.0 - UVW.y, 0.0) * SIZE.y
	);

	float tex_mod = 1.0;
	if (use_density_texture) {
		tex_mod = texture(density_texture, WORLD_POSITION * texture_scale).r;
	}

	// Camera-aligned visibility fade plane preserving near-camera murk
	float cam_mod = fog_fade_camera_clear(
		WORLD_POSITION,
		camera_pos,
		camera_forward,
		fade_plane_dist,
		fade_sharpness,
		near_fog_ratio
	);

	DENSITY = base_density * edge_atten * height_atten * tex_mod * cam_mod;
	ALBEDO = albedo.rgb;
	EMISSION = emission.rgb;
}
