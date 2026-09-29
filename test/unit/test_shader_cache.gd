extends GutTest

## A GUT test script for the [ShaderCache] class validating precompilation resources.
var test_name: String = "Test ShaderCache"


func test_initialize() -> void:
	print("Testing ShaderCache.initialize()...")
	var shader_cache: ShaderCache = load("res://core/shader_cache.gd").new()
	var mock_mat: StandardMaterial3D = StandardMaterial3D.new()
	shader_cache.materials.append(mock_mat)

	# Since initialize() just prints, we can only verify the materials array wasn't altered
	shader_cache.initialize()
	assert_eq(shader_cache.materials.size(), 1, "Cache should contain the added material")
