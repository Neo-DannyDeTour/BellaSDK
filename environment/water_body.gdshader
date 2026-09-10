shader_type spatial;
render_mode blend_mix, cull_disabled, specular_schlick_ggx;

// --- GEOMETRY & TIME ---
uniform float water_time = 0.0;
uniform vec3 water_size = vec3(10.0, 3.0, 10.0);
uniform bool show_side_walls = false;

// --- OPTICAL ABSORPTION & BEER'S LAW ---
uniform vec4 shallow_color : source_color = vec4(0.28, 0.58, 0.85, 0.45);
uniform vec4 deep_color : source_color = vec4(0.01, 0.06, 0.18, 0.95);
uniform float depth_distance : hint_range(0.1, 50.0) = 4.5;
uniform float beers_law : hint_range(0.1, 20.0) = 2.2;

// --- GERSTNER WAVES ---
uniform float wave_amplitude = 0.1;
uniform float wave_length = 4.5;
uniform float wave_speed = 1.4;
uniform float wave_steepness : hint_range(0.0, 1.0) = 0.35;

// --- 3D INTERACTIVE RIPPLES ---
const int MAX_RIPPLES = 16;
uniform vec4 ripples[16];
uniform float ripple_mesh_height = 0.22;
const float RIPPLE_SPEED = 3.0;
const float RIPPLE_WAVELENGTH = 1.0;
const float RIPPLE_LIFETIME = 2.5;

// --- SURFACE NORMALS & NOISE ---
uniform sampler2D normal_map_1 : hint_normal;
uniform sampler2D normal_map_2 : hint_normal;
uniform vec2 uv_scale = vec2(3.0, 3.0);
uniform float normal_bump_strength : hint_range(0.1, 5.0) = 1.2;
uniform vec2 pan_speed_1 = vec2(0.025, 0.015);
uniform vec2 pan_speed_2 = vec2(-0.02, 0.03);

// --- FOAM & EDGES ---
uniform sampler2D foam_noise : hint_default_white;
uniform vec4 foam_color : source_color = vec4(0.92, 0.96, 1.0, 1.0);
uniform float foam_distance : hint_range(0.0, 2.0) = 0.4;

// --- REFRACTION & OPTICS ---
uniform float refraction_strength : hint_range(0.0, 0.1) = 0.025;
uniform vec4 underwater_ceiling_color : source_color = vec4(0.01, 0.07, 0.16, 1.0);

// --- SCREEN BUFFERS ---
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap, repeat_disable;

varying vec3 local_normal;
varying vec3 v_world_pos;

// Evaluates Gerstner wave displacement (trochoidal horizontal & vertical motion)
vec3 evaluate_gerstner_wave(vec2 dir, float amp, float len, float steep, vec2 pos, float time) {
    vec2 d = normalize(dir);
    float k = 6.2831853 / max(len, 0.01);
    float c = sqrt(9.8 / k);
    float phase = (d.x * pos.x + d.y * pos.y) * k + (time * c * 0.6);
    float q = steep / (k * amp * 3.0 + 0.0001);

    return vec3(
        -d.x * q * amp * cos(phase),
        amp * sin(phase),
        -d.y * q * amp * cos(phase)
    );
}

// Evaluates per-vertex dynamic 3D vertical displacement
float get_ripple_displacement(vec2 pos) {
    float total_h = 0.0;
    for (int i = 0; i < MAX_RIPPLES; i++) {
        float amp = ripples[i].w;
        if (amp <= 0.001) {
            continue;
        }

        vec2 center = ripples[i].xy;
        float elapsed = water_time - ripples[i].z;
        if (elapsed < 0.0 || elapsed > RIPPLE_LIFETIME) {
            continue;
        }

        float dist = distance(pos, center);
        float wave_front = elapsed * RIPPLE_SPEED;
        float d_wave = dist - wave_front;

        float spatial_envelope = exp(-0.5 * (d_wave * d_wave) / (RIPPLE_WAVELENGTH * 1.2));
        float time_decay = clamp(1.0 - (elapsed / RIPPLE_LIFETIME), 0.0, 1.0);
        float k = 6.2831853 / RIPPLE_WAVELENGTH;
        total_h += sin(k * d_wave) * amp * spatial_envelope * time_decay;
    }
    return total_h;
}

// Evaluates per-fragment normal gradient perturbation from ripples
vec2 calculate_ripple_normals(vec2 pos) {
    vec2 total_grad = vec2(0.0);
    for (int i = 0; i < MAX_RIPPLES; i++) {
        float amp = ripples[i].w;
        if (amp <= 0.001) {
            continue;
        }

        vec2 center = ripples[i].xy;
        float elapsed = water_time - ripples[i].z;
        if (elapsed < 0.0 || elapsed > RIPPLE_LIFETIME) {
            continue;
        }

        float dist = distance(pos, center);
        float wave_front = elapsed * RIPPLE_SPEED;
        float d_wave = dist - wave_front;

        float spatial_envelope = exp(-0.5 * (d_wave * d_wave) / (RIPPLE_WAVELENGTH * 1.2));
        float time_decay = clamp(1.0 - (elapsed / RIPPLE_LIFETIME), 0.0, 1.0);
        float current_amp = amp * spatial_envelope * time_decay;

        float k = 6.2831853 / RIPPLE_WAVELENGTH;
        float phase = k * d_wave;

        if (dist > 0.001) {
            vec2 dir = (pos - center) / dist;
            float d_height = k * cos(phase) * current_amp;
            total_grad += dir * d_height;
        }
    }
    return total_grad;
}

void vertex() {
    local_normal = NORMAL;
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    if (NORMAL.y > 0.5) {
        float t = water_time * wave_speed;

        // Multi-frequency Gerstner wave superposition
        vec3 gw1 = evaluate_gerstner_wave(vec2(1.0, 0.2), wave_amplitude, wave_length, wave_steepness, v_world_pos.xz, t);
        vec3 gw2 = evaluate_gerstner_wave(vec2(-0.6, 0.8), wave_amplitude * 0.45, wave_length * 0.55, wave_steepness, v_world_pos.xz, t * 1.15);
        vec3 gw3 = evaluate_gerstner_wave(vec2(0.3, -0.95), wave_amplitude * 0.2, wave_length * 0.35, wave_steepness, v_world_pos.xz, t * 0.8);

        vec3 total_gw = gw1 + gw2 + gw3;
        float rip_disp = get_ripple_displacement(v_world_pos.xz) * ripple_mesh_height;

        VERTEX.x += total_gw.x;
        VERTEX.z += total_gw.z;
        VERTEX.y += total_gw.y + rip_disp;
    }
}

void fragment() {
    vec2 surface_uv = (v_world_pos.xz / max(water_size.xz, vec2(1.0))) * uv_scale;
    vec2 uv_1 = surface_uv + water_time * pan_speed_1;
    vec2 uv_2 = surface_uv + water_time * pan_speed_2;

    vec3 n1 = texture(normal_map_1, uv_1).rgb * 2.0 - 1.0;
    vec3 n2 = texture(normal_map_2, uv_2).rgb * 2.0 - 1.0;
    vec3 blended_normal = normalize(n1 + n2);
    blended_normal.xy *= normal_bump_strength;

    if (local_normal.y > 0.5) {
        vec2 rip_grad = calculate_ripple_normals(v_world_pos.xz);
        blended_normal.x += rip_grad.x * 3.5;
        blended_normal.y += rip_grad.y * 3.5;
    }

    vec3 final_normal_dir = normalize(blended_normal);
    bool is_underwater = !FRONT_FACING;

    if (is_underwater) {
        if (local_normal.y < 0.5) {
            discard;
        }

        // Snell's Window portal for underwater ceiling
        float view_angle = abs(dot(NORMAL, VIEW));
        float snells_window = smoothstep(0.08, 0.45, view_angle - (final_normal_dir.x * 0.12));

        vec2 ref_ofs = final_normal_dir.xy * refraction_strength * 2.0 * snells_window;
        vec3 sky_view = texture(SCREEN_TEXTURE, clamp(SCREEN_UV + ref_ofs, vec2(0.001), vec2(0.999))).rgb;

        ALBEDO = mix(underwater_ceiling_color.rgb, sky_view, snells_window);
        ALBEDO += max(vec3(0.0), (final_normal_dir - 0.5) * 0.15) * snells_window;
        ALPHA = 1.0;
        SPECULAR = 0.0;
        ROUGHNESS = 0.4;
    } else {
        if (local_normal.y < 0.5 && !show_side_walls) {
            discard;
        }

        NORMAL = (VIEW_MATRIX * vec4(final_normal_dir.x, 1.0, final_normal_dir.y, 0.0)).xyz;

        // Linearized world depth calculation
        float depth_raw = textureLod(DEPTH_TEXTURE, SCREEN_UV, 0.0).r;
        vec4 ndc_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
        ndc_pos.xyz /= ndc_pos.w;
        float depth_z = -ndc_pos.z;
        float vertex_z = -VERTEX.z;
        float water_depth = max(0.0, depth_z - vertex_z);

        // Safe refraction with chromatic dispersion
        vec2 ref_ofs = final_normal_dir.xy * refraction_strength * clamp(water_depth * 0.8, 0.0, 1.0);
        vec2 safe_uv = clamp(SCREEN_UV + ref_ofs, vec2(0.001), vec2(0.999));

        float ref_depth_raw = textureLod(DEPTH_TEXTURE, safe_uv, 0.0).r;
        vec4 ref_ndc = INV_PROJECTION_MATRIX * vec4(safe_uv * 2.0 - 1.0, ref_depth_raw, 1.0);
        ref_ndc.xyz /= ref_ndc.w;
        float ref_water_depth = -ref_ndc.z - vertex_z;

        if (ref_water_depth < 0.0) {
            safe_uv = SCREEN_UV;
        }

        // Chromatic aberration split on refracted background
        float bg_r = texture(SCREEN_TEXTURE, clamp(safe_uv + ref_ofs * 0.12, vec2(0.001), vec2(0.999))).r;
        float bg_g = texture(SCREEN_TEXTURE, safe_uv).g;
        float bg_b = texture(SCREEN_TEXTURE, clamp(safe_uv - ref_ofs * 0.12, vec2(0.001), vec2(0.999))).b;
        vec3 refracted_bg = vec3(bg_r, bg_g, bg_b);

        // Beer's Law exponential absorption
        float depth_ratio = clamp(water_depth / max(depth_distance, 0.01), 0.0, 1.0);
        float absorption = clamp(1.0 - exp(-water_depth * beers_law * 0.25), 0.0, 1.0);
        vec3 water_tint = mix(shallow_color.rgb, deep_color.rgb, depth_ratio);
        vec3 under_surface = mix(refracted_bg, water_tint, absorption);

        // Fresnel reflection
        float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 4.0);
        vec3 surface_albedo = mix(under_surface, shallow_color.rgb + vec3(0.1), fresnel * 0.7);

        // Organic shoreline & obstacle contact foam
        float foam_depth_mask = 1.0 - smoothstep(0.0, max(foam_distance, 0.01), water_depth);
        float foam_sample = texture(foam_noise, surface_uv * 2.2 + water_time * 0.04).r;
        float foam_blend = smoothstep(0.42, 0.68, foam_depth_mask * (foam_sample * 1.5 + 0.25));

        ALBEDO = mix(surface_albedo, foam_color.rgb, foam_blend);
        ROUGHNESS = mix(0.02, 0.55, foam_blend);
        SPECULAR = mix(0.8, 0.1, foam_blend);
        ALPHA = clamp(water_depth * 18.0, 0.0, 1.0);
    }
}
