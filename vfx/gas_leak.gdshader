shader_type spatial;
// Unshaded is highly optimized. We don't need lighting calculations for refraction.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_texture : repeat_enable;
uniform sampler2D mask_texture;

uniform float distortion_strength : hint_range(0.0, 0.2) = 0.05;
uniform float scroll_speed = 0.5;
uniform float blur_lod : hint_range(0.0, 5.0) = 2.0;

void vertex() {
	// Highly optimized Billboard effect (keeps quads facing the camera)
	mat4 modified_model_view = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	MODELVIEW_MATRIX = modified_model_view;
}

void fragment() {
	// Pan the noise texture over time to simulate gas flowing
	vec2 noise_uv = UV + vec2(0.0, TIME * scroll_speed);
	vec2 noise = texture(noise_texture, noise_uv).rg;
	
	// Convert noise from [0, 1] range to [-1, 1] range
	vec2 offset = (noise - 0.5) * 2.0;
	
	// Get mask value for soft circular edges
	float mask = texture(mask_texture, UV).r;
	
	// Apply particle alpha (COLOR.a) and mask to the distortion 
	// so the refraction smoothly fades out at the edges and over the particle's lifetime
	float final_alpha = COLOR.a * mask;
	offset *= final_alpha * distortion_strength;
	
	// Sample the screen texture with the offset. 
	// textureLod uses mipmaps to blur the background cheaply!
	vec4 refraction = textureLod(screen_texture, SCREEN_UV + offset, blur_lod);
	
	ALBEDO = refraction.rgb;
	ALPHA = final_alpha;
}