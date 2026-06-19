shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.5;
uniform vec4 neon_color : source_color = vec4(0.0, 1.0, 1.0, 1.0);
uniform float core_brightness : hint_range(0.0, 5.0) = 2.0;
uniform float flicker_speed : hint_range(0.0, 50.0) = 20.0;

void fragment() {
    vec2 uv = UV;
    vec4 tex = texture(TEXTURE, uv);
    float envelope = smoothstep(0.0, 0.2, progress) * (1.0 - smoothstep(0.8, 1.0, progress));

    float time_flicker = TIME * flicker_speed;
    float flicker = clamp(sin(time_flicker) + sin(time_flicker * 1.83) + 1.2, 0.7, 1.0);

    vec2 ps = TEXTURE_PIXEL_SIZE * 2.0;
    float halo_alpha = texture(TEXTURE, uv + vec2(ps.x, 0.0)).a;
    halo_alpha += texture(TEXTURE, uv + vec2(-ps.x, 0.0)).a;
    halo_alpha += texture(TEXTURE, uv + vec2(0.0, ps.y)).a;
    halo_alpha += texture(TEXTURE, uv + vec2(0.0, -ps.y)).a;
    halo_alpha = min(halo_alpha * 0.5, 1.0);

    vec3 core = tex.rgb * vec3(1.0) * core_brightness;
    vec3 halo = neon_color.rgb * 1.5;

    vec3 final_color = mix(halo, core, tex.a);
    float final_alpha = max(tex.a, halo_alpha);

    COLOR = vec4(final_color * flicker, final_alpha * envelope);
}