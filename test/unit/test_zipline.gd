## Unit test suite validating Zipline scene hierarchy, collision volumes, and grab kinematics.
class_name TestZipline
extends GutTest

## Preloaded zipline scene asset.
const ZIPLINE_SCENE: PackedScene = preload("res://player/zipline.tscn")

## Active zipline instance under test.
var zipline: Zipline = null

## Mock player body used across interaction tests.
var mock_player: MockZiplinePlayer = null


## Mock physics body implementing player zipline interaction interface.
class MockZiplinePlayer:
	extends CharacterBody3D

	## Active zipline node passed during grab.
	var grabbed_zipline: Node3D = null

	## Cable start position passed during grab.
	var grabbed_start: Vector3 = Vector3.ZERO

	## Cable end position passed during grab.
	var grabbed_end: Vector3 = Vector3.ZERO

	## Active cooldown simulation flag.
	var cooldown_active: bool = false

	## Grounded state override flag.
	var on_floor_override: bool = false

	## Reports simulated grounded status for testing.
	@warning_ignore("native_method_override")
	func is_on_floor() -> bool:
		return on_floor_override

	## Reports simulated cooldown status to zipline.
	func has_zipline_cooldown() -> bool:
		return cooldown_active

	## Records cable attachment arguments from zipline.
	func _on_zipline_grabbed(z_node: Node3D, s_pos: Vector3, e_pos: Vector3) -> void:
		print("MockZiplinePlayer: _on_zipline_grabbed() called.")
		grabbed_zipline = z_node
		grabbed_start = s_pos
		grabbed_end = e_pos


## Instantiates fresh Zipline and MockZiplinePlayer before each test.
func before_each() -> void:
	print("TestZipline: before_each() setup started.")
	zipline = ZIPLINE_SCENE.instantiate() as Zipline
	add_child_autofree(zipline)

	mock_player = MockZiplinePlayer.new()
	add_child_autofree(mock_player)


## Verifies scene node hierarchy, interactable groups, and collision layers.
func test_zipline_scene_nodes_and_layers() -> void:
	print("TestZipline: test_zipline_scene_nodes_and_layers() called.")
	assert_not_null(zipline.interact_component, "InteractComponent must be present.")
	assert_not_null(zipline.highlight_component, "HighlightComponent must be present.")
	assert_not_null(zipline.interact_label, "Interact Label3D must be present.")
	assert_not_null(zipline.proximity_area, "ProximityArea must be present.")
	assert_true(zipline.is_in_group(Zipline.GROUP_INTERACTABLE), "Must be in interactable group.")

	var interact_body: StaticBody3D = zipline.get_node_or_null("InteractArea") as StaticBody3D
	assert_not_null(interact_body, "InteractArea StaticBody3D must exist.")
	assert_eq(interact_body.collision_layer, 5, "InteractArea must have collision layer 5.")

	assert_eq(zipline.proximity_area.collision_layer, 0, "ProximityArea layer should be 0.")
	assert_eq(zipline.proximity_area.collision_mask, 2, "ProximityArea mask should be 2 (Player).")


## Verifies cable mesh and cylinder collision shapes dynamically resize along curve points.
func test_zipline_geometry_generation() -> void:
	print("TestZipline: test_zipline_geometry_generation() called.")
	var curve: Curve3D = zipline.curve
	curve.set_point_position(0, Vector3.ZERO)
	curve.set_point_position(1, Vector3(0.0, 0.0, 10.0))
	zipline._update_cable()

	var wire_mesh: MeshInstance3D = zipline.get_node_or_null("WireMesh") as MeshInstance3D
	assert_not_null(wire_mesh, "WireMesh must exist.")
	var cyl_mesh: CylinderMesh = wire_mesh.mesh as CylinderMesh
	assert_not_null(cyl_mesh, "WireMesh must use CylinderMesh.")
	assert_almost_eq(cyl_mesh.height, 10.0, 0.01, "Mesh height must match distance.")

	var interact_shape: CollisionShape3D = (
		zipline.get_node_or_null("InteractArea/CollisionShape3D") as CollisionShape3D
	)
	assert_not_null(interact_shape, "InteractArea CollisionShape3D must exist.")
	var interact_cyl: CylinderShape3D = interact_shape.shape as CylinderShape3D
	assert_not_null(interact_cyl, "Interact shape must be CylinderShape3D.")
	assert_almost_eq(interact_cyl.radius, 0.25, 0.001, "Interact radius must be 0.25m.")
	assert_almost_eq(interact_cyl.height, 10.0, 0.01, "Interact shape height must match distance.")

	var prox_shape: CollisionShape3D = (
		zipline.get_node_or_null("ProximityArea/CollisionShape3D") as CollisionShape3D
	)
	assert_not_null(prox_shape, "ProximityArea CollisionShape3D must exist.")
	var prox_cyl: CylinderShape3D = prox_shape.shape as CylinderShape3D
	assert_not_null(prox_cyl, "Proximity shape must be CylinderShape3D.")
	assert_almost_eq(prox_cyl.radius, 0.65, 0.001, "Proximity radius must be 0.65m.")
	assert_almost_eq(prox_cyl.height, 10.0, 0.01, "Proximity shape height must match distance.")


## Verifies manual interact_with triggers cable attachment on character.
func test_crosshair_interact_mount() -> void:
	print("TestZipline: test_crosshair_interact_mount() called.")
	zipline.interact_with(mock_player)

	assert_true(zipline.player_on_zipline, "player_on_zipline must be true after interact.")
	assert_eq(zipline.current_player, mock_player, "current_player must match mock_player.")
	assert_eq(mock_player.grabbed_zipline, zipline, "Player must receive zipline node reference.")


## Verifies airborne body entering proximity area triggers deferred auto-grab.
func test_midair_proximity_auto_grab() -> void:
	print("TestZipline: test_midair_proximity_auto_grab() called.")
	mock_player.cooldown_active = false
	assert_false(mock_player.is_on_floor(), "Player should be airborne by default.")

	zipline._on_proximity_body_entered(mock_player)
	await get_tree().process_frame

	assert_true(zipline.player_on_zipline, "Airborne player entering area must be mounted.")
	assert_eq(zipline.current_player, mock_player, "Current player must be mock_player.")
	assert_eq(mock_player.grabbed_zipline, zipline, "Player grab callback must be triggered.")


## Verifies cooldown timer rejects airborne proximity auto-grab.
func test_cooldown_rejects_auto_grab() -> void:
	print("TestZipline: test_cooldown_rejects_auto_grab() called.")
	mock_player.cooldown_active = true

	zipline._on_proximity_body_entered(mock_player)
	await get_tree().process_frame

	assert_false(zipline.player_on_zipline, "Player on cooldown must not auto-grab.")
	assert_null(mock_player.grabbed_zipline, "Player grab callback must not be invoked.")


## Verifies grounded player in proximity area is not auto-mounted without manual interact.
func test_grounded_rejects_auto_grab() -> void:
	print("TestZipline: test_grounded_rejects_auto_grab() called.")
	mock_player.on_floor_override = true
	mock_player.cooldown_active = false

	zipline._on_proximity_body_entered(mock_player)
	await get_tree().process_frame

	assert_false(zipline.player_on_zipline, "Grounded player must not auto-grab.")
	assert_null(mock_player.grabbed_zipline, "Grounded player must not receive grab call.")


## Verifies releasing player clears references and resets flags.
func test_on_player_released_cleans_up() -> void:
	print("TestZipline: test_on_player_released_cleans_up() called.")
	zipline.force_grab_zipline(mock_player)
	assert_true(zipline.player_on_zipline, "Must be mounted.")

	zipline.on_player_released()
	assert_false(zipline.player_on_zipline, "player_on_zipline must be reset to false.")
	assert_null(zipline.current_player, "current_player must be cleared.")
