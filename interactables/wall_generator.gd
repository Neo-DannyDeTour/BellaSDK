@tool
## Generator socket that accepts a charged cell to power targets.
class_name WallGenerator
extends StaticBody3D

## Emitted when an [EnergyCell] is successfully inserted.
signal cell_inserted(cell: EnergyCell)

## Emitted when an [EnergyCell] is removed from the generator.
@warning_ignore("unused_signal")
signal cell_ejected(cell: EnergyCell)

@export_category("Transmitter")
## Targets powered by the generator. Forwarded to [OutputTransmitter3D].
@export var transmitter_targets: Array[Node3D] = []:
	set(value):
		transmitter_targets = value
		if not is_instance_valid(transmitter):
			transmitter = (get_node_or_null("OutputTransmitter3D") as OutputTransmitter3D)
		if is_instance_valid(transmitter):
			transmitter.targets = value

@export_category("Configuration")
## Angle in degrees to tilt an uncharged cell forward for grab.
@export var eject_tilt_degrees: float = 30.0

## Half height of the [EnergyCell] used as pivot offset for tilt.
@export var cell_half_height: float = 0.25

## Cooldown duration in seconds before cell can re-enter after pickup.
@export var reinsertion_cooldown: float = 1.0

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

## The currently slotted [EnergyCell] powering the generator.
var current_cell: EnergyCell = null

## Indicates whether an insertion animation is currently running.
var _is_animating: bool = false

## Tracks cooldown flag preventing immediate re-entry on grab.
var _is_reinsert_locked: bool = false


## Sets up transmitter targets, connections, and hides initial label.
func _ready() -> void:
	if not is_instance_valid(transmitter):
		transmitter = (get_node_or_null("OutputTransmitter3D") as OutputTransmitter3D)
	if is_instance_valid(transmitter):
		transmitter.targets = transmitter_targets

	if Engine.is_editor_hint():
		return

	print("WallGenerator: Initializing generator: ", name)
	if not is_instance_valid(socket_marker):
		socket_marker = get_node_or_null("SocketMarker") as Marker3D
	if not is_instance_valid(socket_area):
		socket_area = get_node_or_null("SocketArea") as Area3D
	if not is_instance_valid(status_label):
		status_label = get_node_or_null("StatusLabel") as Label3D
	if not is_instance_valid(interact_comp):
		interact_comp = (get_node_or_null("InteractComponent") as InteractComponent)
	if not is_instance_valid(highlight_comp):
		highlight_comp = (get_node_or_null("HighlightComponent") as HighlightComponent)

	if is_instance_valid(socket_area):
		socket_area.body_entered.connect(_on_socket_area_body_entered)
		socket_area.body_exited.connect(_on_socket_area_body_exited)

	if is_instance_valid(interact_comp):
		interact_comp.focused.connect(_on_focus_gained)
		interact_comp.unfocused.connect(_on_focus_lost)

	if is_instance_valid(status_label):
		status_label.hide()

	_update_label()


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


## Inserts the specified [EnergyCell] into the generator socket.
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
	cell.freeze = true
	cell.linear_velocity = Vector3.ZERO
	cell.angular_velocity = Vector3.ZERO

	if is_instance_valid(socket_area):
		socket_area.set_deferred("monitoring", false)

	var base_basis: Basis = (
		socket_marker.global_transform.basis.orthonormalized()
		if is_instance_valid(socket_marker)
		else global_transform.basis.orthonormalized()
	)
	var base_pos: Vector3 = (
		socket_marker.global_position if is_instance_valid(socket_marker) else global_position
	)

	var target_quat: Quaternion
	var target_pos: Vector3

	if cell.is_charged:
		target_quat = base_basis.get_rotation_quaternion()
		target_pos = base_pos
	else:
		var tilt_rot: Basis = Basis(Vector3.RIGHT, deg_to_rad(eject_tilt_degrees))
		var tilted_basis: Basis = (base_basis * tilt_rot).orthonormalized()
		target_quat = tilted_basis.get_rotation_quaternion()

		var bottom_pivot: Vector3 = base_pos - (base_basis.y * cell_half_height)
		target_pos = bottom_pivot + (tilted_basis.y * cell_half_height)

	var tween: Tween = create_tween()
	(
		tween
		. tween_property(cell, "global_position", target_pos, 0.45)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. parallel()
		. tween_property(cell, "quaternion", target_quat, 0.45)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)

	tween.tween_callback(
		func() -> void:
			_is_animating = false
			if cell.is_charged:
				print("WallGenerator: Cell inserted. Energizing system.")
				if is_instance_valid(transmitter):
					transmitter.power_on()
				_update_label()
				cell_inserted.emit(cell)
			else:
				print("WallGenerator: Uncharged cell inserted. Tilted out.")
				cell.is_locked = false
				cell.freeze = true
				if is_instance_valid(cell.interact_comp):
					cell.interact_comp.process_mode = (Node.PROCESS_MODE_INHERIT)
					cell.interact_comp.is_currently_focused = false
				if is_instance_valid(status_label):
					status_label.text = "Cell Depleted - Recharge Required"

				if not Events.item_picked_up.is_connected(_on_cell_picked_up):
					Events.item_picked_up.connect(_on_cell_picked_up)
	)


## Clears tracking state and initiates lockout when retrieved.
func _on_cell_picked_up(item: PickableObject, _holder: Node3D) -> void:
	if item == current_cell:
		print("WallGenerator: Empty cell retrieved. Locking reinsertion.")
		var released_cell: EnergyCell = current_cell
		current_cell = null
		_is_reinsert_locked = true
		_update_label()

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
