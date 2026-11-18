shader_type fog;

#include "res://environment/fog_fade_common.gdshaderinc"

uniform float density : hint_range(0, 1, 0.0001) = 1.0;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 emission : source_color = vec4(0, 0, 0, 1);
uniform float height_falloff = 0.0;
uniform float edge_fade = 0.1;
uniform sampler3D density_texture : hint_default_white;
uniform vec4 fade_plane = vec4(0.0, 1.0, 0.0, -999.0);

void fog() {
	float base_tex = texture(density_texture, UVW).r;
	float h_factor = fog_fade_height_exp(height_falloff, WORLD_POSITION.y - OBJECT_POSITION.y);
	float sdf_fade = fog_fade_sdf_linear(SDF, edge_fade);
	float planar_clip = fog_fade_plane_clip(WORLD_POSITION, fade_plane);

	DENSITY = density * base_tex * h_factor * sdf_fade * planar_clip;
	ALBEDO = albedo.rgb;
	EMISSION = emission.rgb;
}
