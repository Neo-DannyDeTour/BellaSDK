shader_type spatial;
// We use cull_disabled so the waterfall is visible from both sides.
// Opaque rendering is used for maximum performance.
render_mode specular_schlick_ggx, cull_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D normal_map : hint_roughness_normal, filter_linear_mipmap, repeat_enable;

uniform vec2 scroll_speed = vec2(0.0, -1.5);
uniform float refraction_strength = 0.03;
uniform vec4 water_tint : source_color = vec4(0.6, 0.8, 0.85, 0.3);
uniform float roughness_val = 0.15;

void fragment() {
    // 1. Scroll the UV coordinates downward to simulate flowing water
    vec2 uv_scrolled = UV + (scroll_speed * TIME);
    
    // 2. Sample the normal map at the scrolled coordinates
    vec3 normal_data = texture(normal_map, uv_scrolled).rgb;
    vec3 unpacked_normal = normal_data * 2.0 - 1.0;
    
    // 3. Offset the screen texture coordinates by the normal's X and Y
    vec2 ref_uv = SCREEN_UV + (unpacked_normal.xy * refraction_strength);
    vec3 ref_color = texture(screen_texture, ref_uv).rgb;
    
    // 4. Mix the distorted background with the water's tint color
    // The alpha channel of water_tint acts as the mix ratio.
    ALBEDO = mix(ref_color, water_tint.rgb, water_tint.a);
    NORMAL_MAP = normal_data;
    ROUGHNESS = roughness_val;
    METALLIC = 0.0;
    
    // Alpha remains 1.0 because the screen texture handles the "transparency"
    ALPHA = 1.0; 
}