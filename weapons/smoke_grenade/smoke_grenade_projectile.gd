## Thrown smoke grenade canister that detonates after fuse timeout and spawns [SmokeGrenadeCloud].
class_name SmokeGrenadeProjectile
extends RigidBody3D

## Packed scene for the volumetric [SmokeGrenadeCloud].
const SMOKE_CLOUD_SCENE: PackedScene = preload(
	"res://weapons/smoke_grenade/smoke_grenade_cloud.tscn"
)

## Fuse delay in seconds before smoke detonation.
@export var fuse_time: float = 1.6

## Prevents multiple detonations if triggered simultaneously.
var _has_detonated: bool = false

## Active fuse timer reference to cancel on tree exit.
var _fuse_timer: SceneTreeTimer = null


## Configures physics layers, continuous collision detection, and starts fuse timer.
func _ready() -> void:
	assert(fuse_time > 0.0, "fuse_time must be positive")
	set_process(false)
	set_physics_process(false)
	continuous_cd = true
	collision_layer = Types.MASK_DEBRIS
	collision_mask = Types.MASK_SOLID_WORLD | Types.MASK_ENEMIES | Types.MASK_INTERACTIVE

	_fuse_timer = get_tree().create_timer(fuse_time, false)
	_fuse_timer.timeout.connect(_on_fuse_timeout)
	print("[SmokeGrenadeProjectile] Thrown canister armed with fuse: ", fuse_time)


## Cancels fuse and marks detonated on tree exit to prevent post-teardown execution.
func _exit_tree() -> void:
	_has_detonated = true
	if is_instance_valid(_fuse_timer) and _fuse_timer.timeout.is_connected(_on_fuse_timeout):
		_fuse_timer.timeout.disconnect(_on_fuse_timeout)
	_fuse_timer = null


## Handles fuse timer expiry.
func _on_fuse_timeout() -> void:
	if not _has_detonated and is_inside_tree():
		_detonate()


## Spawns [SmokeGrenadeCloud] with world transform pre-assigned before scene tree insertion.
func _detonate() -> void:
	if _has_detonated or not is_inside_tree():
		return
	_has_detonated = true
	var detonate_pos: Vector3 = global_position
	print("[SmokeGrenadeProjectile] Detonating at: ", detonate_pos)

	var cloud_inst: Node = SMOKE_CLOUD_SCENE.instantiate()
	var cloud: SmokeGrenadeCloud = cloud_inst as SmokeGrenadeCloud
	if is_instance_valid(cloud):
		# Prefer current scene -> parent node -> root fallback
		var target_parent: Node = get_tree().current_scene
		if not is_instance_valid(target_parent):
			target_parent = get_parent()
		if not is_instance_valid(target_parent):
			target_parent = get_tree().root

		cloud.transform = Transform3D(Basis.IDENTITY, detonate_pos)
		target_parent.add_child(cloud)
		cloud.global_position = detonate_pos
	elif is_instance_valid(cloud_inst):
		cloud_inst.queue_free()

	queue_free()
