## A trap that appears as a normal tile but attacks the player when approached.
##
## [FlyingTile] acts as an environment hazard. When a player enters its activation
## area, it lifts off the ground, spins to telegraph the attack, and then launches
## itself at the player's last known position.
class_name FlyingTile
extends Area3D

## Defines the sequential lifecycle phases of the flying tile trap.
enum State { IDLE, RISING, SPINNING, ATTACKING }

## The amount of health points deducted from the target upon collision.
@export_group("Tile Settings")
@export var damage: int = 1

## The height in meters the tile will rise before attacking.
@export var rise_height: float = 2.0

## The speed in meters per second at which the tile elevates.
@export var rise_speed: float = 4.0

## The duration in seconds the tile hovers and spins before launching.
@export var spin_duration: float = 0.8

## The flight speed in meters per second during the attack phase.
@export var attack_speed: float = 18.0

## The maximum duration in seconds the tile will fly before self-destructing.
@export var lifetime_after_attack: float = 1.5

## Tracks the current operational phase of the trap.
var _current_state: State = State.IDLE

## The cached initial Y position to calculate relative rise height.
var _start_y: float = 0.0

## Accumulates delta time while in the spinning phase.
var _spin_timer: float = 0.0

## Accumulates delta time while in the attacking phase to handle lifetime expiration.
var _attack_timer: float = 0.0

## The locked normalized vector direction the tile travels during the attack.
var _attack_direction: Vector3 = Vector3.ZERO

## Reference to the targeted player node.
var _target_player: Node3D = null

## The trigger volume that detects when the player comes near.
@onready var _activation_area: Area3D = $ActivationArea

## The primary visual geometry of the tile.
@onready var _mesh: MeshInstance3D = $MeshInstance3D


## Caches the starting height and connects necessary physics signals.
func _ready() -> void:
	_start_y = global_position.y

	_activation_area.body_entered.connect(_on_activation_area_body_entered)
	body_entered.connect(_on_body_entered)

	print("Flying tile initialized and waiting for player.")


## Main physics loop driving state transitions, movement, and visual rotations.
## [param delta] The time elapsed since the previous physics tick in seconds.
func _physics_process(delta: float) -> void:
	match _current_state:
		State.IDLE:
			pass

		State.RISING:
			global_position.y = move_toward(
				global_position.y, _start_y + rise_height, rise_speed * delta
			)

			if global_position.y >= _start_y + rise_height:
				_current_state = State.SPINNING
				print("Tile reached target height. Starting to spin.")

		State.SPINNING:
			_mesh.rotate_y(25.0 * delta)
			_mesh.rotate_x(5.0 * delta)

			_spin_timer += delta
			if _spin_timer >= spin_duration:
				_start_attack()

		State.ATTACKING:
			_mesh.rotate_y(40.0 * delta)
			global_position += _attack_direction * attack_speed * delta

			_attack_timer += delta
			if _attack_timer >= lifetime_after_attack:
				_destroy_tile("Missed player and flew its maximum distance.")


## Locks onto the player and transitions to the rising state.
## [param body] The [Node3D] that entered the trigger area.
func _on_activation_area_body_entered(body: Node3D) -> void:
	if _current_state == State.IDLE and body.is_in_group("player"):
		_target_player = body
		_current_state = State.RISING
		print("Player entered activation sphere. Tile rising.")


## Locks in the attack direction and begins moving towards the player.
func _start_attack() -> void:
	_current_state = State.ATTACKING

	if is_instance_valid(_target_player):
		var target_pos: Vector3 = _target_player.global_position
		target_pos.y += 1.0
		_attack_direction = global_position.direction_to(target_pos)
	else:
		_attack_direction = Vector3.FORWARD

	print("Tile attacking towards player!")


## Resolves collisions during the attack phase, dealing damage to valid targets.
## [param body] The [Node3D] struck by the tile.
func _on_body_entered(body: Node3D) -> void:
	if _current_state != State.ATTACKING:
		return

	var health_comp: HealthComponent = (
		body.find_child("HealthComponent", true, false) as HealthComponent
	)

	if health_comp:
		print("FlyingTile: Direct hit! Calling HealthComponent.take_damage(100)")
		health_comp.take_damage(100)
		_destroy_tile("Succeeded in hitting player.")
	elif body.is_in_group("player"):
		push_warning("FlyingTile: Player hit but no HealthComponent found!")
		_destroy_tile("Hit player, but no HealthComponent found.")
	else:
		print("FlyingTile: Collided with environment.")
		_destroy_tile("Collided with environment.")


## Cleans up the node from memory.
## [param reason] Diagnostic string explaining why the destruction occurred.
func _destroy_tile(reason: String) -> void:
	print("Tile destroyed. Reason: ", reason)
	queue_free()
