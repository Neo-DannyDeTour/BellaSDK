shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// Instance Uniforms: These receive data perfectly from the Node's GDScript 
// keeping draw calls optimized without sharing data across entirely different meshes.
instance uniform bool is_armored = false;
instance uniform vec2 glass_scale = vec2(2.0, 2.0);
instance uniform vec4 glass_color : source_color = vec4(0.8, 0.9, 1.0, 0.4);
instance uniform vec4 net_color : source_color = vec4(0.1, 0.1, 0.1, 1.0);
instance uniform float net_scale = 20.0;

// Standard Uniforms: These remain safely shared.
group_uniforms Glass_Properties;
uniform float roughness : hint_range(0.0, 1.0) = 0.1;

group_uniforms Refraction_and_Distortion;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D distortion_texture : hint_normal;
uniform float distortion_amount : hint_range(0.0, 1.0) = 0.05;

group_uniforms Glass_Block_Effect;
uniform float block_tiles : hint_range(1.0, 50.0) = 1.0;
uniform float block_deform : hint_range(0.0, 1.0) = 0.0;

group_uniforms Armored_Net;
uniform float net_thickness : hint_range(0.0, 0.5) = 0.05;

varying vec3 local_normal;

void vertex() {
    local_normal = NORMAL;
}

void fragment() {
    // 1. Build the Diagonal Armored Net Grid
    vec2 physical_uv = UV * glass_scale;
    vec2 diag_uv = vec2(physical_uv.x + physical_uv.y, physical_uv.x - physical_uv.y) * 0.707106;
    
    float line_x = step(fract(diag_uv.x * net_scale), net_thickness);
    float line_y = step(fract(diag_uv.y * net_scale), net_thickness);
    
    float is_flat_face = step(0.9, abs(local_normal.z));
    float is_net = max(line_x, line_y) * float(is_armored) * is_flat_face;
    
    // 2. Calculate Glass Block Deformation
    vec2 block_uv = fract(UV * block_tiles) - 0.5;
    vec2 block_offset = block_uv * block_deform;
    
    // 3. Calculate Noise Distortion
    vec3 noise = texture(distortion_texture, UV).rgb * 2.0 - 1.0;
    vec2 distort_offset = noise.xy * distortion_amount;
    
    // Combine offsets against the screen space
    vec2 final_screen_uv = SCREEN_UV + block_offset + distort_offset;
    
    // 4. Sample the background
    vec3 screen_color = textureLod(screen_texture, final_screen_uv, 0.0).rgb;
    
    if (is_armored && is_net > 0.5) {
        ALBEDO = net_color.rgb;
        ALPHA = 1.0;
        METALLIC = 0.9;
        ROUGHNESS = 0.3;
    } else {
        ALBEDO = mix(screen_color, glass_color.rgb, glass_color.a);
        ALPHA = 0.99;
        METALLIC = 0.1;
        ROUGHNESS = roughness;
    }
}