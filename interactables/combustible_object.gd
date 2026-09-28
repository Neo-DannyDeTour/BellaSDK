## [CombustibleObject] manages burning state, heat transfer, and propagation to neighbors.
class_name CombustibleObject
extends RigidBody3D

## Default heat accumulation threshold required to ignite this body.
const DEFAULT_IGNITION_THRESHOLD: float = 100.0
## Physics collision layer mask for Interactive objects (Layer 3).
const INTERACTIVE_PHYSICS_LAYER: int = 4
## Physics mask checking Player, Interactive, Debris, and Enemies (2-5).
const PROPAGATION_PHYSICS_MASK: int = 30

## Emitted when [member temperature] hits threshold and the object begins burning.
signal ignited
## Emitted when the object is fully consumed by fire and prepares for removal.
signal burned_down
## Emitted when heat increases, passing current and maximum temperatures.
signal temperature_changed(current: float, max_threshold: float)

## Scene resource for [VolumetricFire] instantiated upon ignition.
@export var fire_scene: PackedScene

## Maximum health durability before the object is destroyed by burning.
@export_range(1.0, 500.0, 1.0) var max_health: float = 60.0

## Heat temperature threshold at which the object ignites.
@export_range(10.0, 200.0, 5.0) var ignition_threshold: float = DEFAULT_IGNITION_THRESHOLD

## Heat units transferred per second to neighboring combustible bodies.
@export_range(5.0, 200.0, 5.0) var heat_radiation_rate: float = 45.0

## Radius in meters within which fire propagates to neighboring bodies.
@export_range(0.5, 10.0, 0.1) var propagation_radius: float = 2.2

## Fire damage taken per second while actively burning.
@export_range(0.0, 100.0, 1.0) var burn_damage_rate: float = 15.0

## Current heat temperature accumulated from neighboring fire sources.
var temperature: float = 0.0

## Current health points remaining before destruction.
var _health: float = 60.0

## Tracks whether this object is currently burning.
var _is_on_fire: bool = false

## Active [VolumetricFire] instance attached to this body while burning.
var _spawned_fire: VolumetricFire = null

## Internal [Area3D] used to detect neighboring combustible objects.
var _propagation_area: Area3D = null

## List of neighboring [CombustibleObject] instances receiving heat.
var _neighboring_targets: Array[CombustibleObject] = []


## Initializes health, sets physics layers, and builds heat detection area.
func _ready() -> void:
	_health = max_health
	collision_layer = INTERACTIVE_PHYSICS_LAYER
	_setup_propagation_area()


## Applies burning damage and radiates heat to neighbors in [method _physics_process].
func _physics_process(delta: float) -> void:
	if not _is_on_fire:
		return

	_propagate_heat(delta)
	take_fire_damage(burn_damage_rate * delta)


## Instantly ignites this object, spawning visual fire and emitting [signal ignited].
func ignite() -> void:
	if _is_on_fire:
		return
	print("[CombustibleObject] Ignited: ", name)
	_is_on_fire = true
	temperature = ignition_threshold
	_spawn_fire_effect()
	ignited.emit()


## Adds heat to [member temperature], triggering [method ignite] when threshold is met.
func apply_heat(amount: float) -> void:
	if _is_on_fire or amount <= 0.0:
		return
	temperature += amount
	print("[CombustibleObject] Heat applied to ", name, ": ", amount, " | Temp: ", temperature)
	temperature_changed.emit(temperature, ignition_threshold)
	if temperature >= ignition_threshold:
		ignite()


## Decrements health and triggers destruction when health reaches zero.
func take_fire_damage(amount: float) -> void:
	if _health <= 0.0:
		return
	_health -= amount
	print("[CombustibleObject] Damage taken by ", name, ": ", amount, " | HP: ", _health)
	if _health <= 0.0:
		_destroy_burned_object()


## Extinguishes burning, frees fire instance, and cools temperature down.
func extinguish() -> void:
	print("[CombustibleObject] Extinguished: ", name)
	_is_on_fire = false
	temperature = 0.0
	if is_instance_valid(_spawned_fire):
		_spawned_fire.extinguish()
		_spawned_fire.queue_free()
		_spawned_fire = null


## Radiates heat to overlapping bodies in [member _propagation_area].
func _propagate_heat(delta: float) -> void:
	if _neighboring_targets.is_empty():
		return

	var heat_step: float = heat_radiation_rate * delta
	for i: int in range(_neighboring_targets.size() - 1, -1, -1):
		var target: CombustibleObject = _neighboring_targets[i]
		if not is_instance_valid(target):
			_neighboring_targets.remove_at(i)
			continue
		target.apply_heat(heat_step)


## Instantiates and configures [VolumetricFire] scene attached to this body.
func _spawn_fire_effect() -> void:
	if not is_instance_valid(fire_scene):
		return

	var fire_node: Node = fire_scene.instantiate()
	if fire_node is VolumetricFire:
		_spawned_fire = fire_node
		_spawned_fire.ignored_body = self
		_spawned_fire.fire_width = 1.4
		_spawned_fire.fire_height = 1.8
		add_child(_spawned_fire)
		_spawned_fire.ignite()


## Creates an [Area3D] sensor detecting bodies on layers 2, 3, 4, and 5.
func _setup_propagation_area() -> void:
	_propagation_area = Area3D.new()
	_propagation_area.name = "PropagationArea"
	_propagation_area.collision_layer = 0
	_propagation_area.collision_mask = PROPAGATION_PHYSICS_MASK

	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = propagation_radius
	col_shape.shape = sphere

	_propagation_area.add_child(col_shape)
	add_child(_propagation_area)

	_propagation_area.body_entered.connect(_on_propagation_body_entered)
	_propagation_area.body_exited.connect(_on_propagation_body_exited)


## Tracks newly entered combustible bodies within propagation radius.
func _on_propagation_body_entered(body: Node3D) -> void:
	if body == self:
		return
	if body is CombustibleObject and not _neighboring_targets.has(body):
		print("[CombustibleObject] Neighbor detected by ", name, ": ", body.name)
		_neighboring_targets.append(body)


## Removes exited bodies from heat propagation tracking list.
func _on_propagation_body_exited(body: Node3D) -> void:
	if body is CombustibleObject:
		print("[CombustibleObject] Neighbor left radius of ", name, ": ", body.name)
		_neighboring_targets.erase(body)


## Frees this node from the scene tree upon complete combustion.
func _destroy_burned_object() -> void:
	print("[CombustibleObject] Destroying burned body: ", name)
	burned_down.emit()
	queue_free()
