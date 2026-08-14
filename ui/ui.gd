class_name UIController
extends CanvasLayer

## Indicates if the environment is rendering without lighting.
var is_fullbright: bool = false

## Indicates if the game world is rendering as a wireframe.
var is_wireframe: bool = false

## Indicates if a wireframe overlay is applied to all meshes.
var is_wireframe_overlay: bool = false

## Indicates if physics collision shapes are drawn on screen.
var is_collision_visible: bool = false

## Tracks whether the user interface is currently hidden.
var is_ui_hidden: bool = false

## Material used to draw the green wireframe debug overlay.
var green_wireframe_material: ShaderMaterial

## Animates the red flash effect when the player takes damage.
var pain_tween: Tween

## Security variable: Indicates if debug commands (noclip) are allowed via input or events.
var is_debug_allowed: bool = OS.has_feature("debug")

# --- KEYCARD UI VARS ---
## Maps keycard IDs to their respective UI textures.
@export var card_textures: Dictionary[StringName, Texture2D] = {}

## Stores the currently instantiated keycard texture rectangles.
var active_card_icons: Dictionary = {}

## Animates the UI elements when the player enters or exits zoom mode.
var zoom_tween: Tween

## Tracks if the player is crouching to adjust UI elements like vignette.
var is_player_crouching: bool = false

## The speed multiplier for UI interpolation animations.
var ui_lerp_speed: float = 15.0

## Animates the crosshair scaling and transformations.
var crosshair_tween: Tween

## Stores the default dimensions of the center crosshair dot.
var default_crosshair_size: Vector2

# --- UI ELEMENT PATHS ---
## Container that centers the crosshair elements on the screen.
@onready var crosshair_container: CenterContainer = $CrosshairContainer

## The central dot texture of the crosshair.
@onready var center_dot: TextureRect = $CrosshairContainer/CenterDot

## The outer circular texture shown when zooming.
@onready var ui_circle_zoom: TextureRect = $CrosshairContainer/UICircleZoom

## The inner circular texture shown when zooming.
@onready var ui_circle_zoom_inner: TextureRect = $CrosshairContainer/UICircleZoomInner

## ColorRect applying a vignette effect to the screen edges.
@onready var vignette: ColorRect = $Vignette

## ColorRect applying a fisheye distortion effect when zooming.
@onready var fisheye_zoom: ColorRect = $FisheyeZoom

## ColorRect applying a visual glitch shader effect.
@onready var glitch_overlay: ColorRect = $GlitchOverlay

## ColorRect applying an electrical shock vignette effect.
@onready var electricity_vignette: ColorRect = $ElectricityVignette

# --- DEBUG & ALERT UI PATHS ---
## Container managing the layout of the noclip warning alert.
@onready var noclip_alert_container: MarginContainer = $NoclipAlertContainer

## Panel background for the noclip alert message.
@onready var noclip_message_container: PanelContainer = $NoclipAlertContainer/NoclipMessageContainer

## Label displaying the current noclip speed or status.
@onready
var noclip_label_message: Label = $NoclipAlertContainer/NoclipMessageContainer/NoclipLabelMessage

## CanvasLayer providing the debug overlay menu.
@onready var debug_panel: CanvasLayer = $DebugPanel

## Button to toggle noclip mode in the debug panel.
@onready var noclip_button: Button = $DebugPanel/PanelContainer/VBoxContainer/NoclipButton

## Button to toggle the performance metrics window.
@onready var metrics_button: Button = $DebugPanel/PanelContainer/VBoxContainer/MetricsButton

## Button to toggle visibility of collision shapes.
@onready var collision_button: Button = $DebugPanel/PanelContainer/VBoxContainer/CollisionButton

## Button to toggle fullbright rendering mode.
@onready var fullbright_button: Button = $DebugPanel/PanelContainer/VBoxContainer/FullbrightButton

## Button to toggle wireframe rendering mode.
@onready var wireframe_button: Button = $DebugPanel/PanelContainer/VBoxContainer/WireframeButton

## Button to toggle the green wireframe material overlay.
@onready var wireframe_overlay_button := (
	$"DebugPanel/PanelContainer/VBoxContainer/WireframeOverlayButton" as Button
)

## Button to hide the main user interface.
@onready var hide_ui_button: Button = $DebugPanel/PanelContainer/VBoxContainer/HideUIButton

## Panel displaying performance metrics like FPS and frame times.
@onready var metrics_panel: PanelContainer = $MetricsPanel

## ColorRect rendering a visual graph of frame times.
@onready var frame_graph: ColorRect = $FrameGraph

## ColorRect providing a red flash overlay when damage is taken.
@onready var pain_overlay: ColorRect = $PainOverlay

# --- HEALTH UI VARS ---
## The atlas texture containing the different heart states.
@export var hearts_atlas: Texture2D

## MarginContainer constraining the health UI to the screen edge.
@onready var health_margin: MarginContainer = $HealthMargin

## Container arranging the health heart icons horizontally.
@onready var hearts_container: HBoxContainer = $HealthMargin/VBoxContainer/HeartsContainer

## Container arranging collected keycard icons horizontally.
@onready var keycards_container: HBoxContainer = $HealthMargin/VBoxContainer/KeycardsContainer

## Container for the note reading screen dimming and text.
@onready var note_overlay_ui: CanvasLayer = $NoteOverlayUI

## Label displaying the actual contents of the read note.
@onready var note_text_label: RichTextLabel = $NoteOverlayUI/NoteText

## Container managing the layout of the sprint debuff UI.
@onready var debuff_container: HBoxContainer = $HealthMargin/VBoxContainer/DebuffContainer

## Icon indicating the sprint blocked debuff is active.
@onready
var sprint_debuff_icon: TextureRect = $HealthMargin/VBoxContainer/DebuffContainer/SprintDebuffIcon

## Progress bar showing the remaining duration of the sprint debuff.
@onready
var sprint_debuff_bar: ProgressBar = $HealthMargin/VBoxContainer/DebuffContainer/SprintDebuffBar

## Container managing the layout of the immobilize debuff UI.
@onready var immobilize_container: HBoxContainer = $HealthMargin/VBoxContainer/ImmobilizeContainer

## Icon indicating the immobilize debuff is active.
@onready
var immobilize_icon: TextureRect = $HealthMargin/VBoxContainer/ImmobilizeContainer/ImmobilizeIcon

## Progress bar showing the remaining duration of the immobilize debuff.
@onready
var immobilize_bar: ProgressBar = $HealthMargin/VBoxContainer/ImmobilizeContainer/ImmobilizeBar

## CanvasGroup for grouping the warning/hint text UI.
@onready var warning_canvas_group: CanvasGroup = $WarningCanvasGroup

## Label displaying temporary hint or warning text to the player.
@onready var warning_label: Label = $WarningCanvasGroup/WarningLabel

# --- DEBUFF UI VARS ---
## Tracks if the player is currently under the effects of an immobilize debuff.
var is_immobilized: bool = false

## Tracks if the player is currently under the effects of a sprint block debuff.
var is_sprint_blocked: bool = false

## Animates the sprint debuff progress bar.
var debuff_tween: Tween

## Animates the immobilize debuff progress bar.
var immobilize_tween: Tween

## Animates the visibility of on-screen warning messages.
var warning_tween: Tween

## Stores the sliced textures for each state of a health heart.
var heart_textures: Array[AtlasTexture] = []

## Stores the UI nodes representing the player's health hearts.
var heart_nodes: Array[TextureRect] = []

## Stores active tweens for individual heart damage animations.
var heart_tweens: Array[Tween] = []

## Tracks the player's current health to determine when to update the UI.
var current_health: int = 300

## Controls the glitch effect animation when shocked.
var glitch_tween: Tween

## Controls the electricity vignette animation when shocked.
var electro_tween: Tween

# --- SUBTITLE UI VARS ---
## Container managing the screen margins and layout bounds of the subtitle UI block.
@onready var subtitle_margin: MarginContainer = $SubtitleMargin

## Rich text element that types out the subtitle text and automatically scrolls it.
@onready var subtitle_label: RichTextLabel = $SubtitleMargin/SubtitlePanel/SubtitleLabel

## Animates the subtitle visibility and the typewriter character reveal effect.
var subtitle_tween: Tween

## Audio player for the text-scrolling blip sound.
var blip_player: AudioStreamPlayer = AudioStreamPlayer.new()

## The audio stream for TTSandy's UI blip (Assign this in the inspector).
@export var ttsandy_blip: AudioStreamMP3

## Tracks the last character count to prevent overlapping audio spam on the same frame.
var last_visible_char: int = 0


func _ready() -> void:
	print("UIController: _ready() called. Initializing UI elements.")
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	debug_panel.hide()

	if frame_graph:
		frame_graph.hide()

	metrics_button.pressed.connect(_on_metrics_button_pressed)

	Events.noclip_toggled.connect(_on_noclip_toggled)
	Events.noclip_speed_changed.connect(_on_noclip_speed_changed)
	Events.player_zoomed.connect(_on_player_zoomed)
	Events.player_crouch_changed.connect(_on_player_crouched)

	if Events.has_signal("player_health_changed"):
		if not Events.player_health_changed.is_connected(update_health):
			Events.player_health_changed.connect(update_health)

	fullbright_button.pressed.connect(_on_fullbright_button_pressed)
	collision_button.pressed.connect(_on_collision_button_pressed)
	hide_ui_button.pressed.connect(_on_hide_ui_button_pressed)
	Events.terminal_mode_toggled.connect(_on_terminal_mode_toggled)

	ui_circle_zoom.pivot_offset = ui_circle_zoom.custom_minimum_size / 2.0
	ui_circle_zoom.scale = Vector2.ZERO
	ui_circle_zoom.modulate.a = 0.0
	ui_circle_zoom.hide()

	ui_circle_zoom_inner.pivot_offset = ui_circle_zoom_inner.custom_minimum_size / 2.0
	ui_circle_zoom_inner.scale = Vector2.ZERO
	ui_circle_zoom_inner.modulate.a = 0.0
	ui_circle_zoom_inner.hide()

	default_crosshair_size = center_dot.custom_minimum_size
	if default_crosshair_size == Vector2.ZERO:
		default_crosshair_size = center_dot.size

	green_wireframe_material = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	shader.code = """
	shader_type spatial;
	render_mode wireframe, unshaded, cull_disabled;

	void fragment() {
		ALBEDO = vec3(0.0, 1.0, 0.0);
	}
	"""
	green_wireframe_material.shader = shader

	_initialize_hearts()
	call_deferred("_check_if_testbed")

	KeycardSystem.card_picked_up.connect(_on_card_picked_up)
	KeycardSystem.card_used.connect(_on_card_used)

	debuff_container.hide()
	immobilize_container.hide()

	if warning_label:
		warning_label.modulate.a = 0.0
		# Apply simple outline theme override to solve the white box background bug
		warning_label.add_theme_color_override("font_outline_color", Color.BLACK)
		warning_label.add_theme_constant_override("outline_size", 12)

	if warning_canvas_group:
		warning_canvas_group.material = null

	# Fix placement of the CanvasGroup Node2D relative to the screen
	_recenter_warning_ui()
	get_viewport().size_changed.connect(_recenter_warning_ui)

	if Events.has_signal("sprint_debuff_applied"):
		if not Events.sprint_debuff_applied.is_connected(_on_sprint_debuff_applied):
			Events.sprint_debuff_applied.connect(_on_sprint_debuff_applied)

	if Events.has_signal("immobilize_debuff_applied"):
		if not Events.immobilize_debuff_applied.is_connected(_on_immobilize_debuff_applied):
			Events.immobilize_debuff_applied.connect(_on_immobilize_debuff_applied)

	if not Events.player_electrocuted.is_connected(_on_player_electrocuted):
		Events.player_electrocuted.connect(_on_player_electrocuted)

	if glitch_overlay != null and glitch_overlay.material is ShaderMaterial:
		glitch_overlay.material.set_shader_parameter("intensity", 0.0)
		glitch_overlay.hide()

	if electricity_vignette != null and electricity_vignette.material is ShaderMaterial:
		electricity_vignette.material.set_shader_parameter("intensity", 0.0)
		electricity_vignette.hide()

	if Events.has_signal("hint_requested"):
		if not Events.hint_requested.is_connected(_show_warning_message):
			Events.hint_requested.connect(_show_warning_message)

	if note_overlay_ui != null:
		note_overlay_ui.hide()

	if Events.has_signal("note_opened"):
		if not Events.note_opened.is_connected(_on_note_opened):
			Events.note_opened.connect(_on_note_opened)

	if Events.has_signal("note_closed"):
		if not Events.note_closed.is_connected(_on_note_closed):
			Events.note_closed.connect(_on_note_closed)
	
	# Add the audio player to the scene tree so it can process sound
	add_child(blip_player)
	
	if Events.has_signal("subtitle_requested"):
		if not Events.subtitle_requested.is_connected(_on_subtitle_requested):
			Events.subtitle_requested.connect(_on_subtitle_requested)
			
	if Events.has_signal("subtitle_canceled"):
		if not Events.subtitle_canceled.is_connected(_on_subtitle_canceled):
			Events.subtitle_canceled.connect(_on_subtitle_canceled)
			
	if subtitle_margin:
		subtitle_margin.hide()
		subtitle_margin.modulate.a = 0.0

func _recenter_warning_ui() -> void:
	print("UIController: _recenter_warning_ui() called to position hint text.")
	if not warning_canvas_group or not warning_label:
		return

	var screen_size: Vector2 = get_viewport().get_visible_rect().size

	# Place the Node2D (CanvasGroup) exactly in the X center and 80px below the Y center
	warning_canvas_group.position = Vector2(screen_size.x / 2.0, (screen_size.y / 2.0) + 70.0)

	# Setting this preset relative to a 0x0 Node2D origin causes the label
	# to perfectly center its own text bounds directly underneath that anchor point.
	warning_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)


func _process(delta: float) -> void:
	var target_vignette_opacity: float = 0.8 if is_player_crouching else 0.0

	var current_opacity: float = vignette.material.get_shader_parameter("vignette_opacity") as float

	if current_opacity == null:
		current_opacity = 0.0

	var new_opacity: float = lerp(current_opacity, target_vignette_opacity, delta * ui_lerp_speed)
	vignette.material.set_shader_parameter("vignette_opacity", new_opacity)


# --- HEALTH LOGIC ---
func _initialize_hearts() -> void:
	print("UIController: _initialize_hearts() called. Setting up health display.")
	if not hearts_atlas:
		push_warning("Hearts atlas not assigned in UI inspector!")
		return

	var atlas_width: float = hearts_atlas.get_width()
	var atlas_height: float = hearts_atlas.get_height()
	var frame_width: float = atlas_width / 5.0

	# Cache textures
	for i: int in range(5):
		var tex: AtlasTexture = AtlasTexture.new()
		tex.atlas = hearts_atlas
		tex.region = Rect2(i * frame_width, 0.0, frame_width, atlas_height)
		heart_textures.append(tex)

	# Populate initial required hearts
	while heart_nodes.size() * 100 < current_health:
		_add_heart_node()

	update_health(current_health)


## Helper function to dynamically add a single heart UI node.
func _add_heart_node() -> void:
	print("UIController: _add_heart_node() - Expanding maximum heart UI count.")
	var atlas_height: float = hearts_atlas.get_height()
	var frame_width: float = hearts_atlas.get_width() / 5.0
	var target_size: Vector2 = Vector2(frame_width * 2.0, atlas_height * 2.0)

	var wrapper: Control = Control.new()
	wrapper.custom_minimum_size = target_size
	wrapper.use_parent_material = true
	hearts_container.add_child(wrapper)

	var rect: TextureRect = TextureRect.new()
	rect.texture = heart_textures[0]
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = target_size
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.use_parent_material = true

	wrapper.add_child(rect)
	heart_nodes.append(rect)
	heart_tweens.append(null)


func update_health(new_health: int) -> void:
	print("UIController: update_health() called with new value: ", new_health)

	# Expand UI dynamically if health exceeds current node count
	while new_health > heart_nodes.size() * 100:
		_add_heart_node()

	var health_decreased: bool = new_health < current_health
	var health_increased: bool = new_health > current_health
	var previous_health: int = current_health
	current_health = new_health

	if health_decreased:
		_trigger_pain_effect()

	if heart_nodes.is_empty() or heart_textures.is_empty():
		return

	for i: int in range(heart_nodes.size()):
		var heart_min: int = i * 100
		var heart_val: int = clampi(current_health - heart_min, 0, 100)
		var prev_heart_val: int = clampi(previous_health - heart_min, 0, 100)

		var frame_index: int = 0
		if heart_val >= 100:
			frame_index = 0
		elif heart_val >= 75:
			frame_index = 1
		elif heart_val >= 50:
			frame_index = 2
		elif heart_val >= 25:
			frame_index = 3
		else:
			frame_index = 4

		heart_nodes[i].texture = heart_textures[frame_index]

		if health_decreased and heart_val < prev_heart_val:
			_animate_heart_damage(i)
		elif health_increased and heart_val > prev_heart_val:
			_animate_heart_heal(i, frame_index)

		heart_nodes[i].get_parent().visible = true


func _trigger_pain_effect() -> void:
	print("UIController: _trigger_pain_effect() called. Flashing screen red.")
	if pain_overlay == null:
		return

	pain_overlay.show()

	# 1. Kill any existing pain tween so rapid hits don't break the animation
	if pain_tween and pain_tween.is_valid():
		pain_tween.kill()

	# 2. FORCE pure red (RGB 1,0,0) with 0.4 alpha, bypassing any inspector settings
	pain_overlay.color = Color(1.0, 0.0, 0.0, 0.4)

	# 3. Tween the entire color property down to 0.0 alpha
	pain_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	pain_tween.tween_property(pain_overlay, "color", Color(1.0, 0.0, 0.0, 0.0), 0.3)
	pain_tween.finished.connect(pain_overlay.hide)


func _animate_heart_damage(index: int) -> void:
	print("UIController: _animate_heart_damage() called for heart index: ", index)
	if index < 0 or index >= heart_nodes.size():
		return

	var heart: TextureRect = heart_nodes[index]

	if heart_tweens[index] and heart_tweens[index].is_valid():
		heart_tweens[index].kill()

	heart.position.y = 0.0

	var tween: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	heart_tweens[index] = tween

	var jump_height: float = -15.0
	var duration: float = 0.08

	tween.tween_property(heart, "position:y", jump_height, duration)
	tween.tween_property(heart, "position:y", jump_height * -0.3, duration)
	tween.tween_property(heart, "position:y", 0.0, duration)


func _animate_heart_heal(index: int, frame_index: int) -> void:
	print("UIController: _animate_heart_heal() called for heart index: ", index)
	if index < 0 or index >= heart_nodes.size():
		return

	var heart: TextureRect = heart_nodes[index]
	var ghost: TextureRect = TextureRect.new()

	ghost.texture = heart_textures[frame_index]
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.custom_minimum_size = heart.custom_minimum_size
	ghost.size = heart.size
	ghost.position = Vector2.ZERO
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ghost.pivot_offset = ghost.size / 2.0
	ghost.modulate = Color(0.0, 1.0, 0.0, 0.5)

	heart.add_child(ghost)

	var tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)

	var anim_duration: float = 0.5
	tween.tween_property(ghost, "scale", Vector2(3.0, 3.0), anim_duration)
	tween.tween_property(ghost, "modulate:a", 0.0, anim_duration)

	tween.chain().tween_callback(ghost.queue_free)


# --- ZOOM ANIMATION LOGIC ---
func _on_player_zoomed(is_zooming: bool) -> void:
	print("UIController: _on_player_zoomed() called. State: ", is_zooming)
	if zoom_tween and zoom_tween.is_valid():
		zoom_tween.kill()

	zoom_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)

	if is_zooming:
		center_dot.hide()
		ui_circle_zoom.show()
		ui_circle_zoom_inner.show()

		ui_circle_zoom.scale = Vector2.ZERO
		ui_circle_zoom.modulate.a = 0.0
		ui_circle_zoom_inner.scale = Vector2.ZERO
		ui_circle_zoom_inner.modulate.a = 0.0

		zoom_tween.tween_property(ui_circle_zoom, "scale", Vector2(1.0, 1.0), 0.5).from(
			Vector2.ZERO
		)
		zoom_tween.tween_property(ui_circle_zoom, "modulate:a", 1.0, 0.3).from(0.0)
		zoom_tween.tween_property(ui_circle_zoom, "rotation", deg_to_rad(15), 1.0).from(0.0)

		zoom_tween.tween_property(ui_circle_zoom_inner, "scale", Vector2(1.0, 1.0), 0.5).from(
			Vector2.ZERO
		)
		zoom_tween.tween_property(ui_circle_zoom_inner, "modulate:a", 0.1, 0.3).from(0.0)
		zoom_tween.tween_property(ui_circle_zoom_inner, "rotation", deg_to_rad(-45), 1.0).from(0.0)

		(
			zoom_tween
			. tween_property(fisheye_zoom, "material:shader_parameter/effect_strength", 0.4, 0.2)
			. from(0.0)
		)

	else:
		center_dot.show()

		zoom_tween.tween_property(ui_circle_zoom, "scale", Vector2(0.0, 0.0), 0.5)
		zoom_tween.tween_property(ui_circle_zoom, "modulate:a", 0.0, 0.3)
		zoom_tween.tween_property(ui_circle_zoom, "rotation", deg_to_rad(0), 0.25)

		zoom_tween.tween_property(ui_circle_zoom_inner, "scale", Vector2(0.0, 0.0), 0.5)
		zoom_tween.tween_property(ui_circle_zoom_inner, "modulate:a", 0.0, 0.3)
		zoom_tween.tween_property(ui_circle_zoom_inner, "rotation", deg_to_rad(0), 0.25)

		zoom_tween.tween_property(
			fisheye_zoom, "material:shader_parameter/effect_strength", 0.0, 0.2
		)

		zoom_tween.finished.connect(
			func() -> void:
				ui_circle_zoom.hide()
				ui_circle_zoom_inner.hide()
		)


# --- CROUCH LISTENER ---
func _on_player_crouched(crouching: bool) -> void:
	is_player_crouching = crouching
	print("UIController: received crouch signal! Crouching: ", crouching)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		# Check for the tilde key to open the debug panel
		if event.keycode == KEY_QUOTELEFT and is_debug_allowed:
			print("UIController: Tilde key pressed. Opening debug panel.")
			_toggle_debug_panel()

		# Catch physical movement inputs to display warnings while debuffed
		if is_immobilized:
			if event.keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_SHIFT]:
				print("UIController: Movement blocked - player is immobilized.")
				_show_warning_message("Can't move!", 2.0)
		elif is_sprint_blocked:
			if event.keycode == KEY_SHIFT:
				print("UIController: Movement blocked - sprint is on cooldown.")
				_show_warning_message("Can't sprint", 2.0)


func _toggle_debug_panel() -> void:
	debug_panel.visible = not debug_panel.visible
	print("UIController: Debug panel visibility toggled -> ", debug_panel.visible)

	if debug_panel.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_noclip_button_pressed() -> void:
	print("UIController: Noclip button pressed.")
	Events.noclip_ui_button_pressed.emit()


func _on_noclip_toggled(is_flying: bool) -> void:
	print("UIController: Noclip toggled. State: ", is_flying)
	if is_flying:
		noclip_message_container.show()
		noclip_button.text = "Noclip ON"
	else:
		noclip_message_container.hide()
		noclip_button.text = "Noclip OFF"


func _on_noclip_speed_changed(speed: float) -> void:
	#print("UIController: _on_noclip_speed_changed() called. Speed: ", speed)
	noclip_label_message.text = "Noclip ON: %.1fx speed" % speed


func _on_fullbright_button_pressed() -> void:
	is_fullbright = !is_fullbright
	print("UIController: Fullbright toggled. State: ", is_fullbright)

	if is_fullbright:
		fullbright_button.text = "Fullbright ON"
	else:
		fullbright_button.text = "Fullbright OFF"

	Events.fullbright_toggled.emit(is_fullbright)


func _on_wireframe_button_pressed() -> void:
	is_wireframe = !is_wireframe
	print("UIController: Wireframe toggled. State: ", is_wireframe)

	if is_wireframe:
		wireframe_button.text = "Wireframe ON"
	else:
		wireframe_button.text = "Wireframe OFF"

	Events.wireframe_toggled.emit(is_wireframe)


func _on_wireframe_overlay_button_pressed() -> void:
	is_wireframe_overlay = !is_wireframe_overlay
	print("UIController: Wireframe overlay toggled. State: ", is_wireframe_overlay)

	if is_wireframe_overlay:
		wireframe_overlay_button.text = "Wireframe Overlay ON"
	else:
		wireframe_overlay_button.text = "Wireframe Overlay OFF"

	Events.wireframe_overlay_toggled.emit(is_wireframe_overlay)

	var root_node: Node = get_tree().current_scene
	if root_node:
		_apply_wireframe_to_node(root_node, is_wireframe_overlay)


func _apply_wireframe_to_node(node: Node, is_overlay: bool) -> void:
	if node is MeshInstance3D or node is CSGShape3D:
		if is_overlay:
			node.material_overlay = green_wireframe_material
		else:
			node.material_overlay = null

	for child: Node in node.get_children():
		_apply_wireframe_to_node(child, is_overlay)


func _on_metrics_button_pressed() -> void:
	print("UIController: Metrics button pressed.")
	if metrics_panel:
		metrics_panel.toggle_window()

		if frame_graph:
			frame_graph.visible = metrics_panel.visible


# --- NEW CROSSHAIR ANIMATION ---
func _on_terminal_mode_toggled(is_active: bool) -> void:
	print("UIController: Terminal mode toggled to ", is_active, ". Animating crosshair.")

	if crosshair_tween and crosshair_tween.is_valid():
		crosshair_tween.kill()

	crosshair_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)

	if is_active:
		var target_size: Vector2 = Vector2(16.0, 16.0)
		crosshair_tween.tween_property(center_dot, "custom_minimum_size", target_size, 0.3)
		crosshair_tween.tween_property(center_dot, "size", target_size, 0.3)
	else:
		crosshair_tween.tween_property(
			center_dot, "custom_minimum_size", default_crosshair_size, 0.3
		)
		crosshair_tween.tween_property(center_dot, "size", default_crosshair_size, 0.3)


# --- COLLISION DEBUG LOGIC ---
func _on_collision_button_pressed() -> void:
	is_collision_visible = !is_collision_visible
	print("UIController: Collision visibility toggled. State: ", is_collision_visible)

	get_tree().debug_collisions_hint = is_collision_visible
	collision_button.text = "Collisions ON" if is_collision_visible else "Collisions OFF"

	var root_node: Node = get_tree().current_scene
	if root_node:
		_force_collision_redraw(root_node, is_collision_visible)


func _force_collision_redraw(node: Node, show_collisions: bool) -> void:
	if node is CollisionShape3D and node.shape:
		var temp_shape: Shape3D = node.shape
		node.shape = null
		node.shape = temp_shape
	elif node is ShapeCast3D and node.shape:
		var temp_shape: Shape3D = node.shape
		node.shape = null
		node.shape = temp_shape
	elif node is RayCast3D:
		var temp_target: Vector3 = node.target_position
		node.target_position = Vector3.ZERO
		node.target_position = temp_target

	if node is CollisionShape3D or node is RayCast3D or node is ShapeCast3D:
		node.visible = show_collisions

	for child: Node in node.get_children():
		_force_collision_redraw(child, show_collisions)


func _on_hide_ui_button_pressed() -> void:
	print("UIController: Hide UI button pressed.")
	hide_ui_button.release_focus()
	_toggle_ui_elements(not is_ui_hidden)


func _toggle_ui_elements(should_hide: bool) -> void:
	is_ui_hidden = should_hide
	var visibility: bool = !is_ui_hidden

	crosshair_container.visible = visibility
	noclip_alert_container.visible = visibility
	health_margin.visible = visibility
	vignette.visible = visibility
	fisheye_zoom.visible = visibility

	hide_ui_button.text = "Show UI" if is_ui_hidden else "Hide UI"
	print("UIController: UI Visibility set to: ", visibility)


func _check_if_testbed() -> void:
	print("UIController: Checking if current scene is TestbedMap...")
	var current_scene: Node = get_tree().current_scene

	if current_scene and "testbed.scn" in current_scene.scene_file_path.to_lower():
		_open_metrics_panel()


func _open_metrics_panel() -> void:
	print("UIController: TestbedMap detected. Opening metrics panel automatically.")

	if metrics_panel and not metrics_panel.visible:
		metrics_panel.toggle_window()

		if frame_graph:
			frame_graph.visible = metrics_panel.visible


func _on_card_picked_up(card_id: StringName) -> void:
	print("UIController: Displaying new card ID ", card_id)
	var card_rect: TextureRect = TextureRect.new()
	card_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_rect.custom_minimum_size = Vector2(80.0, 130.0)
	card_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	if card_textures.has(card_id):
		card_rect.texture = card_textures[card_id]
	else:
		print("UI Warning: No texture mapped in UIController for card ID: ", card_id)

	keycards_container.add_child(card_rect)
	active_card_icons[card_id] = card_rect

	# Bounce animation
	card_rect.scale = Vector2.ZERO
	card_rect.pivot_offset = card_rect.custom_minimum_size / 2.0
	var tween: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card_rect, "scale", Vector2.ONE, 0.4)


func _on_card_used(card_id: StringName) -> void:
	print("UIController: Removing used card ID ", card_id)
	if active_card_icons.has(card_id):
		var card_rect: TextureRect = active_card_icons[card_id]
		var tween: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(card_rect, "scale", Vector2.ZERO, 0.2)
		tween.finished.connect(card_rect.queue_free)
		active_card_icons.erase(card_id)


func _show_warning_message(message: String, duration: float) -> void:
	print("UIController: Displaying warning '", message, "' for ", duration, "s.")
	warning_label.text = message

	if warning_tween and warning_tween.is_valid():
		warning_tween.kill()

	warning_tween = create_tween().set_trans(Tween.TRANS_SINE)
	warning_tween.tween_property(warning_label, "modulate:a", 1.0, 0.1)
	warning_tween.tween_interval(duration)
	warning_tween.tween_property(warning_label, "modulate:a", 0.0, 0.5)


func _on_sprint_debuff_applied(duration: float) -> void:
	print(
		"UIController: _on_sprint_debuff_applied() - Starting debuff UI for ", duration, " seconds."
	)
	debuff_container.show()
	is_sprint_blocked = true

	sprint_debuff_bar.max_value = duration
	sprint_debuff_bar.value = duration

	if debuff_tween and debuff_tween.is_valid():
		debuff_tween.kill()

	debuff_tween = create_tween()
	debuff_tween.tween_property(sprint_debuff_bar, "value", 0.0, duration)

	debuff_tween.finished.connect(
		func() -> void:
			debuff_container.hide()
			is_sprint_blocked = false
	)


func _on_immobilize_debuff_applied(duration: float) -> void:
	print(
		"UIController: _on_immobilize_debuff_applied() - Starting immobilize UI for ",
		duration,
		" seconds."
	)
	immobilize_container.show()
	is_immobilized = true

	immobilize_bar.max_value = duration
	immobilize_bar.value = duration

	if immobilize_tween and immobilize_tween.is_valid():
		immobilize_tween.kill()

	immobilize_tween = create_tween()
	immobilize_tween.tween_property(immobilize_bar, "value", 0.0, duration)

	immobilize_tween.finished.connect(
		func() -> void:
			immobilize_container.hide()
			is_immobilized = false
	)


func _on_player_electrocuted() -> void:
	print("UIController: _on_player_electrocuted() - Triggering electric shock UI effects.")

	# 1. Instantly kill the pain overlay if it was triggered by the damage tick
	if pain_tween and pain_tween.is_valid():
		pain_tween.kill()
	if pain_overlay:
		pain_overlay.hide()

	if glitch_overlay != null and glitch_overlay.material is ShaderMaterial:
		glitch_overlay.show()
		if glitch_tween and glitch_tween.is_valid():
			glitch_tween.kill()

		glitch_tween = create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

		glitch_tween.tween_method(
			func(val: float) -> void:
				glitch_overlay.material.set_shader_parameter("intensity", val)
				glitch_overlay.queue_redraw(),
			0.6,
			0.0,
			0.4
		)
		glitch_tween.finished.connect(glitch_overlay.hide)

	if electricity_vignette != null and electricity_vignette.material is ShaderMaterial:
		electricity_vignette.show()
		if electro_tween and electro_tween.is_valid():
			electro_tween.kill()

		electro_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

		electro_tween.tween_method(
			func(val: float) -> void:
				electricity_vignette.material.set_shader_parameter("intensity", val)
				electricity_vignette.queue_redraw(),
			1.0,
			0.0,
			0.5
		)
		electro_tween.finished.connect(electricity_vignette.hide)


func _on_note_opened(note_text: String) -> void:
	print("UIController: _on_note_opened() received. Displaying text.")
	if note_overlay_ui != null and note_text_label != null:
		var formatted_text: String = note_text.replace("\\n", "\n")
		note_text_label.text = formatted_text
		note_overlay_ui.show()


func _on_note_closed() -> void:
	print("UIController: _on_note_closed() received. Hiding UI.")
	if note_overlay_ui != null:
		note_overlay_ui.hide()


## Displays the subtitle text, typing it out to match audio length, and fades out after.
func _on_subtitle_requested(speaker: String, text: String, duration: float) -> void:
	print("UIController: _on_subtitle_requested() called. Displaying scrolling subtitle for ", speaker)
	
	if not subtitle_label or not subtitle_margin:
		return
		
	var formatted_speaker: String = speaker
	
	if speaker == "TTSandy":
		formatted_speaker = "[color=#00ffff][b]" + speaker + ":[/b][/color]"
		
		# Play the blip exactly ONCE right as the UI appears
		if ttsandy_blip != null:
			blip_player.stream = ttsandy_blip
			# FIX: Locked the pitch to 1.0 for a consistent accessibility audio cue.
			blip_player.pitch_scale = 1.0
			blip_player.play()
	else:
		formatted_speaker = "[b]" + speaker + ":[/b]"
		
	subtitle_label.text = formatted_speaker + " " + text
	
	subtitle_label.visible_characters = 0
	subtitle_margin.show()
	
	if subtitle_tween and subtitle_tween.is_valid():
		subtitle_tween.kill()
		
	subtitle_tween = create_tween()
	
	subtitle_tween.parallel().tween_property(subtitle_margin, "modulate:a", 1.0, 0.15)
	
	var total_chars: int = subtitle_label.get_total_character_count()
	var type_duration: float = max(0.1, duration - 0.5)
	
	# We removed .bind(speaker) since the update function no longer needs to know who is talking
	subtitle_tween.parallel().tween_method(
		_update_visible_characters,
		0,
		total_chars,
		type_duration
	)
	
	subtitle_tween.chain().tween_interval(0.5)
	subtitle_tween.chain().tween_property(subtitle_margin, "modulate:a", 0.0, 0.5)
	subtitle_tween.finished.connect(subtitle_margin.hide)


## Updates the visible characters for the typewriter effect.
func _update_visible_characters(current_chars: int) -> void:
	subtitle_label.visible_characters = current_chars


func _on_subtitle_canceled() -> void:
	print("UIController: _on_subtitle_canceled() called. Stopping subtitle animations.")
	
	if subtitle_tween and subtitle_tween.is_valid():
		subtitle_tween.kill()
		
	if blip_player and blip_player.playing:
		blip_player.stop()
		
	if subtitle_margin:
		subtitle_margin.hide()
		subtitle_margin.modulate.a = 0.0
