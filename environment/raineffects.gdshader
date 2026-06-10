/*
AAA Procedural Rain & Puddle Shader - Vector Stable Edition
Fixed: Implemented Absolute World-Space Triplanar Mapping for weather effects.
*/

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ==========================================
// 1. BASE MATERIAL
// ==========================================
group_uniforms Base_Material;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal;
uniform sampler2D roughness_tex : hint_default_white;
uniform sampler2D height_tex : hint_default_black; 
uniform float uv_scale : hint_range(0.1, 20.0) = 1.0;

// ==========================================
// 2. WEATHER SYSTEM
// ==========================================
group_uniforms Weather_System;
uniform float rain_amount : hint_range(0.0, 1.0) = 1.0; 
uniform float wetness : hint_range(0.0, 1.0) = 0.5; 
uniform float puddle_darkening : hint_range(0.0, 1.0) = 0.6; 
uniform float rain_falloff_angle : hint_range(-1.0, 1.0) = 0.0; 

// ==========================================
// 3. MACRO PUDDLES
// ==========================================
group_uniforms Macro_Puddles;
uniform sampler2D macro_noise_tex : hint_default_black; 
uniform float macro_noise_scale : hint_range(0.01, 1.0) = 0.1;
uniform float macro_noise_contrast : hint_range(0.0, 0.99) = 0.3; 
uniform float puddle_spread : hint_range(0.0, 1.0) = 0.3;
uniform float puddle_edge_softness : hint_range(0.001, 0.5) = 0.05;

// ==========================================
// 4. TOP DROPS
// ==========================================
group_uniforms Top_Drops;
uniform sampler2D drops_tex; 
uniform float drops_size : hint_range(0.1, 10.0) = 1.0;
uniform float drops_intensity : hint_range(0.0, 10.0) = 1.0; 
uniform float static_drops : hint_range(0.0, 1.0) = 0.0; 

// ==========================================
// 5. SIDE STREAKS
// ==========================================
group_uniforms Side_Streaks;
// NOTE: Ensure this texture is populated in the inspector!
uniform sampler2D streaks_tex; 
uniform float streaks_scale : hint_range(0.1, 10.0) = 1.0;
uniform float streaks_speed : hint_range(0.0, 2.0) = 0.2;
uniform float streaks_angle : hint_range(0.0, 1.0) = 0.8; 

// ==========================================
// 6. RIPPLES
// ==========================================
group_uniforms Ripples;
uniform sampler2D ripples_tex; 
uniform float ripples_scale : hint_range(0.01, 2.0) = 0.1;
uniform float ripples_intensity : hint_range(0.0, 2.0) = 1.0;

// ==========================================
// 7. PUDDLE WAVES
// ==========================================
group_uniforms Puddle_Waves;
uniform sampler2D wave_noise_tex : hint_normal; 
uniform float wave_scale : hint_range(0.1, 10.0) = 2.0;
uniform float wave_speed : hint_range(0.0, 1.0) = 0.1;
uniform float wave_strength : hint_range(0.0, 1.0) = 0.3;

varying vec3 v_world_pos;

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// --- DROP MATH ---
vec4 get_drops(vec2 drops_uv, float time) {
    vec4 drops;
    vec4 drops_tex_color = textureLod(drops_tex, drops_uv * drops_size, 0.0);
    drops.xyz = vec3(drops_tex_color.rg, 1.0);
    float static_drops_mask = 1.0 - step(0.1, drops_tex_color.a);
    
    float animated_shift = drops_intensity * fract((drops_tex_color.b * 2.0 - 1.0) - time * 0.25);
    float time_shift = mix(animated_shift, drops_intensity, static_drops);
    
    float dyn_drops_mask = step(0.9, drops_tex_color.a) * time_shift;
    vec3 drops_dyn = mix(vec3(0.5, 0.5, 1.0), drops.xyz, time_shift);
    
    drops.a = dyn_drops_mask + static_drops_mask;
    drops.xyz = mix(vec3(0.5, 0.5, 1.0), drops.xyz, static_drops_mask);
    drops.xyz = mix(drops.xyz, drops_dyn, dyn_drops_mask);
    
    return drops;
}

// --- STREAK MATH ---
vec4 get_streaks(vec2 streaks_uv, float time) {
    vec4 streaks_tex_color = texture(streaks_tex, streaks_uv * streaks_scale);
    vec4 streaks;
    streaks.xyz = vec3(streaks_tex_color.rg, 1.0);
    streaks.a = streaks_tex_color.a;
    
    float drop_trail = texture(streaks_tex, vec2(streaks_uv.x, streaks_uv.y + time * streaks_speed)).b;
    streaks.a *= clamp(drop_trail - 0.4, 0.0, 1.0);
    streaks.a = smoothstep(0.0, 0.2, streaks.a);
    
    return streaks;
}

vec2 random_hash(vec2 p) {
    return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

float get_ripple_height(vec2 uv, float time, float scale) {
    vec2 grid_uv = uv * scale;
    vec2 grid_id = floor(grid_uv);
    vec2 grid_fract = fract(grid_uv);

    float ripple_height = 0.0;

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 neighbor = vec2(float(x), float(y));
            vec2 rand_point = random_hash(grid_id + neighbor);
            vec2 diff = neighbor + rand_point - grid_fract;
            float dist = length(diff);
            float drop_time = fract(time * 0.8 + rand_point.x);
            float ring = sin(dist * 30.0 - drop_time * 20.0);
            float fade = smoothstep(0.6, 0.0, dist) * smoothstep(1.0, 0.7, drop_time) * smoothstep(0.0, 0.1, drop_time);
            ripple_height += ring * fade;
        }
    }
    return ripple_height;
}

// --- RIPPLE MATH ---
vec4 get_ripples(vec2 uv, float time) {
    float epsilon = 0.01; 
    float h  = get_ripple_height(uv, time, ripples_scale * 10.0);
    float hx = get_ripple_height(uv + vec2(epsilon, 0.0), time, ripples_scale * 10.0);
    float hy = get_ripple_height(uv + vec2(0.0, epsilon), time, ripples_scale * 10.0);
    
    vec3 normal = normalize(vec3(h - hx, h - hy, 0.5)); 
    return vec4(normal * 0.5 + 0.5, 1.0);
}

// --- PUDDLE WAVES ---
vec3 get_puddle_waves(vec2 uv, float time) {
    vec2 wave_uv_1 = (uv * wave_scale) + vec2(time * wave_speed, time * wave_speed * 0.5);
    vec2 wave_uv_2 = (uv * wave_scale * 0.8) + vec2(-time * wave_speed * 0.7, time * wave_speed * 0.3);
    
    vec3 w1 = texture(wave_noise_tex, wave_uv_1).rgb;
    vec3 w2 = texture(wave_noise_tex, wave_uv_2).rgb;
    
    vec3 n1 = w1 * 2.0 - 1.0;
    vec3 n2 = w2 * 2.0 - 1.0;
    vec3 final_wave = normalize(n1 + n2);
    
    return mix(vec3(0.5, 0.5, 1.0), final_wave * 0.5 + 0.5, wave_strength);
}

void fragment() {
    float time = TIME * 1.5;
    
    // Mesh UV for base textures so they stick to the object
    vec2 base_uv = UV * uv_scale;
    
    // Safely extract Absolute World Normal directly in fragment to prevent rotation skewing
    vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
    vec3 mask = abs(world_normal);
    
    // Absolute World Triplanar Mapping for Weather (Rain always falls straight down)
    vec2 side_uv_x = v_world_pos.zy; 
    vec2 side_uv_z = v_world_pos.xy; 
    float is_x_side = step(mask.z, mask.x);
    vec2 side_uv = mix(side_uv_z, side_uv_x, is_x_side);
    vec2 top_uv = v_world_pos.xz;
    
    // Angle evaluations
    float top_mask = smoothstep(streaks_angle - 0.1, streaks_angle + 0.1, world_normal.y);
    float rain_contact_mask = smoothstep(rain_falloff_angle, 0.0, world_normal.y); 
    float is_upwards = smoothstep(0.0, 0.1, world_normal.y);

    vec3 base_albedo = texture(albedo_tex, base_uv).rgb;
    vec3 base_normal = texture(normal_tex, base_uv).rgb;
    float base_roughness = texture(roughness_tex, base_uv).r;
    float surface_height = texture(height_tex, base_uv).r; 
    
    float raw_noise = texture(macro_noise_tex, top_uv * macro_noise_scale).r;
    float macro_noise = smoothstep(macro_noise_contrast, 1.0, raw_noise);
    
    float water_level = wetness + (macro_noise * puddle_spread);
    float puddle_depth = water_level - surface_height;
    
    // Puddles strictly clamped to upwards-facing normals
    float puddle_mask = smoothstep(0.0, puddle_edge_softness, puddle_depth);
    puddle_mask *= step(0.01, wetness) * is_upwards; 
    
    float damp_mask = smoothstep(0.0, 0.5, wetness) * rain_contact_mask; 
    
    vec3 base_water_normal = get_puddle_waves(top_uv, TIME); 
    vec3 water_surface_normal = base_water_normal; 
    
    vec4 top_drops = get_drops(top_uv, time);
    vec4 side_streaks = get_streaks(side_uv, time);
    vec4 final_drops = mix(side_streaks, top_drops, top_mask);
    
    vec3 drop_normal = final_drops.rgb;
    float drop_mask = final_drops.a * damp_mask * (1.0 - puddle_mask) * rain_amount; 
    
    vec4 ripples = get_ripples(top_uv, time);
    vec3 ripple_norm = mix(base_water_normal, ripples.rgb, ripples.a * ripples_intensity);
    water_surface_normal = mix(base_water_normal, ripple_norm, puddle_mask * rain_amount);
    
    vec3 final_albedo = base_albedo * (1.0 - (puddle_darkening * damp_mask));
    
    float final_roughness = mix(base_roughness, base_roughness * 0.4, damp_mask);
    final_roughness = mix(final_roughness, 0.07, drop_mask); 
    final_roughness = mix(final_roughness, mix(0.02, 0.08, wave_strength), puddle_mask); 
    
    vec3 final_normal = base_normal;
    final_normal = mix(final_normal, drop_normal, drop_mask);
    final_normal = mix(final_normal, water_surface_normal, puddle_mask);

    ALBEDO = final_albedo;
    ROUGHNESS = final_roughness;
    NORMAL_MAP = final_normal;
    SPECULAR = mix(0.5, 0.8, puddle_mask); 
}


///*
//Original Shader (MIT Licensed): https://github.com/Lexpartizan/Godot_rain_shader
//Modified & ported to Godot 4
//*/
//
//shader_type spatial;
//
//uniform sampler2D albedo : source_color;
//uniform sampler2D normal : hint_normal;
//uniform sampler2D rough : hint_default_white;
//uniform sampler2D metal : hint_default_black;
//
//uniform float scale_UV_material : hint_range(0.0, 10.0) = 1.0;
//uniform float scale_UV_rain : hint_range(0.0, 100.0) = 10.0;
//uniform sampler2D roofing_height : hint_default_black;
//uniform vec3 cam_heightmap_world_position;
//uniform float cam_heightmap_size : hint_range(1.0, 100.0) = 10.0;
//
//uniform bool rain = true;
//
//uniform float wet_level : hint_range(0.0, 1.0) = 0.5;
//uniform float water_metallnes : hint_range(0.0, 1.0) = 0.0;
//uniform float dry_angle : hint_range(-1.0, 1.0) = -0.1;
//uniform bool puddles_noise = true;
//uniform sampler2D puddles_tex : hint_default_black;
//uniform float streaks_length : hint_range(0.0, 1.0) = 0.5;
//uniform float streaks_angle : hint_range(0.0, 1.0) = 0.8;
//
//uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;
//uniform float without_snow_angle : hint_range(0.0, 1.0) = 0.3;
//uniform float snow_brightness : hint_range(0.0, 1.0) = 0.8;
//
//uniform sampler2D noise_tex;
//uniform sampler2D drops_tex;
//uniform sampler2D ripples_tex;
//uniform sampler2D streaks_tex;
//uniform sampler2D snow_norm : hint_normal;
//
//uniform float drops_intensity = 1.0;
//uniform bool static_drops = false;
//uniform float drops_size = 1.0;
//uniform bool no_ripples = false;
//
//varying vec3 world_pos;
//varying vec3 model_pos;
//varying vec3 weights;
//varying vec3 mask;
//
//varying float snow_distribution;
//varying float under_rain;
//varying float start_streaks_angle;
//varying float puddles_plain;
//varying float raining;
//varying float time;
//varying float wetness;
//varying float thin_layer_water;
//varying float puddles_amount;
//
//void vertex() {
    //world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    //model_pos = mat3(MODEL_MATRIX) * VERTEX;
    //weights = mat3(MODEL_MATRIX) * NORMAL;
    //mask = abs(weights);
    //
    //vec2 roof_uv = (world_pos.xz - cam_heightmap_world_position.xz) / cam_heightmap_size + 0.5;
    //float occluder = texture(roofing_height, roof_uv).g;
    //
    //occluder = step(world_pos.y, occluder - 0.25);
    //
    //float out_x = step(roof_uv.x, 1.0) * step(0.0, roof_uv.x);
    //float out_y = step(roof_uv.y, 1.0) * step(0.0, roof_uv.y);
    //occluder *= out_x * out_y;
    //
    //occluder = 1.0 - occluder;
    //time = TIME * 1.5;
    //raining = rain ? 1.0 : 0.0;
    //
    //under_rain = occluder * smoothstep(dry_angle, 0.0, weights.y);
    //snow_distribution = occluder * smoothstep(without_snow_angle, 1.0, weights.y);
    //start_streaks_angle = 1.0 - step(streaks_angle, weights.y);
    //puddles_plain = step(0.999, weights.y);
    //wetness = smoothstep(0.0, 0.5, wet_level);
    //thin_layer_water = smoothstep(0.5, 1.0, wet_level);
    //puddles_amount = smoothstep(0.05, 1.0, wet_level);
//}
//
//vec4 get_drops_and_streaks(vec2 drops_uv, vec2 streaks_uv, float p_time, 
                           //float p_start_streaks_angle, float p_raining, float p_under_rain) {
    //vec4 drops;
    //vec4 drops_tex_color = texture(drops_tex, drops_uv * drops_size);
    //drops.xyz = vec3(drops_tex_color.rg, 1.0);
    //float static_drops_mask = 1.0 - step(0.1, drops_tex_color.a);
    //
    //float time_shift = static_drops ? drops_intensity : 
                       //drops_intensity * fract((drops_tex_color.b * 2.0 - 1.0) - p_time * 0.25);
    //
    //float dyn_drops_mask = step(0.9, drops_tex_color.a) * time_shift;
    //vec3 drops_dyn = mix(vec3(0.5, 0.5, 1.0), drops.xyz, time_shift);
    //drops.a = dyn_drops_mask + static_drops_mask;
    //drops.xyz = mix(vec3(0.5, 0.5, 1.0), drops.xyz, static_drops_mask);
    //drops.xyz = mix(drops.xyz, drops_dyn, dyn_drops_mask);
    //
    //vec4 streaks_tex_color = texture(streaks_tex, streaks_uv);
    //vec4 streaks;
    //streaks.xyz = vec3(streaks_tex_color.rg, 1.0);
    //streaks.a = streaks_tex_color.a;
    //streaks.a *= p_start_streaks_angle;
    //
    //float s_fade = texture(streaks_tex, vec2(streaks_uv.x, streaks_uv.y + p_time * 0.2)).b;
    //streaks.a *= clamp(s_fade - (0.7 - 0.3 * streaks_length), 0.0, 1.0);
    //streaks.a = smoothstep(0.0, 0.2, streaks.a);
    //
    //drops = mix(drops, streaks, streaks.a);
    //drops.xyz = normalize(drops.xyz);
    //drops.a *= p_raining * p_under_rain;
    //
    //return drops;
//}
//
//vec4 get_puddles_and_ripples(vec3 puddles_normal, vec2 uv, vec2 uv_mat, 
                             //float p_puddles_amount, vec3 p_model_pos, float p_time, 
                             //float p_raining, float p_puddles_plain, float p_under_rain, 
                             //bool p_puddles_noise) {
    //vec4 puddles;
    //puddles.rgb = puddles_normal;
    //float noise_val = texture(noise_tex, p_model_pos.xz * 0.01).r;
    //puddles.a = smoothstep(1.0 - p_puddles_amount, 1.0, noise_val);
    //
    //vec2 ripples_uv = uv * 0.1;
    //vec4 rip_tex_1 = texture(ripples_tex, ripples_uv);
    //vec4 rip_tex_2 = texture(ripples_tex, ripples_uv * vec2(1.0, -1.0));
    //vec4 rip_tex_3 = texture(ripples_tex, ripples_uv * vec2(-1.0, 1.0));
    //vec4 rip_tex_4 = texture(ripples_tex, ripples_uv * vec2(-1.0, -1.0));
    //
    //vec4 rip1 = vec4(rip_tex_1.r, rip_tex_1.g, 1.0, rip_tex_1.a);
    //vec4 rip2 = vec4(rip_tex_2.r, rip_tex_2.g, 1.0, rip_tex_2.a);
    //vec4 rip3 = vec4(rip_tex_3.r, rip_tex_3.g, 1.0, rip_tex_3.a);
    //vec4 rip4 = vec4(rip_tex_4.r, rip_tex_4.g, 1.0, rip_tex_4.a);
    //
    //float t_rip_1 = fract(p_time * 0.5 + (rip_tex_1.b * 2.0 - 1.0));
    //float t_rip_2 = fract(p_time * 0.5 + 0.25 + (rip_tex_2.b * 2.0 - 1.0));
    //float t_rip_3 = fract(p_time * 0.5 + 0.5 + (rip_tex_3.b * 2.0 - 1.0));
    //float t_rip_4 = fract(p_time * 0.5 + 0.75 + (rip_tex_4.b * 2.0 - 1.0));
    //
    //float waves = 3.0;
    //rip1.a = smoothstep(0.0, 0.8, sin(clamp((t_rip_1 - 1.0 + rip1.a) * 20.0, 0.0, waves) * 6.28) * (1.0 - t_rip_1));
    //rip2.a = smoothstep(0.0, 0.8, sin(clamp((t_rip_2 - 1.0 + rip2.a) * 20.0, 0.0, waves) * 6.28) * (1.0 - t_rip_2));
    //rip3.a = smoothstep(0.0, 0.8, sin(clamp((t_rip_3 - 1.0 + rip3.a) * 20.0, 0.0, waves) * 6.28) * (1.0 - t_rip_3));
    //rip4.a = smoothstep(0.0, 0.8, sin(clamp((t_rip_4 - 1.0 + rip4.a) * 20.0, 0.0, waves) * 6.28) * (1.0 - t_rip_4));
    //
    //rip1 = mix(rip1, rip2, rip2.a);
    //rip1 = mix(rip1, rip3, rip3.a);
    //rip1 = mix(rip1, rip4, rip4.a);
    //rip1.rgb = normalize(rip1.rgb);
    //rip1.a *= p_raining;
    //
    //puddles.a *= p_puddles_noise ? 1.0 : 0.0;
    //puddles.a += texture(puddles_tex, uv_mat).r * p_puddles_amount;
    //
    //float mix_factor = step(0.7, rip1.a * step(0.85, puddles.a));
    //puddles = no_ripples ? puddles : mix(puddles, rip1, mix_factor);
    //puddles.a *= p_puddles_plain * p_under_rain;
    //
    //return puddles;
//}
//
//vec3 saturation(float sat, vec3 color) {
    //float oneMinusSat = 1.0 - sat;
    //vec3 luminance = vec3(0.3086, 0.6094, 0.0820) * oneMinusSat;
    //mat3 sat_matrix = mat3(
        //vec3(luminance.x) + vec3(sat, 0.0, 0.0),
        //vec3(luminance.y) + vec3(0.0, sat, 0.0),
        //vec3(luminance.z) + vec3(0.0, 0.0, sat)
    //);
    //return clamp(sat_matrix * color, 0.0, 1.0);
//}
//
//void fragment() {
    //vec2 triplanar_uv_rain; 
    //vec2 triplanar_uv_streaks;
    //vec2 triplanar_uv_snow;
    //
    //float branchless = step(mask.x, mask.z);
    //triplanar_uv_rain = model_pos.xy * branchless + model_pos.zy * (1.0 - branchless);
    //triplanar_uv_streaks = triplanar_uv_rain;
    //
    //branchless = step(mask.x, mask.y) * step(mask.z, mask.y);
    //triplanar_uv_rain = triplanar_uv_rain * (1.0 - branchless) + model_pos.xz * branchless;
    //
    //triplanar_uv_rain *= scale_UV_rain;
    //triplanar_uv_streaks *= scale_UV_rain * 0.2;
    //triplanar_uv_snow = model_pos.xz * scale_UV_rain * 0.1;
    //
    //vec2 uv_mat = UV * scale_UV_material;
    //
    //vec4 drops = get_drops_and_streaks(triplanar_uv_rain, triplanar_uv_streaks, 
                                       //time, start_streaks_angle, raining, under_rain);
                                       //
    //vec4 puddles = get_puddles_and_ripples(vec3(0.5, 0.5, 1.0), triplanar_uv_rain, uv_mat,
                                           //puddles_amount, model_pos, time, raining, 
                                           //puddles_plain, under_rain, puddles_noise);
                                           //
    //drops.a *= under_rain;
    //puddles.a *= under_rain;
    //
    //vec3 dry_albedo = texture(albedo, uv_mat).rgb;
    //vec3 snow_brightness_avg = texture(albedo, uv_mat, 10.0).rgb;
    //
    //// Safety check added to prevent Division by Zero on Pitch Black Textures
    //float safe_avg_x = max(snow_brightness_avg.x, 0.0001);
    //snow_brightness_avg.x = snow_brightness / safe_avg_x;
    //
    //float safe_snow_brightness = max(snow_brightness, 0.0001);
    //float val = snow_distribution * snow_amount / safe_snow_brightness;
    //float snow_mask = 1.0 - smoothstep(0.0, val, dry_albedo.r * snow_brightness_avg.x);
    //snow_mask = smoothstep(0.0, 0.8, snow_mask);
    //
    //dry_albedo = mix(dry_albedo, vec3(snow_brightness), snow_mask);
    //
    //float snow_dist_amt = smoothstep(0.8, 0.9, snow_distribution * snow_amount);
    //dry_albedo = mix(dry_albedo, vec3(snow_brightness), snow_dist_amt);
    //
    //float dry_rough = texture(rough, uv_mat).r;
    //dry_rough = mix(dry_rough, 1.0, snow_mask);
    //dry_rough = mix(dry_rough, 1.0, snow_dist_amt);
    //
    //vec3 norm = texture(normal, uv_mat).rgb;
    //vec3 snow_normals = texture(snow_norm, triplanar_uv_snow).rgb;
    //norm = mix(norm, snow_normals, snow_mask);
    //norm = mix(norm, snow_normals, snow_dist_amt);
        //
    //float dry_metalic = texture(metal, uv_mat).x;
    //dry_metalic = mix(dry_metalic, 0.0, snow_mask);
    //
    //float porosity = clamp((dry_rough - 0.5) / 0.4, 0.0, 1.0);
    //float factor = mix(1.0, 0.2, (1.0 - dry_metalic) * porosity);
    //float wet_rough = 1.0 - mix(1.0, 1.0 - dry_rough, mix(1.0, factor, wetness * 0.5));
    //
    //vec3 wet_albedo = saturation(1.0 + wetness, dry_albedo);
    //wet_albedo = wet_albedo * mix(1.0, factor, wetness);
    //wet_albedo = mix(dry_albedo, wet_albedo, under_rain);
    //
    //ALBEDO = mix(dry_albedo, wet_albedo, wetness);
    //METALLIC = dry_metalic;
    //
    //norm = mix(norm, drops.rgb, drops.a);
    //norm = mix(norm, puddles.rgb, puddles.a);
    //NORMAL_MAP = norm;
//
    //wet_rough = mix(wet_rough, 0.07, drops.a);
    //wet_rough = mix(wet_rough, 0.3, puddles.a);
    //wet_rough = mix(wet_rough, wet_rough * 0.5, thin_layer_water);
    //ROUGHNESS = mix(dry_rough, wet_rough, under_rain);
    //SPECULAR = puddles.a;
//}