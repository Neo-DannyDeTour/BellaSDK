shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// --- Uniforms ---
uniform vec4 oil_color : source_color = vec4(0.04, 0.035, 0.03, 0.95);
uniform vec4 burn_color : source_color = vec4(1.0, 0.35, 0.02, 1.0);
uniform vec4 ash_color : source_color = vec4(0.02, 0.02, 0.02, 0.4);

uniform float iridescence_strength : hint_range(0.0, 1.0) = 0.85;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.06;
uniform float wet_metallic : hint_range(0.0, 1.0) = 0.35;

uniform float edge_falloff : hint_range(0.01, 0.5) = 0.15;
uniform float stroke_cap_length : hint_range(0.01, 0.3) = 0.08;
uniform float noise_scale = 4.0;
uniform sampler2D noise_tex : hint_default_white;

// Combustion uniforms driven by script
uniform float ignite_center : hint_range(0.0, 1.0) = 0.5;
uniform float burn_radius : hint_range(0.0, 2.0) = 0.0;
uniform float burn_edge_width = 0.06;

void fragment() {
    // Subtle surface noise for fluid meniscus wobble
    vec2 wobble_uv = vec2(UV.x * noise_scale * 0.5, UV.y * noise_scale * 2.0);
    float n = texture(noise_tex, wobble_uv).r;

    // Stroke cap taper: softens and rounds start and end of path
    float cap_mask = smoothstep(0.0, stroke_cap_length, UV.x) *
        (1.0 - smoothstep(1.0 - stroke_cap_length, 1.0, UV.x));

    // Smooth fluid meniscus edge without jagged dry-brush shredding
    float lateral_dist = abs(UV.y - 0.5) * 2.0;
    float distorted_edge = lateral_dist + (n - 0.5) * 0.08;
    float edge_mask = 1.0 - smoothstep(1.0 - edge_falloff, 1.0, distorted_edge);
    float spill_alpha_mask = edge_mask * cap_mask;

    // Thin-film iridescence
    vec3 view_dir = normalize(VIEW);
    float fresnel = 1.0 - clamp(dot(NORMAL, view_dir), 0.0, 1.0);
    vec3 rainbow = 0.5 + 0.5 * cos(6.28318 * (fresnel * 1.6 + n * 0.2 + vec3(0.0, 0.33, 0.67)));
    vec3 base_oil = mix(oil_color.rgb, rainbow, iridescence_strength * fresnel);

    // Combustion front: clamped by is_ignited so it is completely invisible at burn_radius <= 0.0
    float is_ignited = step(0.001, burn_radius);
    float dist_from_ignition = abs(UV.x - ignite_center);

    float burn_front = is_ignited * (1.0 - smoothstep(burn_radius - burn_edge_width, burn_radius, dist_from_ignition));
    float ember_edge = is_ignited * smoothstep(burn_radius - burn_edge_width, burn_radius, dist_from_ignition) *
        (1.0 - smoothstep(burn_radius, burn_radius + burn_edge_width, dist_from_ignition));

    // Surface attributes
    vec3 final_albedo = mix(base_oil, ash_color.rgb, burn_front);
    float final_alpha = mix(oil_color.a * spill_alpha_mask, ash_color.a * spill_alpha_mask, burn_front);
    vec3 flame_glow = burn_color.rgb * ember_edge * 8.0 * (n + 0.5);

    ALBEDO = final_albedo;
    ALPHA = clamp(final_alpha, 0.0, 1.0);
    ROUGHNESS = mix(wet_roughness, 0.85, burn_front);
    METALLIC = mix(wet_metallic, 0.0, burn_front);
    SPECULAR = mix(0.9, 0.1, burn_front);
    EMISSION = flame_glow;
}
