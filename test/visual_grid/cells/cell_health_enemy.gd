## Visual test cell verifying enemy [HealthComponent] damage and death transitions.
class_name CellHealthEnemy
extends MechanicTestCell

## Preloaded enemy scene containing a [HealthComponent].
const ENEMY_SCENE: PackedScene = preload("res://enemies/evil_goon.tscn")

## Spawned enemy instance under test.
var _enemy: Node3D = null

## Cached [HealthComponent] resolved via [NodeQuery].
var _health: HealthComponent = null

## Tracks whether [signal HealthComponent.died] emitted.
var _died: bool = false


## Spawns enemy on the pad and connects to its [HealthComponent].
func _setup_cell() -> void:
	cell_title = "Enemy: Health & Death"
	_died = false
	_enemy = ENEMY_SCENE.instantiate() as Node3D
	_enemy.position = Vector3(0.0, 0.5, 0.0)
	add_child(_enemy)
	await wait_frames(2)

	var found: Node = NodeQuery.find_first_child_of_type(_enemy, HealthComponent)
	if found is HealthComponent:
		_health = found
		_health.died.connect(_on_enemy_died)


## Applies partial then lethal damage and verifies HP drop and death signal.
func _run_test() -> void:
	if not assert_true(is_instance_valid(_health), "Enemy must have HealthComponent."):
		return

	var start_hp: int = _health.current_health
	_health.take_damage(20)
	await wait_frames(2)
	assert_true(_health.current_health < start_hp, "Health must decrease after take_damage.")

	_health.take_damage(9999)
	var ok: bool = await wait_until(func() -> bool: return _died, 2.0)
	assert_true(ok, "HealthComponent must emit died on lethal damage.")


## Cleans up spawned enemy instance.
func _teardown_cell() -> void:
	if is_instance_valid(_enemy):
		_enemy.queue_free()
	await wait_frames(1)


## Records enemy death callback.
func _on_enemy_died() -> void:
	_died = true
