shader_type spatial;
render_mode unshaded, depth_draw_never;

// Removed filter_linear_mipmap. filter_nearest is the cheapest possible read.
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

// Parameters
uniform float pixel_size : hint_range(0.001, 0.1, 0.001) = 0.02;
uniform float jitter_speed : hint_range(0.0, 20.0, 0.1) = 10.0;
uniform float jitter_intensity : hint_range(0.0, 0.5, 0.01) = 0.05;

void fragment() {
    // 1. Get screen aspect ratio
    vec2 aspect = vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);

    // 2. Adjust screen UVs
    vec2 adjusted_uv = SCREEN_UV * aspect;

    // 3. Calculate time-based jitter
    vec2 jitter = vec2(
        sin(TIME * jitter_speed + adjusted_uv.y * 50.0),
        cos(TIME * jitter_speed * 0.8 + adjusted_uv.x * 50.0)
    ) * (pixel_size * jitter_intensity);

    // 4. Snap UVs to create blocks.
    // Adding 0.5 offsets the read to the exact center of the snapped block,
    // preventing it from accidentally reading recognizable edge outlines.
    vec2 snapped_uv = (floor((adjusted_uv + jitter) / pixel_size) + 0.5) * pixel_size;

    // 5. Revert aspect ratio
    snapped_uv /= aspect;

    // 6. Standard, cheap texture read without mipmaps
    vec3 censor_color = texture(screen_texture, snapped_uv).rgb;

    ALBEDO = censor_color;
}
