shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.5;
uniform float wave_speed : hint_range(0.0, 10.0) = 3.0;
uniform float wave_freq : hint_range(0.0, 20.0) = 10.0;
uniform float wave_width : hint_range(0.0, 0.1) = 0.015;

void fragment() {
    vec2 uv = UV;
    
    // Calculate raw displacement without the compressing edge_mask
    vec2 displacement = vec2(
        cos(uv.y * wave_freq * 0.8 + TIME * wave_speed * 0.8) * (wave_width * 0.5),
        sin(uv.x * wave_freq + TIME * wave_speed) * wave_width
    );

    // Apply displacement
    uv += displacement;

    vec4 tex = texture(TEXTURE, uv);
    
    // Envelope handles the fade in/out based on the progress tween
    float envelope = smoothstep(0.0, 0.2, progress) * (1.0 - smoothstep(0.8, 1.0, progress));
    vec3 water_tint = vec3(0.8, 0.9, 1.0);
    
    COLOR = vec4(tex.rgb * water_tint, tex.a * envelope);
}