shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float flute_count : hint_range(1.0, 60.0, 1.0) = 16.0;
uniform float compress_ratio : hint_range(0.1, 10.0, 0.01) = 1.2;
uniform float refraction : hint_range(0.0, 5.0, 0.01) = 1.5;
uniform float edge_overlap : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform float edge_brightness : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform float frost_blur : hint_range(0.0, 5.0, 0.1) = 0.6;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.1;
uniform vec4 glass_tint : source_color = vec4(0.92, 0.97, 1.0, 0.12);

void fragment() {
	float flute_id = floor(UV.x * flute_count);
	float flute_x = (UV.x - (flute_id / flute_count)) * flute_count;

	// Cylindrical lens curve: 0 at flute center, max at edges, signed across center.
	float lens_curve = (1.0 - sin(flute_x * PI)) * sign(0.5 - flute_x);
	float flute_span = compress_ratio / flute_count;
	float overlap_shift = (edge_overlap / flute_count) * (flute_x - 0.5);
	float offset_x = (lens_curve * refraction * flute_span) + overlap_shift;

	vec2 refracted_uv = clamp(SCREEN_UV + vec2(offset_x, 0.0), vec2(0.001), vec2(0.999));
	vec3 refracted = textureLod(screen_texture, refracted_uv, frost_blur).rgb;

	// Left (white) and right (black) bevel highlights per flute column.
	float left_edge = smoothstep(0.1, 0.0, flute_x);
	refracted = mix(refracted, vec3(1.0), left_edge * edge_brightness);
	float right_edge = smoothstep(0.9, 1.0, flute_x);
	refracted = mix(refracted, vec3(0.0), right_edge * edge_brightness);

	// Perturb normal along X for specular glints across each cylindrical flute ridge.
	vec3 flute_normal = normalize(vec3(cos(flute_x * PI) * 0.45, 0.0, 1.0));
	NORMAL = normalize(
		TANGENT * flute_normal.x + BINORMAL * flute_normal.y + NORMAL * flute_normal.z
	);

	vec3 tinted = mix(refracted, glass_tint.rgb, glass_tint.a);
	ALBEDO = glass_tint.rgb * 0.08;
	EMISSION = tinted;
	ROUGHNESS = roughness;
	SPECULAR = 0.6;
	ALPHA = 1.0;
}
