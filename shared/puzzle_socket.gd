## Manages puzzle socket interactions, power transmission states, and dynamic prompt visibility.
@tool
class_name PuzzleSocket
extends StaticBody3D

## Emitted when the socket enters an active powered state.
signal socket_powered_on
## Emitted when the socket loses power or its connection is cut.
signal socket_powered_off

## Node name used for the editor-only lightning particle preview.
const PREVIEW_PARTICLES_NAME: String = "EditorPowerSourcePreview"

## Determines if this socket supplies power to connected plugs.
@export_group("Socket Settings")
@export var is_power_source: bool = false:
	set(value):
		is_power_source = value
		if is_inside_tree():
			_update_editor_preview()
## Requires an active power loop to distribute energy to targets.
@export var requires_power_link: bool = false
## Determines if the inserted plug can be extracted by player interaction.
@export var can_be_unplugged: bool = true
## Reference point marker defining where the plug locks visually.
@export var snap_position: Marker3D
## Light node indicating power connection status.
@export var indicator_light: Light3D
## In-world 3D label displaying interaction prompts to the player.
@export var label: Label3D
## Component handling player aim focus and interaction triggers.
@export var socket_interact_comp: InteractComponent
## Component handling visual mesh highlight outlining.
@export var highlight_comp: Node
## Trigger area responsible for detecting when a plug enters or exits the socket.
@export var plug_trigger_area: Area3D
## Particle texture displayed in the editor when the socket is a power source.
@export var power_source_texture: Texture2D:
	set(value):
		power_source_texture = value
		if is_inside_tree():
			_update_editor_preview()

## Transmitter node passing logic triggers and progress to targets.
@export_category("Connections")
@export var transmitter: OutputTransmitter3D:
	set(value):
		transmitter = value
		if is_inside_tree():
			_sync_transmitter()

## Array of destination nodes receiving power signals.
@export var targets: Array[Node3D] = []:
	set(value):
		targets = value
		if is_inside_tree():
			_sync_transmitter()

## Tracks whether a plug is physically inserted and connected.
var is_powered: bool = false
## Reference to the currently inserted plug node.
var current_plug: Node3D = null
## Prevents instant re-insertion right after an unplug event.
var is_cooling_down: bool = false
## Controls prompt text visibility based on player game settings.
var _show_text_prompts: bool = true


## Initializes component listeners, default light state, and prompt settings.
func _ready() -> void:
	print("PuzzleSocket: Initializing _ready() lifecycle.")
	_sync_transmitter()

	if not is_instance_valid(label):
		label = get_node_or_null("Label3D") as Label3D

	if not is_instance_valid(highlight_comp):
		highlight_comp = get_node_or_null("HighlightComponent")

	if not is_instance_valid(snap_position):
		snap_position = get_node_or_null("Marker3D") as Marker3D

	if not is_instance_valid(indicator_light):
		indicator_light = get_node_or_null("OmniLight3D") as Light3D

	if not is_instance_valid(plug_trigger_area):
		plug_trigger_area = get_node_or_null("PlugTriggerArea") as Area3D

	if not is_instance_valid(socket_interact_comp):
		socket_interact_comp = get_node_or_null("InteractComponent") as InteractComponent

	if is_instance_valid(label):
		label.hide()

	if Engine.is_editor_hint():
		_update_editor_preview()
		return

	_remove_editor_preview()

	if is_instance_valid(indicator_light):
		indicator_light.visible = true
		indicator_light.light_color = Color.RED

	if is_instance_valid(plug_trigger_area):
		plug_trigger_area.body_entered.connect(_on_body_entered)
		plug_trigger_area.body_exited.connect(_on_body_exited)
	else:
		push_error("PuzzleSocket: Missing PlugTriggerArea child node!")

	if is_instance_valid(GlobalSettings) and GlobalSettings.has_method("get_setting"):
		var raw_setting: Variant = GlobalSettings.get_setting("Gameplay", "show_item_prompts", true)
		_show_text_prompts = raw_setting as bool

	if is_instance_valid(Events) and Events.has_signal("item_prompts_toggled"):
		if not Events.item_prompts_toggled.is_connected(_on_item_prompts_toggled):
			Events.item_prompts_toggled.connect(_on_item_prompts_toggled)

	if is_instance_valid(socket_interact_comp):
		print("PuzzleSocket: Binding signals to InteractComponent.")
		if not socket_interact_comp.interacted.is_connected(_on_socket_interacted):
			socket_interact_comp.interacted.connect(_on_socket_interacted)
		if not socket_interact_comp.focused.is_connected(_on_socket_focused):
			socket_interact_comp.focused.connect(_on_socket_focused)
		if not socket_interact_comp.unfocused.is_connected(_on_socket_unfocused):
			socket_interact_comp.unfocused.connect(_on_socket_unfocused)
	else:
		push_error("PuzzleSocket: CRITICAL - Could not find InteractComponent on ", name)


## Safely propagates the target array to the attached transmitter.
func _sync_transmitter() -> void:
	if not is_inside_tree() or not is_node_ready():
		return
	if is_instance_valid(transmitter):
		transmitter.targets = targets


## Manages the editor-only lightning particle preview instance based on state.
func _update_editor_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return

	var existing_preview: GPUParticles3D = (
		get_node_or_null(PREVIEW_PARTICLES_NAME) as GPUParticles3D
	)

	if is_power_source:
		if not is_instance_valid(existing_preview):
			var particles: GPUParticles3D = _build_lightning_particles()
			particles.name = PREVIEW_PARTICLES_NAME
			add_child(particles)
			if is_instance_valid(snap_position):
				particles.position = snap_position.position
		else:
			existing_preview.emitting = true
			existing_preview.visible = true
	elif is_instance_valid(existing_preview):
		existing_preview.queue_free()


## Cleans up any editor preview nodes that leaked into runtime memory.
func _remove_editor_preview() -> void:
	var existing_preview: Node = get_node_or_null(PREVIEW_PARTICLES_NAME)
	if is_instance_valid(existing_preview):
		existing_preview.queue_free()


## Constructs procedural electric spark particles for editor visualization.
func _build_lightning_particles() -> GPUParticles3D:
	var particles: GPUParticles3D = GPUParticles3D.new()
	var particle_mat: ParticleProcessMaterial = ParticleProcessMaterial.new()

	particle_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	particle_mat.emission_sphere_radius = 0.22
	particle_mat.direction = Vector3.UP
	particle_mat.spread = 180.0
	particle_mat.initial_velocity_min = 0.4
	particle_mat.initial_velocity_max = 1.0
	particle_mat.gravity = Vector3.ZERO
	particle_mat.scale_min = 0.8
	particle_mat.scale_max = 1.2

	var quad_mesh: QuadMesh = QuadMesh.new()
	quad_mesh.size = Vector2(0.12, 0.30)

	var draw_mat: StandardMaterial3D = StandardMaterial3D.new()
	draw_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw_mat.no_depth_test = true
	draw_mat.albedo_color = Color.WHITE

	if is_instance_valid(power_source_texture):
		draw_mat.albedo_texture = power_source_texture

	quad_mesh.material = draw_mat

	particles.amount = 9
	particles.lifetime = 0.35
	particles.explosiveness = 0.1
	particles.process_material = particle_mat
	particles.draw_pass_1 = quad_mesh
	return particles


## Extracts the plug and transfers it into the player's hands on interact.
func _on_socket_interacted(character: CharacterBody3D) -> void:
	print("Socket: Player interacted with socket.")
	if not is_powered:
		return

	if not can_be_unplugged:
		return

	var released_plug: Node3D = current_plug
	unplug()

	if is_instance_valid(released_plug) and released_plug.has_method("pick_up"):
		var player_hand_marker: Marker3D = character.get("hold_position") as Marker3D

		if is_instance_valid(player_hand_marker):
			character.set("held_object", released_plug)

			if released_plug is RigidBody3D:
				PhysicsServer3D.body_set_state(
					released_plug.get_rid(),
					PhysicsServer3D.BODY_STATE_TRANSFORM,
					player_hand_marker.global_transform
				)
				released_plug.linear_velocity = Vector3.ZERO
				released_plug.angular_velocity = Vector3.ZERO

			released_plug.pick_up(player_hand_marker, character)
			_on_socket_unfocused()
		else:
			push_warning("Socket: Could not find hold_position on Player!")


## Direct interact method fallback invoked when interacted directly by scanner.
func interact_with(character: CharacterBody3D) -> void:
	print("Socket: interact_with fallback called by character.")
	_on_socket_interacted(character)


## Detects a compatible plug entering the socket trigger zone.
func _on_body_entered(body: Node3D) -> void:
	if not is_powered and body.is_in_group("plug") and not is_cooling_down:
		plug_in(body)


## Detects when the active plug leaves the socket trigger boundary.
func _on_body_exited(body: Node3D) -> void:
	if is_powered and body == current_plug:
		unplug()


## Connects the plug, handles forced drop, and updates circuit states.
func plug_in(plug: Node3D) -> void:
	print("Socket: Plugging in ", plug.name)
	if plug.has_method("drop") and plug.get("is_held"):
		print("Socket: Plug is currently held. Forcing drop.")
		plug.drop()

	is_powered = true
	current_plug = plug

	_trigger_delayed_snap(plug)

	if not can_be_unplugged:
		if "is_locked" in plug:
			plug.set("is_locked", true)

	if is_instance_valid(socket_interact_comp):
		if socket_interact_comp.get("is_currently_focused") == true:
			_on_socket_focused()

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


## Waits for a physics tick before aligning and locking the plug.
func _trigger_delayed_snap(plug: Node3D) -> void:
	print("Socket: Awaiting physics frame to guarantee clean state.")
	await get_tree().physics_frame

	if is_instance_valid(plug) and is_powered:
		_snap_and_freeze_plug(plug)


## Detaches the current plug, restores physics, and resets outputs.
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
				_deenergize_targets()

		if current_plug.has_signal("power_state_changed"):
			current_plug.power_state_changed.disconnect(_on_plug_power_changed)

	is_powered = false
	is_cooling_down = true
	get_tree().create_timer(1.0, false).timeout.connect(func() -> void: is_cooling_down = false)

	if current_plug is RigidBody3D:
		var rb_plug: RigidBody3D = current_plug as RigidBody3D
		rb_plug.freeze = false
		if "is_locked" in rb_plug:
			rb_plug.set("is_locked", false)

	current_plug = null

	if is_instance_valid(indicator_light):
		indicator_light.visible = true
		indicator_light.light_color = Color.RED


## Displays context prompts, enables highlight, and emits speech cues.
func _on_socket_focused() -> void:
	print("Socket: _on_socket_focused() called.")
	if is_instance_valid(highlight_comp) and highlight_comp.has_method("set_highlighted"):
		highlight_comp.set_highlighted(true)

	if not is_instance_valid(label):
		print("Socket: Label node reference is NULL!")
		return

	var events: Array[InputEvent] = InputMap.action_get_events("interact")
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

	var speech_text: String = ""

	if is_powered and can_be_unplugged:
		label.text = "Unplug [%s]" % key_name
		speech_text = label.text
	elif not is_powered:
		label.text = "Find the plug"
		speech_text = label.text
	else:
		label.text = ""

	print("Socket: Label text set to: '", label.text, "' | show_prompts: ", _show_text_prompts)

	if _show_text_prompts and not label.text.is_empty():
		label.show()
	else:
		label.hide()

	if Events.has_signal("object_focused") and not speech_text.is_empty():
		print("Socket: Broadcasting object_focused prompt to TTSandy.")
		Events.object_focused.emit(speech_text, self)


## Hides prompt label and disables highlight when focus is lost.
func _on_socket_unfocused() -> void:
	print("Socket: _on_socket_unfocused() called.")
	if is_instance_valid(highlight_comp) and highlight_comp.has_method("set_highlighted"):
		highlight_comp.set_highlighted(false)

	if is_instance_valid(label):
		label.hide()


## Synchronizes prompt visibility when toggled in the settings menu.
func _on_item_prompts_toggled(enabled: bool) -> void:
	print("Socket: Item prompt visibility updated -> ", enabled)
	_show_text_prompts = enabled
	if not _show_text_prompts and is_instance_valid(label):
		label.hide()


## Reacts to power state modifications emitted by the connected plug.
func _on_plug_power_changed(has_power: bool) -> void:
	if not is_power_source and is_powered and requires_power_link:
		if has_power:
			if is_instance_valid(indicator_light):
				indicator_light.light_color = Color.GREEN
			_energize_targets()
		else:
			if is_instance_valid(indicator_light):
				indicator_light.light_color = Color.YELLOW
			_deenergize_targets()


## Broadcasts power-on signal and instructs transmitter to trigger targets.
func _energize_targets() -> void:
	print("Socket: Energizing targets via Transmitter.")
	socket_powered_on.emit()
	if is_instance_valid(transmitter):
		transmitter.power_on()
	else:
		push_warning("Socket: Missing OutputTransmitter3D! Cannot energize targets.")


## Broadcasts power-off signal and instructs transmitter to reset targets.
func _deenergize_targets() -> void:
	print("Socket: De-energizing targets via Transmitter.")
	socket_powered_off.emit()
	if is_instance_valid(transmitter):
		transmitter.power_off()
	else:
		push_warning("Socket: Missing OutputTransmitter3D! Cannot de-energize targets.")


## Freezes and locks the plug transform to the target snap position.
func _snap_and_freeze_plug(plug: Node3D) -> void:
	print("Socket: Snapping and freezing plug to exact center.")
	if not is_instance_valid(plug) or not is_instance_valid(snap_position):
		return

	var target_transform: Transform3D = snap_position.global_transform

	if "snap_marker" in plug and is_instance_valid(plug.get("snap_marker")):
		var marker: Marker3D = plug.get("snap_marker") as Marker3D
		target_transform = target_transform * marker.transform.affine_inverse()

	if plug is RigidBody3D:
		plug.linear_velocity = Vector3.ZERO
		plug.angular_velocity = Vector3.ZERO

		PhysicsServer3D.body_set_state(
			plug.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, target_transform
		)

		plug.global_transform = target_transform
		plug.freeze = true
	else:
		plug.global_transform = target_transform
