## An Area3D volume that continuously modifies the health of overlapping bodies.
##
## Periodically applies damage or healing to any [Node3D] within the area that possesses a
## valid [HealthComponent] as a child.
class_name HealthModifier
extends Area3D

## The amount of health to modify per tick. Negative values deal damage. Positive values heal.
@export var modify_amount: int = -25
## Time interval in seconds between health modifications.
@export var tick_interval: float = 1.0

## Internal timer used for scheduling health ticks.
var _tick_timer: Timer


## Initializes and starts the internal tick timer upon entering the scene tree.
func _ready() -> void:
	_tick_timer = Timer.new()
	_tick_timer.wait_time = tick_interval
	_tick_timer.autostart = true
	add_child(_tick_timer)

	_tick_timer.timeout.connect(_on_tick_timer_timeout)


## Called periodically by the internal timer. Iterates over overlapping bodies and modifies health.
func _on_tick_timer_timeout() -> void:
	var bodies: Array[Node3D] = get_overlapping_bodies()

	for body: Node3D in bodies:
		# Added "Components/" to the relative path
		var health_node: Node = body.get_node_or_null("Components/HealthComponent")

		if health_node is HealthComponent:
			if modify_amount < 0:
				health_node.take_damage(abs(modify_amount))
			elif modify_amount > 0:
				health_node.heal(modify_amount)
