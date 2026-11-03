## Thrown signal rocket projectile that illuminates environment and extinguishes after burn expiry.
class_name SignalRocketProjectile
extends RigidBody3D

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Minimum flare light energy during active burn.
const FLARE_ENERGY_MIN: float = 3.0

## Peak flare light energy during active burn.
const FLARE_ENERGY_MAX: float = 5.0

## Duration of a single flicker step in seconds.
const FLICKER_STEP_TIME: float = 0.06

## Light fade-out duration in seconds when rocket expires.
const FADEOUT_DURATION: float = 0.5

## Delay in seconds after emission stops before freeing node to allow particles to clear.
const PARTICLE_TAIL_WAIT: float = 1.5

## Weapon scene path re-instantiated on pickup; path-based to break preload cycle.
const WEAPON_SCENE_PATH: String = "res://weapons/signal_rocket/signal_rocket_weapon.tscn"

# --------------------------------------
# EXPORTS
# --------------------------------------
## Display label inspected by player interaction scanner on crosshair hover.
@export var display_name: String = "Signal Rocket"

## Default burn time in seconds if spawned without explicit arming call.
@export var burn_time: float = 18.0

## OmniLight3D providing red/orange flare lighting.
@export var flare_light: OmniLight3D

## GPUParticles3D emitting flare sparks and smoke trail.
@export var flare_particles: GPUParticles3D

# --------------------------------------
# PUBLIC VARIABLES
# --------------------------------------
## Child interaction component enabling player pickup while actively burning.
@onready
var interact_comp: InteractComponent = get_node_or_null("InteractComponent") as InteractComponent

# --------------------------------------
# PRIVATE VARIABLES
# --------------------------------------
## Prevents duplicate burnout sequences.
var _is_extinguished: bool = false

## Active timer tracking remaining burn duration.
var _burn_timer: SceneTreeTimer = null

## Active timer tracking particle tail cleanup delay.
var _cleanup_timer: SceneTreeTimer = null

## Active tween controlling light flicker and fadeout.
var _light_tween: Tween = null


# --------------------------------------
# LIFECYCLE METHODS
# --------------------------------------
## Configures physics layers, caches VFX nodes, and initializes default burn state.
func _ready() -> void:
	assert(burn_time > 0.0, "burn_time must be positive")
	set_process(false)
	set_physics_process(false)
	continuous_cd = true
	collision_layer = CollisionLayers.MASK_DEBRIS | CollisionLayers.MASK_INTERACTIVE
	collision_mask = (
		CollisionLayers.MASK_SOLID_WORLD
		| CollisionLayers.MASK_ENEMIES
		| CollisionLayers.MASK_INTERACTIVE
	)

	if not is_instance_valid(flare_light):
		flare_light = get_node_or_null("OmniLight3D") as OmniLight3D
	if not is_instance_valid(flare_particles):
		flare_particles = get_node_or_null("GPUParticles3D") as GPUParticles3D

	if is_instance_valid(flare_light):
		flare_light.light_color = Color(1.0, 0.25, 0.05)
		flare_light.omni_range = 14.0
		flare_light.light_energy = FLARE_ENERGY_MIN

	if is_instance_valid(flare_particles):
		flare_particles.emitting = true

	if is_instance_valid(interact_comp):
		Utilities.safe_connect(interact_comp.interacted, _on_interact_component_interacted)

	# Cache hit in normal play (level already references weapon scene) -> resolves instantly.
	var req_err: Error = ResourceLoader.load_threaded_request(WEAPON_SCENE_PATH)
	if req_err != OK:
		push_error("SignalRocketProjectile: Failed to request weapon scene: %s" % req_err)

	_start_flicker()
	arm(burn_time)


## Disconnects timers and kills tweens on tree exit.
func _exit_tree() -> void:
	_is_extinguished = true
	_clear_timers()
	_kill_light_tween()


# --------------------------------------
# PUBLIC METHODS
# --------------------------------------
## Arms or resets the projectile burn countdown with the specified duration in seconds.
func arm(duration: float) -> void:
	if _is_extinguished or not is_inside_tree():
		return

	burn_time = maxf(0.05, duration)
	_clear_timers()
	_burn_timer = get_tree().create_timer(burn_time, false)
	_burn_timer.timeout.connect(_on_burn_timeout)
	print("[SignalRocketProjectile] Armed with burn duration: ", burn_time)


## Handles player interaction to re-equip the burning projectile into player hands.
func interact_with(character: CharacterBody3D) -> void:
	_pickup_rocket(character)


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
## Callback invoked by [member interact_comp] when player interacts.
func _on_interact_component_interacted(character: CharacterBody3D) -> void:
	_pickup_rocket(character)


## Instantiates weapon scene with remaining burn time, equips to player, and frees projectile.
func _pickup_rocket(character: CharacterBody3D) -> void:
	if _is_extinguished or not is_inside_tree() or not is_instance_valid(character):
		return

	var remaining_burn: float = 0.1
	if is_instance_valid(_burn_timer):
		remaining_burn = maxf(0.1, _burn_timer.time_left)

	var scene_root: Node = get_tree().current_scene
	if not is_instance_valid(scene_root):
		scene_root = get_tree().root

	var weapon_scene: PackedScene = (
		ResourceLoader.load_threaded_get(WEAPON_SCENE_PATH) as PackedScene
	)
	if not is_instance_valid(weapon_scene):
		push_error("SignalRocketProjectile: Weapon scene unavailable for pickup.")
		return

	var inst: Node = weapon_scene.instantiate()
	var weapon: SignalRocketWeapon = inst as SignalRocketWeapon
	if not is_instance_valid(weapon):
		if is_instance_valid(inst):
			inst.queue_free()
		return

	weapon.burn_duration = remaining_burn
	scene_root.add_child(weapon)
	weapon.equip_to_player(character)
	print(
		"[SignalRocketProjectile] Re-picked up by player with ", remaining_burn, "s burn remaining."
	)
	queue_free()


## Starts looping light energy flicker tween.
func _start_flicker() -> void:
	if not is_inside_tree() or not is_instance_valid(flare_light):
		return

	_light_tween = Utilities.reset_tween(self, _light_tween)
	if is_instance_valid(_light_tween):
		_light_tween.set_loops()
		_light_tween.tween_property(
			flare_light, "light_energy", FLARE_ENERGY_MAX, FLICKER_STEP_TIME
		)
		_light_tween.tween_property(
			flare_light, "light_energy", FLARE_ENERGY_MIN, FLICKER_STEP_TIME
		)


## Initiates graceful fadeout of light and stops particle emission on burn expiry.
func _on_burn_timeout() -> void:
	if _is_extinguished or not is_inside_tree():
		return

	_is_extinguished = true
	collision_layer = CollisionLayers.MASK_DEBRIS
	if is_instance_valid(interact_comp):
		interact_comp.is_enabled = false

	print("[SignalRocketProjectile] Burn expired at: ", global_position)

	if is_instance_valid(flare_particles):
		flare_particles.emitting = false

	_light_tween = Utilities.reset_tween(self, _light_tween)
	if is_instance_valid(_light_tween) and is_instance_valid(flare_light):
		_light_tween.tween_property(flare_light, "light_energy", 0.0, FADEOUT_DURATION)

	_cleanup_timer = get_tree().create_timer(PARTICLE_TAIL_WAIT, false)
	_cleanup_timer.timeout.connect(_on_cleanup_timeout)


## Frees projectile node after remaining particles have dissipated.
func _on_cleanup_timeout() -> void:
	if is_inside_tree():
		queue_free()


## Safely kills the active light tween.
func _kill_light_tween() -> void:
	Utilities.safe_kill_tween(_light_tween)
	_light_tween = null


## Disconnects active scene tree timers.
func _clear_timers() -> void:
	if is_instance_valid(_burn_timer) and _burn_timer.timeout.is_connected(_on_burn_timeout):
		_burn_timer.timeout.disconnect(_on_burn_timeout)
	_burn_timer = null

	if (
		is_instance_valid(_cleanup_timer)
		and _cleanup_timer.timeout.is_connected(_on_cleanup_timeout)
	):
		_cleanup_timer.timeout.disconnect(_on_cleanup_timeout)
	_cleanup_timer = null
