shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float grid_size : hint_range(2.0, 20.0) = 8.0;

void fragment() {
    vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
    vec2 grid_uv = SCREEN_UV * res / grid_size;
    vec2 local_uv = fract(grid_uv) - 0.5;
    
    vec3 color = texture(screen_texture, SCREEN_UV).rgb;
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    
    // Inverse relationship: darker luma = larger dot radius
    float radius = (1.0 - luma) * 0.7; 
    float dist = length(local_uv);
    
    // Create the dot mask
    float dot_mask = step(radius, dist);
    
    // Mix the original color with black based on the dots
    vec3 final_color = mix(vec3(0.0), color, dot_mask);
    
    COLOR = vec4(final_color, 1.0);
}