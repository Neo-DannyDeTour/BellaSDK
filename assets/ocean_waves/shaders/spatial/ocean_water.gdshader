shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, world_vertex_coords;

/**
 * Water lighting model roughly follows the 2019 GDC talk: "Wakes, Explosions and Lighting: Interactive Water Simulation in Atlas".
 * Source: https://gpuopen.com/gdc-presentations/2019/gdc-2019-agtd6-interactive-water-simulation-in-atlas.pdf
 */

#define MAX_CASCADES 8    
#define REFLECTANCE  0.02 // Reflectance from air to water (eta=1.33).

global uniform vec4 water_color : source_color;
global uniform vec4 foam_color : source_color;
uniform vec3 depth_color_consumption = vec3(22.0, 133.0, 168.0);

// --- NEW: Subsurface & Crest settings ---
uniform vec3 crest_color : source_color = vec3(0.0, 0.65, 0.85); // Light blue/teal
uniform float crest_glow_intensity : hint_range(0.0, 2.0) = 0.2;
uniform float aerated_foam_glow : hint_range(0.0, 2.0) = 0.3;
// ----------------------------------------

uniform float roughness : hint_range(0.0, 1.0) = 0.4;
uniform float normal_strength : hint_range(0.0, 1.0) = 1.0; 
uniform sampler2D foam_noise_tex : repeat_enable, filter_linear_mipmap;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

group_uniforms cascade_data;
uniform vec4 map_scales[MAX_CASCADES];               
global uniform int num_cascades;
global uniform sampler2DArray displacements;         
global uniform sampler2DArray normals : hint_normal; 

varying float wave_height;
varying float foam_factor;
varying float fresnel;

void vertex() {
    UV = VERTEX.xz;
    float distance_cam = length(VERTEX.xz - CAMERA_POSITION_WORLD.xz);
    if (distance_cam < 1024.0) 
    {
        float distance_factor = min(exp(-(distance_cam-512.0)*0.007), 1.0); 

        vec3 displacement = vec3(0.0); 
        for (int i = 0; i < num_cascades; ++i) {
            vec4 scales = map_scales[i];
            displacement += textureLod(displacements, vec3(UV*scales.xy, float(i)), 0.0).xyz * scales.z; 
        }
        VERTEX += displacement * distance_factor;
        wave_height = displacement.y;
    }
    else
    {
        wave_height = 0.0;
    }
}

vec4 cubic_weights(float a) {
    float a2 = a*a;
    float a3 = a2*a;

    float w0 =-a3     + a2*3.0 - a*3.0 + 1.0;
    float w1 = a3*3.0 - a2*6.0         + 4.0;
    float w2 =-a3*3.0 + a2*3.0 + a*3.0 + 1.0;
    float w3 = a3;
    return vec4(w0, w1, w2, w3) / 6.0;
}

vec4 texture_bicubic(in sampler2DArray sampler, in vec3 uvw) {
    vec2 dims = vec2(textureSize(sampler, 0).xy);
    vec2 dims_inv = 1.0 / dims;
    uvw.xy = uvw.xy*dims + 0.5;

    vec2 fuv = fract(uvw.xy);
    vec4 wx = cubic_weights(fuv.x);
    vec4 wy = cubic_weights(fuv.y);

    vec4 g = vec4(wx.xz + wx.yw, wy.xz + wy.yw);
    vec4 h = (vec4(wx.yw, wy.yw) / g + vec2(-1.5, 0.5).xyxy + floor(uvw.xy).xxyy)*dims_inv.xxyy;
    vec2 w = g.xz / (g.xz + g.yw);
    return mix(
        mix(texture(sampler, vec3(h.yw, uvw.z)), texture(sampler, vec3(h.xw, uvw.z)), w.x),
        mix(texture(sampler, vec3(h.yz, uvw.z)), texture(sampler, vec3(h.xz, uvw.z)), w.x), w.y);
}

void fragment() {
    float map_size = float(textureSize(normals, 0).x);
    float dist = length(VERTEX.xz - CAMERA_POSITION_WORLD.xz); // Fixed World Origin Bug
    
    vec3 gradient = vec3(0.0); 
    float foam_alpha = 0.0;
    
    for (int i = 0; i < num_cascades; ++i) {
	    vec4 scales = map_scales[i];
	    vec3 coords = vec3(UV*scales.xy, float(i));
	    
	    // Using standard hardware bilinear filtering. It is infinitely faster and looks identical at a distance.
	    gradient += texture(normals, coords).xyw * vec3(scales.ww, 1.0);
	    foam_alpha += texture(foam_noise_tex, UV * scales.xy * 1.0).r;
	}
    foam_factor = smoothstep(0.0, 1.0, gradient.z*0.75) * exp(-dist*0.0075);

    // ===================== shine through ===================================#
    float depth_tex = texture(depth_texture, SCREEN_UV).r;
    
    vec4 view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
    view_pos.xyz /= view_pos.w;
    
    float smooth_alpha = 1.0 - smoothstep(view_pos.z + 0.66, view_pos.z, VERTEX.z);
    ALPHA *= clamp(smooth_alpha, 0.00, 1.0);
    if (ALPHA < 0.9){
        foam_factor = clamp(foam_factor + 0.5 - ALPHA, 0.0, 1.0);
    }
    
    float depth_visibility_range = clamp(max(depth_color_consumption.r, max(depth_color_consumption.g,depth_color_consumption.b)),0.0,200.0);
    float factor_translucency =  1.0 - smoothstep(view_pos.z + depth_visibility_range, view_pos.z, VERTEX.z);
    factor_translucency = clamp(factor_translucency, 0.35, 1.0);
    vec3 screen_albedo = texture(screen_texture, SCREEN_UV, 0.0).rgb;
    vec3 depth_water_color = mix(screen_albedo, water_color.rgb, factor_translucency);
    
    float smooth_red = smoothstep(view_pos.z + depth_color_consumption.r, view_pos.z, VERTEX.z);
    float smooth_green = smoothstep(view_pos.z + depth_color_consumption.g, view_pos.z, VERTEX.z);
    float smooth_blue = smoothstep(view_pos.z + depth_color_consumption.b, view_pos.z, VERTEX.z);
    vec3 color_shallow = max(vec3(smooth_red, smooth_green, smooth_blue) * depth_water_color, water_color.rgb);
    
    depth_water_color = mix(color_shallow, water_color.rgb, factor_translucency);
    // ===================== shine through ===================================#
    
    // --- NEW: Subsurface Crest and Aerated Water Glow ---
    // 1. Mask for the peaks of the waves (starts glowing over 0.5m high)
    float wave_crest_mask = smoothstep(0.5, 3.5, wave_height); 
    
    // 2. Mask for the churned, aerated water (the micro-foam glowing under the surface)
    float aerated_mask = smoothstep(0.1, 0.9, foam_factor); 
    
    // Combine them with the intensities chosen by the user
    float total_subsurface = clamp((wave_crest_mask * crest_glow_intensity) + (aerated_mask * aerated_foam_glow), 0.0, 1.0);
    
    // Mix the deep water with the bright crest/aerated color BEFORE applying the thick white foam
    vec3 water_with_glow = mix(depth_water_color, crest_color, total_subsurface);
    
    // Finally, mix the solid white foam completely on top
    ALBEDO = mix(water_with_glow, foam_color.rgb, foam_factor * foam_alpha * foam_alpha);
    // ----------------------------------------------------
    
    fresnel = mix(pow(1.0 - dot(VIEW, NORMAL), 5.0*exp(-2.69*roughness)) / (1.0 + 22.7*pow(roughness, 1.5)), 1.0, REFLECTANCE);
    ROUGHNESS = (1.0 - fresnel) * foam_factor + 0.4; 
    
    gradient *= mix(0.015, normal_strength, exp(-dist*0.0175)); 
    NORMAL = (VIEW_MATRIX * vec4(normalize(vec3(-gradient.x, 1.0, -gradient.y)), 0.0)).xyz;
}

float smith_masking_shadowing(in float cos_theta, in float alpha) {
    float a = cos_theta / (alpha * sqrt(1.0 - cos_theta*cos_theta)); 
    float a_sq = a*a;
    return a < 1.6 ? (1.0 - 1.259*a + 0.396*a_sq) / (3.535*a + 2.181*a_sq) : 0.0;
}

float ggx_distribution(in float cos_theta, in float alpha) {
    float a_sq = alpha*alpha;
    float d = 1.0 + (a_sq - 1.0) * cos_theta * cos_theta;
    return a_sq / (PI * d*d);
}

void light() {
    vec3 halfway = normalize(LIGHT + VIEW);
    float dot_nl = max(dot(NORMAL, LIGHT), 2e-5);
    float dot_nv = max(dot(NORMAL, VIEW), 2e-5);

    // --- SPECULAR ---
    float light_mask = smith_masking_shadowing(roughness, dot_nv);
    float view_mask = smith_masking_shadowing(roughness, dot_nl);
    float microfacet_distribution = ggx_distribution(dot(NORMAL, halfway), roughness);
    float geometric_attenuation = 1.0 / (1.0 + light_mask + view_mask);
    SPECULAR_LIGHT += fresnel * microfacet_distribution * geometric_attenuation / (4.0 * dot_nv + 0.1) * ATTENUATION;

    // --- DIFFUSE ---
    // CHANGED: Hooked SSS up to your chosen crest color parameter instead of a hardcoded green
    vec3 sss_modifier = crest_color * 1.5; 
    
    float sss_height = 1.0 * max(0.0, wave_height + 2.5) * pow(max(dot(LIGHT, -VIEW), 0.0), 4.0) * pow(0.5 - 0.5 * dot(LIGHT, NORMAL), 3.0);
    float sss_near = 0.5 * pow(dot_nv, 2.0);
    float lambertian = 0.5 * dot_nl;
    DIFFUSE_LIGHT += mix((sss_height + sss_near) * sss_modifier / (1.0 + light_mask) + lambertian, foam_color.rgb, foam_factor) * (1.0 - fresnel) * ATTENUATION * LIGHT_COLOR;
}