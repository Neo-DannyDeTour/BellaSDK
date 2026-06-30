@tool
extends StaticBody3D

const DOUBLE_TAP_DELAY: float = 0.3

@export_category("Connections")
@export var targets: Array[Node3D]

@export_category("Installation Settings")
@export var requires_installation: bool = false
@export var pickable_valve_scene: PackedScene

@export var can_be_detached: bool = false:
	set(value):
		can_be_detached = value
		if can_be_detached:
			lock_when_finished = false

@export_category("Valve Settings")
@export var turn_duration: float = 3.0
@export var visual_rotations: float = 2.0
@export var turn_clockwise: bool = true

@export var lock_when_finished: bool = false:
	set(value):
		lock_when_finished = value
		if lock_when_finished:
			can_be_detached = false

@export var is_back_and_forth: bool = true:
	set(value):
		is_back_and_forth = value
		if is_back_and_forth:
			reverts_on_release = false

@export var reverts_on_release: bool = false:
	set(value):
		reverts_on_release = value
		if reverts_on_release:
			is_back_and_forth = false
		else:
			fast_revert_on_release = false

@export var fast_revert_on_release: bool = false:
	set(value):
		fast_revert_on_release = value
		if fast_revert_on_release:
			reverts_on_release = true

@export var fast_revert_multiplier: float = 4.0
@export var spin_axis: Vector3 = Vector3(0, 1, 0)
@export var label: Label3D
@export var outline_material: ShaderMaterial

@onready var valve_audio: AudioStreamPlayer3D = get_node_or_null("ValveAudio")

var progress: float = 0.0
var is_focused: bool = false
var current_target_progress: float = 1.0
var is_locked: bool = false
var was_interacting: bool = false
var is_installed: bool = true

var last_interact_time: float = 0.0
var wheel: Node3D
var debug_line: MeshInstance3D
var initial_rotation: Vector3
var highlight_comp: Node
var install_cooldown: float = 0.0
var has_been_installed: bool = false

var _cached_player: Node3D = null


func _ready() -> void:
	print("Valve: _ready() initialized.")
	
	if requires_installation:
		is_installed = false
		has_been_installed = false
	else:
		has_been_installed = true
		
	if Engine.is_editor_hint():
		return

	wheel = get_node_or_null("Wheel")
	if is_instance_valid(wheel):
		initial_rotation = wheel.rotation_degrees
		if requires_installation:
			wheel.hide()
	else:
		push_warning("Valve: Please group meshes under Node3D named 'Wheel'!")

	highlight_comp = get_node_or_null("HighlightComponent")

	var interact_comp: Node = get_node_or_null("Interact_Component")
	if is_instance_valid(interact_comp):
		if not interact_comp.focused.is_connected(_on_interact_component_focused):
			interact_comp.focused.connect(_on_interact_component_focused)
		if not interact_comp.unfocused.is_connected(_on_interact_component_unfocused):
			interact_comp.unfocused.connect(_on_interact_component_unfocused)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_draw_connection_line()
		return

	if install_cooldown > 0.0:
		install_cooldown -= delta

	if not is_installed and install_cooldown <= 0.0:
		if not is_instance_valid(_cached_player):
			_cached_player = get_tree().get_first_node_in_group("player") as Node3D
			
		if is_instance_valid(_cached_player):
			var held: Node3D = _get_player_held_object(_cached_player)
			
			if is_instance_valid(held):
				# OPTIMIZATION: Avoid square root math by using distance_squared_to (0.6 * 0.6 = 0.36)
				var dist_sq: float = global_position.distance_squared_to(held.global_position)
				if dist_sq < 0.36: 
					_install_valve(_cached_player, held)

	var is_interacting: bool = (
		is_focused and Input.is_action_pressed("interact") and is_installed
	)
	var just_pressed: bool = (
		is_focused and Input.is_action_just_pressed("interact") and is_installed
	)

	if can_be_detached and just_pressed:
		var current_time: float = Time.get_ticks_msec() / 1000.0
		if current_time - last_interact_time <= DOUBLE_TAP_DELAY:
			_detach_valve()
			last_interact_time = 0.0
			return
		else:
			last_interact_time = current_time

	if is_locked:
		_manage_audio(false)
		return

	if is_instance_valid(highlight_comp) and highlight_comp.has_method("suppress"):
		highlight_comp.suppress(is_interacting)

	if is_interacting and not was_interacting:
		if is_back_and_forth and progress > 0.0 and progress < 1.0:
			current_target_progress = 0.0 if current_target_progress == 1.0 else 1.0

	var old_progress: float = progress

	if is_interacting:
		progress = move_toward(progress, current_target_progress, delta / turn_duration)
		if lock_when_finished and progress >= 1.0:
			is_locked = true
			progress = 1.0
	else:
		if reverts_on_release:
			var revert_target: float = 0.0 if current_target_progress == 1.0 else 1.0
			var current_turn_duration: float = turn_duration
			
			if fast_revert_on_release:
				current_turn_duration = turn_duration / fast_revert_multiplier
				if was_interacting:
					print("Valve: Released, initiating fast revert towards ", revert_target)
			
			progress = move_toward(progress, revert_target, delta / current_turn_duration)

	if is_back_and_forth and not is_interacting:
		if progress >= 1.0:
			current_target_progress = 0.0
		elif progress <= 0.0:
			current_target_progress = 1.0

	# OPTIMIZATION: Only calculate rotation matrix and loop targets if the valve is actively spinning
	var is_moving: bool = not is_equal_approx(progress, old_progress)
	
	if is_moving:
		if is_instance_valid(wheel):
			var dir_multiplier: float = -1.0 if turn_clockwise else 1.0
			var total_angle: float = 360.0 * visual_rotations * dir_multiplier * progress
			wheel.rotation_degrees = initial_rotation + (spin_axis * total_angle)

		for target: Node3D in targets:
			if is_instance_valid(target) and target.has_method("set_progress"):
				target.set_progress(progress)

	_manage_audio(is_moving)
	was_interacting = is_interacting


func _manage_audio(is_moving: bool) -> void:
	if not is_instance_valid(valve_audio):
		return
		
	if is_moving and not valve_audio.playing:
		print("Valve: Started playing turning audio.")
		valve_audio.play()
	elif not is_moving and valve_audio.playing:
		print("Valve: Stopped turning audio.")
		valve_audio.stop()


# --- COMPATIBILITY BRIDGE ---
func _get_player_held_object(player: Node3D) -> Node3D:
	if not is_instance_valid(player):
		return null
		
	# 1. Legacy Check
	if "held_object" in player and player.get("held_object") != null:
		return player.get("held_object") as Node3D
		
	# 2. Component Check
	var int_comp: Node = player.get("interaction_component") if "interaction_component" in player else null
	if is_instance_valid(int_comp):
		if "held_item" in int_comp and int_comp.get("held_item") != null:
			return int_comp.get("held_item") as Node3D
			
		var scanner: Node = int_comp.get("interaction_scanner") if "interaction_scanner" in int_comp else null
		if is_instance_valid(scanner) and "held_object" in scanner and scanner.get("held_object") != null:
			return scanner.get("held_object") as Node3D
			
	return null


func _clear_player_held_object(player: Node3D) -> void:
	print("Valve: Clearing player held object references.")
	if "held_object" in player:
		player.set("held_object", null)
		
	var int_comp: Node = player.get("interaction_component") if "interaction_component" in player else null
	if is_instance_valid(int_comp):
		if int_comp.has_method("force_clear_hands"):
			int_comp.force_clear_hands()
		elif "held_item" in int_comp:
			int_comp.set("held_item", null)


func _install_valve(player: Node3D, held_valve: Node3D) -> void:
	print("Valve: _install_valve() called. Destroying pickable valve.")
	if is_instance_valid(held_valve):
		held_valve.queue_free()
		
	_clear_player_held_object(player)

	is_installed = true
	has_been_installed = true
	is_locked = false
	current_target_progress = 1.0

	if is_instance_valid(wheel):
		wheel.show()

	var weapon_holder: Node3D = player.get_node_or_null("%WeaponHolder")
	if is_instance_valid(weapon_holder):
		weapon_holder.show()
	print("Valve: Valve Auto-Installed!")


func _detach_valve() -> void:
	print("Valve: _detach_valve() called.")
	if not pickable_valve_scene:
		push_warning("Cannot detach: No Pickable Valve Scene assigned!")
		return

	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if not is_instance_valid(player):
		return

	var spawned_valve: Node3D = pickable_valve_scene.instantiate() as Node3D

	if is_instance_valid(outline_material) and "outline_material" in spawned_valve:
		spawned_valve.set("outline_material", outline_material)

	get_tree().current_scene.add_child(spawned_valve)
	
	if "hold_position" in player and is_instance_valid(player.get("hold_position")):
		spawned_valve.global_position = player.get("hold_position").global_position

	if is_instance_valid(wheel):
		spawned_valve.global_position = wheel.global_position
		spawned_valve.global_rotation = wheel.global_rotation
	else:
		spawned_valve.global_position = global_position

	# Use the new forceful component grab if it exists
	var grabbed_successfully: bool = false
	var int_comp: Node = player.get("interaction_component") if "interaction_component" in player else null
	
	if is_instance_valid(int_comp) and int_comp.has_method("force_grab_item"):
		int_comp.force_grab_item(spawned_valve as RigidBody3D)
		grabbed_successfully = true
	elif "held_object" in player:
		player.set("held_object", spawned_valve)

	# Only manually call pick_up if the component didn't already handle it
	if not grabbed_successfully and spawned_valve.has_method("pick_up") and "hold_position" in player:
		spawned_valve.pick_up(player.get("hold_position"), player)

	var weapon_holder: Node3D = player.get_node_or_null("%WeaponHolder")
	if is_instance_valid(weapon_holder) and not grabbed_successfully:
		weapon_holder.hide()

	is_installed = false
	is_locked = false
	install_cooldown = 1.0

	if is_instance_valid(wheel):
		wheel.hide()


func _on_interact_component_focused() -> void:
	print("Valve: _on_interact_component_focused() called.")
	if is_locked:
		return
	is_focused = true
	if is_instance_valid(label):
		_update_valve_label()
		label.show()


func _on_interact_component_unfocused() -> void:
	print("Valve: _on_interact_component_unfocused() called.")
	is_focused = false
	if is_instance_valid(label):
		label.hide()


func _draw_connection_line() -> void:
	if not targets or targets.is_empty():
		if is_instance_valid(debug_line):
			debug_line.queue_free()
			debug_line = null
		return

	if not is_instance_valid(debug_line):
		debug_line = MeshInstance3D.new()
		add_child(debug_line)
		debug_line.top_level = true
		debug_line.global_transform = Transform3D.IDENTITY

		var immediate_mesh := ImmediateMesh.new()
		debug_line.mesh = immediate_mesh

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color.RED
		mat.no_depth_test = true
		debug_line.material_override = mat

	var mesh: ImmediateMesh = debug_line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	for target: Node3D in targets:
		if is_instance_valid(target):
			mesh.surface_add_vertex(global_position)
			mesh.surface_add_vertex(target.global_position)

	mesh.surface_end()


func _update_valve_label() -> void:
	print("Valve: _update_valve_label() called.")
	if not is_instance_valid(label):
		return

	if is_installed:
		var events: Array = InputMap.action_get_events("interact")
		var key_name: String = "???"

		if events.size() > 0:
			var raw_text: String = events[0].as_text()
			key_name = (
				raw_text
				. replace(" (Physical)", "")
				. replace(" - Physical", "")
				. replace(" (Physics)", "")
				. replace(" - Physics", "")
				. replace("Left Mouse Button", "LMB")
				. replace("Right Mouse Button", "RMB")
				. replace("Middle Mouse Button", "MMB")
				. strip_edges()
			)

		var text: String = "Hold [%s]" % key_name
		if can_be_detached:
			text += "\nDouble tap [%s] to detach" % key_name

		label.text = text

	elif has_been_installed:
		label.text = "Attach the valve"
	else:
		label.text = "Find the valve"
