## Manages on-screen warning messages, contextual prompts, and note reading overlays.
class_name NotificationHUD
extends Control

@export_category("Vault Prompt Settings")
## Display size for the Kenney jump prompt icon widget.
@export var prompt_size: Vector2 = Vector2(64.0, 64.0)
## Vertical pixel offset positioning the prompt below the center crosshair.
@export var center_dot_offset_y: float = 40.0

## Container used to control warning label opacity and layout position.
@onready var warning_container: Control = $WarningContainer
## Label displaying temporary hint or warning text to the player.
@onready var warning_label: Label = $WarningContainer/WarningLabel
## Container for the note reading screen dimming and text presentation.
@onready var note_overlay_ui: CanvasLayer = $NoteOverlayUI
## Rich text label displaying the formatted note content.
@onready var note_text_label: RichTextLabel = $NoteOverlayUI/NoteText
## Dynamic parent container holding the vault prompt icon.
@onready var vault_prompt_container: Control = $VaultPromptContainer
## Texture display node holding the Kenney jump keybind icon.
@onready var vault_key_icon: TextureRect = $VaultPromptContainer/VaultKeyIcon

## Animates visibility fade transitions for warning banners.
var warning_tween: Tween
## Animates visibility fade transitions for the vault prompt.
var vault_prompt_tween: Tween
## Target 2D screen coordinate actively interpolated by the prompt container.
var _target_prompt_pos: Vector2 = Vector2.ZERO
## World coordinate of the active ledge target edge.
var _target_world_pos: Vector3 = Vector3.ZERO
## Tracks whether a vault ledge is currently available.
var _is_vault_available: bool = false
## Tracks whether the prompt widget is currently faded in.
var _is_prompt_showing: bool = false
## Tracks whether the player is currently holding an object.
var _is_holding_item: bool = false


## Initializes UI components and binds global bus listeners.
func _ready() -> void:
	print("NotificationHUD: _ready() called. Initializing UI.")
	if is_instance_valid(note_overlay_ui):
		note_overlay_ui.hide()

	if is_instance_valid(warning_label):
		warning_label.modulate.a = 0.0
		warning_label.add_theme_color_override("font_outline_color", Color.BLACK)
		warning_label.add_theme_constant_override("outline_size", 12)

	if is_instance_valid(vault_prompt_container):
		vault_prompt_container.top_level = true
		vault_prompt_container.custom_minimum_size = prompt_size
		vault_prompt_container.size = prompt_size
		vault_prompt_container.pivot_offset = prompt_size * 0.5
		vault_prompt_container.modulate.a = 0.0
		vault_prompt_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_update_vault_key_icon()

	_connect_signals()


## Interpolates prompt position across 2D viewport coordinates.
## [param delta] Elapsed frame delta time in seconds.
func _process(delta: float) -> void:
	if not _is_prompt_showing and not _is_vault_available:
		return
	if not is_instance_valid(vault_prompt_container):
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	var icon_size: Vector2 = vault_prompt_container.size
	var resting_pos: Vector2 = Vector2(
		(viewport_size.x - icon_size.x) * 0.5,
		((viewport_size.y - icon_size.y) * 0.5) + center_dot_offset_y
	)

	var camera: Camera3D = get_viewport().get_camera_3d()
	if is_instance_valid(camera) and _target_world_pos != Vector3.ZERO:
		var is_behind: bool = camera.is_position_behind(_target_world_pos)
		var screen_2d: Vector2 = camera.unproject_position(_target_world_pos)
		var is_on_screen: bool = not is_behind and get_viewport_rect().has_point(screen_2d)

		if is_on_screen:
			_target_prompt_pos = screen_2d - (icon_size * 0.5)
		else:
			_target_prompt_pos = resting_pos
	else:
		_target_prompt_pos = resting_pos

	vault_prompt_container.global_position = (vault_prompt_container.global_position.lerp(
		_target_prompt_pos, delta * 20.0
	))


## Binds notification and prompt events from the global [Events] bus.
func _connect_signals() -> void:
	print("NotificationHUD: Connecting global event bus signals.")
	if not Events.hint_requested.is_connected(show_warning_message):
		Events.hint_requested.connect(show_warning_message)
	if not Events.note_opened.is_connected(_on_note_opened):
		Events.note_opened.connect(_on_note_opened)
	if not Events.note_closed.is_connected(_on_note_closed):
		Events.note_closed.connect(_on_note_closed)
	if not Events.vault_prompt_updated.is_connected(_on_vault_prompt_updated):
		Events.vault_prompt_updated.connect(_on_vault_prompt_updated)
	if not Events.held_item_changed.is_connected(_on_held_item_changed):
		Events.held_item_changed.connect(_on_held_item_changed)


## Refreshes the vault icon texture matching the jump action.
func _update_vault_key_icon() -> void:
	print("NotificationHUD: Updating vault keybind icon.")
	if not is_instance_valid(vault_key_icon):
		return

	var helper: Node = get_node_or_null("/root/InputHelper")
	if not is_instance_valid(helper):
		helper = get_node_or_null("/root/InputHelperClass")

	if not is_instance_valid(helper) or not InputMap.has_action("jump"):
		return

	var events: Array[InputEvent] = InputMap.action_get_events("jump")
	if events.is_empty():
		return

	var icon_tex: Texture2D = helper.call("get_event_icon", events[0]) as Texture2D
	if is_instance_valid(icon_tex):
		vault_key_icon.texture = icon_tex
		vault_key_icon.custom_minimum_size = prompt_size


## Receives vault availability updates and target ledge world positions.
## [param is_available] Flags if a vaultable ledge is currently nearby.
## [param world_pos] 3D world coordinate of the ledge edge point.
func _on_vault_prompt_updated(is_available: bool, world_pos: Vector3) -> void:
	if not is_instance_valid(vault_prompt_container):
		return

	_is_vault_available = is_available and not _is_holding_item
	_target_world_pos = world_pos

	if _is_vault_available:
		if not _is_prompt_showing:
			_is_prompt_showing = true
			var viewport_size: Vector2 = get_viewport_rect().size
			var icon_size: Vector2 = vault_prompt_container.size
			_target_prompt_pos = Vector2(
				(viewport_size.x - icon_size.x) * 0.5,
				((viewport_size.y - icon_size.y) * 0.5) + center_dot_offset_y
			)
			vault_prompt_container.global_position = _target_prompt_pos
			_fade_vault_prompt(1.0)
	else:
		if _is_prompt_showing:
			_is_prompt_showing = false
			_fade_vault_prompt(0.0)


## Handles held item status changes, immediately hiding prompt when carrying.
## [param is_holding] True if an object is actively carried.
func _on_held_item_changed(is_holding: bool) -> void:
	print("NotificationHUD: _on_held_item_changed() called -> ", is_holding)
	_is_holding_item = is_holding
	if _is_holding_item and _is_prompt_showing:
		_is_prompt_showing = false
		_fade_vault_prompt(0.0)


## Smoothly animates the alpha opacity of the vault prompt widget.
## [param target_alpha] The destination alpha transparency float.
func _fade_vault_prompt(target_alpha: float) -> void:
	print("NotificationHUD: Fading vault prompt to alpha: ", target_alpha)
	if is_instance_valid(vault_prompt_tween) and vault_prompt_tween.is_valid():
		vault_prompt_tween.kill()

	vault_prompt_tween = create_tween().set_trans(Tween.TRANS_SINE)
	vault_prompt_tween.tween_property(vault_prompt_container, "modulate:a", target_alpha, 0.15)


## Fades in a centered notification banner with the provided text.
## [param message] String content to present to the user.
## [param duration] Visible display duration before fading out.
func show_warning_message(message: String, duration: float = 2.0) -> void:
	print("NotificationHUD: Displaying warning '", message, "' for ", duration, "s.")
	if not is_instance_valid(warning_label):
		return

	warning_label.text = message

	if is_instance_valid(warning_tween) and warning_tween.is_valid():
		warning_tween.kill()

	warning_tween = create_tween().set_trans(Tween.TRANS_SINE)
	warning_tween.tween_property(warning_label, "modulate:a", 1.0, 0.1)
	warning_tween.tween_interval(duration)
	warning_tween.tween_property(warning_label, "modulate:a", 0.0, 0.5)


## Shows the note reading interface populated with formatted note text.
## [param note_text] Raw text string loaded from the note entity.
func _on_note_opened(note_text: String) -> void:
	print("NotificationHUD: _on_note_opened() received.")
	if is_instance_valid(note_overlay_ui) and is_instance_valid(note_text_label):
		var formatted_text: String = note_text.replace("\\n", "\n")
		note_text_label.text = formatted_text
		note_overlay_ui.show()


## Hides the note reading canvas layer.
func _on_note_closed() -> void:
	print("NotificationHUD: _on_note_closed() received.")
	if is_instance_valid(note_overlay_ui):
		note_overlay_ui.hide()
