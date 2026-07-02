shader_type spatial;
// unshaded: No heavy lighting calculations (keeps FPS high).
// blend_mix: Standard alpha transparency.
// depth_draw_never: Prevents transparent sorting glitches.
// cull_disabled: Ensures the quad is visible from both sides.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec3 color_orange : source_color = vec3(1.0, 0.4, 0.0);
uniform vec3 color_blue : source_color = vec3(0.0, 0.5, 1.0);
uniform float wave_speed_multiplier = 1.0;
uniform float start_time = 0.0;

void vertex() {
    // 1. Billboard Quad Mesh
    // This overrides the matrix to continuously face the camera purely via the GPU.
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
        INV_VIEW_MATRIX[0],
        INV_VIEW_MATRIX[1],
        INV_VIEW_MATRIX[2],
        MODEL_MATRIX[3]
    );
    MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
    // Determine the local elapsed time since the effect was triggered
    float local_time = TIME - start_time;
    
    // Total sequence loop is 6.0 seconds: 
    // 1s invis -> 2s orange -> 1s invis -> 2s blue
    float t = mod(local_time, 6.0);

    // 2, 4, 5. Timing and Color States (Branchless 60 FPS Optimization)
    float is_orange_phase = step(1.0, t) * step(t, 3.0);
    float is_blue_phase = step(4.0, t);
    
    // Visibility multiplier (0.0 when in the 1-second invisible phases)
    float visibility = is_orange_phase + is_blue_phase;

    // Determine the current color based on the phase
    vec3 final_color = mix(vec3(0.0), color_orange, is_orange_phase);
    final_color = mix(final_color, color_blue, is_blue_phase);

    // 3. Fades to transparent on its outward ends
    // Centers the UV mapping and creates a soft radial fade mask
    vec2 centered_uv = UV * 2.0 - 1.0;
    float edge_fade = 1.0 - smoothstep(0.2, 1.0, length(centered_uv));

    // 3 & 5. Fires up transparent waves at random speeds
    // UV.y is 0 at the top, 1 at the bottom. Adding time pushes the waves upwards.
    float t_speed = TIME * wave_speed_multiplier;
    
    // Combining offset sine waves creates pseudo-random wave velocities and patterns
    float wave1 = sin(UV.y * 15.0 + t_speed * 8.0);
    float wave2 = sin(UV.y * 28.0 + t_speed * 15.0 + UV.x * 6.0);
    float wave3 = sin(UV.y * 10.0 + t_speed * 4.0 - UV.x * 3.0);

    // Normalize combined waves into a 0.0 to 1.0 alpha map
    float combined_waves = (wave1 + wave2 + wave3) / 3.0;
    combined_waves = combined_waves * 0.5 + 0.5;
    
    // Sharpen the wave contrast so it looks more like energy pulses
    combined_waves = smoothstep(0.3, 0.8, combined_waves);

    // Output
    ALBEDO = final_color;
    // Multiply sequence timing, the edge fade mask, and the moving waves
    ALPHA = visibility * edge_fade * combined_waves;
}