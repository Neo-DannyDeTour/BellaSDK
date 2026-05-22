shader_type fog;

uniform sampler3D noise_texture : repeat_enable; // Ensure your NoiseTexture3D is seamless
uniform float noise_scale = 0.02;

// Cloud Shaping
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform float density_multiplier : hint_range(0.0, 20.0) = 8.0;

// Lighting
uniform vec3 cloud_color : source_color = vec3(0.9, 0.95, 1.0);
uniform vec3 shadow_color : source_color = vec3(0.3, 0.35, 0.4);

// Wind mapped to global static variables
uniform vec3 wind_direction = vec3(1.0, 0.0, 0.0);
uniform float wind_speed = 2;

void fog() {
    // 1. Calculate wind movement
    vec3 wind_offset = normalize(wind_direction) * (wind_speed * TIME);
    
    // 2. Sample Macro Noise (NEW: Massive shapes for weather zones)
    // We multiply noise_scale by 0.15 to make these shapes huge, and move them slower
    vec3 macro_pos = (WORLD_POSITION * (noise_scale * 0.15)) + (wind_offset * 0.3);
    float macro_noise = texture(noise_texture, macro_pos).r;
    
    // 3. Sample Base Noise (Medium shapes)
    vec3 base_pos = (WORLD_POSITION * noise_scale) + wind_offset;
    float base_noise = texture(noise_texture, base_pos).r;
    
    // 4. Sample Detail Noise (Small, fast wisps)
    vec3 detail_pos = (WORLD_POSITION * (noise_scale * 3.14)) + (wind_offset * 1.5); 
    float detail_noise = texture(noise_texture, detail_pos).r;
    
    // 5. Combine the noises
    // Base provides the core shape, Macro clusters them together, Detail erodes the edges
    float combined_noise = (base_noise * 0.6) + (macro_noise * 0.5) - (detail_noise * 0.3);
    
    // 6. The Height Gradient
    float height_gradient = UVW.y;
    float shape_modifier = smoothstep(0.0, 0.15, height_gradient) * smoothstep(1.0, 0.4, height_gradient);
    
    // 7. Apply Dynamic Coverage (NEW)
    // Instead of a flat threshold, we use the macro noise to push the threshold up or down.
    // mix(0.5, 1.5) means in some areas coverage is halved (clear sky), in others it's boosted by 50% (massive clouds).
    float dynamic_coverage = cloud_coverage * mix(0.5, 1.5, macro_noise);
    
    // Calculate final density
    float final_cloud = (combined_noise - (1.0 - dynamic_coverage)) * shape_modifier;
    final_cloud = max(0.0, final_cloud);
    
    // 8. Fake self-shadowing
    vec3 final_albedo = mix(shadow_color, cloud_color, height_gradient + 0.2);
    
    DENSITY = final_cloud * density_multiplier;
    ALBEDO = final_albedo;
}