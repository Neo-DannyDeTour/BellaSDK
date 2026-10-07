## Organic predator manipulating physics props and attacking player.
class_name TentacleEnemy
extends StaticBody3D

## Central operational behavior states for [TentacleEnemy].
enum State { IDLE, PLAYING, HOLDING, SPOTTED, ATTACKING }

## Delay in seconds before striking after spotting player.
@export var charge_delay: float = 2.0

## Probability between 0.0 and 1.0 of throwing an object.
@export_range(0.0, 1.0) var throw_attack_chance: float = 0.4

## Linear force applied when launching thrown props.
@export var throw_force: float = 15.0

## Damage points inflicted by direct physical strike.
@export var strike_damage: int = 15

## Target tracking interpolation speed factor.
@export var track_speed: float = 5.0

## Maximum vertical reaching distance in meters.
@export var max_reach: float = 8.0

## Duration in seconds an object is held aloft.
@export var hold_duration: float = 1.5

## Interval in seconds between prop interactions.
@export var interact_interval: float = 1.5

## Current operational state of tentacle.
var current_state: TentacleEnemy.State = TentacleEnemy.State.IDLE

## Active [RigidBody3D] prop currently held.
var held_object: RigidBody3D = null

## Tracked player target entity in range.
var target_player: Node3D = null

## Tracked idle prop entity chosen as toy.
var target_toy: Node3D = null

## Elapsed charge duration before striking.
var _charge_timer: float = 0.0

## Elapsed duration of holding current prop.
var _hold_timer: float = 0.0

## Elapsed interval between toy pokes.
var _interact_timer: float = 0.0

## Accumulated idle time for procedural sway.
var _idle_time: float = 0.0

## Indicates if an active strike tween blocks.
var _is_striking: bool = false

## Destination coordinates for placing toy.
var _place_target: Vector3 = Vector3.ZERO

## Reusable vector buffer preventing per-tick vector allocations.
var _desired_pos: Vector3 = Vector3.ZERO

## Active tween controlling strike motion.
var _action_tween: Tween = null

## Pre-allocated weapon candidate list avoiding heap churn.
var _potential_weapons: Array[RigidBody3D] = []

## Spatial target driving procedural mesh tip.
@onready var tentacle_target: Node3D = $TentacleTarget

## Detection volume sensing player and props.
@onready var detection_area: Area3D = $DetectionArea

## Core health tracking component for enemy.
@onready var health_component: HealthComponent = $HealthComponent


## Initializes signal bindings and sets initial state.
func _ready() -> void:
	print("TentacleEnemy: _ready() initializing enemy.")
	tentacle_target.position = Vector3(0.0, max_reach * 0.5, 0.0)

	detection_area.collision_layer = CollisionLayers.MASK_NONE
	detection_area.collision_mask = (CollisionLayers.MASK_PLAYER | CollisionLayers.MASK_INTERACTIVE)

	Utilities.safe_connect(detection_area.body_entered, _on_detection_area_body_entered)
	Utilities.safe_connect(detection_area.body_exited, _on_detection_area_body_exited)

	if is_instance_valid(health_component):
		Utilities.safe_connect(health_component.died, _on_died)

	_switch_state(TentacleEnemy.State.IDLE)


## Dispatches physics updates based on active state.
func _physics_process(delta: float) -> void:
	if _is_striking:
		_process_attacking(delta)
		return

	match current_state:
		TentacleEnemy.State.IDLE:
			_process_idle(delta)
		TentacleEnemy.State.PLAYING:
			_process_playing(delta)
		TentacleEnemy.State.HOLDING:
			_process_holding(delta)
		TentacleEnemy.State.SPOTTED:
			_process_spotted(delta)


## Evaluates procedural idle sway and moves target.
func _process_idle(delta: float) -> void:
	print("TentacleEnemy: _process_idle() updating idle sway.")
	_idle_time += delta

	_desired_pos.x = sin(_idle_time * 1.2) * (max_reach * 0.4)
	_desired_pos.y = (max_reach * 0.5) + sin(_idle_time * 0.8) * 2.0
	_desired_pos.z = cos(_idle_time * 1.5) * (max_reach * 0.4)

	tentacle_target.position = MathUtils.damp_v3(
		tentacle_target.position, _desired_pos, track_speed, delta
	)


## Evaluates toy hovering and periodic interactions.
func _process_playing(delta: float) -> void:
	#print("TentacleEnemy: _process_playing() hovering over toy.")
	_idle_time += delta
	_interact_timer += delta

	if not is_instance_valid(target_toy):
		_switch_state(TentacleEnemy.State.IDLE)
		return

	_desired_pos = target_toy.global_position + Vector3(0.0, 1.2, 0.0)
	_desired_pos.x += sin(_idle_time * 3.0) * 0.6
	_desired_pos.z += cos(_idle_time * 2.5) * 0.6

	tentacle_target.global_position = MathUtils.damp_v3(
		tentacle_target.global_position, _desired_pos, track_speed, delta
	)

	if _interact_timer >= interact_interval:
		_interact_timer = 0.0
		var toy_rb: RigidBody3D = target_toy if target_toy is RigidBody3D else null
		if is_instance_valid(toy_rb):
			if randf() < 0.25:
				grab_object(toy_rb)
			else:
				poke_object(toy_rb)


## Carries held prop to local destination position.
func _process_holding(delta: float) -> void:
	print("TentacleEnemy: _process_holding() carrying held prop.")
	if not is_instance_valid(held_object):
		_switch_state(TentacleEnemy.State.IDLE)
		return

	_hold_timer += delta
	tentacle_target.position = MathUtils.damp_v3(
		tentacle_target.position, _place_target, track_speed, delta
	)
	held_object.global_position = tentacle_target.global_position

	if _hold_timer >= hold_duration:
		drop_object()
		_switch_state(TentacleEnemy.State.PLAYING)


## Tracks player target and charges strike attack.
func _process_spotted(delta: float) -> void:
	print("TentacleEnemy: _process_spotted() charging strike on target.")
	if not is_instance_valid(target_player):
		_switch_state(TentacleEnemy.State.IDLE)
		return

	_desired_pos = target_player.global_position
	_desired_pos.y += 1.0

	tentacle_target.global_position = MathUtils.damp_v3(
		tentacle_target.global_position, _desired_pos, track_speed * 0.4, delta
	)

	_charge_timer += delta
	if _charge_timer >= charge_delay:
		_switch_state(TentacleEnemy.State.ATTACKING)
		_decide_attack()


## Locks held prop transform to tentacle tip.
func _process_attacking(_delta: float) -> void:
	print("TentacleEnemy: _process_attacking() locking held object transform.")
	if is_instance_valid(held_object):
		held_object.global_position = tentacle_target.global_position


## Transitions active state and resets tick timers.
func _switch_state(new_state: TentacleEnemy.State) -> void:
	print("TentacleEnemy: _switch_state() switching to state: ", new_state)
	if current_state == new_state:
		return

	current_state = new_state
	match current_state:
		TentacleEnemy.State.IDLE:
			_check_for_pickables()
		TentacleEnemy.State.PLAYING:
			_interact_timer = 0.0
		TentacleEnemy.State.HOLDING:
			_hold_timer = 0.0
		TentacleEnemy.State.SPOTTED:
			_charge_timer = 0.0


## Selects strike or throw attack sequence.
func _decide_attack() -> void:
	print("TentacleEnemy: _decide_attack() evaluating attack pattern.")
	if is_instance_valid(held_object):
		throw_object_at_player()
		return

	if randf() <= throw_attack_chance:
		_potential_weapons.clear()
		for body: Node3D in detection_area.get_overlapping_bodies():
			if body is RigidBody3D and body.get(&"is_held") != true:
				var rb_body: RigidBody3D = body
				_potential_weapons.append(rb_body)

		if not _potential_weapons.is_empty():
			var chosen: RigidBody3D = _potential_weapons.pick_random()
			_perform_grab_and_throw(chosen)
			return

	strike_player()


## Scans detection volume for untethered props.
func _check_for_pickables() -> void:
	print("TentacleEnemy: _check_for_pickables() checking for props.")
	for body: Node3D in detection_area.get_overlapping_bodies():
		if body is RigidBody3D and body.get(&"is_held") != true:
			print("TentacleEnemy: Target prop detected: ", body.name)
			target_toy = body
			_switch_state(TentacleEnemy.State.PLAYING)
			return


## Applies small physical impulse to chosen toy.
func poke_object(body: RigidBody3D) -> void:
	print("TentacleEnemy: poke_object() tapping prop: ", body.name)
	var poke_dir: Vector3 = (
		Vector3(randf_range(-1.0, 1.0), randf_range(0.0, 0.5), randf_range(-1.0, 1.0)).normalized()
	)
	body.apply_impulse(poke_dir * 2.0)


## Freezes prop and sets random placement goal.
func grab_object(body: RigidBody3D) -> void:
	print("TentacleEnemy: grab_object() grabbing prop: ", body.name)
	held_object = body
	held_object.freeze = true

	var rx: float = randf_range(-max_reach * 0.5, max_reach * 0.5)
	var rz: float = randf_range(-max_reach * 0.5, max_reach * 0.5)
	_place_target = Vector3(rx, max_reach * 0.3, rz)
	_switch_state(TentacleEnemy.State.HOLDING)


## Orchestrates multi-step grab and throw tween.
func _perform_grab_and_throw(weapon: RigidBody3D) -> void:
	print("TentacleEnemy: _perform_grab_and_throw() grabbing weapon.")
	_is_striking = true
	_action_tween = Utilities.reset_tween(self, _action_tween)
	if not _action_tween:
		_is_striking = false
		return

	_action_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	(
		_action_tween
		. tween_property(tentacle_target, ^"global_position", weapon.global_position, 0.2)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)

	_action_tween.tween_callback(
		func() -> void:
			if is_instance_valid(weapon):
				held_object = weapon
				held_object.freeze = true
			else:
				_is_striking = false
				_switch_state(TentacleEnemy.State.SPOTTED)
	)

	var lift_pos: Vector3 = global_position + Vector3(0.0, max_reach * 0.6, 0.0)
	(
		_action_tween
		. tween_property(tentacle_target, ^"global_position", lift_pos, 0.25)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)

	_action_tween.tween_callback(
		func() -> void:
			if is_instance_valid(held_object):
				throw_object_at_player()
			else:
				_is_striking = false
				_switch_state(TentacleEnemy.State.SPOTTED)
	)


## Launches held prop at player with linear force.
func throw_object_at_player() -> void:
	print("TentacleEnemy: throw_object_at_player() launching prop.")
	_is_striking = true

	if not is_instance_valid(held_object) or not is_instance_valid(target_player):
		_is_striking = false
		_switch_state(TentacleEnemy.State.SPOTTED)
		return

	var target_pos: Vector3 = target_player.global_position
	target_pos.y += 1.0

	var throw_dir: Vector3 = tentacle_target.global_position.direction_to(target_pos)
	throw_dir.y += 0.2
	throw_dir = throw_dir.normalized()

	var projectile: RigidBody3D = held_object
	held_object = null
	projectile.freeze = false
	projectile.linear_velocity = throw_dir * throw_force

	_action_tween = Utilities.reset_tween(self, _action_tween)
	if not _action_tween:
		_is_striking = false
		return

	_action_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_action_tween.tween_property(
		tentacle_target, ^"position", Vector3(0.0, max_reach * 0.5, 0.0), 0.3
	)

	_action_tween.tween_callback(
		func() -> void:
			_is_striking = false
			if is_instance_valid(target_player):
				_switch_state(TentacleEnemy.State.SPOTTED)
			else:
				_switch_state(TentacleEnemy.State.IDLE)
	)


## Releases and unfreezes held prop naturally.
func drop_object() -> void:
	print("TentacleEnemy: drop_object() releasing held prop.")
	if is_instance_valid(held_object):
		held_object.freeze = false
		held_object = null


## Rockets tentacle tip toward player to damage.
func strike_player() -> void:
	print("TentacleEnemy: strike_player() executing strike.")
	_is_striking = true
	var strike_target: Vector3 = tentacle_target.global_position
	if is_instance_valid(target_player):
		strike_target = target_player.global_position
		strike_target.y += 1.0

	_action_tween = Utilities.reset_tween(self, _action_tween)
	if not _action_tween:
		_is_striking = false
		return

	_action_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	(
		_action_tween
		. tween_property(tentacle_target, ^"global_position", strike_target, 0.15)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_IN)
	)

	_action_tween.tween_callback(
		func() -> void:
			if is_instance_valid(target_player):
				print("TentacleEnemy: Strike impact on player.")
				var raw_hc: Node = NodeQuery.find_first_child_of_type(
					target_player, HealthComponent
				)
				var health: HealthComponent = raw_hc if raw_hc is HealthComponent else null
				if is_instance_valid(health):
					health.take_damage(strike_damage)
				elif target_player.has_method(&"take_damage"):
					target_player.call(&"take_damage", strike_damage)
	)

	(
		_action_tween
		. tween_property(tentacle_target, ^"position", Vector3(0.0, max_reach * 0.5, 0.0), 0.3)
		. set_delay(0.1)
	)

	_action_tween.tween_callback(
		func() -> void:
			_is_striking = false
			if not is_instance_valid(target_player):
				_switch_state(TentacleEnemy.State.IDLE)
			else:
				_switch_state(TentacleEnemy.State.SPOTTED)
	)


## Handles entity entering detection territory.
func _on_detection_area_body_entered(body: Node3D) -> void:
	print("TentacleEnemy: _on_detection_area_body_entered() with: ", body.name)
	if body.is_in_group(&"player"):
		target_player = body
		if is_instance_valid(held_object):
			_switch_state(TentacleEnemy.State.ATTACKING)
			throw_object_at_player()
		else:
			_switch_state(TentacleEnemy.State.SPOTTED)
	elif body is RigidBody3D and current_state == TentacleEnemy.State.IDLE:
		if body.get(&"is_held") == true:
			return
		target_toy = body
		_switch_state(TentacleEnemy.State.PLAYING)


## Handles entity exiting detection territory.
func _on_detection_area_body_exited(body: Node3D) -> void:
	print("TentacleEnemy: _on_detection_area_body_exited() with: ", body.name)
	if body == target_player:
		target_player = null
		var in_combat_state: bool = (
			current_state == TentacleEnemy.State.SPOTTED
			or current_state == TentacleEnemy.State.ATTACKING
		)
		if in_combat_state and not _is_striking:
			_switch_state(TentacleEnemy.State.IDLE)
	elif body == target_toy:
		target_toy = null
		if current_state == TentacleEnemy.State.PLAYING:
			_switch_state(TentacleEnemy.State.IDLE)


## Drops held prop and droops tentacle on defeat.
func _on_died() -> void:
	print("TentacleEnemy: _on_died() tentacle defeated.")
	if is_instance_valid(held_object):
		held_object.freeze = false
		held_object = null

	_action_tween = Utilities.reset_tween(self, _action_tween)
	if is_instance_valid(_action_tween):
		_action_tween.tween_property(tentacle_target, ^"position:y", 0.0, 0.5)
