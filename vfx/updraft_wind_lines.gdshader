shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, particle_trails;

uniform vec4 line_color : source_color = vec4(0.82, 0.94, 1.0, 0.88);
uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform vec2 uv_scale = vec2(1.0, 1.8);
uniform float flow_speed : hint_range(0.0, 15.0) = 4.5;
uniform float line_sharpness : hint_range(0.1, 5.0) = 1.6;
uniform float edge_fade_x : hint_range(0.05, 0.5) = 0.3;
uniform float edge_fade_y : hint_range(0.05, 0.5) = 0.22;

varying float v_seed;

void vertex() {
    v_seed = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
}

void fragment() {
    // Panning noise along the 3D ribbon trail length (UV.y) with per-instance phase offset
    vec2 scrolled_uv = vec2(
        UV.x * uv_scale.x + v_seed,
        (UV.y * uv_scale.y) - (TIME * flow_speed * 0.45) + v_seed * 3.7
    );
    float raw_noise = texture(noise_texture, scrolled_uv).r;
    // Keep strong base visibility while modulating streak gusts
    float gust_mod = mix(0.55, 1.0, smoothstep(0.2, 0.8, raw_noise));

    // Crisp transverse ribbon core (UV.x) and tapered head/tail (UV.y)
    float mask_x = smoothstep(0.0, edge_fade_x, UV.x) * smoothstep(1.0, 1.0 - edge_fade_x, UV.x);
    float core_spine = pow(max(0.0, sin(UV.x * PI)), line_sharpness);
    float mask_y = smoothstep(0.0, edge_fade_y, UV.y)
            * smoothstep(1.0, 1.0 - (edge_fade_y * 1.4), UV.y);

    float streak_alpha = mix(mask_x, core_spine, 0.65) * mask_y * gust_mod;

    ALBEDO = line_color.rgb * COLOR.rgb * 1.35;
    ALPHA = clamp(streak_alpha * line_color.a * COLOR.a, 0.0, 1.0);
}
