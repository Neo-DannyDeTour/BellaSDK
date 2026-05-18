shader_type spatial;
render_mode unshaded, cull_disabled, blend_premul_alpha;

// --- TEXTURES ---
uniform sampler3D worlnoise : filter_linear_mipmap, repeat_enable;
uniform sampler3D perlworlnoise : filter_linear_mipmap, repeat_enable;
uniform sampler2D weathermap : filter_linear_mipmap, repeat_enable;

// --- CLOUD CONTROLS ---
uniform vec3 sun_direction = vec3(0.5, 0.5, 0.5); // Replaces LIGHT0_DIRECTION
uniform vec4 sun_color : source_color = vec4(1.0, 0.9, 0.8, 1.0);
uniform float sun_energy = 5.0;

uniform vec2 wind_direction = vec2(1, 0);
uniform float wind_speed :hint_range(0.0, 20.0) = 1.0;
uniform float _density : hint_range(0.01, 0.2) = 0.05;
uniform float cloud_coverage :hint_range(0.1, 1.0) = 0.25;
uniform float _time_offset : hint_range(0.0, 1000.0, 0.5) = 0.0;
uniform int steps : hint_range(16, 128) = 64;

varying vec3 world_position;
varying vec3 camera_position;
varying vec3 box_center;
varying vec3 box_scale;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    camera_position = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    
    // Get the actual physical bounds of the BoxMesh
    box_scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz)) * 0.5;
    box_center = MODEL_MATRIX[3].xyz;
}

// Box Intersection
vec2 intersectAABB(vec3 ro, vec3 rd, vec3 boxMin, vec3 boxMax) {
    vec3 tMin = (boxMin - ro) / rd;
    vec3 tMax = (boxMax - ro) / rd;
    vec3 t1 = min(tMin, tMax);
    vec3 t2 = max(tMin, tMax);
    float tNear = max(max(t1.x, t1.y), t1.z);
    float tFar = min(min(t2.x, t2.y), t2.z);
    return vec2(tNear, tFar);
}

// ORIGINAL MATH: Remap
float remap(float originalValue,  float originalMin,  float originalMax,  float newMin,  float newMax) {
    return newMin + (((originalValue - originalMin) / (originalMax - originalMin)) * (newMax - newMin));
}

// ORIGINAL MATH: Phase
float henyey_greenstein(float cos_theta, float g) {
    const float k = 0.0795774715459;
    return k * (1.0 - g * g) / (pow(1.0 + g * g - 2.0 * g * cos_theta, 1.5));
}

// NEW HEIGHT FUNCTION: Based on the BoxMesh limits instead of Earth radius
float GetHeightFractionForPoint(float p_y) { 
    float box_bottom = box_center.y - box_scale.y;
    float box_top = box_center.y + box_scale.y;
    return clamp((p_y - box_bottom) / (box_top - box_bottom), 0.0, 1.0);
}

// ORIGINAL MATH: Gradients
vec4 mixGradients(float cloudType){
    const vec4 STRATUS_GRADIENT = vec4(0.02, 0.05, 0.09, 0.11);
    const vec4 STRATOCUMULUS_GRADIENT = vec4(0.02, 0.2, 0.48, 0.625);
    const vec4 CUMULUS_GRADIENT = vec4(0.01, 0.0625, 0.78, 1.0);
    float stratus = 1.0 - clamp(cloudType * 2.0, 0.0, 1.0);
    float stratocumulus = 1.0 - abs(cloudType - 0.5) * 2.0;
    float cumulus = clamp(cloudType - 0.5, 0.0, 1.0) * 2.0;
    return STRATUS_GRADIENT * stratus + STRATOCUMULUS_GRADIENT * stratocumulus + CUMULUS_GRADIENT * cumulus;
}

float densityHeightGradient(float heightFrac, float cloudType) {
    vec4 cloudGradient = mixGradients(cloudType);
    return smoothstep(cloudGradient.x, cloudGradient.y, heightFrac) - smoothstep(cloudGradient.z, cloudGradient.w, heightFrac);
}

// ORIGINAL MATH: Density calculation
float density(vec3 p, vec3 weather, float mip) {
    float time = TIME;
    float height_fraction = GetHeightFractionForPoint(p.y);
    
    p.xz += time * 20.0 * normalize(wind_direction) * wind_speed * 0.6;
    vec4 n = textureLod(perlworlnoise, p.xyz * 0.00008, mip - 2.0);
    float fbm = n.g*0.625 + n.b*0.25 + n.a*0.125;
    float g = densityHeightGradient(height_fraction, weather.r);
    
    float base_cloud = remap(n.r, -(1.0-fbm), 1.0, 0.0, 1.0);
    float weather_coverage = cloud_coverage * weather.b;
    base_cloud = remap(base_cloud*g, 1.0-(weather_coverage), 1.0, 0.0, 1.0);
    base_cloud *= weather_coverage;
    
    p.xz -= time * normalize(wind_direction) * 40.0;
    p.y -= time * 40.0;
    vec3 hn = textureLod(worlnoise, p*0.001, mip).rgb;
    float hfbm = hn.r*0.625 + hn.g*0.25 + hn.b*0.125;
    hfbm = mix(hfbm, 1.0-hfbm, clamp(height_fraction*4.0, 0.0, 1.0));
    
    base_cloud = remap(base_cloud, hfbm*0.4 * height_fraction, 1.0, 0.0, 1.0);
    return pow(clamp(base_cloud, 0.0, 1.0), (1.0 - height_fraction) * 0.8 + 0.5);
}

// ORIGINAL MATH: Raymarching Volumetric Loop
vec4 march(vec3 ro, vec3 rd, float t_start, float t_end) {
    float total_distance = t_end - t_start;
    float ss = total_distance / float(steps); // step size
    float lss = ss * 0.5; // light step size
    
    vec3 ldir = normalize(sun_direction);
    vec3 p = ro + rd * t_start;
    
    // Dither starting position to prevent ugly banding
    p += rd * fract(sin(dot(ro.xy, vec2(12.9898,78.233))) * 43758.5453) * ss;

    float T = 1.0;
    float alpha = 0.0;
    vec3 L = vec3(0.0);
    
    float costheta = dot(ldir, rd);
    float phase = max(max(henyey_greenstein(costheta, 0.6), henyey_greenstein(costheta, (0.4 - 1.4 * ldir.y))), henyey_greenstein(costheta, -0.2));
    
    // Colors
    vec3 atmosphere_sun = sun_color.rgb * sun_energy;
    vec3 atmosphere_ambient = vec3(0.5, 0.6, 0.8);
    vec3 atmosphere_ground = vec3(0.3, 0.3, 0.3);
    
    float time = TIME * 0.001 + 0.005 * _time_offset;
    vec2 weather_pos = time * normalize(wind_direction) * wind_speed;
    const float weather_scale = 0.00006;
    
    for (int i = 0; i < steps; i++) {
        vec3 weather_sample = texture(weathermap, p.xz * weather_scale + 0.5 + weather_pos).xyz;
        float height_fraction = GetHeightFractionForPoint(p.y);

        float t = density(p, weather_sample, 0.0);
        float dt = exp(-_density * t * ss);
        T *= dt;

        if (t > 0.0) {
            vec3 lp = p;
            float cd = 0.0;
            
            // Light march
            for (int j = 0; j < 6; j++) {
                lp += ldir * lss;
                vec3 lweather = texture(weathermap, lp.xz * weather_scale + 0.5 + weather_pos).xyz;
                cd += density(lp, lweather, float(j));
            }
            
            float beers = exp(-_density * cd * lss);
            float beers2 = exp(-_density * cd * lss * 0.25) * 0.7;
            float beers_total = max(beers, beers2);

            vec3 ambient = mix(atmosphere_ground, vec3(1.0), smoothstep(0.0, 1.0, height_fraction)) * _density * mix(atmosphere_ambient, vec3(1.0), 0.4) * clamp(sun_direction.y, 0.0, 1.0);
            
            float current_alpha = (1.0 - dt) * (1.0 - alpha);
            alpha += current_alpha;
            L += (ambient + beers_total * atmosphere_sun * phase * current_alpha) * T * t;
        }
        
        p += rd * ss;
        if (T < 0.01) break; // Early exit to save performance
    }
    return clamp(vec4(L, alpha), 0.0, 1.0);
}

void fragment() {
    vec3 ro = camera_position;
    vec3 rd = normalize(world_position - ro);
    
    vec3 extents = box_scale;
    vec2 hit = intersectAABB(ro, rd, box_center - extents, box_center + extents);

    // If ray misses the box entirely
    if (hit.x > hit.y || hit.y < 0.0) {
        discard;
    }

    // Start marching at the camera if we are inside the box, otherwise start at the box edge
    float t_start = max(0.0, hit.x);
    float t_end = hit.y;

    vec4 col = march(ro, rd, t_start, t_end);
    
    ALBEDO = col.rgb;
    ALPHA = col.a;
}