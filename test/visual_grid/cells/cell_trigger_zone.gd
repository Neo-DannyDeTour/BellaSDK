## Visual test cell verifying [BaseTriggerArea3D] detects player entry.
class_name CellTriggerZone
extends MechanicTestCell

## Trigger area instance under test.
var _trigger: BaseTriggerArea3D = null

## Mock player [CharacterBody3D] moved into the trigger volume.
var _mock_body: CharacterBody3D = null

## Tracks whether [signal BaseTriggerArea3D.player_entered] fired.
var _entered: bool = false


## Builds trigger volume and places mock player outside its bounds.
func _setup_cell() -> void:
	cell_title = "Trigger: Player Entry Zone"
	_entered = false

	_trigger = BaseTriggerArea3D.new()
	var trig_col: CollisionShape3D = CollisionShape3D.new()
	var trig_box: BoxShape3D = BoxShape3D.new()
	trig_box.size = Vector3(3.0, 2.5, 3.0)
	trig_col.shape = trig_box
	_trigger.add_child(trig_col)
	_trigger.trigger_size = Vector3(3.0, 2.5, 3.0)
	_trigger.show_in_game = true
	_trigger.position = Vector3(0.0, 1.25, 0.0)
	add_child(_trigger)
	_trigger.player_entered.connect(_on_player_entered)

	_mock_body = CharacterBody3D.new()
	_mock_body.add_to_group("player")
	_mock_body.collision_layer = CollisionLayers.MASK_PLAYER
	_mock_body.collision_mask = CollisionLayers.MASK_ENVIRONMENT
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(0.8, 1.8, 0.8)
	col.shape = shape
	_mock_body.add_child(col)
	_mock_body.position = Vector3(-4.0, 1.0, 0.0)
	add_child(_mock_body)

	await wait_frames(3)


## Moves mock player into the trigger area and verifies entry signal.
func _run_test() -> void:
	_mock_body.position = Vector3(0.0, 1.0, 0.0)
	var ok: bool = await wait_until(func() -> bool: return _entered, 2.0)
	assert_true(ok, "BaseTriggerArea3D must emit player_entered when player enters.")


## Cleans up trigger and mock player nodes.
func _teardown_cell() -> void:
	if is_instance_valid(_mock_body):
		_mock_body.queue_free()
	if is_instance_valid(_trigger):
		_trigger.queue_free()
	await wait_frames(1)


## Records trigger entry callback.
func _on_player_entered(_player: Node3D) -> void:
	_entered = true
