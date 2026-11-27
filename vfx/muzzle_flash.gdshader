shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform sampler2D flash_atlas : source_color, filter_linear, repeat_disable;

instance uniform vec2 atlas_offset = vec2(0.0, 0.0);
instance uniform float flash_alpha = 0.0;
instance uniform float hdr_energy = 7.5;
instance uniform vec4 flash_tint : source_color = vec4(1.0, 0.78, 0.38, 1.0);

void fragment() {
	vec2 tile_uv = clamp(UV, vec2(0.002), vec2(0.998)) * 0.5 + atlas_offset;
	vec4 tex = texture(flash_atlas, tile_uv);
	float luma = max(tex.r, max(tex.g, tex.b));
	float intensity = luma * flash_alpha;
	vec3 hot_core = vec3(1.0, 0.98, 0.92);
	float core_mask = smoothstep(0.32, 0.90, intensity);
	vec3 outer_color = tex.rgb * flash_tint.rgb;
	vec3 color = mix(outer_color, hot_core, core_mask);
	ALBEDO = color * hdr_energy;
	ALPHA = clamp(intensity * flash_tint.a, 0.0, 1.0);
}
