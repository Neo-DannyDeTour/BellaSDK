shader_type fog;

uniform float density : hint_range(0, 1, 0.0001) = 1.0;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 emission : source_color = vec4(0, 0, 0, 1);
uniform float height_falloff = 0.0;
uniform float edge_fade = 0.1;
uniform sampler3D density_texture : hint_default_white;
uniform vec4 fade_plane = vec4(0.0, 1.0, 0.0, -999.0);

void fog() {
	float base_tex = texture(density_texture, UVW).r;
	float rel_y = WORLD_POSITION.y - OBJECT_POSITION.y;
	float h_factor = 1.0;
	if (height_falloff > 0.0001) {
		h_factor = clamp(exp(-height_falloff * rel_y), 0.0, 1.0);
	}
	float sdf_fade = clamp(-SDF / max(edge_fade, 0.0001), 0.0, 1.0);
	float plane_dist = dot(WORLD_POSITION, fade_plane.xyz) + fade_plane.w;
	float planar_clip = smoothstep(-0.35, 0.0, plane_dist);

	DENSITY = density * base_tex * h_factor * sdf_fade * planar_clip;
	ALBEDO = albedo.rgb;
	EMISSION = emission.rgb;
}
