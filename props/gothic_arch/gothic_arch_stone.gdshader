shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_texture : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float normal_scale : hint_range(0.0, 2.0) = 1.0;
uniform vec3 moss_color : source_color = vec3(0.18, 0.24, 0.14);
uniform float moss_sharpness : hint_range(1.0, 10.0) = 4.0;

instance uniform vec3 instance_tint : source_color = vec3(1.0, 1.0, 1.0);
instance uniform float wear_intensity : hint_range(0.0, 1.0) = 0.25;
instance uniform float moss_coverage : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_normal;

void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 base_albedo = texture(albedo_texture, UV).rgb * instance_tint;
	vec3 orm = texture(orm_texture, UV).rgb;
	vec3 normal_map = texture(normal_texture, UV).rgb;

	float cavity_mask = 1.0 - orm.r;
	vec3 worn_albedo = mix(base_albedo, base_albedo * 0.45, cavity_mask * wear_intensity);

	vec3 norm = normalize(world_normal);
	float up_mask = clamp(norm.y, 0.0, 1.0);
	float moss_mask = clamp(pow(up_mask, moss_sharpness) * moss_coverage * orm.r, 0.0, 1.0);

	ALBEDO = mix(worn_albedo, moss_color, moss_mask);
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.7;
	ROUGHNESS = mix(orm.g, 0.92, moss_mask);
	METALLIC = orm.b;
	NORMAL_MAP = normal_map;
	NORMAL_MAP_DEPTH = normal_scale;
}
