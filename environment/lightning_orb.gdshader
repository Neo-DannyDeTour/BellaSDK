shader_type spatial;
render_mode blend_add, unshaded, cull_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 plasma_color : source_color = vec4(0.2, 0.7, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.5, 0.9, 1.0, 1.0);

uniform float emission_energy : hint_range(1.0, 40.0) = 18.0;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.5;
uniform float noise_scale : hint_range(1.0, 20.0) = 6.0;
uniform float noise_speed : hint_range(0.1, 10.0) = 3.0;
uniform float filament_sharpness : hint_range(1.0, 16.0) = 6.5;

vec3 hash33(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yxz + 19.19);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n000 = dot(hash33(i + vec3(0.0, 0.0, 0.0)) - 0.5, f - vec3(0.0, 0.0, 0.0));
	float n100 = dot(hash33(i + vec3(1.0, 0.0, 0.0)) - 0.5, f - vec3(1.0, 0.0, 0.0));
	float n010 = dot(hash33(i + vec3(0.0, 1.0, 0.0)) - 0.5, f - vec3(0.0, 1.0, 0.0));
	float n110 = dot(hash33(i + vec3(1.0, 1.0, 0.0)) - 0.5, f - vec3(1.0, 1.0, 0.0));
	float n001 = dot(hash33(i + vec3(0.0, 0.0, 1.0)) - 0.5, f - vec3(0.0, 0.0, 1.0));
	float n101 = dot(hash33(i + vec3(1.0, 0.0, 1.0)) - 0.5, f - vec3(1.0, 0.0, 1.0));
	float n011 = dot(hash33(i + vec3(0.0, 1.0, 1.0)) - 0.5, f - vec3(0.0, 1.0, 1.0));
	float n111 = dot(hash33(i + vec3(1.0, 1.0, 1.0)) - 0.5, f - vec3(1.0, 1.0, 1.0));

	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);

	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);

	return mix(nxy0, nxy1, f.z);
}

void vertex() {
	float wobble = sin(TIME * 24.0 + VERTEX.x * 12.0 + VERTEX.y * 14.0);
	VERTEX += NORMAL * wobble * 0.015;
}

void fragment() {
	vec3 pos_a = (VERTEX * noise_scale) + vec3(0.0, TIME * noise_speed, 0.0);
	vec3 pos_b = (VERTEX * (noise_scale * 1.5)) - vec3(TIME * noise_speed * 1.2, 0.0, TIME * noise_speed);

	float n_a = noise3d(pos_a);
	float n_b = noise3d(pos_b);
	float plasma_field = abs(n_a * 1.3 + n_b * 0.7);

	float filament = pow(clamp(1.0 - plasma_field, 0.0, 1.0), filament_sharpness);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	float flicker = mix(0.85, 1.2, fract(sin(floor(TIME * 30.0) * 43.12) * 43758.54));

	vec3 filament_color = filament * core_color.rgb * 5.0;
	vec3 glow_sphere = plasma_color.rgb * (0.35 + fresnel * 2.0);
	vec3 rim_glow = rim_color.rgb * pow(fresnel, 1.5) * 3.5;

	vec3 final_color = (filament_color + glow_sphere + rim_glow) * flicker;

	ALBEDO = final_color * emission_energy;
}
