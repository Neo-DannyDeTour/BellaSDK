shader_type canvas_item;

// Grab the screen texture. filter_nearest prevents the GPU 
// from blurring the artificially lowered resolution.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

// Target resolution for the software renderer look.
uniform vec2 software_resolution = vec2(640.0, 480.0);

// PS1 dithering matrix (4x4) used to smooth the 5-bit color banding
const float dither_matrix[16] = float[16](
	-4.0,  0.0, -3.0,  1.0,
	 2.0, -2.0,  3.0, -1.0,
	-3.0,  1.0, -4.0,  0.0,
	 3.0, -1.0, -2.0,  2.0
);

void fragment() {
	// 1. Pixelation: Snap the continuous SCREEN_UV to the low-res grid
	vec2 grid_uv = floor(SCREEN_UV * software_resolution) / software_resolution;
	
	// 2. Sample the screen at the snapped UV
	vec3 color = texture(screen_texture, grid_uv).rgb;
	
	// 3. Dithering: Calculate grid position for the dither matrix
	// Tied to the virtual resolution so dots remain prominent
	vec2 virtual_pos = floor(SCREEN_UV * software_resolution);
	int x = int(virtual_pos.x) % 4;
	int y = int(virtual_pos.y) % 4;
	int index = y * 4 + x;
	
	// The offset scales the values down for a subtle brightness change
	float dither_offset = dither_matrix[index] / 8.0;
	
	// 4. Quantization: Simulate the PS1's 15-bit color (5 bits per channel)
	// Multiply by 255.0 to 8-bit, divide by 8.0 for 5-bit depth, 
	// apply dither, floor, and normalize back using 31.0.
	color = floor((color * 255.0) / 8.0 + dither_offset) / 31.0;
	
	COLOR = vec4(color, 1.0);
}