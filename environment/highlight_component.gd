## Applies outline materials to target meshes on focus, first sight, or periodically.
class_name HighlightComponent
extends Node

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Available outline palette color options matching visual settings.
const OUTLINE_COLOR_VALUES: Array[Color] = [
	Color(0.0, 1.0, 0.5, 1.0),
	Color(0.0, 0.8, 1.0, 1.0),
	Color(1.0, 0.9, 0.1, 1.0),
	Color(1.0, 0.5, 0.0, 1.0),
	Color(1.0, 0.2, 0.2, 1.0),
	Color(1.0, 0.1, 0.8, 1.0),
	Color(1.0, 1.0, 1.0, 1.0)
]

## Default constant value for outline periodic trigger interval.
const DEFAULT_OUTLINE_INTERVAL: float = 10.0

## Default constant value for outline temporary pulse duration.
const DEFAULT_OUTLINE_DURATION: float = 3.0

# --------------------------------------
# EXPORTS
# --------------------------------------
## The shader material applied as an outline when the target is focused.
@export var outline_material: ShaderMaterial

## Array of specific meshes to highlight. Leave empty to auto-detect nodes.
@export var target_meshes: Array[GeometryInstance3D]

## The component handling interaction logic. Assign in inspector for performance.
@export var interact_component: Node

## Optional pre-existing [VisibleOnScreenNotifier3D]. Auto-created if null.
@export var visibility_notifier: VisibleOnScreenNotifier3D

# --------------------------------------
# RUNTIME STATE
# --------------------------------------
## Tracks whether the current target is actively focused by the player.
var _is_focused: bool = false

## Tracks whether the highlight effect is temporarily disabled or overridden.
var _is_suppressed: bool = false

## Cached geometry instances to prevent expensive runtime tree traversals.
var _cached_meshes: Array[GeometryInstance3D] = []

## Outline base mode: 0 is Off, 1 is Always, 2 is On Focus.
var _outline_mode: int = 2

## Tracks whether the first sight highlight feature is active globally.
var _first_sight_enabled: bool = false

## Tracks whether the periodic highlight feature is active globally.
var _periodic_enabled: bool = false

## Active highlight outline color vector.
var _outline_color: Color = Color(0.0, 1.0, 0.5, 1.0)

## Active highlight oscillation pulse speed.
var _blink_speed: float = 8.0

## Active highlight minimum pulse intensity clamp.
var _min_intensity: float = 0.2

## Active highlight maximum pulse intensity clamp.
var _max_intensity: float = 1.0

## Active highlight periodic repeat interval in seconds.
var _outline_interval: float = 10.0

## Active highlight temporary pulse duration in seconds.
var _outline_duration: float = 3.0

## Tracks whether this object has ever entered the camera viewport.
var _has_been_seen: bool = false

## Tracks whether the object is currently within the camera frustum.
var _is_on_screen: bool = false

## Tracks whether the first sight temporary highlight is actively running.
var _is_first_sight_active: bool = false

## Tracks whether a periodic highlight pulse is actively running.
var _is_periodic_active: bool = false

## Tracks whether the visibility notifier was created dynamically.
var _owns_screen_notifier: bool = false

## Internal timer managing periodic interval ticks.
var _periodic_timer: Timer = null

## Internal timer managing temporary pulse duration expiration.
var _duration_timer: Timer = null


## Initializes connections, caches meshes, and sets up timers.
func _ready() -> void:
	if Engine.is_editor_hint():
		return

	print("HighlightComponent: Initializing component.")

	if not is_instance_valid(interact_component):
		var parent: Node = get_parent()
		if is_instance_valid(parent):
			interact_component = parent.get_node_or_null("InteractComponent")

	if is_instance_valid(interact_component):
		if interact_component.has_signal(&"focused"):
			interact_component.connect(&"focused", _on_focus)
		if interact_component.has_signal(&"unfocused"):
			interact_component.connect(&"unfocused", _on_unfocus)
	else:
		print("HighlightComponent: No InteractComponent assigned or found in parent.")

	_cache_target_meshes()
	_setup_timers()
	_setup_visibility_notifier()
	_connect_outline_events()
	_load_initial_settings()
	set_process(true)


## Cleans up dynamically instantiated visibility notifier on exit.
func _exit_tree() -> void:
	print("HighlightComponent: Exiting tree, cleaning up resources.")
	if _owns_screen_notifier and is_instance_valid(visibility_notifier):
		visibility_notifier.queue_free()


## Checks camera visibility every frame until first sight triggers.
func _process(_delta: float) -> void:
	if _first_sight_enabled and not _has_been_seen:
		if _is_target_on_screen():
			print("HighlightComponent: Target seen on first sight.")
			_has_been_seen = true
			_is_on_screen = true
			_trigger_first_sight_pulse()
			if not _periodic_enabled:
				set_process(false)
	elif not _first_sight_enabled and not _periodic_enabled:
		set_process(false)


## Sets up internal timers for periodic and duration highlight cycles.
func _setup_timers() -> void:
	print("HighlightComponent: Setting up internal timers.")
	_periodic_timer = Timer.new()
	_periodic_timer.name = "HighlightPeriodicTimer"
	_periodic_timer.one_shot = false
	_periodic_timer.wait_time = _outline_interval
	_periodic_timer.timeout.connect(_on_periodic_timeout)
	add_child(_periodic_timer)

	_duration_timer = Timer.new()
	_duration_timer.name = "HighlightDurationTimer"
	_duration_timer.one_shot = true
	_duration_timer.wait_time = _outline_duration
	_duration_timer.timeout.connect(_on_duration_timeout)
	add_child(_duration_timer)


## Instantiates or connects a [VisibleOnScreenNotifier3D] on the target.
func _setup_visibility_notifier() -> void:
	print("HighlightComponent: Setting up visibility notifier.")
	if not is_instance_valid(visibility_notifier):
		var parent: Node = get_parent()
		if is_instance_valid(parent):
			var existing_notif: Node = parent.get_node_or_null("HighlightVisibilityNotifier")
			if existing_notif is VisibleOnScreenNotifier3D:
				visibility_notifier = existing_notif as VisibleOnScreenNotifier3D

	if not is_instance_valid(visibility_notifier):
		var parent: Node = get_parent()
		if parent is Node3D:
			visibility_notifier = VisibleOnScreenNotifier3D.new()
			visibility_notifier.name = "HighlightVisibilityNotifier"
			_owns_screen_notifier = true
			parent.add_child.call_deferred(visibility_notifier)

	if is_instance_valid(visibility_notifier):
		_setup_notifier_aabb()
		if not visibility_notifier.screen_entered.is_connected(_on_screen_entered):
			visibility_notifier.screen_entered.connect(_on_screen_entered)
		if not visibility_notifier.screen_exited.is_connected(_on_screen_exited):
			visibility_notifier.screen_exited.connect(_on_screen_exited)


## Calculates and configures bounding box for [VisibleOnScreenNotifier3D].
func _setup_notifier_aabb() -> void:
	#print("HighlightComponent: Configuring visibility notifier AABB.")
	if not is_instance_valid(visibility_notifier):
		return

	var combined_aabb: AABB = AABB()
	var has_aabb: bool = false
	for m: GeometryInstance3D in _cached_meshes:
		if is_instance_valid(m) and m is VisualInstance3D:
			var mesh_aabb: AABB = (m as VisualInstance3D).get_aabb()
			if mesh_aabb.size != Vector3.ZERO:
				if not has_aabb:
					combined_aabb = mesh_aabb
					has_aabb = true
				else:
					combined_aabb = combined_aabb.merge(mesh_aabb)

	if has_aabb and combined_aabb.size != Vector3.ZERO:
		visibility_notifier.aabb = combined_aabb
	else:
		visibility_notifier.aabb = AABB(Vector3(-1.0, -1.0, -1.0), Vector3(2.0, 2.0, 2.0))


## Verifies if target is currently within the active camera frustum.
func _is_target_on_screen() -> bool:
	if is_instance_valid(visibility_notifier) and visibility_notifier.is_on_screen():
		return true

	var vp: Viewport = get_viewport()
	if is_instance_valid(vp):
		var cam: Camera3D = vp.get_camera_3d()
		if is_instance_valid(cam):
			var parent: Node = get_parent()
			if parent is Node3D:
				var parent_pos: Vector3 = (parent as Node3D).global_position
				return cam.is_position_in_frustum(parent_pos)

	return false


## Subscribes to global outline signals from the event bus.
func _connect_outline_events() -> void:
	print("HighlightComponent: Binding outline event listeners.")
	if not is_instance_valid(Events):
		return

	if Events.has_signal(&"outline_mode_changed"):
		if not Events.outline_mode_changed.is_connected(_on_outline_mode_changed):
			Events.outline_mode_changed.connect(_on_outline_mode_changed)

	if Events.has_signal(&"outline_first_sight_toggled"):
		if not Events.outline_first_sight_toggled.is_connected(_on_outline_first_sight_toggled):
			Events.outline_first_sight_toggled.connect(_on_outline_first_sight_toggled)

	if Events.has_signal(&"outline_periodic_toggled"):
		if not Events.outline_periodic_toggled.is_connected(_on_outline_periodic_toggled):
			Events.outline_periodic_toggled.connect(_on_outline_periodic_toggled)

	if Events.has_signal(&"outline_color_changed"):
		if not Events.outline_color_changed.is_connected(_on_outline_color_changed):
			Events.outline_color_changed.connect(_on_outline_color_changed)

	if Events.has_signal(&"outline_blink_speed_changed"):
		if not Events.outline_blink_speed_changed.is_connected(_on_outline_blink_speed_changed):
			Events.outline_blink_speed_changed.connect(_on_outline_blink_speed_changed)

	if Events.has_signal(&"outline_min_intensity_changed"):
		if not Events.outline_min_intensity_changed.is_connected(_on_outline_min_intensity_changed):
			Events.outline_min_intensity_changed.connect(_on_outline_min_intensity_changed)

	if Events.has_signal(&"outline_max_intensity_changed"):
		if not Events.outline_max_intensity_changed.is_connected(_on_outline_max_intensity_changed):
			Events.outline_max_intensity_changed.connect(_on_outline_max_intensity_changed)

	if Events.has_signal(&"outline_interval_changed"):
		if not Events.outline_interval_changed.is_connected(_on_outline_interval_changed):
			Events.outline_interval_changed.connect(_on_outline_interval_changed)

	if Events.has_signal(&"outline_duration_changed"):
		if not Events.outline_duration_changed.is_connected(_on_outline_duration_changed):
			Events.outline_duration_changed.connect(_on_outline_duration_changed)


## Reads initial outline configuration from [GlobalSettings] silently.
func _load_initial_settings() -> void:
	print("HighlightComponent: Loading initial outline settings.")
	if is_instance_valid(GlobalSettings):
		_outline_mode = GlobalSettings.get_setting("Accessibility", "outline_mode", 2)
		_first_sight_enabled = GlobalSettings.get_setting(
			"Accessibility", "outline_first_sight", false
		)
		_periodic_enabled = GlobalSettings.get_setting("Accessibility", "outline_periodic", false)
		var col_idx: int = GlobalSettings.get_setting("Accessibility", "outline_color_index", 0)
		if col_idx >= 0 and col_idx < OUTLINE_COLOR_VALUES.size():
			_outline_color = OUTLINE_COLOR_VALUES[col_idx]
		_blink_speed = GlobalSettings.get_setting("Accessibility", "outline_blink_speed", 8.0)
		_min_intensity = GlobalSettings.get_setting("Accessibility", "outline_min_intensity", 0.2)
		_max_intensity = GlobalSettings.get_setting("Accessibility", "outline_max_intensity", 1.0)
		_outline_interval = GlobalSettings.get_setting(
			"Accessibility", "outline_interval", DEFAULT_OUTLINE_INTERVAL
		)
		_outline_duration = GlobalSettings.get_setting(
			"Accessibility", "outline_duration", DEFAULT_OUTLINE_DURATION
		)

	if is_instance_valid(_periodic_timer):
		_periodic_timer.wait_time = _outline_interval
		if _periodic_enabled:
			_periodic_timer.start(_outline_interval)

	if is_instance_valid(_duration_timer):
		_duration_timer.wait_time = _outline_duration

	_apply_shader_parameters()
	_refresh_highlight()


## Responds to global outline mode changes and updates highlight meshes.
func _on_outline_mode_changed(mode: int) -> void:
	print("HighlightComponent: Outline mode updated to: ", mode)
	_outline_mode = mode
	_refresh_highlight()


## Responds to global first sight highlight toggle changes.
func _on_outline_first_sight_toggled(enabled: bool) -> void:
	print("HighlightComponent: First sight highlight toggled: ", enabled)
	_first_sight_enabled = enabled
	if enabled and not _has_been_seen:
		set_process(true)
	elif not enabled:
		_is_first_sight_active = false
		_refresh_highlight()


## Responds to global periodic highlight toggle changes.
func _on_outline_periodic_toggled(enabled: bool) -> void:
	print("HighlightComponent: Periodic highlight toggled: ", enabled)
	_periodic_enabled = enabled
	if enabled:
		if is_instance_valid(_periodic_timer):
			_periodic_timer.start(_outline_interval)
	else:
		if is_instance_valid(_periodic_timer) and not _periodic_timer.is_stopped():
			_periodic_timer.stop()
		_is_periodic_active = false
		_refresh_highlight()


## Responds to global outline color changes and updates material.
func _on_outline_color_changed(color: Color) -> void:
	print("HighlightComponent: Outline color updated to: ", color)
	_outline_color = color
	_apply_shader_parameters()


## Responds to global outline blink speed changes.
func _on_outline_blink_speed_changed(speed: float) -> void:
	print("HighlightComponent: Outline blink speed updated to: ", speed)
	_blink_speed = speed
	_apply_shader_parameters()


## Responds to global outline minimum intensity changes.
func _on_outline_min_intensity_changed(intensity: float) -> void:
	print("HighlightComponent: Outline min intensity updated to: ", intensity)
	_min_intensity = intensity
	_apply_shader_parameters()


## Responds to global outline maximum intensity changes.
func _on_outline_max_intensity_changed(intensity: float) -> void:
	print("HighlightComponent: Outline max intensity updated to: ", intensity)
	_max_intensity = intensity
	_apply_shader_parameters()


## Responds to global outline periodic interval changes.
func _on_outline_interval_changed(interval: float) -> void:
	print("HighlightComponent: Outline interval updated to: ", interval)
	_outline_interval = interval
	if is_instance_valid(_periodic_timer):
		_periodic_timer.wait_time = interval
		if _periodic_enabled:
			_periodic_timer.start(interval)


## Responds to global outline pulse duration changes.
func _on_outline_duration_changed(duration: float) -> void:
	print("HighlightComponent: Outline duration updated to: ", duration)
	_outline_duration = duration
	if is_instance_valid(_duration_timer):
		_duration_timer.wait_time = duration


## Applies active outline parameters directly to the [ShaderMaterial].
func _apply_shader_parameters() -> void:
	print("HighlightComponent: Applying outline shader uniforms.")
	if not is_instance_valid(outline_material):
		return

	outline_material.set_shader_parameter("highlight_color", _outline_color)
	outline_material.set_shader_parameter("blink_speed", _blink_speed)
	outline_material.set_shader_parameter("min_intensity", _min_intensity)
	outline_material.set_shader_parameter("max_intensity", _max_intensity)


## Evaluates current focus and mode rules to apply or clear highlights.
func _refresh_highlight() -> void:
	if _is_suppressed:
		_update_materials(null)
		return

	var is_mode_active: bool = false
	match _outline_mode:
		1:
			is_mode_active = true
		2:
			is_mode_active = _is_focused
		_:
			is_mode_active = false

	var is_first_sight: bool = _first_sight_enabled and _is_first_sight_active
	var is_periodic: bool = _periodic_enabled and _is_periodic_active and _is_on_screen

	if is_mode_active or is_first_sight or is_periodic:
		_update_materials(outline_material)
	else:
		_update_materials(null)


## Caches explicitly assigned meshes or discovers them once at startup.
func _cache_target_meshes() -> void:
	print("HighlightComponent: Caching target meshes.")
	_cached_meshes.clear()

	if target_meshes.size() > 0:
		for m: GeometryInstance3D in target_meshes:
			if is_instance_valid(m):
				_cached_meshes.append(m)
		return

	var parent: Node = get_parent()
	if not is_instance_valid(parent):
		return

	var mesh_nodes: Array[Node] = parent.find_children("*", "MeshInstance3D")
	for m: Node in mesh_nodes:
		if is_instance_valid(m) and m is GeometryInstance3D:
			_cached_meshes.append(m as GeometryInstance3D)

	var csg_nodes: Array[Node] = parent.find_children("*", "CSGShape3D")
	for c: Node in csg_nodes:
		if is_instance_valid(c) and c is GeometryInstance3D:
			_cached_meshes.append(c as GeometryInstance3D)


## Callback triggered when the interactable gains player focus.
func _on_focus() -> void:
	print("HighlightComponent: Target actively focused by player.")
	_is_focused = true
	_refresh_highlight()


## Callback triggered when the interactable loses player focus.
func _on_unfocus() -> void:
	print("HighlightComponent: Target unfocused by player.")
	_is_focused = false
	_refresh_highlight()


## Responds to the visibility notifier entering the camera view.
func _on_screen_entered() -> void:
	print("HighlightComponent: Target entered screen view.")
	_is_on_screen = true
	if _first_sight_enabled and not _has_been_seen:
		_has_been_seen = true
		_trigger_first_sight_pulse()
	elif _periodic_enabled and _is_periodic_active:
		_refresh_highlight()


## Responds to the visibility notifier leaving the camera view.
func _on_screen_exited() -> void:
	#print("HighlightComponent: Target exited screen view.")
	_is_on_screen = false
	if _periodic_enabled and _is_periodic_active:
		_refresh_highlight()


## Triggers temporary outline pulse on first visual acquisition.
func _trigger_first_sight_pulse() -> void:
	print("HighlightComponent: Triggering first sight highlight pulse.")
	_is_first_sight_active = true
	_refresh_highlight()
	if is_instance_valid(_duration_timer):
		_duration_timer.start(_outline_duration)


## Responds to temporary highlight duration timer expiration.
func _on_duration_timeout() -> void:
	print("HighlightComponent: Temporary highlight pulse expired.")
	_is_first_sight_active = false
	_is_periodic_active = false
	_refresh_highlight()


## Responds to periodic pulse interval timer expiration.
func _on_periodic_timeout() -> void:
	print("HighlightComponent: Periodic interval tick triggered.")
	if not _periodic_enabled:
		return

	if _is_target_on_screen():
		print("HighlightComponent: Target is visible during tick. Pulsing highlight.")
		_is_on_screen = true
		_is_periodic_active = true
		_refresh_highlight()
		if is_instance_valid(_duration_timer):
			_duration_timer.start(_outline_duration)


## Temporarily suppresses or restores the highlight state.
func suppress(state: bool) -> void:
	print("HighlightComponent: Suppress state set to: ", state)
	_is_suppressed = state
	_refresh_highlight()


## Applies or clears outline material across cached geometry targets.
func _update_materials(mat: Material) -> void:
	for i: int in range(_cached_meshes.size() - 1, -1, -1):
		var m: GeometryInstance3D = _cached_meshes[i]
		if not is_instance_valid(m):
			_cached_meshes.remove_at(i)
			continue
		_apply_to_mesh(m, mat)


## Instantiates or cleans up child overlay nodes on target meshes.
func _apply_to_mesh(base_mesh: GeometryInstance3D, mat: Material) -> void:
	var child_name: String = "HighlightOverlayChild"

	if mat != null:
		print("HighlightComponent: Spawning highlight mesh on: ", base_mesh.name)
		if not base_mesh.has_node(child_name):
			var hl_mesh: MeshInstance3D = MeshInstance3D.new()
			hl_mesh.name = child_name
			hl_mesh.material_override = mat
			hl_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

			var is_flat: bool = false

			if base_mesh is MeshInstance3D:
				var mi: MeshInstance3D = base_mesh
				hl_mesh.mesh = mi.mesh
				if mi.skeleton:
					hl_mesh.skeleton = mi.skeleton
				if mi.skin:
					hl_mesh.skin = mi.skin

				if hl_mesh.mesh is QuadMesh or hl_mesh.mesh is PlaneMesh:
					is_flat = true

			elif base_mesh is CSGShape3D:
				var csg_shape: CSGShape3D = base_mesh
				var csg_data: Array = csg_shape.get_meshes()
				if csg_data.size() == 2:
					if csg_data[0] is Transform3D:
						hl_mesh.transform = csg_data[0]
					if csg_data[1] is Mesh:
						var csg_mesh: Mesh = csg_data[1]
						hl_mesh.mesh = csg_mesh

			base_mesh.add_child.call_deferred(hl_mesh)

			if is_flat:
				hl_mesh.set_instance_shader_parameter("is_billboard", true)
			else:
				hl_mesh.set_instance_shader_parameter("is_billboard", false)

		base_mesh.custom_aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 4.0))
	else:
		var existing_hl: Node = base_mesh.get_node_or_null(child_name)
		if is_instance_valid(existing_hl):
			existing_hl.queue_free()

		base_mesh.custom_aabb = AABB()
