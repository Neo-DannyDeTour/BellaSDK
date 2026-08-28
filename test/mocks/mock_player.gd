## Test mock for Player assembling default stubs, bypassing hardware captures, and tracking damage.
class_name MockPlayer
extends Player

## Tracks the last damage value applied via [method take_damage].
var last_damage: int = 0

## Tracks the last heal value applied via [method heal].
var last_heal: int = 0


## Lifecycle initialization assembling mock components into the hierarchy.
func _init() -> void:
	var mock_loco: MockLocomotion = MockLocomotion.new()
	mock_loco.name = "MockLocomotion"
	locomotion_component = mock_loco
	add_child(mock_loco)

	var mock_menu: SystemMenuController = SystemMenuController.new()
	mock_menu.name = "MockSystemMenu"
	system_menu = mock_menu
	add_child(mock_menu)

	var mock_cam: CameraController = CameraController.new()
	mock_cam.name = "MockCameraController"
	camera_controller = mock_cam
	add_child(mock_cam)

	var mock_interact: DummyComponent = DummyComponent.new()
	mock_interact.name = "MockInteractionComponent"
	interaction_component = mock_interact
	add_child(mock_interact)

	var mock_env: DummyComponent = DummyComponent.new()
	mock_env.name = "MockEnvironmentComponent"
	environment_component = mock_env
	add_child(mock_env)

	var mock_stats: DummyComponent = DummyComponent.new()
	mock_stats.name = "MockStatsComponent"
	stats_component = mock_stats
	add_child(mock_stats)

	var components_container: Node = Node.new()
	components_container.name = "Components"
	add_child(components_container)

	var local_health: HealthComponent = HealthComponent.new()
	local_health.name = "HealthComponent"
	components_container.add_child(local_health)
	health_component = local_health


## Overridden mouse capture stub to prevent OS mouse capture during test runs.
func _capture_mouse() -> void:
	print("MockPlayer: _capture_mouse() skipped for automated testing.")


## Simulates player damage routing and records applied damage values.
## [param amount] Damage value to apply.
func take_damage(amount: int) -> void:
	print("MockPlayer: take_damage() called with: ", amount)
	last_damage = amount
	if is_instance_valid(health_component) and health_component.has_method("take_damage"):
		health_component.take_damage(amount)


## Simulates player healing routing and records applied healing values.
## [param amount] Health value to restore.
func heal(amount: int) -> void:
	print("MockPlayer: heal() called with: ", amount)
	last_heal = amount
	if is_instance_valid(health_component) and health_component.has_method("heal"):
		health_component.heal(amount)
