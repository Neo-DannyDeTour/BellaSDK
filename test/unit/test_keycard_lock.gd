## Unit test suite validating KeycardLock clearance checking and signal interactions.
extends GutTest

const KEYCARD_LOCK_SCRIPT: GDScript = preload("res://interactables/keycard_lock.gd")

## KeycardLock instance under test.
var _lock: KeycardLock

## Status label instance attached to lock.
var _label: Label3D


## Instantiates a clean KeycardLock node before each test.
func before_each() -> void:
	print("Setting up KeycardLock instance for testing.")
	_lock = KEYCARD_LOCK_SCRIPT.new() as KeycardLock
	_label = Label3D.new()
	_lock.status_label = _label
	_lock.add_child(_label)
	add_child_autofree(_lock)


## Cleans up KeycardLock instance after test execution.
func after_each() -> void:
	print("Tearing down KeycardLock test instance.")
	_lock = null
	_label = null


## Verifies default lock required card ID configuration.
func test_default_required_card_id() -> void:
	print("Testing default required_card_id on KeycardLock.")
	assert_eq(_lock.required_card_id, &"R", "Default required_card_id should be 'R'.")


## Verifies focused event updates label text to requirement string.
func test_on_focused_updates_label() -> void:
	print("Testing KeycardLock _on_focused label update.")
	_lock.required_card_id = &"A1"
	_lock.call("_ready")
	_lock.call("_on_focused")

	assert_eq(
		_label.text,
		"LOCKED - requires A1 card",
		"Focusing lock should update status label with requirement text."
	)


## Verifies unfocused event clears status label text.
func test_on_unfocused_clears_label() -> void:
	print("Testing KeycardLock _on_unfocused label clearing.")
	_lock.required_card_id = &"A1"
	_lock.call("_ready")
	_lock.call("_on_focused")
	_lock.call("_on_unfocused")

	assert_eq(_label.text, "", "Unfocusing lock should clear status label text.")


## Verifies interaction without clearance triggers access denied.
func test_interacted_without_card_denies_access() -> void:
	print("Testing KeycardLock interaction without required keycard.")
	_lock.required_card_id = &"AdminCard"
	_lock.call("_ready")
	var dummy_player: CharacterBody3D = CharacterBody3D.new()
	add_child_autofree(dummy_player)

	_lock.call("_on_interacted", dummy_player)

	assert_eq(_label.text, "DENIED", "Interaction without card should set status label to DENIED.")


## Verifies interaction with clearance grants access and emits signal.
func test_interacted_with_card_grants_access() -> void:
	print("Testing KeycardLock interaction with required keycard.")
	_lock.required_card_id = &"SecurityAlpha"
	_lock.call("_ready")
	watch_signals(_lock)

	KeycardSystem.grant_card(&"SecurityAlpha")
	var dummy_player: CharacterBody3D = CharacterBody3D.new()
	add_child_autofree(dummy_player)

	_lock.call("_on_interacted", dummy_player)

	assert_signal_emitted(_lock, "access_granted", "Access granted signal should be emitted.")
	assert_eq(_label.text, "GRANTED", "Status label should display GRANTED upon successful unlock.")
