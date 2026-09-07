@tool
## Interactive wall lever toggling targets via [OutputTransmitter3D].
class_name WallLever
extends StaticBody3D

## Emitted when the lever completes its transition between states.
signal state_changed(is_active: bool)
## Emitted when an incomplete lever missing its stick is triggered.
signal handle_missing(character: CharacterBody3D)
## Emitted when a missing stick is successfully mounted into base.
signal stick_installed
## Emitted when a one-time lever stick detaches and drops to floor.
signal stick_fallen

@export_group("Output Transmission")
## Target nodes commanded by this lever via [OutputTransmitter3D].
@export var output_targets: Array[Node3D] = []:
	set = _set_output_targets

@export_group("Global Architecture")
## Global event identifier broadcast across scenes via event bus.
@export var global_event_name: String = ""

@export_group("Prompt Settings")
## Action text displayed when lever is intact and ready to pull.
@export var prompt_pull: String = "Pull Lever"

## Action text displayed when lever is missing its stick handle.
@export var prompt_missing: String = "Missing Handle"

## Action text displayed when player possesses stick to attach.
@export var prompt_repair: String = "Attach Handle"

## Required item ID string to validate stick in player inventory.
@export var required_item_id: String = "lever_stick"

@export_group("Lever Configuration")
## Whether the lever begins complete or missing its stick handle.
@export var is_complete: bool = true:
	set = _set_is_complete

## Whether the lever handle detaches and drops after single pull.
@export var is_one_time_use: bool = false

## [PackedScene] of [LeverStickItem] spawned when handle drops.
@export var stick_item_scene: PackedScene

## Current activation state toggling downstream output targets.
@export var is_pulled: bool = false:
	set = _set_is_pulled

## Duration in seconds for the handle rotation tween animation.
@export var pull_duration: float = 0.35

## Handle rotation angle in degrees around local X axis when off.
@export var angle_off_deg: float = 0.0

## Handle rotation angle in degrees around local X axis when on.
@export var angle_on_deg: float = 180.0

@export_group("Visual Highlighting")
## Visual mesh instance that receives the outline overlay effect.
@export var mesh_to_highlight: MeshInstance3D

## Shader material applied to outline the mesh on cursor focus.
@export var outline_material: ShaderMaterial

@export_group("Internal Node References")
## Pivot node holding stick mesh rotating around local X axis.
@export var stick_pivot: Node3D

## Floating 3D label displaying contextual action prompts to user.
@export var prompt_label: Label3D

## Transmitter routing activation signals to downstream devices.
@export var transmitter: OutputTransmitter3D

## Component handling cursor focus and player interaction events.
@export var interact_component: InteractComponent

## Component handling visual outline display on focused objects.
@export var highlight_component: HighlightComponent

## Active tween animating the handle rotation between states.
var _tween: Tween

## Tracks whether the one-time lever has already been spent.
var _is_used: bool = false

## Prevents concurrent interactions while handle is animating.
var _is_animating: bool = false


## Resolves node references and synchronizes starting visual pose.
func _ready() -> void:
	if not is_instance_valid(stick_pivot):
		stick_pivot = get_node_or_null("StickPivot")
	if not is_instance_valid(prompt_label):
		prompt_label = get_node_or_null("PromptLabel")
	if not is_instance_valid(prompt_label):
		prompt_label = get_node_or_null("LabelInteract")
	if not is_instance_valid(transmitter):
		transmitter = get_node_or_null("OutputTransmitter3D")
	if not is_instance_valid(interact_component):
		interact_component = get_node_or_null("InteractComponent")
	if not is_instance_valid(highlight_component):
		highlight_component = get_node_or_null("HighlightComponent")

	_sync_targets_to_transmitter()
	_update_stick_visibility()
	_update_handle_pose(false)

	if Engine.is_editor_hint():
		return

	if is_instance_valid(prompt_label):
		prompt_label.visible = false

	if is_instance_valid(interact_component):
		interact_component.focused.connect(_on_focused)
		interact_component.unfocused.connect(_on_unfocused)
		if not interact_component.interacted.is_connected(interact_with):
			interact_component.interacted.connect(interact_with)


## Handles player interaction triggered by [InteractComponent].
func interact_with(character: CharacterBody3D) -> void:
	if is_one_time_use and _is_used:
		print("WallLever: Cannot use ", name, " - lever is already spent.")
		return

	if _is_animating:
		print("WallLever: Lever ", name, " is currently moving.")
		return

	if not is_complete:
		var has_stick: bool = _character_has_stick(character)
		if has_stick:
			_consume_stick_from_character(character)
			install_stick()
			_update_prompt_text(character)
		else:
			print("WallLever: Cannot pull ", name, " - handle missing!")
			handle_missing.emit(character)
		return

	toggle(character)


## Mounts handle onto lever base and updates completeness state.
func install_stick() -> void:
	print("WallLever: Stick mounted onto ", name, ". Lever is ready to pull.")
	is_complete = true
	_update_stick_visibility()
	_update_handle_pose(false)
	_update_prompt_text()
	stick_installed.emit()


## Toggles lever state and animates rotation toward target angle.
func toggle(character: CharacterBody3D = null) -> void:
	is_pulled = not is_pulled
	var actor: String = String(character.name) if is_instance_valid(character) else "Script"
	print("WallLever: Toggled by ", actor, ". State: ", is_pulled)

	_update_handle_pose(true)

	# Synchronize transmitter state with starting lever configuration
	if is_instance_valid(transmitter):
		if is_pulled:
			transmitter.power_on()
		else:
			transmitter.power_off()

	if global_event_name != "":
		print("WallLever: Broadcasting event -> ", global_event_name)
		Events.level_event_triggered.emit(global_event_name, is_pulled)


## Spawns [LeverStickItem] physics pickup and hides intact stick.
func _drop_stick() -> void:
	if not is_instance_valid(stick_pivot):
		return

	print("WallLever: Handle breaking off ", name, " and falling to floor.")
	_is_used = true
	is_complete = false
	stick_pivot.visible = false

	if is_instance_valid(prompt_label):
		prompt_label.visible = false
	if is_instance_valid(highlight_component):
		highlight_component.suppress(true)
	if is_instance_valid(mesh_to_highlight):
		mesh_to_highlight.material_overlay = null

	if is_instance_valid(stick_item_scene):
		var stick_node: Node = stick_item_scene.instantiate()
		var spawn_root: Node = get_parent() if is_instance_valid(get_parent()) else self
		spawn_root.add_child(stick_node)

		if stick_node is Node3D:
			var node_3d: Node3D = stick_node as Node3D
			node_3d.global_transform = stick_pivot.global_transform

		if stick_node is RigidBody3D:
			var rb: RigidBody3D = stick_node as RigidBody3D
			rb.freeze = false
			rb.collision_layer = 4
			rb.collision_mask = 1
			var forward_dir: Vector3 = -global_transform.basis.z
			rb.apply_central_impulse((forward_dir * 0.4) + (Vector3.DOWN * 0.2))
			rb.apply_torque_impulse(Vector3(randf_range(-0.5, 0.5), 0.2, 0.5))
	else:
		print("WallLever: Assign stick_item_scene in Inspector to spawn dropped pickup!")

	stick_fallen.emit()


## Finalizes pull animation and handles one-time stick detachment.
func _on_pull_completed() -> void:
	_is_animating = false
	state_changed.emit(is_pulled)

	if is_one_time_use and is_pulled:
		_drop_stick()


## Updates [member stick_pivot] rotation via tween or snap.
func _update_handle_pose(animate: bool) -> void:
	if not is_instance_valid(stick_pivot):
		return

	var target_deg: float = angle_on_deg if is_pulled else angle_off_deg
	var target_rot: Vector3 = Vector3(deg_to_rad(target_deg), 0.0, 0.0)

	if animate and not Engine.is_editor_hint() and is_inside_tree():
		if is_instance_valid(_tween) and _tween.is_running():
			_tween.kill()

		_is_animating = true
		_tween = create_tween()
		(
			_tween
			. tween_property(stick_pivot, "rotation", target_rot, pull_duration)
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_IN_OUT)
		)
		_tween.finished.connect(_on_pull_completed)
	else:
		stick_pivot.rotation = target_rot


## Updates action prompt string based on completeness and player.
func _update_prompt_text(character: CharacterBody3D = null) -> void:
	if not is_instance_valid(prompt_label):
		return

	var text_body: String = ""
	if is_complete:
		text_body = prompt_pull
	else:
		if _character_has_stick(character):
			text_body = prompt_repair
		else:
			text_body = prompt_missing

	prompt_label.text = text_body


## Validates whether player character inventory possesses handle.
func _character_has_stick(character: CharacterBody3D) -> bool:
	if not is_instance_valid(character):
		return false
	var inv: Node = character.get_node_or_null("InventoryComponent")
	if is_instance_valid(inv) and inv.has_method("has_item"):
		return inv.call("has_item", required_item_id)
	return false


## Removes the stick item from character inventory upon mounting.
func _consume_stick_from_character(character: CharacterBody3D) -> void:
	if not is_instance_valid(character):
		return
	var inv: Node = character.get_node_or_null("InventoryComponent")
	if is_instance_valid(inv) and inv.has_method("remove_item"):
		inv.call("remove_item", required_item_id, 1)


## Shows prompt label and applies highlight outline upon focus.
func _on_focused() -> void:
	if is_one_time_use and _is_used:
		return

	if is_instance_valid(prompt_label):
		var player: CharacterBody3D = null
		if is_instance_valid(interact_component):
			player = interact_component.get_character_hovered_by_cur_camera()
		_update_prompt_text(player)
		prompt_label.visible = true

	if is_instance_valid(mesh_to_highlight) and is_instance_valid(outline_material):
		mesh_to_highlight.material_overlay = outline_material


## Hides prompt label and clears highlight outline upon unfocus.
func _on_unfocused() -> void:
	if is_instance_valid(prompt_label):
		prompt_label.visible = false

	if is_instance_valid(mesh_to_highlight):
		mesh_to_highlight.material_overlay = null


## Synchronizes exported targets with child [OutputTransmitter3D].
func _sync_targets_to_transmitter() -> void:
	if not is_instance_valid(transmitter):
		transmitter = get_node_or_null("OutputTransmitter3D")
	if is_instance_valid(transmitter):
		transmitter.targets = output_targets


## Setter for [member output_targets] updating child transmitter.
func _set_output_targets(value: Array[Node3D]) -> void:
	output_targets = value
	if not is_inside_tree():
		return
	_sync_targets_to_transmitter()


## Setter for [member is_complete] updating stick visibility.
func _set_is_complete(value: bool) -> void:
	is_complete = value
	if not is_inside_tree():
		return
	_update_stick_visibility()


## Setter for [member is_pulled] adjusting handle pose in editor.
func _set_is_pulled(value: bool) -> void:
	is_pulled = value
	if not is_inside_tree():
		return
	if Engine.is_editor_hint():
		_update_handle_pose(false)


## Toggles visibility of [member stick_pivot] based on state.
func _update_stick_visibility() -> void:
	if is_instance_valid(stick_pivot):
		stick_pivot.visible = is_complete
