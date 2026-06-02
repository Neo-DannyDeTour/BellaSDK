shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float grain_amount : hint_range(0.0, 1.0) = 0.08;

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    vec3 color = texture(screen_texture, SCREEN_UV).rgb;
    
    // Animated noise
    float noise = rand(SCREEN_UV + vec2(TIME, -TIME));
    color -= (noise - 0.5) * grain_amount;
    
    // Vignette math
    vec2 uv_dist = SCREEN_UV * (1.0 - SCREEN_UV.yx);
    float vignette = uv_dist.x * uv_dist.y * 15.0;
    color *= pow(vignette, 0.2);
    
    COLOR = vec4(color, 1.0);
}