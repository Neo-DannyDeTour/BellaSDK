extends StaticBody3D

signal rope_broken

var health: int = 10
var is_broken: bool = false


# We add the parameters here so it catches what the shotgun throws!
func take_damage(amount: int, _direction: Vector3) -> void:
	if is_broken:
		return  # Stop right here! We are already dead.

	# 1. Subtract the shotgun's damage from the rope's health
	health -= amount

	# 2. Only break if health drops to 0 or below
	if health <= 0:
		is_broken = true
		snap_rope()


func snap_rope() -> void:
	print("Rope snapped!")

	# 3. Emit the EXACT signal the drawbridge is listening for
	rope_broken.emit()

	# Play snap sound, spawn particle, hide mesh, etc.

	# 4. Delete the entire Path3D root, not just the StaticBody!
	if owner:
		owner.queue_free()
	else:
		queue_free()
