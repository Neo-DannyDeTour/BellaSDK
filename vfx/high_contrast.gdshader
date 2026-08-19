shader_type canvas_item;

// Reads the screen behind this ColorRect
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// The colors we will snap to. You can change these in the inspector later!
uniform vec4 dark_color : source_color = vec4(0.0, 0.0, 0.0, 1.0); // Pure Black
uniform vec4 light_color : source_color = vec4(1.0, 1.0, 0.0, 1.0); // High-vis Yellow
uniform float threshold : hint_range(0.0, 1.0) = 0.4; // At what brightness do we switch?

void fragment() {
    vec4 screen_color = texture(screen_texture, SCREEN_UV);

    // Calculate how bright the pixel is using standard luminance weights
    float luminance = dot(screen_color.rgb, vec3(0.299, 0.587, 0.114));

    // Snap to either the light or dark color based on the threshold
    if (luminance > threshold) {
        COLOR = light_color;
    } else {
        COLOR = dark_color;
    }
}
