extends GutTest


func test_passes() -> void:
	print("Running test_passes")
	assert_eq(1, 1)


func test_fails() -> void:
	print("Running test_fails")
	assert_eq("hello", "hello")
