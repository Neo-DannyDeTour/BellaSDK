@tool
extends StaticBody3D

@onready var interact_component: Interact_Component = $Interact_Component
@onready var highlight_component: HighlightComponent = $HighlightComponent
@onready var label_interact: Label3D = $LabelInteract

@export_category("Button References")
# Drag the node you want to physically move down here (e.g., the 'button' Node3D)
@export var pressable_part: Node3D
# Drag the actual mesh you want to glow here (e.g., 'Circle_017')
@export var mesh_to_highlight: MeshInstance3D
@export var outline_material: ShaderMaterial

@export_category("Connections")
@export var targets: Array[Node3D]
@export var click_sound: AudioStreamPlayer3D

var press_tween: Tween
var can_press: bool = true


func _ready() -> void:
	if interact_component and not Engine.is_editor_hint():
		interact_component.focused.connect(_on_focus)
		interact_component.unfocused.connect(_on_unfocus)

		# Make sure this is connected so the button actually works!
		if not interact_component.interacted.is_connected(_on_interact):
			interact_component.interacted.connect(_on_interact)

	label_interact.hide()


func _on_focus() -> void:
	label_interact.show()
	# Apply the material directly to the exact mesh
	if mesh_to_highlight and outline_material:
		mesh_to_highlight.material_overlay = outline_material


func _on_unfocus() -> void:
	label_interact.hide()
	# Remove the material
	if mesh_to_highlight:
		mesh_to_highlight.material_overlay = null


func _on_interact(_player: CharacterBody3D) -> void:
	if not pressable_part or not can_press:
		return

	can_press = false

	if click_sound:
		click_sound.play()
	# ---------------------------

	if highlight_component:
		highlight_component.suppress(true)

	if press_tween and press_tween.is_valid():
		press_tween.kill()

	press_tween = create_tween()

	# Get the current Y position so it always returns to the correct height
	var base_y := pressable_part.position.y

	# Animate it down slightly, then back up to its original base_y
	(
		press_tween
		. tween_property(pressable_part, "position:y", base_y - 0.02, 0.1)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	(
		press_tween
		. tween_property(pressable_part, "position:y", base_y, 0.15)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_IN_OUT)
	)

	for target in targets:
		if target != null and target.has_method("interact"):
			target.interact()

	await get_tree().create_timer(1.0).timeout
	can_press = true

	if highlight_component:
		highlight_component.suppress(false)


# --- EDITOR DEBUG LINE ---

var debug_line: MeshInstance3D


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_draw_connection_line()


func _draw_connection_line() -> void:
	if not targets:
		if debug_line:
			debug_line.queue_free()
		return

	if not debug_line:
		debug_line = MeshInstance3D.new()
		add_child(debug_line)

		var immediate_mesh := ImmediateMesh.new()
		debug_line.mesh = immediate_mesh

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color.RED
		debug_line.material_override = mat

	var mesh := debug_line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	for target in targets:
		if target:
			mesh.surface_add_vertex(Vector3.ZERO)
			mesh.surface_add_vertex(to_local(target.global_position))

	mesh.surface_end()
