## Articulated 2.0m female mannequin prop with event-driven [PhysicalBoneSimulator3D] ragdoll.
class_name MannequinRagdoll
extends Node3D

## Emitted when ragdoll simulation activates on hit, interaction, or explicit call.
signal ragdoll_activated(hit_bone: StringName, impulse: Vector3)

## Preloaded 2.0m articulated mannequin glTF scene generated from Blender.
const MODEL_SCENE: PackedScene = preload(
	"res://assets/models/mannequin_ragdoll/mannequin_ragdoll.glb"
)
## Group name for entities capable of receiving weapon and hazard damage.
const GROUP_DAMAGEABLE: StringName = &"damageable"
## Root physical bone name used as fallback impulse target.
const BONE_PELVIS: StringName = &"Pelvis"
## Upper torso physical bone name used for chest/center-of-mass hits.
const BONE_CHEST: StringName = &"Chest"
## Default physics mask combining Environment, Player, and Interactive layers.
const DEFAULT_RAGDOLL_MASK: int = (
	CollisionLayers.MASK_ENVIRONMENT
	| CollisionLayers.MASK_PLAYER
	| CollisionLayers.MASK_INTERACTIVE
)
## Default linear damping applied to ragdoll limb bodies.
const DEFAULT_LINEAR_DAMP: float = 0.45
## Default angular damping applied to ragdoll joints to prevent jitter.
const DEFAULT_ANGULAR_DAMP: float = 2.20

## Starts limp ragdoll physics immediately on [method _ready] when enabled.
@export var start_active: bool = false
## Multiplier converting incoming weapon damage into directional ragdoll impulse.
@export var hit_impulse_scale: float = 0.35
## Total articulated mass in kilograms distributed across all 17 mannequin segments.
@export var total_mass: float = 62.0
## Optional [HealthComponent] tracking structural hit points alongside ragdoll physics.
@export var health_component: HealthComponent

## Tracks whether [PhysicalBoneSimulator3D] ragdoll simulation is currently active.
var is_ragdoll_active: bool = false

## Cached reference to the instantiated mannequin [Skeleton3D].
var _skeleton: Skeleton3D
## Cached reference to the skinned [MeshInstance3D] on Render Layer 3.
var _mesh_instance: MeshInstance3D
## Cached reference to the [PhysicalBoneSimulator3D] driving ragdoll bones.
var _simulator: PhysicalBoneSimulator3D
## Lookup table mapping bone [StringName] identifiers to [PhysicalBone3D] nodes.
var _physical_bones: Dictionary[StringName, PhysicalBone3D] = {}
## Cached rest-pose local transforms for each bone index to support pool resets.
var _initial_bone_poses: Dictionary[int, Transform3D] = {}


## Strongly-typed configuration container for individual physical bone dimensions.
class BoneSpec:
	extends RefCounted

	var name: StringName
	var length: float
	var radius: float
	var mass_share: float
	var is_hinge: bool
	var swing_deg: float
	var twist_deg: float

	func _init(
		b_name: StringName,
		b_length: float,
		b_radius: float,
		b_mass_share: float,
		b_is_hinge: bool,
		b_swing_deg: float,
		b_twist_deg: float
	) -> void:
		name = b_name
		length = b_length
		radius = b_radius
		mass_share = b_mass_share
		is_hinge = b_is_hinge
		swing_deg = b_swing_deg
		twist_deg = b_twist_deg


## Physics bone collider that relays weapon raycast and projectile hits to [MannequinRagdoll].
class MannequinPhysicalBone:
	extends PhysicalBone3D

	## Owning [MannequinRagdoll] controller receiving relayed damage events.
	var ragdoll_owner: MannequinRagdoll
	## Bone identifier assigned to this physical segment.
	var segment_bone_name: StringName = &""

	## Relays incoming weapon or melee damage to the owning [MannequinRagdoll].
	func take_damage(
		amount: float, hit_position: Vector3 = Vector3.ZERO, hit_dir: Vector3 = Vector3.ZERO
	) -> void:
		print("MannequinPhysicalBone: Hit on bone ", segment_bone_name, " for ", amount)
		if is_instance_valid(ragdoll_owner):
			ragdoll_owner.on_bone_damaged(self, amount, hit_position, hit_dir)


## Disables per-frame polling, validates invariants, builds physical bones, and sets layers.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(total_mass > 0.0, "MannequinRagdoll: total_mass must be greater than zero.")
	print("MannequinRagdoll: Initializing 2.0m articulated mannequin ragdoll: ", name)

	add_to_group(GROUP_DAMAGEABLE)
	_setup_model_and_skeleton()
	_build_physical_bones()

	if start_active:
		activate_ragdoll.call_deferred()


## Receives direct damage calls, forwards to [HealthComponent], and activates ragdoll physics.
func take_damage(
	amount: float, hit_position: Vector3 = Vector3.ZERO, hit_dir: Vector3 = Vector3.ZERO
) -> void:
	print("MannequinRagdoll: take_damage() - Amount: ", amount)
	if is_instance_valid(health_component):
		health_component.take_damage(int(amount))

	var dir_norm: Vector3 = (
		hit_dir.normalized() if hit_dir.length_squared() > 0.0001 else Vector3.BACK
	)
	var impulse: Vector3 = dir_norm * (amount * hit_impulse_scale)
	var target_bone: StringName = _find_closest_bone_name(hit_position)
	activate_ragdoll(impulse, hit_position, target_bone)


## Handles localized damage relayed from an individual struck [MannequinPhysicalBone].
func on_bone_damaged(
	bone: MannequinPhysicalBone, amount: float, hit_position: Vector3, hit_dir: Vector3
) -> void:
	print("MannequinRagdoll: Bone damaged: ", bone.segment_bone_name, " | Amount: ", amount)
	if is_instance_valid(health_component):
		health_component.take_damage(int(amount))

	var dir_norm: Vector3 = (
		hit_dir.normalized() if hit_dir.length_squared() > 0.0001 else Vector3.BACK
	)
	var impulse: Vector3 = dir_norm * (amount * hit_impulse_scale)
	activate_ragdoll(impulse, hit_position, bone.segment_bone_name)


## Starts ragdoll simulation safely via deferred execution and applies an optional hit impulse.
func activate_ragdoll(
	impulse: Vector3 = Vector3.ZERO,
	hit_position: Vector3 = Vector3.ZERO,
	target_bone: StringName = &""
) -> void:
	print("MannequinRagdoll: Queuing ragdoll activation on bone: ", target_bone)
	_apply_simulation_and_impulse.call_deferred(impulse, hit_position, target_bone)


## Stops ragdoll physics simulation and restores the standing A-pose skeleton state.
func reset_ragdoll() -> void:
	print("MannequinRagdoll: Resetting ragdoll to standing A-pose.")
	_reset_simulation_deferred.call_deferred()


## Returns the active [Skeleton3D] instance driving the mannequin mesh.
func get_skeleton() -> Skeleton3D:
	return _skeleton


## Returns the [PhysicalBone3D] registered for [param bone_name], or null if not found.
func get_physical_bone(bone_name: StringName) -> PhysicalBone3D:
	if _physical_bones.has(bone_name):
		return _physical_bones[bone_name]
	return null


## Returns the total number of configured [PhysicalBone3D] ragdoll segments.
func get_physical_bone_count() -> int:
	return _physical_bones.size()


## Instantiates the Blender glTF model, caches [Skeleton3D] and [MeshInstance3D], and sets layers.
func _setup_model_and_skeleton() -> void:
	var existing_skel: Skeleton3D = _find_skeleton_recursive(self)
	if existing_skel == null and MODEL_SCENE != null:
		var model_inst: Node = MODEL_SCENE.instantiate()
		model_inst.name = "MannequinModel"
		add_child(model_inst)
		existing_skel = _find_skeleton_recursive(model_inst)

	_skeleton = existing_skel
	assert(_skeleton != null, "MannequinRagdoll: Skeleton3D missing from mannequin model.")

	_mesh_instance = _find_mesh_recursive(self)
	assert(_mesh_instance != null, "MannequinRagdoll: MeshInstance3D missing from mannequin model.")

	# Enforce Layer 3 (Interactive) on visual mesh per project layer conventions
	_mesh_instance.layers = CollisionLayers.RENDER_MASK_INTERACTIVE

	for i: int in range(_skeleton.get_bone_count()):
		_initial_bone_poses[i] = _skeleton.get_bone_pose(i)


## Constructs the [PhysicalBoneSimulator3D] and 17 articulated [PhysicalBone3D] segments.
func _build_physical_bones() -> void:
	if _skeleton == null:
		return

	_simulator = PhysicalBoneSimulator3D.new()
	_simulator.name = "PhysicalBoneSimulator3D"
	_skeleton.add_child(_simulator)

	var specs: Array[BoneSpec] = [
		BoneSpec.new(&"Pelvis", 0.22, 0.125, 0.16, false, 20.0, 15.0),
		BoneSpec.new(&"Waist", 0.17, 0.105, 0.10, false, 28.0, 22.0),
		BoneSpec.new(&"Chest", 0.27, 0.130, 0.18, false, 25.0, 20.0),
		BoneSpec.new(&"Neck", 0.08, 0.048, 0.03, false, 35.0, 30.0),
		BoneSpec.new(&"Head", 0.24, 0.095, 0.07, false, 40.0, 35.0),
		BoneSpec.new(&"UpperArm.L", 0.26, 0.045, 0.04, false, 75.0, 45.0),
		BoneSpec.new(&"LowerArm.L", 0.26, 0.038, 0.03, true, 125.0, 10.0),
		BoneSpec.new(&"Hand.L", 0.16, 0.030, 0.015, false, 45.0, 25.0),
		BoneSpec.new(&"UpperArm.R", 0.26, 0.045, 0.04, false, 75.0, 45.0),
		BoneSpec.new(&"LowerArm.R", 0.26, 0.038, 0.03, true, 125.0, 10.0),
		BoneSpec.new(&"Hand.R", 0.16, 0.030, 0.015, false, 45.0, 25.0),
		BoneSpec.new(&"UpperLeg.L", 0.42, 0.078, 0.08, false, 65.0, 30.0),
		BoneSpec.new(&"LowerLeg.L", 0.41, 0.054, 0.05, true, 130.0, 10.0),
		BoneSpec.new(&"Foot.L", 0.20, 0.040, 0.02, false, 35.0, 15.0),
		BoneSpec.new(&"UpperLeg.R", 0.42, 0.078, 0.08, false, 65.0, 30.0),
		BoneSpec.new(&"LowerLeg.R", 0.41, 0.054, 0.05, true, 130.0, 10.0),
		BoneSpec.new(&"Foot.R", 0.20, 0.040, 0.02, false, 35.0, 15.0),
	]

	for spec: BoneSpec in specs:
		_create_bone_collider(
			spec.name,
			spec.length,
			spec.radius,
			spec.mass_share,
			spec.is_hinge,
			spec.swing_deg,
			spec.twist_deg
		)


## Creates and configures a single [MannequinPhysicalBone] with capsule shape and joint limits.
func _create_bone_collider(
	bone_name: StringName,
	bone_len: float,
	radius: float,
	mass_share: float,
	is_hinge: bool,
	swing_deg: float,
	twist_deg: float
) -> void:
	var bone_idx: int = _skeleton.find_bone(String(bone_name))
	if bone_idx < 0:
		return

	var phys_bone: MannequinPhysicalBone = MannequinPhysicalBone.new()
	phys_bone.name = "PhysicalBone_" + String(bone_name).replace(".", "_")
	phys_bone.ragdoll_owner = self
	phys_bone.segment_bone_name = bone_name
	phys_bone.set(&"bone_name", String(bone_name))
	phys_bone.mass = maxf(0.25, total_mass * mass_share)
	phys_bone.friction = 0.75
	phys_bone.bounce = 0.05
	phys_bone.linear_damp = DEFAULT_LINEAR_DAMP
	phys_bone.angular_damp = DEFAULT_ANGULAR_DAMP
	phys_bone.collision_layer = CollisionLayers.MASK_INTERACTIVE
	phys_bone.collision_mask = DEFAULT_RAGDOLL_MASK
	phys_bone.body_offset = Transform3D(Basis.IDENTITY, Vector3(0.0, bone_len * 0.5, 0.0))

	var col_shape: CollisionShape3D = CollisionShape3D.new()
	col_shape.name = "CollisionShape3D"
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = maxf(radius * 2.02, bone_len)
	col_shape.shape = capsule
	phys_bone.add_child(col_shape)

	_simulator.add_child(phys_bone)

	if bone_name != BONE_PELVIS:
		if is_hinge:
			phys_bone.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
			phys_bone.set("joint_constraints/angular_limit_enabled", true)
			phys_bone.set("joint_constraints/angular_limit_upper", swing_deg)
			phys_bone.set("joint_constraints/angular_limit_lower", 0.0)
		else:
			phys_bone.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			phys_bone.set("joint_constraints/swing_span", swing_deg)
			phys_bone.set("joint_constraints/twist_span", twist_deg)

	_physical_bones[bone_name] = phys_bone


## Deferred helper that starts physical bone simulation and applies directional impulse.
func _apply_simulation_and_impulse(
	impulse: Vector3, hit_position: Vector3, target_bone: StringName
) -> void:
	if _simulator == null:
		return

	if not is_ragdoll_active:
		is_ragdoll_active = true
		_simulator.active = true
		_simulator.physical_bones_start_simulation()
		print("MannequinRagdoll: PhysicalBoneSimulator3D simulation active.")

	var resolved_bone: StringName = target_bone
	if not _physical_bones.has(resolved_bone):
		resolved_bone = BONE_CHEST if _physical_bones.has(BONE_CHEST) else BONE_PELVIS

	if impulse.length_squared() > 0.0001 and _physical_bones.has(resolved_bone):
		var pb: PhysicalBone3D = _physical_bones[resolved_bone]
		var offset: Vector3 = (
			hit_position - pb.global_position
			if hit_position.length_squared() > 0.0001
			else Vector3.ZERO
		)
		pb.apply_impulse(impulse, offset)

	ragdoll_activated.emit(resolved_bone, impulse)


## Deferred helper that halts physical bone simulation and restores initial bone transforms.
func _reset_simulation_deferred() -> void:
	if _simulator == null or _skeleton == null:
		return

	_simulator.physical_bones_stop_simulation()
	_simulator.active = false
	is_ragdoll_active = false

	for bone_idx: int in _initial_bone_poses.keys():
		_skeleton.set_bone_pose(bone_idx, _initial_bone_poses[bone_idx])


## Finds the closest [PhysicalBone3D] name to [param world_pos] using squared distance.
func _find_closest_bone_name(world_pos: Vector3) -> StringName:
	if world_pos.length_squared() <= 0.0001 or _physical_bones.is_empty():
		return BONE_CHEST

	var best_name: StringName = BONE_CHEST
	var best_dist_sq: float = INF
	for b_name: StringName in _physical_bones.keys():
		var pb: PhysicalBone3D = _physical_bones[b_name]
		var d_sq: float = pb.global_position.distance_squared_to(world_pos)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best_name = b_name
	return best_name


## Recursively searches [param node] hierarchy for the first [Skeleton3D].
func _find_skeleton_recursive(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton_recursive(child)
		if found != null:
			return found
	return null


## Recursively searches [param node] hierarchy for the first [MeshInstance3D].
func _find_mesh_recursive(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh_recursive(child)
		if found != null:
			return found
	return null
