## Example GUT test suite.
##
## This is a template unit test suite used to demonstrate basic assertions
## within the [GutTest] framework.
class_name TestExample
extends GutTest


## Demonstrates a passing mathematical assertion.
func test_passes() -> void:
	print("TestExample: Executing test_passes() basic equality check.")
	assert_eq(1, 1)


## Demonstrates a passing string equality assertion.
func test_fails() -> void:
	print("TestExample: Executing test_fails() basic string match check.")
	assert_eq("hello", "hello")
