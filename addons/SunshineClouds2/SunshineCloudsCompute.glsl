#[compute]
#version 450

#define PI 3.14159265359
#define ABSORPTION_COEFFICIENT 0.9

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, binding = 0) uniform image2D output_data_image;
layout(rgba32f, binding = 1) uniform image2D output_color_image;
layout(rgba32f, binding = 2) uniform image2D accum_1A_image;
layout(rgba32f, binding = 3) uniform image2D accum_1B_image;
layout(rgba32f, binding = 4) uniform image2D accum_2A_image;
layout(rgba32f, binding = 5) uniform image2D accum_2B_image;

layout(binding = 6) uniform sampler2D depth_image;
layout(binding = 7) uniform sampler2D extra_large_noise;
layout(binding = 8) uniform sampler3D large_noise;
layout(binding = 9) uniform sampler3D noise_medium;
layout(binding = 10) uniform sampler3D noise_small;
layout(binding = 11) uniform sampler3D curl_noise;
layout(binding = 12) uniform sampler2D dither_small;
layout(binding = 13) uniform sampler2D heightmask;

struct GenericData {
    vec4 extralarge_noise_scale;
    vec4 large_noise_lighting;
    vec4 medium_noise_travel;
    vec4 small_noise_atmos;
    vec4 ambient_color;
    vec4 ambient_occlusion_color;
    vec4 atmosphere_fog_color;
    vec4 step_and_lod;
    vec4 cloud_params1;
    vec4 cloud_bounds;
    vec4 effects_params;
    vec4 wind_and_queries;
    vec4 light_counts_and_swept;
    vec4 raster_and_scales;
    vec4 time_coverage_density;
    vec4 lighting_and_accum;

    mat4 cam_projection;
    mat4 cam_inv_projection;
    mat4 cam_view;
    mat4 cam_inv_view;
    mat4 prev_cam_projection;
    mat4 prev_cam_inv_projection;
    mat4 prev_cam_view;
    mat4 prev_cam_inv_view;
};

struct DirectionalLight {
    vec4 direction;
    vec4 color;
};

struct PointLight {
    vec4 position;
    vec4 color;
};

struct PointEffector {
    vec4 position;
    vec4 params;
};

layout(std140, binding = 14) uniform GeneralDataBlock {
    GenericData data;
} genericData;

layout(std140, binding = 15) uniform LightsBuffer {
    DirectionalLight directionalLights[4];
    PointLight pointLights[128];
    PointEffector pointEffectors[64];
};

layout(std430, binding = 16) restrict buffer SamplePointsBuffer {
    vec4 SamplePoints[32];
};

layout(std140, binding = 17) uniform DummySceneDataBlock {
    mat4 dummy_mat[8];
} dummy_scene_data;

float quadraticOut(float t) {
    return -t * (t - 2.0);
}

float quadraticIn(float t) {
    return t * t;
}

float remap(float value, float min1, float max1, float min2, float max2) {
    return min2 + (value - min1) * (max2 - min2) / (max1 - min1);
}

float BeersLaw(float dist, float absorption) {
    return exp(-dist * absorption);
}

float HenyeyGreenstein(float g, float costh) {
    return (1.0 - g * g) / (4.0 * PI * pow(max(1.0 + g * g - 2.0 * g * costh, 0.0001), 1.5));
}

vec2 getCloudLayerIntersections(vec3 ro, vec3 rd, float floorY, float ceilingY) {
    if (abs(rd.y) < 1e-5) {
        if (ro.y >= floorY && ro.y <= ceilingY) {
            return vec2(0.0, 1e6);
        }
        return vec2(-1.0);
    }
    float t0 = (floorY - ro.y) / rd.y;
    float t1 = (ceilingY - ro.y) / rd.y;
    return vec2(max(min(t0, t1), 0.0), max(t0, t1));
}

float sampleEffectorAdditive(vec3 worldPosition) {
    float effectorAdditive = 0.0;
    int count = int(genericData.data.light_counts_and_swept.y);
    for (int i = 0; i < count; i++) {
        float d = distance(pointEffectors[i].position.xyz, worldPosition);
        float r = pointEffectors[i].position.w;
        if (d < r) {
            effectorAdditive += mix(pointEffectors[i].params.x, 0.0, d / r);
        }
    }
    return effectorAdditive;
}

float sampleScene(
    vec3 largeNoisePos,
    vec3 mediumNoisePos,
    vec3 smallNoisePos,
    vec3 worldPosition,
    float cloudceiling,
    float cloudfloor,
    float extralargeNoiseValue,
    float largenoisescale,
    float mediumnoisescale,
    float smallnoisescale,
    float coverage,
    float smallscalePower,
    float curlPower,
    float lod,
    bool ambientsample)
{
    float clampedWorldHeight = remap(worldPosition.y, cloudfloor, cloudceiling, 0.0, 1.0);
    vec4 gradientSample = texture(heightmask, vec2(clampedWorldHeight, 0.5)).rgba;

    float edgeFade = min(smoothstep(0.0, 0.1, clampedWorldHeight), smoothstep(1.0, 0.9, clampedWorldHeight));
    float extraLargeShape = extralargeNoiseValue * gradientSample.b;

    if (extraLargeShape <= 0.0001) {
        return 0.0;
    }

    float smallShape = texture(noise_small, (worldPosition - smallNoisePos) / smallnoisescale).r;
    float curlHeightSample = (1.0 - gradientSample.a);

    float effectorAdditive = 0.0;
    vec2 windDir = genericData.data.wind_and_queries.xy;
    float sweptRange = genericData.data.light_counts_and_swept.z;
    float sweptPower = genericData.data.light_counts_and_swept.w;
    worldPosition += vec3(windDir.x, 0.0, windDir.y) * sweptPower * quadraticIn(1.0 - clamp(clampedWorldHeight / max(sweptRange, 0.001), 0.0, 1.0));

    if (lod > 0.0) {
        effectorAdditive = sampleEffectorAdditive(worldPosition) * edgeFade;

        if (!ambientsample && curlHeightSample > 0.0 && min(curlPower, lod) > 0.5) {
            float curlLod = remap(lod, 0.5, 1.0, 0.0, 1.0);
            vec3 curlOffset = (((texture(curl_noise, (worldPosition - mediumNoisePos) / mediumnoisescale).xyz * 2.0) - 1.0) * vec3(1.0, 0.2, 1.0) + vec3(windDir.x, 0.0, windDir.y) * 0.9) * curlPower * curlHeightSample * curlLod;
            worldPosition += curlOffset * 3.0;

            clampedWorldHeight = remap(worldPosition.y, cloudfloor, cloudceiling, 0.0, 1.0);
            gradientSample = texture(heightmask, vec2(clampedWorldHeight, 0.5)).rgba;
        }
    }

    float largeShape = texture(large_noise, (worldPosition - largeNoisePos) / largenoisescale).r * extraLargeShape;
    largeShape = smoothstep(coverage, coverage - 0.1, 1.0 - (largeShape * gradientSample.r)) + max(effectorAdditive, 0.0);
    vec4 mediumShapes = texture(noise_medium, (worldPosition - mediumNoisePos) / mediumnoisescale).rgba;
    float mediumshape = 1.0 - mediumShapes.b;
    smallShape = smallShape * gradientSample.g * pow((1.0 - mediumshape), smallscalePower);

    float shape = mediumshape + max(effectorAdditive, 0.0);
    shape = clamp(remap(shape, 1.0 - largeShape, 1.0, 0.0, 1.0), 0.0, 1.0);
    shape = clamp(remap(shape, smallShape, 1.0, 0.0, 1.0), 0.0, 1.0);
    shape += min(effectorAdditive, 0.0);

    return clamp((shape * edgeFade * extraLargeShape), 0.0, 1.0);
}

float sampleLighting(
    int stepCount,
    vec3 worldPosition,
    vec3 extralargeNoisePos,
    vec3 largeNoisePos,
    vec3 mediumNoisePos,
    vec3 smallNoisePos,
    vec3 sunDirection,
    float densityMultiplier,
    float sunUpWeight,
    float stepDistance,
    float cloudceiling,
    float cloudfloor,
    float extralargenoisescale,
    float largenoisescale,
    float mediumnoisescale,
    float smallnoisescale,
    float coverage,
    float smallscalePower,
    float curlPower,
    float lod)
{
    float density = 0.0;
    float stepCountFloat = max(float(stepCount) * lod, 2.0);
    float actualDistance = mix(stepDistance * 4.0, stepDistance, lod);
    float eachShortStep = actualDistance / (float(stepCount) / stepCountFloat) / stepCountFloat;
    float traveledDistance = 0.0;

    float sunUpValue = 1.0 - sunUpWeight;
    float eachStepWeight = 1.0 / stepCountFloat;

    for (float i = 0.0; i < stepCountFloat; i++) {
        traveledDistance = mix(eachShortStep, actualDistance, clamp(quadraticOut(i / stepCountFloat), 0.0, 1.0));
        vec3 curPos = worldPosition + sunDirection * traveledDistance;

        if (density < 1.0 && clamp(curPos.y, cloudfloor, cloudceiling) == curPos.y) {
            float heightGradient = remap(curPos.y, cloudfloor, cloudceiling, 0.0, 1.0);
            heightGradient = clamp(smoothstep(sunUpValue - 0.1, sunUpValue, heightGradient), 0.0, 1.0);
            float extraLargeShape = texture(extra_large_noise, (curPos.xz - extralargeNoisePos.xz) / extralargenoisescale).a;

            float thisDensity = sampleScene(largeNoisePos, mediumNoisePos, smallNoisePos, curPos, cloudceiling, cloudfloor, extraLargeShape, largenoisescale, mediumnoisescale, smallnoisescale, coverage, smallscalePower, curlPower, lod, true) * densityMultiplier * eachStepWeight;
            density += mix(1.0, thisDensity, heightGradient);
        } else {
            break;
        }
    }

    return density;
}

void main() {
    ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = ivec2(genericData.data.raster_and_scales.xy);

    if (uv.x >= size.x || uv.y >= size.y) {
        return;
    }

    vec2 depthUV = (vec2(uv) + 0.5) / vec2(size);
    float depth = texture(depth_image, depthUV).r;

    vec4 view = genericData.data.cam_inv_projection * vec4(depthUV * 2.0 - 1.0, depth, 1.0);
    view.xyz /= view.w;
    float linear_depth = length(view.xyz);
    if (depth == 0.0) {
        linear_depth *= 100.0;
    }

    vec4 clipPos = vec4(depthUV * 2.0 - 1.0, 1.0, 1.0);
    vec4 viewPos = genericData.data.cam_inv_projection * clipPos;
    viewPos.xyz /= viewPos.w;

    vec3 rd_world = normalize(mat3(genericData.data.cam_inv_view) * normalize(viewPos.xyz));
    vec3 rayOrigin = genericData.data.cam_inv_view[3].xyz;

    float ditherScale = 40.037;
    vec2 ditherUV = (depthUV * ditherScale) + vec2(mod(genericData.data.time_coverage_density.x, 100.0));
    float ditherValue = texture(dither_small, ditherUV).r;

    int stepCount = int(genericData.data.cloud_bounds.z);
    int lightingStepCount = int(genericData.data.cloud_bounds.w);
    int directionalLightCount = int(genericData.data.cloud_params1.y);
    int pointLightCount = int(genericData.data.light_counts_and_swept.x);

    vec3 extralargeNoisePos = genericData.data.extralarge_noise_scale.xyz;
    vec3 largeNoisePos = genericData.data.large_noise_lighting.xyz;
    vec3 mediumNoisePos = genericData.data.medium_noise_travel.xyz;
    vec3 smallNoisePos = genericData.data.small_noise_atmos.xyz;

    float extralargenoiseScale = genericData.data.extralarge_noise_scale.w;
    float largenoiseScale = genericData.data.raster_and_scales.z;
    float mediumnoiseScale = genericData.data.raster_and_scales.w;
    float smallnoiseScale = genericData.data.step_and_lod.x;

    float minstep = genericData.data.step_and_lod.y;
    float maxstep = genericData.data.step_and_lod.z;
    float lod_bias = genericData.data.step_and_lod.w;

    float curlPower = genericData.data.effects_params.w;
    float lightingStepDistance = genericData.data.medium_noise_travel.w;
    float cloudfloor = genericData.data.cloud_bounds.x;
    float cloudceiling = genericData.data.cloud_bounds.y;

    float densityMultiplier = genericData.data.time_coverage_density.z;
    float sharpness = clamp(1.0 - genericData.data.cloud_params1.x, 0.001, 1.0) * 2.0;
    float lightingSharpness = genericData.data.large_noise_lighting.w;
    float smallNoiseMultiplier = genericData.data.time_coverage_density.w;
    float coverage = genericData.data.time_coverage_density.y * 1.01;

    float lightingdensityMultiplier = genericData.data.lighting_and_accum.x;
    lightingdensityMultiplier += lightingdensityMultiplier * 3.0 * coverage;

    vec4 aobase = genericData.data.ambient_occlusion_color;
    bool depthBreak = false;

    float maxTheoreticalStep = float(stepCount) * maxstep;
    float highestDensity = 0.0;
    float highestDensityDistance = maxTheoreticalStep;
    float lodMaxDistance = maxstep * float(stepCount) * lod_bias;

    vec2 slab = getCloudLayerIntersections(rayOrigin, rd_world, cloudfloor, cloudceiling);
    float tStart = max(slab.x, 0.0);
    float tEnd = min(slab.y, min(maxTheoreticalStep, linear_depth));

    float newStep = maxstep * ditherValue;
    float traveledDistance = tStart + newStep;

    vec3 directionalLightSunUpPower[4] = vec3[4](vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0));
    float totalLightPower = 0.0;

    for (int lightI = 0; lightI < directionalLightCount; lightI++) {
        if (directionalLights[lightI].color.a > 0.0) {
            directionalLightSunUpPower[lightI].r = smoothstep(-0.03, 0.07, dot(directionalLights[lightI].direction.xyz, vec3(0.0, 1.0, 0.0)));
            totalLightPower += directionalLights[lightI].color.a * directionalLightSunUpPower[lightI].r;
            directionalLightSunUpPower[lightI].b = dot(directionalLights[lightI].direction.xyz, rd_world);
        }
    }

    vec4 lightColor = vec4(0.0);
    vec3 paintedColor = vec3(0.0);
    float initialdistanceSample = 0.0;

    float lightingSamples = 0.0;
    float density = 0.0;
    float ambient = 0.0;
    float depthFade = 1.0;
    float newdensity = 0.0;
    vec3 curPos = vec3(0.0);

    float curLod = 1.0;
    float samplePosCount = genericData.data.wind_and_queries.w;

    if (samplePosCount > 0.0 && uv == ivec2(0)) {
        for (int i = 0; i < int(samplePosCount); i++) {
            curPos = SamplePoints[i].xyz;
            vec4 maskSample = texture(extra_large_noise, (curPos.xz - extralargeNoisePos.xz) / extralargenoiseScale);
            SamplePoints[i].w = pow(sampleScene(largeNoisePos, mediumNoisePos, smallNoisePos, curPos, cloudceiling, cloudfloor, maskSample.a, largenoiseScale, mediumnoiseScale, smallnoiseScale, coverage, smallNoiseMultiplier, curlPower, 1.0, false) * densityMultiplier, sharpness);
        }
    }

    if (tStart <= tEnd) {
        for (int i = 0; i < stepCount; i++) {
            if (traveledDistance > tEnd) {
                if (traveledDistance > linear_depth) {
                    depthBreak = true;
                }
                break;
            }

            curPos = rayOrigin + rd_world * traveledDistance;
            vec4 maskSample = texture(extra_large_noise, (curPos.xz - extralargeNoisePos.xz) / extralargenoiseScale);

            curLod = 1.0 - clamp(traveledDistance / lodMaxDistance, 0.0, 1.0);
            newdensity = pow(sampleScene(largeNoisePos, mediumNoisePos, smallNoisePos, curPos, cloudceiling, cloudfloor, maskSample.a, largenoiseScale, mediumnoiseScale, smallnoiseScale, coverage, smallNoiseMultiplier, curlPower, curLod, false) * densityMultiplier, sharpness) * depthFade;

            if (newdensity > 0.0) {
                if (initialdistanceSample == 0.0) {
                    initialdistanceSample = traveledDistance;
                }

                float powderEffect = pow(newdensity, genericData.data.cloud_params1.z * 2.0);
                paintedColor += maskSample.rgb;
                lightingSamples += 1.0;

                for (int lightI = 0; lightI < directionalLightCount; lightI++) {
                    vec3 sundir = directionalLights[lightI].direction.xyz;
                    float sunUpWeight = directionalLightSunUpPower[lightI].r;

                    int thislightingStepCount = min(int(directionalLights[lightI].direction.w), lightingStepCount);
                    float henyeygreenstein = pow(HenyeyGreenstein(genericData.data.cloud_params1.w, directionalLightSunUpPower[lightI].b), mix(1.0, 2.0, 1.0 - genericData.data.cloud_params1.w));
                    float densitySample = sampleLighting(thislightingStepCount, curPos, extralargeNoisePos, largeNoisePos, mediumNoisePos, smallNoisePos, sundir, densityMultiplier * lightingdensityMultiplier, sunUpWeight, lightingStepDistance, cloudceiling, cloudfloor, extralargenoiseScale, largenoiseScale, mediumnoiseScale, smallnoiseScale, coverage, smallNoiseMultiplier, curlPower, curLod);
                    densitySample = BeersLaw(lightingStepDistance, densitySample * henyeygreenstein);
                    float thisStepLightingWeight = (pow(densitySample, lightingSharpness)) * sunUpWeight;

                    lightColor.rgb += pow(directionalLights[lightI].color.rgb * directionalLights[lightI].color.a * thisStepLightingWeight, vec3(2.2)) * powderEffect;
                    directionalLightSunUpPower[lightI].g += directionalLights[lightI].color.a * thisStepLightingWeight;
                }

                for (int lightI = 0; lightI < pointLightCount; lightI++) {
                    vec3 lightToOriginDelta = pointLights[lightI].position.xyz - curPos;
                    float lightDistanceWeight = length(lightToOriginDelta);
                    if (pointLights[lightI].color.a > 0.0 && lightDistanceWeight < pointLights[lightI].position.w) {
                        lightToOriginDelta = normalize(lightToOriginDelta);
                        float densitySample = sampleLighting(3, curPos, extralargeNoisePos, largeNoisePos, mediumNoisePos, smallNoisePos, lightToOriginDelta, densityMultiplier, 1.0, min(maxstep, lightDistanceWeight), cloudceiling, cloudfloor, extralargenoiseScale, largenoiseScale, mediumnoiseScale, smallnoiseScale, coverage, smallNoiseMultiplier, curlPower, curLod);

                        float henyeygreenstein = pow(HenyeyGreenstein(genericData.data.cloud_params1.w, dot(lightToOriginDelta, rd_world)), mix(1.0, 2.0, 1.0 - genericData.data.cloud_params1.w));
                        densitySample = BeersLaw(lightDistanceWeight, densitySample * henyeygreenstein);
                        densitySample = mix(densitySample, newdensity, 0.5) * powderEffect;
                        lightDistanceWeight = lightDistanceWeight / pointLights[lightI].position.w;
                        lightDistanceWeight = pointLights[lightI].color.a * pow((1.0 - lightDistanceWeight), 2.2) * densitySample;

                        lightColor.rgb += pow(pointLights[lightI].color.rgb * lightDistanceWeight, vec3(2.2));
                    }
                }

                if (aobase.a > 0.0) {
                    ambient += sampleScene(largeNoisePos, mediumNoisePos, smallNoisePos, curPos + vec3(0.0, 1.0, 0.0) * minstep, cloudceiling, cloudfloor, maskSample.a, largenoiseScale, mediumnoiseScale, smallnoiseScale, coverage, smallNoiseMultiplier, curlPower, curLod, true) * densityMultiplier * lightingdensityMultiplier;
                }

                newStep = mix(mix(maxstep, minstep, pow(newdensity, 0.1)), maxstep, float(i) / float(stepCount));
                if (newdensity > highestDensity) {
                    highestDensity = newdensity;
                    highestDensityDistance = traveledDistance;
                }
            } else {
                newStep = maxstep;
            }

            if (i == 0) {
                newdensity = mix(newdensity, 0.0, traveledDistance / maxstep);
            }

            density += newdensity;
            if (density >= 1.0) {
                break;
            }

            traveledDistance += newStep;
        }
    }

    density = clamp(density, 0.0, 1.0);
    density *= clamp(smoothstep(maxstep * float(stepCount), minstep * float(stepCount), traveledDistance), 0.0, 1.0);
    ambient = clamp(ambient / max(lightingSamples, 1.0), 0.0, 1.0);
    paintedColor = clamp(paintedColor / max(lightingSamples, 1.0), 0.0, 1.0);

    vec3 ambientLight = genericData.data.ambient_color.rgb * totalLightPower;
    ambientLight = mix(ambientLight, ambientLight * aobase.rgb, ambient * aobase.a) * paintedColor;

    lightColor.rgb += ambientLight * density;
    lightColor.a = density;

    float finalDensityDistance = min(traveledDistance, highestDensityDistance);
    vec3 worldFinalPos = rayOrigin + rd_world * traveledDistance;
    vec3 delta = rayOrigin - genericData.data.prev_cam_inv_view[3].xyz;
    worldFinalPos += delta;

    vec4 reprojectedClipPos = genericData.data.prev_cam_view * vec4(worldFinalPos, 1.0);
    bool is_override = (reprojectedClipPos.z <= 0.0);

    vec4 reprojectedScreenPos = genericData.data.prev_cam_projection * reprojectedClipPos;
    vec2 reprojectedNdc = (reprojectedScreenPos.xy / reprojectedScreenPos.w);
    vec2 screen_position = (reprojectedNdc * 0.5 + 0.5) - depthUV;

    ivec2 adjustedUV = uv + ivec2(screen_position * vec2(size));
    bool is_out_of_bounds = (adjustedUV.x < 0 || adjustedUV.x >= size.x || adjustedUV.y < 0 || adjustedUV.y >= size.y);
    ivec2 clampedUV = clamp(adjustedUV, ivec2(0), size - ivec2(1));

    float accumdecay = genericData.data.lighting_and_accum.y;
    float usingaccumA = genericData.data.lighting_and_accum.z;
    float travelspeed = length(delta) + maxstep;

    vec4 currentColorAccumilation;
    vec4 currentDataAccumilation;

    if (usingaccumA > 0.0) {
        currentColorAccumilation = imageLoad(accum_1A_image, clampedUV).rgba;
        currentDataAccumilation = imageLoad(accum_2A_image, clampedUV).rgba;
    } else {
        currentColorAccumilation = imageLoad(accum_1B_image, clampedUV).rgba;
        currentDataAccumilation = imageLoad(accum_2B_image, clampedUV).rgba;
    }

    float currentDepthBreak = float(depthBreak);

    if (is_override || is_out_of_bounds || (currentDepthBreak != currentDataAccumilation.a && abs(initialdistanceSample - currentDataAccumilation.r) > travelspeed * 0.5)) {
        currentColorAccumilation = lightColor;
        currentDataAccumilation.r = initialdistanceSample;
        currentDataAccumilation.g = traveledDistance;
        currentDataAccumilation.b = finalDensityDistance;
    } else {
        currentColorAccumilation = mix(lightColor, currentColorAccumilation, accumdecay);
        currentDataAccumilation.r = mix(initialdistanceSample, currentDataAccumilation.r, accumdecay);
        currentDataAccumilation.g = mix(traveledDistance, currentDataAccumilation.g, accumdecay);
        currentDataAccumilation.b = mix(finalDensityDistance, currentDataAccumilation.b, accumdecay);
    }
    currentDataAccumilation.a = currentDepthBreak;

    if (usingaccumA > 0.0) {
        imageStore(accum_1B_image, uv, currentColorAccumilation);
        imageStore(accum_2B_image, uv, currentDataAccumilation);
    } else {
        imageStore(accum_1A_image, uv, currentColorAccumilation);
        imageStore(accum_2A_image, uv, currentDataAccumilation);
    }

    currentDataAccumilation.r = min(currentDataAccumilation.r, initialdistanceSample);
    imageStore(output_color_image, uv, currentColorAccumilation);
    imageStore(output_data_image, uv, currentDataAccumilation);
}
