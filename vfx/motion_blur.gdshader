shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 camera_angular_velocity = vec2(0.0);
uniform float motion_blur_strength = 0.5;
uniform int blur_samples = 8;

void fragment() {
    // Increased velocity scalar from 0.005 to 0.08 for realistic rotational streak
    vec2 vel = camera_angular_velocity * motion_blur_strength * 0.08;
    vel = clamp(vel, vec2(-0.05), vec2(0.05));

    if (length(vel) < 0.00005 || motion_blur_strength <= 0.005) {
        COLOR = texture(screen_texture, SCREEN_UV);
    } else {
        vec4 color = vec4(0.0);
        for (int i = 0; i < blur_samples; i++) {
            float offset_scale = (float(i) / float(blur_samples - 1)) - 0.5;
            vec2 sample_uv = clamp(
                SCREEN_UV + (vel * offset_scale),
                vec2(0.001),
                vec2(0.999)
            );
            color += texture(screen_texture, sample_uv);
        }
        COLOR = color / float(blur_samples);
    }
}
