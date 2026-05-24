extends CanvasLayer

var is_fullbright: bool = false
var is_wireframe: bool = false
var is_wireframe_overlay: bool = false
var is_collision_visible: bool = false
var is_ui_hidden: bool = false

var green_wireframe_material: ShaderMaterial

# NEW UI VARS
var zoom_tween: Tween
var is_player_crouching: bool = false
var ui_lerp_speed: float = 15.0

var crosshair_tween: Tween
var default_crosshair_size: Vector2

@onready var center_dot: TextureRect = $MarginContainer/CenterDot
@onready var ui_circle_zoom: TextureRect = $MarginContainer/UICircleZoom
@onready var ui_circle_zoom_inner: TextureRect = $MarginContainer/UICircleZoomInner
@onready var vignette: ColorRect = $Vignette
@onready var fisheye_zoom: ColorRect = $FisheyeZoom

@onready var noclip_message_container: PanelContainer = $MarginContainer3/NoclipMessageContainer
@onready
var noclip_label_message: Label = $MarginContainer3/NoclipMessageContainer/NoclipLabelMessage
@onready var noclip_button: Button = $DebugPanel/VBoxContainer/NoclipButton
@onready var metrics_button: Button = $DebugPanel/VBoxContainer/MetricsButton
@onready var collision_button: Button = $DebugPanel/VBoxContainer/CollisionButton

@onready var debug_panel: Panel = $DebugPanel
@onready var metrics_panel: PanelContainer = $MetricsPanel

@onready var fullbright_button: Button = $DebugPanel/VBoxContainer/FullbrightButton
@onready var wireframe_button: Button = $DebugPanel/VBoxContainer/WireframeButton
@onready var wireframe_overlay_button: Button = $DebugPanel/VBoxContainer/WireframeOverlayButton

@onready var hide_ui_button: Button = $DebugPanel/VBoxContainer/HideUIButton
@onready var margin_container: CenterContainer = $MarginContainer
@onready var margin_container3: MarginContainer = $MarginContainer3


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	debug_panel.hide()

	metrics_button.pressed.connect(_on_metrics_button_pressed)

	# Connect signals
	Events.noclip_toggled.connect(_on_noclip_toggled)
	Events.noclip_speed_changed.connect(_on_noclip_speed_changed)
	Events.player_zoomed.connect(_on_player_zoomed)
	Events.player_crouch_changed.connect(_on_player_crouched)

	debug_panel.hide()
	fullbright_button.pressed.connect(_on_fullbright_button_pressed)

	collision_button.pressed.connect(_on_collision_button_pressed)
	hide_ui_button.pressed.connect(_on_hide_ui_button_pressed)

	# We use custom_minimum_size / 2.0 to guarantee the pivot is dead center!
	ui_circle_zoom.pivot_offset = ui_circle_zoom.custom_minimum_size / 2.0
	ui_circle_zoom.scale = Vector2.ZERO
	ui_circle_zoom.modulate.a = 0.0
	ui_circle_zoom.hide()

	ui_circle_zoom_inner.pivot_offset = ui_circle_zoom_inner.custom_minimum_size / 2.0
	ui_circle_zoom_inner.scale = Vector2.ZERO
	ui_circle_zoom_inner.modulate.a = 0.0
	ui_circle_zoom_inner.hide()

	Events.terminal_mode_toggled.connect(_on_terminal_mode_toggled)

	# Save the original size of your crosshair so we can return to it later
	default_crosshair_size = center_dot.custom_minimum_size
	if default_crosshair_size == Vector2.ZERO:
		default_crosshair_size = center_dot.size  # Fallback just in case

	# BUILD THE HL2 GREEN WIREFRAME SHADER
	green_wireframe_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
    shader_type spatial;
    render_mode wireframe, unshaded, cull_disabled;
    
    void fragment() {
        ALBEDO = vec3(0.0, 1.0, 0.0); // Bright Green!
    }
	"""
	green_wireframe_material.shader = shader


func _process(delta: float) -> void:
	# 0.8 is usually the 'sweet spot' for a heavy vignette.
	# 10.0 might be making the whole screen black or breaking the math!
	var target_vignette_opacity := 0.8 if is_player_crouching else 0.0

	var current_opacity := vignette.material.get_shader_parameter("vignette_opacity") as float
	if current_opacity == null:
		current_opacity = 0.0

	var new_opacity: float = lerp(current_opacity, target_vignette_opacity, delta * ui_lerp_speed)
	vignette.material.set_shader_parameter("vignette_opacity", new_opacity)


# --- ZOOM ANIMATION LOGIC ---
func _on_player_zoomed(is_zooming: bool) -> void:
	if zoom_tween and zoom_tween.is_valid():
		zoom_tween.kill()

	zoom_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)

	if is_zooming:
		# Hide standard crosshair, show zoom circles
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
	print("UI received crouch signal! Crouching: ", crouching)


# --- DEBUG & NOCLIP LOGIC ---


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("console"):
		var is_open := not debug_panel.visible
		debug_panel.visible = is_open
		get_tree().paused = is_open

		if is_open:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		Events.debug_menu_toggled.emit(is_open)


func _on_noclip_button_pressed() -> void:
	Events.noclip_ui_button_pressed.emit()


func _on_noclip_toggled(is_flying: bool) -> void:
	if is_flying:
		noclip_message_container.show()
		noclip_button.text = "Noclip ON"
	else:
		noclip_message_container.hide()
		noclip_button.text = "Noclip OFF"


func _on_noclip_speed_changed(speed: float) -> void:
	noclip_label_message.text = "Noclip ON: %.1fx speed" % speed


func _on_fullbright_button_pressed() -> void:
	is_fullbright = !is_fullbright

	if is_fullbright:
		fullbright_button.text = "Fullbright ON"
	else:
		fullbright_button.text = "Fullbright OFF"

	Events.fullbright_toggled.emit(is_fullbright)


func _on_wireframe_button_pressed() -> void:
	is_wireframe = !is_wireframe

	if is_wireframe:
		wireframe_button.text = "Wireframe ON"
	else:
		wireframe_button.text = "Wireframe OFF"

	Events.wireframe_toggled.emit(is_wireframe)


func _on_wireframe_overlay_button_pressed() -> void:
	is_wireframe_overlay = !is_wireframe_overlay

	if is_wireframe_overlay:
		wireframe_overlay_button.text = "Wireframe Overlay ON"
	else:
		wireframe_overlay_button.text = "Wireframe Overlay OFF"

	Events.wireframe_overlay_toggled.emit(is_wireframe_overlay)

	# NEW: Reach into the 3D scene and apply the shader
	var root_node := get_tree().current_scene
	if root_node:
		_apply_wireframe_to_node(root_node, is_wireframe_overlay)


func _apply_wireframe_to_node(node: Node, is_overlay: bool) -> void:
	# Check for both standard meshes AND CSG geometry
	if node is MeshInstance3D or node is CSGShape3D:
		if is_overlay:
			node.material_overlay = green_wireframe_material
		else:
			node.material_overlay = null

	# Keep digging through all the children
	for child in node.get_children():
		_apply_wireframe_to_node(child, is_overlay)


func _on_metrics_button_pressed() -> void:
	if metrics_panel:
		metrics_panel.toggle_window()


# --- NEW CROSSHAIR ANIMATION ---
func _on_terminal_mode_toggled(is_active: bool) -> void:
	if crosshair_tween and crosshair_tween.is_valid():
		crosshair_tween.kill()

	crosshair_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)

	if is_active:
		# Animate down to 8x8 pixels
		var target_size := Vector2(16, 16)
		crosshair_tween.tween_property(center_dot, "custom_minimum_size", target_size, 0.3)
		crosshair_tween.tween_property(center_dot, "size", target_size, 0.3)

		# Optional: Make it slightly transparent when aiming at the keypad
		# crosshair_tween.tween_property(center_dot, "modulate:a", 0.7, 0.3)
	else:
		# Animate back to the default size
		crosshair_tween.tween_property(
			center_dot, "custom_minimum_size", default_crosshair_size, 0.3
		)
		crosshair_tween.tween_property(center_dot, "size", default_crosshair_size, 0.3)

		# Optional: Restore full opacity
		# crosshair_tween.tween_property(center_dot, "modulate:a", 1.0, 0.3)


# --- COLLISION DEBUG LOGIC ---


func _on_collision_button_pressed() -> void:
	is_collision_visible = !is_collision_visible

	# This is the global flag that tells Godot to draw collision shapes
	get_tree().debug_collisions_hint = is_collision_visible

	# Update button text for clarity
	collision_button.text = "Collisions ON" if is_collision_visible else "Collisions OFF"

	# We "nudge" the scene tree to make sure the debug meshes update immediately
	var root_node := get_tree().current_scene
	if root_node:
		_force_collision_redraw(root_node, is_collision_visible)


func _force_collision_redraw(node: Node, show_collisions: bool) -> void:
	# 1. Force Godot to rebuild the shapes. We must do this for BOTH ON and OFF.
	# Rebuilding the shape while debug_collisions_hint is false is what destroys the lingering debug mesh.
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

	# 2. Update the actual visibility property to fix things like the RayCast blue circles
	if node is CollisionShape3D or node is RayCast3D or node is ShapeCast3D:
		node.visible = show_collisions

	# 3. Recursively check children
	for child in node.get_children():
		_force_collision_redraw(child, show_collisions)


func _on_hide_ui_button_pressed() -> void:
	_toggle_ui_elements(!is_ui_hidden)


func _toggle_ui_elements(should_hide: bool) -> void:
	is_ui_hidden = should_hide

	var visibility: bool = !is_ui_hidden

	# Toggle the main UI containers
	margin_container.visible = visibility
	margin_container3.visible = visibility

	# Toggle the screen effects
	vignette.visible = visibility
	fisheye_zoom.visible = visibility

	hide_ui_button.text = "Show UI" if is_ui_hidden else "Hide UI"

	print("UI Visibility: ", visibility)
