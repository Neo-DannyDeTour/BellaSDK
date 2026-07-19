@tool
class_name JumpPad
extends Area3D

## The peak height the player reaches during the jump trajectory.
@export var apex_height: float = 3.0:
	set(value):
		apex_height = maxf(0.1, value)
		_update_trajectory()

## Multiplier to increase or decrease the overall flight speed.
@export_range(0.1, 5.0, 0.1) var flight_speed_multiplier: float = 1.0:
	set(value):
		flight_speed_multiplier = maxf(0.1, value)
		_update_trajectory()

## The base upward gravity applied to the player while ascending.
@export var player_gravity: float = 9.8:
	set(value):
		player_gravity = maxf(0.1, value)
		_update_trajectory()

## Multiplier applied to the gravity while the player is falling.
@export var fall_gravity_multiplier: float = 1.0:
	set(value):
		fall_gravity_multiplier = maxf(0.1, value)
		_update_trajectory()

## The total calculated time for the player to reach the target.
var _flight_time: float = 0.0
## The timer used to simulate the ball flight in the editor.
var _timer: float = 0.0
## The initial velocity applied to the player upon entering the jump pad.
var _initial_velocity: Vector3 = Vector3.ZERO
## The time it takes for the player to reach the apex of the jump.
var _t_up: float = 0.0
## The custom gravity applied while the player is ascending.
var _custom_gravity_up: float = 9.8
## The custom gravity applied while the player is descending.
var _custom_gravity_down: float = 9.8

## The last recorded position of the jump pad to detect movement.
var _last_start_pos: Vector3 = Vector3.ZERO
## The last recorded position of the target to detect movement.
var _last_target_pos: Vector3 = Vector3.ZERO

## Cached Target node to avoid repeated get_node calls.
var _target_node: Node3D
## Cached BallVisual node.
var _ball_visual: Node3D
## Cached LineVisual node.
var _line_visual: MeshInstance3D
## Cached ApexVisual node.
var _apex_visual: MeshInstance3D


func _enter_tree() -> void:
	_create_default_nodes()


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # Only detect Layer 2 (Player)

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	# Clean up visualizer nodes when the game actually runs
	if not Engine.is_editor_hint():
		for node_name: String in ["BallVisual", "LineVisual", "ApexVisual"]:
			var n: Node = get_node_or_null(node_name)
			if is_instance_valid(n):
				n.queue_free()

	_update_trajectory()


func _process(delta: float) -> void:
	if not is_instance_valid(_target_node):
		_target_node = get_node_or_null("Target") as Node3D

	if is_instance_valid(_target_node):
		if global_position != _last_start_pos or _target_node.global_position != _last_target_pos:
			_update_trajectory()
			_last_start_pos = global_position
			_last_target_pos = _target_node.global_position

	# Simulate the ball flight in the editor
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


func _update_trajectory() -> void:
	if not is_instance_valid(_target_node):
		_target_node = get_node_or_null("Target") as Node3D

	if not is_instance_valid(_target_node):
		return

	var p_start: Vector3 = global_position
	var p_end: Vector3 = _target_node.global_position

	var y_apex: float = maxf(p_start.y, p_end.y) + apex_height
	var h_start: float = y_apex - p_start.y
	var h_end: float = y_apex - p_end.y

	var g_up: float = player_gravity
	var g_down: float = player_gravity * fall_gravity_multiplier

	# Standard projectile equations
	var v_y0: float = sqrt(2.0 * g_up * h_start)
	var base_t_up: float = v_y0 / g_up
	var base_t_down: float = sqrt((2.0 * h_end) / g_down)
	var base_flight_time: float = base_t_up + base_t_down

	# Apply speed controls
	_flight_time = base_flight_time / flight_speed_multiplier
	_t_up = base_t_up / flight_speed_multiplier
	_custom_gravity_up = g_up * pow(flight_speed_multiplier, 2)
	_custom_gravity_down = g_down * pow(flight_speed_multiplier, 2)

	if _flight_time > 0.0:
		var v_xz: Vector3 = (p_end - p_start) / _flight_time
		_initial_velocity = Vector3(v_xz.x, v_y0 * flight_speed_multiplier, v_xz.z)
	else:
		_initial_velocity = Vector3.ZERO

	_update_visuals()


func _update_visuals() -> void:
	if not Engine.is_editor_hint() or _flight_time <= 0.0:
		return

	# Draw the Line
	if not is_instance_valid(_line_visual):
		_line_visual = get_node_or_null("LineVisual") as MeshInstance3D

	if is_instance_valid(_line_visual):
		_line_visual.top_level = false  # Allow it to inherit transforms naturally

		var imm_mesh: ImmediateMesh
		if _line_visual.mesh is ImmediateMesh:
			imm_mesh = _line_visual.mesh as ImmediateMesh
		else:
			imm_mesh = ImmediateMesh.new()
			_line_visual.mesh = imm_mesh
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = Color.CYAN
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_line_visual.material_override = mat

		imm_mesh.clear_surfaces()
		imm_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		var segments: int = 40

		# Convert global trajectory into local space for the ImmediateMesh
		var prev_pos: Vector3 = _line_visual.to_local(_get_position_at_time(0.0))

		for i: int in range(1, segments + 1):
			var t: float = _flight_time * (float(i) / float(segments))
			var curr_pos: Vector3 = _line_visual.to_local(_get_position_at_time(t))
			imm_mesh.surface_add_vertex(prev_pos)
			imm_mesh.surface_add_vertex(curr_pos)
			prev_pos = curr_pos

		imm_mesh.surface_end()

	# Position the Apex Marker
	if not is_instance_valid(_apex_visual):
		_apex_visual = get_node_or_null("ApexVisual") as MeshInstance3D

	if is_instance_valid(_apex_visual):
		_apex_visual.top_level = true
		_apex_visual.global_position = _get_position_at_time(_t_up)


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
		if is_instance_valid(_target_node):
			target_y = _target_node.global_position.y
		var y_apex: float = maxf(p0.y, target_y) + apex_height
		y = y_apex - 0.5 * _custom_gravity_down * td * td

	var xz: Vector3 = Vector3(_initial_velocity.x, 0.0, _initial_velocity.z) * t
	return Vector3(p0.x + xz.x, y, p0.z + xz.z)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.get_class() == "CharacterBody3D":
		print(
			"JumpPad: _on_body_entered() called. Launching player with velocity: ",
			_initial_velocity
		)
		body.velocity = _initial_velocity

		var sm: Node = body.get_node_or_null("StateMachine")
		if not is_instance_valid(sm):
			for child: Node in body.get_children():
				if child.has_method("transition_to"):
					sm = child
					break

		if is_instance_valid(sm) and sm.has_method("transition_to"):
			sm.transition_to(
				"Air",
				{
					"jump_pad": true,
					"launch_gravity": _custom_gravity_up,
					"launch_fall_gravity": _custom_gravity_down
				}
			)


func _get_or_create_internal_node(node_name: String, node_class: Variant) -> Node:
	var n: Node = get_node_or_null(node_name)
	if not is_instance_valid(n):
		n = node_class.new()
		n.name = node_name
		# Adding as INTERNAL_MODE_BACK hides it completely from the Scene Tree
		add_child(n, false, Node.INTERNAL_MODE_BACK)
	return n


func _create_default_nodes() -> void:
	# 1. Generate Hidden / Internal Nodes (Visible in viewport, hidden in Scene Tree)
	var col: CollisionShape3D = (
		_get_or_create_internal_node("CollisionShape3D", CollisionShape3D) as CollisionShape3D
	)
	if not col.shape:
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(2.0, 0.2, 2.0)
		col.shape = shape

	var pad: MeshInstance3D = (
		_get_or_create_internal_node("PadMesh", MeshInstance3D) as MeshInstance3D
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
			_get_or_create_internal_node("BallVisual", MeshInstance3D) as MeshInstance3D
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
			_get_or_create_internal_node("LineVisual", MeshInstance3D) as MeshInstance3D
		)
		line.top_level = true

		var apex: MeshInstance3D = (
			_get_or_create_internal_node("ApexVisual", MeshInstance3D) as MeshInstance3D
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

	# 2. Generate the Target Node (Explicitly NOT internal so you can see/edit it)
	var target: Marker3D = get_node_or_null("Target") as Marker3D
	if not is_instance_valid(target):
		target = Marker3D.new()
		target.name = "Target"
		target.position = Vector3(0.0, 5.0, -10.0)
		add_child(target)
		# Setting owner makes it save properly so your edits to the target stick
		if Engine.is_editor_hint() and is_inside_tree():
			target.owner = get_tree().edited_scene_root
