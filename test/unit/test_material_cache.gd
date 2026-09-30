extends GutTest

## A GUT test script for the [MaterialCache] class validating shader caching logic.
var test_name: String = "Test MaterialCache"


func before_each() -> void:
	print("Clearing MaterialCache before test...")
	MaterialCache.clear_cache()


func test_get_instance() -> void:
	print("Testing MaterialCache.get_instance()...")
	var mock_mat: StandardMaterial3D = StandardMaterial3D.new()
	var inst1: Material = MaterialCache.get_instance(mock_mat)
	assert_not_null(inst1, "Should create a cached instance")
	assert_ne(inst1, mock_mat, "Cached instance should be a duplicate of original")

	var inst2: Material = MaterialCache.get_instance(mock_mat)
	assert_eq(inst1, inst2, "Subsequent calls should return the same cached instance")


func test_get_instance_null() -> void:
	print("Testing MaterialCache.get_instance() with null...")
	var inst: Material = MaterialCache.get_instance(null)
	assert_null(inst, "Null input should return null")


func test_clear_cache() -> void:
	print("Testing MaterialCache.clear_cache()...")
	var mock_mat: StandardMaterial3D = StandardMaterial3D.new()
	var inst1: Material = MaterialCache.get_instance(mock_mat)

	MaterialCache.clear_cache()

	var inst2: Material = MaterialCache.get_instance(mock_mat)
	assert_ne(inst1, inst2, "After clearing cache, a new instance should be created")
