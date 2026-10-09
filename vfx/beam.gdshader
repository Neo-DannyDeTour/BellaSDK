shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, shadows_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 inner_color : source_color = vec4(1.0, 0.12, 0.36, 1.0);
uniform vec4 outer_color : source_color = vec4(0.85, 0.03, 0.08, 1.0);
uniform vec4 smoke_color : source_color = vec4(0.5, 0.06, 0.03, 1.0);

uniform float core_power : hint_range(1.0, 60.0) = 28.0;
uniform float inner_power : hint_range(1.0, 20.0) = 6.0;
uniform float outer_power : hint_range(0.5, 10.0) = 1.6;

uniform float core_intensity : hint_range(1.0, 20.0) = 8.0;
uniform float inner_intensity : hint_range(1.0, 10.0) = 4.0;
uniform float outer_intensity : hint_range(0.1, 5.0) = 1.4;

uniform sampler2D noise_texture : repeat_enable;
uniform float smoke_scale : hint_range(0.1, 20.0) = 2.5;
uniform float smoke_speed : hint_range(0.1, 10.0) = 2.0;
uniform float smoke_intensity : hint_range(0.0, 3.0) = 1.1;

instance uniform float segment_length = 1.0;

varying vec3 v_cylinder_axis;

void vertex() {
	v_cylinder_axis = normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void fragment() {
	vec3 view_dir = normalize(-VERTEX);
	vec3 v_perp = view_dir - dot(view_dir, v_cylinder_axis) * v_cylinder_axis;
	float len_perp = length(v_perp);
	float ndotv = 1.0;
	if (len_perp > 0.001) {
		ndotv = clamp(abs(dot(NORMAL, v_perp / len_perp)), 0.0, 1.0);
	}

	float longitudinal_fade = smoothstep(0.0, 0.06, UV.y) * smoothstep(1.0, 0.94, UV.y);

	float core = pow(ndotv, core_power) * core_intensity;
	float inner = pow(ndotv, inner_power) * inner_intensity;
	float outer = pow(ndotv, outer_power) * outer_intensity;

	vec2 uv_smoke_1 = vec2(
		UV.x * 2.0,
		UV.y * smoke_scale * (segment_length * 0.15) - TIME * smoke_speed
	);
	vec2 uv_smoke_2 = vec2(
		UV.x * -1.5,
		UV.y * smoke_scale * 0.8 * (segment_length * 0.15) - TIME * (smoke_speed * 0.7)
	);

	float noise1 = texture(noise_texture, uv_smoke_1).r;
	float noise2 = texture(noise_texture, uv_smoke_2).r;
	float combined_noise = noise1 * noise2 * 2.0;

	float smoke_envelope = smoothstep(0.03, 0.35, ndotv);
	float smoke = combined_noise * smoke_envelope * smoke_intensity;

	vec3 beam_rgb = (core_color.rgb * core)
		+ (inner_color.rgb * inner)
		+ (outer_color.rgb * outer)
		+ (smoke_color.rgb * smoke);

	float alpha = clamp(core + inner + outer + smoke, 0.0, 1.0) * longitudinal_fade;

	ALBEDO = beam_rgb;
	ALPHA = alpha;
}
