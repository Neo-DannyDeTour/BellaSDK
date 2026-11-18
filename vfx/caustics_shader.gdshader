shader_type spatial;
// blend_mix with ALBEDO 0.0 ensures ONLY black can be drawn. No light spots possible.
render_mode blend_mix, depth_draw_never, unshaded;

uniform sampler2D drop_texture : hint_normal, filter_linear_mipmap, repeat_enable;

// --- CAUSTIC CONTROLS ---
// Overall opacity of the shadows
uniform float shadow_opacity : hint_range(0.0, 1.0) = 0.5;
// Increase this to make shadows "thicker" and fill in the holes in the middle of drops
uniform float shadow_thickness : hint_range(1.0, 100.0) = 40.0;

// --- CIRCLE MASK ---
uniform float circle_radius : hint_range(0.0, 2.0) = 0.5;
uniform float circle_softness : hint_range(0.01, 1.0) = 0.2;

// --- MOTION ---
uniform float scale_1 = 3.0;
uniform float speed_1 = 0.12;
uniform float scale_2 = 5.0;
uniform float speed_2 = 0.2;

void fragment() {
    // 1. Calculate scrolling layers
    vec2 uv1 = UV * scale_1; uv1.y -= TIME * speed_1;
    vec2 uv2 = UV * scale_2; uv2.y -= TIME * speed_2;

    // 2. Get normal data
    vec2 n1 = texture(drop_texture, uv1).xy * 2.0 - 1.0;
    vec2 n2 = texture(drop_texture, uv2).xy * 2.0 - 1.0;

    // 3. DISTORTION MATH
    // We take the length of each layer separately and combine them.
    // This helps "fill in" the gaps compared to adding the vectors first.
    float distortion = length(n1) + length(n2);

    // 4. THE SHADOW MASK
    // We multiply by thickness and CLAMP.
    // This turns the drops into solid black blobs rather than rings.
    float rain_mask = clamp(distortion * shadow_thickness, 0.0, 1.0);

    // 5. CIRCLE MASK MATH
    float dist_from_center = distance(UV, vec2(0.5));
    float circle_mask = 1.0 - smoothstep(circle_radius - circle_softness, circle_radius, dist_from_center);

    // 6. FINAL OUTPUT
    // Albedo is pure black. The ONLY thing that changes is the Alpha.
    ALBEDO = vec3(0.0);

    // Combine masks and apply master opacity
    float final_alpha = rain_mask * shadow_opacity * circle_mask;

    ALPHA = clamp(final_alpha, 0.0, 1.0);
}
