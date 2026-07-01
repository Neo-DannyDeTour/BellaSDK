class_name FlyingTile extends Area3D

enum State { IDLE, RISING, SPINNING, ATTACKING }

@export_group("Tile Settings")
@export var damage: int = 1
@export var rise_height: float = 2.0
@export var rise_speed: float = 4.0
@export var spin_duration: float = 0.8
@export var attack_speed: float = 18.0
@export var lifetime_after_attack: float = 1.5

var _current_state: State = State.IDLE
var _start_y: float = 0.0
var _spin_timer: float = 0.0
var _attack_timer: float = 0.0
var _attack_direction: Vector3 = Vector3.ZERO
var _target_player: Node3D = null

@onready var _activation_area: Area3D = $ActivationArea
@onready var _mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	_start_y = global_position.y
	
	# Connect signals via code for safety and clean inspector
	_activation_area.body_entered.connect(_on_activation_area_body_entered)
	body_entered.connect(_on_body_entered)
	
	print("Flying tile initialized and waiting for player.")

func _physics_process(delta: float) -> void:
	match _current_state:
		State.IDLE:
			pass
			
		State.RISING:
			# Move up smoothly to target height
			global_position.y = move_toward(global_position.y, _start_y + rise_height, rise_speed * delta)
			
			if global_position.y >= _start_y + rise_height:
				_current_state = State.SPINNING
				print("Tile reached target height. Starting to spin.")
				
		State.SPINNING:
			# Visual spin effect before attacking
			_mesh.rotate_y(25.0 * delta)
			_mesh.rotate_x(5.0 * delta) # Slight wobble for a "magic" look
			
			_spin_timer += delta
			if _spin_timer >= spin_duration:
				_start_attack()
				
		State.ATTACKING:
			# Continue spinning rapidly while flying
			_mesh.rotate_y(40.0 * delta)
			
			# Move quickly in the locked direction
			global_position += _attack_direction * attack_speed * delta
			
			# Destroy if it flies too far without hitting anything
			_attack_timer += delta
			if _attack_timer >= lifetime_after_attack:
				_destroy_tile("Missed player and flew its maximum distance.")

func _on_activation_area_body_entered(body: Node3D) -> void:
	if _current_state == State.IDLE and body.is_in_group("player"):
		_target_player = body
		_current_state = State.RISING
		print("Player entered activation sphere. Tile rising.")

func _start_attack() -> void:
	_current_state = State.ATTACKING
	
	if is_instance_valid(_target_player):
		var target_pos: Vector3 = _target_player.global_position
		# Aim slightly higher so the tile targets the torso, not the feet origin
		target_pos.y += 1.0 
		_attack_direction = global_position.direction_to(target_pos)
	else:
		# Fallback just in case the player was freed from the tree
		_attack_direction = Vector3.FORWARD
		
	print("Tile attacking towards player!")

func _on_body_entered(body: Node3D) -> void:
	# We only care about collisions when the tile is actually flying
	if _current_state != State.ATTACKING:
		return
		
	if body.is_in_group("player"):
		print("Tile hit player! Dealing damage: ", damage)
		if body.has_method("take_damage"):
			body.take_damage(damage)
		_destroy_tile("Succeeded in hitting player.")
	else:
		# If it hits a wall, pillar, or static floor
		print("Tile hit the environment.")
		_destroy_tile("Collided with a wall or object.")

func _destroy_tile(reason: String) -> void:
	print("Tile destroyed. Reason: ", reason)
	queue_free()
