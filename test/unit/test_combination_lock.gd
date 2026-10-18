## Unit tests for CombinationLock puzzle interactable.
class_name TestCombinationLock
extends GutTest

## Target combination lock instance being tested.
var _lock: CombinationLock = null


## Sets up clean CombinationLock test instance.
func before_each() -> void:
	print("TestCombinationLock: before_each() setup started.")
	_lock = CombinationLock.new()
	_lock.secret_code = "4567"
	add_child_autofree(_lock)


## Tears down test references.
func after_each() -> void:
	print("TestCombinationLock: after_each() cleanup.")
	_lock = null


## Verifies that secret code is clamped to 3 characters and converted to uppercase on ready.
func test_secret_code_formatting() -> void:
	print("TestCombinationLock: test_secret_code_formatting() called.")
	_lock.secret_code = "abc12"
	_lock._ready()
	assert_eq(_lock.secret_code, "ABC", "Secret code should be trimmed to 3 uppercase characters.")


## Verifies submitting code matching secret code triggers lock resolution.
func test_code_submission_correct() -> void:
	print("TestCombinationLock: test_code_submission_correct() called.")
	_lock.secret_code = "789"
	_lock._ready()

	_lock._on_code_submitted("789")
	assert_true(
		_lock.is_queued_for_deletion(),
		"Lock should be queued for deletion upon correct code submission."
	)


## Verifies submitting incorrect code keeps lock active.
func test_code_submission_incorrect() -> void:
	print("TestCombinationLock: test_code_submission_incorrect() called.")
	_lock.secret_code = "789"
	_lock._ready()

	_lock._on_code_submitted("111")
	assert_false(
		_lock.is_queued_for_deletion(),
		"Lock should remain active when incorrect code is submitted."
	)
