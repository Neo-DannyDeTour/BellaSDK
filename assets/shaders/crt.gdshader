shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.25;

void fragment() {
    vec2 uv = SCREEN_UV;
    vec4 color = texture(screen_texture, uv);
    
    // Fast scanline generation using sine waves
    float scanline = sin(uv.y * 800.0) * 0.04 * scanline_intensity;
    color.rgb -= scanline;
    
    COLOR = color;
}