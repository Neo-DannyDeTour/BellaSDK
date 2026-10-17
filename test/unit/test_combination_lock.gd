## Unit test suite validating CombinationLock secret code formatting and code verification.
extends GutTest

const COMBINATION_LOCK_SCRIPT: GDScript = preload("res://interactables/combination_lock.gd")

## CombinationLock Node3D instance under test.
var _lock: Node3D


## Instantiates a clean CombinationLock node before each test run.
func before_each() -> void:
	print("Setting up CombinationLock instance for testing.")
	_lock = COMBINATION_LOCK_SCRIPT.new() as Node3D
	add_child_autofree(_lock)


## Cleans up CombinationLock instance after test execution.
func after_each() -> void:
	print("Tearing down CombinationLock test instance.")
	_lock = null


## Verifies that secret code is truncated to 3 characters and converted to uppercase.
func test_secret_code_formatting_on_ready() -> void:
	print("Testing CombinationLock secret code formatting on ready.")
	_lock.set("secret_code", "abcde")
	_lock.call("_ready")

	var formatted_code: String = _lock.get("secret_code") as String
	assert_eq(
		formatted_code,
		"ABC",
		"Secret code should be truncated to 3 characters and converted to upper case."
	)


## Verifies code submission evaluation for correct secret code.
func test_code_submitted_correct() -> void:
	print("Testing CombinationLock submission with matching code.")
	_lock.set("secret_code", "789")
	_lock.call("_ready")

	_lock.call("_on_code_submitted", "789")
	assert_true(true, "Correct code submitted executed cleanly.")


## Verifies code submission evaluation for incorrect code.
func test_code_submitted_incorrect() -> void:
	print("Testing CombinationLock submission with incorrect code.")
	_lock.set("secret_code", "789")
	_lock.call("_ready")

	_lock.call("_on_code_submitted", "000")
	assert_true(true, "Incorrect code submitted executed cleanly without error.")
