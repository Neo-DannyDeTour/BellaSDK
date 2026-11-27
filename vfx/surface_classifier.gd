## Static material and node classifier mapping physics colliders to [enum SurfaceType].
class_name SurfaceClassifier
extends Object

## Supported physical surface categories for impact decals, dust, debris, and sparks.
enum SurfaceType {
	CONCRETE,
	WOOD,
	METAL,
	DIRT,
	GLASS,
}

## Explicit node group mappings checked on collider and its parent.
const GROUP_SURFACE_MAP: Dictionary[StringName, SurfaceType] = {
	&"wood": SurfaceType.WOOD,
	&"metal": SurfaceType.METAL,
	&"concrete": SurfaceType.CONCRETE,
	&"stone": SurfaceType.CONCRETE,
	&"brick": SurfaceType.CONCRETE,
	&"dirt": SurfaceType.DIRT,
	&"soil": SurfaceType.DIRT,
	&"wet_dirt": SurfaceType.DIRT,
	&"glass": SurfaceType.GLASS,
}

## Metadata key inspected on collider or parent for explicit surface overrides.
const META_SURFACE_TYPE: StringName = &"surface_type"

## Primary material keywords matched before generic prop/architecture nouns.
const PRIMARY_KEYWORD_MAP: Dictionary[String, SurfaceType] = {
	"wood": SurfaceType.WOOD,
	"plank": SurfaceType.WOOD,
	"timber": SurfaceType.WOOD,
	"chipwood": SurfaceType.WOOD,
	"osb": SurfaceType.WOOD,
	"sheet_metal": SurfaceType.METAL,
	"metal": SurfaceType.METAL,
	"steel": SurfaceType.METAL,
	"iron": SurfaceType.METAL,
	"wet_dirt": SurfaceType.DIRT,
	"dirt": SurfaceType.DIRT,
	"mud": SurfaceType.DIRT,
	"soil": SurfaceType.DIRT,
	"earth": SurfaceType.DIRT,
	"grass": SurfaceType.DIRT,
	"sand": SurfaceType.DIRT,
	"glass": SurfaceType.GLASS,
	"concrete": SurfaceType.CONCRETE,
	"stone": SurfaceType.CONCRETE,
	"brick": SurfaceType.CONCRETE,
	"plaster": SurfaceType.CONCRETE,
	"cement": SurfaceType.CONCRETE,
}

## Secondary prop and architecture nouns matched when no material keyword matches.
const FALLBACK_KEYWORD_MAP: Dictionary[String, SurfaceType] = {
	"crate": SurfaceType.WOOD,
	"grille": SurfaceType.METAL,
	"pipe": SurfaceType.METAL,
	"ladder": SurfaceType.METAL,
	"window": SurfaceType.GLASS,
	"pane": SurfaceType.GLASS,
	"wall": SurfaceType.CONCRETE,
}


## Classifies [param collider] using groups, metadata, materials, and node names.
static func classify(collider: Object) -> SurfaceType:
	if not is_instance_valid(collider) or not (collider is Node):
		return SurfaceType.CONCRETE

	var node: Node = collider as Node
	var parent: Node = node.get_parent()

	var group_hit: int = _classify_node_groups(node)
	if group_hit >= 0:
		return group_hit as SurfaceType
	if is_instance_valid(parent):
		var parent_group_hit: int = _classify_node_groups(parent)
		if parent_group_hit >= 0:
			return parent_group_hit as SurfaceType

	var meta_hit: int = _classify_node_metadata(node)
	if meta_hit >= 0:
		return meta_hit as SurfaceType
	if is_instance_valid(parent):
		var parent_meta_hit: int = _classify_node_metadata(parent)
		if parent_meta_hit >= 0:
			return parent_meta_hit as SurfaceType

	var mat_hit: int = _classify_attached_materials(node, parent)
	if mat_hit >= 0:
		return mat_hit as SurfaceType

	var node_name_hit: int = _classify_text(String(node.name).to_lower())
	if node_name_hit >= 0:
		return node_name_hit as SurfaceType
	if is_instance_valid(parent):
		var parent_name_hit: int = _classify_text(String(parent.name).to_lower())
		if parent_name_hit >= 0:
			return parent_name_hit as SurfaceType

	return SurfaceType.CONCRETE


## Checks [member GROUP_SURFACE_MAP] against [param node], returning -1 if unmatched.
static func _classify_node_groups(node: Node) -> int:
	for group_name: StringName in GROUP_SURFACE_MAP:
		if node.is_in_group(group_name):
			var surface: SurfaceType = GROUP_SURFACE_MAP[group_name]
			return int(surface)
	return -1


## Reads [constant META_SURFACE_TYPE] from [param node] using strict Variant narrowing.
static func _classify_node_metadata(node: Node) -> int:
	if not node.has_meta(META_SURFACE_TYPE):
		return -1
	var raw_val: Variant = node.get_meta(META_SURFACE_TYPE)
	if raw_val is int:
		var idx: int = raw_val if raw_val is int else -1
		if idx >= int(SurfaceType.CONCRETE) and idx <= int(SurfaceType.GLASS):
			return idx
		return -1
	if raw_val is String:
		var text_val: String = raw_val if raw_val is String else ""
		return _classify_text(text_val.strip_edges().to_lower())
	if raw_val is StringName:
		var sn_val: StringName = raw_val if raw_val is StringName else &""
		return _classify_text(String(sn_val).strip_edges().to_lower())
	return -1


## Checks material paths on [param node], its child meshes, and sibling meshes under [param parent].
static func _classify_attached_materials(node: Node, parent: Node) -> int:
	if node is MeshInstance3D:
		var self_hit: int = _classify_mesh_instance(node as MeshInstance3D)
		if self_hit >= 0:
			return self_hit
	elif node is CSGShape3D:
		var raw_mat: Variant = node.get(&"material")
		if raw_mat is Material:
			var csg_hit: int = _classify_material(raw_mat as Material)
			if csg_hit >= 0:
				return csg_hit

	for child: Node in node.get_children():
		if child is MeshInstance3D:
			var child_hit: int = _classify_mesh_instance(child as MeshInstance3D)
			if child_hit >= 0:
				return child_hit

	if is_instance_valid(parent):
		if parent is MeshInstance3D:
			var parent_mesh_hit: int = _classify_mesh_instance(parent as MeshInstance3D)
			if parent_mesh_hit >= 0:
				return parent_mesh_hit
		for sibling: Node in parent.get_children():
			if sibling != node and sibling is MeshInstance3D:
				var sibling_hit: int = _classify_mesh_instance(sibling as MeshInstance3D)
				if sibling_hit >= 0:
					return sibling_hit
	return -1


## Inspects [member MeshInstance3D.material_override] and surface materials for path keywords.
static func _classify_mesh_instance(mesh_inst: MeshInstance3D) -> int:
	if is_instance_valid(mesh_inst.material_override):
		var override_hit: int = _classify_material(mesh_inst.material_override)
		if override_hit >= 0:
			return override_hit

	var mesh: Mesh = mesh_inst.mesh
	if is_instance_valid(mesh):
		var surface_count: int = mesh.get_surface_count()
		for surf_idx: int in range(surface_count):
			var surf_override: Material = mesh_inst.get_surface_override_material(surf_idx)
			if is_instance_valid(surf_override):
				var surf_override_hit: int = _classify_material(surf_override)
				if surf_override_hit >= 0:
					return surf_override_hit
			var surf_mat: Material = mesh.surface_get_material(surf_idx)
			if is_instance_valid(surf_mat):
				var surf_mat_hit: int = _classify_material(surf_mat)
				if surf_mat_hit >= 0:
					return surf_mat_hit
	return -1


## Matches [member Resource.resource_path] on [param mat] against surface keywords.
static func _classify_material(mat: Material) -> int:
	if not is_instance_valid(mat) or mat.resource_path.is_empty():
		return -1
	return _classify_text(mat.resource_path.to_lower())


## Matches lowercased [param text] against primary material terms then prop fallback nouns.
static func _classify_text(text: String) -> int:
	if text.is_empty():
		return -1
	for keyword: String in PRIMARY_KEYWORD_MAP:
		if text.contains(keyword):
			var surface: SurfaceType = PRIMARY_KEYWORD_MAP[keyword]
			return int(surface)
	for fallback_kw: String in FALLBACK_KEYWORD_MAP:
		if text.contains(fallback_kw):
			var fallback_surface: SurfaceType = FALLBACK_KEYWORD_MAP[fallback_kw]
			return int(fallback_surface)
	return -1
