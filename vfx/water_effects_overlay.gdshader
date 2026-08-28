shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// 0 = Underwater / Ripples / Rain, 2 = Waterfall Stream Flow
uniform int effect_mode : hint_range(0, 2) = 0;
uniform float drop_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float wash_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float clear_progress : hint_range(0.0, 1.5) = 0.0;

const vec3 light_dir = vec3(0.5, 0.5, 1.0);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    if (drop_intensity <= 0.001 && wash_intensity <= 0.001 && clear_progress >= 1.49) {
        COLOR = texture(screen_tex, SCREEN_UV);
    } else {
        vec2 aspect_uv = SCREEN_UV;
        aspect_uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;

        vec2 total_distortion = vec2(0.0);
        float specular_light = 0.0;

        // --- 1. WATERFALL FLOW OR UNDERWATER WIPING / REFRACTION ---
        if (wash_intensity > 0.0) {
            if (effect_mode == 2) {
                // Waterfall downward flow with vertical wipe
                vec2 flow_uv = UV;
                flow_uv.y -= TIME * 3.0;
                float wave = sin(flow_uv.x * 20.0 + TIME) * cos(flow_uv.y * 15.0);
                float wipe_mask = smoothstep(clear_progress - 0.2, clear_progress + 0.05, UV.y);
                total_distortion += vec2(wave, wave * 1.5) * 0.04 * wash_intensity * wipe_mask;
            } else {
                // Underwater diagonal wipe & thick refraction
                float diag = (UV.x + UV.y) * 0.5;
                float wipe_noise = sin(UV.y * 30.0 + TIME * 2.0) * 0.02 + sin(UV.x * 20.0 - TIME * 1.5) * 0.02;
                float wipe_edge = diag + wipe_noise;
                float thick_threshold = clear_progress * 1.4 - 0.2;
                float thick_mask = smoothstep(thick_threshold - 0.05, thick_threshold + 0.05, wipe_edge);

                vec2 center_uv = (SCREEN_UV - 0.5) * vec2(1.77, 1.0);
                float dist = length(center_uv);
                float t = TIME * 12.0;
                float wave_ring = sin(dist * 25.0 - t) + sin(dist * 40.0 - t * 1.3) * 0.5;
                float center_mask = smoothstep(0.0, 0.3, dist);
                total_distortion += normalize(center_uv) * wave_ring * 0.015 * wash_intensity * center_mask * thick_mask;

                vec2 thick_refraction = vec2(
                    sin(UV.y * 20.0 + TIME * 8.0),
                    cos(UV.x * 20.0 + TIME * 7.0)
                ) * 0.008 * wash_intensity * thick_mask;
                total_distortion += thick_refraction;
            }
        }

        // --- 2. POP-IN & RESURFACE DROPLETS ---
        if (drop_intensity > 0.001) {
            for (float i = 1.0; i <= 2.0; i++) {
                float grid_scale = 4.5 * i;
                vec2 grid_uv = aspect_uv * grid_scale;
                vec2 cell_id = floor(grid_uv);
                vec2 local_uv = fract(grid_uv) - 0.5;

                float r1 = hash(cell_id + i * 1.1);
                float r2 = hash(cell_id + i * 2.2);
                vec2 drop_pos = (vec2(r1, r2) - 0.5) * 0.5;
                vec2 offset = local_uv - drop_pos;

                float shape_seed = hash(cell_id + 7.0);
                vec2 shape_offset = offset;
                shape_offset.y += abs(shape_offset.x) * mix(0.0, 0.4, shape_seed);

                float wobble = sin(atan(offset.y, offset.x) * 4.0) * mix(0.0, 0.02, shape_seed);
                float dist = length(shape_offset) + wobble;
                float radius = mix(0.12, 0.28, hash(cell_id + 10.0));

                float spawn_threshold = hash(cell_id + 5.0);
                float final_speed = max(0.5, mix(1.0, 4.5, spawn_threshold));
                float life = sin(TIME * final_speed + r1 * 6.28);

                float current_active_level = mix(0.15, 0.95, drop_intensity);
                float visibility = smoothstep(spawn_threshold, spawn_threshold + 0.1, current_active_level);

                if (life > 0.0 && dist < radius && visibility > 0.0) {
                    float mask = smoothstep(radius, radius * 0.7, dist) * life * visibility;
                    float z = sqrt(max(0.0, radius * radius - dist * dist));
                    vec3 normal = normalize(vec3(offset.x, offset.y, z * 0.6));

                    total_distortion += normal.xy * mask * 0.15 * drop_intensity;
                    float spec = pow(max(dot(normal, normalize(light_dir)), 0.0), 64.0);
                    specular_light += spec * mask * 1.5 * drop_intensity;
                }
            }
        }

        // --- 3. FINAL COMPOSITING ---
        vec4 screen_color = textureLod(screen_tex, SCREEN_UV - total_distortion, abs(total_distortion.x) * 10.0);
        vec3 wet_tint = vec3(0.85, 0.92, 1.0);
        float tint_mix = clamp(wash_intensity * 0.15, 0.0, 0.3);
        vec3 composite = mix(screen_color.rgb, wet_tint, tint_mix) + vec3(specular_light);

        COLOR = vec4(composite, 1.0);
    }
}
