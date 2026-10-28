shader_type canvas_item;

// This grabs the rendered game world behind the UI
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// Target highlight color and blend weight for aim assist locking
uniform vec4 target_tint : source_color = vec4(1.0, 0.2, 0.2, 1.0);
uniform float target_tint_weight : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    // 1. Get the color of the screen exactly behind this pixel
    vec4 screen_color = texture(screen_texture, SCREEN_UV);

    // 2. Calculate how bright the background is (Standard Luminance formula)
    float brightness = dot(screen_color.rgb, vec3(0.299, 0.587, 0.114));

    // 3. Get the shape and transparency of your actual UI circle texture
    vec4 circle_texture = texture(TEXTURE, UV);

    // 4. If the background brightness is > 0.5 (light), make the circle black.
    //    If it's < 0.5 (dark), make the circle white.
    vec3 base_color = mix(vec3(1.0), vec3(0.0), step(0.5, brightness));
    vec3 final_color = mix(base_color, target_tint.rgb, target_tint_weight);

    // 5. Output the color, but keep your circle's original transparency
    COLOR = vec4(final_color, circle_texture.a);
}
