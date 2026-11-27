## Unit tests for [OceanClouds] canopy scene, uniforms, sun sync, and camera following.
extends GutTest

## Preloaded ocean clouds scene under test.
const OCEAN_CLOUDS_SCENE: PackedScene = preload("res://environment/ocean_clouds/ocean_clouds.tscn")


## Verifies scene instantiation, volumetric render layer, and uniform updates via exports.
func test_instantiation_and_export_uniforms() -> void:
	var clouds: OceanClouds = OCEAN_CLOUDS_SCENE.instantiate() as OceanClouds
	assert_not_null(clouds, "OceanClouds scene should instantiate as OceanClouds.")
	add_child_autofree(clouds)

	var mesh_node: MeshInstance3D = clouds.get_node("CloudMesh") as MeshInstance3D
	assert_not_null(mesh_node, "CloudMesh child must exist.")
	assert_eq(
		mesh_node.layers,
		CollisionLayers.RENDER_MASK_VOLUMETRICS,
		"CloudMesh should render on Layer 10 (Volumetrics)."
	)

	var mat: ShaderMaterial = mesh_node.material_override as ShaderMaterial
	assert_not_null(mat, "CloudMesh must have a ShaderMaterial override.")

	clouds.wind_speed = 42.0
	clouds.cloud_coverage = 0.75
	clouds.canopy_radius = 2400.0

	var speed_raw: Variant = mat.get_shader_parameter(OceanClouds.PARAM_WIND_SPEED)
	var speed_val: float = speed_raw if speed_raw is float else -1.0
	assert_almost_eq(speed_val, 42.0, 0.001)

	var cov_raw: Variant = mat.get_shader_parameter(OceanClouds.PARAM_CLOUD_COVERAGE)
	var cov_val: float = cov_raw if cov_raw is float else -1.0
	assert_almost_eq(cov_val, 0.75, 0.001)

	var plane: PlaneMesh = mesh_node.mesh as PlaneMesh
	assert_not_null(plane)
	assert_eq(plane.size, Vector2(4800.0, 4800.0))


## Verifies sun direction and color sync from an assigned [DirectionalLight3D].
func test_sync_sun_light_updates_shader() -> void:
	var clouds: OceanClouds = OCEAN_CLOUDS_SCENE.instantiate() as OceanClouds
	add_child_autofree(clouds)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.7, 0.4, 1.0)
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	add_child_autofree(sun)

	clouds.sun_light = sun
	var mesh_node: MeshInstance3D = clouds.get_node("CloudMesh") as MeshInstance3D
	var mat: ShaderMaterial = mesh_node.material_override as ShaderMaterial

	var color_raw: Variant = mat.get_shader_parameter(OceanClouds.PARAM_SUN_COLOR)
	var synced_color: Color = color_raw if color_raw is Color else Color.BLACK
	assert_eq(synced_color, sun.light_color)

	var dir_raw: Variant = mat.get_shader_parameter(OceanClouds.PARAM_SUN_DIRECTION)
	var synced_dir: Vector3 = dir_raw if dir_raw is Vector3 else Vector3.ZERO
	var expected_dir: Vector3 = sun.global_basis.z.normalized()
	assert_almost_eq(synced_dir.distance_to(expected_dir), 0.0, 0.001)


## Verifies camera XZ following preserves Y altitude and gates process when disabled.
func test_follow_camera_xz_preserves_altitude() -> void:
	var clouds: OceanClouds = OCEAN_CLOUDS_SCENE.instantiate() as OceanClouds
	clouds.position = Vector3(0.0, 95.0, 0.0)
	add_child_autofree(clouds)

	var cam: Camera3D = Camera3D.new()
	cam.position = Vector3(120.0, 12.0, -85.0)
	add_child_autofree(cam)
	cam.make_current()

	clouds._process(0.016)
	assert_almost_eq(clouds.global_position.x, 120.0, 0.01)
	assert_almost_eq(clouds.global_position.y, 95.0, 0.01)
	assert_almost_eq(clouds.global_position.z, -85.0, 0.01)

	clouds.follow_camera_xz = false
	assert_false(clouds.is_processing(), "Process must disable when follow_camera_xz is false.")
