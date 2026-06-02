shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
const int RADIUS = 3;

void fragment() {
    vec2 tex_size = SCREEN_PIXEL_SIZE;
    
    vec3 means[4] = vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0));
    vec3 variances[4] = vec3[](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0));
    
    float samples = float((RADIUS + 1) * (RADIUS + 1));
    
    // Quadrant 1 (Top Right)
    for (int i = 0; i <= RADIUS; i++) {
        for (int j = 0; j <= RADIUS; j++) {
            vec3 color = texture(screen_texture, SCREEN_UV + vec2(float(i), float(j)) * tex_size).rgb;
            means[0] += color;
            variances[0] += color * color;
        }
    }
    // Quadrant 2 (Bottom Right)
    for (int i = 0; i <= RADIUS; i++) {
        for (int j = 0; j <= RADIUS; j++) {
            vec3 color = texture(screen_texture, SCREEN_UV + vec2(float(i), float(-j)) * tex_size).rgb;
            means[1] += color;
            variances[1] += color * color;
        }
    }
    // Quadrant 3 (Top Left)
    for (int i = 0; i <= RADIUS; i++) {
        for (int j = 0; j <= RADIUS; j++) {
            vec3 color = texture(screen_texture, SCREEN_UV + vec2(float(-i), float(j)) * tex_size).rgb;
            means[2] += color;
            variances[2] += color * color;
        }
    }
    // Quadrant 4 (Bottom Left)
    for (int i = 0; i <= RADIUS; i++) {
        for (int j = 0; j <= RADIUS; j++) {
            vec3 color = texture(screen_texture, SCREEN_UV + vec2(float(-i), float(-j)) * tex_size).rgb;
            means[3] += color;
            variances[3] += color * color;
        }
    }
    
    float min_variance = 100.0;
    vec3 final_color = vec3(0.0);
    
    for (int k = 0; k < 4; k++) {
        means[k] /= samples;
        variances[k] = abs(variances[k] / samples - means[k] * means[k]);
        float total_variance = variances[k].r + variances[k].g + variances[k].b;
        
        if (total_variance < min_variance) {
            min_variance = total_variance;
            final_color = means[k];
        }
    }
    
    COLOR = vec4(final_color, 1.0);
}