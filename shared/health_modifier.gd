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

## Caches mapped health component instances for overlapping bodies.
var _health_cache: Dictionary = {}


## Initializes timer and area signals upon entering scene tree.
func _ready() -> void:
	print("HealthModifier: Initializing health modifier volume.")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_tick_timer = Timer.new()
	_tick_timer.wait_time = tick_interval
	_tick_timer.autostart = true
	add_child(_tick_timer)

	_tick_timer.timeout.connect(_on_tick_timer_timeout)


## Resolves and caches health components when bodies enter area.
func _on_body_entered(body: Node3D) -> void:
	print("HealthModifier: Body entered volume -> ", body.name)
	var comp: Node = _resolve_health_node(body)
	if is_instance_valid(comp):
		_health_cache[body] = comp


## Clears body from component cache when exiting area volume.
func _on_body_exited(body: Node3D) -> void:
	print("HealthModifier: Body exited volume -> ", body.name)
	_health_cache.erase(body)


## Resolves [HealthComponent] on target through paths or properties.
func _resolve_health_node(body: Node3D) -> Node:
	print("HealthModifier: Resolving health component for -> ", body.name)
	var health_node: Node = body.get_node_or_null("Components/HealthComponent")
	if health_node == null:
		health_node = body.get_node_or_null("HealthComponent")
	if health_node == null:
		health_node = body.find_child("HealthComponent", true, false)
	if health_node == null and body.has_method("get"):
		var h_comp: Variant = body.get("health_component")
		if h_comp is Node:
			health_node = h_comp as Node
	return health_node


## Retrieves overlapping bodies within the area. Can be overridden for testing.
func _get_target_bodies() -> Array[Node3D]:
	return get_overlapping_bodies()


## Called periodically by the internal timer. Iterates over overlapping bodies and modifies health.
func _on_tick_timer_timeout() -> void:
	print("HealthModifier: Processing tick damage/heal.")
	var bodies: Array[Node3D] = _get_target_bodies()

	for body: Node3D in bodies:
		if not is_instance_valid(body):
			_health_cache.erase(body)
			continue

		var health_node: Node = _health_cache.get(body) as Node
		if not is_instance_valid(health_node):
			health_node = _resolve_health_node(body)
			if is_instance_valid(health_node):
				_health_cache[body] = health_node
			else:
				continue

		if health_node.has_method("take_damage") and health_node.has_method("heal"):
			if modify_amount < 0:
				health_node.take_damage(abs(modify_amount))
			elif modify_amount > 0:
				health_node.heal(modify_amount)
