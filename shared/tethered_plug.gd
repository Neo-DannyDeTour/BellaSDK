class_name TetheredPlug
extends PickableObject

signal power_state_changed(is_energized: bool)

## Defines how stretchy the cable is (0.0 is completely rigid, 1.0 is highly elastic).
@export_category("Cable Physics")
@export_range(0.0, 1.0) var cable_elasticity: float = 0.0

## The Marker3D node used to determine the exact snapping position when plugging into a socket.
@export var snap_marker: Marker3D

## The point where the cable originates.
var anchor_point: Node3D
## The maximum allowed length of the cable.
var max_cable_length: float
## The connected partner plug at the other end of the cable.
var partner_plug: Node3D = null
## Indicates whether the plug is currently supplying power.
var is_energized: bool = false
## Indicates whether the plug is currently being dragged heavily.
var is_trailing_mode: bool = false

# --- NEW DRAG LOGIC ---
## Internal cache for the original physics mass.
var _original_mass: float = 3.0
## Internal cache for the original physics friction.
var _original_friction: float = 1.0
## Internal cache for the original physics linear dampening.
var _original_linear_damp: float = 0.0
## Internal cache for the original physics angular dampening.
var _original_angular_damp: float = 0.0


func _ready() -> void:
	_original_mass = mass
	_original_linear_damp = linear_damp
	_original_angular_damp = angular_damp

	if physics_material_override:
		_original_friction = physics_material_override.friction

	add_to_group("plug")

	if label:
		label.hide()

	if interact_comp:
		if not interact_comp.focused.is_connected(_on_focus):
			interact_comp.focused.connect(_on_focus)
		if not interact_comp.unfocused.is_connected(_on_unfocus):
			interact_comp.unfocused.connect(_on_unfocus)

	# --- FULL PLUG SHADER WARM-UP ---
	# By passing 'self' instead of 'mesh', we recursively compile
	# every single mesh attached to this plug, not just the main one.
	_set_model_transparency(self, held_transparency)

	# We yield twice to ensure the renderer catches the state
	await get_tree().process_frame
	await get_tree().process_frame
	_set_model_transparency(self, 0.0)


# --- UI & HIGHLIGHT LOGIC ---
func _update_lock_state() -> void:
	print("TetheredPlug: _update_lock_state() called. Lock state: ", is_locked)
	if is_locked:
		if label:
			label.hide()
		if highlight_comp:
			highlight_comp.suppress(true)
	else:
		if highlight_comp:
			highlight_comp.suppress(false)


func _on_focus() -> void:
	if is_locked:
		return  # Ignore the cursor entirely if permanently plugged in

	print("TetheredPlug: _on_focus() called. Updating UI label.")
	if label:
		# Dynamically grab the player's keybind, just like you did in the socket!
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

		label.text = "Grab Plug [%s]" % key_name
		label.show()


func _on_unfocus() -> void:
	print("TetheredPlug: _on_unfocus() called. Hiding UI label.")
	if label:
		label.hide()


# --- POWER TRANSMISSION ---
func set_power_state(state: bool) -> void:
	print("TetheredPlug: set_power_state() called. Energized: ", state)
	if is_energized != state:
		is_energized = state
		power_state_changed.emit(is_energized)

		if is_instance_valid(partner_plug) and partner_plug.has_method("set_power_state"):
			partner_plug.set_power_state(state)


# --- PHYSICS LOGIC ---
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not is_instance_valid(anchor_point):
		return

	# 1. The player dictates movement. The held plug ignores limits.
	if not is_trailing_mode:
		return

	# 2. The trailing plug forcefully pulls itself to keep up with the held plug.
	var to_anchor: Vector3 = anchor_point.global_position - state.transform.origin
	var dist: float = to_anchor.length()

	if dist > max_cable_length:
		var dir: Vector3 = to_anchor.normalized()
		var overshoot: float = dist - max_cable_length

		var outward_vel: float = state.linear_velocity.dot(-dir)
		if outward_vel > 0.0:
			state.linear_velocity -= (-dir) * outward_vel

		if cable_elasticity <= 0.01:
			state.transform.origin += dir * overshoot
		else:
			var spring_strength: float = lerpf(2.0, 15.0, cable_elasticity)
			state.linear_velocity += dir * (overshoot * spring_strength)


# Call this from your Player/Hand script when picking up THIS plug
func on_grabbed() -> void:
	print("TetheredPlug: on_grabbed() called. Initializing trailing mode on partner.")
	if is_instance_valid(partner_plug) and partner_plug is TetheredPlug:
		partner_plug.set_trailing_mode(true)


# Call this from your Player/Hand script when dropping THIS plug
func on_released() -> void:
	print("TetheredPlug: on_released() called. Disabling trailing mode on partner.")
	if is_instance_valid(partner_plug) and partner_plug is TetheredPlug:
		partner_plug.set_trailing_mode(false)


# Modifies the physics state of the trailing plug
func set_trailing_mode(is_trailing: bool) -> void:
	print("TetheredPlug: set_trailing_mode() called. Mode active: ", is_trailing)
	is_trailing_mode = is_trailing

	if is_trailing:
		mass = 0.05  # Extremely light
		gravity_scale = 0.0  # No falling
		linear_damp = 0.0  # ZERO air friction
		angular_damp = 0.0  # ZERO rotational friction

		if physics_material_override:
			physics_material_override = physics_material_override.duplicate()
			physics_material_override.friction = 0.0
	else:
		mass = _original_mass
		gravity_scale = 1.0
		linear_damp = _original_linear_damp
		angular_damp = _original_angular_damp

		if physics_material_override:
			physics_material_override.friction = _original_friction
