shader_type fog;

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
	float height_atten = clamp(
		exp2(-height_falloff * (WORLD_POSITION.y - OBJECT_POSITION.y)),
		0.0,
		1.0
	);
	float min_extent = max(min(min(SIZE.x, SIZE.y), SIZE.z), 0.001);
	float sdf_factor = clamp(-2.0 * SDF / min_extent, 0.0001, 1.0);
	float edge_atten = pow(sdf_factor, max(edge_fade, 0.001));

	float base_density = density * height_atten * texture(density_texture, UVW).r * edge_atten;

	// Preserve near-camera underwater murk while clearing flashlight cone up to fade_plane.
	vec3 fade_plane_origin = fade_plane.xyz * fade_plane.w;
	float dist_past_plane = dot(WORLD_POSITION - fade_plane_origin, fade_plane.xyz);
	float plane_ramp = clamp(dist_past_plane * fade_sharpness + 1.0, 0.0, 1.0);
	float fade_mult = mix(near_fog_ratio, 1.0, plane_ramp);

	DENSITY = base_density * fade_mult * albedo.a;
	ALBEDO = albedo.rgb;
	EMISSION = emission.rgb;
}
