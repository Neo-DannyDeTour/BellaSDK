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
uniform float wind_speed = 2.0;

void fog() {
    // 1. Calculate wind movement
    vec3 wind_offset = normalize(wind_direction) * (wind_speed * TIME);
    
    // 2. Sample the Base Noise (Big shapes)
    vec3 base_pos = (WORLD_POSITION * noise_scale) + wind_offset;
    float base_noise = texture(noise_texture, base_pos).r;
    
    // 3. Sample Detail Noise (Breaks the repetition)
    // We multiply the scale by an irrational number (like 3.14) so the grid never lines up perfectly
    vec3 detail_pos = (WORLD_POSITION * (noise_scale * 3.14)) + (wind_offset * 1.5); 
    float detail_noise = texture(noise_texture, detail_pos).r;
    
    // Combine them: Subtract a bit of detail from the base to carve out random chunks
    float combined_noise = base_noise - (detail_noise * 0.4);
    
    // 4. The Height Gradient
    float height_gradient = UVW.y;
    float shape_modifier = smoothstep(0.0, 0.1, height_gradient) * smoothstep(1.0, 0.3, height_gradient);
    
    // 5. Apply coverage threshold
    float final_cloud = (combined_noise - (1.0 - cloud_coverage)) * shape_modifier;
    final_cloud = max(0.0, final_cloud);
    
    // 6. Fake self-shadowing
    vec3 final_albedo = mix(shadow_color, cloud_color, height_gradient + 0.2);
    
    DENSITY = final_cloud * density_multiplier;
    ALBEDO = final_albedo;
}