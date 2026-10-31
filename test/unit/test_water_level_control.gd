## Unit tests verifying WaterBody floor-anchored level adjustments and button triggers.
class_name TestWaterLevelControl
extends GutTest

## Preloaded WaterBody packed scene.
const WATER_BODY_SCENE: PackedScene = preload("res://environment/water_body.tscn")

## Instance of WaterBody under test.
var water: WaterBody = null


## Sets up fresh WaterBody node and isolates test environment before each run.
func before_each() -> void:
	get_tree().paused = false
	var root: Window = get_tree().root
	for child: Node in root.find_children("*", "SmokeGrenadeProjectile", true, false):
		child.queue_free()
	for child: Node in root.find_children("*", "FogVolume", true, false):
		child.queue_free()

	var smoke_manager: Node = root.get_node_or_null("SmokeManager")
	if is_instance_valid(smoke_manager) and smoke_manager.has_method(&"clear_all"):
		smoke_manager.call(&"clear_all")

	water = WATER_BODY_SCENE.instantiate() as WaterBody
	water.position = Vector3(0.0, 10.0, 0.0)
	water.water_size = Vector3(10.0, 30.0, 10.0)
	water.level_change_duration = 0.1
	add_child_autofree(water)

	# Overwrite baseline to account for properties assigned prior to tree entrance
	water._default_position_y = water.position.y
	water._default_water_size_y = water.water_size.y


## Cleans up active references after each test.
func after_each() -> void:
	if is_instance_valid(water) and not water.is_queued_for_deletion():
		water.queue_free()
	water = null


## Awaits signal emission by waiting directly for the level tween to finish.
func _wait_for_transition(target_water: WaterBody) -> void:
	if (
		not target_water.is_level_transition_complete()
		and is_instance_valid(target_water._level_tween)
	):
		await target_water._level_tween.finished


## Tests baseline recording and floor anchoring when lowering water level.
func test_water_level_lowering_anchors_floor() -> void:
	assert_eq(water._default_position_y, 10.0, "Baseline position Y must match setup.")
	assert_eq(water._default_water_size_y, 30.0, "Baseline water_size.y must match setup.")

	var baseline_floor_y: float = water.position.y - (water.water_size.y * 0.5)
	assert_almost_eq(baseline_floor_y, -5.0, 0.001, "Baseline floor Y must be at -5.0m.")

	watch_signals(water)
	water.target_level_delta = -20.0
	water.power_on()

	assert_signal_emitted(water, "water_level_transition_started")

	await _wait_for_transition(water)
	assert_signal_emitted(water, "water_level_transition_finished")

	assert_almost_eq(water.water_size.y, 10.0, 0.01, "Water height should shrink by 20m to 10m.")
	assert_almost_eq(water.position.y, 0.0, 0.01, "Water center Y should drop by 10m to 0m.")

	var lowered_floor_y: float = water.position.y - (water.water_size.y * 0.5)
	assert_almost_eq(
		lowered_floor_y, baseline_floor_y, 0.01, "Floor Y must remain anchored at -5.0m."
	)

	var lowered_surface_y: float = water.position.y + (water.water_size.y * 0.5)
	assert_almost_eq(
		lowered_surface_y, 5.0, 0.01, "Surface Y must drop from 25.0m down to 5.0m (-20m)."
	)


## Tests toggle mode restoring baseline size and position on power_off.
func test_water_level_toggle_restores_baseline() -> void:
	water.water_level_mode = WaterBody.WaterLevelMode.TOGGLE
	water.target_level_delta = -20.0
	water.power_on()
	await _wait_for_transition(water)

	assert_almost_eq(water.water_size.y, 10.0, 0.01)

	water.power_off()
	await _wait_for_transition(water)

	assert_almost_eq(water.water_size.y, 30.0, 0.01, "Water height should restore to 30m.")
	assert_almost_eq(water.position.y, 10.0, 0.01, "Water position Y should restore to 10m.")


## Tests one-shot mode ignoring power_off restoration.
func test_water_level_one_shot_ignores_power_off() -> void:
	water.water_level_mode = WaterBody.WaterLevelMode.ONE_SHOT
	water.target_level_delta = -20.0
	water.power_on()
	await _wait_for_transition(water)

	assert_almost_eq(water.water_size.y, 10.0, 0.01)

	water.power_off()
	await wait_physics_frames(2)

	assert_almost_eq(water.water_size.y, 10.0, 0.01, "One-shot must not restore on power_off.")


## Tests safe depth clamping to 0.1m when delta exceeds available height.
func test_water_level_depth_clamping() -> void:
	water.target_level_delta = -50.0
	water.power_on()
	await _wait_for_transition(water)

	assert_almost_eq(water.water_size.y, 0.1, 0.01, "Water height must clamp to safe minimum 0.1m.")
	var expected_pos_y: float = 10.0 + ((0.1 - 30.0) * 0.5)
	assert_almost_eq(water.position.y, expected_pos_y, 0.01, "Position Y must anchor floor.")
