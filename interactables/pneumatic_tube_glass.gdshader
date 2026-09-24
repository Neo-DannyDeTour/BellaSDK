shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled;

// Color tint of the glass body
uniform vec4 glass_tint : source_color = vec4(0.82, 0.92, 0.98, 0.15);

// Edge glare / Fresnel highlight color
uniform vec4 edge_color : source_color = vec4(0.9, 0.98, 1.0, 0.7);

// Structural seam ring color
uniform vec4 rib_color : source_color = vec4(0.18, 0.20, 0.22, 0.85);

// Fresnel edge rim power (higher value = thinner edge highlight)
uniform float fresnel_power : hint_range(1.0, 10.0, 0.1) = 3.5;

// Surface roughness of the plastic/glass
uniform float glass_roughness : hint_range(0.0, 1.0, 0.05) = 0.1;

// Spacing density of the reinforcement ring seams along the tube length
uniform float seam_frequency : hint_range(1.0, 50.0, 0.5) = 12.0;

// Width of the reinforcement ring seams
uniform float seam_thickness : hint_range(0.01, 0.3, 0.01) = 0.04;


void fragment() {
    // Calculate Fresnel rim lighting to highlight curved glass edges
    float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);

    // Mix base glass color with Fresnel rim
    vec3 base_rgb = mix(glass_tint.rgb, edge_color.rgb, fresnel);
    float base_alpha = mix(glass_tint.a, edge_color.a, fresnel);

    // Generate periodic structural rings along UV.y (extrusion path length)
    float seam_coord = fract(UV.y * seam_frequency);
    float seam_mask = step(1.0 - seam_thickness, seam_coord) + step(seam_coord, seam_thickness);
    seam_mask = clamp(seam_mask, 0.0, 1.0);

    // Blend glass with reinforcement ribs
    ALBEDO = mix(base_rgb, rib_color.rgb, seam_mask);
    ALPHA = mix(base_alpha, rib_color.a, seam_mask);
    ROUGHNESS = mix(glass_roughness, 0.4, seam_mask);
    METALLIC = mix(0.1, 0.7, seam_mask);
    SPECULAR = 0.8;
}
