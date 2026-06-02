shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    vec3 color = texture(screen_texture, SCREEN_UV).rgb;
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    
    // Overexpose the midtones and map to night vision green
    luma = clamp(luma * 1.8, 0.0, 1.0);
    vec3 nv_color = vec3(0.1, luma * 0.9 + 0.1, 0.15);
    
    // Add phosphor noise
    nv_color += (rand(SCREEN_UV + vec2(TIME * 5.0)) - 0.5) * 0.15;
    
    // Add binocular vignette
    float dist = length(SCREEN_UV - 0.5);
    nv_color *= smoothstep(0.6, 0.35, dist);
    
    COLOR = vec4(nv_color, 1.0);
}