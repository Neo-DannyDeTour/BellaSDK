## Global manager handling real-time high-contrast silhouette overlays across target groups.
## Coordinates scene trees and applies unshaded stencil materials to accessibility objects.
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

## Tracks whether vision assist high-contrast silhouettes are rendered globally.
var is_active: bool = false

## Tracks whether diorama preview silhouette overlays are explicitly enabled.
var diorama_preview_active: bool = false

## Current background shading mode applied behind overlays.
var current_mode: String = "aaa_blue"

## Dictionary mapping scene group names to target outline and fill colors.
var group_colors: Dictionary[String, Color] = {
	"friends": Color(0.0, 0.5, 1.0, 1.0),
	"enemies": Color(1.0, 0.1, 0.1, 1.0),
	"interactables": Color(1.0, 0.9, 0.0, 1.0),
	"traversal": Color(0.0, 1.0, 0.2, 1.0),
	"clues": Color(1.0, 0.0, 1.0, 1.0),
	"cover": Color(1.0, 1.0, 1.0, 1.0)
}

## Caches instantiated unshaded [ShaderMaterial] instances per group.
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
			events.connect("vision_assist_toggled", _on_vision_assist_toggled)
		if events.has_signal("vision_assist_mode_changed"):
			events.connect("vision_assist_mode_changed", _on_vision_assist_mode_changed)
		if events.has_signal("vision_assist_color_changed"):
			events.connect("vision_assist_color_changed", _on_vision_assist_color_changed)

	Utilities.safe_connect(get_tree().node_added, _on_scene_node_added)


## Reconstructs and caches the [ShaderMaterial] associated with a group key.
func _rebuild_material_for_group(group_name: String) -> void:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = _silhouette_shader
	mat.set_shader_parameter("highlight_color", group_colors[group_name])
	mat.render_priority = 100
	_group_materials[group_name] = mat
	print("VisionAssistManager: Rebuilt material for group -> ", group_name)


## Controls whether silhouette overlays render in the diorama viewport.
func set_diorama_overlays_active(diorama_root: Node, active: bool) -> void:
	if not is_instance_valid(diorama_root):
		return
	print("VisionAssistManager: Updating diorama overlays state to: ", active)
	diorama_preview_active = active
	for group_name: String in _group_materials.keys():
		var mat: ShaderMaterial = _group_materials[group_name]
		var group_nodes: Array[Node] = diorama_root.find_children("*", "", true, false)
		if diorama_root.is_in_group(group_name):
			group_nodes.append(diorama_root)
		for node: Node in group_nodes:
			if node.is_in_group(group_name):
				_apply_overlay_to_meshes(node, active, mat)


## Recursively applies high-contrast silhouette overlays to diorama scenes.
func apply_diorama_overlays(diorama_root: Node) -> void:
	set_diorama_overlays_active(diorama_root, diorama_preview_active)


## Handles global vision assist toggle events across all registered groups.
func _on_vision_assist_toggled(toggled_on: bool) -> void:
	if is_active == toggled_on:
		return

	print("VisionAssistManager: Toggled vision assist state to: ", toggled_on)
	is_active = toggled_on

	var tree: SceneTree = get_tree()
	if not tree:
		return

	for group_name: String in _group_materials.keys():
		var target_material: ShaderMaterial = _group_materials[group_name]
		var nodes: Array[Node] = tree.get_nodes_in_group(group_name)
		for node: Node in nodes:
			var active_state: bool = (
				diorama_preview_active if _is_node_in_diorama(node) else is_active
			)
			_apply_overlay_to_meshes(node, active_state, target_material)


## Updates background desaturation and tint rendering styles.
func _on_vision_assist_mode_changed(mode_name: String) -> void:
	print("VisionAssistManager: Changing background mode style to: ", mode_name)
	current_mode = mode_name


## Updates the highlight color assigned to a specific group in real-time.
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
		var active_state: bool = diorama_preview_active if _is_node_in_diorama(node) else is_active
		_apply_overlay_to_meshes(node, active_state, target_material)


## Applies overlays immediately to newly spawned nodes belonging to groups.
func _on_scene_node_added(node: Node) -> void:
	if not is_active and not diorama_preview_active:
		return

	if not node.is_node_ready():
		await node.ready

	if not is_instance_valid(node):
		return

	var in_diorama: bool = _is_node_in_diorama(node)
	var active_state: bool = diorama_preview_active if in_diorama else is_active
	if not active_state:
		return

	for group_name: String in _group_materials.keys():
		if node.is_in_group(group_name):
			print("VisionAssistManager: Applying overlay to spawned node: ", node.name)
			_apply_overlay_to_meshes(node, true, _group_materials[group_name])
			break


## Evaluates whether a given node is situated within a diorama preview.
func _is_node_in_diorama(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if NodeQuery.find_ancestor_of_type(node, SubViewport) != null:
		return true
	return NodeQuery.find_ancestor_with_meta(node, &"is_diorama") != null


## Recursively sets or removes stencil materials via [MaterialCache].
func _apply_overlay_to_meshes(
	target_node: Node, active_state: bool, target_material: ShaderMaterial
) -> void:
	if not is_instance_valid(target_node):
		return

	if target_node is GeometryInstance3D:
		var geom_node: GeometryInstance3D = target_node
		if active_state:
			var final_mat: ShaderMaterial = target_material
			var base_tex: Texture2D = null
			var needs_billboard: bool = false

			if geom_node is Sprite3D:
				var sprite: Sprite3D = geom_node
				base_tex = sprite.texture
				needs_billboard = (sprite.billboard != BaseMaterial3D.BILLBOARD_DISABLED)
			elif geom_node is MeshInstance3D:
				var mesh_inst: MeshInstance3D = geom_node
				if mesh_inst.mesh:
					var active_mat: Material = mesh_inst.get_active_material(0)
					if active_mat is BaseMaterial3D:
						var base_mat: BaseMaterial3D = active_mat
						base_tex = base_mat.albedo_texture
						needs_billboard = (
							base_mat.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED
						)

			if is_instance_valid(base_tex) or needs_billboard:
				var base_id: int = 0
				if is_instance_valid(base_tex):
					base_id = base_tex.get_instance_id()
				var var_key: String = "%d_%s" % [base_id, str(needs_billboard)]
				var cached_var: Variant = MaterialCache.get_variant(target_material, var_key)
				if cached_var is ShaderMaterial:
					var cached_mat: ShaderMaterial = cached_var
					final_mat = cached_mat
				if is_instance_valid(base_tex):
					final_mat.set_shader_parameter("base_texture", base_tex)
				final_mat.set_shader_parameter("enable_billboard", needs_billboard)

			geom_node.material_overlay = final_mat
		else:
			geom_node.material_overlay = null

	for child: Node in target_node.get_children(true):
		_apply_overlay_to_meshes(child, active_state, target_material)
