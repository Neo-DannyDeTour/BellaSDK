shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform vec4 ribbon_color : source_color = vec4(0.9, 0.85, 0.2, 1.0);
uniform float wind_speed : hint_range(0.0, 50.0) = 15.0;
uniform float flutter_amplitude : hint_range(0.0, 0.5) = 0.08;
uniform float wave_frequency : hint_range(0.5, 20.0) = 8.0;

void vertex() {
	// Root (UV.y = 0) stays locked to the vent; tip (UV.y = 1) swings wildly
	float weight = pow(UV.y, 1.8);
	float wave = sin((TIME * wind_speed) - (VERTEX.y * wave_frequency));
	float cross_wave = cos((TIME * wind_speed * 0.7) - (VERTEX.y * wave_frequency * 0.5));

	// Primary upward/forward flutter + secondary lateral twist
	VERTEX.x += wave * flutter_amplitude * weight;
	VERTEX.z += cross_wave * (flutter_amplitude * 0.6) * weight;
	VERTEX.y += abs(wave) * (flutter_amplitude * 0.3) * weight;
}

void fragment() {
	ALBEDO = ribbon_color.rgb;
	ROUGHNESS = 0.7;
}
