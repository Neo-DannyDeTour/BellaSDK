shader_type canvas_item;

// Allows reading the render behind the UI
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

uniform vec4 fade_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float fade_amount : hint_range(0.0, 1.0) = 0.0;
uniform float blur_amount : hint_range(0.0, 5.0) = 0.0;
uniform float blink_openness : hint_range(0.0, 1.0) = 1.0; // 1.0 is fully open, 0.0 is closed

void fragment() {
    // 1. Blur Effect (Reads from screen texture using mipmaps for cheap blur)
    vec4 blurred_screen = textureLod(screen_texture, SCREEN_UV, blur_amount);

    // 2. Eye Blink Effect (Calculates curved eyelids)
    float dist_from_center_x = abs(UV.x - 0.5);
    float eyelid_curve = dist_from_center_x * dist_from_center_x * 0.5;

    float top_lid_edge = (1.0 - blink_openness) * 0.6 + eyelid_curve;
    float bottom_lid_edge = 1.0 - ((1.0 - blink_openness) * 0.6 + eyelid_curve);

    // Check if current pixel is covered by the eyelids
    float in_eyelid = step(UV.y, top_lid_edge) + step(bottom_lid_edge, UV.y);
    in_eyelid = clamp(in_eyelid, 0.0, 1.0);

    // 3. Composite Final Color
    vec4 final_color = blurred_screen;
    final_color = mix(final_color, fade_color, fade_amount);
    final_color = mix(final_color, vec4(0.0, 0.0, 0.0, 1.0), in_eyelid);

    COLOR = final_color;
}
