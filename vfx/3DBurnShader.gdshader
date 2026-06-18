shader_type spatial;
render_mode cull_disabled; // Allows us to see the back of the plane

uniform sampler2D albedo_texture : source_color;
uniform sampler2D noise_texture;
uniform sampler2D burn_texture : source_color; // GradientTexture1D

uniform vec2 hit_uv = vec2(0.5, 0.5);
uniform float radius = 0.0;
uniform float border_width = 0.15; // Controls how thick the fire is
uniform float noise_scale = 0.15; // Replaces burn_mult

// Function from the tutorial to remap values
float inverse_lerp(float a, float b, float v) {
    return (v - a) / (b - a);
}

void fragment() {
    vec4 albedo = texture(albedo_texture, UV);
    float noise_val = texture(noise_texture, UV).r;
    
    // Calculate distance from hit point with noise displacement
    float dist = length(hit_uv - UV) + (noise_val * noise_scale);
    
    // 1. Core burn area: discard pixels completely
    if (dist < radius) {
        discard;
    }
    
    // 2. Map distance across the border width to get a 0.0 to 1.0 value
    float burn_uv_x = inverse_lerp(radius, radius + border_width, dist);
    
    // Clamp to prevent the gradient texture from wrapping/repeating
    burn_uv_x = clamp(burn_uv_x, 0.0, 1.0);
    
    // 3. Sample the fire colors from the gradient
    vec3 burn_color = texture(burn_texture, vec2(burn_uv_x, 0.0)).rgb;
    
    // 4. GPU-optimized step: 1.0 if outside fire, 0.0 if inside fire border
    float is_unburned = step(radius + border_width, dist);
    
    // 5. Final color blending
    ALBEDO = mix(burn_color, albedo.rgb, is_unburned);
    
    // 6. Only apply emission glow to the burning parts
    float is_burning = 1.0 - is_unburned;
    EMISSION = burn_color * 2.5 * is_burning;
}