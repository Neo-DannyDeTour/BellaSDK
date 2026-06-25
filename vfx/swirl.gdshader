shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// Swirl properties
uniform vec2 center = vec2(0.5, 0.5);
uniform float strength = 5.0;
uniform float radius = 0.5;

// Gameboy Palette
const vec3 color_1 = vec3(0.058, 0.219, 0.058); // Darkest
const vec3 color_2 = vec3(0.188, 0.384, 0.188);
const vec3 color_3 = vec3(0.545, 0.674, 0.058);
const vec3 color_4 = vec3(0.607, 0.737, 0.058); // Lightest

void fragment() {
    // 1. Calculate distance and direction from the center
    vec2 uv = SCREEN_UV - center;
    float dist = length(uv);

    // 2. Calculate rotation amount (closer to center = more rotation)
    // max() ensures the swirl naturally stops at the defined radius without branching
    float swirl_amount = max(radius - dist, 0.0) * strength;

    // 3. Create a 2D rotation matrix
    float s = sin(swirl_amount);
    float c = cos(swirl_amount);
    mat2 rot_matrix = mat2(vec2(c, -s), vec2(s, c));

    // 4. Apply rotation and translate back to screen space
    vec2 swirled_uv = (rot_matrix * uv) + center;

    // 5. Sample the texture using the new swirled coordinates
    vec3 color = texture(screen_texture, swirled_uv).rgb;
    
    // 6. Apply your Gameboy Palette math
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    
    // Mix cleanly without branching
    vec3 final_color = mix(color_1, color_2, step(0.25, luma));
    final_color = mix(final_color, color_3, step(0.50, luma));
    final_color = mix(final_color, color_4, step(0.75, luma));
    
    COLOR = vec4(final_color, 1.0);
}