shader_type spatial;
render_mode cull_disabled, unshaded;

// ==========================================
// 1. GLASS CONTROLS (Fixes the Darkness)
// ==========================================
group_uniforms Glass_Appearance;
uniform vec4 glass_tint : source_color = vec4(0.7, 0.8, 1.0, 1.0);
uniform float glass_opacity : hint_range(0.0, 1.0) = 0.2;
uniform float brightness_boost : hint_range(0.0, 5.0) = 0.5;

// ==========================================
// 2. RAIN CONTROLS
// ==========================================
group_uniforms Rain_Logic;
uniform float scale = 5.0;
uniform float speed = 2.0;
uniform float wiggle = 10.0;
uniform float drop_strength = 20.0;
uniform float trail_strength = 0.3;
uniform float refraction = 0.05;
uniform float blur : hint_range(0.0, 10.0) = 4.0; // DECUPLED: Now controls blur depth
uniform float fade_distance : hint_range(0.0, 100.0) = 10.0; // BOOSTED
uniform int layers = 1;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

float RandomNumber(vec2 seed){
    seed = fract(seed * vec2(123.456, 234.789));
    seed += dot(seed, seed * 34.73);
    return fract(seed.x * seed.y);
}

// Returns vec3: xy = refraction offset, z = mask for blur/lighting
vec3 RainDrops(vec2 uv, float drop_scale, float drop_speed, float drop_wiggle) {
    float t = TIME * drop_speed;
    float by = (1. - uv.y) * .3 + .7;
    float w = uv.y * drop_wiggle;
    uv *= drop_scale;
    uv.y -= t * .25;
    vec2 grid_uv = fract(uv) - .5;
    vec2 id = floor(uv);

    float rn = RandomNumber(id);
    t += rn * 6.28;
    w *= rn;

    float dr = .05 * by;
    float doffs = .5 - dr;
    float x = (rn - .5) * doffs;
    x += sin(w + cos(w * 4.) * pow(sin(x), 2.)) * (doffs - abs(x));
    float y = cos(t + cos(t + cos(t) * .5)) * doffs;

    vec2 dpos = grid_uv - vec2(x, y);
    float drop = smoothstep(dr, .01, length(dpos));

    float trail = smoothstep(dr, -dr, dpos.y);
    trail *= smoothstep(dr, .01, abs(dpos.x));
    trail *= smoothstep(-.5, y, grid_uv.y);

    // AAA Fade Fix: We use a power function to make the fade more aggressive
    float fade = 1. - clamp(pow(fwidth(uv.x) * fade_distance, 0.5), 0, 1);

    float mask = (drop + trail) * fade;
    vec2 offset = mask * dpos * refraction;

    return vec3(offset, mask);
}

void fragment() {
    vec2 droplets_offset = vec2(0);
    float blur_mask = 0.0;

    for(float i = 1.; i <= float(layers); i++){
        vec3 rain = RainDrops(UV, scale * i * .2, speed * i * .12, wiggle * i * .7);
        droplets_offset += rain.xy;
        blur_mask += rain.z;
    }

    // 1. Refracted and Blurred Background
    // AAA Blur Fix: We use the raw blur_mask instead of the tiny offset length
    vec3 background = textureLod(screen_tex, SCREEN_UV - droplets_offset * blur_mask, blur).rgb;

    // 2. Base Tint (Lifts the window out of the dark)
    vec3 col = mix(background, glass_tint.rgb, glass_opacity);
    col += glass_tint.rgb * brightness_boost * 0.2;

    // 3. Droplet Highlights
    float final_mask = clamp(blur_mask, 0.0, 1.0);
    col = mix(col, glass_tint.rgb, final_mask * 0.2);
    col += glass_tint.rgb * brightness_boost * final_mask;

    ALBEDO = col;
}
