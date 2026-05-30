shader_type spatial;
render_mode unshaded;

uniform sampler2D tex : source_color, filter_linear;

void vertex() {
    UV.x = 1.0 - UV.x; // flip mirror horizontally
}

void fragment() {
    vec4 mirror_sample = texture(tex, UV);
    ALBEDO = mirror_sample.rgb;
}