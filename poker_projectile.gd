extends RigidBody3D
class_name PokerProjectile

## The amount of time in seconds before the projectile deletes itself.
## Deleting physical objects quickly ensures physics calculations remain lightweight for a stable 60 FPS.
@export var lifespan: float = 0.2


func _ready() -> void:
	print("Poker projectile spawned and moving to deform the meat cube.")
	
	# Create a timer to automatically clean up the projectile
	var timer: SceneTreeTimer = get_tree().create_timer(lifespan)
	timer.timeout.connect(_on_lifespan_timeout)


func _on_lifespan_timeout() -> void:
	print("Poker projectile hit its lifespan limit and is queueing free.")
	queue_free()
