shader_type spatial;
// Keep blend_mix to allow the faked screen texture transparency to work
render_mode specular_schlick_ggx, blend_mix;

uniform vec4 base_color : source_color = vec4(0.1, 0.25, 0.35, 0.4);
uniform float deformation_speed = 2.0;
uniform float deformation_strength = 0.08;

// --- Refraction & Blur Uniforms ---
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float refraction_strength : hint_range(0.0, 1.0) = 0.15; // Increased for more visible distortion
uniform float blur_amount : hint_range(0.0, 5.0) = 2.0;

// --- Surface Ripple Uniforms ---
uniform float ripple_grid_size = 6.0; 
uniform float ripple_frequency = 25.0; 
uniform float ripple_speed = 1.0; 
uniform float ripple_strength = 0.2; 

// High quality, stable hash function for pseudo-randomness without slow sin() calculations
vec3 hash32(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yzz) * p3.zyx);
}

// Calculates the true height of overlapping ripples at a given UV
float get_ripples_height(vec2 uv, float time) {
    vec2 id = floor(uv);
    vec2 local_uv = fract(uv);
    float total_height = 0.0;

    // Sample the current cell and 8 surrounding cells (3x3) to allow waves to overlap
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 offset = vec2(float(x), float(y));
            vec2 cell_id = id + offset;
            
            vec3 rand = hash32(cell_id);
            vec2 drop_pos = offset + rand.xy; 
            
            float dist = length(local_uv - drop_pos);
            
            float drop_life = fract(time + rand.z);
            float current_radius = drop_life * 1.5; 
            
            float mask = smoothstep(0.0, 0.15, current_radius - dist) 
                       * smoothstep(0.0, 0.4, dist - (current_radius - 0.5));
            mask = max(0.0, mask);
            
            float wave = sin((dist - drop_life * 1.5) * ripple_frequency + rand.z * 6.2831);
            
            float age_fade = 1.0 - drop_life;
            age_fade *= age_fade; 
            
            total_height += wave * mask * age_fade;
        }
    }
    return total_height;
}

// Converts our mathematical height map into a tangent-space Normal Map
vec3 compute_ripple_normal(vec2 uv, float time, float grid_size, float strength) {
    vec2 e = vec2(0.01, 0.0);
    vec2 scaled_uv = uv * grid_size;
    
    float h = get_ripples_height(scaled_uv, time);
    float hx = get_ripples_height(scaled_uv + e.xy, time);
    float hy = get_ripples_height(scaled_uv + e.yx, time);
    
    vec3 n = normalize(vec3(h - hx, h - hy, e.x / strength));
    return n;
}

void vertex() {
    // Generate organic ripples over the sphere surface (Shape Deformation)
    float wave_x = sin(VERTEX.y * 4.0 + TIME * deformation_speed);
    float wave_y = cos(VERTEX.x * 4.0 + TIME * deformation_speed * 1.2);
    float combined_wave = (wave_x + wave_y) * 0.5;
    
    VERTEX += NORMAL * combined_wave * deformation_strength;
}

void fragment() {
    // 1. Generate Tangent-Space Ripple Normal
    vec3 ripple_normal = compute_ripple_normal(UV, TIME * ripple_speed, ripple_grid_size, ripple_strength);
    NORMAL_MAP = ripple_normal;
    
    // 2. Convert to View-Space Normal for accurate screen distortion
    // This physically aligns the ripples and the sphere's curvature with the camera lens
    vec3 view_normal = normalize(TANGENT * ripple_normal.x + BINORMAL * ripple_normal.y + NORMAL * ripple_normal.z);
    
    // 3. Screen Space Refraction & Blur
    vec2 ref_ofs = view_normal.xy * refraction_strength;
    vec3 refracted_bg = textureLod(screen_texture, SCREEN_UV + ref_ofs, blur_amount).rgb;
    
    // 4. Final Output
    ALBEDO = mix(refracted_bg, base_color.rgb, base_color.a);
    ALPHA = 1.0; 
    
    ROUGHNESS = 0.1;
    METALLIC = 0.9;
    
    float fresnel = sqrt(max(1.0 - dot(NORMAL, VIEW), 0.0));
    ALBEDO += vec3(0.1, 0.3, 0.5) * fresnel * 0.5;
}