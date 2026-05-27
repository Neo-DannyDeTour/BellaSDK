shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// THE WIPE CONTROL (0 = fully wet/blurred, 1.5 = completely clear)
uniform float clear_progress : hint_range(0.0, 1.5) = 1.5; 

void fragment() {
    vec2 uv = SCREEN_UV;
    
    // --- THE WIPE MASK ---
    float mask = smoothstep(clear_progress - 0.3, clear_progress, SCREEN_UV.y);

    // Ripple effect
    float rippleSpeed = 1.5;
    float rippleDensity = 10.0;
    float rippleStrength = 0.02 * mask; 

    vec2 center = vec2(0.5, 0.5);
    vec2 delta = uv - center;
    float distance = length(delta);
    float angle = atan(delta.y, delta.x);

    vec2 distorted_uv = uv;
    distorted_uv.x += cos(angle * rippleDensity + TIME * rippleSpeed) * rippleStrength * distance;
    distorted_uv.y += sin(angle * rippleDensity + TIME * rippleSpeed) * rippleStrength * distance;

    // Simple blur effect
    vec4 color = vec4(0.0);
    float total = 0.0;
    
    float blur_radius = 0.001 * mask;
    
    for (float x = -2.0; x <= 2.0; x++) {
        for (float y = -2.0; y <= 2.0; y++) {
            vec2 samplePos = distorted_uv + vec2(x, y) * blur_radius; 
            color += texture(screen_texture, samplePos);
            total += 1.0;
        }
    }
    color /= total;

    COLOR = color;
}