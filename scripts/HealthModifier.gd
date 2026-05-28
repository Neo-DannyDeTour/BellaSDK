extends Area3D

## Negative values deal damage. Positive values heal.
@export var modify_amount: int = -25
@export var tick_interval: float = 1.0

var _tick_timer: Timer


func _ready() -> void:
	_tick_timer = Timer.new()
	_tick_timer.wait_time = tick_interval
	_tick_timer.autostart = true
	add_child(_tick_timer)
	
	_tick_timer.timeout.connect(_on_tick_timer_timeout)


func _on_tick_timer_timeout() -> void:
	var bodies: Array[Node3D] = get_overlapping_bodies()
	
	for body: Node3D in bodies:
		var health_node: Node = body.get_node_or_null("HealthComponent")
		if health_node is HealthComponent:
			if modify_amount < 0:
				health_node.take_damage(abs(modify_amount))
			elif modify_amount > 0:
				health_node.heal(modify_amount)
