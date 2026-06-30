shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, world_vertex_coords;

uniform sampler2DArray baked_displacement : filter_linear_mipmap, repeat_enable;
uniform float playback_speed = 20.0; 
uniform float displacement_scale = 1.0;
uniform float tile_length = 88.0; 

// Visuals
uniform vec3 water_color : source_color = vec3(0.05, 0.15, 0.25);
uniform vec3 foam_color : source_color = vec3(0.9, 0.9, 0.95);
uniform vec3 crest_color : source_color = vec3(0.0, 0.65, 0.85);

uniform float crest_glow_intensity : hint_range(0.0, 2.0) = 0.8;
uniform float aerated_foam_glow : hint_range(0.0, 2.0) = 0.5;

// NEW: Foam Extractors
uniform float foam_threshold : hint_range(0.0, 1.0) = 0.05;
uniform float foam_multiplier : hint_range(0.0, 10.0) = 2.0;

uniform float roughness : hint_range(0.0, 1.0) = 0.4;
uniform float metallic : hint_range(0.0, 1.0) = 0.05;

// Variables passed between functions
varying float wave_height;
varying float raw_foam;
varying vec2 world_uv;

void vertex() {
    float total_frames = float(textureSize(baked_displacement, 0).z);
    
    float current_frame = TIME * playback_speed;
    float frame_a = floor(current_frame);
    float frame_b = frame_a + 1.0;
    
    frame_a = mod(frame_a, total_frames);
    frame_b = mod(frame_b, total_frames);
    
    float blend_factor = fract(current_frame);
    
    world_uv = VERTEX.xz / tile_length;
    
    vec4 data_a = textureLod(baked_displacement, vec3(world_uv, frame_a), 0.0);
    vec4 data_b = textureLod(baked_displacement, vec3(world_uv, frame_b), 0.0);
    vec4 final_data = mix(data_a, data_b, blend_factor);
    
    VERTEX += final_data.xyz * displacement_scale;
    
    wave_height = final_data.y * displacement_scale;
    raw_foam = final_data.w; 
}

void fragment() {
    // --- 1. HIGH RESOLUTION NORMALS ---
    // We recalculate the frame times to sample the exact same frame blending
    float total_frames = float(textureSize(baked_displacement, 0).z);
    float current_frame = TIME * playback_speed;
    float frame_a = mod(floor(current_frame), total_frames);
    float frame_b = mod(frame_a + 1.0, total_frames);
    float blend_factor = fract(current_frame);

    // Look slightly to the left/right and up/down on the texture
    vec2 e = vec2(0.005, 0.0); 
    
    float h_right = mix(textureLod(baked_displacement, vec3(world_uv + e.xy, frame_a), 0.0).y, textureLod(baked_displacement, vec3(world_uv + e.xy, frame_b), 0.0).y, blend_factor);
    float h_left  = mix(textureLod(baked_displacement, vec3(world_uv - e.xy, frame_a), 0.0).y, textureLod(baked_displacement, vec3(world_uv - e.xy, frame_b), 0.0).y, blend_factor);
    
    float h_down = mix(textureLod(baked_displacement, vec3(world_uv + e.yx, frame_a), 0.0).y, textureLod(baked_displacement, vec3(world_uv + e.yx, frame_b), 0.0).y, blend_factor);
    float h_up   = mix(textureLod(baked_displacement, vec3(world_uv - e.yx, frame_a), 0.0).y, textureLod(baked_displacement, vec3(world_uv - e.yx, frame_b), 0.0).y, blend_factor);

    // Mathematically construct the perfect curve of the wave, ignoring the mesh polygons
    vec3 normal_map = normalize(vec3(h_left - h_right, e.x * 2.0 * tile_length / displacement_scale, h_up - h_down));
    
    // Apply to lighting
    NORMAL = (VIEW_MATRIX * vec4(normal_map, 0.0)).xyz;

    // --- 2. FOAM RECOVERY ---
    // Force the dark alpha channel data into bright white foam
    float foam_factor = smoothstep(foam_threshold, 1.0, raw_foam * foam_multiplier);

    // --- 3. SUBSURFACE GLOW ---
    float wave_crest_mask = smoothstep(0.5, 3.5, wave_height);
    float aerated_mask = smoothstep(0.1, 0.9, foam_factor);
    float total_subsurface = clamp((wave_crest_mask * crest_glow_intensity) + (aerated_mask * aerated_foam_glow), 0.0, 1.0);
    
    vec3 water_with_glow = mix(water_color, crest_color, total_subsurface);
    ALBEDO = mix(water_with_glow, foam_color, foam_factor);
    
    ROUGHNESS = mix(roughness, 1.0, foam_factor);
    METALLIC = metallic;
}