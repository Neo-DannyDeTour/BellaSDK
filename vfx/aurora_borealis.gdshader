shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;

group_uniforms Noise;
uniform vec2 noise_tiling = vec2(7.0, 0.1);
uniform vec2 primary_speed = vec2(0.04, 0.01);
uniform vec2 secondary_speed = vec2(0.045, 0.015);
uniform float secondary_scale_offset = 1.18;
uniform float dissolve_power : hint_range(0.5, 8.0) = 2.0;

group_uniforms CurtainMask;
uniform float horizontal_fade_power : hint_range(0.5, 4.0) = 1.5;
uniform float vertical_falloff_power : hint_range(0.5, 6.0) = 2.2;
uniform float bottom_sharpness : hint_range(0.01, 0.5) = 0.15;

group_uniforms VertexWave;
uniform float wave_amplitude : hint_range(0.0, 50.0) = 8.0;
uniform float wave_frequency : hint_range(0.001, 0.5) = 0.04;
uniform float wave_speed : hint_range(0.0, 5.0) = 0.6;

instance uniform vec4 tint_color : source_color = vec4(0.1, 0.9, 0.4, 1.0);
instance uniform float intensity : hint_range(0.0, 10.0) = 2.0;
instance uniform float phase_offset = 0.0;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave_phase = (world_pos.x + world_pos.z) * wave_frequency + (TIME * wave_speed) + phase_offset;
	float secondary_wave = sin(world_pos.z * (wave_frequency * 2.3) - (TIME * wave_speed * 0.7) + phase_offset);
	VERTEX.z += (sin(wave_phase) + secondary_wave * 0.5) * wave_amplitude;
}

void fragment() {
	vec2 phase_uv = vec2(phase_offset * 0.13, phase_offset * 0.07);
	vec2 uv1 = UV * noise_tiling + (TIME * primary_speed) + phase_uv;
	vec2 uv2 = (UV * noise_tiling * secondary_scale_offset) + (TIME * secondary_speed) - phase_uv;

	float n1 = texture(noise_tex, uv1).r;
	float n2 = pow(texture(noise_tex, uv2).r, dissolve_power);

	float h_mask = pow(sin( clamp(UV.x, 0.0, 1.0) * PI ), horizontal_fade_power);
	float v_inv = 1.0 - clamp(UV.y, 0.0, 1.0);
	float v_bottom = smoothstep(0.0, bottom_sharpness, v_inv);
	float v_top = pow( clamp(UV.y, 0.0, 1.0), vertical_falloff_power );
	float mask = h_mask * v_bottom * v_top;

	float aurora = n1 * n2 * mask;
	ALBEDO = tint_color.rgb * (aurora * intensity * tint_color.a);
}
