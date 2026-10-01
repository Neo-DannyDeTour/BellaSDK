## Area3D volume that continuously modifies the health of overlapping bodies.
class_name HealthModifier
extends Area3D

## The amount of health to modify per tick. Negative deals damage, positive heals.
@export var modify_amount: int = -25

## Time interval in seconds between consecutive health modifications.
@export var tick_interval: float = 1.0

## Internal timer used for scheduling periodic health ticks.
var _tick_timer: Timer

## Maps overlapping physics bodies to their resolved [HealthComponent].
var _health_cache: Dictionary = {}


## Initializes timer and connects body detection signals.
func _ready() -> void:
	print("HealthModifier: Initializing health modifier volume.")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_tick_timer = Timer.new()
	_tick_timer.wait_time = tick_interval
	_tick_timer.autostart = true
	add_child(_tick_timer)
	_tick_timer.timeout.connect(_on_tick_timer_timeout)


## Resolves and caches [HealthComponent] when a body enters the volume.
func _on_body_entered(body: Node3D) -> void:
	print("HealthModifier: Body entered volume -> ", body.name)
	var comp: HealthComponent = _resolve_health_node(body)
	if is_instance_valid(comp):
		_health_cache[body] = comp


## Clears the body from the health component cache upon exit.
func _on_body_exited(body: Node3D) -> void:
	print("HealthModifier: Body exited volume -> ", body.name)
	_health_cache.erase(body)


## Resolves [HealthComponent] on target via direct property or typed search.
func _resolve_health_node(body: Node3D) -> HealthComponent:
	print("HealthModifier: Resolving health component for -> ", body.name)
	if not is_instance_valid(body):
		return null

	if "health_component" in body:
		var comp: Variant = body.get("health_component")
		if comp is HealthComponent:
			return comp as HealthComponent

	var child_comp: Node = NodeQuery.find_first_child_of_type(body, HealthComponent)
	if child_comp is HealthComponent:
		return child_comp as HealthComponent

	return null


## Retrieves overlapping bodies within the area. Can be overridden for tests.
func _get_target_bodies() -> Array[Node3D]:
	print("HealthModifier: Fetching overlapping bodies.")
	return get_overlapping_bodies()


## Periodically modifies health on cached and newly resolved overlapping bodies.
func _on_tick_timer_timeout() -> void:
	print("HealthModifier: Processing tick damage/heal.")
	var bodies: Array[Node3D] = _get_target_bodies()

	for body: Node3D in bodies:
		if not is_instance_valid(body):
			_health_cache.erase(body)
			continue

		var comp: HealthComponent = _health_cache.get(body) as HealthComponent
		if not is_instance_valid(comp):
			comp = _resolve_health_node(body)
			if is_instance_valid(comp):
				_health_cache[body] = comp
			else:
				continue

		if modify_amount < 0:
			comp.take_damage(absi(modify_amount))
		elif modify_amount > 0:
			comp.heal(modify_amount)
