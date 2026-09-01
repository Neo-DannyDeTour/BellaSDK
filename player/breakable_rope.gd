## A destructible physics rope that breaks after sustaining sufficient damage.
##
## Acts as a structural weak point in puzzle mechanics. Once the rope's health drops
## to zero, it broadcasts a signal (useful for dropping drawbridges or heavy objects)
## and then frees its root hierarchy.
class_name BreakableRope
extends StaticBody3D

## Emitted when the rope's health reaches zero and it snaps.
signal rope_broken

## The total amount of damage this rope can sustain before breaking.
@export var health: int = 10

## Tracks if the rope has already been destroyed to prevent duplicate breaking logic.
var is_broken: bool = false


## Handles incoming damage, such as from shotgun blasts or physics impacts.
## [param amount] The damage value to subtract from health.
## [param hit_position] The global coordinate where the impact occurred.
## [param direction] The trajectory vector of the incoming attack.
func take_damage(amount: int, hit_position: Vector3, direction: Vector3) -> void:
	print(
		"BreakableRope: take_damage() called. Amount: ",
		amount,
		" | Pos: ",
		hit_position,
		" | Dir: ",
		direction
	)

	if is_broken:
		return  # Stop right here! We are already dead.

	# 1. Subtract the shotgun's damage from the rope's health
	health -= amount

	# 2. Only break if health drops to 0 or below
	if health <= 0:
		is_broken = true
		snap_rope()


## Executes the destruction sequence, broadcasting the signal and cleaning up nodes.
func snap_rope() -> void:
	print("BreakableRope: snap_rope() called. Rope snapped!")

	# 3. Emit the EXACT signal the drawbridge is listening for
	rope_broken.emit()

	# Play snap sound, spawn particle, hide mesh, etc.

	# 4. Delete the entire Path3D root, not just the StaticBody!
	if owner:
		print("BreakableRope: Freeing owner node.")
		owner.queue_free()
	else:
		print("BreakableRope: Freeing self.")
		queue_free()
