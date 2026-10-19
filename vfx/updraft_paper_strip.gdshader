shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform vec4 strip_color : source_color = vec4(0.95, 0.88, 0.3, 1.0);
uniform float wind_speed : hint_range(0.0, 60.0) = 18.0;
uniform float flutter_amplitude : hint_range(0.0, 0.5) = 0.08;
uniform float wave_frequency : hint_range(0.5, 30.0) = 10.0;
uniform float lift_bend_ratio : hint_range(0.0, 2.0) = 0.75;

void vertex() {
	// Root (UV.y = 0) stays anchored to vent ring; tip (UV.y = 1) lifts and flutters
	float weight = pow(clamp(UV.y, 0.0, 1.0), 1.6);

	// Progressive upward bend driven by updraft lift strength
	float upward_lift = weight * lift_bend_ratio;
	VERTEX.y += upward_lift;
	// Arc inward slightly as paper curves up (arc length preservation)
	VERTEX.z -= weight * weight * (lift_bend_ratio * 0.3);

	// High-frequency flutter noise
	float wave_phase = (TIME * wind_speed) - (UV.y * wave_frequency);
	float wave = sin(wave_phase);
	float cross_wave = cos(wave_phase * 0.73);

	VERTEX.x += wave * flutter_amplitude * weight;
	VERTEX.z += cross_wave * (flutter_amplitude * 0.5) * weight;
	VERTEX.y += abs(wave) * (flutter_amplitude * 0.35) * weight;
}

void fragment() {
	ALBEDO = strip_color.rgb;
	ROUGHNESS = 0.65;
	SPECULAR = 0.15;
}
