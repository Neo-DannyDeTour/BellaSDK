class_name PhysExplosion3D
extends RigidBody3D

@export_category("Explosion Dynamics")
@export var explosion_force: float = 50.0
@export var explosion_radius: float = 5.0
@export var self_kick_multiplier: float = 0.5

@export_category("Random Timer")
@export var min_fuse_time: float = 1.0
@export var max_fuse_time: float = 4.0

@onready var blast_area: Area3D = $BlastArea
@onready var blast_shape: CollisionShape3D = $BlastArea/CollisionShape3D
@onready var burst_sparks: GPUParticles3D = $BurstSparks

# Grab the internal editor icon directly using Scene Unique Nodes
@onready var _editor_icon: Node3D = get_node_or_null("%EditorIcon")

var _fuse_timer: float = 0.0


func _ready() -> void:
	# Purge the editor icon immediately at runtime (Zero overhead!)
	if not Engine.is_editor_hint():
		if is_instance_valid(_editor_icon):
			_editor_icon.queue_free()

	if blast_shape.shape is SphereShape3D:
		blast_shape.shape = blast_shape.shape.duplicate()
		blast_shape.shape.radius = explosion_radius
		
	_reset_fuse()


func _physics_process(delta: float) -> void:
	_fuse_timer -= delta
	
	if _fuse_timer <= 0.0:
		_detonate()
		_reset_fuse()


func _reset_fuse() -> void:
	_fuse_timer = randf_range(min_fuse_time, max_fuse_time)


func _detonate() -> void:
	# Trigger the heavy burst of sparks
	burst_sparks.restart()
	
	var bodies: Array[Node3D] = blast_area.get_overlapping_bodies()
	var center: Vector3 = global_position
	
	for body: Node3D in bodies:
		if body is RigidBody3D and body != self:
			if body.get_parent() is PhysicsCable3D:
				continue
				
			body.sleeping = false 
			
			var dir: Vector3 = center.direction_to(body.global_position)
			var dist: float = center.distance_to(body.global_position)
			
			if dist < 0.01:
				dir = Vector3.UP
				dist = 0.1
				
			var falloff: float = maxf(0.0, 1.0 - (dist / explosion_radius))
			var impulse: Vector3 = dir * explosion_force * falloff * body.mass
			
			body.apply_impulse(impulse, Vector3(0.0, 0.1, 0.0))
			
	var random_kick: Vector3 = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(0.5, 1.5),
		randf_range(-1.0, 1.0)
	).normalized()
	
	var final_kick: Vector3 = random_kick * explosion_force * self_kick_multiplier * mass
	apply_central_impulse(final_kick)
