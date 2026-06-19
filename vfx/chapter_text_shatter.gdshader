shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;

// The timeline configuration
uniform float intro_ratio : hint_range(0.0, 1.0) = 0.25;
uniform float outro_ratio : hint_range(0.0, 1.0) = 0.75;

// Controls the visual density and spread of the shatter
uniform float grid_size = 40.0; // Increased for finer pieces
uniform float scatter_distance = 0.5;
uniform float gravity = 0.8;

// Cheap pseudo-random generation
float rand(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    // 1. Define the grid block for the current pixel
    vec2 grid_uv = floor(UV * grid_size);

    // --- TIMELINE MAPPING ---
    // Intro maps progress 0.0 -> intro_ratio to a countdown of 1.0 -> 0.0 (flying inward)
    float intro_prog = 1.0 - clamp(progress / intro_ratio, 0.0, 1.0);
    
    // Outro maps progress outro_ratio -> 1.0 to a countup of 0.0 -> 1.0 (exploding outward)
    float outro_prog = clamp((progress - outro_ratio) / (1.0 - outro_ratio), 0.0, 1.0);

    // --- RANDOMNESS GENERATION ---
    // We add arbitrary arbitrary offsets to the grid coordinate to generate 
    // two completely distinct explosion patterns for entering and exiting.
    float hash_in = rand(grid_uv + vec2(13.37, 42.0));
    float hash_out = rand(grid_uv + vec2(73.31, 24.0));

    // --- PHASE 1: UNSHATTER (Intro) ---
    float angle_in = hash_in * 6.2831;
    // Randomize speed slightly per chunk so they don't move uniformly
    float speed_in = (hash_in * 0.5 + 0.5) * scatter_distance; 
    vec2 dir_in = vec2(cos(angle_in), sin(angle_in)) * speed_in;
    
    vec2 intro_offset = dir_in * intro_prog;
    intro_offset.y += pow(intro_prog, 2.5) * gravity; // Gravity arc

    // --- PHASE 3: SHATTER (Outro) ---
    float angle_out = hash_out * 6.2831;
    float speed_out = (hash_out * 0.5 + 0.5) * scatter_distance;
    vec2 dir_out = vec2(cos(angle_out), sin(angle_out)) * speed_out;
    
    vec2 outro_offset = dir_out * outro_prog;
    outro_offset.y += pow(outro_prog, 2.5) * gravity; // Gravity arc

    // Combine offsets. During Phase 2 (Hold), both intro_prog and outro_prog are 0.0.
    vec2 final_offset = intro_offset + outro_offset;
    vec2 sample_uv = UV - final_offset;

    // Viewport bounds culling to prevent texture wrapping/atlas bleeding
    if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
        COLOR = vec4(0.0);
    } else {
        vec4 tex = texture(TEXTURE, sample_uv);
        
        // Dynamically fade out chunks as they fly further away
        float alpha_mask = 1.0 - max(intro_prog, outro_prog);
        COLOR = vec4(tex.rgb, tex.a * alpha_mask);
    }
}