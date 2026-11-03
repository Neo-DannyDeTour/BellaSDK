## Throwable signal rocket weapon that ignites on pickup, drops on weapon swap, and launches.
class_name SignalRocketWeapon
extends ThrowableWeapon

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Minimum guaranteed flight burn duration in seconds when thrown or dropped near expiry.
const MIN_REMAINING_BURN: float = 0.1

## Base light intensity for active flare.
const FLARE_ENERGY_MIN: float = 3.0

## Peak light intensity for active flare flicker.
const FLARE_ENERGY_MAX: float = 5.0

## Duration of a single flicker oscillation step in seconds.
const FLICKER_STEP_TIME: float = 0.06

## Forward velocity in meters per second applied when rocket is dropped on weapon switch.
const DROP_FORWARD_SPEED: float = 2.5

## Upward velocity boost in meters per second applied when rocket is dropped on weapon switch.
const DROP_UPWARD_BOOST: float = 0.5

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Signal Rocket")
## Total burn duration in seconds from initial pickup until full burnout.
@export_range(5.0, 60.0, 0.5) var burn_duration: float = 18.0

## Held OmniLight3D emitting red/orange flare illumination.
@export var flare_light: OmniLight3D

## Held GPUParticles3D emitting ignition sparks and smoke.
@export var flare_particles: GPUParticles3D

# --------------------------------------
# PRIVATE VARIABLES
# --------------------------------------
## Millisecond timestamp recorded when rocket is ignited on pickup.
var _ignition_time_msec: float = 0.0

## Prevents duplicate drop or depletion handling during slot transitions.
var _is_expended: bool = false

## Active timer tracking burnout while held in player hands.
var _burn_timer: SceneTreeTimer = null

## Active tween driving light energy flicker.
var _flicker_tween: Tween = null


# --------------------------------------
# LIFECYCLE METHODS
# --------------------------------------
## Validates exports, enforces single-stack capacity, and ensures flare starts extinguished.
func _ready() -> void:
	super._ready()
	max_ammo = 1
	current_ammo = 1

	if not is_instance_valid(projectile_scene):
		projectile_scene = preload("res://weapons/signal_rocket/signal_rocket_projectile.tscn")

	if not is_instance_valid(flare_light):
		flare_light = get_node_or_null("MuzzlePoint/OmniLight3D") as OmniLight3D
	if not is_instance_valid(flare_particles):
		flare_particles = get_node_or_null("MuzzlePoint/GPUParticles3D") as GPUParticles3D

	assert(is_instance_valid(projectile_scene), "projectile_scene must be assigned")
	_set_flare_active(false)


## Cleans up active timers and tweens when removed from scene tree.
func _exit_tree() -> void:
	super._exit_tree()
	_clear_burn_timer()
	_kill_flicker_tween()


# --------------------------------------
# PUBLIC METHODS
# --------------------------------------
## Equips rocket to player, keeps mesh visible, and ignites the flare timer.
func equip_to_player(player_body: CharacterBody3D) -> void:
	super.equip_to_player(player_body)
	visible = true
	_ignite_held_rocket()


## Launches projectile with remaining burn time and extinguishes held VFX.
func shoot(player_camera: Camera3D) -> bool:
	if not is_equipped or _is_expended or not is_instance_valid(player_camera):
		return false

	var current_time: float = Time.get_ticks_msec()
	if current_time - last_throw_time < fire_rate * 1000.0:
		return false

	if current_ammo <= 0:
		print(weapon_tag, ": No signal rockets remaining.")
		return false

	_is_expended = true
	last_throw_time = current_time
	current_ammo = 0

	var remaining_sec: float = _get_remaining_burn_time(current_time)

	_clear_burn_timer()
	_set_flare_active(false)
	_play_throw_audio()
	_spawn_rocket_projectile(player_camera, remaining_sec, throw_speed, upward_boost)
	sync_ammo_ui()
	_handle_depleted()
	return true


## Invoked by [WeaponInventoryComponent] when player switches away; drops active lit rocket.
func on_unequip() -> void:
	if not is_equipped or _is_expended or current_ammo <= 0:
		return

	_is_expended = true
	current_ammo = 0
	var remaining_sec: float = _get_remaining_burn_time(Time.get_ticks_msec())

	_clear_burn_timer()
	_set_flare_active(false)

	var drop_cam: Camera3D = _resolve_drop_camera()
	if is_instance_valid(drop_cam):
		_spawn_rocket_projectile(drop_cam, remaining_sec, DROP_FORWARD_SPEED, DROP_UPWARD_BOOST)
	else:
		_spawn_rocket_fallback(remaining_sec)

	print(weapon_tag, ": Dropped lit signal rocket due to weapon switch.")
	call_deferred(&"_cleanup_after_unequip")


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
## Calculates remaining burn duration in seconds clamped to [constant MIN_REMAINING_BURN].
func _get_remaining_burn_time(current_time_msec: float) -> float:
	var elapsed_sec: float = (current_time_msec - _ignition_time_msec) / 1000.0
	return maxf(MIN_REMAINING_BURN, burn_duration - elapsed_sec)


## Starts held burn countdown and activates light and spark particles.
func _ignite_held_rocket() -> void:
	_ignition_time_msec = Time.get_ticks_msec()
	_is_expended = false
	_set_flare_active(true)
	_clear_burn_timer()

	_burn_timer = get_tree().create_timer(burn_duration, false)
	_burn_timer.timeout.connect(_on_held_burn_timeout)
	print(weapon_tag, ": Ignited in hand for ", burn_duration, "s.")


## Handles complete burnout while player is still holding the rocket.
func _on_held_burn_timeout() -> void:
	if not is_equipped or _is_expended or current_ammo <= 0 or not is_inside_tree():
		return

	print(weapon_tag, ": Burned out in hand -> depleting.")
	_is_expended = true
	_set_flare_active(false)
	current_ammo = 0
	sync_ammo_ui()
	_handle_depleted()


## Swaps to previous weapon, removes empty rocket slot from inventory, and frees node.
func _handle_depleted() -> void:
	print(weapon_tag, ": Depleted -> removing from inventory and swapping to previous.")
	var inv: WeaponInventoryComponent = _find_inventory(null)
	if is_instance_valid(inv):
		inv.swap_to_previous()
		inv.remove_weapon(self)
	queue_free()


## Deferred slot cleanup after unequip so slot selection finishes cleanly.
func _cleanup_after_unequip() -> void:
	if not is_inside_tree():
		return
	var inv: WeaponInventoryComponent = _find_inventory(null)
	if is_instance_valid(inv):
		inv.remove_weapon(self)
	queue_free()


## Resolves player [Camera3D] from [WeaponInventoryComponent] or active viewport.
func _resolve_drop_camera() -> Camera3D:
	var inv: WeaponInventoryComponent = _find_inventory(null)
	if is_instance_valid(inv) and is_instance_valid(inv.camera):
		return inv.camera
	var vp: Viewport = get_viewport()
	if is_instance_valid(vp):
		return vp.get_camera_3d()
	return null


## Spawns [SignalRocketProjectile] using camera basis, clearance raycast, and custom impulse.
func _spawn_rocket_projectile(
	player_camera: Camera3D, remaining_burn: float, forward_speed: float, up_boost: float
) -> void:
	if not is_instance_valid(projectile_scene):
		push_error("SignalRocketWeapon: projectile_scene is not assigned!")
		return

	var inst: Node = projectile_scene.instantiate()
	var projectile: SignalRocketProjectile = inst as SignalRocketProjectile
	if not is_instance_valid(projectile):
		if is_instance_valid(inst):
			inst.queue_free()
		return

	var forward_dir: Vector3 = -player_camera.global_transform.basis.z.normalized()
	var cam_pos: Vector3 = player_camera.global_position
	var desired_pos: Vector3 = cam_pos + forward_dir * 0.65
	if is_instance_valid(muzzle_point):
		desired_pos = muzzle_point.global_position

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var spawn_pos: Vector3 = desired_pos

	if is_instance_valid(space_state):
		var hit: Dictionary = Utilities.raycast_3d(
			space_state, cam_pos, desired_pos, CollisionLayers.MASK_SOLID_WORLD, _excluded_rids
		)
		if not hit.is_empty():
			var hit_pos: Vector3 = hit.get("position", cam_pos)
			var hit_normal: Vector3 = hit.get("normal", Vector3.UP)
			spawn_pos = hit_pos + hit_normal * 0.12

	var scene_root: Node = get_tree().current_scene
	if not is_instance_valid(scene_root):
		scene_root = get_tree().root

	scene_root.add_child(projectile)
	projectile.global_position = spawn_pos
	projectile.linear_velocity = (forward_dir * forward_speed) + (Vector3.UP * up_boost)
	projectile.angular_velocity = Vector3(4.0, 1.5, -2.0)
	projectile.arm(remaining_burn)
	print(weapon_tag, ": Spawned projectile at ", spawn_pos, " with ", remaining_burn, "s burn.")


## Fallback projectile spawn at weapon global position if camera reference is unavailable.
func _spawn_rocket_fallback(remaining_burn: float) -> void:
	if not is_instance_valid(projectile_scene):
		return

	var inst: Node = projectile_scene.instantiate()
	var projectile: SignalRocketProjectile = inst as SignalRocketProjectile
	if not is_instance_valid(projectile):
		if is_instance_valid(inst):
			inst.queue_free()
		return

	var scene_root: Node = get_tree().current_scene
	if not is_instance_valid(scene_root):
		scene_root = get_tree().root

	var forward_dir: Vector3 = -global_transform.basis.z.normalized()
	scene_root.add_child(projectile)
	projectile.global_position = global_position
	projectile.linear_velocity = (
		(forward_dir * DROP_FORWARD_SPEED) + (Vector3.UP * DROP_UPWARD_BOOST)
	)
	projectile.angular_velocity = Vector3(2.0, 1.0, -1.0)
	projectile.arm(remaining_burn)


## Toggles held flare light, flicker tween, and particle emission.
func _set_flare_active(active: bool) -> void:
	_kill_flicker_tween()

	if is_instance_valid(flare_light):
		flare_light.light_color = Color(1.0, 0.25, 0.05)
		flare_light.omni_range = 14.0
		flare_light.visible = active
		if active:
			flare_light.light_energy = FLARE_ENERGY_MIN
			_start_flicker_tween()
		else:
			flare_light.light_energy = 0.0

	if is_instance_valid(flare_particles):
		flare_particles.emitting = active


## Loops rapid energy oscillation on the held flare light.
func _start_flicker_tween() -> void:
	if not is_inside_tree() or not is_instance_valid(flare_light):
		return

	_flicker_tween = Utilities.reset_tween(self, _flicker_tween)
	if is_instance_valid(_flicker_tween):
		_flicker_tween.set_loops()
		_flicker_tween.tween_property(
			flare_light, "light_energy", FLARE_ENERGY_MAX, FLICKER_STEP_TIME
		)
		_flicker_tween.tween_property(
			flare_light, "light_energy", FLARE_ENERGY_MIN, FLICKER_STEP_TIME
		)


## Safely terminates the active flicker tween.
func _kill_flicker_tween() -> void:
	Utilities.safe_kill_tween(_flicker_tween)
	_flicker_tween = null


## Disconnects and clears the held burnout timer.
func _clear_burn_timer() -> void:
	if is_instance_valid(_burn_timer) and _burn_timer.timeout.is_connected(_on_held_burn_timeout):
		_burn_timer.timeout.disconnect(_on_held_burn_timeout)
	_burn_timer = null
