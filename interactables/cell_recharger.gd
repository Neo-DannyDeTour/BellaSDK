## Station that docks an uncharged [EnergyCell] and recharges it.
class_name CellRecharger
extends StaticBody3D

## Emitted when an energy cell begins the recharging process.
signal recharge_started(cell: EnergyCell)

## Emitted when an energy cell completes charging.
signal recharge_completed(cell: EnergyCell)

@export_category("Configuration")
## Duration in seconds required to recharge an energy cell.
@export var recharge_duration: float = 3.0

## Angle in degrees to tilt the cell forward when ready for grab.
@export var eject_tilt_degrees: float = 30.0

## Half height of the [EnergyCell] used as pivot offset for tilt.
@export var cell_half_height: float = 0.25

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

## Reference to the [EnergyCell] currently resting in dock.
var docked_cell: EnergyCell = null

## Active charging tween reference for smooth property cancellation.
var _charge_tween: Tween = null


## Sets up dock connections, signals, and hides the initial label.
func _ready() -> void:
	print("CellRecharger: Initializing station: ", name)
	if not is_instance_valid(dock_marker):
		dock_marker = get_node_or_null("DockMarker") as Marker3D
	if not is_instance_valid(dock_area):
		dock_area = get_node_or_null("DockArea") as Area3D
	if not is_instance_valid(status_label):
		status_label = get_node_or_null("StatusLabel") as Label3D
	if not is_instance_valid(interact_comp):
		interact_comp = (get_node_or_null("InteractComponent") as InteractComponent)
	if not is_instance_valid(highlight_comp):
		highlight_comp = (get_node_or_null("HighlightComponent") as HighlightComponent)

	if is_instance_valid(dock_area):
		dock_area.body_entered.connect(_on_dock_area_body_entered)

	if is_instance_valid(interact_comp):
		interact_comp.focused.connect(_on_focus_gained)
		interact_comp.unfocused.connect(_on_focus_lost)

	if is_instance_valid(status_label):
		status_label.hide()

	_update_label()


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
	else:
		_show_feedback("Insert energy cell to recharge")


## Triggered when an entity enters the dock detection area.
func _on_dock_area_body_entered(body: Node3D) -> void:
	if is_instance_valid(docked_cell):
		return

	if body is EnergyCell:
		print("CellRecharger: Cell entered dock trigger: ", body.name)
		dock_cell(body as EnergyCell)


## Docks the [EnergyCell] into the station and begins charging.
func dock_cell(cell: EnergyCell) -> void:
	if not is_instance_valid(cell) or is_instance_valid(docked_cell):
		return

	if cell.is_charged:
		print("CellRecharger: Cell is already charged.")
		_show_feedback("Cell is already charged!")
		return

	print("CellRecharger: Docking cell for recharge: ", cell.name)
	docked_cell = cell

	if is_instance_valid(interact_comp):
		interact_comp.process_mode = Node.PROCESS_MODE_DISABLED

	if cell.is_held:
		cell.drop()

	cell.is_locked = true
	cell.freeze = true
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

	var move_tween: Tween = create_tween()
	(
		move_tween
		. tween_property(cell, "global_position", target_pos, 0.3)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		move_tween
		. parallel()
		. tween_property(cell, "quaternion", target_quat, 0.3)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)

	move_tween.tween_callback(_start_charge_sequence.bind(cell))


## Runs visual charge tween and status label text updates.
func _start_charge_sequence(cell: EnergyCell) -> void:
	if not is_instance_valid(cell):
		return

	cell.fill_progress = 0.0
	recharge_started.emit(cell)

	if is_instance_valid(_charge_tween) and _charge_tween.is_valid():
		_charge_tween.kill()

	_charge_tween = create_tween()
	(
		_charge_tween
		. tween_property(cell, "fill_progress", 1.0, recharge_duration)
		. set_trans(Tween.TRANS_LINEAR)
		. set_ease(Tween.EASE_IN_OUT)
	)

	_charge_tween.parallel().tween_method(
		func(prog: float) -> void:
			if is_instance_valid(status_label):
				var pct: int = int(prog * 100.0)
				status_label.text = "Recharging Cell... (%d%%)" % pct,
		0.0,
		1.0,
		recharge_duration
	)

	_charge_tween.tween_callback(_finish_recharge)


## Finalizes recharge, tilts cell from bottom, and unlocks grab.
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
	var tilted_pos: Vector3 = bottom_pivot + (tilted_basis.y * cell_half_height)

	var tilt_tween: Tween = create_tween()
	(
		tilt_tween
		. tween_property(docked_cell, "quaternion", tilted_quat, 0.35)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tilt_tween
		. parallel()
		. tween_property(docked_cell, "global_position", tilted_pos, 0.35)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)

	tilt_tween.tween_callback(
		func() -> void:
			if not is_instance_valid(docked_cell):
				return

			docked_cell.is_locked = false
			docked_cell.freeze = true

			if is_instance_valid(docked_cell.interact_comp):
				docked_cell.interact_comp.process_mode = (Node.PROCESS_MODE_INHERIT)
				docked_cell.interact_comp.is_currently_focused = false

			if is_instance_valid(interact_comp):
				interact_comp.process_mode = Node.PROCESS_MODE_INHERIT

			if is_instance_valid(status_label):
				status_label.text = "Charging Complete - Ready to Grab"

			recharge_completed.emit(docked_cell)

			if not Events.item_picked_up.is_connected(_on_cell_picked_up):
				Events.item_picked_up.connect(_on_cell_picked_up)
	)


## Clears dock state when the recharged cell is taken by player.
func _on_cell_picked_up(item: PickableObject, _holder: Node3D) -> void:
	if item == docked_cell:
		print("CellRecharger: Cell grabbed by player, clearing dock.")
		docked_cell = null
		if is_instance_valid(interact_comp):
			interact_comp.process_mode = Node.PROCESS_MODE_INHERIT
		_update_label()
		if Events.item_picked_up.is_connected(_on_cell_picked_up):
			Events.item_picked_up.disconnect(_on_cell_picked_up)


## Updates the floating [Label3D] text based on dock state.
func _update_label() -> void:
	if not is_instance_valid(status_label):
		return
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
	var held_prop: Variant = character.get("held_object")
	if is_instance_valid(held_prop) and held_prop is EnergyCell:
		return held_prop as EnergyCell

	var tree: SceneTree = get_tree()
	if not tree:
		return null

	for node: Node in tree.get_nodes_in_group("pickable_objects"):
		if node is EnergyCell and (node as EnergyCell).holder == character:
			return node as EnergyCell

	return null
