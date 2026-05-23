extends RigidBody3D

@export var health := 200
@export var knockback_force := 0.5
@export var vertical_kick := 0.7

# --- THE FIGHTING BAG BOBBING ---
var time_passed := 0.0


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# This creates a "Fighting Bag" bobbing effect
	# It adds a tiny constant force that oscillates over time
	time_passed += get_process_delta_time()
	var bob := sin(time_passed * 2.0) * 0.5
	state.apply_force(Vector3(0, bob, 0))


# --- TAKING DAMAGE & KNOCKBACK ---
func take_damage(amount: int, dir: Vector3) -> void:
	health -= amount
	print("Hit! Health: ", health)

	# THE PHYSICS PUNCH
	# We take the pellet direction, flatten the Y slightly so they fly 'back',
	# and then add a 'kick' upward so they catch some air.
	var punch := dir.normalized() * knockback_force
	punch.y += vertical_kick

	apply_central_impulse(punch)


func _process(_delta: float) -> void:
	if health <= 0:
		die()


func die() -> void:
	# TODO: Spawn some red particles or a sound here!
	queue_free()
