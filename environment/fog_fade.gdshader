shader_type fog;

#include "res://environment/fog_fade_common.gdshaderinc"

uniform float density : hint_range(0.0, 1.0, 0.0001) = 1.0;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float height_falloff = 0.0;
uniform float edge_fade = 0.1;
uniform float near_fog_ratio : hint_range(0.0, 1.0) = 0.45;
uniform float fade_sharpness : hint_range(0.05, 2.0) = 0.35;
uniform sampler3D density_texture : hint_default_white;
uniform vec4 fade_plane = vec4(0.0, 1.0, 0.0, -999.0);

void fog() {
	float height_atten = fog_fade_height_exp2(height_falloff, WORLD_POSITION.y - OBJECT_POSITION.y);
	float edge_atten = fog_fade_sdf_pow(SDF, SIZE, edge_fade);
	float base_density = density * height_atten * texture(density_texture, UVW).r * edge_atten;

	// Preserve near-camera underwater murk while clearing flashlight cone up to fade_plane.
	float fade_mult = fog_fade_plane_ramp(WORLD_POSITION, fade_plane, fade_sharpness, near_fog_ratio);

	DENSITY = base_density * fade_mult * albedo.a;
	ALBEDO = albedo.rgb;
	EMISSION = emission.rgb;
}
