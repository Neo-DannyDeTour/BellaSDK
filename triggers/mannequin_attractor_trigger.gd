@tool
## Trigger area initiating a sequenced attraction force dragging mannequin bones to a target.
## Inherits [BaseTriggerArea3D] for editor visualizer synchronization and player detection.
class_name MannequinAttractorTrigger3D
extends BaseTriggerArea3D

## Emitted when the ragdoll attraction sequence commences.
signal sequence_started

## Emitted when all targeted physical bones reach the destination volume or timeout occurs.
signal sequence_completed

## Emitted when a specific targeted physical bone enters the arrival destination.
signal bone_arrived(bone_name: StringName)

## Predefined anatomical bone selections for rapid configuration.
enum BonePreset {
	CUSTOM,
	TORSO,
	ARMS,
	LEGS,
	HEAD,
	ALL,
}

## Torso bone group identifiers.
const PRESET_TORSO_BONES: Array[StringName] = [&"Chest", &"Pelvis"]
## Arm bone group identifiers.
const PRESET_ARM_BONES: Array[StringName] = [
	&"Hand.L",
	&"Hand.R",
	&"LowerArm.L",
	&"LowerArm.R",
]
## Leg bone group identifiers.
const PRESET_LEG_BONES: Array[StringName] = [
	&"Foot.L",
	&"Foot.R",
	&"LowerLeg.L",
	&"LowerLeg.R",
]
## Head bone group identifiers.
const PRESET_HEAD_BONES: Array[StringName] = [&"Head"]
## Full skeleton articulated physical bone identifiers.
const PRESET_ALL_BONES: Array[StringName] = [
	&"Pelvis",
	&"Waist",
	&"Chest",
	&"Neck",
	&"Head",
	&"UpperArm.L",
	&"LowerArm.L",
	&"Hand.L",
	&"UpperArm.R",
	&"LowerArm.R",
	&"Hand.R",
	&"UpperLeg.L",
	&"LowerLeg.L",
	&"Foot.L",
	&"UpperLeg.R",
	&"LowerLeg.R",
	&"Foot.R",
]

@export_category("Attractor Targets")
## The target articulated mannequin ragdoll prop to pull.
@export var target_mannequin: MannequinRagdoll

## The destination arrival volume or marker where bones are drawn.
@export var target_destination: Node3D

## Spherical distance threshold in meters when [member target_destination] is a generic [Node3D].
@export var arrival_radius: float = 0.8

@export_category("Bone Selection")
## Anatomical preset for quickly populating [member target_bones].
@export var bone_preset: BonePreset = BonePreset.TORSO:
	set(value):
		bone_preset = value
		_apply_preset(value)

## List of [StringName] physical bone names attracted toward the destination.
@export var target_bones: Array[StringName] = [&"Chest", &"Pelvis"]

@export_category("Attraction Dynamics")
## Target linear velocity in meters per second applied to each chosen bone.
@export var pull_speed: float = 8.0

## Responsiveness multiplier scaling the corrective PD spring force.
@export var spring_gain: float = 14.0

## Upper clamp in Newtons preventing physics instability or explosive impulses.
@export var max_force: float = 650.0

## Maximum duration in seconds before automatically halting the sequence. 0 disables timeout.
@export var max_duration: float = 10.0

## Initiates attraction sequence immediately on entering scene tree if enabled.
@export var auto_start: bool = false

## Tracks whether the physics pull sequence is currently executing.
var is_active: bool = false

## Elapsed seconds since sequence activation.
var _elapsed_time: float = 0.0

## Set of targeted physical bones that have not yet arrived at the destination.
var _pending_bones: Array[StringName] = []


## Initializes visualizer styling and disables per-frame physics process until triggered.
func _ready() -> void:
	if trigger_text == "TRIGGER":
		trigger_text = "ATTRACTOR"
	if trigger_color == Color(0.9, 0.5, 0.1, 0.25):
		trigger_color = Color(0.85, 0.15, 0.8, 0.25)
	if outline_color == Color(1.0, 0.8, 0.3, 0.9):
		outline_color = Color(0.95, 0.3, 0.9, 0.9)

	super._ready()

	if Engine.is_editor_hint():
		return

	set_physics_process(false)

	if auto_start:
		start_sequence.call_deferred()


## Drives continuous physics attraction force towards destination on each physics tick.
func _physics_process(delta: float) -> void:
	if not is_active:
		set_physics_process(false)
		return

	_elapsed_time += delta
	if max_duration > 0.0 and _elapsed_time >= max_duration:
		print("MannequinAttractorTrigger3D: Sequence timed out after ", _elapsed_time, "s.")
		stop_sequence()
		return

	if not is_instance_valid(target_mannequin) or not is_instance_valid(target_destination):
		print("MannequinAttractorTrigger3D: Target or destination missing. Aborting sequence.")
		stop_sequence()
		return

	var dest_center: Vector3 = _resolve_destination_center()

	for i: int in range(_pending_bones.size() - 1, -1, -1):
		var bone_name: StringName = _pending_bones[i]
		var phys_bone: PhysicalBone3D = target_mannequin.get_physical_bone(bone_name)
		if not is_instance_valid(phys_bone):
			_pending_bones.remove_at(i)
			continue

		if _has_bone_arrived(phys_bone.global_position, dest_center):
			_pending_bones.remove_at(i)
			bone_arrived.emit(bone_name)
			print("MannequinAttractorTrigger3D: Bone arrived at destination: ", bone_name)
			continue

		_apply_bone_spring_force(phys_bone, dest_center, delta)

	if _pending_bones.is_empty():
		print("MannequinAttractorTrigger3D: All target bones arrived at destination volume.")
		stop_sequence()


## Starts the ragdoll attraction sequence, waking mannequin simulation and enabling physics.
func start_sequence() -> void:
	if is_active:
		return

	if not is_instance_valid(target_mannequin):
		push_warning("MannequinAttractorTrigger3D: Cannot start sequence - target_mannequin null.")
		return
	if not is_instance_valid(target_destination):
		push_warning("MannequinAttractorTrigger3D: Cannot start - target_destination null.")
		return

	if not target_mannequin.is_ragdoll_active:
		target_mannequin.activate_ragdoll()

	_elapsed_time = 0.0
	_pending_bones.clear()
	for bone_name: StringName in target_bones:
		if not _pending_bones.has(bone_name):
			_pending_bones.append(bone_name)

	if _pending_bones.is_empty():
		push_warning("MannequinAttractorTrigger3D: target_bones is empty. Aborting start.")
		return

	is_active = true
	set_physics_process(true)
	sequence_started.emit()
	print(
		"MannequinAttractorTrigger3D: Sequence started. Attracting bones: ",
		_pending_bones,
		" at speed ",
		pull_speed
	)


## Stops attraction forces and allows the mannequin ragdoll to settle naturally.
func stop_sequence() -> void:
	if not is_active:
		return

	is_active = false
	set_physics_process(false)
	_pending_bones.clear()
	sequence_completed.emit()
	print("MannequinAttractorTrigger3D: Sequence completed.")


## Callback triggered by [BaseTriggerArea3D] when the player character enters this volume.
func _on_player_entered(_player_node: Node3D) -> void:
	start_sequence()


## Updates [member target_bones] based on [enum BonePreset] selection.
func _apply_preset(preset: BonePreset) -> void:
	match preset:
		BonePreset.TORSO:
			target_bones = PRESET_TORSO_BONES.duplicate()
		BonePreset.ARMS:
			target_bones = PRESET_ARM_BONES.duplicate()
		BonePreset.LEGS:
			target_bones = PRESET_LEG_BONES.duplicate()
		BonePreset.HEAD:
			target_bones = PRESET_HEAD_BONES.duplicate()
		BonePreset.ALL:
			target_bones = PRESET_ALL_BONES.duplicate()
		BonePreset.CUSTOM:
			pass


## Determines the 3D focal center of the configured destination node.
func _resolve_destination_center() -> Vector3:
	if target_destination is TargetArrivalBox3D:
		var arrival_box: TargetArrivalBox3D = target_destination as TargetArrivalBox3D
		return arrival_box.get_target_center()
	return target_destination.global_position


## Checks whether [param bone_pos] satisfies arrival inside the destination boundary.
func _has_bone_arrived(bone_pos: Vector3, dest_center: Vector3) -> bool:
	if target_destination is TargetArrivalBox3D:
		var arrival_box: TargetArrivalBox3D = target_destination as TargetArrivalBox3D
		return arrival_box.contains_point(bone_pos)

	return bone_pos.distance_squared_to(dest_center) <= (arrival_radius * arrival_radius)


## Computes and applies a corrective PD spring impulse to [param phys_bone].
func _apply_bone_spring_force(
	phys_bone: PhysicalBone3D, dest_center: Vector3, delta: float
) -> void:
	var delta_pos: Vector3 = dest_center - phys_bone.global_position
	var dist: float = delta_pos.length()
	if dist <= 0.001:
		return

	var pull_dir: Vector3 = delta_pos / dist
	var desired_velocity: Vector3 = pull_dir * pull_speed
	var velocity_error: Vector3 = desired_velocity - phys_bone.linear_velocity

	var mass: float = phys_bone.mass
	var force: Vector3 = velocity_error * (mass * spring_gain)
	if force.length_squared() > (max_force * max_force):
		force = force.normalized() * max_force

	var impulse: Vector3 = force * delta
	phys_bone.apply_central_impulse(impulse)
