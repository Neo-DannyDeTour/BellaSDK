shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float intensity : hint_range(0.0, 1.0) = 0.2;

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    float time_snap = floor(TIME * 15.0);
    float block_y = floor(uv.y * 25.0);
    
    // Calculate a random offset for this specific block of the screen
    float offset = (rand(vec2(block_y, time_snap)) - 0.5) * intensity * 0.5;
    float is_glitching = step(0.85, rand(vec2(block_y, time_snap + 1.0)));
    
    uv.x += offset * is_glitching;
    
    // Split RGB
    float r = texture(screen_texture, uv + vec2(0.015 * is_glitching, 0.0)).r;
    float g = texture(screen_texture, uv).g;
    float b = texture(screen_texture, uv - vec2(0.015 * is_glitching, 0.0)).b;
    
    COLOR = vec4(r, g, b, 1.0);
}