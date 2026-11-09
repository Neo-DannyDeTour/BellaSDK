@tool
class_name BuildTestWorld
extends EditorScript
## Editor utility that auto-generates missing test chunks, assembles the complete
## test_world.tscn hierarchy with wired exports, and opens it in the editor.

## Target directory for the generated test world scene.
const TEST_DIR: String = "res://test"

## Output file path for the assembled test world scene.
const SCENE_PATH: String = "res://test/test_world.tscn"

## Sentinel chunk path checked to verify if test chunks exist on disk.
const ORIGIN_CHUNK_PATH: String = "res://world/chunks/chunk_0_0.tscn"

## Preloaded default player scene resource.
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

## World-space dimensions of the 5x5 km base ground box.
const GROUND_SIZE: Vector3 = Vector3(5000.0, 1.0, 5000.0)

## Local Y offset placing the top surface of the 1m thick ground at Y = 0.
const GROUND_OFFSET: Vector3 = Vector3(0.0, -0.5, 0.0)

## Directional light Euler rotation in degrees for scene contrast.
const SUN_ROTATION_DEG: Vector3 = Vector3(-60.0, 45.0, 0.0)

## Initial player spawn position at the center of chunk (0, 0).
const PLAYER_SPAWN_POS: Vector3 = Vector3(125.0, 2.0, 125.0)

## Polling interval in seconds for the [ChunkManager] I/O timer.
const IO_POLL_INTERVAL: float = 0.05

## Polling interval in seconds for the [PlayerChunkTracker] boundary timer.
const TRACKER_POLL_INTERVAL: float = 0.2

## Dark gray albedo color applied to the 5x5 km base ground mesh.
const COLOR_GROUND: Color = Color(0.12, 0.13, 0.15, 1.0)


## Entry point executed via File -> Run in the Godot Editor.
func _run() -> void:
	if not ResourceLoader.exists(ORIGIN_CHUNK_PATH):
		var chunk_gen: GenerateTestChunks = GenerateTestChunks.new()
		chunk_gen._run()

	DirAccess.make_dir_recursive_absolute(TEST_DIR)

	var root: Node3D = Node3D.new()
	root.name = "TestWorld"

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = SUN_ROTATION_DEG
	sun.shadow_enabled = true
	root.add_child(sun)
	sun.owner = root

	_build_base_ground(root)

	var dyn_container: Node3D = Node3D.new()
	dyn_container.name = "DynamicContainer"
	root.add_child(dyn_container)
	dyn_container.owner = root

	var chunk_mgr: ChunkManager = _build_chunk_manager(root, dyn_container)
	_build_player(root)
	_build_hud(root, chunk_mgr, dyn_container)

	var packed: PackedScene = PackedScene.new()
	var err: Error = packed.pack(root)
	root.free()

	if err != OK:
		push_error("Failed to pack TestWorld scene: ", err)
		return

	var save_err: Error = ResourceSaver.save(packed, SCENE_PATH)
	if save_err != OK:
		push_error("Failed to save TestWorld scene: ", save_err)
		return

	print("Saved and opening test world scene: ", SCENE_PATH)
	if Engine.is_editor_hint():
		EditorInterface.open_scene_from_path(SCENE_PATH)


## Creates and attaches the 5000x1x5000m static environment floor to [param root].
func _build_base_ground(root: Node3D) -> void:
	var ground: StaticBody3D = StaticBody3D.new()
	ground.name = "BaseGround"
	ground.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	ground.collision_mask = CollisionLayers.MASK_NONE
	root.add_child(ground)
	ground.owner = root

	var col_shape: BoxShape3D = BoxShape3D.new()
	col_shape.size = GROUND_SIZE
	var col_node: CollisionShape3D = CollisionShape3D.new()
	col_node.name = "CollisionShape3D"
	col_node.shape = col_shape
	col_node.position = GROUND_OFFSET
	ground.add_child(col_node)
	col_node.owner = root

	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = GROUND_SIZE
	var ground_mat: StandardMaterial3D = StandardMaterial3D.new()
	ground_mat.albedo_color = COLOR_GROUND
	ground_mat.roughness = 0.95

	var mesh_node: MeshInstance3D = MeshInstance3D.new()
	mesh_node.name = "MeshInstance3D"
	mesh_node.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
	mesh_node.mesh = box_mesh
	mesh_node.material_override = ground_mat
	mesh_node.position = GROUND_OFFSET
	ground.add_child(mesh_node)
	mesh_node.owner = root


## Creates [ChunkManager] with its child [Timer] and wires [param dyn_container].
func _build_chunk_manager(root: Node3D, dyn_container: Node3D) -> ChunkManager:
	var chunk_mgr: ChunkManager = ChunkManager.new()
	chunk_mgr.name = "ChunkManager"
	root.add_child(chunk_mgr)
	chunk_mgr.owner = root

	var io_timer: Timer = Timer.new()
	io_timer.name = "IOTimer"
	io_timer.wait_time = IO_POLL_INTERVAL
	io_timer.one_shot = false
	chunk_mgr.add_child(io_timer)
	io_timer.owner = root

	chunk_mgr.dynamic_container = dyn_container
	return chunk_mgr


## Instantiates default [Player], sets spawn position, and attaches [PlayerChunkTracker].
func _build_player(root: Node3D) -> void:
	var player: Node3D = PLAYER_SCENE.instantiate() as Node3D
	player.name = "Player"
	player.position = PLAYER_SPAWN_POS
	root.add_child(player)
	player.owner = root

	var tracker: PlayerChunkTracker = PlayerChunkTracker.new()
	tracker.name = "PlayerChunkTracker"
	player.add_child(tracker)
	tracker.owner = root

	var poll_timer: Timer = Timer.new()
	poll_timer.name = "PollTimer"
	poll_timer.wait_time = TRACKER_POLL_INTERVAL
	poll_timer.one_shot = false
	poll_timer.autostart = true
	tracker.add_child(poll_timer)
	poll_timer.owner = root


## Creates [CanvasLayer] and [ChunkDebugHud] wired to [param chunk_mgr].
func _build_hud(root: Node3D, chunk_mgr: ChunkManager, dyn_container: Node3D) -> void:
	var hud_layer: CanvasLayer = CanvasLayer.new()
	hud_layer.name = "HUDLayer"
	root.add_child(hud_layer)
	hud_layer.owner = root

	var hud: ChunkDebugHud = ChunkDebugHud.new()
	hud.name = "ChunkDebugHud"
	hud_layer.add_child(hud)
	hud.owner = root

	hud.chunk_manager = chunk_mgr
	hud.dynamic_container = dyn_container
