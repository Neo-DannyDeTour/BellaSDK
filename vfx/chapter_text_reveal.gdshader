shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0);
uniform float wipe_softness = 0.1;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    
    float reveal_in = smoothstep(0.0, 0.3, progress);
    float reveal_out = smoothstep(0.7, 1.0, progress);
    
    float mask_in = smoothstep(UV.x - wipe_softness, UV.x + wipe_softness, reveal_in * (1.0 + wipe_softness * 2.0));
    float mask_out = 1.0 - smoothstep(UV.x - wipe_softness, UV.x + wipe_softness, reveal_out * (1.0 + wipe_softness * 2.0));
    
    COLOR = vec4(tex.rgb, tex.a * mask_in * mask_out);
}