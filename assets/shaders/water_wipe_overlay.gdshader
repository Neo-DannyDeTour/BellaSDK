shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float drop_intensity : hint_range(0.0, 1.0) = 0.0; 
uniform float wash_intensity : hint_range(0.0, 1.0) = 0.0; 
uniform float clear_progress : hint_range(0.0, 1.5) = 1.0; 

const vec3 light_dir = vec3(0.5, 0.5, 1.0);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    if (drop_intensity <= 0.001 && wash_intensity <= 0.001 && clear_progress >= 0.999) {
        COLOR = texture(screen_tex, SCREEN_UV);
    } else {
        vec2 aspect_uv = UV * vec2(1.77, 1.0);
        vec2 total_distortion = vec2(0.0);
        float specular_light = 0.0; 
        
        // ==========================================
        // 0. DIAGONAL WIPE MASK
        // ==========================================
        float diag = (UV.x + UV.y) * 0.5; 
        float wipe_noise = sin(UV.y * 35.0 + TIME * 2.0) * 0.02 + sin(UV.x * 25.0 - TIME * 1.5) * 0.02 + (hash(UV * 10.0) - 0.5) * 0.02;
        float edge = diag + wipe_noise;
        
        float thick_threshold = clear_progress * 1.4 - 0.2;
        // thick_mask represents the heavy underwater volume
        float thick_mask = smoothstep(thick_threshold - 0.04, thick_threshold + 0.04, edge);
        
        // wiped_area represents the clean lens behind the wipe
        float wiped_area = 1.0 - thick_mask;
        
        // Droplets and ripples only exist where the lens has been wiped!
        float final_drop_intensity = drop_intensity * wiped_area;
        float final_wash_intensity = wash_intensity * wiped_area;
        
        // ==========================================
        // 1. POP-IN DROPLETS 
        // ==========================================
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
            
            float current_active_level = mix(0.15, 0.95, final_drop_intensity);
            float visibility = smoothstep(spawn_threshold, spawn_threshold + 0.1, current_active_level);
            
            if (life > 0.0 && dist < radius && visibility > 0.0) {
                float mask = smoothstep(radius, radius * 0.7, dist) * life * visibility;
                float z = sqrt(radius * radius - dist * dist);
                vec3 normal = normalize(vec3(offset.x, offset.y, z * 0.6));
                
                total_distortion += normal.xy * mask * 0.15;
                float spec = pow(max(dot(normal, normalize(light_dir)), 0.0), 64.0);
                specular_light += spec * mask * 1.5;
            }
        }
        
        total_distortion *= final_drop_intensity;
        specular_light *= final_drop_intensity;
        
        // ==========================================
        // 2. BIOSHOCK MULTI-WAVE RIPPLES
        // ==========================================
        if (final_wash_intensity > 0.0) {
            vec2 center_uv = (SCREEN_UV - 0.5) * vec2(1.77, 1.0);
            float dist_from_center = length(center_uv);
            float t = TIME * 12.0;
            
            float wave1 = sin(dist_from_center * 25.0 - t);
            float wave2 = sin(dist_from_center * 40.0 - t * 1.3) * 0.5; 
            float wave3 = cos(dist_from_center * 15.0 - t * 0.7) * 0.7; 
            
            float complex_ring = wave1 + wave2 + wave3;
            float center_mask = smoothstep(0.0, 0.3, dist_from_center);
            
            vec2 ripple_dist = normalize(center_uv) * complex_ring * 0.015 * final_wash_intensity * center_mask;
            total_distortion += ripple_dist;
        }

        // ==========================================
        // 3. APPLY THICK REFRACTION (Underwater)
        // ==========================================
        // Multiplier reduced from 0.03 to 0.01 for weaker ripples
        vec2 thick_refraction = vec2(sin(UV.y * 20.0 + TIME * 8.0), cos(UV.x * 20.0 + TIME * 7.0)) * 0.01;
        total_distortion += thick_refraction * thick_mask;

        // ==========================================
        // 4. RENDER THE SCREEN
        // ==========================================
        vec4 screen_color = textureLod(screen_tex, SCREEN_UV - total_distortion, abs(total_distortion.x) * 10.0);
        COLOR = screen_color + vec4(vec3(specular_light), 0.0);
    }
}