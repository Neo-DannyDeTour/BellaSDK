## Unit tests for [MannequinAttractorTrigger3D] and [TargetArrivalBox3D].
extends GutTest

const MANNEQUIN_SCENE: PackedScene = preload("res://interactables/mannequin_ragdoll.tscn")
const ATTRACTOR_SCENE: PackedScene = preload("res://triggers/mannequin_attractor_trigger.tscn")
const ARRIVAL_SCENE: PackedScene = preload("res://triggers/target_arrival_box_3d.tscn")


## Tests [TargetArrivalBox3D] containment testing and center computation.
func test_target_arrival_box_containment() -> void:
	var box: TargetArrivalBox3D = ARRIVAL_SCENE.instantiate() as TargetArrivalBox3D
	add_child_autofree(box)
	box.global_position = Vector3(10.0, 5.0, -10.0)
	box.trigger_size = Vector3(4.0, 4.0, 4.0)
	box.trigger_offset = Vector3(0.0, 1.0, 0.0)

	var center: Vector3 = box.get_target_center()
	assert_eq(center, Vector3(10.0, 6.0, -10.0), "Center must offset correctly in world space.")

	assert_true(
		box.contains_point(Vector3(10.0, 6.0, -10.0)), "Center point must be inside arrival box."
	)
	assert_true(
		box.contains_point(Vector3(11.5, 6.5, -10.5)),
		"Point within 4x4x4 extents must be contained."
	)
	assert_false(
		box.contains_point(Vector3(10.0, 9.0, -10.0)),
		"Point outside vertical extent must not be contained."
	)


## Tests [MannequinAttractorTrigger3D] bone presets and dynamic bone list updates.
func test_attractor_preset_switching() -> void:
	var attractor: MannequinAttractorTrigger3D = (
		ATTRACTOR_SCENE.instantiate() as MannequinAttractorTrigger3D
	)
	add_child_autofree(attractor)

	attractor.bone_preset = MannequinAttractorTrigger3D.BonePreset.HEAD
	assert_eq(
		attractor.target_bones, [&"Head"], "HEAD preset must populate target_bones with Head."
	)

	attractor.bone_preset = MannequinAttractorTrigger3D.BonePreset.ARMS
	assert_true(attractor.target_bones.has(&"Hand.L"), "ARMS preset must contain Hand.L.")
	assert_true(attractor.target_bones.has(&"Hand.R"), "ARMS preset must contain Hand.R.")

	attractor.bone_preset = MannequinAttractorTrigger3D.BonePreset.ALL
	assert_eq(attractor.target_bones.size(), 17, "ALL preset must select all 17 physical bones.")


## Tests sequence activation, ragdoll wake-up, and graceful completion.
func test_attractor_sequence_flow() -> void:
	var ragdoll: MannequinRagdoll = MANNEQUIN_SCENE.instantiate() as MannequinRagdoll
	add_child_autofree(ragdoll)

	var destination: TargetArrivalBox3D = ARRIVAL_SCENE.instantiate() as TargetArrivalBox3D
	add_child_autofree(destination)
	destination.global_position = Vector3(0.0, 2.0, -5.0)

	var attractor: MannequinAttractorTrigger3D = (
		ATTRACTOR_SCENE.instantiate() as MannequinAttractorTrigger3D
	)
	add_child_autofree(attractor)
	attractor.target_mannequin = ragdoll
	attractor.target_destination = destination
	var custom_bones: Array[StringName] = [&"Chest"]
	attractor.target_bones = custom_bones
	attractor.pull_speed = 10.0

	assert_false(
		attractor.is_physics_processing(), "Attractor must start with physics process disabled."
	)
	assert_false(ragdoll.is_ragdoll_active, "Ragdoll must start inactive.")

	watch_signals(attractor)
	attractor.start_sequence()
	await get_tree().process_frame

	assert_true(attractor.is_active, "Attractor must be marked active.")
	assert_true(
		attractor.is_physics_processing(), "Physics process must be enabled during active sequence."
	)
	assert_true(ragdoll.is_ragdoll_active, "Ragdoll must be activated upon sequence start.")
	assert_signal_emitted(attractor, "sequence_started")

	attractor.stop_sequence()
	assert_false(attractor.is_active, "Attractor must be inactive after stop.")
	assert_false(attractor.is_physics_processing(), "Physics process must be disabled after stop.")
	assert_signal_emitted(attractor, "sequence_completed")
