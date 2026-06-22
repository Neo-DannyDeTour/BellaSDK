shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back;

uniform float audio_data[32];
uniform bool is_playing = false;

void vertex() {
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
        INV_VIEW_MATRIX[0],
        INV_VIEW_MATRIX[1],
        INV_VIEW_MATRIX[2],
        MODEL_MATRIX[3]
    );
    MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
        vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
        vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
        vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
        vec4(0.0, 0.0, 0.0, 1.0)
    );
    MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
    vec2 uv = UV - 0.5;
    float radius = length(uv);
    
    // atan(y,x) gives an angle from -PI to PI
    float angle = atan(uv.y, uv.x); 
    
    // Shift the angle so that the bottom of the circle is 0
    float shifted_angle = angle + 1.57079632;
    shifted_angle = mod(shifted_angle + 3.14159265, 6.2831853) - 3.14159265;
    
    // Mirror the circle: 0.0 is bottom, 1.0 is top (mirrored on left and right)
    float norm_angle = abs(shifted_angle) / 3.14159265;
    
    float bars = 32.0;
    float bar_index = floor(norm_angle * bars);
    
    float current_val = 0.0;
    if (is_playing) {
        // Clamp index to 31 to prevent array out-of-bounds at the very top pixel
        current_val = audio_data[int(clamp(bar_index, 0.0, 31.0))];
    } else {
        current_val = (sin(TIME * 3.0 + bar_index * 0.4) * 0.5 + 0.5) * 0.15;
    }
    
    float inner_radius = 0.15;
    // Pushed the extrusion to 0.35 for taller, more dramatic spikes
    float max_radius = inner_radius + (current_val * 0.35);
    
    float alpha = step(inner_radius, radius) * step(radius, max_radius);
    
    // Create clean gaps between the bars
    float gap = fract(norm_angle * bars);
    alpha *= step(0.15, gap) * step(gap, 0.85); 
    
    // Colors
    vec3 color_blue = vec3(0.1, 0.6, 1.0);
    vec3 color_pink = vec3(0.9, 0.1, 0.7);
    vec3 color_orange = vec3(1.0, 0.4, 0.1);
    
    vec3 final_color;
    if (norm_angle < 0.5) {
        final_color = mix(color_blue, color_pink, norm_angle * 2.0);
    } else {
        final_color = mix(color_pink, color_orange, (norm_angle - 0.5) * 2.0);
    }
    
    ALBEDO = final_color;
    ALPHA = alpha;
}