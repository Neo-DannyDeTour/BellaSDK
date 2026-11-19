@tool
## Generator socket with articulated claw that accepts a charged cell to power targets.
class_name WallGenerator
extends StaticBody3D

# --------------------------------------
# SIGNALS
# --------------------------------------
## Emitted when an [EnergyCell] is successfully inserted.
signal cell_inserted(cell: EnergyCell)

## Emitted when an [EnergyCell] is removed from the generator.
signal cell_ejected(cell: EnergyCell)

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Pre-allocated shader uniform name for indicator LED color.
const PARAM_LED_COLOR: StringName = &"led_color"
## Pre-allocated shader uniform name for indicator LED blink speed.
const PARAM_BLINK_SPEED: StringName = &"blink_speed"
## Pre-allocated shader uniform name for indicator LED emission intensity.
const PARAM_INTENSITY: StringName = &"intensity"
## Retracted local Z offset of [member _claw_arm] inside the socket bay.
const CLAW_RETRACT_Z: float = 0.05
## Extended local Z offset of [member _claw_arm] when reaching for or presenting a cell.
const CLAW_EXTEND_Z: float = 0.24
## Open pincer yaw angle in degrees.
const CLAW_OPEN_DEG: float = 28.0
## Closed pincer yaw angle in degrees when gripping a cell.
const CLAW_GRIP_DEG: float = 6.0
## Blink frequency in radians per second when generator is empty or depleted.
const RED_BLINK_SPEED: float = 8.0

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Transmitter")
## Targets powered by the generator. Forwarded to [OutputTransmitter3D].
@export var transmitter_targets: Array[Node3D] = []:
	set(value):
		transmitter_targets = value
		if not is_instance_valid(transmitter):
			transmitter = get_node_or_null("OutputTransmitter3D") as OutputTransmitter3D
		if is_instance_valid(transmitter):
			transmitter.targets = value

@export_category("Configuration")
## Angle in degrees to tilt an uncharged cell forward for grab.
@export var eject_tilt_degrees: float = 30.0

## Half height of the [EnergyCell] used as pivot offset for tilt.
@export var cell_half_height: float = 0.25

## Cooldown duration in seconds before cell can re-enter after pickup.
@export var reinsertion_cooldown: float = 1.0

## Forward offset in meters when the claw presents a depleted cell to the player.
@export var present_forward_offset: float = 0.20

@export_category("Components")
## The [Marker3D] socket where the energy cell rests inside.
@export var socket_marker: Marker3D

## The [Area3D] detection zone for inserting cells.
@export var socket_area: Area3D

## Floating [Label3D] displaying instructions and status.
@export var status_label: Label3D

## The [OutputTransmitter3D] controlling target actor power.
@export var transmitter: OutputTransmitter3D

## The [InteractComponent] handling direct player interaction.
@export var interact_comp: InteractComponent

## The [HighlightComponent] managing outline effects on focus.
@export var highlight_comp: HighlightComponent

@export_category("Materials")
## Triplanar horror rusted metal material applied to housing and claw parts.
@export var rusted_material: ShaderMaterial

## Emissive LED shader material applied to indicator bulbs.
@export var led_material: ShaderMaterial

# --------------------------------------
# PUBLIC VARIABLES
# --------------------------------------
## The currently slotted [EnergyCell] powering the generator.
var current_cell: EnergyCell = null

# --------------------------------------
# PRIVATE VARIABLES
# --------------------------------------
var _is_animating: bool = false
var _is_reinsert_locked: bool = false
var _claw_tween: Tween = null
var _red_led: MeshInstance3D = null
var _green_led: MeshInstance3D = null
var _claw_arm: Node3D = null
var _claw_finger_l: Node3D = null
var _claw_finger_r: Node3D = null


# --------------------------------------
# LIFECYCLE METHODS
# --------------------------------------
## Sets up transmitter targets, claw rig, materials, and signal connections.
func _ready() -> void:
	if not is_instance_valid(transmitter):
		transmitter = get_node_or_null("OutputTransmitter3D") as OutputTransmitter3D
	if is_instance_valid(transmitter):
		transmitter.targets = transmitter_targets

	if Engine.is_editor_hint():
		return

	set_process(false)
	set_physics_process(false)
	print("WallGenerator: Initializing generator: ", name)
	_cache_nodes()
	_apply_horror_materials()
	_bind_signals()

	if is_instance_valid(status_label):
		status_label.hide()

	_update_label()
	_update_indicator_lights()


## Disconnects global event listeners when leaving the scene tree.
func _exit_tree() -> void:
	if not Engine.is_editor_hint() and is_instance_valid(Events):
		if Events.item_picked_up.is_connected(_on_cell_picked_up):
			Events.item_picked_up.disconnect(_on_cell_picked_up)


# --------------------------------------
# PUBLIC METHODS
# --------------------------------------
## Handles player interaction; retrieves empty cell or docks held cell.
func interact_with(character: CharacterBody3D) -> void:
	print("WallGenerator: interact_with() called by ", character.name)
	if _is_animating:
		return

	if is_instance_valid(current_cell):
		if not current_cell.is_charged and not current_cell.is_locked:
			var player_interact: PlayerInteractionComponent = (
				character.get_node_or_null("PlayerInteractionComponent")
				as PlayerInteractionComponent
			)
			if is_instance_valid(player_interact):
				print("WallGenerator: Ejecting uncharged cell to player.")
				player_interact.force_grab_item(current_cell)
		return

	if _is_reinsert_locked:
		return

	var candidate_cell: EnergyCell = _find_held_cell(character)
	if is_instance_valid(candidate_cell):
		insert_cell(candidate_cell)
	else:
		_show_feedback("Find the energy cell")


## Inserts the specified [EnergyCell] into the generator socket using the metal claw.
func insert_cell(cell: EnergyCell) -> void:
	if (
		not is_instance_valid(cell)
		or _is_animating
		or is_instance_valid(current_cell)
		or _is_reinsert_locked
	):
		return

	print("WallGenerator: Slotted cell into generator socket.")
	_is_animating = true
	current_cell = cell

	if cell.is_held:
		cell.drop()

	cell.is_locked = true
	cell.set_deferred(&"freeze", true)
	cell.linear_velocity = Vector3.ZERO
	cell.angular_velocity = Vector3.ZERO

	if is_instance_valid(socket_area):
		socket_area.set_deferred(&"monitoring", false)

	var base_basis: Basis = (
		socket_marker.global_transform.basis.orthonormalized()
		if is_instance_valid(socket_marker)
		else global_transform.basis.orthonormalized()
	)
	var base_pos: Vector3 = (
		socket_marker.global_position if is_instance_valid(socket_marker) else global_position
	)

	if cell.is_charged:
		_animate_claw_insert(cell, base_pos, base_basis.get_rotation_quaternion())
	else:
		_animate_claw_reject_present(cell, base_pos, base_basis)


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
## Caches required scene components and articulated claw nodes from the model.
func _cache_nodes() -> void:
	if not is_instance_valid(socket_marker):
		socket_marker = get_node_or_null("SocketMarker") as Marker3D
	if not is_instance_valid(socket_area):
		socket_area = get_node_or_null("SocketArea") as Area3D
	if not is_instance_valid(status_label):
		status_label = get_node_or_null("StatusLabel") as Label3D
	if not is_instance_valid(interact_comp):
		interact_comp = get_node_or_null("InteractComponent") as InteractComponent
	if not is_instance_valid(highlight_comp):
		highlight_comp = get_node_or_null("HighlightComponent") as HighlightComponent

	var model: Node = get_node_or_null("Model")
	if not is_instance_valid(model):
		return

	_red_led = model.find_child("RedLED", true, false) as MeshInstance3D
	_green_led = model.find_child("GreenLED", true, false) as MeshInstance3D
	_claw_arm = model.find_child("ClawArm", true, false) as Node3D
	_claw_finger_l = model.find_child("ClawFingerL", true, false) as Node3D
	_claw_finger_r = model.find_child("ClawFingerR", true, false) as Node3D


## Applies shared rusted steel and LED materials to the imported GLB sub-meshes.
func _apply_horror_materials() -> void:
	var model: Node = get_node_or_null("Model")
	if not is_instance_valid(model):
		return

	if is_instance_valid(rusted_material):
		var steel_names: Array[String] = [
			"Housing",
			"ClawBaseMesh",
			"ClawArmMesh",
			"ClawFingerLMesh",
			"ClawFingerRMesh",
		]
		for mesh_name: String in steel_names:
			var mi: MeshInstance3D = model.find_child(mesh_name, true, false) as MeshInstance3D
			if is_instance_valid(mi):
				mi.set_surface_override_material(0, rusted_material)

	if is_instance_valid(led_material):
		if is_instance_valid(_red_led):
			_red_led.set_surface_override_material(0, led_material)
			_red_led.set_instance_shader_parameter(PARAM_LED_COLOR, Color(0.95, 0.08, 0.08, 1.0))
		if is_instance_valid(_green_led):
			_green_led.set_surface_override_material(0, led_material)
			_green_led.set_instance_shader_parameter(PARAM_LED_COLOR, Color(0.15, 0.95, 0.25, 1.0))


## Connects socket area and interaction focus signals.
func _bind_signals() -> void:
	if is_instance_valid(socket_area):
		Utilities.safe_connect(socket_area.body_entered, _on_socket_area_body_entered)
		Utilities.safe_connect(socket_area.body_exited, _on_socket_area_body_exited)

	if is_instance_valid(interact_comp):
		Utilities.safe_connect(interact_comp.focused, _on_focus_gained)
		Utilities.safe_connect(interact_comp.unfocused, _on_focus_lost)


## Animates the metal claw reaching out, gripping the charged cell, and seating it in socket.
func _animate_claw_insert(cell: EnergyCell, target_pos: Vector3, target_quat: Quaternion) -> void:
	_claw_tween = Utilities.reset_tween(self, _claw_tween)
	if is_instance_valid(_claw_arm):
		_claw_tween.tween_property(_claw_arm, "position:z", CLAW_EXTEND_Z, 0.14)
		_claw_tween.parallel().tween_property(_claw_arm, "rotation_degrees:x", 0.0, 0.14)
	if is_instance_valid(_claw_finger_l) and is_instance_valid(_claw_finger_r):
		_claw_tween.parallel().tween_property(
			_claw_finger_l, "rotation_degrees:y", -CLAW_OPEN_DEG, 0.12
		)
		_claw_tween.parallel().tween_property(
			_claw_finger_r, "rotation_degrees:y", CLAW_OPEN_DEG, 0.12
		)

	if is_instance_valid(_claw_finger_l) and is_instance_valid(_claw_finger_r):
		_claw_tween.tween_property(_claw_finger_l, "rotation_degrees:y", CLAW_GRIP_DEG, 0.12)
		_claw_tween.parallel().tween_property(
			_claw_finger_r, "rotation_degrees:y", -CLAW_GRIP_DEG, 0.12
		)

	(
		_claw_tween
		. tween_property(cell, "global_position", target_pos, 0.34)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_claw_tween
		. parallel()
		. tween_property(cell, "quaternion", target_quat, 0.34)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	if is_instance_valid(_claw_arm):
		(
			_claw_tween
			. parallel()
			. tween_property(_claw_arm, "position:z", CLAW_RETRACT_Z, 0.34)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)

	if is_instance_valid(_claw_finger_l) and is_instance_valid(_claw_finger_r):
		_claw_tween.tween_property(_claw_finger_l, "rotation_degrees:y", -CLAW_OPEN_DEG, 0.12)
		_claw_tween.parallel().tween_property(
			_claw_finger_r, "rotation_degrees:y", CLAW_OPEN_DEG, 0.12
		)

	_claw_tween.tween_callback(_on_charged_cell_seated.bind(cell))


## Animates the metal claw grabbing a depleted cell and presenting it outward to the player.
func _animate_claw_reject_present(cell: EnergyCell, base_pos: Vector3, base_basis: Basis) -> void:
	var tilt_rot: Basis = Basis(Vector3.RIGHT, deg_to_rad(eject_tilt_degrees))
	var tilted_basis: Basis = (base_basis * tilt_rot).orthonormalized()
	var target_quat: Quaternion = tilted_basis.get_rotation_quaternion()
	var bottom_pivot: Vector3 = base_pos - (base_basis.y * cell_half_height)
	var target_pos: Vector3 = (
		bottom_pivot + (tilted_basis.y * cell_half_height) + (base_basis.z * present_forward_offset)
	)

	_claw_tween = Utilities.reset_tween(self, _claw_tween)
	if is_instance_valid(_claw_finger_l) and is_instance_valid(_claw_finger_r):
		_claw_tween.tween_property(_claw_finger_l, "rotation_degrees:y", CLAW_GRIP_DEG, 0.12)
		_claw_tween.parallel().tween_property(
			_claw_finger_r, "rotation_degrees:y", -CLAW_GRIP_DEG, 0.12
		)

	(
		_claw_tween
		. tween_property(cell, "global_position", target_pos, 0.36)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_claw_tween
		. parallel()
		. tween_property(cell, "quaternion", target_quat, 0.36)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	if is_instance_valid(_claw_arm):
		(
			_claw_tween
			. parallel()
			. tween_property(_claw_arm, "position:z", CLAW_EXTEND_Z, 0.36)
			. set_trans(Tween.TRANS_BACK)
			. set_ease(Tween.EASE_OUT)
		)
		(
			_claw_tween
			. parallel()
			. tween_property(_claw_arm, "rotation_degrees:x", 18.0, 0.36)
			. set_trans(Tween.TRANS_BACK)
			. set_ease(Tween.EASE_OUT)
		)

	if is_instance_valid(_claw_finger_l) and is_instance_valid(_claw_finger_r):
		_claw_tween.tween_property(_claw_finger_l, "rotation_degrees:y", -CLAW_OPEN_DEG, 0.12)
		_claw_tween.parallel().tween_property(
			_claw_finger_r, "rotation_degrees:y", CLAW_OPEN_DEG, 0.12
		)

	_claw_tween.tween_callback(_on_depleted_cell_presented.bind(cell))


## Finalizes generator online state once a charged cell is seated.
func _on_charged_cell_seated(cell: EnergyCell) -> void:
	_is_animating = false
	if not is_instance_valid(cell):
		return
	print("WallGenerator: Cell inserted. Energizing system.")
	if is_instance_valid(transmitter):
		transmitter.power_on()
	_update_label()
	_update_indicator_lights()
	cell_inserted.emit(cell)


## Unlocks a presented depleted cell so the player can grab it.
func _on_depleted_cell_presented(cell: EnergyCell) -> void:
	_is_animating = false
	if not is_instance_valid(cell):
		return
	print("WallGenerator: Uncharged cell presented by claw.")
	cell.is_locked = false
	cell.freeze = true
	if is_instance_valid(cell.interact_comp):
		cell.interact_comp.process_mode = Node.PROCESS_MODE_INHERIT
		cell.interact_comp.is_currently_focused = false
	if is_instance_valid(status_label):
		status_label.text = "Cell Depleted - Recharge Required"
	_update_indicator_lights()
	Utilities.safe_connect(Events.item_picked_up, _on_cell_picked_up)


## Retracts the claw back into the housing after presenting a cell.
func _retract_claw_to_rest() -> void:
	_claw_tween = Utilities.reset_tween(self, _claw_tween)
	if is_instance_valid(_claw_arm):
		(
			_claw_tween
			. tween_property(_claw_arm, "position:z", CLAW_RETRACT_Z, 0.25)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		(
			_claw_tween
			. parallel()
			. tween_property(_claw_arm, "rotation_degrees:x", 0.0, 0.25)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
	if is_instance_valid(_claw_finger_l) and is_instance_valid(_claw_finger_r):
		_claw_tween.parallel().tween_property(_claw_finger_l, "rotation_degrees:y", 0.0, 0.25)
		_claw_tween.parallel().tween_property(_claw_finger_r, "rotation_degrees:y", 0.0, 0.25)


## Reveals floating label when focused by player crosshair.
func _on_focus_gained() -> void:
	print("WallGenerator: Focus gained. Showing status label.")
	if is_instance_valid(status_label):
		status_label.show()


## Hides floating label when player crosshair turns away.
func _on_focus_lost() -> void:
	print("WallGenerator: Focus lost. Hiding status label.")
	if is_instance_valid(status_label):
		status_label.hide()


## Triggered when an entity enters the socket detection area.
func _on_socket_area_body_entered(body: Node3D) -> void:
	if _is_animating or is_instance_valid(current_cell) or _is_reinsert_locked:
		return

	if body is EnergyCell:
		print("WallGenerator: Detected cell in proximity: ", body.name)
		insert_cell(body as EnergyCell)


## Triggered when an entity exits socket trigger bounds.
func _on_socket_area_body_exited(body: Node3D) -> void:
	if body is EnergyCell:
		print("WallGenerator: Cell cleared socket trigger bounds: ", body.name)


## Clears tracking state, retracts claw, and initiates lockout when retrieved.
func _on_cell_picked_up(item: PickableObject, _holder: Node3D) -> void:
	if item == current_cell:
		print("WallGenerator: Empty cell retrieved. Locking reinsertion.")
		var released_cell: EnergyCell = current_cell
		current_cell = null
		_is_reinsert_locked = true
		_retract_claw_to_rest()
		_update_label()
		_update_indicator_lights()
		cell_ejected.emit(released_cell)

		if Events.item_picked_up.is_connected(_on_cell_picked_up):
			Events.item_picked_up.disconnect(_on_cell_picked_up)

		get_tree().create_timer(reinsertion_cooldown).timeout.connect(
			_check_reinsertion_unlock.bind(released_cell)
		)


## Evaluates whether the cell is fully clear of socket bounds.
func _check_reinsertion_unlock(released_cell: EnergyCell) -> void:
	print("WallGenerator: Evaluating reinsertion unlock conditions.")
	if not is_instance_valid(socket_area):
		_is_reinsert_locked = false
		return

	if not socket_area.monitoring:
		socket_area.monitoring = true

	if is_instance_valid(released_cell) and socket_area.overlaps_body(released_cell):
		print("WallGenerator: Cell still inside socket. Extending cooldown.")
		get_tree().create_timer(0.2).timeout.connect(_check_reinsertion_unlock.bind(released_cell))
		return

	print("WallGenerator: Reinsertion unlocked. Socket receptive.")
	_is_reinsert_locked = false


## Updates the floating [Label3D] text based on current state.
func _update_label() -> void:
	if not is_instance_valid(status_label):
		return

	if is_instance_valid(current_cell):
		if current_cell.is_charged:
			status_label.text = "Generator Active (Online)"
		else:
			status_label.text = "Cell Depleted - Recharge Required"
	else:
		status_label.text = "Insert Energy Cell"


## Displays temporary feedback on the floating label.
func _show_feedback(msg: String) -> void:
	if not is_instance_valid(status_label):
		return
	status_label.text = msg
	status_label.show()
	get_tree().create_timer(2.0).timeout.connect(
		func() -> void:
			_update_label()
			if (
				is_instance_valid(interact_comp)
				and not interact_comp.is_currently_focused
				and is_instance_valid(status_label)
			):
				status_label.hide()
	)


## Finds an [EnergyCell] held by the specified player character.
func _find_held_cell(character: CharacterBody3D) -> EnergyCell:
	print("Searching for held EnergyCell on character: ", character.name)
	var held_prop: Variant = character.get("held_object")
	if is_instance_valid(held_prop) and held_prop is EnergyCell:
		var held_cell: EnergyCell = held_prop as EnergyCell
		return held_cell

	var tree: SceneTree = get_tree()
	if not tree or not is_instance_valid(tree.root):
		return null

	for node: Node in NodeQuery.find_children_in_group(tree.root, &"pickable_objects"):
		if node is EnergyCell:
			var cell: EnergyCell = node as EnergyCell
			if cell.holder == character:
				return cell

	return null


## Updates hood button indicator light emissions; blinks red when empty or depleted.
func _update_indicator_lights() -> void:
	var is_online: bool = is_instance_valid(current_cell) and current_cell.is_charged
	if is_instance_valid(_red_led):
		_red_led.set_instance_shader_parameter(PARAM_INTENSITY, 0.0 if is_online else 3.2)
		_red_led.set_instance_shader_parameter(
			PARAM_BLINK_SPEED, 0.0 if is_online else RED_BLINK_SPEED
		)
	if is_instance_valid(_green_led):
		_green_led.set_instance_shader_parameter(PARAM_INTENSITY, 3.0 if is_online else 0.0)
		_green_led.set_instance_shader_parameter(PARAM_BLINK_SPEED, 0.0)
