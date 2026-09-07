## Unit test suite validating ladder volumes, collision sizing, and mounting pipelines.
class_name TestLadder
extends GutTest

# Adjust path as needed
const LADDER_SCENE: PackedScene = preload("res://interactables/ladder.tscn")

var ladder: Ladder = null
var player: MockPlayer = null
var mock_env: MockEnvironmentComponent = null


func before_each() -> void:
	# Instantiate full ladder scene to ensure $Arrow and $CollisionShape3D exist
	ladder = LADDER_SCENE.instantiate() as Ladder
	add_child(ladder)

	player = MockPlayer.new()
	mock_env = MockEnvironmentComponent.new()
	mock_env.name = "MockEnvironmentComponent"
	player.environment_component = mock_env
	player.add_child(mock_env)
	add_child(player)


func after_each() -> void:
	if is_instance_valid(ladder):
		ladder.queue_free()
	if is_instance_valid(player):
		player.queue_free()


func test_ladder_size_updates_collision_shape() -> void:
	var target_size: Vector3 = Vector3(1.5, 8.0, 0.4)
	ladder.ladder_size = target_size

	var col_node: CollisionShape3D = ladder.get_node("CollisionShape3D") as CollisionShape3D
	var box_shape: BoxShape3D = col_node.shape as BoxShape3D

	assert_eq(box_shape.size, target_size, "Collision shape size must match ladder_size.")


func test_player_enters_ladder_forwards_to_environment() -> void:
	ladder._on_body_entered(player)

	assert_eq(
		mock_env.last_entered_ladder,
		ladder,
		"Player environment component should register entered ladder."
	)


func test_player_exits_ladder_forwards_to_environment() -> void:
	ladder._on_body_exited(player)

	assert_eq(
		mock_env.last_exited_ladder,
		ladder,
		"Player environment component should register exited ladder."
	)


func test_ladder_cooldown_blocks_reentry() -> void:
	mock_env.last_ladder = ladder
	mock_env.ladder_cooldown = 0.5
	mock_env.last_entered_ladder = null

	ladder._on_body_entered(player)

	assert_null(
		mock_env.last_entered_ladder,
		"Player should not re-enter the same ladder while cooldown is active."
	)
