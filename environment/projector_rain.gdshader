shader_type spatial;

// blend_mul makes the white background invisible, and the black dots darken the ground
// unshaded means it ignores other level lighting and acts purely as a decal/projector
render_mode blend_mul, unshaded, depth_draw_never;

uniform sampler2D rain_texture : filter_linear_mipmap, repeat_enable;

// Your requested controls
uniform vec2 scroll_speed = vec2(0.0, -1.0); // Speed and direction
uniform float size_multiplier = 1.0;         // Higher number = smaller, more tiled dots
uniform float blackness : hint_range(0.0, 1.0) = 1.0; // 1.0 is pitch black dots, 0.0 is invisible

void fragment() {
    // 1. Handle the Size (Scale the UVs)
    vec2 scaled_uv = UV * size_multiplier;

    // 2. Handle the Speed (Scroll over time)
    vec2 scrolled_uv = scaled_uv + (scroll_speed * TIME);

    // 3. Sample your 2048x2048 texture
    vec4 tex_color = texture(rain_texture, scrolled_uv);

    // 4. Handle the "Blackness"
    // We mix pure white (which is invisible in blend_mul) with your texture
    vec3 final_color = mix(vec3(1.0), tex_color.rgb, blackness);

    ALBEDO = final_color;
}
