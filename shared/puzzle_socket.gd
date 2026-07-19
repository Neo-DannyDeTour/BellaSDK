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
@export var label: Label3D
@export var socket_interact_comp: InteractComponent

@export_category("Connections")
@export var transmitter: OutputTransmitter3D:
	set(value):
		transmitter = value
		_sync_transmitter()

# Keeps targets on the parent for easy level design, syncing automatically
@export var targets: Array[Node3D]:
	set(value):
		targets = value
		_sync_transmitter()

var is_powered: bool = false  # (Note: This means "Plug is Inserted" in base logic)
var current_plug: Node3D = null
var is_cooling_down: bool = false


func _ready() -> void:
	_sync_transmitter()

	if not Engine.is_editor_hint():
		if is_instance_valid(indicator_light):
			indicator_light.visible = true
			indicator_light.light_color = Color.RED  # <-- Default to Red

		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)

		if is_instance_valid(label):
			label.hide()

		if is_instance_valid(socket_interact_comp):
			socket_interact_comp.interacted.connect(_on_socket_interacted)
			socket_interact_comp.focused.connect(_on_socket_focused)
			socket_interact_comp.unfocused.connect(_on_socket_unfocused)


func _sync_transmitter() -> void:
	# Automatically pass the targets to the transmitter so it handles visual lines and logic
	if is_instance_valid(transmitter):
		transmitter.targets = targets


# --- THE INSTANT GRAB MAGIC ---
func _on_socket_interacted(character: CharacterBody3D) -> void:
	print("Socket: Player interacted with socket.")
	if is_powered and can_be_unplugged:
		var released_plug: Node3D = current_plug
		unplug()

		if is_instance_valid(released_plug) and released_plug.has_method("pick_up"):
			var player_hand_marker: Marker3D = character.get("hold_position") as Marker3D

			if is_instance_valid(player_hand_marker):
				# 1. Update the Player's inventory reference!
				character.set("held_object", released_plug)

				# 2. THE MASTER TELEPORT KEY
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


func _on_body_entered(body: Node3D) -> void:
	if not is_powered and body.is_in_group("plug") and not is_cooling_down:
		plug_in(body)


func _on_body_exited(body: Node3D) -> void:
	if is_powered and body == current_plug:
		unplug()


func plug_in(plug: Node3D) -> void:
	print("Socket: Plugging in ", plug.name)
	if plug.has_method("drop") and plug.get("is_held"):
		print("Socket: Plug is currently held. Forcing drop.")
		plug.drop()

	is_powered = true
	current_plug = plug

	# 1. Ensure physics from drop() completely settle before snapping
	_trigger_delayed_snap(plug)

	if not can_be_unplugged:
		if "is_locked" in plug:
			plug.set("is_locked", true)

	if is_instance_valid(socket_interact_comp) and socket_interact_comp.is_currently_focused:
		_on_socket_focused()

	# --- ELECTRICITY & LIGHT LOGIC ---
	if plug.has_signal("power_state_changed"):
		plug.power_state_changed.connect(_on_plug_power_changed)

	if is_power_source:
		if is_instance_valid(indicator_light):
			indicator_light.light_color = Color.GREEN
		if plug.has_method("set_power_state"):
			plug.set_power_state(true)
	else:
		if requires_power_link:
			if plug.get("is_energized") == true:
				if is_instance_valid(indicator_light):
					indicator_light.light_color = Color.GREEN
				_energize_targets()
			else:
				if is_instance_valid(indicator_light):
					indicator_light.light_color = Color.YELLOW
		else:
			if is_instance_valid(indicator_light):
				indicator_light.light_color = Color.GREEN
			_energize_targets()


func _trigger_delayed_snap(plug: Node3D) -> void:
	print("Socket: Awaiting physics frame to guarantee clean state.")
	await get_tree().physics_frame

	if is_instance_valid(plug) and is_powered:
		_snap_and_freeze_plug(plug)


func unplug() -> void:
	print("Socket: Unplug sequence initiated.")
	if not can_be_unplugged or not is_powered:
		return

	if is_instance_valid(current_plug):
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

	# OPTIMIZATION: Use a SceneTreeTimer instead of calculating cooldown mathematically in _process
	is_cooling_down = true
	get_tree().create_timer(1.0, false).timeout.connect(func() -> void: is_cooling_down = false)

	if current_plug is RigidBody3D:
		var rb_plug := current_plug as RigidBody3D
		rb_plug.freeze = false
		if "is_locked" in rb_plug:
			rb_plug.set("is_locked", false)

	current_plug = null

	# --- Reset to Default State ---
	if is_instance_valid(indicator_light):
		indicator_light.visible = true
		indicator_light.light_color = Color.RED


# --- THE MISSING UI LOGIC ---
func _on_socket_focused() -> void:
	if not is_instance_valid(label):
		return

	var events: Array[InputEvent] = InputMap.action_get_events("interact")
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

	if is_powered and can_be_unplugged:
		label.text = "Unplug [%s]" % key_name
		label.show()
	elif not is_powered:
		label.text = "Requires Plug"
		label.show()
	else:
		label.hide()  # It's powered and locked forever, hide UI


func _on_socket_unfocused() -> void:
	if is_instance_valid(label):
		label.hide()


# --- Helpers to manage Target Triggers cleanly ---
func _on_plug_power_changed(has_power: bool) -> void:
	# If a plug is sitting in a receiver socket, and the OTHER end changes state
	if not is_power_source and is_powered and requires_power_link:
		if has_power:
			if is_instance_valid(indicator_light):
				indicator_light.light_color = Color.GREEN
			_energize_targets()
		else:
			if is_instance_valid(indicator_light):
				indicator_light.light_color = Color.YELLOW
			_deenergize_targets()


func _energize_targets() -> void:
	print("Socket: Energizing targets via Transmitter.")
	socket_powered_on.emit()
	if is_instance_valid(transmitter):
		transmitter.power_on()
	else:
		push_warning("Socket: Missing OutputTransmitter3D! Cannot energize targets.")


func _deenergize_targets() -> void:
	print("Socket: De-energizing targets via Transmitter.")
	socket_powered_off.emit()
	if is_instance_valid(transmitter):
		transmitter.power_off()
	else:
		push_warning("Socket: Missing OutputTransmitter3D! Cannot de-energize targets.")


func _snap_and_freeze_plug(plug: Node3D) -> void:
	print("Socket: Snapping and freezing plug to exact center.")
	if not is_instance_valid(plug) or not is_instance_valid(snap_position):
		return

	var target_transform: Transform3D = snap_position.global_transform

	if "snap_marker" in plug and is_instance_valid(plug.get("snap_marker")):
		var marker: Marker3D = plug.get("snap_marker") as Marker3D
		target_transform = target_transform * marker.transform.affine_inverse()

	if plug is RigidBody3D:
		# Clear momentum to prevent physics engine fighting
		plug.linear_velocity = Vector3.ZERO
		plug.angular_velocity = Vector3.ZERO

		# Force Transform on the Physics server FIRST
		PhysicsServer3D.body_set_state(
			plug.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, target_transform
		)

		# Apply to node and freeze LAST
		plug.global_transform = target_transform
		plug.freeze = true
	else:
		plug.global_transform = target_transform
