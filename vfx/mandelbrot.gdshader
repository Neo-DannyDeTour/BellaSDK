shader_type canvas_item;

// Center of the Mandelbrot set
uniform vec2 center = vec2(0.0, 0.0); 
uniform float zoom = 1.0;
uniform int max_iterations = 64; 

// Controls how fast the colors ripple
uniform float time_scale = 0.5;

// Fast, branchless cosine color palette
// The vectors a, b, c, d define the specific color gradient
vec3 calculate_palette(float t) {
    vec3 a = vec3(0.5, 0.5, 0.5);
    vec3 b = vec3(0.5, 0.5, 0.5);
    vec3 c = vec3(1.0, 1.0, 1.0);
    vec3 d = vec3(0.0, 0.33, 0.67); // Shifts through a blue/cyan/purple spectrum
    
    return a + b * cos(6.28318 * (c * t + d));
}

void fragment() {
    // 1. Map screen UV to complex plane coordinates
    vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
    vec2 c = (SCREEN_UV - 0.5) * aspect;
    
    // 2. Apply the zoom and position
    c = c / zoom + center;

    vec2 z = vec2(0.0, 0.0);
    int iterations = 0;

    // 3. Optimized Mandelbrot loop
    for (int i = 0; i < max_iterations; i++) {
        float x = (z.x * z.x - z.y * z.y) + c.x;
        float y = (2.0 * z.x * z.y) + c.y;
        z = vec2(x, y);

        // dot(z,z) bypasses the square root for a performance boost
        if (dot(z, z) > 4.0) {
            break;
        }
        iterations++;
    }

    // Default to black for coordinates completely inside the set
    vec3 final_color = vec3(0.0); 

    // 4. Apply dynamic colors to the exterior
    if (iterations < max_iterations) {
        // Map the iteration count to a 0.0 - 1.0 range
        float t = float(iterations) / float(max_iterations);
        
        // Add TIME to make the colors flow dynamically
        t += TIME * time_scale;
        
        final_color = calculate_palette(t);
    }

    COLOR = vec4(final_color, 1.0);
}