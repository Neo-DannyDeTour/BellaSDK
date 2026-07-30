shader_type spatial;
// Forcing blend_mix and depth_draw_never pushes this to the transparent pipeline, 
// ensuring it renders AFTER the opaque full-screen accessibility quad.
render_mode blend_mix, depth_draw_never, unshaded, depth_test_disabled, cull_disabled;

uniform vec4 highlight_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float highlight_opacity : hint_range(0.0, 1.0) = 1.0; // Keep at 1.0 for solid color

void fragment() {
    ALBEDO = highlight_color.rgb;
    ALPHA = highlight_opacity;
}