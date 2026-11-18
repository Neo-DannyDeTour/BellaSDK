shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float distortion_strength : hint_range(0.0, 1.0) = 0.1;
uniform float rim_power : hint_range(0.1, 10.0) = 3.0;

// Controls the color separation for that heavy 3D glass look
uniform float aberration_strength : hint_range(0.8, 1.2) = 1.05;

void fragment() {
    // 1. Calculate the 3D curve of the sphere relative to the camera
    float fresnel = 1.0 - dot(NORMAL, VIEW);
    fresnel = pow(fresnel, rim_power);

    // 2. Create the donut mask so it's hollow in the center
    float mask = smoothstep(0.0, 0.2, fresnel) * smoothstep(1.0, 0.8, fresnel);

    // 3. Calculate the base 3D offset using the sphere's normals
    vec2 base_offset = NORMAL.xy * distortion_strength * mask * COLOR.a;

    // 4. Sample the screen 3 times with slightly different offsets for chromatic aberration
    float r = texture(screen_texture, SCREEN_UV + (base_offset * aberration_strength)).r;
    float g = texture(screen_texture, SCREEN_UV + base_offset).g;
    float b = texture(screen_texture, SCREEN_UV + (base_offset / aberration_strength)).b;

    // 5. Output the final heavy 3D distortion
    ALBEDO = vec3(r, g, b);
    ALPHA = mask * COLOR.a;
}
