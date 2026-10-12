@tool
## Spawns horror silhouettes behind the player that vanish instantly when turned toward.
## Designed as a standalone [Area3D] level design trigger zone in Godot 4.
class_name SpookEncounter
extends Area3D

## Emitted when the spook spawns. Passes [param spawn_pos] world position.
signal spook_spawned(spawn_pos: Vector3)

## Emitted when the spook vanishes after the player turns around.
signal spook_vanished

## Physics collision layer for Environment geometry (Layer 1).
const PHYSICS_LAYER_ENVIRONMENT: int = 1

## Physics collision layer for Player character detection (Layer 2).
const PHYSICS_LAYER_PLAYER: int = 2

@export_group("Trigger Volume")

## 3D boundary dimensions of the trigger volume and physics collision box.
@export var trigger_size: Vector3 = Vector3(4.0, 2.5, 4.0):
	set(value):
		trigger_size = value
		if is_inside_tree():
			_rebuild_visuals()

## Volumetric inner fill color and transparency for the editor gizmo.
@export var trigger_color: Color = Color(0.8, 0.1, 0.1, 0.15):
	set(value):
		trigger_color = value
		if is_inside_tree():
			_update_materials()

## Wireframe outline color for the bounding cage in the editor.
@export var outline_color: Color = Color(1.0, 0.2, 0.2, 0.85):
	set(value):
		outline_color = value
		if is_inside_tree():
			_update_materials()

## Renders gizmo wireframes through obstructing solid geometry.
@export var x_ray_mode: bool = false:
	set(value):
		x_ray_mode = value
		if is_inside_tree():
			_update_materials()

## Displays a forward-facing orientation arrow along local -Z.
@export var show_orientation: bool = true:
	set(value):
		show_orientation = value
		if is_inside_tree():
			_update_arrow()

## Shows metric dimension measurements on the 3D billboard label.
@export var show_metric_dimensions: bool = true:
	set(value):
		show_metric_dimensions = value
		if is_inside_tree():
			_update_text()

## Debug text displayed above the encounter area in the editor.
@export var trigger_text: String = "SPOOK TRIGGER":
	set(value):
		trigger_text = value
		if is_inside_tree():
			_update_text()

## Keeps editor wireframes and gizmos visible during runtime playtests.
@export var show_gizmo_in_game: bool = false:
	set(value):
		show_gizmo_in_game = value
		if is_inside_tree():
			_update_visibility()

@export_group("Spook Visuals & Variety")

## Primary texture displaying the horror entity silhouette.
@export var spook_texture: Texture2D:
	set(value):
		spook_texture = value
		if is_inside_tree():
			_update_sprite_properties()

## Optional alternate textures chosen at random for encounter variety.
@export var alternate_textures: Array[Texture2D] = []

## Size of one sprite pixel in 3D meters, controlling base scale.
@export var pixel_size: float = 0.005:
	set(value):
		pixel_size = value
		if is_inside_tree():
			_update_sprite_properties()

## Minimum random scale multiplier applied to the spawned sprite.
@export_range(0.2, 2.0, 0.05) var min_scale: float = 0.85

## Maximum random scale multiplier applied to the spawned sprite.
@export_range(0.5, 3.0, 0.05) var max_scale: float = 1.35

## Randomly flips the silhouette horizontally for visual variety.
@export var random_flip_h: bool = true

## Applies subtle random brightness variance to the silhouette.
@export var randomize_tint: bool = true

## Height offset in meters added above the detected floor position.
@export var floor_offset: float = 0.0:
	set(value):
		floor_offset = value
		if is_inside_tree():
			_update_sprite_properties()

## Displays the preview sprite in the 3D editor viewport.
@export var preview_spook_in_editor: bool = true:
	set(value):
		preview_spook_in_editor = value
		if is_inside_tree():
			_update_sprite_visibility()

## Renders sprite unshaded so it remains readable in darkness.
@export var unshaded_sprite: bool = true:
	set(value):
		unshaded_sprite = value
		if is_inside_tree():
			_update_sprite_properties()

## Enables double-sided shadow casting on the silhouette sprite.
@export var enable_shadow_casting: bool = true:
	set(value):
		enable_shadow_casting = value
		if is_inside_tree():
			_update_sprite_properties()

@export_group("Behind Spawn & Gaze Despawn")

## Distance in meters directly behind the player's back to spawn.
@export_range(1.0, 10.0, 0.25) var spawn_behind_distance: float = 3.0

## Forward camera view alignment threshold (dot product) triggering despawn.
@export_range(-0.2, 0.8, 0.05) var turn_around_threshold: float = 0.15

## Delay in seconds after entering trigger before spawning behind the player.
@export_range(0.0, 5.0, 0.1) var spawn_delay: float = 0.5

@export_group("Spawn Parameters")

## Probability between 0.0 and 1.0 of spawning on trigger entry.
@export_range(0.0, 1.0, 0.05) var spawn_chance: float = 1.0

## Destroys this encounter node after vanishing to prevent re-trigger.
@export var one_shot: bool = true

var _collision_shape: CollisionShape3D
var _fill_mesh_node: MeshInstance3D
var _wireframe_node: MeshInstance3D
var _arrow_node: MeshInstance3D
var _label_node: Label3D
var _spook_sprite: Sprite3D
var _notifier: VisibleOnScreenNotifier3D

var _player_camera: Camera3D
var _tracked_player: Node3D
var _spawn_timer: float = 0.0
var _is_active: bool = false
var _has_triggered: bool = false
var _active_lifetime: float = 0.0


## Initializes layers, child nodes, gizmo meshes, and collision links.
func _ready() -> void:
	print("SpookEncounter: Initializing encounter node -> ", name)
	collision_layer = 0
	collision_mask = PHYSICS_LAYER_PLAYER

	_ensure_child_nodes()
	_rebuild_visuals()
	_update_visibility()
	_update_sprite_visibility()

	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)


## Checks rear spawn readiness and detects turn-around gaze each frame.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if not is_instance_valid(_player_camera):
		_player_camera = get_viewport().get_camera_3d()
		if not is_instance_valid(_player_camera):
			return

	if _is_active:
		_active_lifetime += delta
		# Grace period: ignore despawn for the first 0.35s to allow shadow rendering
		if _active_lifetime > 0.35 and _is_player_looking_at_spook():
			print("SpookEncounter: Player turned around! Despawning instantly.")
			_despawn_spook()
		return

	if is_instance_valid(_tracked_player) and not (_has_triggered and one_shot):
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			var roll: float = randf()
			if roll <= spawn_chance:
				_has_triggered = true
				_spawn_spook_behind(_tracked_player)
			else:
				print("SpookEncounter: Spawn roll missed (", roll, " > ", spawn_chance, ").")
				_tracked_player = null


## Instantiates collision, sprite, notifier, and gizmo nodes if missing.
func _ensure_child_nodes() -> void:
	print("SpookEncounter: Ensuring presence of required child nodes.")
	if not is_instance_valid(_collision_shape):
		_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
		if not is_instance_valid(_collision_shape):
			_collision_shape = CollisionShape3D.new()
			_collision_shape.name = "CollisionShape3D"
			add_child(_collision_shape)

	if not is_instance_valid(_spook_sprite):
		_spook_sprite = get_node_or_null("Sprite3D") as Sprite3D
		if not is_instance_valid(_spook_sprite):
			_spook_sprite = Sprite3D.new()
			_spook_sprite.name = "Sprite3D"
			add_child(_spook_sprite)

	if not is_instance_valid(_notifier):
		_notifier = get_node_or_null("VisibleNotifier") as VisibleOnScreenNotifier3D
		if not is_instance_valid(_notifier) and is_instance_valid(_spook_sprite):
			_notifier = (
				_spook_sprite.get_node_or_null("VisibleNotifier") as VisibleOnScreenNotifier3D
			)
		if not is_instance_valid(_notifier):
			_notifier = VisibleOnScreenNotifier3D.new()
			_notifier.name = "VisibleNotifier"
			add_child(_notifier)

	if not is_instance_valid(_fill_mesh_node):
		_fill_mesh_node = get_node_or_null("FillMesh") as MeshInstance3D
		if not is_instance_valid(_fill_mesh_node):
			_fill_mesh_node = MeshInstance3D.new()
			_fill_mesh_node.name = "FillMesh"
			add_child(_fill_mesh_node)

	if not is_instance_valid(_wireframe_node):
		_wireframe_node = get_node_or_null("Wireframe") as MeshInstance3D
		if not is_instance_valid(_wireframe_node):
			_wireframe_node = MeshInstance3D.new()
			_wireframe_node.name = "Wireframe"
			add_child(_wireframe_node)

	if not is_instance_valid(_arrow_node):
		_arrow_node = get_node_or_null("DirectionArrow") as MeshInstance3D
		if not is_instance_valid(_arrow_node):
			_arrow_node = MeshInstance3D.new()
			_arrow_node.name = "DirectionArrow"
			add_child(_arrow_node)

	if not is_instance_valid(_label_node):
		_label_node = get_node_or_null("VisualizerLabel") as Label3D
		if not is_instance_valid(_label_node):
			_label_node = Label3D.new()
			_label_node.name = "VisualizerLabel"
			_label_node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_label_node.no_depth_test = true
			add_child(_label_node)


## Synchronizes collision box, fill meshes, wireframes, and labels.
func _rebuild_visuals() -> void:
	print("SpookEncounter: Rebuilding gizmo visuals.")
	_ensure_child_nodes()
	_update_collision_shape()
	_update_fill_mesh()
	_update_wireframe_mesh()
	_update_materials()
	_update_arrow()
	_update_text()
	_update_sprite_properties()


## Updates the [BoxShape3D] resource size on [CollisionShape3D].
func _update_collision_shape() -> void:
	print("SpookEncounter: Updating collision shape.")
	if not is_instance_valid(_collision_shape):
		return
	var box: BoxShape3D = _collision_shape.shape as BoxShape3D
	if not is_instance_valid(box):
		box = BoxShape3D.new()
		_collision_shape.shape = box
	box.size = trigger_size


## Updates dimensions of the inner volumetric [BoxMesh] visualizer.
func _update_fill_mesh() -> void:
	print("SpookEncounter: Updating fill mesh.")
	if not is_instance_valid(_fill_mesh_node):
		return
	var box_mesh: BoxMesh = _fill_mesh_node.mesh as BoxMesh
	if not is_instance_valid(box_mesh):
		box_mesh = BoxMesh.new()
		_fill_mesh_node.mesh = box_mesh
	box_mesh.size = trigger_size


## Rebuilds the wireframe cage using [ImmediateMesh] line primitives.
func _update_wireframe_mesh() -> void:
	print("SpookEncounter: Updating wireframe mesh lines.")
	if not is_instance_valid(_wireframe_node):
		return
	var imm_mesh: ImmediateMesh = ImmediateMesh.new()
	var half: Vector3 = trigger_size * 0.5
	imm_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_draw_line(imm_mesh, Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z))
	_draw_line(imm_mesh, Vector3(half.x, -half.y, -half.z), Vector3(half.x, -half.y, half.z))
	_draw_line(imm_mesh, Vector3(half.x, -half.y, half.z), Vector3(-half.x, -half.y, half.z))
	_draw_line(imm_mesh, Vector3(-half.x, -half.y, half.z), Vector3(-half.x, -half.y, -half.z))
	_draw_line(imm_mesh, Vector3(-half.x, half.y, -half.z), Vector3(half.x, half.y, -half.z))
	_draw_line(imm_mesh, Vector3(half.x, half.y, -half.z), Vector3(half.x, half.y, half.z))
	_draw_line(imm_mesh, Vector3(half.x, half.y, half.z), Vector3(-half.x, half.y, half.z))
	_draw_line(imm_mesh, Vector3(-half.x, half.y, half.z), Vector3(-half.x, half.y, -half.z))
	_draw_line(imm_mesh, Vector3(-half.x, -half.y, -half.z), Vector3(-half.x, half.y, -half.z))
	_draw_line(imm_mesh, Vector3(half.x, -half.y, -half.z), Vector3(half.x, half.y, -half.z))
	_draw_line(imm_mesh, Vector3(half.x, -half.y, half.z), Vector3(half.x, half.y, half.z))
	_draw_line(imm_mesh, Vector3(-half.x, -half.y, half.z), Vector3(-half.x, half.y, half.z))
	imm_mesh.surface_end()
	_wireframe_node.mesh = imm_mesh


## Appends two vertex points forming a line segment to [ImmediateMesh].
func _draw_line(target_mesh: ImmediateMesh, from: Vector3, to: Vector3) -> void:
	target_mesh.surface_add_vertex(from)
	target_mesh.surface_add_vertex(to)


## Updates unshaded materials, colors, and depth testing on gizmos.
func _update_materials() -> void:
	print("SpookEncounter: Updating gizmo materials.")
	if is_instance_valid(_fill_mesh_node) and _fill_mesh_node.mesh != null:
		var fill_mat: StandardMaterial3D = StandardMaterial3D.new()
		fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		fill_mat.albedo_color = trigger_color
		fill_mat.no_depth_test = x_ray_mode
		_fill_mesh_node.set_surface_override_material(0, fill_mat)

	if is_instance_valid(_wireframe_node) and _wireframe_node.mesh != null:
		var wire_mat: StandardMaterial3D = StandardMaterial3D.new()
		wire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wire_mat.albedo_color = outline_color
		wire_mat.no_depth_test = x_ray_mode
		_wireframe_node.set_surface_override_material(0, wire_mat)


## Constructs a local -Z directional gizmo arrow using [ImmediateMesh].
func _update_arrow() -> void:
	print("SpookEncounter: Updating orientation arrow.")
	if not is_instance_valid(_arrow_node):
		return
	_arrow_node.visible = show_orientation
	if not show_orientation:
		return

	var arrow_mesh: ImmediateMesh = ImmediateMesh.new()
	var forward_len: float = (trigger_size.z * 0.5) + 0.8
	var head_len: float = 0.35
	var head_width: float = 0.2

	arrow_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_draw_line(arrow_mesh, Vector3.ZERO, Vector3(0.0, 0.0, -forward_len))
	var tip: Vector3 = Vector3(0.0, 0.0, -forward_len)
	_draw_line(arrow_mesh, tip, Vector3(-head_width, 0.0, -forward_len + head_len))
	_draw_line(arrow_mesh, tip, Vector3(head_width, 0.0, -forward_len + head_len))
	_draw_line(arrow_mesh, tip, Vector3(0.0, head_width, -forward_len + head_len))
	_draw_line(arrow_mesh, tip, Vector3(0.0, -head_width, -forward_len + head_len))
	arrow_mesh.surface_end()
	_arrow_node.mesh = arrow_mesh

	var arrow_mat: StandardMaterial3D = StandardMaterial3D.new()
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_mat.albedo_color = outline_color
	arrow_mat.no_depth_test = x_ray_mode
	_arrow_node.set_surface_override_material(0, arrow_mat)


## Formats and positions the 3D billboard label above the trigger.
func _update_text() -> void:
	print("SpookEncounter: Updating billboard label text.")
	if not is_instance_valid(_label_node):
		return
	var text_output: String = trigger_text
	if show_metric_dimensions:
		text_output += (
			"\n[%.1fm × %.1fm × %.1fm]" % [trigger_size.x, trigger_size.y, trigger_size.z]
		)
	_label_node.text = text_output
	_label_node.position = Vector3(0.0, (trigger_size.y * 0.5) + 0.5, 0.0)


## Configures billboard, pixel size, shadow casting, and preview position.
func _update_sprite_properties() -> void:
	print("SpookEncounter: Configuring sprite parameters and shadow modes.")
	if not is_instance_valid(_spook_sprite):
		return

	_spook_sprite.texture = spook_texture
	_spook_sprite.pixel_size = pixel_size
	_spook_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_spook_sprite.double_sided = true
	_spook_sprite.shaded = not unshaded_sprite

	# Shadow and cutout requirements for Godot 4:
	_spook_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_spook_sprite.alpha_scissor_threshold = 0.5
	_spook_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED

	var half_y: float = trigger_size.y * 0.5
	var sprite_h: float = 2.0
	if spook_texture != null:
		sprite_h = float(spook_texture.get_height()) * pixel_size
	var base_y: float = -half_y + (sprite_h * 0.5) + floor_offset

	if Engine.is_editor_hint():
		_spook_sprite.top_level = false
		_spook_sprite.position = Vector3(0.0, base_y, 0.0)
		_spook_sprite.scale = Vector3.ONE
		_spook_sprite.flip_h = false
		_spook_sprite.modulate = Color.WHITE


## Updates visibility of fill meshes, wireframes, arrows, and labels.
func _update_visibility() -> void:
	print("SpookEncounter: Updating gizmo element visibility.")
	var is_editor: bool = Engine.is_editor_hint()
	var gizmo_visible: bool = is_editor or show_gizmo_in_game
	if is_instance_valid(_fill_mesh_node):
		_fill_mesh_node.visible = gizmo_visible
	if is_instance_valid(_wireframe_node):
		_wireframe_node.visible = gizmo_visible
	if is_instance_valid(_arrow_node):
		_arrow_node.visible = gizmo_visible and show_orientation
	if is_instance_valid(_label_node):
		_label_node.visible = gizmo_visible


## Toggles sprite visibility between editor preview and active state.
func _update_sprite_visibility() -> void:
	print("SpookEncounter: Updating sprite visibility toggle.")
	if not is_instance_valid(_spook_sprite):
		return
	if Engine.is_editor_hint():
		_spook_sprite.visible = preview_spook_in_editor
	else:
		_spook_sprite.visible = _is_active


## Raycasts downward onto Environment Layer 1 to find floor height.
func _find_floor_position(candidate_pos: Vector3) -> Vector3:
	print("SpookEncounter: Raycasting floor height at -> ", candidate_pos)
	var world: World3D = get_world_3d()
	if not is_instance_valid(world):
		return candidate_pos

	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if not is_instance_valid(space_state):
		return candidate_pos

	var ray_top: Vector3 = candidate_pos + Vector3(0.0, 2.0, 0.0)
	var ray_bottom: Vector3 = candidate_pos - Vector3(0.0, 8.0, 0.0)

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_top, ray_bottom, PHYSICS_LAYER_ENVIRONMENT
	)
	var hit: Dictionary = space_state.intersect_ray(query)
	if not hit.is_empty():
		var raw_pos: Variant = hit.get(&"position")
		if raw_pos is Vector3:
			var hit_pos: Vector3 = raw_pos
			print("SpookEncounter: Floor surface detected at -> ", hit_pos)
			return hit_pos

	print("SpookEncounter: Floor raycast missed. Falling back to trigger bottom.")
	return Vector3(candidate_pos.x, global_position.y - (trigger_size.y * 0.5), candidate_pos.z)


## Computes spawn position behind player back avoiding obstacle collision.
func _calculate_behind_spawn_position(player_node: Node3D) -> Vector3:
	print("SpookEncounter: Calculating rear spawn location behind player.")
	var cam_fwd: Vector3 = -_player_camera.global_transform.basis.z
	var planar_fwd: Vector3 = Vector3(cam_fwd.x, 0.0, cam_fwd.z)
	if planar_fwd.is_zero_approx():
		planar_fwd = -player_node.global_transform.basis.z
		planar_fwd = Vector3(planar_fwd.x, 0.0, planar_fwd.z)
	planar_fwd = planar_fwd.normalized()

	var back_dir: Vector3 = -planar_fwd
	var player_pos: Vector3 = player_node.global_position
	var desired_rear: Vector3 = player_pos + (back_dir * spawn_behind_distance)

	var world: World3D = get_world_3d()
	if is_instance_valid(world):
		var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
		if is_instance_valid(space_state):
			var head_height: Vector3 = Vector3(0.0, 1.2, 0.0)
			var wall_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
				player_pos + head_height, desired_rear + head_height, PHYSICS_LAYER_ENVIRONMENT
			)
			var wall_hit: Dictionary = space_state.intersect_ray(wall_query)
			if not wall_hit.is_empty():
				var hit_point: Vector3 = wall_hit.get(&"position", desired_rear)
				print("SpookEncounter: Obstructing wall hit behind player at ", hit_point)
				desired_rear = hit_point - (back_dir * 0.4)

	return _find_floor_position(desired_rear)


## Checks whether player camera has rotated toward the spook silhouette.
## Checks whether player camera has rotated toward the spook silhouette.
func _is_player_looking_at_spook() -> bool:
	if not is_instance_valid(_player_camera) or not is_instance_valid(_spook_sprite):
		return false

	var cam_pos: Vector3 = _player_camera.global_position
	var spook_pos: Vector3 = _spook_sprite.global_position
	var to_spook: Vector3 = (spook_pos - cam_pos).normalized()
	var cam_fwd: Vector3 = -_player_camera.global_transform.basis.z.normalized()
	var dot: float = cam_fwd.dot(to_spook)

	# 0.35 means looking directly at it (approx 70-degree cone)
	if dot > 0.35 and _has_line_of_sight():
		return true

	return false


## Spawns spook behind player with shadow casting enabled.
func _spawn_spook_behind(player_node: Node3D) -> void:
	print("SpookEncounter: Spawning silhouette behind player back.")
	var chosen_tex: Texture2D = spook_texture
	if not alternate_textures.is_empty():
		var all_textures: Array[Texture2D] = alternate_textures.duplicate()
		if spook_texture != null:
			all_textures.append(spook_texture)
		chosen_tex = all_textures.pick_random()

	if chosen_tex == null:
		push_warning("SpookEncounter: No valid texture assigned to spook.")
		return

	_spook_sprite.texture = chosen_tex
	var chosen_scale: float = randf_range(min_scale, max_scale)
	_spook_sprite.scale = Vector3(chosen_scale, chosen_scale, chosen_scale)

	if random_flip_h:
		_spook_sprite.flip_h = randf() > 0.5
	if randomize_tint:
		var tint_val: float = randf_range(0.75, 1.0)
		_spook_sprite.modulate = Color(tint_val, tint_val, tint_val, 1.0)
	else:
		_spook_sprite.modulate = Color.WHITE

	var floor_point: Vector3 = _calculate_behind_spawn_position(player_node)
	var sprite_h: float = float(chosen_tex.get_height()) * pixel_size * chosen_scale
	var target_y: float = floor_point.y + (sprite_h * 0.5) + floor_offset

	_spook_sprite.top_level = true
	_spook_sprite.global_position = Vector3(floor_point.x, target_y, floor_point.z)

	# Orient sprite flat towards player's forward direction so the rear light hits it square
	var cam_fwd: Vector3 = -_player_camera.global_transform.basis.z
	var planar_fwd: Vector3 = Vector3(cam_fwd.x, 0.0, cam_fwd.z).normalized()
	if not planar_fwd.is_zero_approx():
		_spook_sprite.look_at(_spook_sprite.global_position + planar_fwd, Vector3.UP)

	if is_instance_valid(_notifier):
		_notifier.global_position = _spook_sprite.global_position

	_active_lifetime = 0.0
	_is_active = true
	_spook_sprite.visible = true

	print(
		"SpookEncounter: Silhouette positioned at ",
		_spook_sprite.global_position,
		" behind player."
	)
	spook_spawned.emit(_spook_sprite.global_position)


## Hides sprite, cleans state, and emits [signal spook_vanished].
func _despawn_spook() -> void:
	print("SpookEncounter: Silhouette vanished instantly.")
	_is_active = false
	_spook_sprite.visible = false
	spook_vanished.emit()

	if one_shot:
		queue_free()


## Tests environment occlusion between camera and spook chest.
func _has_line_of_sight() -> bool:
	if not is_instance_valid(_player_camera):
		return false

	var world: World3D = get_world_3d()
	if not is_instance_valid(world):
		return false

	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if not is_instance_valid(space_state):
		return false

	var sprite_h: float = 2.0
	if _spook_sprite.texture != null:
		sprite_h = (
			float(_spook_sprite.texture.get_height())
			* _spook_sprite.pixel_size
			* _spook_sprite.scale.y
		)
	var target_chest: Vector3 = _spook_sprite.global_position + Vector3(0.0, sprite_h * 0.2, 0.0)

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		_player_camera.global_position, target_chest, PHYSICS_LAYER_ENVIRONMENT
	)
	var hit: Dictionary = space_state.intersect_ray(query)
	return hit.is_empty()


## Registers player entry, initializes camera, and starts spawn timer.
func _on_body_entered(body: Node3D) -> void:
	print("SpookEncounter: Body entered trigger volume -> ", body.name)
	if _is_active or (_has_triggered and one_shot):
		return

	_tracked_player = body
	_player_camera = get_viewport().get_camera_3d()
	_spawn_timer = spawn_delay


## Clears tracked player reference when leaving the trigger area.
func _on_body_exited(body: Node3D) -> void:
	print("SpookEncounter: Body exited trigger volume -> ", body.name)
	if _tracked_player == body:
		_tracked_player = null
		if _is_active:
			_despawn_spook()
