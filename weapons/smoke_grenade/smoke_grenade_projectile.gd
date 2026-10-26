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


## Configures physics layers, continuous collision detection, and starts fuse timer.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	continuous_cd = true
	collision_layer = Types.MASK_DEBRIS
	collision_mask = Types.MASK_SOLID_WORLD | Types.MASK_ENEMIES | Types.MASK_INTERACTIVE
	Utilities.delay_call(self, fuse_time, _detonate)
	print("[SmokeGrenadeProjectile] Thrown canister armed with fuse: ", fuse_time)


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
		var scene_root: Node = get_tree().current_scene
		if not is_instance_valid(scene_root):
			scene_root = get_tree().root
		# Pre-assign transform before add_child so _ready() raycasts at detonation coordinates.
		cloud.transform = Transform3D(Basis.IDENTITY, detonate_pos)
		scene_root.add_child(cloud)
		cloud.global_position = detonate_pos
	elif is_instance_valid(cloud_inst):
		cloud_inst.queue_free()

	queue_free()
