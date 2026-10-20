shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec4 drop_tint : source_color = vec4(0.82, 0.90, 0.98, 0.68);
uniform float refraction_strength : hint_range(0.0, 0.08) = 0.025;
uniform float highlight_boost : hint_range(0.0, 2.0) = 0.45;

void vertex() {
	vec3 world_center = MODEL_MATRIX[3].xyz;
	vec3 vel_vec = MODEL_MATRIX[1].xyz;
	float streak_len = max(length(vel_vec), 0.001);
	vec3 up_dir = vel_vec / streak_len;
	float width = max(length(MODEL_MATRIX[0].xyz), 0.005);

	// Axial billboard: lock quad Y to 3D velocity vector and rotate X to always face camera
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - world_center);
	vec3 right_dir = cross(to_cam, up_dir);
	float right_len = length(right_dir);
	right_dir = (right_len > 0.0001) ? (right_dir / right_len) : vec3(1.0, 0.0, 0.0);

	vec3 world_vert = world_center + right_dir * (VERTEX.x * width) + up_dir * (VERTEX.y * streak_len);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_vert, 1.0);
}

void fragment() {
	float centered_x = UV.x * 2.0 - 1.0;
	float horiz = 1.0 - abs(centered_x);
	float vert = sin(UV.y * PI);

	// Swirling storm droplets (COLOR.g > 0.5) have a rounder bead profile
	float profile = mix(horiz * vert, smoothstep(0.0, 0.7, horiz) * pow(vert, 0.65), COLOR.g);
	float mask = smoothstep(0.05, 0.85, profile);

	// Refract background scene so raindrops contrast against both bright daylight and dark night
	vec2 refract_offset = vec2(centered_x, (UV.y - 0.5) * 0.5) * refraction_strength * mask;
	vec3 bg_col = textureLod(screen_tex, SCREEN_UV + refract_offset, 0.0).rgb;
	float bg_luma = dot(bg_col, vec3(0.299, 0.587, 0.114));

	// Core specular highlight + subtle dark refractive rim for bright sky contrast
	float core = smoothstep(0.45, 0.95, horiz * vert);
	float edge_darken = mix(1.0, 0.62, bg_luma * (1.0 - core));
	vec3 refracted_drop = bg_col * edge_darken + drop_tint.rgb * (core * highlight_boost);

	ALBEDO = mix(drop_tint.rgb, refracted_drop, 0.78);
	ALPHA = clamp(drop_tint.a * mask * COLOR.r, 0.0, 0.95);
}
