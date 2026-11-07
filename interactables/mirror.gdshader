shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D reflection_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 glass_tint : source_color = vec4(0.88, 0.94, 0.92, 1.0);
uniform vec3 cage_color : source_color = vec3(0.18, 0.20, 0.22);
uniform float cage_density : hint_range(4.0, 64.0) = 22.0;
uniform float cage_thickness : hint_range(0.01, 0.2) = 0.055;
uniform float cage_depth : hint_range(0.0, 0.05) = 0.012;
uniform float crack_refraction : hint_range(0.0, 0.08) = 0.028;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.04;

instance uniform float crack_intensity : hint_range(0.0, 1.0) = 0.0;
instance uniform vec2 impact_uv = vec2(0.5, 0.5);

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Returns vec3(edge_dist, cell_id_x, cell_id_y) for Voronoi shard cells.
vec3 voronoi_cracks(vec2 uv, float scale) {
	vec2 n = floor(uv * scale);
	vec2 f = fract(uv * scale);
	float md1 = 8.0;
	float md2 = 8.0;
	vec2 best_id = vec2(0.0);

	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < md1) {
				md2 = md1;
				md1 = d;
				best_id = n + g;
			} else if (d < md2) {
				md2 = d;
			}
		}
	}
	return vec3(sqrt(md2) - sqrt(md1), best_id);
}

// Evaluates 45-degree diamond Georgian wire mesh at parallax UV.
vec2 wire_cage_mask(vec2 uv, float density, float thickness) {
	vec2 p = uv * density;
	vec2 rot = vec2(p.x + p.y, p.x - p.y) * 0.70710678;
	vec2 grid = abs(fract(rot - 0.5) - 0.5);
	float d_wire = min(grid.x, grid.y);
	float d_knot = length(grid);
	float wire = 1.0 - smoothstep(thickness * 0.6, thickness, d_wire);
	float knot = 1.0 - smoothstep(thickness * 1.1, thickness * 1.6, d_knot);
	float bevel = clamp((thickness - d_wire) / max(thickness, 0.001), 0.0, 1.0);
	return vec2(max(wire, knot * 0.85), bevel);
}

void fragment() {
	vec3 view_ts = normalize(vec3(
		dot(VIEW, TANGENT),
		dot(VIEW, BINORMAL),
		dot(VIEW, NORMAL)
	));
	vec2 parallax_offset = (view_ts.xy / max(view_ts.z, 0.15)) * cage_depth;

	vec2 refl_uv = vec2(1.0 - UV.x, UV.y);
	float crack_line = 0.0;
	float shard_frost = 0.0;
	vec2 normal_perturb = vec2(0.0);

	if (crack_intensity > 0.001) {
		float impact_dist = distance(UV, impact_uv);
		float radius = crack_intensity * 0.85;
		float radial_mask = 1.0 - smoothstep(radius * 0.35, radius + 0.08, impact_dist);

		vec3 v_primary = voronoi_cracks(UV, 14.0);
		vec3 v_fine = voronoi_cracks(UV * 2.3 + v_primary.yz * 0.13, 24.0);

		float primary_edge = 1.0 - smoothstep(0.0, 0.045 * radial_mask, v_primary.x);
		float fine_edge = 1.0 - smoothstep(0.0, 0.03 * radial_mask, v_fine.x);
		float ring_wave = abs(sin(impact_dist * 38.0 - v_primary.x * 4.0));
		float radial_ring = (1.0 - smoothstep(0.0, 0.12, ring_wave)) * radial_mask * 0.6;

		crack_line = clamp((primary_edge + fine_edge * 0.7 + radial_ring) * radial_mask, 0.0, 1.0);
		shard_frost = clamp((1.0 - smoothstep(0.0, 0.09, impact_dist)) * crack_intensity, 0.0, 1.0);

		vec2 shard_rand = (hash22(v_primary.yz) - 0.5) * 2.0;
		refl_uv += shard_rand * crack_refraction * radial_mask * crack_intensity;
		normal_perturb = shard_rand * crack_line * 0.35;
	}

	vec2 wire_uv = UV - parallax_offset * 0.5;
	vec2 cage = wire_cage_mask(wire_uv, cage_density, cage_thickness);
	float wire_mask = cage.x;
	float wire_bevel = cage.y;

	vec2 shadow_uv = UV - parallax_offset;
	float wire_shadow = wire_cage_mask(shadow_uv, cage_density, cage_thickness).x * 0.45;

	vec3 reflection = texture(reflection_texture, clamp(refl_uv, 0.001, 0.999)).rgb;
	reflection *= glass_tint.rgb * (1.0 - wire_shadow);

	vec3 metal_albedo = mix(cage_color * 0.65, cage_color * 1.35, wire_bevel);
	vec3 composite = mix(reflection, metal_albedo, wire_mask);

	vec3 fracture_color = vec3(0.82, 0.90, 0.92);
	composite = mix(composite, fracture_color, clamp(crack_line * 0.78 + shard_frost * 0.5, 0.0, 1.0));

	ALBEDO = composite;
	METALLIC = mix(0.92, 0.85, wire_mask) * (1.0 - crack_line * 0.7);
	ROUGHNESS = clamp(
		mix(base_roughness, 0.38, wire_mask) + crack_line * 0.65 + shard_frost * 0.4,
		0.02,
		0.95
	);
	SPECULAR = 0.75;
	NORMAL_MAP = normalize(vec3(
		normal_perturb.x + (wire_bevel - 0.5) * wire_mask * 0.25,
		normal_perturb.y + (wire_bevel - 0.5) * wire_mask * 0.25,
		1.0
	)) * 0.5 + 0.5;
}
