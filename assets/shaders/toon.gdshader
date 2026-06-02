shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float color_levels : hint_range(1.0, 10.0, 1.0) = 5.0;

void fragment() {
    vec3 color = texture(screen_texture, SCREEN_UV).rgb;
    
    // Floor the color values to force them into distinct bands
    color = floor(color * color_levels) / color_levels;
    
    COLOR = vec4(color, 1.0);
}