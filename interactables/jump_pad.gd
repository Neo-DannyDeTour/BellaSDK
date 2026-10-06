@tool
## Physics trigger that launches the player to a destination along a parabolic arc.
class_name JumpPad
extends Area3D

## Specific 3D node the player lands on; if null, a default child marker is used.
@export var assigned_target: Node3D:
	set(value):
		assigned_target = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_trajectory()

## Peak height the player reaches above the highest point during the jump trajectory.
@export var apex_height: float = 3.0:
	set(value):
		apex_height = maxf(0.1, value)
		if is_inside_tree() and Engine.is_editor_hint():
			_update_trajectory()

## Multiplier to increase or decrease the overall flight speed.
@export_range(0.1, 5.0, 0.1) var flight_speed_multiplier: float = 1.0:
	set(value):
		flight_speed_multiplier = maxf(0.1, value)
		if is_inside_tree() and Engine.is_editor_hint():
			_update_trajectory()

## Base upward gravity applied to the player while ascending.
@export var player_gravity: float = 9.8:
	set(value):
		player_gravity = maxf(0.1, value)
		if is_inside_tree() and Engine.is_editor_hint():
			_update_trajectory()

## Multiplier applied to the gravity while the player is falling.
@export var fall_gravity_multiplier: float = 1.0:
	set(value):
		fall_gravity_multiplier = maxf(0.1, value)
		if is_inside_tree() and Engine.is_editor_hint():
			_update_trajectory()

## Total calculated time for the player to reach the target.
var _flight_time: float = 0.0
## Timer used to simulate the ball flight in the editor.
var _timer: float = 0.0
## Initial velocity applied to the player upon entering the jump pad.
var _initial_velocity: Vector3 = Vector3.ZERO
## Time it takes for the player to reach the apex of the jump.
var _t_up: float = 0.0
## Custom gravity applied while the player is ascending.
var _custom_gravity_up: float = 9.8
## Custom gravity applied while the player is descending.
var _custom_gravity_down: float = 9.8

## Cached reference to fallback target node.
var _target_node: Node3D

## Last recorded position of the jump pad to detect movement.
var _last_start_pos: Vector3 = Vector3.ZERO
## Last recorded position of the target to detect movement.
var _last_target_pos: Vector3 = Vector3.ZERO

## Cached BallVisual node.
var _ball_visual: Node3D
## Cached LineVisual node.
var _line_visual: MeshInstance3D
## Cached ApexVisual node.
var _apex_visual: MeshInstance3D


## Generates hidden visualizer nodes and default target in the editor.
func _enter_tree() -> void:
	_create_default_nodes()


## Connects trigger signals and deletes editor visualizer meshes on play.
func _ready() -> void:
	collision_layer = CollisionLayers.MASK_NONE
	collision_mask = CollisionLayers.MASK_PLAYER

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	if not Engine.is_editor_hint():
		var n: Node = get_node_or_null("BallVisual")
		if is_instance_valid(n):
			n.queue_free()
		n = get_node_or_null("LineVisual")
		if is_instance_valid(n):
			n.queue_free()
		n = get_node_or_null("ApexVisual")
		if is_instance_valid(n):
			n.queue_free()

	_update_trajectory()


## Continuously verifies positions of pad and target to rebuild arc.
func _process(delta: float) -> void:
	var active_target: Node3D = assigned_target
	if not is_instance_valid(active_target):
		active_target = get_node_or_null("Target") as Node3D

	if is_instance_valid(active_target):
		var has_pad_moved: bool = global_position != _last_start_pos
		var has_target_moved: bool = active_target.global_position != _last_target_pos
		if has_pad_moved or has_target_moved:
			_update_trajectory()
			_last_start_pos = global_position
			_last_target_pos = active_target.global_position

	if _flight_time > 0.0 and Engine.is_editor_hint():
		_timer += delta
		if _timer > _flight_time + 2.0:
			_timer = 0.0

		if not is_instance_valid(_ball_visual):
			_ball_visual = get_node_or_null("BallVisual") as Node3D

		if is_instance_valid(_ball_visual):
			if _timer <= _flight_time:
				_ball_visual.visible = true
				_ball_visual.global_position = _get_position_at_time(_timer)
			else:
				_ball_visual.visible = false


## Suppresses editor warning regarding missing collision shape.
func _get_configuration_warnings() -> PackedStringArray:
	return PackedStringArray()


## Recalculates launch velocity and gravity from spatial delta.
func _update_trajectory() -> void:
	if not is_inside_tree():
		return

	var active_target: Node3D = assigned_target
	if not is_instance_valid(active_target):
		active_target = get_node_or_null("Target") as Node3D

	if not is_instance_valid(active_target):
		_flight_time = 0.0
		_update_visuals()
		return

	var p_start: Vector3 = global_position
	var p_end: Vector3 = active_target.global_position

	var y_apex: float = maxf(p_start.y, p_end.y) + apex_height
	var h_start: float = y_apex - p_start.y
	var h_end: float = y_apex - p_end.y

	var g_up: float = player_gravity
	var g_down: float = player_gravity * fall_gravity_multiplier

	var v_y0: float = sqrt(2.0 * g_up * h_start)
	var base_t_up: float = v_y0 / g_up
	var base_t_down: float = sqrt((2.0 * h_end) / g_down)
	var base_flight_time: float = base_t_up + base_t_down

	_flight_time = base_flight_time / flight_speed_multiplier
	_t_up = base_t_up / flight_speed_multiplier
	_custom_gravity_up = g_up * pow(flight_speed_multiplier, 2.0)
	_custom_gravity_down = g_down * pow(flight_speed_multiplier, 2.0)

	if _flight_time > 0.0:
		var v_xz: Vector3 = (p_end - p_start) / _flight_time
		_initial_velocity = Vector3(v_xz.x, v_y0 * flight_speed_multiplier, v_xz.z)
	else:
		_initial_velocity = Vector3.ZERO

	_update_visuals()


## Redraws arc path lines and apex indicator for editor viewport.
func _update_visuals() -> void:
	if not Engine.is_editor_hint():
		return

	if _flight_time <= 0.0:
		if is_instance_valid(_line_visual):
			_line_visual.visible = false
		if is_instance_valid(_apex_visual):
			_apex_visual.visible = false
		return

	if not is_instance_valid(_line_visual):
		_line_visual = get_node_or_null("LineVisual") as MeshInstance3D

	if is_instance_valid(_line_visual):
		_line_visual.visible = true
		_line_visual.top_level = false

		var imm_mesh: ImmediateMesh = _line_visual.mesh as ImmediateMesh
		if not imm_mesh:
			imm_mesh = ImmediateMesh.new()
			_line_visual.mesh = imm_mesh
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = Color.CYAN
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_line_visual.material_override = mat

		imm_mesh.clear_surfaces()
		imm_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		var segments: int = 40

		var prev_pos: Vector3 = _line_visual.to_local(_get_position_at_time(0.0))

		for i: int in range(1, segments + 1):
			var t: float = _flight_time * (float(i) / float(segments))
			var curr_pos: Vector3 = _line_visual.to_local(_get_position_at_time(t))
			imm_mesh.surface_add_vertex(prev_pos)
			imm_mesh.surface_add_vertex(curr_pos)
			prev_pos = curr_pos

		imm_mesh.surface_end()

	if not is_instance_valid(_apex_visual):
		_apex_visual = get_node_or_null("ApexVisual") as MeshInstance3D

	if is_instance_valid(_apex_visual):
		_apex_visual.visible = true
		_apex_visual.top_level = true
		_apex_visual.global_position = _get_position_at_time(_t_up)


## Solves kinematic equations to find 3D coordinate at flight time.
func _get_position_at_time(t: float) -> Vector3:
	var p0: Vector3 = global_position
	if not is_instance_valid(_target_node):
		_target_node = get_node_or_null("Target") as Node3D

	var y: float = 0.0

	if t <= _t_up:
		y = p0.y + _initial_velocity.y * t - 0.5 * _custom_gravity_up * t * t
	else:
		var td: float = t - _t_up
		var target_y: float = p0.y

		if is_instance_valid(assigned_target):
			target_y = assigned_target.global_position.y
		elif is_instance_valid(_target_node):
			target_y = _target_node.global_position.y

		var y_apex: float = maxf(p0.y, target_y) + apex_height
		y = y_apex - 0.5 * _custom_gravity_down * td * td

	var xz: Vector3 = Vector3(_initial_velocity.x, 0.0, _initial_velocity.z) * t
	return Vector3(p0.x + xz.x, y, p0.z + xz.z)


## Detects player entry, applies velocity, and transitions state machine.
func _on_body_entered(body: Node3D) -> void:
	var character: CharacterBody3D = body as CharacterBody3D
	if character and (character.is_in_group(&"player") or character is Player):
		print(
			"JumpPad: _on_body_entered() called. Launching player with velocity: ",
			_initial_velocity
		)
		character.velocity = _initial_velocity

		var sm: Node = character.get_node_or_null("StateMachine")
		if not is_instance_valid(sm):
			sm = NodeQuery.find_first_child_of_type(character, StateMachine)

		if is_instance_valid(sm) and sm.has_method("transition_to"):
			sm.call(
				&"transition_to",
				"Air",
				{
					"jump_pad": true,
					"launch_gravity": _custom_gravity_up,
					"launch_fall_gravity": _custom_gravity_down
				}
			)


## Spawns or retrieves nodes safely without cluttering the scene tree.
func _get_or_create_internal_node(node_name: String, node_factory: Callable) -> Node:
	var n: Node = get_node_or_null(node_name)
	if not is_instance_valid(n):
		n = node_factory.call() as Node
		n.name = node_name
		add_child(n, false, Node.INTERNAL_MODE_BACK)
	return n


## Instantiates target, mesh, and collision required for jump pad to operate.
func _create_default_nodes() -> void:
	var col: CollisionShape3D = (
		_get_or_create_internal_node("CollisionShape3D", CollisionShape3D.new) as CollisionShape3D
	)
	if not col.shape:
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(2.0, 0.2, 2.0)
		col.shape = shape

	var pad: MeshInstance3D = (
		_get_or_create_internal_node("PadMesh", MeshInstance3D.new) as MeshInstance3D
	)
	if not pad.mesh:
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(2.0, 0.2, 2.0)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color.GREEN
		box.material = mat
		pad.mesh = box

	if Engine.is_editor_hint():
		var ball: MeshInstance3D = (
			_get_or_create_internal_node("BallVisual", MeshInstance3D.new) as MeshInstance3D
		)
		ball.top_level = true
		if not ball.mesh:
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = 0.2
			sphere.height = 0.4
			var b_mat: StandardMaterial3D = StandardMaterial3D.new()
			b_mat.albedo_color = Color.YELLOW
			b_mat.emission_enabled = true
			b_mat.emission = Color.YELLOW
			sphere.material = b_mat
			ball.mesh = sphere

		var line: MeshInstance3D = (
			_get_or_create_internal_node("LineVisual", MeshInstance3D.new) as MeshInstance3D
		)
		line.top_level = true

		var apex: MeshInstance3D = (
			_get_or_create_internal_node("ApexVisual", MeshInstance3D.new) as MeshInstance3D
		)
		apex.top_level = true
		if not apex.mesh:
			var apex_box: BoxMesh = BoxMesh.new()
			apex_box.size = Vector3(1.0, 0.05, 1.0)
			var a_mat: StandardMaterial3D = StandardMaterial3D.new()
			a_mat.albedo_color = Color.MAGENTA
			a_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			apex_box.material = a_mat
			apex.mesh = apex_box

	var target: Marker3D = get_node_or_null("Target") as Marker3D
	if not is_instance_valid(target):
		target = Marker3D.new()
		target.name = "Target"
		target.position = Vector3(0.0, 5.0, -10.0)
		add_child(target)
		if Engine.is_editor_hint() and is_inside_tree():
			target.owner = get_tree().edited_scene_root
