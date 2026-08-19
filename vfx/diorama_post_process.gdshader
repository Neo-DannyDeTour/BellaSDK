shader_type canvas_item;

// Required to read the rendered 3D viewport behind this 2D overlay
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Uniforms driven by DioramaPostProcess script (0: Off, 1: CRT, 2: VHS, 3: Pixelate, etc.)
uniform int filter_mode : hint_range(0, 19) = 0;
uniform float grain_amount : hint_range(0.0, 20.0) = 0.0;

// Random noise generator for film grain
float random(vec2 uv) {
    return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
    // 1. Sample the underlying 3D diorama render
    vec4 base_color = texture(screen_texture, SCREEN_UV);
    vec3 final_color = base_color.rgb;

    // 2. Apply Film Grain
    if (grain_amount > 0.0) {
        float noise = (random(SCREEN_UV + vec2(TIME * 0.1, TIME * 0.05)) - 0.5) * (grain_amount * 0.02);
        final_color += noise;
    }

    // 3. Screen Filters preview logic based on enum index
    if (filter_mode == 1) {
        // CRT
        float scanline = sin(SCREEN_UV.y * 800.0) * 0.04;
        final_color -= scanline;
    } else if (filter_mode == 3) {
        // Pixelate
        vec2 grid = vec2(160.0, 120.0);
        vec2 pixel_uv = floor(SCREEN_UV * grid) / grid;
        final_color = texture(screen_texture, pixel_uv).rgb;
    } else if (filter_mode == 5) {
        // Gameboy
        float lum = dot(final_color, vec3(0.299, 0.587, 0.114));
        if (lum < 0.25) {
            final_color = vec3(0.06, 0.22, 0.06);
        } else if (lum < 0.5) {
            final_color = vec3(0.19, 0.38, 0.19);
        } else if (lum < 0.75) {
            final_color = vec3(0.54, 0.67, 0.06);
        } else {
            final_color = vec3(0.61, 0.73, 0.06);
        }
    }

    COLOR = vec4(final_color, base_color.a);
}
