extends PickableObject
class_name TetheredPlug

signal power_state_changed(is_energized: bool)

@export_category("UI Components")
@export var highlight_comp: HighlightComponent

@export_category("Cable Physics")
@export_range(0.0, 1.0) var cable_elasticity: float = 0.0
@export var snap_marker: Marker3D

var anchor_point: Node3D
var max_cable_length: float 
var partner_plug: Node3D = null
var is_energized: bool = false

# --- NEW DRAG LOGIC ---
var _original_mass: float = 3.0
var _original_friction: float = 1.0

func _ready() -> void:
	# Save the default 3kg mass so we can restore it later
	_original_mass = mass
	
	# Safely grab the original friction if you are using a PhysicsMaterial
	if physics_material_override:
		_original_friction = physics_material_override.friction
	
	add_to_group("plug")
	
	if label: label.hide()
	
	# Wire up the hover interactions
	if interact_comp:
		interact_comp.focused.connect(_on_focus)
		interact_comp.unfocused.connect(_on_unfocus)

# --- UI & HIGHLIGHT LOGIC ---
func _update_lock_state() -> void:
	if is_locked:
		if label: label.hide()
		if highlight_comp: highlight_comp.suppress(true)
	else:
		if highlight_comp: highlight_comp.suppress(false)

func _on_focus() -> void:
	if is_locked: return # Ignore the cursor entirely if permanently plugged in
	
	if label:
		# Dynamically grab the player's keybind, just like you did in the socket!
		var events := InputMap.action_get_events("interact")
		var key_name := "???"
		if events.size() > 0:
			var raw_text := events[0].as_text()
			key_name = raw_text.replace(" (Physical)", "").replace(" - Physical", "").replace(" (Physics)", "").replace(" - Physics", "").replace("Left Mouse Button", "LMB").replace("Right Mouse Button", "RMB").replace("Middle Mouse Button", "MMB").strip_edges()

		label.text = "Grab Plug [%s]" % key_name
		label.show()

func _on_unfocus() -> void:
	if label: label.hide()

# --- POWER TRANSMISSION ---
func set_power_state(state: bool) -> void:
	if is_energized != state:
		is_energized = state
		power_state_changed.emit(is_energized)
		
		if is_instance_valid(partner_plug) and partner_plug.has_method("set_power_state"):
			partner_plug.set_power_state(state)

# --- PHYSICS LOGIC ---
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not is_instance_valid(anchor_point): 
		return
		
	var to_anchor := anchor_point.global_position - state.transform.origin
	var dist := to_anchor.length()
	
	if dist > (max_cable_length + 0.1):
		if is_held: 
			drop() 
			
		var dir := to_anchor.normalized()
		var overshoot := dist - max_cable_length
		
		var outward_vel := state.linear_velocity.dot(-dir)
		if outward_vel > 0:
			state.linear_velocity -= (-dir) * outward_vel
			
		if cable_elasticity <= 0.01:
			state.transform.origin += dir * overshoot 
		else:
			var spring_strength: float = lerpf(2.0, 15.0, cable_elasticity)
			state.linear_velocity += dir * (overshoot * spring_strength)

# Call this from your Player/Hand script when picking up THIS plug
func on_grabbed() -> void:
	if is_instance_valid(partner_plug) and partner_plug is TetheredPlug:
		partner_plug.set_trailing_mode(true)

# Call this from your Player/Hand script when dropping THIS plug
func on_released() -> void:
	if is_instance_valid(partner_plug) and partner_plug is TetheredPlug:
		partner_plug.set_trailing_mode(false)

# Modifies the physics state of the trailing plug
func set_trailing_mode(is_trailing: bool) -> void:
	if is_trailing:
		mass = 0.2 # Drop to 200g
		
		if physics_material_override:
			# Make sure the material is unique so it doesn't affect the held plug
			physics_material_override = physics_material_override.duplicate()
			physics_material_override.friction = 0.0 # Slide like ice
	else:
		mass = _original_mass
		
		if physics_material_override:
			physics_material_override.friction = _original_friction
