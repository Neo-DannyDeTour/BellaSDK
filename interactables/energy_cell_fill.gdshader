shader_type spatial;

uniform vec4 discharged_color : source_color = vec4(0.9, 0.15, 0.15, 1.0);
uniform vec4 charged_color : source_color = vec4(0.15, 0.95, 0.25, 1.0);
uniform float fill_progress : hint_range(0.0, 1.0) = 0.0;
uniform float min_height = -0.5;
uniform float max_height = 0.5;
uniform float edge_softness = 0.02;
uniform float glow_energy = 2.5;

varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	float normalized_y = clamp((local_y - min_height) / (max_height - min_height), 0.0, 1.0);
	float fill_factor = smoothstep(normalized_y - edge_softness, normalized_y + edge_softness, fill_progress);

	vec3 final_color = mix(discharged_color.rgb, charged_color.rgb, fill_factor);
	ALBEDO = final_color;
	EMISSION = charged_color.rgb * fill_factor * glow_energy;
}
