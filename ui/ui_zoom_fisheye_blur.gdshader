shader_type canvas_item;

// Godot 4 requires these hints to grab the screen for blurring
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// How heavily the screen bulges
uniform float distortion_amount : hint_range(0.0, 5.0) = 1.0;
// How blurry the edges get
uniform float blur_amount : hint_range(0.0, 5.0) = 2.5;

// The master switch! 0.0 is off, 1.0 is full zoom effect.
uniform float effect_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    // 1. Center the UV coordinates so math expands outward from the middle
    vec2 center_uv = UV - 0.5;

    // 2. Calculate how far the current pixel is from the center
    float dist = length(center_uv);

    // 3. Fisheye (Barrel Distortion) Math
    // The further from the center, the more we pull the UV coordinates
    float distortion = 1.0 + (dist * dist * distortion_amount * effect_strength);
    vec2 distorted_uv = center_uv * distortion + 0.5;

    // 4. Edge Blur Math
    // Smoothstep creates a gradient: 0.0 at the center, smoothly blending to 1.0 at the edges
    float edge_mask = smoothstep(0.2, 0.7, dist);

    // Multiply the mask by our blur amount and the master strength
    float current_blur = edge_mask * blur_amount * effect_strength;

    // 5. Output the final color using textureLod to apply the blur
    COLOR = textureLod(screen_texture, distorted_uv, current_blur);
}
