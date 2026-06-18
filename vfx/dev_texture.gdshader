// Strict Godot 4 static typing rules applied.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back;

// --- Uniforms ---
group_uniforms Grid_Settings;
uniform vec3 bg_color_a : source_color = vec3(0.22, 0.22, 0.22);
uniform vec3 bg_color_b : source_color = vec3(0.28, 0.28, 0.28);
uniform vec4 major_line_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform vec4 minor_line_color : source_color = vec4(0.4, 0.4, 0.4, 0.5);
uniform float bg_alpha : hint_range(0.0, 1.0) = 1.0;

uniform float unit_scale : hint_range(0.1, 10.0) = 1.0;
uniform float major_subdivisions : hint_range(2.0, 10.0) = 2.0;
uniform float minor_subdivisions : hint_range(2.0, 20.0) = 8.0;
uniform float line_thickness : hint_range(0.001, 0.05) = 0.01;

group_uniforms Reference_Textures;
uniform sampler2D dev_texture_backup : hint_default_black, filter_linear_mipmap;
uniform sampler2D mannequin_silhouette : hint_default_transparent, filter_linear_mipmap;

group_uniforms Architecture_Settings;
uniform int architecture_type : hint_range(0, 5) = 0;

// --- Helper Functions ---
float get_grid_line(vec2 uv, float subdivisions, float thickness) {
    vec2 grid = fract(uv * subdivisions);
    vec2 fr = min(grid, 1.0 - grid);
    vec2 delta = fwidth(uv * subdivisions);
    vec2 line = smoothstep(delta * thickness, delta * (thickness + 0.5), fr);
    return 1.0 - min(line.x, line.y);
}

float draw_ladder(vec2 uv, float thickness) {
    // Two vertical rails centered at x=0.25 and x=0.75
    float rails = step(abs(abs(uv.x - 0.5) - 0.25), thickness);
    // Horizontal rungs repeated vertically
    float rungs = step(abs(fract(uv.y * 10.0) - 0.5), thickness * 5.0) * step(abs(uv.x - 0.5), 0.25);
    return clamp(rails + rungs, 0.0, 1.0);
}
float draw_vent(vec2 uv, float thickness) {
    vec2 center_dist = abs(uv - 0.5);
    // Outer square boundary
    float border = step(abs(max(center_dist.x, center_dist.y) - 0.4), thickness);
    // Inner diagonal louvers
    float louvers = step(abs(fract((uv.x + uv.y) * 15.0) - 0.5), thickness * 10.0);
    // Mask to keep louvers inside the border
    float mask = step(max(center_dist.x, center_dist.y), 0.4);
    return max(border, louvers * mask);
}

float draw_hazard(vec2 uv) {
    // Thick diagonal stripes
    return step(fract((uv.x + uv.y) * 4.0), 0.5);
}

float draw_ruler(vec2 uv, float thickness) {
    // Thick borders on all edges
    float edges = step(uv.x, 0.05) + step(0.95, uv.x) + step(uv.y, 0.05) + step(0.95, uv.y);
    // Repeating major/minor ticks
    float ticks = step(fract(uv.x * 10.0), thickness * 2.0) + step(fract(uv.y * 10.0), thickness * 2.0);
    return clamp(edges * ticks, 0.0, 1.0);
}

float draw_spawn(vec2 uv, float thickness) {
    float dist = length(uv - vec2(0.5));
    // Outer dashed/solid circle
    float circle = step(abs(dist - 0.35), thickness);
    // Inner crosshair
    float cross = step(abs(uv.x - 0.5), thickness) * step(abs(uv.y - 0.5), 0.2) +
                  step(abs(uv.y - 0.5), thickness) * step(abs(uv.x - 0.5), 0.2);
    return max(circle, cross);
}

float draw_window(vec2 uv, float thickness) {
    vec2 center_dist = abs(uv - 0.5);
    
    // Outer frame
    float outer_box = step(max(center_dist.x, center_dist.y), 0.25);
    float outer_hole = step(max(center_dist.x, center_dist.y), 0.25 - thickness);
    float outer_frame = max(0.0, outer_box - outer_hole);
    
    // Inner frame
    float inner_box = step(max(center_dist.x, center_dist.y), 0.22);
    float inner_hole = step(max(center_dist.x, center_dist.y), 0.22 - thickness);
    float inner_frame = max(0.0, inner_box - inner_hole);
    
    return max(outer_frame, inner_frame);
}

float draw_door(vec2 uv, float thickness) {
    float dx = abs(uv.x - 0.5);
    
    // Outer door frame (open at the bottom, so y doesn't check against a bottom boundary)
    float outer_box = step(dx, 0.25) * step(uv.y, 0.75);
    float outer_hole = step(dx, 0.25 - thickness) * step(uv.y, 0.75 - thickness);
    float outer_frame = max(0.0, outer_box - outer_hole);
    
    // Inner door frame
    float inner_box = step(dx, 0.22) * step(uv.y, 0.72);
    float inner_hole = step(dx, 0.22 - thickness) * step(uv.y, 0.72 - thickness);
    float inner_frame = max(0.0, inner_box - inner_hole);
    
    return max(outer_frame, inner_frame);
}

float draw_stairs(vec2 uv, float thickness) {
    // Defines a 5-step staircase profile
    float steps = 5.0;
    
    // Scale UVs up into grid cells
    float scaled_x = uv.x * steps;
    float scaled_y = uv.y * steps;
    
    vec2 local = fract(vec2(scaled_x, scaled_y));
    
    // Identify the diagonal cells where the stair edge exists
    float is_stair_cell = step(abs(floor(scaled_y) - floor(scaled_x)), 0.1);
    
    // Draw the horizontal tread (top of the cell) and vertical riser (left of the cell)
    float tread = step(1.0 - local.y, thickness * steps);
    float riser = step(local.x, thickness * steps);
    
    return clamp((tread + riser) * is_stair_cell, 0.0, 1.0);
}

// --- Fragment ---
void fragment() {
    vec2 uv = UV * unit_scale;
    
    // 1. Procedural Checkered Macro Grid (Your existing code)
    vec2 check_uv = floor(fract(uv) * 2.0);
    float checker = mod(check_uv.x + check_uv.y, 2.0);
    vec3 base_color = mix(bg_color_a, bg_color_b, checker);
    
    // 2. Procedural Grid Lines (Your existing code)
    float major_grid = get_grid_line(uv, major_subdivisions, line_thickness * 2.0);
    float minor_grid = get_grid_line(uv, minor_subdivisions, line_thickness);
    
    vec3 final_albedo = base_color;
    final_albedo = mix(final_albedo, minor_line_color.rgb, minor_grid * minor_line_color.a);
    final_albedo = mix(final_albedo, major_line_color.rgb, major_grid * major_line_color.a);
    
    float line_alpha = max(minor_grid * minor_line_color.a, major_grid * major_line_color.a);

    // 3. Architecture Element Override
    float arch_mask = 0.0;
    
    switch (architecture_type) {
        case 1: arch_mask = draw_ladder(UV, line_thickness); break;
        case 2: arch_mask = draw_vent(UV, line_thickness); break;
        case 3: arch_mask = draw_hazard(UV); break;
        case 4: arch_mask = draw_ruler(UV, line_thickness); break;
        case 5: arch_mask = draw_spawn(UV, line_thickness); break;
        case 6: arch_mask = draw_window(UV, line_thickness); break;
        case 7: arch_mask = draw_door(UV, line_thickness); break;
        case 8: arch_mask = draw_stairs(UV, line_thickness); break;
    }
    
    // Apply white color where the architectural mask exists
    final_albedo = mix(final_albedo, vec3(1.0), arch_mask);
    
    // 4. Mannequin Overlay (Your existing code)
    vec4 mannequin = texture(mannequin_silhouette, UV);
    final_albedo = mix(final_albedo, mannequin.rgb, mannequin.a);

    // 5. Final Alpha Compositing
    float final_alpha = max(bg_alpha, line_alpha);
    final_alpha = max(final_alpha, mannequin.a);
    final_alpha = max(final_alpha, arch_mask); // Ensure architecture elements stay opaque

    ALBEDO = final_albedo;
    ALPHA = final_alpha;
    ROUGHNESS = 0.8; 
}