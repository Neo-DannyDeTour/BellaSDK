shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// The classic 1-bit Macintosh color palette
uniform vec3 light_color : source_color = vec3(0.88, 0.94, 0.91);
uniform vec3 dark_color : source_color = vec3(0.20, 0.22, 0.19);
uniform float contrast : hint_range(0.5, 3.0) = 1.2;

// Hardcoded 4x4 Bayer Matrix for optimal performance
// This avoids conditional logic and external texture sampling entirely
const float bayer_matrix_4x4[16] = float[16](
    0.0000, 0.5000, 0.1250, 0.6250,
    0.7500, 0.2500, 0.8750, 0.3750,
    0.1875, 0.6875, 0.0625, 0.5625,
    0.9375, 0.4375, 0.8125, 0.3125
);

void fragment() {
    vec3 color = texture(screen_texture, SCREEN_UV).rgb;
    
    // Calculate grayscale luma and push the contrast 
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    luma = clamp((luma - 0.5) * contrast + 0.5, 0.0, 1.0);
    
    // Determine the current pixel's coordinate within the 4x4 matrix grid
    int x = int(mod(FRAGCOORD.x, 4.0));
    int y = int(mod(FRAGCOORD.y, 4.0));
    int index = x + y * 4;
    
    // Retrieve the exact brightness threshold for this specific pixel
    float threshold = bayer_matrix_4x4[index];
    
    // Branchless binary color selection: 
    // If the luma is brighter than the matrix threshold, it becomes the light color.
    float is_light = step(threshold, luma);
    vec3 final_color = mix(dark_color, light_color, is_light);
    
    COLOR = vec4(final_color, 1.0);
}