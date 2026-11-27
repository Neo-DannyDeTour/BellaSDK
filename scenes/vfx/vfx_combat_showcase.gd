## Playable industrial combat VFX showcase validating HL2 smoke, HDR fire, and bullet impacts.
class_name VfxCombatShowcase
extends Node3D

@onready var _ambient_smoke: Node3D = $AmbientSmoke
@onready var _fire_bays: Node3D = $FireBays
@onready var _target_walls: Node3D = $TargetWalls
@onready var _player: Node3D = $Player


## Validates showcase bays and disables unused per-frame polling.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(is_instance_valid(_ambient_smoke), "VfxCombatShowcase requires AmbientSmoke node.")
	assert(is_instance_valid(_fire_bays), "VfxCombatShowcase requires FireBays node.")
	assert(is_instance_valid(_target_walls), "VfxCombatShowcase requires TargetWalls node.")
	assert(is_instance_valid(_player), "VfxCombatShowcase requires Player node.")
	print("VfxCombatShowcase: Ready with smoke, fire, weapon, and impact bays.")
