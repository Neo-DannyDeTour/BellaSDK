## Unit and regression tests verifying Portal performance hardening and Drone mouse capture.
class_name TestPortalAndDroneOptimizations
extends GutTest


## Restores default input mouse mode after each test.
func after_each() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Verifies StateMachineLock respects capture_mouse parameter for vehicles and remote machines.
func test_state_machine_lock_preserves_captured_mouse_mode() -> void:
	print("TestPortalAndDrone: Verifying StateMachineLock mouse mode handling.")
	var lock_state: StateMachineLock = StateMachineLock.new()
	add_child_autofree(lock_state)

	lock_state.enter({"capture_mouse": true})
	assert_true(
		bool(lock_state.get("_is_mouse_captured")),
		"_is_mouse_captured should be true when capture_mouse=true."
	)

	var motion_event: InputEventMouseMotion = InputEventMouseMotion.new()
	lock_state.handle_input(motion_event)
	assert_false(
		get_viewport().is_input_handled(),
		"Mouse motion should NOT be swallowed when capture_mouse=true."
	)

	lock_state.enter({"capture_mouse": false})
	assert_false(
		bool(lock_state.get("_is_mouse_captured")),
		"_is_mouse_captured should be false when capture_mouse=false."
	)

	lock_state.exit()
	assert_false(
		bool(lock_state.get("_is_mouse_captured")),
		"_is_mouse_captured should reset to false on state exit."
	)


## Verifies Portal SubViewport size clamping, far plane, and AABB thickness.
func test_portal_viewport_limits_and_far_plane() -> void:
	print("TestPortalAndDrone: Verifying Portal buffer limits and far plane.")
	var packed: PackedScene = load("res://interactables/portal.tscn") as PackedScene
	assert_not_null(packed, "Portal scene must load.")

	var portal_instance: Node = packed.instantiate()
	var portal: Portal = portal_instance as Portal
	add_child_autofree(portal)

	assert_eq(portal.cull_far, 35.0, "Portal cull_far must default to 35.0m.")
	assert_eq(
		portal.max_viewport_size,
		Vector2i(512, 512),
		"Portal max_viewport_size must clamp to 512x512."
	)

	var notifier: VisibleOnScreenNotifier3D = (
		portal.get_node_or_null("PortalVisibilityNotifier") as VisibleOnScreenNotifier3D
	)
	assert_not_null(notifier, "Screen notifier must exist on Portal.")
	assert_true(
		notifier.aabb.size.z >= 0.4,
		"Screen notifier AABB must have 3D thickness to prevent edge flutter."
	)

	var sub_vp: SubViewport = portal.get_node_or_null("PortalSubViewport") as SubViewport
	assert_not_null(sub_vp, "PortalSubViewport must exist.")
	assert_true(
		sub_vp.size.x <= 512 and sub_vp.size.y <= 512,
		"Portal SubViewport size must be clamped within max_viewport_size."
	)


## Verifies RainController reuses existing HeightfieldCollision without creating duplicates.
func test_rain_controller_reuses_heightfield() -> void:
	print("TestPortalAndDrone: Verifying RainController single heightfield invariant.")
	var packed: PackedScene = load("res://environment/rain_controller.tscn") as PackedScene
	assert_not_null(packed, "RainController scene must load.")

	var rain: Node = packed.instantiate()
	add_child_autofree(rain)

	var heightfields: Array[Node] = rain.find_children(
		"*", "GPUParticlesCollisionHeightField3D", true, false
	)
	assert_eq(
		heightfields.size(),
		1,
		"RainController must only contain exactly 1 GPUParticlesCollisionHeightField3D."
	)
