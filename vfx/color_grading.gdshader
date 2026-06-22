shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

uniform float brightness : hint_range(0.0, 5.0) = 1.0;
uniform float contrast : hint_range(0.0, 5.0) = 1.0;
uniform float saturation : hint_range(0.0, 5.0) = 1.0;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    vec4 original_color = texture(screen_texture, SCREEN_UV);
    vec3 color = original_color.rgb;

    // Apply Brightness
    color *= brightness;

    // Apply Contrast
    color = (color - 0.5) * contrast + 0.5;

    // Apply Saturation (using standard luminance weights)
    float luminance = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 grayscale = vec3(luminance);
    color = mix(grayscale, color, saturation);

    // Apply Tint
    color *= tint_color.rgb;

    // Fixed: Using COLOR.a instead of original_color.a to allow the Area3D to fade it
    COLOR = vec4(color, COLOR.a);
}