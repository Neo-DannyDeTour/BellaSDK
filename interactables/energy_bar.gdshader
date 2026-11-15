shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

instance uniform float energy_ratio = 1.0;

uniform vec3 empty_bg_color : source_color = vec3(0.04, 0.04, 0.04);
uniform vec3 low_color : source_color = vec3(0.95, 0.12, 0.06);
uniform vec3 mid_color : source_color = vec3(0.95, 0.65, 0.08);
uniform vec3 full_color : source_color = vec3(0.15, 0.95, 0.28);
uniform float emission_strength : hint_range(0.0, 8.0) = 3.2;
uniform float segments : hint_range(4.0, 24.0) = 10.0;

void fragment() {
	float fill = clamp(energy_ratio, 0.0, 1.0);
	float seg_gap = step(0.14, fract(UV.x * segments));
	float lit = step(UV.x, fill) * seg_gap;

	vec3 bar_col = mix(low_color, mid_color, smoothstep(0.0, 0.5, fill));
	bar_col = mix(bar_col, full_color, smoothstep(0.5, 1.0, fill));

	// Pulse dim red when reserve is depleted so player sees charger is dead.
	float empty_pulse = (1.0 - step(0.01, fill)) * (0.35 + 0.65 * (0.5 + 0.5 * sin(TIME * 6.0)));
	vec3 final_emit = bar_col * lit * emission_strength + low_color * empty_pulse * 1.4;

	ALBEDO = mix(empty_bg_color, bar_col, lit);
	ROUGHNESS = 0.25;
	METALLIC = 0.1;
	EMISSION = final_emit;
}
