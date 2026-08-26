## Global autoload managing real-time AAA high-contrast silhouette overlays
## across target scene groups.
##
## Hooks into scene loading to recursively apply unshaded flat color materials
## as overlays to all geometry and sprites within designated accessibility groups.
# class_name VisionAssistManager
extends Node

## Named color lookups for console and UI palette selections.
const COLOR_PALETTE: Dictionary[String, Color] = {
	"cyan": Color(0.0, 0.8, 1.0, 1.0),
	"blue": Color(0.0, 0.4, 1.0, 1.0),
	"yellow": Color(1.0, 0.9, 0.0, 1.0),
	"green": Color(0.0, 1.0, 0.2, 1.0),
	"red": Color(1.0, 0.1, 0.1, 1.0),
	"magenta": Color(1.0, 0.0, 1.0, 1.0),
	"white": Color(1.0, 1.0, 1.0, 1.0),
	"black": Color(0.0, 0.0, 0.0, 1.0)
}

## Spatial shader source code for high-contrast stencil overlays.
const OVERLAY_SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled;

uniform vec4 highlight_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D base_texture : hint_default_white, filter_nearest;
uniform float alpha_scissor = 0.5;
uniform bool enable_billboard = false;

void vertex() {
	if (enable_billboard) {
		vec3 scale = vec3(
			length(MODEL_MATRIX[0].xyz),
			length(MODEL_MATRIX[1].xyz),
			length(MODEL_MATRIX[2].xyz)
		);

		mat4 billboard_matrix = mat4(
			normalize(VIEW_MATRIX[0]),
			normalize(VIEW_MATRIX[1]),
			normalize(VIEW_MATRIX[2]),
			MODELVIEW_MATRIX[3]
		);

		billboard_matrix = billboard_matrix * mat4(
			vec4(scale.x, 0.0, 0.0, 0.0),
			vec4(0.0, scale.y, 0.0, 0.0),
			vec4(0.0, 0.0, scale.z, 0.0),
			vec4(0.0, 0.0, 0.0, 1.0)
		);

		MODELVIEW_MATRIX = billboard_matrix;
	}
}

void fragment() {
	float alpha = texture(base_texture, UV).a;
	if (alpha < alpha_scissor) {
		discard;
	}
	ALBEDO = highlight_color.rgb;
}
"""

## Tracks whether vision assist high-contrast silhouettes are currently rendered globally.
var is_active: bool = false

## Current background shading mode applied behind overlays.
var current_mode: String = "aaa_blue"

## Dictionary mapping scene group names to their target outline and fill colors.
var group_colors: Dictionary[String, Color] = {
	"friends": Color(0.0, 0.5, 1.0, 1.0),
	"enemies": Color(1.0, 0.1, 0.1, 1.0),
	"interactables": Color(1.0, 0.9, 0.0, 1.0),
	"traversal": Color(0.0, 1.0, 0.2, 1.0),
	"clues": Color(1.0, 0.0, 1.0, 1.0),
	"cover": Color(1.0, 1.0, 1.0, 1.0)
}

## Caches instantiated unshaded ShaderMaterial instances per group.
var _group_materials: Dictionary[String, ShaderMaterial] = {}

## Base shader resource enforcing solid silhouettes with billboarding support.
var _silhouette_shader: Shader = Shader.new()


## Lifecycle initialization method pre-building materials and connecting event listeners.
func _ready() -> void:
	print("VisionAssistManager: Initializing high contrast systems.")
	_silhouette_shader.code = OVERLAY_SHADER_CODE

	for group_name: String in group_colors.keys():
		_rebuild_material_for_group(group_name)

	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("vision_assist_toggled"):
			events.vision_assist_toggled.connect(_on_vision_assist_toggled)
		if events.has_signal("vision_assist_mode_changed"):
			events.vision_assist_mode_changed.connect(_on_vision_assist_mode_changed)
		if events.has_signal("vision_assist_color_changed"):
			events.vision_assist_color_changed.connect(_on_vision_assist_color_changed)

	get_tree().node_added.connect(_on_scene_node_added)


## Reconstructs and caches the ShaderMaterial associated with a specific group key.
## [param group_name] The target scene group identifier.
func _rebuild_material_for_group(group_name: String) -> void:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = _silhouette_shader
	mat.set_shader_parameter("highlight_color", group_colors[group_name])
	mat.render_priority = 100
	_group_materials[group_name] = mat


## Recursively applies high-contrast silhouette overlays to an isolated diorama hierarchy.
## [param diorama_root] Root [Node] of the diorama scene.
func apply_diorama_overlays(diorama_root: Node) -> void:
	if not is_instance_valid(diorama_root):
		return
	print("VisionAssistManager: Forcing diorama overlays on ", diorama_root.name)
	for group_name: String in _group_materials.keys():
		var mat: ShaderMaterial = _group_materials[group_name]
		var group_nodes: Array[Node] = diorama_root.find_children("*", "", true, false)
		if diorama_root.is_in_group(group_name):
			group_nodes.append(diorama_root)
		for node: Node in group_nodes:
			if node.is_in_group(group_name):
				_apply_overlay_to_meshes(node, true, mat)


## Handles global vision assist toggle events across all registered groups.
## [param toggled_on] Whether high-contrast overlays should be displayed.
func _on_vision_assist_toggled(toggled_on: bool) -> void:
	print("VisionAssistManager: Toggled vision assist state to: ", toggled_on)
	is_active = toggled_on

	for group_name: String in _group_materials.keys():
		var target_material: ShaderMaterial = _group_materials[group_name]
		var nodes: Array[Node] = get_tree().get_nodes_in_group(group_name)
		for node: Node in nodes:
			if _is_node_in_diorama(node):
				_apply_overlay_to_meshes(node, true, target_material)
			else:
				_apply_overlay_to_meshes(node, is_active, target_material)


## Updates background desaturation and tint rendering styles.
## [param mode_name] Key identifier matching the preset style.
func _on_vision_assist_mode_changed(mode_name: String) -> void:
	print("VisionAssistManager: Changing background mode style to: ", mode_name)
	current_mode = mode_name


## Updates the highlight color assigned to a specific group in real-time.
## [param target_group] The group key identifier.
## [param color_name] Named color string from the palette.
func _on_vision_assist_color_changed(target_group: String, color_name: String) -> void:
	var clean_group: String = target_group.to_lower()
	var clean_color: String = color_name.to_lower()

	if not group_colors.has(clean_group) or not COLOR_PALETTE.has(clean_color):
		push_warning("VisionAssistManager: Invalid group or color passed: " + clean_color)
		return

	print("VisionAssistManager: Updating color for [", clean_group, "] -> ", clean_color)
	group_colors[clean_group] = COLOR_PALETTE[clean_color]
	_rebuild_material_for_group(clean_group)

	var target_material: ShaderMaterial = _group_materials[clean_group]
	for node: Node in get_tree().get_nodes_in_group(clean_group):
		if is_active or _is_node_in_diorama(node):
			_apply_overlay_to_meshes(node, true, target_material)


## Applies overlays immediately to newly spawned nodes belonging to configured groups.
## [param node] The newly added [Node] instance.
func _on_scene_node_added(node: Node) -> void:
	if not node.is_node_ready():
		await node.ready

	var in_diorama: bool = _is_node_in_diorama(node)
	if not is_active and not in_diorama:
		return

	for group_name: String in _group_materials.keys():
		if node.is_in_group(group_name):
			print("VisionAssistManager: Applying overlay to spawned node: ", node.name)
			_apply_overlay_to_meshes(node, true, _group_materials[group_name])
			break


## Evaluates whether a given node is situated within the diorama preview viewport.
## [param node] Target [Node] to evaluate.
## [return] `true` if the node resides within a SubViewport or Diorama tree.
func _is_node_in_diorama(node: Node) -> bool:
	var current: Node = node
	while is_instance_valid(current):
		if current is SubViewport or current.name == "FastDioramaMap":
			return true
		current = current.get_parent()
	return false


## Recursively sets or removes stencil materials on geometry and sprite instances.
## [param target_node] Target [Node] to process.
## [param active_state] Flag indicating if overlay should be applied or cleared.
## [param target_material] [ShaderMaterial] instance configured for the group.
func _apply_overlay_to_meshes(
	target_node: Node, active_state: bool, target_material: ShaderMaterial
) -> void:
	if target_node is GeometryInstance3D:
		if active_state:
			var final_mat: ShaderMaterial = target_material
			var base_tex: Texture2D = null
			var needs_billboard: bool = false

			if target_node is Sprite3D:
				var sprite: Sprite3D = target_node as Sprite3D
				base_tex = sprite.texture
				needs_billboard = (sprite.billboard != BaseMaterial3D.BILLBOARD_DISABLED)
			elif target_node is MeshInstance3D:
				var mesh_inst: MeshInstance3D = target_node as MeshInstance3D
				if mesh_inst.mesh:
					var active_mat: Material = mesh_inst.get_active_material(0)
					if is_instance_valid(active_mat):
						if "albedo_texture" in active_mat:
							base_tex = active_mat.get("albedo_texture") as Texture2D
						if "billboard_mode" in active_mat:
							needs_billboard = (
								active_mat.get("billboard_mode")
								!= BaseMaterial3D.BILLBOARD_DISABLED
							)

			if is_instance_valid(base_tex) or needs_billboard:
				final_mat = target_material.duplicate() as ShaderMaterial
				if is_instance_valid(base_tex):
					final_mat.set_shader_parameter("base_texture", base_tex)
				final_mat.set_shader_parameter("enable_billboard", needs_billboard)

			target_node.material_overlay = final_mat
		else:
			target_node.material_overlay = null

	for child: Node in target_node.get_children(true):
		_apply_overlay_to_meshes(child, active_state, target_material)
