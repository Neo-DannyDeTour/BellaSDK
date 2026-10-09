## Applies an outline material to target meshes when the parent interactable is focused.
##
## Caches visual geometry in [method _ready] to avoid recursive tree walks during interactions.
class_name HighlightComponent
extends Node

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

## The shader material applied as an outline when the target is focused.
@export var outline_material: ShaderMaterial

## Array of specific meshes to highlight. Leave empty to auto-detect nodes.
@export var target_meshes: Array[GeometryInstance3D]

## The component handling interaction logic. Assign in inspector for performance.
@export var interact_component: Node

## Tracks whether the current target is actively focused by the player.
var _is_focused: bool = false

## Tracks whether the highlight effect is temporarily disabled or overridden.
var _is_suppressed: bool = false

## Cached geometry instances to prevent expensive runtime tree traversals.
var _cached_meshes: Array[GeometryInstance3D] = []

## Outline rendering mode: 0 is Off, 1 is Always, 2 is On Focus.
var _outline_mode: int = 2

## Active highlight outline color vector.
var _outline_color: Color = Color(0.0, 1.0, 0.5, 1.0)

## Active highlight oscillation pulse speed.
var _blink_speed: float = 8.0

## Active highlight minimum pulse intensity clamp.
var _min_intensity: float = 0.2

## Active highlight maximum pulse intensity clamp.
var _max_intensity: float = 1.0


## Initializes component connections and caches all target meshes for runtime.
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
	_connect_outline_events()
	_load_initial_settings()


## Subscribes to global outline signals from the event bus.
func _connect_outline_events() -> void:
	print("HighlightComponent: Binding outline event listeners.")
	if not is_instance_valid(Events):
		return

	if Events.has_signal(&"outline_mode_changed"):
		if not Events.outline_mode_changed.is_connected(_on_outline_mode_changed):
			Events.outline_mode_changed.connect(_on_outline_mode_changed)

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


## Reads initial outline configuration from [GlobalSettings] and syncs material uniforms.
func _load_initial_settings() -> void:
	print("HighlightComponent: Loading initial outline settings.")
	if is_instance_valid(GlobalSettings):
		_outline_mode = GlobalSettings.get_setting("Accessibility", "outline_mode", 2)
		var col_idx: int = GlobalSettings.get_setting("Accessibility", "outline_color_index", 0)
		if col_idx >= 0 and col_idx < OUTLINE_COLOR_VALUES.size():
			_outline_color = OUTLINE_COLOR_VALUES[col_idx]
		_blink_speed = GlobalSettings.get_setting("Accessibility", "outline_blink_speed", 8.0)
		_min_intensity = GlobalSettings.get_setting("Accessibility", "outline_min_intensity", 0.2)
		_max_intensity = GlobalSettings.get_setting("Accessibility", "outline_max_intensity", 1.0)

	_apply_shader_parameters()
	_refresh_highlight()


## Responds to global outline mode changes and updates highlight meshes.
## [param mode] Target outline render mode index.
func _on_outline_mode_changed(mode: int) -> void:
	print("HighlightComponent: Outline mode updated to: ", mode)
	_outline_mode = mode
	_refresh_highlight()


## Responds to global outline color changes and updates material.
## [param color] Target outline tint color.
func _on_outline_color_changed(color: Color) -> void:
	print("HighlightComponent: Outline color updated to: ", color)
	_outline_color = color
	_apply_shader_parameters()


## Responds to global outline blink speed changes.
## [param speed] Pulse frequency rate in hertz.
func _on_outline_blink_speed_changed(speed: float) -> void:
	print("HighlightComponent: Outline blink speed updated to: ", speed)
	_blink_speed = speed
	_apply_shader_parameters()


## Responds to global outline minimum intensity changes.
## [param intensity] Lower clamp limit for pulse opacity.
func _on_outline_min_intensity_changed(intensity: float) -> void:
	print("HighlightComponent: Outline min intensity updated to: ", intensity)
	_min_intensity = intensity
	_apply_shader_parameters()


## Responds to global outline maximum intensity changes.
## [param intensity] Upper clamp limit for pulse opacity.
func _on_outline_max_intensity_changed(intensity: float) -> void:
	print("HighlightComponent: Outline max intensity updated to: ", intensity)
	_max_intensity = intensity
	_apply_shader_parameters()


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
	#print("HighlightComponent: Refreshing highlight display.")
	if _is_suppressed or _outline_mode == 0:
		_update_materials(null)
		return

	if _outline_mode == 1:
		_update_materials(outline_material)
	elif _outline_mode == 2:
		_update_materials(outline_material if _is_focused else null)


## Caches explicitly assigned meshes or discovers them once during initialization.
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


## Temporarily suppresses or restores the highlight state based on game events.
## [param state] Whether outline rendering is suppressed.
func suppress(state: bool) -> void:
	print("HighlightComponent: Suppress state set to: ", state)
	_is_suppressed = state
	_refresh_highlight()


## Applies or clears the outline material across all cached geometry targets.
## [param mat] The highlight material to apply, or null to clear.
func _update_materials(mat: Material) -> void:
	for i: int in range(_cached_meshes.size() - 1, -1, -1):
		var m: GeometryInstance3D = _cached_meshes[i]
		if not is_instance_valid(m):
			_cached_meshes.remove_at(i)
			continue
		_apply_to_mesh(m, mat)


## Instantiates or cleans up child overlay nodes and updates bounds on target mesh.
## [param base_mesh] The target geometry node receiving the outline.
## [param mat] The material applied to the overlay mesh.
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

			base_mesh.add_child(hl_mesh)

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
