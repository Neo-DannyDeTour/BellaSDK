shader_type canvas_item;

// Allows us to grab the screen behind the UI
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

uniform float clear_progress : hint_range(0.0, 1.5) = 0.0;
uniform float drop_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float wash_intensity : hint_range(0.0, 1.0) = 0.0;

uniform float distortion_strength = 0.04;
uniform float time_scale = 3.0;

// --- HASH FUNCTION REQUIRED FOR PROCEDURAL DROPLETS ---
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void fragment() {
    // --- 1. ASPECT RATIO CORRECTION ---
    // Keeps the droplets perfectly round regardless of your screen resolution
    vec2 aspect_uv = SCREEN_UV;
    aspect_uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

    // --- 2. THE WASH EFFECT (Flowing Water) ---
    vec2 flow_uv = UV;
    flow_uv.y -= TIME * time_scale;
    float wave = sin(flow_uv.x * 20.0 + TIME) * cos(flow_uv.y * 15.0);
    float wash_distortion = wave * distortion_strength * wash_intensity;
    
    // --- 3. POP-IN DROPLETS ---
    vec2 total_drop_distortion = vec2(0.0);
    float specular_light = 0.0;
    
    // Fake 2D light source pointing slightly down and right
    vec3 light_dir = normalize(vec3(0.5, 0.5, 1.0)); 

    for (float i = 1.0; i <= 2.0; i++) {
        float grid_scale = 4.5 * i; 
        vec2 grid_uv = aspect_uv * grid_scale;
        
        vec2 cell_id = floor(grid_uv);
        vec2 local_uv = fract(grid_uv) - 0.5;
        
        float r1 = hash(cell_id + i * 1.1);
        float r2 = hash(cell_id + i * 2.2);
        vec2 drop_pos = (vec2(r1, r2) - 0.5) * 0.5;
        vec2 offset = local_uv - drop_pos;
        
        float shape_seed = hash(cell_id + 7.0);
        vec2 shape_offset = offset;
        shape_offset.y += abs(shape_offset.x) * mix(0.0, 0.4, shape_seed);
        
        float wobble_freq = mix(3.0, 6.0, hash(cell_id + 8.0));
        float wobble = sin(atan(offset.y, offset.x) * wobble_freq) * mix(0.0, 0.02, shape_seed);
        
        float dist = length(shape_offset) + wobble;
        float radius = mix(0.12, 0.28, hash(cell_id + 10.0));
        
        float spawn_threshold = hash(cell_id + 5.0);
        float mapped_speed = mix(1.0, 4.5, spawn_threshold);
        
        float final_speed = max(0.5, mapped_speed + (hash(cell_id + 12.0) - 0.5) * 1.5); 
        float life = sin(TIME * final_speed + r1 * 6.28);
        
        float current_active_level = mix(0.15, 0.95, drop_intensity);
        float visibility = smoothstep(spawn_threshold, spawn_threshold + 0.1, current_active_level);
        
        if (life > 0.0 && dist < radius && visibility > 0.0) {
            float mask = smoothstep(radius, radius * 0.7, dist) * life * visibility;
            float z = sqrt(radius * radius - dist * dist);
            vec3 normal = normalize(vec3(offset.x, offset.y, z * 0.6));
            
            total_drop_distortion += normal.xy * mask * 0.15;
            float spec = pow(max(dot(normal, light_dir), 0.0), 64.0);
            specular_light += spec * mask * 1.5;
        }
    }
    
    total_drop_distortion *= drop_intensity;
    specular_light *= drop_intensity;

    // --- 4. THE WIPE MECHANIC ---
    // If UV.y is lower than the wipe line, it returns to 0 (clean).
// --- 4. THE WIPE MECHANIC (Only affects the heavy flowing wash) ---
    float wipe_mask = smoothstep(clear_progress - 0.2, clear_progress + 0.05, UV.y);
    
    // --- 5. COMBINE AND DISTORT SCREEN ---
    vec2 distorted_screen_uv = SCREEN_UV;
    
    // Droplets distort independently of the heavy wash wipe!
    distorted_screen_uv.x += (wash_distortion * wipe_mask) + total_drop_distortion.x;
    distorted_screen_uv.y += (wash_distortion * 1.5 * wipe_mask) + total_drop_distortion.y; 
    
    vec3 screen_color = texture(screen_texture, distorted_screen_uv).rgb;
    
    // --- 6. FINAL COLOR & HIGHLIGHTS ---
    vec3 wet_tint = vec3(0.8, 0.9, 1.0);
    float wetness_visibility = wash_intensity * wipe_mask * 0.15;
    vec3 final_color = mix(screen_color, wet_tint, wetness_visibility);
    
    // Add specular highlights from droplets (no wipe_mask multiplier here)
    final_color += vec3(specular_light);
    
    COLOR = vec4(final_color, 1.0);
}