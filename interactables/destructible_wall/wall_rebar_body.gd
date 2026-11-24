## Static rebar collider absorbing hitscan damage so bullets never pass to parent wall chunks.
class_name WallRebarBody
extends StaticBody3D

## Spatial 3D sound effect played when bullets ricochet off exposed steel rebar.
@export var ricochet_sfx: AudioStream = null


## Disables per-frame processing on initialization.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)


## Absorbs incoming hitscan damage and requests a 3D ricochet sound at [param hit_pos].
func take_damage(
	_amount: int, hit_pos: Vector3 = Vector3.ZERO, _dir: Vector3 = Vector3.ZERO
) -> void:
	print("WallRebarBody: Bullet ricocheted off exposed rebar at ", hit_pos)
	if is_instance_valid(ricochet_sfx):
		Events.sfx_3d_requested.emit(ricochet_sfx, hit_pos, &"SFX")
