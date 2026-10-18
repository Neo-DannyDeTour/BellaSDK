## Pickable tethered plug managing cable physics and circuit power states.
class_name TetheredPlug
extends PickableObject

## Emitted when the plug's energized circuit state changes.
signal power_state_changed(is_energized: bool)

@export_category("Cable Physics")

## Elasticity ratio of the cable connecting both ends.
@export_range(0.0, 1.0) var cable_elasticity: float = 0.0

## Reference [Marker3D] defining the alignment socket snap point.
@export var snap_marker: Marker3D

## Anchor [Node3D] origin point where the cable begins.
var anchor_point: Node3D

## Maximum allowed reach distance before tension pulls the plug.
var max_cable_length: float

## Connected partner plug instance on the opposite cable end.
var partner_plug: TetheredPlug = null

## Indicates whether current plug actively conducts energy.
var is_energized: bool = false

## Indicates if plug is pulled along behind player as trailing mass.
var is_trailing_mode: bool = false

## Cached base mass value to restore after trailing mode.
var _original_mass: float = 3.0

## Cached base physics material friction value.
var _original_friction: float = 1.0

## Cached base air linear damping value.
var _original_linear_damp: float = 0.0

## Cached base rotational angular damping value.
var _original_angular_damp: float = 0.0


## Caches initial physics values, groups, and warms up shaders.
func _ready() -> void:
	print("TetheredPlug: Initializing _ready() lifecycle.")
	_original_mass = mass
	_original_linear_damp = linear_damp
	_original_angular_damp = angular_damp

	if is_instance_valid(physics_material_override):
		_original_friction = physics_material_override.friction

	add_to_group(&"plug")

	if is_instance_valid(label):
		label.hide()

	if is_instance_valid(interact_comp):
		if not interact_comp.focused.is_connected(_on_focus):
			interact_comp.focused.connect(_on_focus)
		if not interact_comp.unfocused.is_connected(_on_unfocus):
			interact_comp.unfocused.connect(_on_unfocus)

	_set_model_transparency(self, held_transparency)
	await get_tree().process_frame
	await get_tree().process_frame
	_set_model_transparency(self, 0.0)


## Synchronizes highlight component and prompt label with lock state.
func _update_lock_state() -> void:
	print("TetheredPlug: _update_lock_state() -> ", is_locked)
	if is_locked:
		if is_instance_valid(label):
			label.hide()
		if is_instance_valid(highlight_comp):
			highlight_comp.call(&"suppress", true)
	else:
		if is_instance_valid(highlight_comp):
			highlight_comp.call(&"suppress", false)


## Builds key prompt string and displays interact label on focus.
func _on_focus() -> void:
	if is_locked:
		return

	print("TetheredPlug: _on_focus() displaying grab prompt.")
	if not is_instance_valid(label):
		return

	var events: Array[InputEvent] = InputMap.action_get_events(&"interact")
	var key_name: String = "E"
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


## Hides interact label when aim focus leaves plug volume.
func _on_unfocus() -> void:
	print("TetheredPlug: _on_unfocus() hiding grab prompt.")
	if is_instance_valid(label):
		label.hide()


## Sets energized state and propagates update to partner plug.
func set_power_state(state: bool) -> void:
	print("TetheredPlug: Setting power state -> ", state)
	if is_energized != state:
		is_energized = state
		power_state_changed.emit(is_energized)

		if is_instance_valid(partner_plug):
			partner_plug.set_power_state(state)


## Applies trailing tension constraint forces relative to anchor.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not is_instance_valid(anchor_point):
		return

	if not is_trailing_mode:
		return

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


## Engages trailing physics on partner plug upon being picked up.
func on_grabbed() -> void:
	print("TetheredPlug: on_grabbed() called. Partner trailing engaged.")
	if is_instance_valid(partner_plug):
		partner_plug.set_trailing_mode(true)


## Disengages trailing physics on partner plug when released.
func on_released() -> void:
	print("TetheredPlug: on_released() called. Partner trailing released.")
	if is_instance_valid(partner_plug):
		partner_plug.set_trailing_mode(false)


## Toggles low-mass zero-gravity state for dragging behind player.
func set_trailing_mode(is_trailing: bool) -> void:
	print("TetheredPlug: set_trailing_mode() -> ", is_trailing)
	is_trailing_mode = is_trailing

	if is_trailing:
		mass = 0.05
		gravity_scale = 0.0
		linear_damp = 0.0
		angular_damp = 0.0

		if is_instance_valid(physics_material_override):
			physics_material_override = (physics_material_override.duplicate() as PhysicsMaterial)
			physics_material_override.friction = 0.0
	else:
		mass = _original_mass
		gravity_scale = 1.0
		linear_damp = _original_linear_damp
		angular_damp = _original_angular_damp

		if is_instance_valid(physics_material_override):
			physics_material_override.friction = _original_friction
