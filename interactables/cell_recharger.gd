## Station with articulated claw and top reserve bar that recharges an [EnergyCell].
class_name CellRecharger
extends StaticBody3D

# --------------------------------------
# SIGNALS
# --------------------------------------
## Emitted when an energy cell begins the recharging process.
signal recharge_started(cell: EnergyCell)

## Emitted when an energy cell completes charging.
signal recharge_completed(cell: EnergyCell)

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Pre-allocated shader uniform name for top energy reserve bar fill ratio.
const PARAM_ENERGY_RATIO: StringName = &"energy_ratio"
## Retracted local Z offset of [member _claw_arm] inside the dock bay.
const CLAW_RETRACT_Z: float = 0.05
## Extended local Z offset of [member _claw_arm] when gripping or presenting a cell.
const CLAW_EXTEND_Z: float = 0.24
## Open pincer yaw angle in degrees.
const CLAW_OPEN_DEG: float = 28.0
## Closed pincer yaw angle in degrees when gripping a cell.
const CLAW_GRIP_DEG: float = 6.0

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Configuration")
## Duration in seconds required to recharge an energy cell.
@export var recharge_duration: float = 3.0

## Angle in degrees to tilt the cell forward when ready for grab.
@export var eject_tilt_degrees: float = 30.0

## Half height of the [EnergyCell] used as pivot offset for tilt.
@export var cell_half_height: float = 0.25

## Forward offset in meters when the claw presents a charged cell to the player.
@export var present_forward_offset: float = 0.20

## Maximum energy reserve capacity stored by the charger.
@export var max_energy: float = 2.0

## Current remaining energy reserve available to give to cells.
@export var available_energy: float = 2.0:
	set = set_available_energy

## Energy consumed from [member available_energy] per full cell recharge.
@export var energy_cost_per_charge: float = 1.0

@export_category("Components")
## The [Marker3D] dock where the cell rests during charging.
@export var dock_marker: Marker3D

## The [Area3D] detection zone for docking cells.
@export var dock_area: Area3D

## Floating [Label3D] displaying instructions and progress.
@export var status_label: Label3D

## The [InteractComponent] handling direct player interaction.
@export var interact_comp: InteractComponent

## The [HighlightComponent] managing outline effects on focus.
@export var highlight_comp: HighlightComponent

@export_category("Materials")
## Triplanar horror rusted metal material applied to housing and claw parts.
@export var rusted_material: ShaderMaterial

## Emissive segmented bar material applied to the top [EnergyBar] mesh.
@export var energy_bar_material: ShaderMaterial

# --------------------------------------
# PUBLIC VARIABLES
# --------------------------------------
## Reference to the [EnergyCell] currently resting in dock.
var docked_cell: EnergyCell = null

# --------------------------------------
# PRIVATE VARIABLES
# --------------------------------------
var _charge_tween: Tween = null
var _claw_tween: Tween = null
var _energy_bar: MeshInstance3D = null
var _claw_arm: Node3D = null
var _claw_finger_l: Node3D = null
var _claw_finger_r: Node3D = null


# --------------------------------------
# LIFECYCLE METHODS
# --------------------------------------
## Sets up dock connections, claw rig, materials, and top energy bar state.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	print("CellRecharger: Initializing station: ", name)
	_cache_nodes()
	_apply_horror_materials()
	_bind_signals()

	if is_instance_valid(status_label):
		status_label.hide()

	_update_energy_bar()
	_update_label()


## Disconnects global event listeners when leaving the scene tree.
func _exit_tree() -> void:
	if Events.item_picked_up.is_connected(_on_cell_picked_up):
		Events.item_picked_up.disconnect(_on_cell_picked_up)


# --------------------------------------
# PUBLIC METHODS
# --------------------------------------
## Updates [member available_energy] and refreshes the top energy reserve bar.
func set_available_energy(value: float) -> void:
	available_energy = clampf(value, 0.0, maxf(max_energy, 0.001))
	_update_energy_bar()


## Handles player interaction; grabs docked cell or docks held cell.
func interact_with(character: CharacterBody3D) -> void:
	print("CellRecharger: interact_with() called by ", character.name)
	if is_instance_valid(docked_cell):
		if not docked_cell.is_locked:
			var player_interact: PlayerInteractionComponent = (
				character.get_node_or_null("PlayerInteractionComponent")
				as PlayerInteractionComponent
			)
			if is_instance_valid(player_interact):
				print("CellRecharger: Forwarding pickup to player.")
				player_interact.force_grab_item(docked_cell)
		return

	var candidate_cell: EnergyCell = _find_held_cell(character)
	if is_instance_valid(candidate_cell):
		dock_cell(candidate_cell)
	elif available_energy < energy_cost_per_charge:
		_show_feedback("Charger Depleted - No Energy")
	else:
		_show_feedback("Insert energy cell to recharge")


## Docks the [EnergyCell] into the station with the metal claw and begins charging.
func dock_cell(cell: EnergyCell) -> void:
	if not is_instance_valid(cell) or is_instance_valid(docked_cell):
		return

	if cell.is_charged:
		print("CellRecharger: Cell is already charged.")
		_show_feedback("Cell is already charged!")
		return

	if available_energy < energy_cost_per_charge:
		print("CellRecharger: Insufficient reserve energy.")
		_show_feedback("Charger Depleted - No Energy")
		return

	print("CellRecharger: Docking cell for recharge: ", cell.name)
	docked_cell = cell

	if is_instance_valid(interact_comp):
		interact_comp.process_mode = Node.PROCESS_MODE_DISABLED

	if cell.is_held:
		cell.drop()

	cell.is_locked = true
	cell.set_deferred(&"freeze", true)
	cell.linear_velocity = Vector3.ZERO
	cell.angular_velocity = Vector3.ZERO

	var target_quat: Quaternion = (
		dock_marker.global_transform.basis.orthonormalized().get_rotation_quaternion()
		if is_instance_valid(dock_marker)
		else global_transform.basis.orthonormalized().get_rotation_quaternion()
	)
	var target_pos: Vector3 = (
		dock_marker.global_position if is_instance_valid(dock_marker) else global_position
	)

	_animate_claw_dock(cell, target_pos, target_quat)


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
## Caches required scene components and articulated claw nodes from the model.
func _cache_nodes() -> void:
	if not is_instance_valid(dock_marker):
		dock_marker = get_node_or_null("DockMarker") as Marker3D
	if not is_instance_valid(dock_area):
		dock_area = get_node_or_null("DockArea") as Area3D
	if not is_instance_valid(status_label):
		status_label = get_node_or_null("StatusLabel") as Label3D
	if not is_instance_valid(interact_comp):
		interact_comp = get_node_or_null("InteractComponent") as InteractComponent
	if not is_instance_valid(highlight_comp):
		highlight_comp = get_node_or_null("HighlightComponent") as HighlightComponent

	var model: Node = get_node_or_null("Model")
	if not is_instance_valid(model):
		return

	_energy_bar = model.find_child("EnergyBar", true, false) as MeshInstance3D
	_claw_arm = model.find_child("ClawArm", true, false) as Node3D
	_claw_finger_l = model.find_child("ClawFingerL", true, false) as Node3D
	_claw_finger_r = model.find_child("ClawFingerR", true, false) as Node3D


## Applies shared rusted steel and top energy bar shaders to imported GLB sub-meshes.
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

	if is_instance_valid(energy_bar_material) and is_instance_valid(_energy_bar):
		_energy_bar.set_surface_override_material(0, energy_bar_material)


## Connects dock area and interaction focus signals.
func _bind_signals() -> void:
	if is_instance_valid(dock_area):
		Utilities.safe_connect(dock_area.body_entered, _on_dock_area_body_entered)

	if is_instance_valid(interact_comp):
		Utilities.safe_connect(interact_comp.focused, _on_focus_gained)
		Utilities.safe_connect(interact_comp.unfocused, _on_focus_lost)


## Animates the claw reaching out, gripping the cell, and pulling it into dock.
func _animate_claw_dock(cell: EnergyCell, target_pos: Vector3, target_quat: Quaternion) -> void:
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

	_claw_tween.tween_callback(_start_charge_sequence.bind(cell))


## Runs visual charge tween, drains reserve energy bar, and updates status label.
func _start_charge_sequence(cell: EnergyCell) -> void:
	if not is_instance_valid(cell):
		return

	cell.fill_progress = 0.0
	recharge_started.emit(cell)

	var start_energy: float = available_energy
	var end_energy: float = maxf(start_energy - energy_cost_per_charge, 0.0)

	_charge_tween = Utilities.reset_tween(self, _charge_tween)
	(
		_charge_tween
		. tween_property(cell, "fill_progress", 1.0, recharge_duration)
		. set_trans(Tween.TRANS_LINEAR)
		. set_ease(Tween.EASE_IN_OUT)
	)
	_charge_tween.parallel().tween_method(
		func(prog: float) -> void:
			set_available_energy(lerpf(start_energy, end_energy, prog))
			if is_instance_valid(status_label):
				var pct: int = int(prog * 100.0)
				status_label.text = "Recharging Cell... (%d%%)" % pct,
		0.0,
		1.0,
		recharge_duration
	)

	_charge_tween.tween_callback(_finish_recharge)


## Finalizes recharge, extends claw to present the charged cell, and unlocks grab.
func _finish_recharge() -> void:
	print("CellRecharger: Recharge finished! Energizing cell.")
	if not is_instance_valid(docked_cell):
		return

	docked_cell.charge()

	var base_basis: Basis = (
		dock_marker.global_transform.basis.orthonormalized()
		if is_instance_valid(dock_marker)
		else global_transform.basis.orthonormalized()
	)
	var base_pos: Vector3 = (
		dock_marker.global_position if is_instance_valid(dock_marker) else global_position
	)

	var tilt_rot: Basis = Basis(Vector3.RIGHT, deg_to_rad(eject_tilt_degrees))
	var tilted_basis: Basis = (base_basis * tilt_rot).orthonormalized()
	var tilted_quat: Quaternion = tilted_basis.get_rotation_quaternion()
	var bottom_pivot: Vector3 = base_pos - (base_basis.y * cell_half_height)
	var tilted_pos: Vector3 = (
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
		. tween_property(docked_cell, "quaternion", tilted_quat, 0.36)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_claw_tween
		. parallel()
		. tween_property(docked_cell, "global_position", tilted_pos, 0.36)
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

	_claw_tween.tween_callback(_on_charged_cell_presented)


## Unlocks the presented cell and binds pickup cleanup.
func _on_charged_cell_presented() -> void:
	if not is_instance_valid(docked_cell):
		return

	docked_cell.is_locked = false
	docked_cell.freeze = true

	if is_instance_valid(docked_cell.interact_comp):
		docked_cell.interact_comp.process_mode = Node.PROCESS_MODE_INHERIT
		docked_cell.interact_comp.is_currently_focused = false

	if is_instance_valid(interact_comp):
		interact_comp.process_mode = Node.PROCESS_MODE_INHERIT

	if is_instance_valid(status_label):
		status_label.text = "Charging Complete - Ready to Grab"

	recharge_completed.emit(docked_cell)
	Utilities.safe_connect(Events.item_picked_up, _on_cell_picked_up)


## Retracts the claw back into the dock housing after the player grabs the cell.
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


## Updates the top [EnergyBar] shader uniform from [member available_energy].
func _update_energy_bar() -> void:
	if not is_instance_valid(_energy_bar):
		return
	var ratio: float = clampf(available_energy / maxf(max_energy, 0.001), 0.0, 1.0)
	_energy_bar.set_instance_shader_parameter(PARAM_ENERGY_RATIO, ratio)


## Reveals floating label when hovered and focused by player.
func _on_focus_gained() -> void:
	print("CellRecharger: Focus gained. Showing status label.")
	if is_instance_valid(status_label):
		status_label.show()


## Hides floating label when player crosshair looks away.
func _on_focus_lost() -> void:
	print("CellRecharger: Focus lost. Hiding status label.")
	if is_instance_valid(status_label):
		status_label.hide()


## Triggered when an entity enters the dock detection area.
func _on_dock_area_body_entered(body: Node3D) -> void:
	if is_instance_valid(docked_cell):
		return

	if body is EnergyCell:
		print("CellRecharger: Cell entered dock trigger: ", body.name)
		dock_cell(body as EnergyCell)


## Clears dock state and retracts claw when the recharged cell is taken by player.
func _on_cell_picked_up(item: PickableObject, _holder: Node3D) -> void:
	if item == docked_cell:
		print("CellRecharger: Cell grabbed by player, clearing dock.")
		docked_cell = null
		_retract_claw_to_rest()
		if is_instance_valid(interact_comp):
			interact_comp.process_mode = Node.PROCESS_MODE_INHERIT
		_update_label()
		if Events.item_picked_up.is_connected(_on_cell_picked_up):
			Events.item_picked_up.disconnect(_on_cell_picked_up)


## Updates the floating [Label3D] text based on dock state and reserve energy.
func _update_label() -> void:
	if not is_instance_valid(status_label):
		return
	if available_energy < energy_cost_per_charge:
		status_label.text = "Cell Recharger - Depleted"
	else:
		status_label.text = "Cell Recharger - Place Cell Here"


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
		var cell: EnergyCell = held_prop as EnergyCell
		return cell

	var tree: SceneTree = get_tree()
	if not tree or not is_instance_valid(tree.root):
		return null

	var pickables: Array[Node] = NodeQuery.find_children_in_group(tree.root, &"pickable_objects")
	for node: Node in pickables:
		if node is EnergyCell:
			var cell: EnergyCell = node as EnergyCell
			if cell.holder == character:
				return cell

	return null
