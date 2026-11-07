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

## [SignalRocketWeapon] burn property; set by name so this script never names that class.
## Typed ref recreated weapon<->projectile cycle -> deadlocked threaded sub-loads at 99%.
const PROP_BURN_DURATION: StringName = &"burn_duration"

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

## Floating 3D label rendering equip and grab instructions.
@export var label: Label3D

## Sprite display rendering hardware button prompt icon.
@export var prompt_icon: Sprite3D

## Visual outline highlight component for player focus cues.
@export var highlight_comp: HighlightComponent

# --------------------------------------
# PRIVATE VARIABLES
# --------------------------------------
## Toggle state governing item text prompt visibility.
var _show_text_prompts: bool = true

## Prevents duplicate pickup execution during frame transitions.
var _is_being_picked_up: bool = false

## Prevents duplicate burnout sequences.
var _is_extinguished: bool = false

## Active timer tracking remaining burn duration.
var _burn_timer: SceneTreeTimer = null

## Active timer tracking particle tail cleanup delay.
var _cleanup_timer: SceneTreeTimer = null

## Active tween controlling light flicker and fadeout.
var _light_tween: Tween = null

# --------------------------------------
# ONREADY VARIABLES
# --------------------------------------
## Child interaction component enabling player pickup while actively burning.
@onready
var interact_comp: InteractComponent = get_node_or_null("InteractComponent") as InteractComponent


# --------------------------------------
# LIFECYCLE METHODS
# --------------------------------------
## Configures physics layers, caches VFX/UI nodes, and initializes default burn state.
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
	if not is_instance_valid(label):
		label = get_node_or_null("Label3D") as Label3D
	if not is_instance_valid(prompt_icon):
		prompt_icon = get_node_or_null("PromptIcon") as Sprite3D
	if not is_instance_valid(highlight_comp):
		highlight_comp = get_node_or_null("HighlightComponent") as HighlightComponent

	if is_instance_valid(label):
		label.hide()
	if is_instance_valid(prompt_icon):
		prompt_icon.hide()

	if is_instance_valid(flare_light):
		flare_light.light_color = Color(1.0, 0.25, 0.05)
		flare_light.omni_range = 14.0
		flare_light.light_energy = FLARE_ENERGY_MIN

	if is_instance_valid(flare_particles):
		flare_particles.emitting = true

	var settings_node: Node = get_node_or_null("/root/GlobalSettings")
	if is_instance_valid(settings_node) and settings_node.has_method("get_setting"):
		var prompt_setting: Variant = settings_node.call(
			"get_setting", "Gameplay", "show_item_prompts", true
		)
		if typeof(prompt_setting) == TYPE_BOOL:
			_show_text_prompts = prompt_setting

	if Events.has_signal("item_prompts_toggled"):
		Utilities.safe_connect(Events.item_prompts_toggled, _on_item_prompts_toggled)

	if is_instance_valid(interact_comp):
		Utilities.safe_connect(interact_comp.interacted, _on_interact_component_interacted)
		Utilities.safe_connect(interact_comp.focused, _on_interact_focused)
		Utilities.safe_connect(interact_comp.unfocused, _on_interact_unfocused)

	# Cache hit in normal play (level already references weapon scene) -> resolves instantly.
	var req_err: Error = ResourceLoader.load_threaded_request(WEAPON_SCENE_PATH)
	if req_err != OK:
		push_error("SignalRocketProjectile: Failed to request weapon scene: %s" % req_err)

	_start_flicker()
	arm(burn_time)


## Disconnects timers, listeners, and kills tweens on tree exit.
func _exit_tree() -> void:
	_is_extinguished = true
	_clear_timers()
	_kill_light_tween()

	if (
		Events.has_signal("item_prompts_toggled")
		and Events.item_prompts_toggled.is_connected(_on_item_prompts_toggled)
	):
		Events.item_prompts_toggled.disconnect(_on_item_prompts_toggled)


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


## Updates prompt labels and hardware icons when crosshair focuses pickup.
func _on_interact_focused() -> void:
	if _is_extinguished or _is_being_picked_up:
		return

	_update_label_text()
	if is_instance_valid(label) and _show_text_prompts:
		label.show()
	if is_instance_valid(prompt_icon) and prompt_icon.texture != null:
		prompt_icon.show()


## Hides prompt visual elements when crosshair moves away.
func _on_interact_unfocused() -> void:
	if is_instance_valid(label):
		label.hide()
	if is_instance_valid(prompt_icon):
		prompt_icon.hide()


## Formats prompt string dynamically matching controls and hardware button textures.
func _update_label_text() -> void:
	var key_name: String = "E"
	var icon_tex: Texture2D = null

	var input_helper_node: Node = get_node_or_null("/root/InputHelper")
	if is_instance_valid(input_helper_node):
		if input_helper_node.has_method("get_action_key_label"):
			var raw_key: Variant = input_helper_node.call("get_action_key_label", &"interact")
			if typeof(raw_key) == TYPE_STRING:
				var parsed_key: String = str(raw_key)
				if not parsed_key.is_empty():
					key_name = parsed_key

		var events: Array[InputEvent] = InputMap.action_get_events(&"interact")
		if not events.is_empty() and input_helper_node.has_method("get_event_icon"):
			var icon_val: Variant = input_helper_node.call("get_event_icon", events[0])
			if icon_val is Texture2D:
				icon_tex = icon_val

	if is_instance_valid(prompt_icon):
		prompt_icon.texture = icon_tex
		prompt_icon.visible = (icon_tex != null)

	if is_instance_valid(label):
		label.text = "Press [%s] to grab" % key_name
		if icon_tex != null and is_instance_valid(prompt_icon):
			label.text = "Press    to grab"
			prompt_icon.position.x = 0.0
			prompt_icon.position.y = label.position.y
		label.position.x = 0.0


## Updates prompt visibility when menu setting is modified.
func _on_item_prompts_toggled(enabled: bool) -> void:
	_show_text_prompts = enabled
	if not _show_text_prompts and is_instance_valid(label):
		label.hide()


## Instantiates weapon scene with remaining burn time, equips to player, and frees projectile.
func _pickup_rocket(character: CharacterBody3D) -> void:
	if (
		_is_being_picked_up
		or _is_extinguished
		or not is_inside_tree()
		or not is_instance_valid(character)
	):
		return

	_is_being_picked_up = true
	_is_extinguished = true

	if is_instance_valid(interact_comp):
		interact_comp.is_enabled = false

	collision_layer = CollisionLayers.MASK_NONE
	collision_mask = CollisionLayers.MASK_NONE

	if is_instance_valid(label):
		label.hide()
	if is_instance_valid(prompt_icon):
		prompt_icon.hide()
	if is_instance_valid(highlight_comp):
		highlight_comp.suppress(true)

	var remaining_burn: float = 0.1
	if is_instance_valid(_burn_timer):
		remaining_burn = maxf(0.1, _burn_timer.time_left)

	_clear_timers()
	_kill_light_tween()

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
	var weapon: ThrowableWeapon = inst as ThrowableWeapon
	if not is_instance_valid(weapon) or not (PROP_BURN_DURATION in weapon):
		if is_instance_valid(inst):
			inst.queue_free()
		return

	weapon.set(PROP_BURN_DURATION, remaining_burn)
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


## Initiates graceful fadeout of light, stops emission, and hides prompts on burn expiry.
func _on_burn_timeout() -> void:
	if _is_extinguished or not is_inside_tree():
		return

	_is_extinguished = true
	collision_layer = CollisionLayers.MASK_DEBRIS
	if is_instance_valid(interact_comp):
		interact_comp.is_enabled = false

	if is_instance_valid(label):
		label.hide()
	if is_instance_valid(prompt_icon):
		prompt_icon.hide()
	if is_instance_valid(highlight_comp):
		highlight_comp.suppress(true)

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
