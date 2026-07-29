extends StaticBody3D
class_name TentacleEnemy

## Defines the current operational behavior of the enemy.
enum State { IDLE, PLAYING, HOLDING, SPOTTED, ATTACKING }

## The current behavior state of the tentacle.
var current_state: State = State.IDLE

## The delay in seconds before the enemy strikes after spotting the player.
@export var charge_delay: float = 2.0

## The probability (0.0 to 1.0) that the enemy will grab an object and throw it during combat.
@export_range(0.0, 1.0) var throw_attack_chance: float = 0.4

## The force applied when throwing a pickable object at the player.
@export var throw_force: float = 15.0

## The amount of damage dealt by a direct tentacle strike.
@export var strike_damage: int = 15

## The speed at which the tentacle's head tracks its targets.
@export var track_speed: float = 5.0

## The maximum reach of the tentacle for idle wandering and striking.
@export var max_reach: float = 8.0

## How often (in seconds) the tentacle taps or decides to grab the toy while playing.
@export var interact_interval: float = 1.5

## How long (in seconds) the tentacle will hold the object before placing it down.
@export var hold_duration: float = 1.5

@onready var detection_area: Area3D = $DetectionArea
@onready var health_component: HealthComponent = $HealthComponent

## The Marker3D representing the "head" of the snake/tentacle.
@onready var tentacle_target: Marker3D = $TentacleTarget

## The player node currently inside the detection area.
var target_player: Node3D = null

## The toy the tentacle is currently tapping or watching.
var target_toy: RigidBody3D = null

## The pickable object currently physically held by the tentacle.
var held_object: RigidBody3D = null

## The accumulated time spent in the idle state, used for sway animation math.
var _idle_time: float = 0.0

## The accumulated time tracking the delay before launching an attack.
var _charge_timer: float = 0.0

## The accumulated time tracking when the next play interaction should occur.
var _interact_timer: float = 0.0

## The accumulated time tracking how long an object has been held.
var _hold_timer: float = 0.0

## The calculated 3D world coordinate where the tentacle intends to drop the toy.
var _place_target: Vector3 = Vector3.ZERO

## A boolean flag indicating whether an attack or throw animation is actively playing.
var _is_striking: bool = false


func _ready() -> void:
	print("TentacleEnemy: _ready() - Initializing snake-like enemy.")
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	detection_area.body_exited.connect(_on_detection_area_body_exited)
	health_component.died.connect(_on_died)
	
	tentacle_target.position = Vector3(0.0, max_reach * 0.5, 0.0)
	_switch_state(State.IDLE)


func _physics_process(delta: float) -> void:
	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.PLAYING:
			_process_playing(delta)
		State.HOLDING:
			_process_holding(delta)
		State.SPOTTED:
			_process_spotted(delta)
		State.ATTACKING:
			_process_attacking(delta)


func _process_idle(delta: float) -> void:
	_idle_time += delta
	
	var wander_x: float = sin(_idle_time * 1.2) * (max_reach * 0.4)
	var wander_y: float = (max_reach * 0.5) + sin(_idle_time * 0.8) * 2.0
	var wander_z: float = cos(_idle_time * 1.5) * (max_reach * 0.4)
	
	var desired_pos := Vector3(wander_x, wander_y, wander_z)
	tentacle_target.position = tentacle_target.position.lerp(desired_pos, delta * track_speed)


func _process_playing(delta: float) -> void:
	_idle_time += delta
	_interact_timer += delta
	
	if not is_instance_valid(target_toy):
		_switch_state(State.IDLE)
		return
		
	var hover_pos: Vector3 = target_toy.global_position + Vector3(0.0, 1.2, 0.0)
	hover_pos.x += sin(_idle_time * 3.0) * 0.6
	hover_pos.z += cos(_idle_time * 2.5) * 0.6
	
	tentacle_target.global_position = tentacle_target.global_position.lerp(
		hover_pos, delta * track_speed
	)
	
	if _interact_timer >= interact_interval:
		_interact_timer = 0.0
		if randf() < 0.25:
			grab_object(target_toy)
		else:
			poke_object(target_toy)


func _process_holding(delta: float) -> void:
	if not is_instance_valid(held_object):
		_switch_state(State.IDLE)
		return
		
	_hold_timer += delta
	
	tentacle_target.position = tentacle_target.position.lerp(_place_target, delta * track_speed)
	held_object.global_position = tentacle_target.global_position
	
	if _hold_timer >= hold_duration:
		drop_object()
		_switch_state(State.PLAYING)


func _process_spotted(delta: float) -> void:
	if not is_instance_valid(target_player):
		_switch_state(State.IDLE)
		return
		
	var target_global: Vector3 = target_player.global_position
	target_global.y += 1.0 
	
	tentacle_target.global_position = tentacle_target.global_position.lerp(
		target_global, delta * track_speed * 0.4 
	)
	
	_charge_timer += delta
	if _charge_timer >= charge_delay:
		_switch_state(State.ATTACKING)
		_decide_attack()


func _process_attacking(_delta: float) -> void:
	# Ensure the held object perfectly follows the tentacle head during attack/throw animations
	if is_instance_valid(held_object):
		held_object.global_position = tentacle_target.global_position


func _switch_state(new_state: State) -> void:
	if current_state == new_state:
		return
		
	current_state = new_state
	print("TentacleEnemy: _switch_state() - Changed to: ", State.keys()[current_state])
	
	match current_state:
		State.IDLE:
			_check_for_pickables()
		State.PLAYING:
			_interact_timer = 0.0
		State.HOLDING:
			_hold_timer = 0.0
		State.SPOTTED:
			_charge_timer = 0.0


func _decide_attack() -> void:
	print("TentacleEnemy: _decide_attack() - Choosing attack pattern.")
	
	# If already holding something, immediately throw it.
	if is_instance_valid(held_object):
		throw_object_at_player()
		return
		
	# Roll the dice to see if we should throw an object instead of biting
	if randf() <= throw_attack_chance:
		var potential_weapons: Array[RigidBody3D] = []
		for body: Node3D in detection_area.get_overlapping_bodies():
			if body is PickableObject and not body.is_held:
				potential_weapons.append(body as RigidBody3D)
				
		if not potential_weapons.is_empty():
			var chosen_weapon: RigidBody3D = potential_weapons.pick_random()
			_perform_grab_and_throw(chosen_weapon)
			return
			
	# Fallback to standard strike if chance fails or no objects are nearby
	strike_player()


func _check_for_pickables() -> void:
	for body: Node3D in detection_area.get_overlapping_bodies():
		if body is PickableObject and not body.is_held:
			print("TentacleEnemy: _check_for_pickables() - Found a toy to play with.")
			target_toy = body
			_switch_state(State.PLAYING)
			return


func poke_object(body: RigidBody3D) -> void:
	print("TentacleEnemy: poke_object() - Lightly tapping the toy.")
	var poke_dir := Vector3(
		randf_range(-1.0, 1.0), 
		randf_range(0.0, 0.5), 
		randf_range(-1.0, 1.0)
	).normalized()
	body.apply_impulse(poke_dir * 2.0)


func grab_object(body: RigidBody3D) -> void:
	print("TentacleEnemy: grab_object() - Picking up the toy to move it.")
	held_object = body
	held_object.freeze = true 
	
	var random_x: float = randf_range(-max_reach * 0.5, max_reach * 0.5)
	var random_z: float = randf_range(-max_reach * 0.5, max_reach * 0.5)
	_place_target = Vector3(random_x, max_reach * 0.3, random_z)
	
	_switch_state(State.HOLDING)


func _perform_grab_and_throw(weapon: RigidBody3D) -> void:
	print("TentacleEnemy: _perform_grab_and_throw() - Snatching weapon to throw!")
	_is_striking = true
	
	# Run the tween strictly during the physics step to avoid rigid body desyncs
	var tween: Tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	
	# Dart to the object quickly
	(
		tween
		.tween_property(tentacle_target, "global_position", weapon.global_position, 0.2)
		.set_trans(Tween.TRANS_CUBIC)
		.set_ease(Tween.EASE_OUT)
	)
	
	# Freeze and secure it to the head
	tween.tween_callback(
		func() -> void:
			if is_instance_valid(weapon):
				held_object = weapon
				held_object.freeze = true
			else:
				_is_striking = false
				_switch_state(State.SPOTTED)
	)
	
	# Lift the object up before throwing to ensure proper physics clearance
	var lift_pos: Vector3 = global_position + Vector3(0.0, max_reach * 0.6, 0.0)
	(
		tween
		.tween_property(tentacle_target, "global_position", lift_pos, 0.25)
		.set_trans(Tween.TRANS_SINE)
		.set_ease(Tween.EASE_IN_OUT)
	)
	
	# Execute the actual throw
	tween.tween_callback(
		func() -> void:
			if is_instance_valid(held_object):
				throw_object_at_player()
			else:
				_is_striking = false
				_switch_state(State.SPOTTED)
	)


func throw_object_at_player() -> void:
	print("TentacleEnemy: throw_object_at_player() - Throwing object!")
	_is_striking = true
	
	if not is_instance_valid(held_object) or not is_instance_valid(target_player):
		_is_striking = false
		_switch_state(State.SPOTTED)
		return
		
	var target_pos: Vector3 = target_player.global_position
	target_pos.y += 1.0 
	
	var throw_dir: Vector3 = tentacle_target.global_position.direction_to(target_pos)
	throw_dir.y += 0.2 
	throw_dir = throw_dir.normalized()
	
	# Cache the object locally before nulling to ensure _process_attacking releases it immediately
	var projectile: RigidBody3D = held_object
	held_object = null
	
	projectile.freeze = false
	# Direct linear_velocity assignment is far more reliable than apply_central_impulse
	# on the exact same frame a RigidBody3D is unfrozen in Godot 4.
	projectile.linear_velocity = throw_dir * throw_force
	
	# Visual follow-through and recoil after throwing
	var tween: Tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	(
		tween
		.tween_property(
			tentacle_target, 
			"position", 
			Vector3(0.0, max_reach * 0.5, 0.0), 
			0.3
		)
	)
	
	tween.tween_callback(
		func() -> void:
			_is_striking = false
			if is_instance_valid(target_player):
				_switch_state(State.SPOTTED)
			else:
				_switch_state(State.IDLE)
	)


func drop_object() -> void:
	if is_instance_valid(held_object):
		print("TentacleEnemy: drop_object() - Placing the object down.")
		held_object.freeze = false
		held_object = null


func strike_player() -> void:
	print("TentacleEnemy: strike_player() - Executing attack!")
	_is_striking = true
	
	var strike_target: Vector3 = tentacle_target.global_position
	if is_instance_valid(target_player):
		strike_target = target_player.global_position
		strike_target.y += 1.0
		
	# Set to physics process mode for engine consistency across all attacks
	var tween: Tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	
	(
		tween
		.tween_property(tentacle_target, "global_position", strike_target, 0.15)
		.set_trans(Tween.TRANS_BACK)
		.set_ease(Tween.EASE_IN)
	)
	
	tween.tween_callback(
		func() -> void:
			if is_instance_valid(target_player) and target_player.has_method("take_damage"):
				print("TentacleEnemy: strike_player() - Hit landed.")
				target_player.take_damage(strike_damage)
	)
	
	(
		tween
		.tween_property(
			tentacle_target, 
			"position", 
			Vector3(0.0, max_reach * 0.5, 0.0), 
			0.3
		)
		.set_delay(0.1)
	)
	
	tween.tween_callback(
		func() -> void:
			_is_striking = false
			if not is_instance_valid(target_player):
				_switch_state(State.IDLE)
			else:
				_switch_state(State.SPOTTED)
	)


func _on_detection_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		print("TentacleEnemy: Player entered territory. Initiating hostility.")
		target_player = body
		if is_instance_valid(held_object):
			_switch_state(State.ATTACKING)
			throw_object_at_player()
		else:
			_switch_state(State.SPOTTED)
			
	elif body is PickableObject and current_state == State.IDLE:
		if body.is_held:
			return
		target_toy = body
		_switch_state(State.PLAYING)


func _on_detection_area_body_exited(body: Node3D) -> void:
	if body == target_player:
		print("TentacleEnemy: Player left detection radius.")
		target_player = null
		if current_state in [State.SPOTTED, State.ATTACKING] and not _is_striking:
			_switch_state(State.IDLE)
			
	elif body == target_toy:
		target_toy = null
		if current_state == State.PLAYING:
			_switch_state(State.IDLE)


func _on_died() -> void:
	print("TentacleEnemy: _on_died() - Enemy defeated.")
	
	if is_instance_valid(held_object):
		held_object.freeze = false
		held_object = null
		
	var tween: Tween = create_tween()
	tween.tween_property(tentacle_target, "position:y", 0.0, 0.5)
