shader_type spatial;
// We disable shadows here because shadow casting on overlapping transparent
// soft bodies is extremely demanding. cull_back ensures one-sided visibility.
render_mode blend_mix, cull_disabled, depth_draw_always, shadows_disabled;

// Expose controls to the Inspector
uniform vec4 albedo : source_color = vec4(0.8, 0.9, 0.95, 0.5);
uniform float roughness_level : hint_range(0.0, 1.0) = 0.2;
uniform float refraction_strength : hint_range(0.0, 0.1) = 0.02;

// Grab the render pass of the screen behind the object
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
    // 1. Calculate the distortion offset using the mesh normal
    vec2 distortion = NORMAL.xy * refraction_strength;

    // 2. Sample the background behind the curtain, applying the distortion
    vec3 background_color = texture(screen_texture, SCREEN_UV + distortion).rgb;

    // 3. Mix the distorted background with your plastic color
    // The alpha channel of your 'albedo' uniform acts as the density/opacity slider.
    ALBEDO = mix(background_color, albedo.rgb, albedo.a);

    // 4. Force the transparent render pass
    // Setting ALPHA to 0.99 forces Godot to draw this after opaque objects so the
    // screen_texture captures the world correctly. Because we already handled the
    // visual transparency in the ALBEDO mix, we avoid traditional alpha-sorting overdraw.
    ALPHA = 0.99;
    ROUGHNESS = roughness_level;
}
