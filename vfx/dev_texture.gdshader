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

// --- Helper Functions ---
float get_grid_line(vec2 uv, float subdivisions, float thickness) {
    vec2 grid = fract(uv * subdivisions);
    vec2 fr = min(grid, 1.0 - grid);
    vec2 delta = fwidth(uv * subdivisions);
    vec2 line = smoothstep(delta * thickness, delta * (thickness + 0.5), fr);
    return 1.0 - min(line.x, line.y);
}

void fragment() {
    vec2 uv = UV * unit_scale;
    
    // 1. Procedural Checkered Macro Grid
    vec2 check_uv = floor(fract(uv) * 2.0);
    float checker = mod(check_uv.x + check_uv.y, 2.0);
    vec3 base_color = mix(bg_color_a, bg_color_b, checker);
    
    // 2. Procedural Grid Lines
    float major_grid = get_grid_line(uv, major_subdivisions, line_thickness * 2.0);
    float minor_grid = get_grid_line(uv, minor_subdivisions, line_thickness);
    
    // Composite the procedural texture layout
    vec3 final_albedo = base_color;
    final_albedo = mix(final_albedo, minor_line_color.rgb, minor_grid * minor_line_color.a);
    final_albedo = mix(final_albedo, major_line_color.rgb, major_grid * major_line_color.a);
    
    // Calculate the alpha footprint of the lines
    float line_alpha = max(minor_grid * minor_line_color.a, major_grid * major_line_color.a);
    
    // 3. Mannequin Overlay
    vec4 mannequin = texture(mannequin_silhouette, UV);
    final_albedo = mix(final_albedo, mannequin.rgb, mannequin.a);

    // 4. Final Alpha Compositing
    // Keep alpha at 1.0 where there are lines or the mannequin, otherwise use bg_alpha
    float final_alpha = max(bg_alpha, line_alpha);
    final_alpha = max(final_alpha, mannequin.a);

    ALBEDO = final_albedo;
    ALPHA = final_alpha;
    ROUGHNESS = 0.8; 
}