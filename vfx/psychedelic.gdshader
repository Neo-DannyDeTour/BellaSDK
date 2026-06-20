shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// Trippy Settings
uniform float wave_speed : hint_range(0.1, 5.0) = 1.5;
uniform float wave_frequency : hint_range(1.0, 50.0) = 15.0;
uniform float wave_amplitude : hint_range(0.0, 0.1) = 0.015;
uniform float hue_speed : hint_range(0.1, 5.0) = 0.5;
uniform float saturation_boost : hint_range(1.0, 3.0) = 1.5;

// Standard branchless math to convert RGB to HSV (Hue, Saturation, Value)
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// Standard branchless math to convert HSV back to RGB
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
    vec2 uv = SCREEN_UV;

    // --- 1. The "Breathing" Geometry Wobble ---
    // Use intersecting sine and cosine waves based on time and screen position
    // to make the pixels drift around in a non-uniform way.
    float wave_x = sin(uv.y * wave_frequency + TIME * wave_speed) * wave_amplitude;
    float wave_y = cos(uv.x * wave_frequency + TIME * wave_speed) * wave_amplitude;
    
    // Apply a secondary, slower wave to make the distortion feel more organic and unpredictable
    wave_x += sin(uv.y * (wave_frequency * 0.5) - TIME * (wave_speed * 0.8)) * (wave_amplitude * 0.5);
    vec2 distorted_uv = uv + vec2(wave_x, wave_y);

    // Fetch the original color using our melted UVs
    vec3 color = texture(screen_texture, distorted_uv).rgb;

    // --- 2. The Endless Hue Shift ---
    // Convert to HSV so we can easily manipulate the color wheel
    vec3 hsv = rgb2hsv(color);

    // Rotate the hue (hsv.x) continually based on TIME
    // The fract() function ensures the value loops perfectly between 0.0 and 1.0
    hsv.x = fract(hsv.x + TIME * hue_speed);

    // Crank up the saturation to make the colors pop aggressively 
    hsv.y = clamp(hsv.y * saturation_boost, 0.0, 1.0);

    // Convert back to RGB and output
    COLOR = vec4(hsv2rgb(hsv), 1.0);
}