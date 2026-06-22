shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float distortion_strength : hint_range(0.0, 0.1) = 0.05;
uniform float chromatic_aberration : hint_range(0.0, 0.05) = 0.01;
uniform float pulse_speed : hint_range(0.0, 10.0) = 4.0;
uniform vec4 rim_color : source_color = vec4(0.5, 0.8, 1.0, 1.0);

// Ripple properties
uniform float ripple_frequency : hint_range(0.0, 50.0) = 20.0;
uniform float ripple_speed : hint_range(0.0, 10.0) = 5.0;
uniform float ripple_amplitude : hint_range(0.0, 1.0) = 0.3;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Pass local coordinates to the fragment shader for perfect spherical ripples
varying vec3 local_pos;

void vertex() {
    local_pos = VERTEX;
}

void fragment() {
    // 1. Calculate the distance from the center in local 3D space
    float dist = length(local_pos);
    
    // 2. Generate the expanding ripple waves
    float ripple = sin(dist * ripple_frequency - TIME * ripple_speed);
    
    // Remap ripple from [-1.0, 1.0] to [0.0, 1.0]
    ripple = (ripple + 1.0) * 0.5;

    // 3. Base pulse
    float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;
    
    // 4. Combine pulse and ripples for dynamic screen distortion
    float current_distortion = distortion_strength * (pulse + ripple * ripple_amplitude);
    
    // Offset based on surface normals
    vec2 offset = NORMAL.xy * current_distortion;
    
    // Chromatic Aberration sampling
    vec2 uv_r = SCREEN_UV + offset * (1.0 + chromatic_aberration);
    vec2 uv_g = SCREEN_UV + offset;
    vec2 uv_b = SCREEN_UV + offset * (1.0 - chromatic_aberration);
    
    float r = texture(screen_texture, uv_r).r;
    float g = texture(screen_texture, uv_g).g;
    float b = texture(screen_texture, uv_b).b;
    
    vec3 warped_scene = vec3(r, g, b);
    
    // 5. Calculate a glowing rim on the edges of the sphere
    float rim_math = 1.0 - dot(VIEW, NORMAL);
    float rim_intensity = smoothstep(0.4, 1.0, rim_math);
    
    // Inject the ripple into the glowing edge so the waves are visible in the color
    float glow_intensity = pulse + (ripple * ripple_amplitude);
    
    ALBEDO = mix(warped_scene, rim_color.rgb, rim_intensity * rim_color.a * glow_intensity);
    
    // Fade out completely near the center for a bubble-like appearance
    ALPHA = smoothstep(0.0, 0.3, rim_math);
}