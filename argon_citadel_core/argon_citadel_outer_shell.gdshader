shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

instance uniform float pulse_phase : hint_range(0.0, 1.0) = 0.0;

group_uniforms Bubble_Motion;
uniform float wobble_amplitude : hint_range(0.0, 0.6, 0.01) = 0.22;
uniform float wobble_frequency : hint_range(0.5, 5.0, 0.05) = 1.85;
uniform float pulse_inflation : hint_range(0.0, 0.5, 0.01) = 0.24;

group_uniforms Liquid_Flow;
uniform vec3 flow_speed_primary = vec3(0.35, 0.72, -0.28);
uniform vec3 flow_speed_secondary = vec3(-0.52, 0.34, 0.46);
uniform float fluid_scale : hint_range(0.5, 6.0, 0.05) = 2.1;

group_uniforms Distortion;
uniform float distortion_strength : hint_range(0.0, 0.25, 0.001) = 0.095;
uniform float lens_refraction : hint_range(0.0, 0.2, 0.001) = 0.055;
uniform float chromatic_aberration : hint_range(0.0, 0.1, 0.001) = 0.028;
uniform float liquid_blur_lod : hint_range(0.0, 4.0, 0.1) = 1.4;

group_uniforms Fluid_Haze;
uniform vec4 orange_fluid_color : source_color = vec4(0.95, 0.38, 0.06, 0.55);
uniform vec4 cyan_fluid_color : source_color = vec4(0.12, 0.78, 0.96, 0.55);
uniform float haze_intensity : hint_range(0.0, 2.0, 0.05) = 0.75;
uniform float depth_softness : hint_range(0.01, 2.0, 0.01) = 0.45;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

varying vec3 v_obj_pos;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z
	);
}

float fbm3d(vec3 p) {
	float val = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		val += noise3d(p) * amp;
		p = p * 2.02 + vec3(9.3, 15.7, 4.1);
		amp *= 0.5;
	}
	return val;
}

vec3 fluid_gradient(vec3 p) {
	float eps = 0.08;
	float c = fbm3d(p);
	return vec3(
		fbm3d(p + vec3(eps, 0.0, 0.0)) - c,
		fbm3d(p + vec3(0.0, eps, 0.0)) - c,
		fbm3d(p + vec3(0.0, 0.0, eps)) - c
	) / eps;
}

void vertex() {
	v_obj_pos = VERTEX;
	float active_surge = sin(pulse_phase * 3.14159265);

	float harmonic = sin(TIME * wobble_frequency + VERTEX.y * 1.7)
		* cos(TIME * (wobble_frequency * 0.73) + VERTEX.x * 1.5)
		* sin(TIME * (wobble_frequency * 0.57) - VERTEX.z * 1.6);
	float surface_wave = fbm3d(VERTEX * 1.35 + vec3(TIME * 0.65, -TIME * 0.85, TIME * 0.45)) - 0.5;

	float wobble = (harmonic * 0.55 + surface_wave * 0.85)
		* wobble_amplitude * (0.7 + active_surge * 0.65);
	float inflation = active_surge * pulse_inflation;

	VERTEX += NORMAL * (wobble + inflation);
}

void fragment() {
	vec3 p_b = v_obj_pos * (fluid_scale * 0.78) + (flow_speed_secondary * TIME);
	vec3 grad_b = fluid_gradient(p_b);

	vec3 p_a = v_obj_pos * fluid_scale + (flow_speed_primary * TIME) + grad_b * 0.35;
	vec3 grad_a = fluid_gradient(p_a);

	vec3 combined_grad = (grad_a + grad_b) * 0.5;
	vec2 blended_flow = combined_grad.xy + combined_grad.zy * 0.5;

	float fluid_val = fbm3d(p_a + combined_grad * 0.25);
	float meniscus = smoothstep(0.32, 0.74, fluid_val);

	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_coords.xyz /= view_coords.w;
	float scene_depth = -view_coords.z;
	float frag_depth = -VERTEX.z;
	float depth_fade = clamp((scene_depth - frag_depth) / depth_softness, 0.0, 1.0);

	float active_surge = sin(pulse_phase * 3.14159265);
	vec3 wet_normal = normalize(NORMAL + combined_grad * 0.42);
	float ndotv = clamp(dot(wet_normal, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 2.4);

	// Full-sphere distortion warps InnerCore and background alike
	vec2 sphere_lens = -wet_normal.xy * lens_refraction * (0.35 + (1.0 - ndotv) * 0.65);
	vec2 flow_offset = blended_flow * distortion_strength * (0.85 + active_surge * 0.45);
	vec2 offset = (flow_offset + sphere_lens) * depth_fade;

	vec2 red_uv = SCREEN_UV + offset * (1.0 + chromatic_aberration);
	vec2 green_uv = SCREEN_UV + offset;
	vec2 blue_uv = SCREEN_UV + offset * (1.0 - chromatic_aberration);

	float r = textureLod(screen_texture, red_uv, liquid_blur_lod).r;
	float g = textureLod(screen_texture, green_uv, liquid_blur_lod).g;
	float b = textureLod(screen_texture, blue_uv, liquid_blur_lod).b;
	vec3 background_color = vec3(r, g, b);

	// Keep pitch-black refracted InnerCore center un-tinted while tinting glowing edges & background
	float bg_luma = max(background_color.r, max(background_color.g, background_color.b));
	float void_preserve = clamp(smoothstep(0.01, 0.18, bg_luma) + fresnel * 0.85, 0.0, 1.0);

	float orange_w = smoothstep(0.0, 0.45, pulse_phase)
		* (1.0 - smoothstep(0.45, 0.65, pulse_phase));
	float cyan_w = smoothstep(0.45, 0.65, pulse_phase);
	float color_mix = orange_w / max(orange_w + cyan_w + 0.001, 0.001);

	vec4 fluid_tint = mix(cyan_fluid_color, orange_fluid_color, color_mix);
	float haze_alpha = clamp(
		(meniscus * 0.55 + fresnel * 0.65)
		* fluid_tint.a * depth_fade * haze_intensity * void_preserve,
		0.0,
		1.0
	);

	vec3 specular_glint = mix(vec3(0.35, 0.92, 1.0), vec3(1.0, 0.58, 0.18), color_mix)
		* pow(fresnel, 2.4) * (0.75 + active_surge * 0.85);
	vec3 final_rgb = mix(background_color, fluid_tint.rgb * (0.75 + meniscus * 0.65), haze_alpha)
		+ specular_glint * depth_fade * void_preserve;

	ALBEDO = final_rgb;
	ALPHA = clamp(depth_fade * 2.0, 0.0, 1.0);
}
