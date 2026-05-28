shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// Brightness threshold to separate the Fill (brighter) from the Outline (darker) in your source texture.
uniform float fill_threshold : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    // 1. Get the background brightness
    vec4 screen_color = texture(screen_texture, SCREEN_UV);
    float bg_brightness = dot(screen_color.rgb, vec3(0.299, 0.587, 0.114));
    
    // 2. Read the pixel from your hearts atlas
    vec4 tex_color = texture(TEXTURE, UV);
    float tex_brightness = max(max(tex_color.r, tex_color.g), tex_color.b);
    
    // 3. Evaluate states (returns 1.0 if true, 0.0 if false)
    float is_bg_light = step(0.5, bg_brightness);
    float is_fill = step(fill_threshold, tex_brightness);
    
    // 4. Define the target colors
    // Outline: Black (0.0) on light bg, White (1.0) on dark bg
    vec3 target_outline_color = mix(vec3(1.0), vec3(0.0), is_bg_light);
    
    // Fill: Pure White (1.0) on light bg, Black (0.0) on dark bg
    vec3 target_fill_color = mix(vec3(0.0), vec3(1.0), is_bg_light);
    
    // 5. Combine everything based on what part of the heart we are drawing
    vec3 final_color = mix(target_outline_color, target_fill_color, is_fill);
    
    // 6. Output the final color, keeping the original alpha transparency
    COLOR = vec4(final_color, tex_color.a);
}