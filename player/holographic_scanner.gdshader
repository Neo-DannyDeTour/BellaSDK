shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

// Instance Uniforms so your Tool Script still works perfectly
instance uniform vec4 base_color : source_color = vec4(0.0, 0.2, 0.8, 0.1);
instance uniform vec4 line_color : source_color = vec4(0.0, 1.0, 1.0, 1.0);
instance uniform float speed = 1.0;
instance uniform float line_count = 2.0;
instance uniform float line_thickness : hint_range(0.01, 1.0) = 0.1;
instance uniform float glow_multiplier = 2.0;

// NEW: We create a variable to pass the 3D position from the Vertex to the Fragment
varying vec3 local_position;

void vertex() {
    // Grab the actual 3D physical coordinates of the mesh (ignoring UV maps entirely!)
    local_position = VERTEX;
}

void fragment() {
    // 1. Calculate the moving phase using the physical Y height (local_position.y)
    float moving_phase = (local_position.y * line_count) + (TIME * speed);

    // 2. Loop the value between 0.0 and 1.0
    float gradient = fract(moving_phase);

    // 3. Shape the gradient into a triangle wave
    float distance_to_center = abs(gradient - 0.5) * 2.0;
    float peak = 1.0 - distance_to_center;

    // 4. "Pinch" the peak based on your thickness slider
    float sharpness = 10.0 / line_thickness;
    float line_mask = pow(peak, sharpness);

    // 5. Apply the colors
    ALBEDO = mix(base_color.rgb, line_color.rgb, line_mask);
    ALPHA = mix(base_color.a, line_color.a, line_mask);

    // 6. Feed into the Emission channel for Glow
    EMISSION = line_color.rgb * line_mask * glow_multiplier;
}
