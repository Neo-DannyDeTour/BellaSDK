@tool
class_name PuzzleSocket
extends Area3D

signal socket_powered_on
signal socket_powered_off

@export_group("Socket Settings")
@export var is_power_source: bool = false
@export var requires_power_link: bool = false
@export var can_be_unplugged: bool = true
@export var snap_position: Marker3D 
@export var indicator_light: Light3D
@export var targets: Array[Node3D]
@export var label: Label3D
@export var socket_interact_comp: Interact_Component

var is_powered: bool = false # (Note: This means "Plug is Inserted" in your base logic)
var current_plug: Node3D = null

var debug_line: MeshInstance3D
var install_cooldown: float = 0.0

func _ready() -> void:
	if not Engine.is_editor_hint():
		if indicator_light:
			indicator_light.visible = true
			indicator_light.light_color = Color.RED # <-- Default to Red
			
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)
		
		if label: label.hide()
		
		if socket_interact_comp:
			socket_interact_comp.interacted.connect(_on_socket_interacted)
			
			# --- THE UI FIX: Wire up the focus signals ---
			socket_interact_comp.focused.connect(_on_socket_focused)
			socket_interact_comp.unfocused.connect(_on_socket_unfocused)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_draw_connection_line()
	else:
		if install_cooldown > 0.0:
			install_cooldown -= delta

# --- THE INSTANT GRAB MAGIC ---
func _on_socket_interacted(character: CharacterBody3D) -> void:
	if is_powered and can_be_unplugged:
		var released_plug := current_plug 
		unplug() 
		
		if released_plug and released_plug.has_method("pick_up"):
			
			var player_hand_marker: Marker3D = character.get("hold_position") as Marker3D
			
			if player_hand_marker:
				# 1. Update the Player's inventory reference!
				character.set("held_object", released_plug)
				
				# 2. THE MASTER TELEPORT KEY
				# This bypasses the RigidBody system and forces the 3D server 
				# to move the object instantly before picking it up.
				if released_plug is RigidBody3D:
					PhysicsServer3D.body_set_state(
						released_plug.get_rid(),
						PhysicsServer3D.BODY_STATE_TRANSFORM,
						player_hand_marker.global_transform
					)
					released_plug.linear_velocity = Vector3.ZERO
					released_plug.angular_velocity = Vector3.ZERO
					
				# 3. Grab it natively
				released_plug.pick_up(player_hand_marker, character)
				
				# 4. Force hide the socket's UI immediately since we just grabbed it
				_on_socket_unfocused()
			else:
				push_warning("Socket: Could not find hold_position on Player!")
# ------------------------------

func _on_body_entered(body: Node3D) -> void:
	# --- THE FIX: Only allow plugging in if the cooldown is at 0 ---
	if not is_powered and body.is_in_group("plug") and install_cooldown <= 0.0:
		plug_in(body)

func _on_body_exited(body: Node3D) -> void:
	if is_powered and body == current_plug:
		unplug()

func plug_in(plug: Node3D) -> void:
	if plug.has_method("drop") and plug.get("is_held"):
		plug.drop()
		
	is_powered = true
	current_plug = plug
	
	# 1. Let the deferred function handle ALL the physics and snapping
	call_deferred("_snap_and_freeze_plug", plug)
		
	if not can_be_unplugged:
		if "is_locked" in plug:
			plug.is_locked = true
			
	if socket_interact_comp and socket_interact_comp.is_currently_focused:
		_on_socket_focused()
			
	# --- ELECTRICITY & LIGHT LOGIC ---
	if plug.has_signal("power_state_changed"):
		plug.power_state_changed.connect(_on_plug_power_changed)

	if is_power_source:
		if indicator_light: indicator_light.light_color = Color.GREEN
		if plug.has_method("set_power_state"):
			plug.set_power_state(true)
	else:
		if requires_power_link:
			if plug.get("is_energized") == true:
				if indicator_light: indicator_light.light_color = Color.GREEN
				_energize_targets()
			else:
				if indicator_light: indicator_light.light_color = Color.YELLOW
		else:
			if indicator_light: indicator_light.light_color = Color.GREEN
			_energize_targets()
			
func unplug() -> void:
	if not can_be_unplugged or not is_powered:
		return
		
	if current_plug:
		if is_power_source:
			if current_plug.has_method("set_power_state"):
				current_plug.set_power_state(false)
		else:
			if requires_power_link:
				if current_plug.get("is_energized") == true:
					_deenergize_targets()
			else:
				# Standard simple socket lost its plug
				_deenergize_targets() 
				
		if current_plug.has_signal("power_state_changed"):
			current_plug.power_state_changed.disconnect(_on_plug_power_changed)

	is_powered = false
	install_cooldown = 1.0 
	
	if current_plug is RigidBody3D:
		current_plug.freeze = false
		# We removed the collision layer changes here!
		if "is_locked" in current_plug:
			current_plug.is_locked = false
		
	current_plug = null
	
	# --- Reset to Default State ---
	if indicator_light:
		indicator_light.visible = true
		indicator_light.light_color = Color.RED

# --- THE MISSING UI LOGIC ---
func _on_socket_focused() -> void:
	if not label: return
	
	var events := InputMap.action_get_events("interact")
	var key_name := "???"
	if events.size() > 0:
		var raw_text := events[0].as_text()
		key_name = raw_text.replace(" (Physical)", "").replace(" - Physical", "").replace(" (Physics)", "").replace(" - Physics", "").replace("Left Mouse Button", "LMB").replace("Right Mouse Button", "RMB").replace("Middle Mouse Button", "MMB").strip_edges()

	if is_powered and can_be_unplugged:
		label.text = "Unplug [%s]" % key_name
		label.show()
	elif not is_powered:
		label.text = "Requires Plug"
		label.show()
	else:
		label.hide() # It's powered and locked forever, hide UI

func _on_socket_unfocused() -> void:
	if label: label.hide()
# ----------------------------

# --- EDITOR DEBUG LINE ---
func _draw_connection_line() -> void:
	if not targets:
		if debug_line:
			debug_line.queue_free()
		return

	if not debug_line:
		debug_line = MeshInstance3D.new()
		add_child(debug_line)
		
		var immediate_mesh := ImmediateMesh.new()
		debug_line.mesh = immediate_mesh
		
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color.RED
		debug_line.material_override = mat

	var mesh := debug_line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	for target in targets:
		if target:
			mesh.surface_add_vertex(Vector3.ZERO) 
			mesh.surface_add_vertex(to_local(target.global_position)) 
	
	mesh.surface_end()

# --- Helpers to manage Target Triggers cleanly ---
func _on_plug_power_changed(has_power: bool) -> void:
	# If a plug is sitting in a receiver socket, and the OTHER end changes state
	if not is_power_source and is_powered and requires_power_link: 
		if has_power:
			if indicator_light: indicator_light.light_color = Color.GREEN
			_energize_targets()
		else:
			if indicator_light: indicator_light.light_color = Color.YELLOW
			_deenergize_targets()

func _energize_targets() -> void:
	socket_powered_on.emit()
	for target in targets:
		if target and target.has_method("power_on"):
			target.power_on()

func _deenergize_targets() -> void:
	socket_powered_off.emit()
	for target in targets:
		if target and target.has_method("power_off"):
			target.power_off()

func _snap_and_freeze_plug(plug: Node3D) -> void:
	if not is_instance_valid(plug) or not snap_position: 
		return
		
	if "snap_marker" in plug and is_instance_valid(plug.get("snap_marker")):
		var marker: Marker3D = plug.get("snap_marker") as Marker3D
		plug.global_transform = snap_position.global_transform * marker.transform.affine_inverse()
	else:
		plug.global_transform = snap_position.global_transform
		
	if plug is RigidBody3D:
		plug.freeze = true
		plug.linear_velocity = Vector3.ZERO
		plug.angular_velocity = Vector3.ZERO
		
		# We removed the collision layer changes here!
		
		PhysicsServer3D.body_set_state(
			plug.get_rid(),
			PhysicsServer3D.BODY_STATE_TRANSFORM,
			plug.global_transform
		)
