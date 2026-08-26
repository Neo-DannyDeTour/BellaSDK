 shader_type canvas_item;

render_mode unshaded;


// Screen texture sampler

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;


// --- Aesthetic Controls ---

group_uniforms ChromaticAberration;

uniform float aberration_strength : hint_range(0.0, 0.05, 0.001) = 0.008;


group_uniforms FilmGrain;

uniform float grain_strength : hint_range(0.0, 0.2, 0.005) = 0.045;

uniform float grain_speed : hint_range(0.0, 30.0, 1.0) = 16.0;


group_uniforms Vignette;

uniform float vignette_intensity : hint_range(0.0, 3.0, 0.05) = 1.4;

uniform float vignette_radius : hint_range(0.0, 2.0, 0.05) = 0.85;


group_uniforms ColorGrading;

uniform float contrast : hint_range(0.5, 2.5, 0.05) = 1.25;

uniform float saturation : hint_range(0.0, 2.0, 0.05) = 0.85;

uniform vec3 shadow_tint : source_color = vec3(0.06, 0.04, 0.12);

uniform vec3 highlight_tint : source_color = vec3(1.05, 0.95, 0.75);


// Fast pseudo-random hash for grain

float hash(vec2 p) {

    vec3 p3 = fract(vec3(p.xyx) * 0.1031);

    p3 += dot(p3, p3.yzx + 33.33);

    return fract((p3.x + p3.y) * p3.z);

}


void fragment() {

    vec2 uv = SCREEN_UV;

    vec2 center_offset = uv - vec2(0.5);

    float dist = length(center_offset);


    // 1. Chromatic Aberration (radial distortion)

    vec2 offset = center_offset * aberration_strength * dist;

    float r = texture(screen_texture, uv - offset).r;

    float g = texture(screen_texture, uv).g;

    float b = texture(screen_texture, uv + offset).b;

    vec3 color = vec3(r, g, b);


    // 2. Contrast & Saturation Adjustment

    float luma = dot(color, vec3(0.299, 0.587, 0.114));

    color = mix(vec3(luma), color, saturation);

    color = (color - 0.5) * contrast + 0.5;


    // 3. 80s Dark Fantasy Split Toning (Shadows -> Purple / Highlights -> Amber)

    float tone_weight = smoothstep(0.0, 1.0, luma);

    color = mix(color * shadow_tint * 2.5, color * highlight_tint, tone_weight);


    // 4. Vignette

    float vignette = smoothstep(vignette_radius, vignette_radius - 0.5, dist * vignette_intensity);

    color *= clamp(vignette, 0.0, 1.0);


    // 5. Film Grain

    float time_step = floor(TIME * grain_speed);

    float noise = hash(uv * 1000.0 + vec2(time_step, -time_step));

    color += (noise - 0.5) * grain_strength;


    COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);

}
