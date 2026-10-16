shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 flash_color : source_color = vec4(6.0, 4.2, 1.5, 1.0);
uniform vec4 fire_color : source_color = vec4(3.2, 0.75, 0.08, 1.0);
uniform vec4 smoke_color : source_color = vec4(0.09, 0.09, 0.1, 1.0);
uniform float displacement_strength : hint_range(0.0, 1.5) = 0.38;
uniform float proximity_fade_distance : hint_range(0.05, 3.0) = 0.65;
uniform float noise_scale : hint_range(0.5, 10.0) = 3.2;

varying float v_temperature;
varying float v_erosion;
varying vec3 v_noise_coord;

float hash_3d(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float value_noise_3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n000 = hash_3d(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash_3d(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash_3d(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash_3d(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash_3d(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash_3d(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash_3d(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash_3d(i + vec3(1.0, 1.0, 1.0));

	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);

	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);

	return mix(nxy0, nxy1, f.z);
}

float fbm_3d(vec3 p) {
	float total = 0.0;
	total += value_noise_3d(p) * 0.65;
	total += value_noise_3d(p * 2.15 + vec3(0.0, TIME * 1.4, 0.0)) * 0.35;
	return total;
}

void vertex() {
	// COLOR.r carries normalized heat; COLOR.a carries opacity/erosion lifecycle.
	v_temperature = clamp(COLOR.r, 0.0, 1.0);
	v_erosion = clamp(COLOR.a, 0.0, 1.0);

	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_noise_coord = world_pos * noise_scale + vec3(0.0, -TIME * 1.6, 0.0);

	float turb = fbm_3d(v_noise_coord) * 2.0 - 1.0;
	VERTEX += NORMAL * (turb * displacement_strength);
}

void fragment() {
	float n = fbm_3d(v_noise_coord * 1.35);
	float edge_fade = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 0.75);
	float alpha_mask = smoothstep(1.0 - v_erosion, 1.0, n * edge_fade);

	// Soft particle depth blending against environment walls and floors.
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	float scene_z = upos.z / upos.w;
	float depth_fade = clamp((VERTEX.z - scene_z) / proximity_fade_distance, 0.0, 1.0);

	float local_heat = clamp(v_temperature * (n * 0.7 + 0.45), 0.0, 1.0);
	vec3 hot_blend = mix(fire_color.rgb, flash_color.rgb, smoothstep(0.65, 1.0, local_heat));
	vec3 emission_out = mix(vec3(0.0), hot_blend, smoothstep(0.18, 0.85, local_heat));

	ALBEDO = smoke_color.rgb;
	EMISSION = emission_out;
	ALPHA = clamp(alpha_mask * depth_fade * v_erosion, 0.0, 1.0);
}
