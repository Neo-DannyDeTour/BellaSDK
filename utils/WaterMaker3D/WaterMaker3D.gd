@tool
extends MeshInstance3D # Or CSGMesh3D depending on what you chose in Step 1

@export var water_color := Color(0.31, 0.54, 0.87, 0.38)
@export var fog_color := Color(0, 0.04, 0.16)
@export_range(0.0, 250.0) var fog_fade_dist := 5.0

# Add these to match the shader
@export var wave_amplitude := 0.2
@export var wave_frequency := 2.0
@export var wave_speed := 1.0

@export var splash_sound: AudioStream
@export var min_splash_velocity := 5.0

var floating_bodies: Array[RigidBody3D] = []
var can_splash := true

static var last_frame_drew_underwater_effect : int = -999

func _ready() -> void:
	self.process_priority = 999 
	
	# Connect the Area3D signals so we know when an object splashes in
	if get_node_or_null("%SwimmableArea3D"):
		%SwimmableArea3D.body_entered.connect(_on_swimmable_area_body_entered)
		%SwimmableArea3D.body_exited.connect(_on_swimmable_area_body_exited)
	
	# NEW: Wait for 1 second after the scene loads, then allow splashes
	await get_tree().create_timer(1.0).timeout
	can_splash = true
# --- THE UPDATE LOOP ---

#func _physics_process(_delta: float) -> void:
	## Continuously update the water height for all objects currently in the pool
	#for i in range(floating_bodies.size() - 1, -1, -1):
		#var body := floating_bodies[i]
		#
		## Safety check in case the object was destroyed/freed while in the water
		#if is_instance_valid(body):
			#if body.is_in_water:
				#body.current_water_height = get_wave_height_at_pos(body.global_position)
		#else:
			#floating_bodies.remove_at(i)
			
# NEW FUNCTION: Replicates the shader math to find the exact surface height at the camera's position
func get_wave_height_at_pos(global_pos: Vector3) -> float:
	var local_pos := to_local(global_pos)
	
	# Time must match the shader's TIME variable perfectly
	var time := (Time.get_ticks_msec() / 1000.0) * wave_speed
	
	# 1:1 replica of the vertex shader math to find the exact wave crest/trough
	var h1: float = sin(local_pos.x * wave_frequency + time) * wave_amplitude
	var h2: float = sin((local_pos.x * 0.8 + local_pos.z * 0.6) * (wave_frequency * 1.5) - time * 1.2) * (wave_amplitude * 0.6)
	var h3: float = cos((local_pos.z * 1.2 - local_pos.x * 0.3) * (wave_frequency * 0.8) + time * 0.7) * (wave_amplitude * 0.4)
	
	# Calculate the flat surface height + the chaotic wave math
	# Note: Assumes your MeshInstance3D is using a BoxMesh. 
	var local_surface_y: float = (mesh.size.y / 2.0) + h1 + h2 + h3 
	
	var surface_global_pos := to_global(Vector3(local_pos.x, local_surface_y, local_pos.z))
	return surface_global_pos.y

func should_draw_camera_underwater_effect() -> bool: 
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport else null
	
	if not camera: return false
	if last_frame_drew_underwater_effect == Engine.get_process_frames(): return false
	
	%CameraPosShapeCast3D.global_position = camera.global_position
	%CameraPosShapeCast3D.force_shapecast_update()
	
	var in_swimmable_area := false
	for i: int in range(%CameraPosShapeCast3D.get_collision_count()):
		if %CameraPosShapeCast3D.get_collider(i) == %SwimmableArea3D:
			in_swimmable_area = true
			break
			
	# If we are inside the rough bounds of the Area3D, do the precise wave check
	if in_swimmable_area:
		# Check if the camera's Y is BELOW the mathematical wave height at that exact spot
		if camera.global_position.y < get_wave_height_at_pos(camera.global_position):
			return true
			
	return false

func _process(_delta: float) -> void:
	# Update shader parameters dynamically so editor sliders work
	if self.material_override is ShaderMaterial: # Using material_override is usually safer for MeshInstances
		var mat := self.material_override as ShaderMaterial
		mat.set_shader_parameter("albedo", water_color)
		mat.set_shader_parameter("wave_amplitude", wave_amplitude)
		mat.set_shader_parameter("wave_frequency", wave_frequency)
		mat.set_shader_parameter("wave_speed", wave_speed)

	# Keep your fog logic...
	%FogVolume.material.set_shader_parameter("albedo", fog_color)
	%FogVolume.material.set_shader_parameter("emission", fog_color)
	%FogVolume.fade_distance = self.fog_fade_dist
	
	if not Engine.is_editor_hint():
		var is_underwater := should_draw_camera_underwater_effect()

		if is_underwater:
			%WaterRippleOverlay.visible = true
			%FogVolume.material.set_shader_parameter("edge_fade", 0.1)
			last_frame_drew_underwater_effect = Engine.get_process_frames()
			
			# --- AUDIO TRICK: Pause the surface sound when underwater ---
			if %SurfaceAudio.playing:
				%SurfaceAudio.stream_paused = true
		else:
			%WaterRippleOverlay.visible = false
			%FogVolume.material.set_shader_parameter("edge_fade", 1.1)
			
			# --- AUDIO TRICK: Resume the surface sound when above water ---
			%SurfaceAudio.stream_paused = false
			if not %SurfaceAudio.playing:
				%SurfaceAudio.play()

# --- PHYSICS & BUOYANCY SIGNALS ---

func _on_swimmable_area_body_entered(body: Node3D) -> void:
	# 1. Your existing buoyancy logic
	if body is PickableObject:
		if not floating_bodies.has(body):
			floating_bodies.append(body)
			body.is_in_water = true
			body.current_water_node = self 

	# 2. NEW: Velocity and Splash Logic
	var impact_speed := 0.0
	
	# Safely get the velocity depending on what kind of body jumped in
	if body is RigidBody3D:
		impact_speed = body.linear_velocity.length()
	elif body is CharacterBody3D: # Usually the Player
		impact_speed = body.velocity.length()
		
	# If they hit the water fast enough, trigger the sound!
	if impact_speed >= min_splash_velocity:
		play_splash_sound(body.global_position, impact_speed)

func play_splash_sound(impact_pos: Vector3, speed: float) -> void:
	if not can_splash or not splash_sound:
		return
		
	var audio_player := AudioStreamPlayer3D.new()
	audio_player.stream = splash_sound
	
	# NEW: Use speed to change the volume! 
	# (Assuming a speed of 10.0 is a "normal" hard hit)
	# clampf ensures the volume multiplier doesn't drop to 0 or go crazy high
	var volume_multiplier := clampf(speed / 10.0, 0.2, 1.5)
	
	# Convert linear multiplier to Decibels (Godot uses decibels for volume)
	audio_player.volume_db = linear_to_db(volume_multiplier)
	
	# Alternatively, tweak the pitch based on speed:
	# audio_player.pitch_scale = clampf(speed / 10.0, 0.8, 1.2)
	
	audio_player.max_distance = 10.0 
	audio_player.unit_size = 1.0     
	
	add_child(audio_player)
	
	var surface_y := get_wave_height_at_pos(impact_pos)
	audio_player.global_position = Vector3(impact_pos.x, surface_y, impact_pos.z)
	
	audio_player.finished.connect(audio_player.queue_free)
	audio_player.play()

func _on_swimmable_area_body_exited(body: Node3D) -> void:
	# THE FIX: Only check the array if the body is actually a PickableObject
	if body is PickableObject:
		if floating_bodies.has(body):
			floating_bodies.erase(body)
			body.is_in_water = false 
			body.current_water_node = null
