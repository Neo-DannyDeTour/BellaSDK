shader_type spatial;
render_mode cull_disabled, unshaded;

uniform sampler2D drop_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

// --- MASTER CONTROLS ---
uniform float drop_strength = 0.05;   // How strongly it bends the background
uniform float blur = 0.0;             // Background blur
uniform float drop_visibility = 0.8;  // Fakes a light hitting the water so drops are visible

// --- LAYER 1 (Large Drops) ---
uniform float scale_1 = 3.0;
uniform float speed_1 = 0.15;

// --- LAYER 2 (Medium Drops) ---
uniform float scale_2 = 6.0;
uniform float speed_2 = 0.25;

// --- LAYER 3 (Tiny, fast background drops) ---
uniform float scale_3 = 10.0;
uniform float speed_3 = 0.4;

void fragment() {
    // 1. Calculate Layer 1
    vec2 uv_1 = UV * scale_1;
    uv_1.y -= TIME * speed_1;
    vec3 n1 = texture(drop_texture, uv_1).rgb * 2.0 - 1.0;

    // 2. Calculate Layer 2
    vec2 uv_2 = UV * scale_2;
    uv_2.y -= TIME * speed_2;
    vec3 n2 = texture(drop_texture, uv_2).rgb * 2.0 - 1.0;

    // 3. Calculate Layer 3
    vec2 uv_3 = UV * scale_3;
    uv_3.y -= TIME * speed_3;
    vec3 n3 = texture(drop_texture, uv_3).rgb * 2.0 - 1.0;

    // 4. Combine all three layers
    vec3 combined_normals = normalize(n1 + n2 + n3);

    // 5. Refract the background
    vec2 distorted_uv = SCREEN_UV + (combined_normals.xy * drop_strength);
    vec3 background = textureLod(screen_tex, distorted_uv, blur).rgb;

    // 6. FAKE LIGHTING (The Visibility Fix)
    // Normal maps point "Up" (positive Y) and "Down" (negative Y) on their curves.
    // We can use this to draw a fake light hitting the top of the drops, and a shadow on the bottom.
    float highlight = max(0.0, combined_normals.y);
    float shadow = max(0.0, -combined_normals.y);

    // Apply the background, add the white highlight, subtract the shadow
    vec3 final_color = background;
    final_color += vec3(highlight * drop_visibility);
    final_color -= vec3(shadow * drop_visibility * 0.5);

    ALBEDO = final_color;
}
