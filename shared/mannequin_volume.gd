@tool
extends Node3D

## The 3D bounding volume. Determines the overall footprint where references will spawn.
@export var volume_size: Vector3 = Vector3(10.0, 4.0, 10.0):
	set(value):
		volume_size = value
		_request_update()

## The spatial distance between each spawned mannequin and reference box cluster.
@export var spacing: float = 2.0:
	set(value):
		spacing = max(0.5, value)
		_request_update()

## If true, references will only spawn if they successfully raycast and hit a physical floor.
@export var only_spawn_on_floors: bool = true:
	set(value):
		only_spawn_on_floors = value
		_request_update()

## Toggles whether these debug references exist during live gameplay or only in the editor.
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		_request_update()

## The standard character texture used when standing clearance is available.
@export var mannequin_texture: Texture2D:
	set(value):
		mannequin_texture = value
		_request_update()

## The texture used to visualize the character in a crouching position when overhead space is tight.
@export var crouch_texture: Texture2D:
	set(value):
		crouch_texture = value
		_request_update()

## The texture used to indicate a surface is reachable for standard wall climbing.
@export var climb_texture: Texture2D:
	set(value):
		climb_texture = value
		_request_update()

## The texture used to indicate a surface is reachable for climbing only after a jump.
@export var jump_climb_texture: Texture2D:
	set(value):
		jump_climb_texture = value
		_request_update()

## Link your saved Player.tscn scene here to automatically extract settings.
@export var player_scene: PackedScene:
	set(value):
		player_scene = value
		_request_update()

## If enabled, visual reference materials will respect depth and be hidden behind geometry.
@export var enable_depth_test: bool = false:
	set(value):
		enable_depth_test = value
		_request_update()

## Toggles individual reference boxes on or off. Useful for decluttering the view.
@export var box_toggles: Array[bool] = [true, true, true]:
	set(value):
		box_toggles = value
		_request_update()

## The specific heights in meters for each spawned reference box.
@export var box_heights: Array[float] = [1.0, 2.5, 3.0]:
	set(value):
		box_heights = value
		_request_update()

## Colors and opacities for each box. Adjust the alpha channel for transparency.
@export var box_colors: Array[Color] = [
	Color(1.0, 0.0, 0.0, 0.4), Color(0.0, 1.0, 0.0, 0.4), Color(0.0, 0.0, 1.0, 0.4)
]:
	set(value):
		box_colors = value
		_request_update()

## The initial upward velocity of the character's jump to visualize max height clearance.
@export var jump_velocity: float = 5.0:
	set(value):
		jump_velocity = value
		_request_update()

## The forward movement speed in meters per second during the jump trajectory.
@export var jump_forward_speed: float = 4.0:
	set(value):
		jump_forward_speed = value
		_request_update()

## The gravity applied to the jump simulation (positive value representing downward force).
@export var jump_gravity: float = 9.8:
	set(value):
		jump_gravity = value
		_request_update()

## Draws a 2m high, 0.5m radius cyan wireframe collision capsule around each mannequin.
@export var show_collision_capsules: bool = true:
	set(value):
		show_collision_capsules = value
		_request_update()

## The maximum walkable slope in degrees. Floors steeper than this will be highlighted red.
@export var max_walkable_slope: float = 45.0:
	set(value):
		max_walkable_slope = value
		_request_update()

## Click this checkbox to permanently bake the generated meshes into your scene tree.
@export var bake_to_scene: bool = false:
	set(value):
		if value:
			_bake_meshes()
		bake_to_scene = false

## Property: Update Queued.
var _update_queued: bool = false
## Property: Container.
var _container: Node3D
## Property: Standing Height.
var _standing_height: float = 2.0
## Property: Crouch Height.
var _crouch_height: float = 1.0


func _ready() -> void:
	print("Initializing Reference Volume Tool...")
	if not Engine.is_editor_hint() and not show_in_game:
		queue_free()
		return
	_request_update()


func _process(_delta: float) -> void:
	if _update_queued:
		_generate_references()
		_update_queued = false


## Flags the script to regenerate all visual instances on the next process frame.
func _request_update() -> void:
	_update_queued = true


## Pulls relevant movement and dimension parameters by safely duck-typing a temporary player scene.
func _sync_with_target() -> void:
	if not player_scene:
		return

	print("Instantiating temporary player scene for reference data extraction...")
	var temp_player: Node = player_scene.instantiate()
	if not temp_player:
		return

	var loco_comp: Node = _find_locomotion_component(temp_player)

	if is_instance_valid(loco_comp):
		print("Syncing metrics from PlayerLocomotionComponent...")

		# Safely extract variables to prevent editor crashes on strictly typed custom nodes
		if "gravity" in loco_comp:
			jump_gravity = loco_comp.get("gravity")
		if "sprinting_speed" in loco_comp:
			jump_forward_speed = loco_comp.get("sprinting_speed")

		if "jump_velocity" in loco_comp:
			jump_velocity = loco_comp.get("jump_velocity")
		elif "jump_velocity" in temp_player:
			jump_velocity = temp_player.get("jump_velocity")

		if "STANDING_HEIGHT" in loco_comp:
			_standing_height = loco_comp.get("STANDING_HEIGHT")
		if "CROUCHING_HEIGHT" in loco_comp:
			_crouch_height = loco_comp.get("CROUCHING_HEIGHT")

		var max_jump_height: float = (pow(jump_velocity, 2.0)) / (2.0 * jump_gravity)

		box_heights.clear()
		box_heights.append(_crouch_height)
		box_heights.append(_standing_height)
		box_heights.append(_standing_height + max_jump_height)

	temp_player.queue_free()


## Recursively searches the temporary player instance to locate the locomotion component safely.
func _find_locomotion_component(node: Node) -> Node:
	# Duck-typing by checking for unique properties guarantees we find the script
	# without crashing the editor due to missing global class contexts.
	if node.get_script() != null and "STANDING_HEIGHT" in node:
		return node

	for child: Node in node.get_children():
		var found: Node = _find_locomotion_component(child)
		if found:
			return found

	return null


## Clears old references, calculates valid spawn positions, and builds multimeshes.
func _generate_references() -> void:
	print("Generating 60-FPS optimized scale references within volume...")
	if is_instance_valid(_container):
		_container.queue_free()

	_sync_with_target()

	_container = Node3D.new()
	add_child(_container)

	var half_size: Vector3 = volume_size / 2.0
	var x_steps: int = int(volume_size.x / spacing)
	var z_steps: int = int(volume_size.z / spacing)

	_draw_grid(half_size, x_steps, z_steps)

	var valid_positions: Array[Vector3] = []
	var invalid_slope_data: Array[Dictionary] = []

	var standing_xforms: Array[Transform3D] = []
	var crouching_xforms: Array[Transform3D] = []
	var climb_xforms: Array[Transform3D] = []
	var jump_climb_xforms: Array[Transform3D] = []

	for x: int in range(x_steps + 1):
		for z: int in range(z_steps + 1):
			var pos_x: float = -half_size.x + (x * spacing)
			var pos_z: float = -half_size.z + (z * spacing)

			var local_start: Vector3 = Vector3(pos_x, half_size.y, pos_z)
			var local_end: Vector3 = Vector3(pos_x, -half_size.y, pos_z)

			var global_start: Vector3 = to_global(local_start)
			var global_end: Vector3 = to_global(local_end)
			var final_pos: Vector3 = local_start

			if only_spawn_on_floors:
				var hit_result: Dictionary = _raycast(global_start, global_end)
				if hit_result.is_empty():
					continue

				final_pos = to_local(hit_result.position)
				var normal: Vector3 = hit_result.normal
				var slope_angle: float = rad_to_deg(Vector3.UP.angle_to(normal))

				if slope_angle > max_walkable_slope:
					invalid_slope_data.append({"pos": final_pos, "normal": normal})
					continue

				_process_posture_and_walls(
					hit_result.position,
					final_pos,
					standing_xforms,
					crouching_xforms,
					climb_xforms,
					jump_climb_xforms
				)
			else:
				final_pos.y = -half_size.y
				# Change: Base at final_pos, pivot bottom.
				standing_xforms.append(Transform3D().translated(final_pos))

			valid_positions.append(final_pos)

	if valid_positions.size() > 0:
		_build_sprite_multimesh(standing_xforms, mannequin_texture, _standing_height)
		_build_sprite_multimesh(crouching_xforms, crouch_texture, _crouch_height)
		_build_sprite_multimesh(climb_xforms, climb_texture, _standing_height)
		_build_sprite_multimesh(jump_climb_xforms, jump_climb_texture, _standing_height)

		_build_boxes_multimesh(valid_positions)

		if show_collision_capsules:
			_build_capsule_multimesh(valid_positions)

		_draw_jump_trajectories(valid_positions)

	if invalid_slope_data.size() > 0:
		_build_slope_warnings_multimesh(invalid_slope_data)


## Determines if a spot is a crouch zone or has adjacent climbable walls via spatial raycasts.
func _process_posture_and_walls(
	global_floor: Vector3,
	local_floor: Vector3,
	standing_xforms: Array[Transform3D],
	crouching_xforms: Array[Transform3D],
	climb_xforms: Array[Transform3D],
	jump_climb_xforms: Array[Transform3D]
) -> void:
	print("Processing posture constraints and resolving wall clearance...")

	# Crouch Check: Raycast up from crouch height to standing height
	var ceil_start: Vector3 = global_floor + Vector3(0.0, _crouch_height, 0.0)
	var ceil_end: Vector3 = global_floor + Vector3(0.0, _standing_height, 0.0)
	var ceil_hit: Dictionary = _raycast(ceil_start, ceil_end)

	# Change: Base at final_pos, pivot bottom for all postural mannequins.
	if not ceil_hit.is_empty() -> void:
		crouching_xforms.append(Transform3D().translated(local_floor))
	else:
		standing_xforms.append(Transform3D().translated(local_floor))

	# Wall Check: Raycast horizontally in 4 directions to find climbable geometry
	var dirs: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
	var max_jump: float = (pow(jump_velocity, 2.0)) / (2.0 * jump_gravity)

	for dir: Vector3 in dirs:
		var wall_start: Vector3 = global_floor + Vector3(0.0, _standing_height * 0.5, 0.0)
		var wall_end: Vector3 = wall_start + (dir * spacing * 0.8)
		var wall_hit: Dictionary = _raycast(wall_start, wall_end)

		if not wall_hit.is_empty():
			var wall_normal: Vector3 = wall_hit.normal
			# Ensure we are hitting a vertical surface (not a slope)
			if abs(wall_normal.y) < 0.2:
				var w_pos: Vector3 = to_local(wall_hit.position)
				# Change: Base at wall floor level (final_pos), pivot bottom for walls too.
				# Offset slightly from the wall so Z-fighting doesn't obscure the texture
				var w_xform: Transform3D = Transform3D().translated(w_pos + (wall_normal * 0.2))

				# Check overhead clearance for jump climbs
				var h_start: Vector3 = (
					wall_hit.position + (wall_normal * 0.1) + Vector3(0.0, max_jump, 0.0)
				)
				var h_end: Vector3 = (
					wall_hit.position + (wall_normal * -0.5) + Vector3(0.0, max_jump, 0.0)
				)
				var ledge_hit: Dictionary = _raycast(h_start, h_end)

				if not ledge_hit.is_empty():
					# Shift the jump climb texture up by exactly max_jump so it reflects character at apex
					var jump_w_xform: Transform3D = Transform3D().translated(
						w_pos + (wall_normal * 0.2) + Vector3(0.0, max_jump, 0.0)
					)
					jump_climb_xforms.append(jump_w_xform)
				else:
					climb_xforms.append(w_xform)


## Renders a yellow wireframe grid across the bottom plane of the volume boundaries.
func _draw_grid(half_size: Vector3, x_steps: int, z_steps: int) -> void:
	print("Drawing volume bounds grid...")
	var grid_mesh: ImmediateMesh = ImmediateMesh.new()
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = grid_mesh

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 0.0, 0.5)
	mat.no_depth_test = not enable_depth_test
	mesh_instance.material_override = mat

	grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for x: int in range(x_steps + 1):
		var pos_x: float = -half_size.x + (x * spacing)
		grid_mesh.surface_add_vertex(Vector3(pos_x, -half_size.y, -half_size.z))
		grid_mesh.surface_add_vertex(Vector3(pos_x, -half_size.y, half_size.z))
	for z: int in range(z_steps + 1):
		var pos_z: float = -half_size.z + (z * spacing)
		grid_mesh.surface_add_vertex(Vector3(-half_size.x, -half_size.y, pos_z))
		grid_mesh.surface_add_vertex(Vector3(half_size.x, -half_size.y, pos_z))
	grid_mesh.surface_end()

	_container.add_child(mesh_instance)


## Casts a physics ray between two global points to find intersecting world geometry.
func _raycast(global_start: Vector3, global_end: Vector3) -> Dictionary:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_start, global_end
	)
	return space_state.intersect_ray(query)


## Reusable pipeline for generating a MultiMeshInstance3D from an array of transforms and a texture.
func _build_sprite_multimesh(
	xforms: Array[Transform3D], tex: Texture2D, sprite_height: float
) -> void:
	if not tex or xforms.is_empty() -> void:
		return

	print(
		"Building Sprite MultiMesh for ",
		xforms.size(),
		" instances at height ",
		sprite_height,
		"..."
	)
	var tex_width: float = float(tex.get_width())
	var tex_height: float = float(tex.get_height())
	var aspect: float = tex_width / tex_height if tex_height > 0.0 else 1.0

	var quad: ArrayMesh = ArrayMesh.new()

	# A structured array holding rendering data for the custom mesh surface creation.
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)

	# The calculated horizontal span of the sprite based on its height and aspect ratio.
	var visual_width: float = sprite_height * aspect

	# The specific 3D spatial coordinates defining the four corners of the quad mesh.
	var vertices: PackedVector3Array = PackedVector3Array(
		[
			Vector3(-visual_width / 2.0, 0.0, 0.0),
			Vector3(visual_width / 2.0, 0.0, 0.0),
			Vector3(visual_width / 2.0, sprite_height, 0.0),
			Vector3(-visual_width / 2.0, sprite_height, 0.0),
		]
	)

	arr[Mesh.ARRAY_VERTEX] = vertices

	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array(
		[
			Vector2(0.0, 1.0),
			Vector2(1.0, 1.0),
			Vector2(1.0, 0.0),
			Vector2(0.0, 0.0),
		]
	)

	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = not enable_depth_test
	quad.surface_set_material(0, mat)

	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = xforms.size()

	for i: int in range(xforms.size()):
		multimesh.set_instance_transform(i, xforms[i])

	var mm_instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mm_instance.multimesh = multimesh
	_container.add_child(mm_instance)


## Generates a single color-instanced MultiMesh for custom size/color reference boxes.
func _build_boxes_multimesh(positions: Array[Vector3]) -> void:
	print("Building customizable MultiMesh reference boxes...")
	var base_box: BoxMesh = BoxMesh.new()
	base_box.size = Vector3(1.0, 1.0, 1.0)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = not enable_depth_test
	base_box.material = mat

	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = base_box

	var valid_indices: Array[int] = []
	for i: int in range(box_heights.size()):
		if i < box_toggles.size() and box_toggles[i]:
			valid_indices.append(i)

	var total_boxes: int = positions.size() * valid_indices.size()
	if total_boxes == 0:
		return

	multimesh.instance_count = total_boxes

	var index: int = 0
	for pos: Vector3 in positions:
		var offset_x: float = 0.5
		for i: int in valid_indices:
			var height: float = box_heights[i]
			var color: Color = Color(1.0, 0.0, 0.0, 0.4)
			if i < box_colors.size():
				color = box_colors[i]

			var scale_vec: Vector3 = Vector3(0.4, height, 0.4)
			var translation: Vector3 = pos + Vector3(offset_x, height / 2.0, 0.0)

			var box_basis: Basis = Basis().scaled(scale_vec)
			var xform: Transform3D = Transform3D(box_basis, translation)

			multimesh.set_instance_transform(index, xform)
			multimesh.set_instance_color(index, color)

			offset_x += 0.5
			index += 1

	var mm_instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mm_instance.multimesh = multimesh
	_container.add_child(mm_instance)


## Builds and batches wireframe cylinders to represent character controller footprint.
func _build_capsule_multimesh(positions: Array[Vector3]) -> void:
	print("Building wireframe collision capsules...")
	var capsule_mesh: ArrayMesh = _create_wireframe_capsule_mesh(0.5, _standing_height)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.0, 1.0, 1.0, 0.8)
	mat.no_depth_test = not enable_depth_test
	capsule_mesh.surface_set_material(0, mat)

	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = capsule_mesh
	multimesh.instance_count = positions.size()

	for i: int in range(positions.size()):
		var xform: Transform3D = Transform3D()
		# Change: Base at positions[i], pivot bottom.
		xform = xform.translated(positions[i])
		multimesh.set_instance_transform(i, xform)

	var mm_instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mm_instance.multimesh = multimesh
	_container.add_child(mm_instance)


## Generates a raw ArrayMesh of lines representing a capsule footprint.
func _create_wireframe_capsule_mesh(radius: float, height: float) -> ArrayMesh:
	# Change: Pivot to bottom-center. Cylinder base at (0,0), top at (0,height)
	var arr: PackedVector3Array = PackedVector3Array()
	var segments: int = 8

	for i: int in range(segments):
		var angle1: float = (PI * 2.0 * i) / segments
		var angle2: float = (PI * 2.0 * (i + 1)) / segments
		var x1: float = cos(angle1) * radius
		var z1: float = sin(angle1) * radius
		var x2: float = cos(angle2) * radius
		var z2: float = sin(angle2) * radius

		# Vertices at base and full height.
		arr.append(Vector3(x1, 0, z1))
		arr.append(Vector3(x2, 0, z2))
		arr.append(Vector3(x1, height, z1))
		arr.append(Vector3(x2, height, z2))

	for i: int in range(4):
		var angle: float = (PI * 2.0 * i) / 4.0
		var x: float = cos(angle) * radius
		var z: float = sin(angle) * radius

		arr.append(Vector3(x, 0, z))
		arr.append(Vector3(x, height, z))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = arr

	var array_mesh: ArrayMesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return array_mesh


## Batches red quads onto the floor where the slope exceeds character walking capabilities.
func _build_slope_warnings_multimesh(slope_data: Array[Dictionary]) -> void:
	print("Building MultiMesh for slope angle warnings...")
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1.5, 1.5)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.0, 0.0, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = not enable_depth_test
	quad.material = mat

	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = slope_data.size()

	for i: int in range(slope_data.size()):
		var data: Dictionary = slope_data[i]
		var pos: Vector3 = data["pos"]
		var normal: Vector3 = data["normal"]

		var xform: Transform3D = Transform3D()
		var up: Vector3 = Vector3.UP

		if normal.is_equal_approx(Vector3.UP):
			xform.basis = Basis()
		elif normal.is_equal_approx(Vector3.DOWN):
			xform.basis = Basis().rotated(Vector3.RIGHT, PI)
		else:
			var axis: Vector3 = up.cross(normal).normalized()
			var angle: float = up.angle_to(normal)
			xform.basis = Basis().rotated(axis, angle)

		xform = xform.rotated_local(Vector3.RIGHT, -PI / 2.0)
		xform.origin = pos + (normal * 0.05)
		multimesh.set_instance_transform(i, xform)

	var mm_instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mm_instance.multimesh = multimesh
	_container.add_child(mm_instance)


## Calculates physics arcs and renders jump trajectories efficiently using ImmediateMesh.
func _draw_jump_trajectories(positions: Array[Vector3]) -> void:
	print("Drawing jump trajectory physics arcs...")
	var line_mesh: ImmediateMesh = ImmediateMesh.new()
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.mesh = line_mesh

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.0, 1.0, 1.0, 0.8)
	mat.no_depth_test = not enable_depth_test
	mesh_instance.material_override = mat

	line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	var time_step: float = 0.05
	var max_time: float = 2.0

	for pos: Vector3 in positions:
		var current_time: float = 0.0
		var prev_point: Vector3 = pos
		var is_first: bool = true

		while current_time <= max_time:
			var current_y: float = (
				(jump_velocity * current_time) - (0.5 * jump_gravity * pow(current_time, 2.0))
			)
			var current_z: float = jump_forward_speed * current_time
			var next_point: Vector3 = pos + Vector3(0.0, current_y, current_z)

			if current_y < 0.0 and not is_first:
				line_mesh.surface_add_vertex(prev_point)
				line_mesh.surface_add_vertex(pos + Vector3(0.0, 0.0, current_z))
				break

			if not is_first:
				line_mesh.surface_add_vertex(prev_point)
				line_mesh.surface_add_vertex(next_point)

			prev_point = next_point
			current_time += time_step
			is_first = false

	line_mesh.surface_end()
	_container.add_child(mesh_instance)


## Duplicates the dynamically generated container and sets it permanently into the Scene Tree.
func _bake_meshes() -> void:
	print("Baking reference meshes to scene tree...")
	if not is_instance_valid(_container):
		print("Nothing to bake.")
		return

	var baked_root: Node3D = _container.duplicate()
	get_parent().add_child(baked_root)
	baked_root.name = "BakedLevelReferences"
	baked_root.global_position = _container.global_position

	var edited_scene_root: Node = get_tree().edited_scene_root
	if edited_scene_root:
		baked_root.owner = edited_scene_root
		_set_owner_recursive(baked_root, edited_scene_root)


## Iterates recursively to set the scene owner so baked nodes are saved with the scene.
func _set_owner_recursive(node: Node, new_owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = new_owner
		_set_owner_recursive(child, new_owner)
