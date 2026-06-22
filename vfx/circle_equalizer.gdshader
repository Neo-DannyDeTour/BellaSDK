shader_type spatial;
// Unshaded means it ignores scene lighting, perfect for floating UI elements
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back;

uniform float audio_data[32];
uniform bool is_playing = false;
uniform vec4 base_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);

void fragment() {
    // Center the UV coordinates to 0,0
    vec2 uv = UV - 0.5;
    
    // Convert to polar coordinates
    float radius = length(uv);
    float angle = atan(uv.y, uv.x); 
    
    // Map angle from -PI..PI to 0..1
    float norm_angle = (angle + 3.14159265) / 6.2831853;
    
    // Define 32 discrete bars to match our GDScript array
    float bars = 32.0;
    float bar_index = floor(norm_angle * bars);
    
    // Fetch audio data or generate idle noise
    float current_val = 0.0;
    if (is_playing) {
        current_val = audio_data[int(bar_index)];
    } else {
        // Generate a smooth idle wave using TIME and the bar index
        current_val = (sin(TIME * 3.0 + bar_index * 0.4) * 0.5 + 0.5) * 0.15;
    }
    
    // Define the inner circle boundary and max extrusion
    float inner_radius = 0.15;
    float max_radius = inner_radius + (current_val * 0.3);
    
    // Mask out the inner circle and everything past the max radius
    float alpha = step(inner_radius, radius) * step(radius, max_radius);
    
    // Slice the circle into distinct bars (adds gaps between them)
    float gap = fract(norm_angle * bars);
    alpha *= step(0.15, gap) * step(gap, 0.85); 
    
    // Slice the bars radially into segments (creates the dotted look)
    float segment_count = 30.0;
    float segments = step(0.2, fract(radius * segment_count));
    alpha *= segments;
    
    ALBEDO = base_color.rgb;
    ALPHA = alpha * base_color.a;
}