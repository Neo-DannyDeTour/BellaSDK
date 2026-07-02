shader_type spatial;
render_mode blend_add, unshaded, cull_disabled;

uniform vec4 wave_color : source_color = vec4(1.0, 0.5, 0.0, 1.0);
uniform float core_thickness = 0.02; // Thickness of the solid 100% opaque center
uniform float glow_thickness = 0.08; // Thickness of the fading glow outside the core
uniform float emission_strength = 2.0; // Push above 1.0 for HDR WorldEnvironment glow

// Animation parameters
uniform float min_radius = 0.4;
uniform float max_radius = 0.6;
uniform float transition_time = 1.0;
uniform float pause_time = 2.0;

void vertex() {
    // Replicates standard billboarding while keeping the mesh's original scale
    mat4 mat_world = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
    mat_world = mat_world * mat4(
        vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
        vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
        vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
        vec4(0.0, 0.0, 0.0, 1.0)
    );
    MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
    MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
    // 1. Calculate the timing cycle
    float cycle_length = (transition_time + pause_time) * 2.0;
    float t = mod(TIME, cycle_length);

    // 2. Calculate growing progress (0.0 to 1.0)
    float up_progress = clamp(t / transition_time, 0.0, 1.0);

    // 3. Calculate shrinking progress (0.0 to 1.0)
    float down_start = transition_time + pause_time;
    float down_progress = clamp((t - down_start) / transition_time, 0.0, 1.0);

    // 4. Combine into a ping-pong linear value (0.0 -> 1.0 -> 0.0)
    float linear_progress = up_progress - down_progress;

    // 5. Apply smoothstep for a seamless ease-in-out curve
    float ease_progress = smoothstep(0.0, 1.0, linear_progress);

    // 6. Interpolate the current radius based on the eased progress
    float current_radius = mix(min_radius, max_radius, ease_progress);

    // 7. Center the UV coordinates (-1.0 to 1.0)
    vec2 center_uv = UV * 2.0 - 1.0;
    float dist = length(center_uv);

    // 8. Calculate distance from the exact mathematical ring line
    float distance_from_ring = abs(dist - current_radius);

    // 9. Calculate solid core and soft glow
    // Alpha stays exactly 1.0 inside core_thickness, then smoothly fades out over glow_thickness
    float alpha = 1.0 - smoothstep(core_thickness, core_thickness + glow_thickness, distance_from_ring);

    ALBEDO = wave_color.rgb * emission_strength;
    ALPHA = alpha * wave_color.a;
}