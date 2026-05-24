@tool
extends StaticBody3D
@export var targets: Array[Node3D]

var bodies_on_button: int = 0
var is_pressed: bool = false

@onready var anim: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	# We only want physics logic in the actual game, not the editor
	if not Engine.is_editor_hint():
		var area := $Area3D
		if not area.body_entered.is_connected(_on_area_3d_body_entered):
			area.body_entered.connect(_on_area_3d_body_entered)
		if not area.body_exited.is_connected(_on_area_3d_body_exited):
			area.body_exited.connect(_on_area_3d_body_exited)


# --- PHYSICS LOGIC ---
func _on_area_3d_body_entered(body: Node3D) -> void:
	if body == self:
		return

	bodies_on_button += 1

	if bodies_on_button == 1 and not is_pressed:
		is_pressed = true
		anim.play("button_down")
		print("Ground Button Pressed!")

		# --- SMART POWER SENDER ---
		for target in targets:
			if target == null:
				continue

			# 1. Did they target the component directly?
			if target.has_method("add_power"):
				target.add_power()
			# 2. Did they target the parent node? Look for the component!
			else:
				var comp := target.get_node_or_null("PowerComponent")
				if comp and comp.has_method("add_power"):
					comp.add_power()


func _on_area_3d_body_exited(body: Node3D) -> void:
	if body == self:
		return

	bodies_on_button -= 1
	bodies_on_button = max(0, bodies_on_button)

	if bodies_on_button == 0 and is_pressed:
		is_pressed = false
		anim.play_backwards("button_down")
		print("Ground Button Unpressed!")

		# --- SMART POWER REMOVER ---
		for target in targets:
			if target == null:
				continue

			if target.has_method("remove_power"):
				target.remove_power()
			else:
				var comp := target.get_node_or_null("PowerComponent")
				if comp and comp.has_method("remove_power"):
					comp.remove_power()


# --- EDITOR DEBUG LINE ---
var debug_line: MeshInstance3D


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_draw_connection_line()


func _draw_connection_line() -> void:
	if targets.is_empty():
		if debug_line:
			debug_line.queue_free()
			debug_line = null
		return

	if not debug_line or not is_instance_valid(debug_line):
		debug_line = MeshInstance3D.new()
		add_child(debug_line)
		var immediate_mesh := ImmediateMesh.new()
		debug_line.mesh = immediate_mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color.DEEP_SKY_BLUE  # Portal button line color!
		debug_line.material_override = mat

	var mesh := debug_line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	for target in targets:
		if target != null and is_instance_valid(target):
			mesh.surface_add_vertex(Vector3.ZERO)
			mesh.surface_add_vertex(to_local(target.global_position))

	mesh.surface_end()
