## GUT unit tests for [NpcActor] and [godiva.tscn] animations, look-at, and event hooks.
extends GutTest

## Preloaded playable Godiva NPC scene at 1.64m player scale.
const GODIVA_SCENE: PackedScene = preload("res://npcs/godiva/godiva.tscn")
## Preloaded [EventSequenceTrigger] script for event dispatcher integration tests.
const EVENT_TRIGGER_SCRIPT: GDScript = preload(
	"res://addons/detour_event_sequencer/event_sequence_trigger.gd"
)
## Preloaded [EventStep] resource script for sequence step construction.
const EVENT_STEP_SCRIPT: GDScript = preload("res://addons/detour_event_sequencer/event_step.gd")

## Active Godiva actor instance created per test.
var _godiva: NpcActor = null


## Instantiates a fresh [NpcActor] inside the scene tree before each test.
func before_each() -> void:
	var inst: Node = GODIVA_SCENE.instantiate()
	assert_true(inst is NpcActor, "godiva.tscn root must be NpcActor.")
	_godiva = inst as NpcActor
	add_child_autofree(_godiva)


## Verifies Godiva height matches 1.64m player scale and SkeletonProfileHumanoid bones exist.
func test_godiva_scale_and_humanoid_skeleton() -> void:
	var shape_node: CollisionShape3D = (
		_godiva.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	)
	assert_not_null(shape_node, "Godiva must have CollisionShape3D.")
	assert_true(shape_node.shape is CapsuleShape3D, "Collision shape must be CapsuleShape3D.")
	var capsule: CapsuleShape3D = shape_node.shape as CapsuleShape3D
	assert_almost_eq(capsule.height, 1.64, 0.005, "Godiva height must match 1.64m player.")

	var skel: Skeleton3D = _godiva.get_skeleton()
	assert_not_null(skel, "Skeleton3D must exist.")
	for bone_name: String in [
		"Hips",
		"Spine",
		"Chest",
		"UpperChest",
		"Neck",
		"Head",
		"LeftUpperArm",
		"RightUpperArm",
		"LeftUpperLeg",
		"RightUpperLeg",
	]:
		assert_gte(skel.find_bone(bone_name), 0, "Missing humanoid bone: " + bone_name)

	var head_idx: int = skel.find_bone("Head")
	var head_pos: Vector3 = skel.get_bone_global_rest(head_idx).origin
	assert_true(head_pos.y > 1.30 and head_pos.y < 1.50, "Head bone height must fit 1.64m scale.")


## Verifies AnimationTree evaluates real bone poses for idle, a_pose, t_pose, and air_hump.
func test_animation_tree_idle_and_air_hump() -> void:
	assert_eq(_godiva.get_current_animation(), &"idle", "Default clip should be idle.")
	var tree: AnimationTree = _godiva.get_animation_tree()
	assert_not_null(tree, "AnimationTree must be created.")
	assert_true(tree.active, "AnimationTree must be active immediately on _ready().")

	var skel: Skeleton3D = _godiva.get_skeleton()
	var arm_idx: int = skel.find_bone("LeftUpperArm")
	var rest_rot: Quaternion = skel.get_bone_rest(arm_idx).basis.get_rotation_quaternion()

	for f_idle: int in range(15):
		tree.advance(1.0 / 60.0)
		assert_gte(f_idle, 0)
	var idle_rot: Quaternion = skel.get_bone_pose_rotation(arm_idx)
	assert_gt(
		idle_rot.angle_to(rest_rot), 0.30, "Idle must actively move arms down out of rest A-pose."
	)

	_godiva.play_animation("a_pose")
	for f_apose: int in range(25):
		tree.advance(1.0 / 60.0)
		assert_gte(f_apose, 0)
	var apose_rot: Quaternion = skel.get_bone_pose_rotation(arm_idx)
	assert_lt(apose_rot.angle_to(rest_rot), 0.08, "a_pose clip must match rest A-pose.")

	_godiva.play_animation("t_pose")
	for f_tpose: int in range(25):
		tree.advance(1.0 / 60.0)
		assert_gte(f_tpose, 0)
	var tpose_rot: Quaternion = skel.get_bone_pose_rotation(arm_idx)
	assert_gt(tpose_rot.angle_to(rest_rot), 0.30, "t_pose clip must raise arms away from A-pose.")
	assert_gt(
		tpose_rot.angle_to(idle_rot), 0.80, "t_pose must be clearly distinct from relaxed idle."
	)

	watch_signals(_godiva)
	_godiva.play_animation("air_hump")
	assert_eq(_godiva.get_current_animation(), &"air_hump", "Current clip should be air_hump.")
	assert_signal_emitted_with_parameters(_godiva, "animation_started", [&"air_hump"])

	_godiva.play_animation("booty_slap")
	for f_slap: int in range(20):
		tree.advance(1.0 / 60.0)
		assert_gte(f_slap, 0)
	assert_eq(_godiva.get_current_animation(), &"booty_slap", "Current clip should be booty_slap.")
	var slap_rot: Quaternion = skel.get_bone_pose_rotation(arm_idx)
	assert_gt(
		slap_rot.angle_to(rest_rot), 0.25, "booty_slap must actively animate arms out of rest pose."
	)

	_godiva.stop_animation()
	assert_eq(_godiva.get_current_animation(), &"idle", "stop_animation should return to idle.")
	assert_signal_emitted_with_parameters(_godiva, "animation_completed", [&"booty_slap"])


## Verifies EventSequenceTrigger CALL_METHOD drives Godiva animations cleanly.
func test_event_sequence_trigger_integration() -> void:
	var container: Node3D = Node3D.new()
	add_child_autofree(container)

	var actor: NpcActor = GODIVA_SCENE.instantiate() as NpcActor
	actor.name = "GodivaTarget"
	container.add_child(actor)

	var trigger: Area3D = EVENT_TRIGGER_SCRIPT.new() as Area3D
	trigger.name = "AnimTrigger"
	container.add_child(trigger)

	var step: EventStep = EVENT_STEP_SCRIPT.new() as EventStep
	step.step_type = EventStep.StepType.CALL_METHOD
	step.exec_mode = EventStep.ExecMode.SEQUENTIAL
	step.target_path = trigger.get_path_to(actor)
	step.method_name = &"play_animation"
	step.parameter = "air_hump"

	var steps_arr: Array[EventStep] = [step]
	trigger.set(&"steps", steps_arr)
	trigger.call(&"trigger_sequence", null)
	await get_tree().process_frame

	assert_eq(
		actor.get_current_animation(),
		&"air_hump",
		"EventSequenceTrigger CALL_METHOD must trigger air_hump."
	)


## Verifies global Events.level_event_triggered starts and stops mapped Godiva animations.
func test_global_events_dispatcher_mapping() -> void:
	Events.level_event_triggered.emit("godiva_air_hump", true)
	assert_eq(
		_godiva.get_current_animation(),
		&"air_hump",
		"Events.level_event_triggered(true) should start mapped clip."
	)

	Events.level_event_triggered.emit("godiva_air_hump", false)
	assert_eq(
		_godiva.get_current_animation(),
		&"idle",
		"Events.level_event_triggered(false) should stop mapped clip."
	)

	Events.level_event_triggered.emit("godiva_booty_slap", true)
	assert_eq(
		_godiva.get_current_animation(),
		&"booty_slap",
		"Events.level_event_triggered(true) should start booty_slap."
	)

	Events.level_event_triggered.emit("godiva_booty_slap", false)
	assert_eq(
		_godiva.get_current_animation(),
		&"idle",
		"Events.level_event_triggered(false) should stop booty_slap."
	)


## Verifies stacked LookAtModifier3D setup and real-time behind-angle body yaw tracking.
func test_look_at_modifiers_and_body_turn() -> void:
	var mods: Array[LookAtModifier3D] = _godiva.get_look_modifiers()
	assert_eq(mods.size(), 2, "NpcActor should attach ChestLookAt and HeadLookAt modifiers.")
	for mod: LookAtModifier3D in mods:
		assert_eq(
			mod.forward_axis,
			SkeletonModifier3D.BONE_AXIS_PLUS_Z,
			"LookAtModifier3D must use +Z forward axis."
		)
		assert_true(mod.use_angle_limitation, "Angle clamp must be enabled on look modifiers.")

	var target: Marker3D = Marker3D.new()
	add_child_autofree(target)
	# Place target behind-left of Godiva (-X, +Z while Godiva faces -Z) -> triggers turn_left
	target.global_position = Vector3(-1.5, 1.48, 2.5)
	_godiva.set_look_target(target)
	_godiva._on_screen_entered()

	var initial_yaw: float = _godiva.global_rotation.y
	var saw_turn_clip: bool = false
	for i: int in range(180):
		_godiva._process(1.0 / 60.0)
		_godiva.get_animation_tree().advance(1.0 / 60.0)
		var cur_clip: StringName = _godiva.get_current_animation()
		if cur_clip == &"turn_left" or cur_clip == &"turn_right":
			saw_turn_clip = true
		var unused_step: int = i
		assert_gte(unused_step, 0)

	var yaw_delta: float = absf(angle_difference(initial_yaw, _godiva.global_rotation.y))
	assert_gt(yaw_delta, 1.0, "Godiva body yaw must turn toward behind-angle target.")
	assert_true(saw_turn_clip, "Turning around must play stepping turn_left/turn_right animation.")
	assert_eq(
		_godiva.get_current_animation(),
		&"idle",
		"Once aligned with target, Godiva must return cleanly to idle."
	)


## Verifies VisibleOnScreenNotifier3D off-screen callback disables per-frame updates.
func test_offscreen_visibility_gating() -> void:
	_godiva._on_screen_entered()
	assert_true(_godiva.is_processing(), "On-screen look-at actor should process.")

	_godiva._on_screen_exited()
	assert_false(_godiva.is_processing(), "Off-screen actor must disable _process().")
	assert_false(_godiva.get_animation_tree().active, "Off-screen AnimationTree must sleep.")
