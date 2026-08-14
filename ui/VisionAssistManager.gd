extends Node

## Dictionary mapping scene group names to their required high-contrast colors.
var _group_colors: Dictionary = {
	#"player": Color(0.0, 0.0, 1.0, 1.0),
	"enemies": Color(1.0, 0.0, 0.0, 1.0),
	"interactables": Color(1.0, 1.0, 0.0, 1.0),
	"traversal": Color(0.0, 1.0, 0.0, 1.0)
}

## Caches the instantiated unshaded materials so they are only created once at startup.
var _group_materials: Dictionary = {}

## Tracks the current active state so dynamically spawned objects can be highlighted instantly.
var is_active: bool = false

## Base shader used to enforce solid silhouettes while respecting alpha cutouts and billboarding.
var _silhouette_shader: Shader = Shader.new()

## The upgraded shader logic now includes a toggle for vertex instructions
## to conditionally billboard the overlay.
const OVERLAY_SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled;

uniform vec4 highlight_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D base_texture : hint_default_white, filter_nearest;
uniform float alpha_scissor = 0.5;
uniform bool enable_billboard = false;

void vertex() {
    if (enable_billboard) {
        // --- MANUAL BILLBOARD LOGIC (XY-Lock) ---
        vec3 scale = vec3(
            length(MODEL_MATRIX[0].xyz),
            length(MODEL_MATRIX[1].xyz),
            length(MODEL_MATRIX[2].xyz)
        );

        // Reconstruct the MODELVIEW_MATRIX so its rotation is aligned with the view matrix.
        mat4 billboard_matrix = mat4(
            normalize(VIEW_MATRIX[0]),
            normalize(VIEW_MATRIX[1]),
            normalize(VIEW_MATRIX[2]),
            MODELVIEW_MATRIX[3]
        );

        // Apply the extracted scale to the reconstructed matrix
        billboard_matrix = billboard_matrix * mat4(
            vec4(scale.x, 0.0, 0.0, 0.0),
            vec4(0.0, scale.y, 0.0, 0.0),
            vec4(0.0, 0.0, scale.z, 0.0),
            vec4(0.0, 0.0, 0.0, 1.0)
        );

        // Apply the final billboarding matrix to the vertex data
        MODELVIEW_MATRIX = billboard_matrix;
    }
}

void fragment() {
    // Calculate the base alpha from the provided texture
    float alpha = texture(base_texture, UV).a;

    // Discard transparent pixels to create the perfect silhouette
    if (alpha < alpha_scissor) {
        discard;
    }
    // Set the solid high-contrast color
    ALBEDO = highlight_color.rgb;
}
"""


func _ready() -> void:
	print("VisionAssistManager: Initializing AAA high contrast materials.")
	_silhouette_shader.code = OVERLAY_SHADER_CODE

	# Pre-generate ShaderMaterials for 60 FPS performance
	for group_name: String in _group_colors.keys():
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = _silhouette_shader
		mat.set_shader_parameter("highlight_color", _group_colors[group_name])
		mat.render_priority = 100
		_group_materials[group_name] = mat

	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("vision_assist_toggled"):
			events.vision_assist_toggled.connect(_on_vision_assist_toggled)

	# Listen for newly instantiated scenes
	get_tree().node_added.connect(_on_scene_node_added)


func _on_vision_assist_toggled(toggled_on: bool) -> void:
	print("VisionAssistManager: Applying AAA overlays across all groups. Active: ", toggled_on)
	is_active = toggled_on

	for group_name: String in _group_materials.keys():
		var target_material: ShaderMaterial = _group_materials[group_name] as ShaderMaterial
		var nodes: Array[Node] = get_tree().get_nodes_in_group(group_name)

		for node: Node in nodes:
			_apply_overlay_to_meshes(node, is_active, target_material)


func _on_scene_node_added(node: Node) -> void:
	if not is_active:
		return

	if not node.is_node_ready():
		await node.ready

	if not is_active:
		return

	for group_name: String in _group_materials.keys():
		if node.is_in_group(group_name):
			print("VisionAssistManager: Applying overlay to dynamically spawned node: ", node.name)
			_apply_overlay_to_meshes(node, true, _group_materials[group_name] as ShaderMaterial)
			break


func _apply_overlay_to_meshes(
	target_node: Node, active_state: bool, target_material: ShaderMaterial
) -> void:
	if target_node is GeometryInstance3D:
		if active_state:
			var final_mat: ShaderMaterial = target_material
			var base_tex: Texture2D = null
			var needs_billboard: bool = false

			# Detect textures and billboard settings on Sprite3D or standard meshes
			if target_node is Sprite3D:
				base_tex = target_node.texture
				needs_billboard = (target_node.billboard != BaseMaterial3D.BILLBOARD_DISABLED)
			elif target_node is MeshInstance3D and target_node.mesh:
				var active_mat: Material = target_node.get_active_material(0)
				if is_instance_valid(active_mat) -> void:
					if "albedo_texture" in active_mat:
						base_tex = active_mat.get("albedo_texture") as Texture2D
					if "billboard_mode" in active_mat:
						needs_billboard = (
							active_mat.get("billboard_mode") != BaseMaterial3D.BILLBOARD_DISABLED
						)

			# Inject texture for alpha testing and set billboarding state
			if is_instance_valid(base_tex) or needs_billboard:
				final_mat = target_material.duplicate() as ShaderMaterial

				if is_instance_valid(base_tex):
					final_mat.set_shader_parameter("base_texture", base_tex)

				final_mat.set_shader_parameter("enable_billboard", needs_billboard)

			target_node.material_overlay = final_mat
			print(
				"VisionAssistManager: Applied overlay to ",
				target_node.name,
				" | Billboard: ",
				needs_billboard
			)
		else:
			target_node.material_overlay = null
			print("VisionAssistManager: Removed overlay from ", target_node.name)

	# Recurse through ALL children, including internal nodes
	for child: Node in target_node.get_children(true):
		_apply_overlay_to_meshes(child, active_state, target_material)
