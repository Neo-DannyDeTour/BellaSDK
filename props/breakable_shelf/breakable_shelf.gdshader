shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 paint_color : source_color = vec4(0.76, 0.78, 0.75, 1.0);
uniform vec4 wood_color : source_color = vec4(0.36, 0.23, 0.13, 1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.88;
instance uniform float albedo_alpha : hint_range(0.0, 1.0) = 1.0;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	float grain = sin(local_pos.x * 60.0 + local_pos.z * 12.0 + hash(local_pos.xz) * 4.0);
	float wear = clamp(grain * 0.5 + 0.5, 0.0, 1.0);
	bool is_outer = abs(local_normal.x) > 0.5 || local_normal.y > 0.5 || abs(local_normal.z) > 0.5;
	vec3 base = mix(wood_color.rgb, paint_color.rgb, is_outer ? 0.82 : 0.25);
	ALBEDO = mix(base, wood_color.rgb * 0.7, wear * 0.25);
	ROUGHNESS = roughness_val;
	ALPHA = albedo_alpha;
}
