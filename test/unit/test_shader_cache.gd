## A GUT test script for the [ShaderCache] class validating precompilation resources.
class_name TestShaderCache
extends GutTest

## The identifier name for this test suite run.
var test_name: String = "Test ShaderCache"


## Verifies that initialize runs cleanly and retains preconfigured materials.
func test_initialize() -> void:
	print("Testing ShaderCache.initialize()...")
	var shader_cache: ShaderCache = ShaderCache.new()
	var mock_mat: StandardMaterial3D = StandardMaterial3D.new()
	shader_cache.materials.append(mock_mat)

	shader_cache.initialize()
	assert_eq(shader_cache.materials.size(), 1, "Cache should contain the added material")
