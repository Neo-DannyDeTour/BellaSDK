shader_type canvas_item;

uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float line_thickness = 2.0;    // Thickness of the border in pixels
uniform vec2 rect_size;                // Fed by GDScript
uniform float speed = 1.5;             // How fast the light races around
uniform float trail_length = 0.3;      // How long the bright tail is
uniform float hover_intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    // Convert UV to actual pixel coordinates
    vec2 px_coords = UV * rect_size;

    // Calculate distance to the closest edge
    float dist_x = min(px_coords.x, rect_size.x - px_coords.x);
    float dist_y = min(px_coords.y, rect_size.y - px_coords.y);
    float min_dist = min(dist_x, dist_y);

    // --- ANTI-ALIASING MASKS ---
    // Smooth inner edge: Fades out smoothly instead of cutting off sharply
    float inner_mask = smoothstep(line_thickness + 0.5, line_thickness - 0.5, min_dist);
    // Smooth outer edge: Softens the absolute edge of the UI element for smooth rotation
    float outer_mask = smoothstep(0.0, 1.0, min_dist);
    
    // Combine them to get a perfectly smooth stroke
    float border_mask = inner_mask * outer_mask;

    // If we are fully outside the mask area, draw nothing to save performance
    if (border_mask == 0.0 || hover_intensity == 0.0) {
        COLOR = vec4(0.0);
    } else {
        // Calculate an angle from the center of the button
        vec2 center = rect_size / 2.0;
        vec2 offset = px_coords - center;
        float angle = atan(offset.y, offset.x); 
        float norm_angle = (angle + 3.14159) / 6.28318; // Normalize 0.0 to 1.0

        // Create the moving target point
        float time_offset = fract(TIME * speed);
        float diff = abs(norm_angle - time_offset);
        if (diff > 0.5) diff = 1.0 - diff; // Make it wrap around seamlessly

        // Create the bright glowing spot
        float glow = smoothstep(trail_length, 0.0, diff);

        // Mix a faint base border with the bright moving glow
        float base_alpha = 0.15; // The baseline visibility of the border
        
        // --- MULTIPLY BY BORDER_MASK ---
        // We multiply our final alpha by the border_mask to apply the smooth edges
        float final_alpha = clamp(base_alpha + glow, 0.0, 1.0) * hover_intensity * border_mask;

        COLOR = vec4(line_color.rgb, final_alpha * line_color.a);
    }
}