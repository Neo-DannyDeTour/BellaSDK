@tool
extends Node3D

@export_group("Generation Trigger")
@export var generate_basalt: bool = false :
	set(value):
		if value:
			_generate()
		generate_basalt = false

@export_group("Field Properties")
@export var field_width: float = 20.0 :
	set(value):
		field_width = value
		_queue_generation()
@export var field_depth: float = 20.0 :
	set(value):
		field_depth = value
		_queue_generation()
@export var amount: int = 100 :
	set(value):
		amount = value
		_queue_generation()

@export_group("Basalt Properties")

# Your original sides variable
@export var sides: int = 6 : 
	set(value):
		sides = value
		_queue_generation()

# The new surface group variable
@export var surface_group: String = "stone" :
	set(value):
		surface_group = value
		_queue_generation()

# Ensure you have ": int = 0" right here!
@export var rings: int = 0 : 
	set(value):
		rings = int(value) if value != null else 0
		_queue_generation()

@export var column_radius: float = 1.0 :
	set(value):
		column_radius = value
		_queue_generation()
@export var base_height: float = 2.0 :
	set(value):
		base_height = value
		_queue_generation()
@export var chaos: float = 0.5 :
	set(value):
		chaos = value
		_queue_generation()
@export var min_spacing: float = 1.8 :
	set(value):
		min_spacing = value
		_queue_generation()

# Group to store generated columns so we can clear them easily
var generated_group_name: String = "generated_basalt"

# --- DEBOUNCE TIMER VARIABLES ---
var _needs_generation: bool = false
var _last_edit_time: int = 0
var _debounce_delay_ms: int = 1000 # 1 second (1000 milliseconds)

func _process(_delta: float) -> void:
	# This runs constantly in the editor. 
	# If generation is queued, it checks if 1 second has passed since your last edit.
	if Engine.is_editor_hint() and _needs_generation:
		if Time.get_ticks_msec() - _last_edit_time > _debounce_delay_ms:
			_needs_generation = false
			_generate()

func _queue_generation() -> void:
	# Every time you change a variable, this resets the 1-second timer
	if Engine.is_editor_hint() and is_node_ready():
		_needs_generation = true
		_last_edit_time = Time.get_ticks_msec()

func _generate() -> void:
	# 1. Clear previous generation
	for child: Node in get_children():
		# Check the group, AND check the name just in case the group was lost
		if child.is_in_group(generated_group_name) or child.name.begins_with("BasaltColumn_"):
			child.queue_free()
			
	# Wait a frame for cleanup (important in tool scripts)
	await get_tree().process_frame 
	
	# Duck Typing. Find magnets by checking for properties instead of class names
	var magnets: Array[Node] = []
	for child: Node in get_children():
		if "push_force" in child and "effect_radius" in child:
			magnets.append(child)

	# Keep track of where we've already put columns to prevent overlap
	var placed_positions: Array[Vector2] = []

	# 2. Generate new columns
	for i: int in range(amount):
		var valid_position: bool = false
		var col_position: Vector3 = Vector3.ZERO
		
		# Try to find an empty spot up to 50 times. 
		var attempts: int = 0
		var max_attempts: int = 50
		
		while not valid_position and attempts < max_attempts:
			attempts += 1
			
			# Pick a random spot inside the Inspector width/depth
			var x_pos: float = randf_range(-field_width / 2.0, field_width / 2.0)
			var z_pos: float = randf_range(-field_depth / 2.0, field_depth / 2.0)
			
			# Apply Chaos (positional jitter)
			x_pos += randf_range(-chaos, chaos)
			z_pos += randf_range(-chaos, chaos)
			
			# --- STRICT BOUNDARY CLAMPING ---
			# Calculate the maximum allowed distance from the center, 
			# subtracting the radius so the geometry doesn't bleed over the edge.
			var max_x: float = max(0.0, (field_width / 2.0) - column_radius)
			var max_z: float = max(0.0, (field_depth / 2.0) - column_radius)
			
			# Force the positions back inside the box if chaos pushed them out
			x_pos = clampf(x_pos, -max_x, max_x)
			z_pos = clampf(z_pos, -max_z, max_z)
			
			var test_pos: Vector2 = Vector2(x_pos, z_pos)
			var is_far_enough: bool = true
			
			# Check distance against all previously placed columns
			for placed: Vector2 in placed_positions:
				if test_pos.distance_to(placed) < min_spacing:
					is_far_enough = false
					break 
					
			if is_far_enough:
				valid_position = true
				col_position = Vector3(test_pos.x, 0.0, test_pos.y)
				placed_positions.append(test_pos)
		
		# If it couldn't find a spot after 50 tries, skip this column entirely
		if not valid_position:
			continue

		# --- PROCEED WITH GENERATION ---
		var column: MeshInstance3D = MeshInstance3D.new()
		var mesh: CylinderMesh = CylinderMesh.new()
		
		# Define sides and shape
		mesh.radial_segments = max(4, sides) 
		
		# Force it to be an integer to prevent the 'Nil' error on startup
		mesh.rings = int(rings) 
		
		mesh.bottom_radius = column_radius
		mesh.top_radius = column_radius
		
		# Start with base height
		var final_height: float = base_height
		
		# Convert the column's local position to global space for accurate math
		var col_global_pos: Vector3 = to_global(col_position)
		
		# 6. Apply Magnets
		for magnet: Node in magnets:
			var dist: float = Vector2(col_global_pos.x, col_global_pos.z).distance_to(Vector2(magnet.global_position.x, magnet.global_position.z))
			
			if dist < magnet.effect_radius:
				var influence: float = 1.0 - (dist / magnet.effect_radius)
				influence = smoothstep(0.0, 1.0, influence) 
				final_height += magnet.push_force * influence
		
		mesh.height = max(0.1, final_height) # Prevent negative heights
		column.mesh = mesh
		
		# Set final position (offset Y so bottom is at 0)
		column.position = Vector3(col_position.x, mesh.height / 2.0, col_position.z)
		
		# Apply Chaos (rotational jitter)
		column.rotation.y = randf_range(-chaos, chaos)
		column.rotation.x = randf_range(-chaos * 0.2, chaos * 0.2)
		column.rotation.z = randf_range(-chaos * 0.2, chaos * 0.2)
		
		# Add flat shading for that Deus Ex look
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX 
		column.set_surface_override_material(0, material)
		
		# 7. Add to scene and allow individual editing
		column.add_to_group(generated_group_name, true)
		column.name = "BasaltColumn_" + str(i)
		add_child(column)
		
		# --- ADD COLLISION ---
		var static_body: StaticBody3D = StaticBody3D.new()
		var collision_shape: CollisionShape3D = CollisionShape3D.new()
		
		# --> ADD THIS BLOCK <--
		# Assign the physics body to the chosen footstep group (e.g. "stone")
		if surface_group != "":
			static_body.add_to_group(surface_group, true)
		
		collision_shape.shape = mesh.create_convex_shape()
		
		static_body.add_child(collision_shape)
		column.add_child(static_body)
		
		if Engine.is_editor_hint():
			var root: Node = get_tree().edited_scene_root
			column.owner = root
			static_body.owner = root
			collision_shape.owner = root
