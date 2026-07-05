shader_type spatial;
// Unshaded disables PBR overhead for maximum 60fps performance. 
render_mode unshaded, cull_back;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D flow_map : hint_default_black;
uniform sampler2D normal_map : hint_normal;
uniform sampler2D color_ramp : hint_default_white;

uniform vec4 core_color : source_color = vec4(0.2, 0.5, 1.0, 1.0);
uniform float flow_speed = 0.3;
uniform float flow_strength = 0.15;
uniform float refraction_strength = 0.05;
uniform float emission_energy = 2.0;

void fragment() {
    // 1. Calculate Flowmap Direction
    vec2 flow_dir = texture(flow_map, UV).rg * 2.0 - 1.0;
    flow_dir *= flow_strength;

    // 2. Dual-Phase Panning (creates seamless, infinitely looping fluid motion)
    float phase0 = fract(TIME * flow_speed);
    float phase1 = fract(TIME * flow_speed + 0.5);
    
    // Calculates a triangle wave to fade smoothly between the two phases
    float flow_lerp = abs((0.5 - phase0) * 2.0);

    vec2 uv0 = UV + flow_dir * phase0;
    vec2 uv1 = UV + flow_dir * phase1;

    // 3. Sample and blend the normal maps
    vec3 normal0 = texture(normal_map, uv0).rgb;
    vec3 normal1 = texture(normal_map, uv1).rgb;
    vec3 blended_normal = mix(normal0, normal1, flow_lerp);
    
    // Unpack normal from 0..1 to -1..1 range
    vec3 unpacked_normal = blended_normal * 2.0 - 1.0;

    // 4. Color Ramp Mapping
    // Use the intensity of the distortion to sample different parts of the color ramp
    float distortion = clamp(length(unpacked_normal.xy), 0.0, 1.0);
    vec3 mapped_color = texture(color_ramp, vec2(distortion, 0.5)).rgb;

    // 5. Screen Refraction
    // Offset the screen UV using our distorted normal vectors
    vec2 screen_uv = SCREEN_UV + unpacked_normal.xy * refraction_strength;
    vec3 refracted_bg = texture(screen_texture, screen_uv).rgb;

    // 6. Fresnel Edge Glow (simulates the dense atmosphere on the edges)
    float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);

    // 7. Final Output
    // Combine refracted background with our mapped color ramp, boosted by energy levels
    vec3 final_color = refracted_bg * mapped_color * core_color.rgb;
    vec3 edge_glow = core_color.rgb * fresnel * (emission_energy * 1.5);
    
    ALBEDO = final_color + edge_glow;
}