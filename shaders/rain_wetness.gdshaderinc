global uniform float rain_wetness;
global uniform float rain_ripple_intensity;
global uniform vec2 rain_wind_dir;

// Computes procedural dual-layered raindrop ripple normals in world XZ space
vec3 compute_rain_ripples(vec2 world_xz, float time) {
	vec2 uv = world_xz * 1.5;
	vec2 cell = floor(uv);
	vec2 frac_uv = fract(uv) - 0.5;

	float seed = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	float t = fract(time * 1.8 + seed);
	float radius = t * 0.45;
	float dist = length(frac_uv);

	float ring = sin((dist - radius) * 45.0) * smoothstep(radius, radius - 0.08, dist) * smoothstep(0.0, 0.05, dist);
	float fade = (1.0 - t) * rain_ripple_intensity;
	vec2 d_norm = normalize(frac_uv + vec2(0.0001)) * ring * fade * 0.35;
	return normalize(vec3(d_norm.x, d_norm.y, 1.0));
}

// Applies porosity darkening, specular flattening, and upward-facing ripple normals
void apply_rain_surface(
	vec3 world_pos,
	vec3 world_normal,
	float time,
	float roof_occlusion,
	inout vec3 albedo,
	inout float roughness,
	inout vec3 normal_map
) {
	float effective_wetness = rain_wetness * roof_occlusion;
	float up_mask = clamp((world_normal.y - 0.65) / 0.35, 0.0, 1.0);

	// Porous darkening and specular reflection boost
	albedo *= mix(1.0, 0.55, effective_wetness);
	roughness = mix(roughness, 0.06, effective_wetness * mix(0.5, 1.0, up_mask));

	if (rain_ripple_intensity > 0.01 && up_mask > 0.01 && roof_occlusion > 0.01) {
		vec3 ripple_n = compute_rain_ripples(world_pos.xz, time);
		normal_map = normalize(mix(normal_map, ripple_n, up_mask * roof_occlusion));
	}
}
