shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Screen texture sampled for glass block refraction.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
// Number of glass blocks along U and V axes.
uniform vec2 tiles = vec2(8.0, 8.0);
// Refraction offset strength across each block.
uniform float distortion : hint_range(-0.2, 0.2, 0.001) = 0.04;
// Edge curvature exponent; higher values flatten block centers.
uniform float block_curvature : hint_range(1.0, 6.0, 0.1) = 2.0;
// Tint applied to refracted background.
uniform vec4 glass_tint : source_color = vec4(0.88, 0.96, 0.98, 1.0);
// Color of mortar/grout seams between glass blocks.
uniform vec4 grout_color : source_color = vec4(0.75, 0.8, 0.82, 1.0);
// Normalized seam thickness at each block border.
uniform float grout_width : hint_range(0.0, 0.25, 0.005) = 0.04;
// Surface roughness for glass specular highlights.
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.08;
// Specular intensity for glass surface reflections.
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.8;

void fragment() {
	vec2 cell_uv = fract(UV * tiles) - 0.5;
	vec2 offset = sign(cell_uv) * pow(abs(cell_uv) * 2.0, vec2(block_curvature)) * distortion;
	vec2 refracted_uv = clamp(SCREEN_UV - offset, vec2(0.001), vec2(0.999));
	vec3 refracted = texture(screen_tex, refracted_uv).rgb * glass_tint.rgb;

	vec2 edge_dist = 0.5 - abs(cell_uv);
	float min_edge = min(edge_dist.x, edge_dist.y);
	float grout_mask = 1.0 - smoothstep(grout_width * 0.5, grout_width, min_edge);

	ALBEDO = mix(refracted, grout_color.rgb, grout_mask);
	ROUGHNESS = mix(roughness, 0.65, grout_mask);
	SPECULAR = specular;
}
