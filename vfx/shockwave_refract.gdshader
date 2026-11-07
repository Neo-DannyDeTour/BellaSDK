shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

// Per-instance uniforms mutated via set_instance_shader_parameter().
instance uniform float shockwave_progress : hint_range(0.0, 1.0) = 0.0;
instance uniform float shockwave_scale : hint_range(0.5, 12.0) = 5.5;

uniform float refraction_strength : hint_range(0.0, 0.15) = 0.045;
uniform vec4 shockwave_tint : source_color = vec4(0.92, 0.95, 1.0, 1.0);
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

void vertex() {
	float current_radius = mix(0.25, shockwave_scale, shockwave_progress);
	VERTEX *= current_radius;
}

void fragment() {
	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim_ring = pow(1.0 - ndotv, 3.2) * smoothstep(0.0, 0.22, ndotv);
	float fade = 1.0 - smoothstep(0.15, 1.0, shockwave_progress);

	vec2 refract_dir = normalize(NORMAL.xy + vec2(0.0001));
	vec2 uv_offset = refract_dir * rim_ring * fade * refraction_strength;
	vec3 screen_rgb = textureLod(screen_texture, SCREEN_UV + uv_offset, 0.0).rgb;

	ALBEDO = mix(screen_rgb, shockwave_tint.rgb, rim_ring * fade * 0.22);
	ALPHA = clamp(rim_ring * fade * 2.8, 0.0, 1.0);
}
