class_name UIController
extends CanvasLayer

var is_fullbright: bool = false
var is_wireframe: bool = false
var is_wireframe_overlay: bool = false
var is_collision_visible: bool = false
var is_ui_hidden: bool = false

var green_wireframe_material: ShaderMaterial

# --- UI VARS ---
var zoom_tween: Tween
var is_player_crouching: bool = false
var ui_lerp_speed: float = 15.0

var crosshair_tween: Tween
var default_crosshair_size: Vector2

# Updated Paths
@onready var crosshair_container: CenterContainer = $CrosshairContainer
@onready var center_dot: TextureRect = $CrosshairContainer/CenterDot
@onready var ui_circle_zoom: TextureRect = $CrosshairContainer/UICircleZoom
@onready var ui_circle_zoom_inner: TextureRect = $CrosshairContainer/UICircleZoomInner

@onready var vignette: ColorRect = $Vignette
@onready var fisheye_zoom: ColorRect = $FisheyeZoom

# Updated Paths
@onready var noclip_alert_container: MarginContainer = $NoclipAlertContainer
@onready var noclip_message_container: PanelContainer = $NoclipAlertContainer/NoclipMessageContainer
@onready var noclip_label_message: Label = $NoclipAlertContainer/NoclipMessageContainer/NoclipLabelMessage

@onready var debug_panel: CanvasLayer = $DebugPanel
@onready var noclip_button: Button = $DebugPanel/PanelContainer/VBoxContainer/NoclipButton
@onready var metrics_button: Button = $DebugPanel/PanelContainer/VBoxContainer/MetricsButton
@onready var collision_button: Button = $DebugPanel/PanelContainer/VBoxContainer/CollisionButton
@onready var fullbright_button: Button = $DebugPanel/PanelContainer/VBoxContainer/FullbrightButton
@onready var wireframe_button: Button = $DebugPanel/PanelContainer/VBoxContainer/WireframeButton
@onready var wireframe_overlay_button: Button = $DebugPanel/PanelContainer/VBoxContainer/WireframeOverlayButton
@onready var hide_ui_button: Button = $DebugPanel/PanelContainer/VBoxContainer/HideUIButton

@onready var metrics_panel: PanelContainer = $MetricsPanel
@onready var frame_graph: ColorRect = $FrameGraph

# --- NEW HEALTH UI VARS ---
@export var hearts_atlas: Texture2D
@onready var health_margin: MarginContainer = $HealthMargin
@onready var hearts_container: HBoxContainer = $HealthMargin/HeartsContainer

# Updated Path
@onready var chapter_title_container: MarginContainer = $ChapterTitleContainer
@onready var chapter_label: RichTextLabel = $ChapterTitleContainer/ChapterLabel

var heart_textures: Array[AtlasTexture] = []
var heart_nodes: Array[TextureRect] = []
var heart_tweens: Array[Tween] = []
var current_health: int = 300

var chapter_tween: Tween


func _ready() -> void:
	print("UI: _ready() called. Initializing canvas elements.")
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
	var shader := Shader.new()
	shader.code = """
    shader_type spatial;
    render_mode wireframe, unshaded, cull_disabled;
    
    void fragment() {
        ALBEDO = vec3(0.0, 1.0, 0.0);
    }
	"""
	green_wireframe_material.shader = shader

	_initialize_hearts()
	
	if not Events.chapter_triggered.is_connected(_on_chapter_triggered):
		Events.chapter_triggered.connect(_on_chapter_triggered)
		
	chapter_label.modulate.a = 0.0
	chapter_label.visible = false
	
	call_deferred("_check_if_testbed")


func _process(delta: float) -> void:
	var target_vignette_opacity := 0.8 if is_player_crouching else 0.0

	var current_opacity := vignette.material.get_shader_parameter("vignette_opacity") as float
	if current_opacity == null:
		current_opacity = 0.0

	var new_opacity: float = lerp(current_opacity, target_vignette_opacity, delta * ui_lerp_speed)
	vignette.material.set_shader_parameter("vignette_opacity", new_opacity)


# --- HEALTH LOGIC ---
func _initialize_hearts() -> void:
	print("UI: _initialize_hearts() called. Setting up health display.")
	if not hearts_atlas:
		push_warning("Hearts atlas not assigned in UI inspector!")
		return

	var atlas_width: float = hearts_atlas.get_width()
	var atlas_height: float = hearts_atlas.get_height()
	var frame_width: float = atlas_width / 5.0

	var target_size: Vector2 = Vector2(frame_width * 2.0, atlas_height * 2.0)

	for i in range(5):
		var tex: AtlasTexture = AtlasTexture.new()
		tex.atlas = hearts_atlas
		tex.region = Rect2(i * frame_width, 0.0, frame_width, atlas_height)
		heart_textures.append(tex)

	for i in range(3):
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

	update_health(current_health)


func update_health(new_health: int) -> void:
	print("UI: update_health() called with new value: ", new_health)
	var health_decreased: bool = new_health < current_health
	var health_increased: bool = new_health > current_health
	var previous_health: int = current_health
	current_health = new_health

	if heart_nodes.is_empty() or heart_textures.is_empty():
		return

	for i in range(heart_nodes.size()):
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


func _animate_heart_damage(index: int) -> void:
	print("UI: _animate_heart_damage() called for heart index: ", index)
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
	print("UI: _animate_heart_heal() called for heart index: ", index)
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
	print("UI: _on_player_zoomed() called. State: ", is_zooming)
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
	print("UI received crouch signal! Crouching: ", crouching)


# --- DEBUG & NOCLIP LOGIC ---
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_QUOTELEFT:
			_toggle_debug_panel()

func _toggle_debug_panel() -> void:
	debug_panel.visible = not debug_panel.visible
	print("UI: Debug panel visibility toggled -> ", debug_panel.visible)
	
	if debug_panel.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_noclip_button_pressed() -> void:
	print("UI: Noclip button pressed.")
	Events.noclip_ui_button_pressed.emit()


func _on_noclip_toggled(is_flying: bool) -> void:
	print("UI: Noclip toggled. State: ", is_flying)
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
	print("UI: Fullbright toggled. State: ", is_fullbright)

	if is_fullbright:
		fullbright_button.text = "Fullbright ON"
	else:
		fullbright_button.text = "Fullbright OFF"

	Events.fullbright_toggled.emit(is_fullbright)


func _on_wireframe_button_pressed() -> void:
	is_wireframe = !is_wireframe
	print("UI: Wireframe toggled. State: ", is_wireframe)

	if is_wireframe:
		wireframe_button.text = "Wireframe ON"
	else:
		wireframe_button.text = "Wireframe OFF"

	Events.wireframe_toggled.emit(is_wireframe)


func _on_wireframe_overlay_button_pressed() -> void:
	is_wireframe_overlay = !is_wireframe_overlay
	print("UI: Wireframe overlay toggled. State: ", is_wireframe_overlay)

	if is_wireframe_overlay:
		wireframe_overlay_button.text = "Wireframe Overlay ON"
	else:
		wireframe_overlay_button.text = "Wireframe Overlay OFF"

	Events.wireframe_overlay_toggled.emit(is_wireframe_overlay)

	var root_node := get_tree().current_scene
	if root_node:
		_apply_wireframe_to_node(root_node, is_wireframe_overlay)


func _apply_wireframe_to_node(node: Node, is_overlay: bool) -> void:
	if node is MeshInstance3D or node is CSGShape3D:
		if is_overlay:
			node.material_overlay = green_wireframe_material
		else:
			node.material_overlay = null

	for child in node.get_children():
		_apply_wireframe_to_node(child, is_overlay)


func _on_metrics_button_pressed() -> void:
	print("UI: Metrics button pressed.")
	if metrics_panel:
		metrics_panel.toggle_window()
		
		if frame_graph:
			frame_graph.visible = metrics_panel.visible


# --- NEW CROSSHAIR ANIMATION ---
func _on_terminal_mode_toggled(is_active: bool) -> void:
	print("UI: Terminal mode toggled to ", is_active, ". Animating crosshair.")
	
	if crosshair_tween and crosshair_tween.is_valid():
		crosshair_tween.kill()

	crosshair_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)

	if is_active:
		var target_size := Vector2(16.0, 16.0)
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
	print("UI: Collision visibility toggled. State: ", is_collision_visible)

	get_tree().debug_collisions_hint = is_collision_visible
	collision_button.text = "Collisions ON" if is_collision_visible else "Collisions OFF"

	var root_node := get_tree().current_scene
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

	for child in node.get_children():
		_force_collision_redraw(child, show_collisions)


func _on_hide_ui_button_pressed() -> void:
	print("UI: Hide UI button pressed.")
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
	print("UI Visibility: ", visibility)


# --- CHAPTER TITLE LOGIC ---
func _on_chapter_triggered(chapter_name: String, anim_style: int, display_duration: float, text_color: Color) -> void:
	print("UI received chapter_triggered signal. Displaying: ", chapter_name, " in color: ", text_color)
	
	chapter_label.add_theme_color_override("default_color", text_color)
	chapter_label.visible = true

	if chapter_tween and chapter_tween.is_valid():
		chapter_tween.kill()

	chapter_tween = create_tween()

	match anim_style:
		Events.ChapterAnimStyle.SIMPLE:
			print("UI animating chapter using SIMPLE style.")
			chapter_label.text = "[center]" + chapter_name + "[/center]"
			chapter_label.visible_ratio = 1.0
			chapter_tween.tween_property(chapter_label, "modulate:a", 1.0, 1.0)
			chapter_tween.tween_interval(display_duration)
			chapter_tween.tween_property(chapter_label, "modulate:a", 0.0, 1.0)

		Events.ChapterAnimStyle.TYPEWRITER:
			print("UI animating chapter using TYPEWRITER style.")
			chapter_label.modulate.a = 1.0
			chapter_label.text = "[center]" + chapter_name + "[/center]"
			chapter_label.visible_ratio = 0.0
			
			var time_per_char: float = 0.05
			var total_time: float = chapter_name.length() * time_per_char
			
			chapter_tween.tween_property(chapter_label, "visible_ratio", 1.0, total_time)
			chapter_tween.tween_interval(display_duration)
			chapter_tween.tween_property(chapter_label, "modulate:a", 0.0, 1.0)

		Events.ChapterAnimStyle.WAVE:
			print("UI animating chapter using WAVE style.")
			var wave_tag: String = "[wave amp=50.0 freq=5.0 connected=1]"
			chapter_label.text = "[center]" + wave_tag + chapter_name + "[/wave][/center]"
			chapter_label.visible_ratio = 1.0
			chapter_tween.tween_property(chapter_label, "modulate:a", 1.0, 1.0)
			chapter_tween.tween_interval(display_duration)
			chapter_tween.tween_property(chapter_label, "modulate:a", 0.0, 1.0)

	chapter_tween.tween_callback(chapter_label.hide)


func _check_if_testbed() -> void:
	print("UI: Checking if current scene is TestbedMap...")
	var current_scene: Node = get_tree().current_scene
	
	if current_scene and "testbed.scn" in current_scene.scene_file_path.to_lower():
		_open_metrics_panel()


func _open_metrics_panel() -> void:
	print("UI: TestbedMap detected. Opening metrics panel automatically.")
	
	if metrics_panel and not metrics_panel.visible:
		metrics_panel.toggle_window()
		
		if frame_graph:
			frame_graph.visible = metrics_panel.visible
