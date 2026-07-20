@tool
class_name GroundButton
extends StaticBody3D

## The transmitter node used to relay power signals to connected targets.
@export var transmitter: OutputTransmitter3D:
	set(value):
		transmitter = value
		_sync_targets()

## Target objects to receive power. Exposed here so designers do not need to click into child nodes.
@export var targets: Array[Node3D]:
	set(value):
		targets = value
		_sync_targets()

## The number of valid physics bodies currently pressing down on the button.
var bodies_on_button: int = 0

## Tracks the active state of the button to ensure animations and signals only trigger once per
## press.
var is_pressed: bool = false

## The visual mesh utilized strictly in the editor to draw connection lines.
var debug_line: MeshInstance3D

## The AnimationPlayer responsible for playing the physical button depression and release
## animations.
@onready var anim: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	set_process(Engine.is_editor_hint())

	if not Engine.is_editor_hint():
		var area: Area3D = $Area3D
		if not area.body_entered.is_connected(_on_area_3d_body_entered):
			area.body_entered.connect(_on_area_3d_body_entered)
		if not area.body_exited.is_connected(_on_area_3d_body_exited):
			area.body_exited.connect(_on_area_3d_body_exited)

	_sync_targets()


func _process(_delta: float) -> void:
	_draw_connection_line()


func _sync_targets() -> void:
	if is_instance_valid(transmitter):
		transmitter.targets = targets


func _on_area_3d_body_entered(body: Node3D) -> void:
	if body == self:
		return

	bodies_on_button += 1

	if bodies_on_button == 1 and not is_pressed:
		is_pressed = true
		anim.play("button_down")
		print("GroundButton: Pressed by body! Energizing transmitter.")

		if is_instance_valid(transmitter):
			transmitter.power_on()


func _on_area_3d_body_exited(body: Node3D) -> void:
	if body == self:
		return

	bodies_on_button -= 1
	bodies_on_button = maxi(0, bodies_on_button)

	if bodies_on_button == 0 and is_pressed:
		is_pressed = false
		anim.play_backwards("button_down")
		print("GroundButton: Unpressed! De-energizing transmitter.")

		if is_instance_valid(transmitter):
			transmitter.power_off()


func _draw_connection_line() -> void:
	if not is_instance_valid(transmitter):
		if is_instance_valid(debug_line):
			debug_line.queue_free()
			debug_line = null
		return

	if not is_instance_valid(debug_line):
		debug_line = MeshInstance3D.new()
		add_child(debug_line)

		var immediate_mesh := ImmediateMesh.new()
		debug_line.mesh = immediate_mesh

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color.DEEP_SKY_BLUE
		debug_line.material_override = mat

	var mesh := debug_line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_add_vertex(to_local(transmitter.global_position))

	mesh.surface_end()
