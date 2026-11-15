## Visual test cell verifying [BreakableCrate] shatters and emits broken signal on hit.
class_name CellCrateBarrel
extends MechanicTestCell

## Preloaded breakable crate scene.
const CRATE_SCENE: PackedScene = preload("res://interactables/breakable_crate.tscn")

## Spawned crate instance under test.
var _crate: Node3D = null

## Tracks whether [signal BreakableCrate.broken] fired.
var _was_broken: bool = false


## Spawns breakable crate at the center of the test pad.
func _setup_cell() -> void:
	cell_title = "Interactable: Breakable Crate"
	_was_broken = false
	_crate = CRATE_SCENE.instantiate() as Node3D
	_crate.position = Vector3(0.0, 0.6, 0.0)
	add_child(_crate)
	if _crate.has_signal("broken"):
		_crate.connect("broken", _on_crate_broken)
	await wait_frames(2)


## Applies lethal hit damage to the crate and asserts break state.
func _run_test() -> void:
	_crate.call("apply_hit", 100.0, _crate.global_position, Vector3.UP * 2.0)
	var ok: bool = await wait_until(func() -> bool: return _was_broken, 2.0)
	assert_true(ok, "BreakableCrate must emit broken signal on lethal hit.")


## Cleans up spawned crate instance.
func _teardown_cell() -> void:
	if is_instance_valid(_crate):
		_crate.queue_free()
	await wait_frames(1)


## Signal callback recording crate destruction.
func _on_crate_broken(_world_pos: Vector3) -> void:
	_was_broken = true
