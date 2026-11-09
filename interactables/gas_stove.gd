# class_name GasStove
extends RigidBody3D

## Low-poly Half-Life 2 style gas stove physics prop ([RigidBody3D]).
## Uses pre-baked GLB mesh and overrides material with procedural [ShaderMaterial].

## Emitted when the stove takes a hard physics impact.
@warning_ignore("unused_signal")
signal stove_impacted(impulse_sq: float)

## Bounding dimensions in meters matching HL2 stove proportions.
const STOVE_SIZE: Vector3 = Vector3(0.85, 0.78, 0.55)
## Default mass in kilograms.
const STOVE_MASS: float = 45.0
## Shader uniform [StringName] cache for grime parameter.
const PARAM_GRIME: StringName = &"grime_amount"
## Preloaded procedural stove shader.
const STOVE_SHADER: Shader = preload("res://shaders/props/gas_stove.gdshader")

## Instance grime override (0.0 clean to 1.0 heavy rust).
@export_range(0.0, 1.0, 0.05) var grime_amount: float = 0.65:
	set(value):
		grime_amount = value
		if is_instance_valid(_mesh_instance) and is_inside_tree():
			_mesh_instance.set_instance_shader_parameter(PARAM_GRIME, grime_amount)

## Cached reference to child [MeshInstance3D].
var _mesh_instance: MeshInstance3D = null
## Cached reference to child [CollisionShape3D].
var _collision_shape: CollisionShape3D = null

## Cached reference to imported GLB container [Node3D].
@onready var _stove_model: Node3D = get_node_or_null(^"gas_stove") as Node3D


## Initializes collision layers, material override, and collision; disables per-frame ticks.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	mass = STOVE_MASS
	collision_layer = CollisionLayers.MASK_DEBRIS
	collision_mask = (
		CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_PLAYER | CollisionLayers.MASK_DEBRIS
	)
	can_sleep = true

	_setup_mesh_and_material()
	_setup_collision()

	assert(is_instance_valid(_mesh_instance), "GasStove: _mesh_instance failed to initialize.")
	assert(is_instance_valid(_collision_shape), "GasStove: _collision_shape failed to initialize.")
	print("GasStove: Initialized low-poly stove prop (45 kg, Layer 4 Debris).")


## Locates child [MeshInstance3D] and configures procedural [ShaderMaterial] and render layers.
func _setup_mesh_and_material() -> void:
	if is_instance_valid(_stove_model):
		var found_mesh: Node = NodeQuery.find_first_child_of_type(_stove_model, MeshInstance3D)
		_mesh_instance = found_mesh as MeshInstance3D
	else:
		var root_found: Node = NodeQuery.find_first_child_of_type(self, MeshInstance3D)
		_mesh_instance = root_found as MeshInstance3D

	if is_instance_valid(_mesh_instance):
		_mesh_instance.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = STOVE_SHADER
		_mesh_instance.material_override = mat
		_mesh_instance.set_instance_shader_parameter(PARAM_GRIME, grime_amount)


## Locates or creates the bounding [BoxShape3D] collider for physics simulation.
func _setup_collision() -> void:
	var found_shape: Node = NodeQuery.find_first_child_of_type(self, CollisionShape3D)
	_collision_shape = found_shape as CollisionShape3D

	if not is_instance_valid(_collision_shape):
		var box: BoxShape3D = BoxShape3D.new()
		box.size = STOVE_SIZE
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = &"StoveCollision"
		_collision_shape.shape = box
		add_child(_collision_shape)
	elif _collision_shape.shape == null:
		var new_box: BoxShape3D = BoxShape3D.new()
		new_box.size = STOVE_SIZE
		_collision_shape.shape = new_box
