shader_type canvas_item;

#define s(edge0, edge1, value) (1.0 - smoothstep(edge0, edge1, value))

// ## Driven strictly by GDScript to ensure frame-perfect audio synchronization
uniform float u_time = 0.0;

// ## The screen or ColorRect resolution used to maintain the correct aspect ratio
uniform vec2 resolution = vec2(1920.0, 1080.0);

// ## The main RGB color of the moving ECG line
uniform vec3 line_color : source_color = vec3(0.1, 1.0, 0.1);

// ## The RGB color of the background grid
uniform vec3 grid_color : source_color = vec3(0.01, 0.05, 0.01);

// ## The core thickness of the heartbeat line
uniform float line_thickness : hint_range(0.0, 1.0, 0.01) = 0.01;

// ## The outer blur amount applied to the edges of the heartbeat line
uniform float line_blur : hint_range(0.0, 1.0, 0.01) = 0.0;

// ## The array of coordinates that defines the structure of the heartbeat waveform
uniform vec2 points[13];

vec3 draw_grid(vec2 uv, float zoom) {
    vec2 grid = abs(fract(uv * zoom) - 0.5);
    float line = min(grid.x, grid.y);
    return vec3(1.0 - smoothstep(0.0, 0.05, line));
}

float segment_dist(vec2 p, vec2 a, vec2 b) {
    float h = clamp(dot(p - a, b - a) / dot(b - a, b - a), 0.0, 1.0);
    return distance(p, a + h * (b - a));
}

float falloff(float x) {
    return exp(-pow(x, 2.0));
}

float closest_segment(vec2 uv) {
    float min_dist = 1e9;
    for (int i = 1; i < points.length(); i++) {
        min_dist = min(min_dist, segment_dist(uv, points[i - 1], points[i]));
    }
    return min_dist;
}

void fragment() {
    vec2 uv = UV - 0.5;
    float aspect = resolution.x / resolution.y;
    uv.x *= aspect;
    
    // Time is completely controlled by the GDScript
    float t = u_time;
    vec3 color_val = draw_grid(uv, 10.0) * grid_color;
    
    color_val = pow(color_val, vec3(1.0 / 2.2));
    
    float min_dist = closest_segment(uv);
    float pixel_size = 2.0 / resolution.y;
    
    float line = s(line_thickness, line_thickness + line_blur + pixel_size, min_dist);
    float pulse = mod(aspect + uv.x - t, aspect * 2.0) - aspect;
    
    float grid_pulse = s(-0.1, 0.0, pulse);
    line *= grid_pulse * falloff(pulse * 2.0);
    
    color_val = mix(color_val, line_color, line);
    
    COLOR = vec4(color_val, 1.0);
}