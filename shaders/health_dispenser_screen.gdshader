shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D screen_tex : source_color, filter_linear, repeat_disable;

// Rolling TV wave settings (matched to drone screen vhs.gdshader)
uniform float wave_speed : hint_range(0.1, 5.0, 0.05) = 0.25;
uniform float wave_frequency : hint_range(0.1, 10.0, 0.1) = 1.9;
uniform float wave_width : hint_range(0.01, 0.5, 0.01) = 0.14;
uniform float refraction_strength : hint_range(0.0, 0.1, 0.001) = 0.014;

// Chromatic aberration, scanlines, and baseline static
uniform float aberration_amount : hint_range(0.0, 0.03, 0.001) = 0.005;
uniform float dither_intensity : hint_range(0.0, 1.0, 0.01) = 0.14;
uniform float scanline_strength : hint_range(0.0, 0.5, 0.01) = 0.12;
uniform float desaturation : hint_range(0.0, 1.0, 0.01) = 0.25;

// Periodic heavy static/distortion burst controls
uniform float burst_period : hint_range(1.0, 12.0, 0.1) = 4.5;
uniform float burst_duty : hint_range(0.05, 0.5, 0.01) = 0.22;
uniform float burst_static_strength : hint_range(0.0, 1.0, 0.01) = 0.78;
uniform float burst_tear_strength : hint_range(0.0, 0.25, 0.005) = 0.085;

float rand(vec2 co) {
	return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float time_step = floor(TIME * 24.0);
	float noise_val = rand(FRAGCOORD.xy + vec2(time_step));
	float row_noise = rand(vec2(floor(uv.y * 48.0), time_step));

	// Periodic burst window (smoothly ramps in/out for intense static & horizontal tear)
	float cycle = fract(TIME / burst_period);
	float burst = smoothstep(0.0, 0.04, cycle) * (1.0 - smoothstep(burst_duty - 0.05, burst_duty, cycle));

	// 1. Rolling downward TV wave
	float wave_phase = fract(uv.y * wave_frequency - TIME * wave_speed);
	float wave_band = smoothstep(0.0, wave_width * 0.5, wave_phase)
		* smoothstep(wave_width, wave_width * 0.5, wave_phase);

	// 2. Horizontal refraction + periodic glitch tear
	vec2 refracted_uv = uv;
	refracted_uv.x += wave_band * (refraction_strength + ((noise_val - 0.5) * 0.012));
	refracted_uv.x += burst * (row_noise - 0.5) * burst_tear_strength;
	refracted_uv = clamp(refracted_uv, vec2(0.001), vec2(0.999));

	// 3. Chromatic aberration (intensifies during burst)
	float aber = aberration_amount + burst * 0.012;
	float r = texture(screen_tex, clamp(refracted_uv + vec2(aber, 0.0), vec2(0.0), vec2(1.0))).r;
	float g = texture(screen_tex, refracted_uv).g;
	float b = texture(screen_tex, clamp(refracted_uv - vec2(aber, 0.0), vec2(0.0), vec2(1.0))).b;
	vec3 color = vec3(r, g, b);

	// 4. Desaturation + CRT scanlines
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, vec3(luma), desaturation);
	color -= sin(uv.y * 220.0) * 0.5 * scanline_strength;

	// 5. Rolling wave static + periodic heavy static burst
	color += (noise_val - 0.5) * dither_intensity;
	color += wave_band * noise_val * 0.35;
	color = mix(color, vec3(noise_val), burst * burst_static_strength);

	ALBEDO = clamp(color, vec3(0.0), vec3(1.0));
}
