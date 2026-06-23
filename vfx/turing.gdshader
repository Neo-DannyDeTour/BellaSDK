shader_type canvas_item;

uniform sampler2D pattern_texture : repeat_enable, filter_linear_mipmap;
uniform float pattern_tiling = 3.0;
uniform float pattern_blur_lod = 2.5;

uniform float brightness_min = 0.2;
uniform float brightness_max = 0.8;

uniform vec4 dark_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 light_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    vec4 base_color = texture(TEXTURE, UV);
    float brightness = dot(base_color.rgb, vec3(0.299, 0.587, 0.114));

    vec2 pattern_uv = UV * pattern_tiling;
    
    // Sampling the mipmaps turns a sharp black and white image into a soft gradient map
    float pattern_val = textureLod(pattern_texture, pattern_uv, pattern_blur_lod).r;

    // Remap brightness to ensure it stays within the blurred pattern's value range
    float threshold = mix(brightness_min, brightness_max, 1.0 - brightness);
    
    // Smoothstep provides a slight anti-aliasing to the labyrinth edges
    float mask = smoothstep(threshold - 0.02, threshold + 0.02, pattern_val);

    COLOR = mix(dark_color, light_color, mask);
    COLOR.a *= base_color.a;
}