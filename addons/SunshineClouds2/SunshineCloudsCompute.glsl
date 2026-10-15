#[compute]
#version 450

#define PI 3.14159265359
#define ABSORPTION_COEFFICIENT 0.9

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, binding = 0) uniform image2D output_data_image;
layout(rgba16f, binding = 1) uniform image2D output_color_image;
layout(rgba16f, binding = 2) uniform image2D accum_1A_image;
layout(rgba16f, binding = 3) uniform image2D accum_1B_image;
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

float quadraticOut(float t) {
	return -t * (t - 2.0);
}

float quadraticIn(float t) {
	return t * t;
}

float remap(float value, float min1, float max1, float min2, float max2) {
	float diff = max1 - min1;
	if (abs(diff) < 0.00001) {
		return min2;
	}
	return min2 + (value - min1) * (max2 - min2) / diff;
}

float BeersLaw(float dist, float absorption) {
	return exp(-max(dist * absorption, 0.0));
}

float HenyeyGreenstein(float g, float costh) {
	float g2 = g * g;
	float denom = max(1.0 + g2 - 2.0 * g * costh, 0.0001);
	return (1.0 - g2) / (4.0 * PI * denom * sqrt(denom));
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
	int count = min(int(genericData.data.light_counts_and_swept.y), 64);
	for (int i = 0; i < count; i++) {
		float d = distance(pointEffectors[i].position.xyz, worldPosition);
		float r = max(pointEffectors[i].position.w, 0.0001);
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
	float clampedWorldHeight = clamp(remap(worldPosition.y, cloudfloor, cloudceiling, 0.0, 1.0), 0.0, 1.0);
	vec4 gradientSample = texture(heightmask, vec2(clampedWorldHeight, 0.5)).rgba;

	// FIX: Replaced inverted smoothstep(1.0, 0.9, x) with 1.0 - smoothstep(0.9, 1.0, x)
	float edgeFade = min(
		smoothstep(0.0, 0.1, clampedWorldHeight),
		1.0 - smoothstep(0.9, 1.0, clampedWorldHeight)
	);
	float extraLargeShape = extralargeNoiseValue * gradientSample.b;

	if (extraLargeShape <= 0.0001) {
		return 0.0;
	}

	float safeSmallScale = max(smallnoisescale, 0.001);
	float safeMedScale = max(mediumnoisescale, 0.001);
	float safeLargeScale = max(largenoisescale, 0.001);

	float smallShape = texture(noise_small, (worldPosition - smallNoisePos) / safeSmallScale).r;
	float curlHeightSample = (1.0 - gradientSample.a);

	float effectorAdditive = 0.0;
	vec2 windDir = genericData.data.wind_and_queries.xy;
	float sweptRange = genericData.data.light_counts_and_swept.z;
	float sweptPower = genericData.data.light_counts_and_swept.w;
	worldPosition += vec3(windDir.x, 0.0, windDir.y) * sweptPower * quadraticIn(1.0 - clamp(clampedWorldHeight / max(sweptRange, 0.001), 0.0, 1.0));

	if (lod > 0.0) {
		effectorAdditive = sampleEffectorAdditive(worldPosition) * edgeFade;

		if (!ambientsample && curlHeightSample > 0.0 && min(curlPower, lod) > 0.5) {
			float curlLod = clamp(remap(lod, 0.5, 1.0, 0.0, 1.0), 0.0, 1.0);
			vec3 curlOffset = (((texture(curl_noise, (worldPosition - mediumNoisePos) / safeMedScale).xyz * 2.0) - 1.0) * vec3(1.0, 0.2, 1.0) + vec3(windDir.x, 0.0, windDir.y) * 0.9) * curlPower * curlHeightSample * curlLod;
			worldPosition += curlOffset * 3.0;

			clampedWorldHeight = clamp(remap(worldPosition.y, cloudfloor, cloudceiling, 0.0, 1.0), 0.0, 1.0);
			gradientSample = texture(heightmask, vec2(clampedWorldHeight, 0.5)).rgba;
		}
	}

	float largeShape = texture(large_noise, (worldPosition - largeNoisePos) / safeLargeScale).r * extraLargeShape;
	// FIX: Replaced inverted smoothstep(coverage, coverage - 0.1, x)
	largeShape = (1.0 - smoothstep(coverage - 0.1, coverage, 1.0 - (largeShape * gradientSample.r))) + max(effectorAdditive, 0.0);
	vec4 mediumShapes = texture(noise_medium, (worldPosition - mediumNoisePos) / safeMedScale).rgba;
	float mediumshape = 1.0 - mediumShapes.b;
	smallShape = smallShape * gradientSample.g * pow(max(1.0 - mediumshape, 0.0), max(smallscalePower, 0.0001));

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
	float safeStepCount = max(float(stepCount), 1.0);
	float stepCountFloat = max(safeStepCount * lod, 2.0);
	float actualDistance = mix(stepDistance * 4.0, stepDistance, lod);
	float eachShortStep = actualDistance / max((safeStepCount / stepCountFloat) * stepCountFloat, 0.0001);
	float traveledDistance = 0.0;

	float sunUpValue = 1.0 - sunUpWeight;
	float eachStepWeight = 1.0 / stepCountFloat;
	float safeExtraLargeScale = max(extralargenoisescale, 0.001);

	for (float i = 0.0; i < stepCountFloat; i++) {
		traveledDistance = mix(eachShortStep, actualDistance, clamp(quadraticOut(i / stepCountFloat), 0.0, 1.0));
		vec3 curPos = worldPosition + sunDirection * traveledDistance;

		if (density < 1.0 && clamp(curPos.y, cloudfloor, cloudceiling) == curPos.y) {
			float heightGradient = clamp(remap(curPos.y, cloudfloor, cloudceiling, 0.0, 1.0), 0.0, 1.0);
			heightGradient = clamp(smoothstep(sunUpValue - 0.1, sunUpValue, heightGradient), 0.0, 1.0);
			float extraLargeShape = texture(extra_large_noise, (curPos.xz - extralargeNoisePos.xz) / safeExtraLargeScale).a;

			float thisDensity = sampleScene(largeNoisePos, mediumNoisePos, smallNoisePos, curPos, cloudceiling, cloudfloor, extraLargeShape, largenoisescale, mediumnoisescale, smallnoisescale, coverage, smallscalePower, curlPower, lod, true) * densityMultiplier * eachStepWeight;
			density += mix(1.0, thisDensity, heightGradient);
		} else {
			break;
		}
	}

	return max(density, 0.0);
}

void sampleHistoryBilinear(
	vec2 reprojectedUV,
	ivec2 size,
	bool useAccumA,
	out vec4 outColor,
	out vec4 outData)
{
	vec2 pixelPos = reprojectedUV * vec2(size) - 0.5;
	ivec2 baseCoord = ivec2(floor(pixelPos));
	vec2 f = fract(pixelPos);

	ivec2 c00 = clamp(baseCoord + ivec2(0, 0), ivec2(0), size - ivec2(1));
	ivec2 c10 = clamp(baseCoord + ivec2(1, 0), ivec2(0), size - ivec2(1));
	ivec2 c01 = clamp(baseCoord + ivec2(0, 1), ivec2(0), size - ivec2(1));
	ivec2 c11 = clamp(baseCoord + ivec2(1, 1), ivec2(0), size - ivec2(1));

	vec4 col00, col10, col01, col11;
	vec4 dat00, dat10, dat01, dat11;

	if (useAccumA) {
		col00 = imageLoad(accum_1A_image, c00);
		col10 = imageLoad(accum_1A_image, c10);
		col01 = imageLoad(accum_1A_image, c01);
		col11 = imageLoad(accum_1A_image, c11);

		dat00 = imageLoad(accum_2A_image, c00);
		dat10 = imageLoad(accum_2A_image, c10);
		dat01 = imageLoad(accum_2A_image, c01);
		dat11 = imageLoad(accum_2A_image, c11);
	} else {
		col00 = imageLoad(accum_1B_image, c00);
		col10 = imageLoad(accum_1B_image, c10);
		col01 = imageLoad(accum_1B_image, c01);
		col11 = imageLoad(accum_1B_image, c11);

		dat00 = imageLoad(accum_2B_image, c00);
		dat10 = imageLoad(accum_2B_image, c10);
		dat01 = imageLoad(accum_2B_image, c01);
		dat11 = imageLoad(accum_2B_image, c11);
	}

	outColor = mix(mix(col00, col10, f.x), mix(col01, col11, f.x), f.y);
	outData = mix(mix(dat00, dat10, f.x), mix(dat01, dat11, f.x), f.y);
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
	view.xyz /= (abs(view.w) < 0.00001) ? 0.00001 : view.w;
	float linear_depth = length(view.xyz);
	if (depth <= 0.00001) {
		linear_depth = 1000000.0;
	}

	vec4 clipPos = vec4(depthUV * 2.0 - 1.0, 1.0, 1.0);
	vec4 viewPos = genericData.data.cam_inv_projection * clipPos;
	viewPos.xyz /= (abs(viewPos.w) < 0.00001) ? 0.00001 : viewPos.w;

	vec3 viewDir = normalize(viewPos.xyz + vec3(0.0, 0.0, 0.00001));
	vec3 rd_world = normalize(mat3(genericData.data.cam_inv_view) * viewDir);
	vec3 rayOrigin = genericData.data.cam_inv_view[3].xyz;

	// 1:1 per-pixel Blue Noise sampling with Golden Ratio temporal sequence
	ivec2 ditherSize = textureSize(dither_small, 0);
	float frameSeed = floor(genericData.data.time_coverage_density.x);
	ivec2 jitterOffset = ivec2(fract(vec2(0.754877666, 0.56984029) * frameSeed) * vec2(ditherSize));
	ivec2 ditherCoord = (uv + jitterOffset) % max(ditherSize, ivec2(1));
	float baseBlueNoise = texelFetch(dither_small, ditherCoord, 0).r;
	float ditherValue = fract(baseBlueNoise + fract(frameSeed * 0.61803398875));

	int stepCount = max(int(genericData.data.cloud_bounds.z), 1);
	int lightingStepCount = max(int(genericData.data.cloud_bounds.w), 1);
	int directionalLightCount = min(int(genericData.data.cloud_params1.y), 4);
	int pointLightCount = min(int(genericData.data.light_counts_and_swept.x), 128);

	vec3 extralargeNoisePos = genericData.data.extralarge_noise_scale.xyz;
	vec3 largeNoisePos = genericData.data.large_noise_lighting.xyz;
	vec3 mediumNoisePos = genericData.data.medium_noise_travel.xyz;
	vec3 smallNoisePos = genericData.data.small_noise_atmos.xyz;

	float extralargenoiseScale = max(genericData.data.extralarge_noise_scale.w, 0.001);
	float largenoiseScale = max(genericData.data.raster_and_scales.z, 0.001);
	float mediumnoiseScale = max(genericData.data.raster_and_scales.w, 0.001);
	float smallnoiseScale = max(genericData.data.step_and_lod.x, 0.001);

	float minstep = max(genericData.data.step_and_lod.y, 0.1);
	float maxstep = max(genericData.data.step_and_lod.z, minstep + 0.1);
	float lod_bias = max(genericData.data.step_and_lod.w, 0.001);

	float curlPower = genericData.data.effects_params.w;
	float lightingStepDistance = max(genericData.data.medium_noise_travel.w, 1.0);
	float cloudfloor = genericData.data.cloud_bounds.x;
	float cloudceiling = max(genericData.data.cloud_bounds.y, cloudfloor + 1.0);

	float densityMultiplier = max(genericData.data.time_coverage_density.z, 0.0);
	float sharpness = clamp(1.0 - genericData.data.cloud_params1.x, 0.001, 1.0) * 2.0;
	float lightingSharpness = max(genericData.data.large_noise_lighting.w, 0.0001);
	float smallNoiseMultiplier = max(genericData.data.time_coverage_density.w, 0.0001);
	float coverage = genericData.data.time_coverage_density.y * 1.01;

	float lightingdensityMultiplier = genericData.data.lighting_and_accum.x;
	lightingdensityMultiplier += lightingdensityMultiplier * 3.0 * coverage;

	vec4 aobase = genericData.data.ambient_occlusion_color;
	bool depthBreak = false;

	float maxTheoreticalStep = float(stepCount) * maxstep;
	float highestDensity = 0.0;
	float highestDensityDistance = maxTheoreticalStep;
	float lodMaxDistance = max(maxstep * float(stepCount) * lod_bias, 1.0);

	vec2 slab = getCloudLayerIntersections(rayOrigin, rd_world, cloudfloor, cloudceiling);
	float tStart = max(slab.x, 0.0);
	float tEnd = min(slab.y, min(maxTheoreticalStep, linear_depth));

	float newStep = minstep * ditherValue;
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
	int samplePosCount = min(int(genericData.data.wind_and_queries.w), 32);

	if (samplePosCount > 0 && uv == ivec2(0)) {
		for (int i = 0; i < samplePosCount; i++) {
			curPos = SamplePoints[i].xyz;
			vec4 maskSample = texture(extra_large_noise, (curPos.xz - extralargeNoisePos.xz) / extralargenoiseScale);
			float rawSample = sampleScene(largeNoisePos, mediumNoisePos, smallNoisePos, curPos, cloudceiling, cloudfloor, maskSample.a, largenoiseScale, mediumnoiseScale, smallnoiseScale, coverage, smallNoiseMultiplier, curlPower, 1.0, false) * densityMultiplier;
			SamplePoints[i].w = (rawSample <= 0.00001) ? 0.0 : pow(rawSample, sharpness);
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
			float rawDensity = sampleScene(largeNoisePos, mediumNoisePos, smallNoisePos, curPos, cloudceiling, cloudfloor, maskSample.a, largenoiseScale, mediumnoiseScale, smallnoiseScale, coverage, smallNoiseMultiplier, curlPower, curLod, false) * densityMultiplier;
			newdensity = ((rawDensity <= 0.00001) ? 0.0 : pow(rawDensity, sharpness)) * depthFade;

			if (newdensity > 0.0) {
				if (initialdistanceSample == 0.0) {
					initialdistanceSample = traveledDistance;
				}

				float powderExp = max(genericData.data.cloud_params1.z * 2.0, 0.0001);
				float powderEffect = (newdensity <= 0.0001) ? 0.0 : pow(newdensity, powderExp);
				paintedColor += maskSample.rgb;
				lightingSamples += 1.0;

				for (int lightI = 0; lightI < directionalLightCount; lightI++) {
					vec3 sundir = directionalLights[lightI].direction.xyz;
					float sunUpWeight = directionalLightSunUpPower[lightI].r;

					int thislightingStepCount = min(int(directionalLights[lightI].direction.w), lightingStepCount);
					float hgBase = max(HenyeyGreenstein(genericData.data.cloud_params1.w, directionalLightSunUpPower[lightI].b), 0.0001);
					float henyeygreenstein = pow(hgBase, mix(1.0, 2.0, 1.0 - genericData.data.cloud_params1.w));
					float densitySample = sampleLighting(thislightingStepCount, curPos, extralargeNoisePos, largeNoisePos, mediumNoisePos, smallNoisePos, sundir, densityMultiplier * lightingdensityMultiplier, sunUpWeight, lightingStepDistance, cloudceiling, cloudfloor, extralargenoiseScale, largenoiseScale, mediumnoiseScale, smallnoiseScale, coverage, smallNoiseMultiplier, curlPower, curLod);
					densitySample = BeersLaw(lightingStepDistance, densitySample * henyeygreenstein);
					float thisStepLightingWeight = pow(max(densitySample, 0.0001), lightingSharpness) * sunUpWeight;

					vec3 dirCol = max(directionalLights[lightI].color.rgb * directionalLights[lightI].color.a * thisStepLightingWeight, vec3(0.0));
					lightColor.rgb += pow(dirCol, vec3(2.2)) * powderEffect;
					directionalLightSunUpPower[lightI].g += directionalLights[lightI].color.a * thisStepLightingWeight;
				}

				for (int lightI = 0; lightI < pointLightCount; lightI++) {
					vec3 lightToOriginDelta = pointLights[lightI].position.xyz - curPos;
					float lightDistanceWeight = length(lightToOriginDelta);
					float lightRadius = max(pointLights[lightI].position.w, 0.001);
					if (pointLights[lightI].color.a > 0.0 && lightDistanceWeight < lightRadius) {
						lightToOriginDelta = normalize(lightToOriginDelta + vec3(0.0, 0.00001, 0.0));
						float densitySample = sampleLighting(3, curPos, extralargeNoisePos, largeNoisePos, mediumNoisePos, smallNoisePos, lightToOriginDelta, densityMultiplier, 1.0, min(maxstep, lightDistanceWeight), cloudceiling, cloudfloor, extralargenoiseScale, largenoiseScale, mediumnoiseScale, smallnoiseScale, coverage, smallNoiseMultiplier, curlPower, curLod);

						float hgBase = max(HenyeyGreenstein(genericData.data.cloud_params1.w, dot(lightToOriginDelta, rd_world)), 0.0001);
						float henyeygreenstein = pow(hgBase, mix(1.0, 2.0, 1.0 - genericData.data.cloud_params1.w));
						densitySample = BeersLaw(lightDistanceWeight, densitySample * henyeygreenstein);
						densitySample = mix(densitySample, newdensity, 0.5) * powderEffect;
						lightDistanceWeight = clamp(lightDistanceWeight / lightRadius, 0.0, 1.0);
						lightDistanceWeight = pointLights[lightI].color.a * pow(max(1.0 - lightDistanceWeight, 0.0), 2.2) * densitySample;

						vec3 ptCol = max(pointLights[lightI].color.rgb * lightDistanceWeight, vec3(0.0));
						lightColor.rgb += pow(ptCol, vec3(2.2));
					}
				}

				if (aobase.a > 0.0) {
					ambient += sampleScene(largeNoisePos, mediumNoisePos, smallNoisePos, curPos + vec3(0.0, 1.0, 0.0) * minstep, cloudceiling, cloudfloor, maskSample.a, largenoiseScale, mediumnoiseScale, smallnoiseScale, coverage, smallNoiseMultiplier, curlPower, curLod, true) * densityMultiplier * lightingdensityMultiplier;
				}

				newStep = mix(mix(maxstep, minstep, pow(max(newdensity, 0.0001), 0.1)), maxstep, float(i) / float(stepCount));
				if (newdensity > highestDensity) {
					highestDensity = newdensity;
					highestDensityDistance = traveledDistance;
				}
			} else {
				newStep = maxstep;
			}

			if (i == 0) {
				newdensity = mix(newdensity, 0.0, clamp(traveledDistance / maxstep, 0.0, 1.0));
			}

			density += newdensity;
			if (density >= 1.0) {
				break;
			}

			traveledDistance += newStep;
		}
	}

	density = clamp(density, 0.0, 1.0);
	// FIX: Replaced inverted smoothstep(maxstep * stepCount, minstep * stepCount, x)
	density *= clamp(
		1.0 - smoothstep(minstep * float(stepCount), maxstep * float(stepCount), traveledDistance),
		0.0,
		1.0
	);
	ambient = clamp(ambient / max(lightingSamples, 1.0), 0.0, 1.0);
	paintedColor = clamp(paintedColor / max(lightingSamples, 1.0), 0.0, 1.0);

	vec3 ambientLight = genericData.data.ambient_color.rgb * totalLightPower;
	ambientLight = mix(ambientLight, ambientLight * aobase.rgb, ambient * aobase.a) * paintedColor;

	lightColor.rgb += ambientLight * density;
	lightColor.a = density;

	if (any(isnan(lightColor)) || any(isinf(lightColor))) {
		lightColor = vec4(0.0);
	}

	float finalDensityDistance = min(traveledDistance, highestDensityDistance);
	float reprDist = (initialdistanceSample > 0.0) ? initialdistanceSample : traveledDistance;
	vec3 worldFinalPos = rayOrigin + rd_world * reprDist;

	vec4 reprojectedClipPos = genericData.data.prev_cam_view * vec4(worldFinalPos, 1.0);
	bool is_override = (reprojectedClipPos.z >= 0.0);

	vec4 reprojectedScreenPos = genericData.data.prev_cam_projection * reprojectedClipPos;
	vec2 reprojectedNdc = reprojectedScreenPos.xy / max(abs(reprojectedScreenPos.w), 0.00001);
	vec2 reprojectedUV = reprojectedNdc * 0.5 + 0.5;

	bool is_out_of_bounds = (
		reprojectedUV.x < 0.0 || reprojectedUV.x > 1.0 ||
		reprojectedUV.y < 0.0 || reprojectedUV.y > 1.0 ||
		any(isnan(reprojectedUV)) || any(isinf(reprojectedUV))
	);

	float accumdecay = genericData.data.lighting_and_accum.y;
	bool usingaccumA = (genericData.data.lighting_and_accum.z > 0.0);
	vec3 delta = rayOrigin - genericData.data.prev_cam_inv_view[3].xyz;
	float travelspeed = length(delta) + maxstep;

	vec4 currentColorAccumilation;
	vec4 currentDataAccumilation;
	sampleHistoryBilinear(clamp(reprojectedUV, vec2(0.0), vec2(1.0)), size, usingaccumA, currentColorAccumilation, currentDataAccumilation);

	float currentDepthBreak = float(depthBreak);
	bool historyCorrupted = (
		any(isnan(currentColorAccumilation)) || any(isinf(currentColorAccumilation)) ||
		any(isnan(currentDataAccumilation)) || any(isinf(currentDataAccumilation))
	);

	if (historyCorrupted || is_override || is_out_of_bounds || accumdecay <= 0.001 || (abs(currentDepthBreak - currentDataAccumilation.a) > 0.5 && abs(initialdistanceSample - currentDataAccumilation.r) > travelspeed * 0.5)) {
		currentColorAccumilation = lightColor;
		currentDataAccumilation.r = initialdistanceSample;
		currentDataAccumilation.g = traveledDistance;
		currentDataAccumilation.b = finalDensityDistance;
	} else {
		float EffectiveDecay = clamp(accumdecay, 0.0, 0.95);
		currentColorAccumilation = mix(lightColor, currentColorAccumilation, EffectiveDecay);
		currentDataAccumilation.r = mix(initialdistanceSample, currentDataAccumilation.r, EffectiveDecay);
		currentDataAccumilation.g = mix(traveledDistance, currentDataAccumilation.g, EffectiveDecay);
		currentDataAccumilation.b = mix(finalDensityDistance, currentDataAccumilation.b, EffectiveDecay);
	}
	currentDataAccumilation.a = currentDepthBreak;

	if (usingaccumA) {
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
