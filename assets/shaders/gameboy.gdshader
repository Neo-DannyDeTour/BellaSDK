shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

const vec3 color_1 = vec3(0.058, 0.219, 0.058); // Darkest
const vec3 color_2 = vec3(0.188, 0.384, 0.188);
const vec3 color_3 = vec3(0.545, 0.674, 0.058);
const vec3 color_4 = vec3(0.607, 0.737, 0.058); // Lightest

void fragment() {
    vec3 color = texture(screen_texture, SCREEN_UV).rgb;
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    
    // Mix cleanly without branching
    vec3 final_color = mix(color_1, color_2, step(0.25, luma));
    final_color = mix(final_color, color_3, step(0.50, luma));
    final_color = mix(final_color, color_4, step(0.75, luma));
    
    COLOR = vec4(final_color, 1.0);
}