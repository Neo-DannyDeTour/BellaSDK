@tool
extends Node3D
class_name LightningManager

## --- REQUIRED ASSIGNMENTS ---

@export var source_marker: Node3D
@export var receiver_markers: Array[Node3D]
@export var lightning_material: ShaderMaterial

## --- STRIKE CONTROL ---

@export var strike_enabled: bool = false:
	set(value):
		strike_enabled = value
		if is_node_ready():
			if value:
				strike()
			else:
				stop_strike()

@export var speed: float = 1.0
@export var flicker_rate: float = 0.05
@export var subdivisions: int = 20

@export_group("Variation Ranges")
@export var arc_height_base: float = 2.0
@export var arc_height_variance: float = 1.0
@export var jitter_base: float = 0.3
@export var jitter_variance: float = 0.2

var is_striking: bool = false
var _immediate_mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D
var _flicker_timer: float = 0.0
var _current_arc_height: float = 0.0
var _current_jitter: float = 0.0

func _ready() -> void:
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh
	
	if lightning_material != null:
		_mesh_instance.material_override = lightning_material
		
	add_child(_mesh_instance)
	
	if strike_enabled:
		strike()

func _process(delta: float) -> void:
	if not is_striking:
		return
		
	# In the editor, Engine.is_editor_hint() can be used if you want to throttle things,
	# but for visual effects testing, running normally is fine.
	_flicker_timer += delta * speed
	
	if _flicker_timer >= flicker_rate:
		_flicker_timer = 0.0
		_randomize_parameters()
		_draw_lightning()

func strike() -> void:
	print("LightningManager: strike() called. Initiating lightning emission.")
	is_striking = true
	_flicker_timer = flicker_rate 
	
	if _mesh_instance != null:
		_mesh_instance.visible = true

func stop_strike() -> void:
	print("LightningManager: stop_strike() called. Halting lightning emission.")
	is_striking = false
	
	if _immediate_mesh != null:
		_immediate_mesh.clear_surfaces()
		
	if _mesh_instance != null:
		_mesh_instance.visible = false

func _randomize_parameters() -> void:
	_current_arc_height = arc_height_base + randf_range(-arc_height_variance, arc_height_variance)
	_current_jitter = jitter_base + randf_range(-jitter_variance, jitter_variance)

func _draw_lightning() -> void:
	_immediate_mesh.clear_surfaces()
	
	if source_marker == null or receiver_markers.is_empty():
		return
		
	# FIX: Convert the global position to local space to avoid double-transforms
	var start_pos: Vector3 = to_local(source_marker.global_position)
	
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	for receiver: Node3D in receiver_markers:
		if receiver == null:
			continue
			
		# FIX: Convert receiver global position to local space
		var end_pos: Vector3 = to_local(receiver.global_position)
		var current_pos: Vector3 = start_pos
		
		for i: int in range(1, subdivisions + 1):
			var t: float = float(i) / float(subdivisions)
			
			var target_pos: Vector3 = start_pos.lerp(end_pos, t)
			
			var arc_factor: float = sin(t * PI)
			target_pos.y += arc_factor * _current_arc_height
			
			if i < subdivisions:
				target_pos.x += randf_range(-_current_jitter, _current_jitter)
				target_pos.y += randf_range(-_current_jitter, _current_jitter)
				target_pos.z += randf_range(-_current_jitter, _current_jitter)
				
			_immediate_mesh.surface_add_vertex(current_pos)
			_immediate_mesh.surface_add_vertex(target_pos)
			
			current_pos = target_pos
			
	_immediate_mesh.surface_end()
