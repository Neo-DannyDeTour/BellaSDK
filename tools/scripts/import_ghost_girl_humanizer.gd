## Headless importer compiling GhostGirl MakeHuman exports into Godot Humanizer assets.
extends SceneTree

## Source directory containing @modeler's GhostGirl Humanizer exports.
const EXPORT_ROOT: String = "res://assets/models/ghost_girl/humanizer_export"
## Path to Humanizer's canonical MakeHuman basis vertex array.
const BASIS_PATH: String = "res://addons/humanizer/data/resources/basis.data"
## Destination file for compiled GhostGirl target deltas.
const TARGET_OUT_PATH: String = "res://humanizer/target/GhostGirl_Targets.data"
## Target key registered in [HumanizerTargetService].
const TARGET_KEY: String = "custom_ghost_girl_anime"
## Destination folder for compiled GhostGirl Humanizer equipment resources.
const EQUIP_OUT_ROOT: String = "res://humanizer/equipment"
## Destination folder for compiled GhostGirl Humanizer material resources.
const MAT_OUT_ROOT: String = "res://humanizer/material"
## Skin material name registered under Body-Default.
const SKIN_MAT_NAME: String = "ghost_girl_anime_skin"
## Target basis vertex index at the crown of the head (used for orientation checks).
const HEAD_TOP_VID: int = 14570
## Target basis vertex index at the left foot sole.
const FOOT_VID: int = 15500
## Target basis vertex index at the nose/face front (+Z check).
const FACE_FRONT_VID: int = 0
## Default skin fallback color (soft peach-fair anime tone) if no skin PNG is exported.
const DEFAULT_SKIN_COLOR: Color = Color(0.99, 0.87, 0.80, 1.0)

## Non-colliding Humanizer slot assignments per GhostGirl equipment ID.
const EQUIP_SLOTS: Dictionary[String, Array] = {
	"GhostGirl_Hair_Cards": ["hair"],
	"GhostGirl_Hood": ["headclothes"],
	"GhostGirl_Cape": ["armsclothes"],
	"GhostGirl_CropTop": ["torsoclothes"],
	"GhostGirl_Skirt": ["legsclothes"],
	"GhostGirl_Gloves": ["handsclothes"],
	"GhostGirl_Boots": ["feetclothes"],
	"GhostGirl_Eye_L": ["lefteye"],
	"GhostGirl_Eye_R": ["righteye"],
	"GhostGirl_Eyelashes": ["lefteyelash", "righteyelash"],
	"GhostGirl_Eyelashes_L": ["lefteyelash"],
	"GhostGirl_Eyelashes_R": ["righteyelash"],
	"GhostGirl_Hair_Cap": ["eyesclothes"],
	"GhostGirl_Teeth_Upper": ["teeth"],
	"GhostGirl_Tongue": ["tongue"],
}

## Cached MakeHuman basis vertex coordinates loaded from [constant BASIS_PATH].
var _basis: PackedVector3Array = PackedVector3Array()


## Schedules import execution after autoloads (including [HumanizerAPI]) finish init.
func _initialize() -> void:
	call_deferred("_run_import_pipeline")


## Runs target compilation, equipment/material generation, and Humanizer smoke test.
func _run_import_pipeline() -> void:
	print("GhostGirlHumanizerImporter: Starting import from ", EXPORT_ROOT)
	if not _load_basis():
		quit(1)
		return

	if not _import_target():
		quit(1)
		return

	var imported_ids: Array[String] = _import_all_equipment()
	if imported_ids.is_empty():
		printerr("GhostGirlHumanizerImporter: No equipment folders imported from ", EXPORT_ROOT)
		quit(1)
		return

	if not _import_skin_material():
		quit(1)
		return

	var smoke_ok: bool = await _run_smoke_check(imported_ids)
	if not smoke_ok:
		quit(1)
		return

	print("GhostGirlHumanizerImporter: Import and smoke check PASSED (", imported_ids.size(), ")")
	quit(0)


## Loads and validates MakeHuman canonical basis vertices from [constant BASIS_PATH].
func _load_basis() -> bool:
	var basis_file: FileAccess = FileAccess.open(BASIS_PATH, FileAccess.READ)
	if basis_file == null:
		printerr("GhostGirlHumanizerImporter: Missing basis file at ", BASIS_PATH)
		return false
	var raw_basis: Variant = basis_file.get_var()
	if not (raw_basis is PackedVector3Array):
		printerr("GhostGirlHumanizerImporter: basis.data is not PackedVector3Array.")
		return false
	_basis = raw_basis as PackedVector3Array
	if _basis.is_empty():
		printerr("GhostGirlHumanizerImporter: basis.data is empty.")
		return false
	print("GhostGirlHumanizerImporter: Loaded basis vertices = ", _basis.size())
	return true


## Imports ghost_girl_anime.target with export_meta.json validation to GhostGirl_Targets.data.
func _import_target() -> bool:
	var target_path: String = EXPORT_ROOT.path_join("ghost_girl_anime.target")
	var meta_path: String = EXPORT_ROOT.path_join("export_meta.json")
	if not FileAccess.file_exists(target_path):
		printerr("GhostGirlHumanizerImporter: Missing target file ", target_path)
		return false

	var unit_scale: float = _resolve_target_unit_scale(meta_path)
	if unit_scale <= 0.0:
		return false

	var tar_file: FileAccess = FileAccess.open(target_path, FileAccess.READ)
	if tar_file == null:
		printerr("GhostGirlHumanizerImporter: Failed to open ", target_path)
		return false

	var deltas: PackedVector4Array = PackedVector4Array()
	var morphed: PackedVector3Array = _basis.duplicate()
	var max_delta_mag: float = 0.0

	while tar_file.get_position() < tar_file.get_length():
		var line: String = tar_file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts: PackedStringArray = line.split(" ", false)
		if parts.size() != 4 or not parts[0].is_valid_int():
			printerr("GhostGirlHumanizerImporter: Invalid target line: ", line)
			return false
		var vid: int = int(parts[0])
		if vid < 0 or vid >= _basis.size():
			printerr("GhostGirlHumanizerImporter: Out-of-range vid ", vid, " / ", _basis.size())
			return false
		var dx: float = float(parts[1]) * unit_scale
		var dy: float = float(parts[2]) * unit_scale
		var dz: float = float(parts[3]) * unit_scale
		var delta_vec: Vector3 = Vector3(dx, dy, dz)
		max_delta_mag = maxf(max_delta_mag, delta_vec.length())
		morphed[vid] = morphed[vid] + delta_vec
		deltas.append(Vector4(dx, dy, dz, float(vid)))

	if deltas.is_empty():
		printerr("GhostGirlHumanizerImporter: Target file had 0 vertex deltas.")
		return false

	if not _validate_morphed_pose(morphed, max_delta_mag):
		return false

	var target_dir: String = TARGET_OUT_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(target_dir):
		DirAccess.make_dir_recursive_absolute(target_dir)

	var out_dict: Dictionary[String, PackedVector4Array] = {}
	out_dict[TARGET_KEY] = deltas
	var out_file: FileAccess = FileAccess.open(TARGET_OUT_PATH, FileAccess.WRITE)
	if out_file == null:
		printerr("GhostGirlHumanizerImporter: Cannot write ", TARGET_OUT_PATH)
		return false
	out_file.store_var(out_dict)
	print(
		"GhostGirlHumanizerImporter: Saved ",
		TARGET_OUT_PATH,
		" deltas=",
		deltas.size(),
		" scale=",
		unit_scale
	)
	return true


## Resolves target delta scale from export_meta.json against basis.data Y bounds.
func _resolve_target_unit_scale(meta_path: String) -> float:
	var basis_bounds: Dictionary = _compute_bounds(_basis)
	var basis_height: float = float(basis_bounds["height"])
	if not FileAccess.file_exists(meta_path):
		print("GhostGirlHumanizerImporter: No export_meta.json; assuming 1.0 m scale.")
		return 1.0

	var meta_text: String = FileAccess.get_file_as_string(meta_path)
	var parsed: Variant = JSON.parse_string(meta_text)
	if not (parsed is Dictionary):
		printerr("GhostGirlHumanizerImporter: export_meta.json must be a JSON object.")
		return -1.0
	var meta: Dictionary = parsed as Dictionary

	if meta.has("target_unit_scale"):
		var raw_scale: Variant = meta.get("target_unit_scale")
		if raw_scale is float or raw_scale is int:
			return float(raw_scale)

	if meta.has("basis_bounds"):
		var raw_bounds: Variant = meta.get("basis_bounds")
		if raw_bounds is Dictionary:
			var exp_bounds: Dictionary = raw_bounds as Dictionary
			var exp_h: float = _extract_height_from_meta_bounds(exp_bounds)
			if exp_h > 0.0:
				var ratio: float = basis_height / exp_h
				print(
					"GhostGirlHumanizerImporter: Basis height=",
					basis_height,
					" meta=",
					exp_h,
					" -> unit_scale=",
					ratio
				)
				if absf(ratio - 1.0) < 0.05:
					return 1.0
				if absf(ratio - 0.1) < 0.01:
					return 0.1
				return ratio
	return 1.0


## Extracts vertical span from export_meta.json basis_bounds supporting min/max or size keys.
func _extract_height_from_meta_bounds(bounds: Dictionary) -> float:
	if bounds.has("size"):
		var raw_size: Variant = bounds.get("size")
		if raw_size is Array and (raw_size as Array).size() >= 2:
			var size_arr: Array = raw_size as Array
			return float(size_arr[1])
		if raw_size is Dictionary:
			var size_dict: Dictionary = raw_size as Dictionary
			if size_dict.has("y"):
				return float(size_dict.get("y"))
	if bounds.has("min") and bounds.has("max"):
		var raw_min: Variant = bounds.get("min")
		var raw_max: Variant = bounds.get("max")
		if raw_min is Array and raw_max is Array:
			var min_arr: Array = raw_min as Array
			var max_arr: Array = raw_max as Array
			if min_arr.size() >= 2 and max_arr.size() >= 2:
				return float(max_arr[1]) - float(min_arr[1])
	return 0.0


## Verifies morphed coordinates stay Y-up, +Z-forward, grounded, and within human bounds.
func _validate_morphed_pose(morphed: PackedVector3Array, max_delta: float) -> bool:
	var bounds: Dictionary = _compute_bounds(morphed)
	var min_pt: Vector3 = bounds["min"]
	var max_pt: Vector3 = bounds["max"]
	var height: float = float(bounds["height"])
	var head_y: float = morphed[HEAD_TOP_VID].y
	var foot_y: float = morphed[FOOT_VID].y
	var face_z: float = morphed[FACE_FRONT_VID].z

	if height < 1.1 or height > 2.2:
		printerr("GhostGirlHumanizerImporter: Morphed height out of range: ", height)
		return false
	if head_y <= foot_y + 1.0:
		printerr("GhostGirlHumanizerImporter: Not Y-up (head=", head_y, " foot=", foot_y, ")")
		return false
	if face_z <= 0.03:
		printerr("GhostGirlHumanizerImporter: Face not +Z-forward (z=", face_z, ")")
		return false
	if max_delta > 0.75:
		printerr("GhostGirlHumanizerImporter: Suspicious target delta magnitude: ", max_delta)
		return false
	print(
		"GhostGirlHumanizerImporter: Morphed bounds min=",
		min_pt,
		" max=",
		max_pt,
		" height=",
		height
	)
	return true


## Computes axis-aligned bounds and Y height for a packed vertex array.
func _compute_bounds(verts: PackedVector3Array) -> Dictionary:
	var min_v: Vector3 = Vector3(1e9, 1e9, 1e9)
	var max_v: Vector3 = Vector3(-1e9, -1e9, -1e9)
	for pt: Vector3 in verts:
		min_v = min_v.min(pt)
		max_v = max_v.max(pt)
	return {"min": min_v, "max": max_v, "height": max_v.y - min_v.y}


## Compiles every exported garment/body-part folder under [constant EXPORT_ROOT].
func _import_all_equipment() -> Array[String]:
	var imported: Array[String] = []
	var used_slots: Dictionary[String, String] = {}
	var dir_names: PackedStringArray = DirAccess.get_directories_at(EXPORT_ROOT)
	dir_names.sort()

	for folder_name: String in dir_names:
		if not folder_name.begins_with("GhostGirl_"):
			continue
		var src_dir: String = EXPORT_ROOT.path_join(folder_name)
		var equip_id: String = folder_name
		var slots: Array[String] = _resolve_slots(equip_id)
		if slots.is_empty():
			printerr("GhostGirlHumanizerImporter: No slot mapping for ", equip_id)
			return []
		for slot_name: String in slots:
			if used_slots.has(slot_name):
				printerr(
					"GhostGirlHumanizerImporter: Slot collision '",
					slot_name,
					"' between ",
					used_slots[slot_name],
					" and ",
					equip_id
				)
				return []
			used_slots[slot_name] = equip_id

		if not _import_single_equipment(equip_id, src_dir, slots):
			return []
		imported.append(equip_id)

	return imported


## Returns typed Humanizer slot array for [param equip_id].
func _resolve_slots(equip_id: String) -> Array[String]:
	var result: Array[String] = []
	if not EQUIP_SLOTS.has(equip_id):
		return result
	var raw_slots: Array = EQUIP_SLOTS[equip_id]
	for item: Variant in raw_slots:
		if item is String:
			result.append(item as String)
	return result


## Parses .mhclo + .obj + albedo .png and saves .mhclo.res, .res, and StandardMaterial3D.
func _import_single_equipment(equip_id: String, src_dir: String, slots: Array[String]) -> bool:
	var mhclo_path: String = _find_file_with_ext(src_dir, "mhclo")
	if mhclo_path.is_empty():
		printerr("GhostGirlHumanizerImporter: No .mhclo in ", src_dir)
		return false

	var mhclo: MHCLO = MHCLO.new()
	mhclo.parse_file(mhclo_path)
	if mhclo.vertex_data.is_empty():
		printerr("GhostGirlHumanizerImporter: Empty vertex_data in ", mhclo_path)
		return false
	if not _validate_mhclo_vertex_bindings(mhclo, equip_id):
		return false

	var obj_path: String = ""
	if not mhclo.obj_file_name.is_empty():
		var candidate: String = src_dir.path_join(mhclo.obj_file_name)
		if FileAccess.file_exists(candidate):
			obj_path = candidate
	if obj_path.is_empty():
		obj_path = _find_file_with_ext(src_dir, "obj")
	if obj_path.is_empty():
		printerr("GhostGirlHumanizerImporter: No .obj in ", src_dir)
		return false

	if not _populate_mhclo_geometry_from_obj(mhclo, obj_path):
		return false

	if mhclo.scale_config.is_empty():
		_populate_default_scale_config(mhclo)

	var equip_dir: String = EQUIP_OUT_ROOT.path_join(equip_id)
	if not DirAccess.dir_exists_absolute(equip_dir):
		DirAccess.make_dir_recursive_absolute(equip_dir)

	var mhclo_out: String = equip_dir.path_join(equip_id + ".mhclo.res")
	mhclo.resource_name = equip_id
	var save_mhclo_err: Error = ResourceSaver.save(mhclo, mhclo_out)
	if save_mhclo_err != OK:
		printerr("GhostGirlHumanizerImporter: Failed saving ", mhclo_out, " err=", save_mhclo_err)
		return false

	var equip_type: HumanizerEquipmentType = HumanizerEquipmentType.new()
	equip_type.resource_name = equip_id
	equip_type.display_name = mhclo.display_name if not mhclo.display_name.is_empty() else equip_id
	equip_type.path = equip_dir
	equip_type.default_material = equip_id
	equip_type.slots = slots
	var equip_out: String = equip_dir.path_join(equip_id + ".res")
	var save_eq_err: Error = ResourceSaver.save(equip_type, equip_out)
	if save_eq_err != OK:
		printerr("GhostGirlHumanizerImporter: Failed saving ", equip_out, " err=", save_eq_err)
		return false

	if not _import_equipment_material(equip_id, src_dir):
		return false

	_invalidate_equipment_weight_cache(equip_id)

	print(
		"GhostGirlHumanizerImporter: Imported ",
		equip_id,
		" slots=",
		slots,
		" verts=",
		mhclo.uv_array.size(),
		" tris=",
		mhclo.index_array.size() / 3
	)
	return true


## Clears stale cached skin weights in user://equipment_weights for [param equip_id].
func _invalidate_equipment_weight_cache(equip_id: String) -> void:
	var cache_root: String = "user://equipment_weights"
	if not DirAccess.dir_exists_absolute(cache_root):
		return
	var rig_dirs: PackedStringArray = DirAccess.get_directories_at(cache_root)
	for rig_dir: String in rig_dirs:
		var cached_file: String = cache_root.path_join(rig_dir).path_join(equip_id + ".res")
		if FileAccess.file_exists(cached_file):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(cached_file))


## Validates all basis vertex references inside [param mhclo] vertex_data.
func _validate_mhclo_vertex_bindings(mhclo: MHCLO, equip_id: String) -> bool:
	var basis_count: int = _basis.size()
	for entry_var: Variant in mhclo.vertex_data:
		if not (entry_var is Dictionary):
			continue
		var entry: Dictionary = entry_var as Dictionary
		var raw_verts: Variant = entry.get("vertex")
		if not (raw_verts is Array):
			continue
		for vid_var: Variant in raw_verts as Array:
			var vid: int = int(vid_var)
			if vid < 0 or vid >= basis_count:
				printerr(
					"GhostGirlHumanizerImporter: ",
					equip_id,
					" invalid basis vid ",
					vid,
					" / ",
					basis_count
				)
				return false
	return true


## Parses an OBJ file into MHCLO uv_array, index_array, custom0_array, and mh2gd_index.
func _populate_mhclo_geometry_from_obj(mhclo: MHCLO, obj_path: String) -> bool:
	var file: FileAccess = FileAccess.open(obj_path, FileAccess.READ)
	if file == null:
		printerr("GhostGirlHumanizerImporter: Cannot open ", obj_path)
		return false

	var obj_verts: PackedVector3Array = PackedVector3Array()
	var obj_uvs: PackedVector2Array = PackedVector2Array()
	var face_corners: Array[Array] = []

	while file.get_position() < file.get_length():
		var line: String = file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("v "):
			var coords: PackedStringArray = line.split(" ", false)
			if coords.size() >= 4:
				obj_verts.append(Vector3(float(coords[1]), float(coords[2]), float(coords[3])))
		elif line.begins_with("vt "):
			var uv_parts: PackedStringArray = line.split(" ", false)
			if uv_parts.size() >= 3:
				obj_uvs.append(Vector2(float(uv_parts[1]), 1.0 - float(uv_parts[2])))
		elif line.begins_with("f "):
			var tokens: PackedStringArray = line.split(" ", false)
			if tokens.size() < 4:
				continue
			var poly: Array[Vector2i] = []
			for idx: int in range(1, tokens.size()):
				var corner: Vector2i = _parse_obj_corner(
					tokens[idx], obj_verts.size(), obj_uvs.size()
				)
				poly.append(corner)
			face_corners.append(poly)

	if obj_verts.size() != mhclo.vertex_data.size():
		printerr(
			"GhostGirlHumanizerImporter: Vertex count mismatch in ",
			obj_path,
			" obj=",
			obj_verts.size(),
			" mhclo=",
			mhclo.vertex_data.size()
		)
		return false

	var uv_arr: PackedVector2Array = PackedVector2Array()
	var idx_arr: PackedInt32Array = PackedInt32Array()
	var c0_arr: PackedFloat32Array = PackedFloat32Array()
	var mh2gd: Array = []
	for mh_idx: int in range(obj_verts.size()):
		mh2gd.append([])

	var corner_map: Dictionary[Vector2i, int] = {}
	for poly_arr: Array in face_corners:
		if poly_arr.size() < 3:
			continue
		var c0: Vector2i = poly_arr[0] as Vector2i
		for tri_i: int in range(1, poly_arr.size() - 1):
			var c1: Vector2i = poly_arr[tri_i] as Vector2i
			var c2: Vector2i = poly_arr[tri_i + 1] as Vector2i
			var g0: int = _get_or_add_godot_vert(c0, obj_uvs, corner_map, uv_arr, c0_arr, mh2gd)
			var g1: int = _get_or_add_godot_vert(c1, obj_uvs, corner_map, uv_arr, c0_arr, mh2gd)
			var g2: int = _get_or_add_godot_vert(c2, obj_uvs, corner_map, uv_arr, c0_arr, mh2gd)
			# Reverse OBJ CCW triangle winding to Godot clockwise front-face winding.
			idx_arr.append(g2)
			idx_arr.append(g1)
			idx_arr.append(g0)

	mhclo.uv_array = uv_arr
	mhclo.index_array = idx_arr
	mhclo.custom0_array = c0_arr
	mhclo.mh2gd_index = mh2gd
	return not idx_arr.is_empty()


## Parses a single OBJ face vertex token ("v", "v/vt", "v//vn", or "v/vt/vn").
func _parse_obj_corner(token: String, v_count: int, vt_count: int) -> Vector2i:
	var comps: PackedStringArray = token.split("/", true)
	var raw_v: int = int(comps[0])
	var v_idx: int = (v_count + raw_v) if raw_v < 0 else (raw_v - 1)
	var vt_idx: int = -1
	if comps.size() >= 2 and not comps[1].is_empty():
		var raw_vt: int = int(comps[1])
		vt_idx = (vt_count + raw_vt) if raw_vt < 0 else (raw_vt - 1)
	return Vector2i(v_idx, vt_idx)


## Deduplicates (mh_id, vt_id) pairs into Godot vertex buffers.
func _get_or_add_godot_vert(
	corner: Vector2i,
	obj_uvs: PackedVector2Array,
	corner_map: Dictionary[Vector2i, int],
	uv_arr: PackedVector2Array,
	c0_arr: PackedFloat32Array,
	mh2gd: Array,
) -> int:
	if corner_map.has(corner):
		return corner_map[corner]
	var gd_id: int = uv_arr.size()
	var uv: Vector2 = (
		obj_uvs[corner.y] if corner.y >= 0 and corner.y < obj_uvs.size() else Vector2.ZERO
	)
	uv_arr.append(uv)
	c0_arr.append(float(corner.x))
	var list_ref: Array = mh2gd[corner.x] as Array
	list_ref.append(gd_id)
	corner_map[corner] = gd_id
	return gd_id


## Populates fallback scale_config using canonical MakeHuman reference points if omitted.
func _populate_default_scale_config(mhclo: MHCLO) -> void:
	var x_span: float = absf(_basis[10589].x - _basis[3924].x)
	var y_span: float = absf(_basis[4370].y - _basis[1524].y)
	var z_span: float = absf(_basis[3946].z - _basis[1892].z)
	mhclo.scale_config = {
		"x": {"start": 3924, "end": 10589, "length": x_span},
		"y": {"start": 1524, "end": 4370, "length": y_span},
		"z": {"start": 1892, "end": 3946, "length": z_span},
	}


## Saves StandardMaterial3D .res + albedo .png + .image.res under res://humanizer/material/<id>/.
func _import_equipment_material(equip_id: String, src_dir: String) -> bool:
	var png_src: String = _find_file_with_ext(src_dir, "png")
	var img: Image = null
	if not png_src.is_empty():
		img = Image.load_from_file(ProjectSettings.globalize_path(png_src))
	if img == null or img.is_empty():
		img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)

	if equip_id == "GhostGirl_Cape":
		_ensure_cape_translucency(img)

	var mat_dir: String = MAT_OUT_ROOT.path_join(equip_id)
	if not DirAccess.dir_exists_absolute(mat_dir):
		DirAccess.make_dir_recursive_absolute(mat_dir)

	var png_out: String = mat_dir.path_join(equip_id + ".png")
	if img.save_png(png_out) != OK:
		printerr("GhostGirlHumanizerImporter: Failed saving ", png_out)
		return false

	# Save ImageTexture as *_albedo.image.res and reload with CACHE_MODE_REPLACE so
	# StandardMaterial3D links an external resource_path cleanly for HumanizerMaterial.
	var img_tex: ImageTexture = ImageTexture.create_from_image(img)
	var tex_out: String = mat_dir.path_join(equip_id + "_albedo.image.res")
	if ResourceSaver.save(img_tex, tex_out) != OK:
		printerr("GhostGirlHumanizerImporter: Failed saving ", tex_out)
		return false
	var saved_tex: Texture2D = (
		ResourceLoader.load(tex_out, "", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
	)
	if saved_tex == null:
		printerr("GhostGirlHumanizerImporter: Failed reloading ", tex_out)
		return false

	var mat: StandardMaterial3D = _build_standard_material(equip_id, saved_tex)
	var mat_out: String = mat_dir.path_join(equip_id + ".res")
	if ResourceSaver.save(mat, mat_out) != OK:
		printerr("GhostGirlHumanizerImporter: Failed saving ", mat_out)
		return false
	return true


## Applies translucent alpha to GhostGirl_Cape albedo if exported fully opaque.
func _ensure_cape_translucency(img: Image) -> void:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var min_alpha: float = 1.0
	var width: int = img.get_width()
	var height: int = img.get_height()
	for y_pos: int in range(0, height, maxi(1, height / 32)):
		for x_pos: int in range(0, width, maxi(1, width / 32)):
			min_alpha = minf(min_alpha, img.get_pixel(x_pos, y_pos).a)
	if min_alpha > 0.98:
		for y_pos: int in range(height):
			for x_pos: int in range(width):
				var px: Color = img.get_pixel(x_pos, y_pos)
				px.a *= 0.58
				img.set_pixel(x_pos, y_pos, px)


## Builds configured [StandardMaterial3D] matching each GhostGirl garment surface type.
func _build_standard_material(equip_id: String, albedo_tex: Texture2D) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = albedo_tex
	mat.albedo_color = Color.WHITE
	if equip_id == "GhostGirl_Cape":
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.78
	elif equip_id in ["GhostGirl_Hair_Cards", "GhostGirl_Eyelashes"]:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.45
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.55
	elif equip_id in ["GhostGirl_Eye_L", "GhostGirl_Eye_R"]:
		mat.roughness = 0.04
		mat.clearcoat_enabled = true
		mat.clearcoat = 0.95
		mat.clearcoat_roughness = 0.03
	elif equip_id in ["GhostGirl_Hood", "GhostGirl_Skirt", "GhostGirl_CropTop"]:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.72
	elif equip_id == "GhostGirl_Boots":
		mat.roughness = 0.45
	else:
		mat.roughness = 0.7
	return mat


## Imports or synthesizes GhostGirl's anime skin material under Body-Default.
func _import_skin_material() -> bool:
	var candidates: Array[String] = [
		EXPORT_ROOT.path_join(SKIN_MAT_NAME + ".png"),
		EXPORT_ROOT.path_join("Body-Default").path_join(SKIN_MAT_NAME + ".png"),
		"res://assets/models/ghost_girl/textures/ghost_girl_skin_albedo.png",
		"res://assets/models/ghost_girl/textures/skin_albedo.png",
	]
	var img: Image = null
	for cand: String in candidates:
		if FileAccess.file_exists(cand):
			img = Image.load_from_file(ProjectSettings.globalize_path(cand))
			if img != null and not img.is_empty():
				break
	if img == null or img.is_empty():
		img = Image.create(256, 256, false, Image.FORMAT_RGBA8)
		img.fill(DEFAULT_SKIN_COLOR)

	var skin_dir: String = MAT_OUT_ROOT.path_join("Body-Default")
	if not DirAccess.dir_exists_absolute(skin_dir):
		DirAccess.make_dir_recursive_absolute(skin_dir)

	var png_out: String = skin_dir.path_join(SKIN_MAT_NAME + ".png")
	if img.save_png(png_out) != OK:
		printerr("GhostGirlHumanizerImporter: Failed saving ", png_out)
		return false

	var img_tex: ImageTexture = ImageTexture.create_from_image(img)
	var tex_out: String = skin_dir.path_join(SKIN_MAT_NAME + "_albedo.image.res")
	if ResourceSaver.save(img_tex, tex_out) != OK:
		printerr("GhostGirlHumanizerImporter: Failed saving ", tex_out)
		return false
	var saved_tex: Texture2D = (
		ResourceLoader.load(tex_out, "", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
	)
	if saved_tex == null:
		printerr("GhostGirlHumanizerImporter: Failed reloading ", tex_out)
		return false

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = saved_tex
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.68
	var mat_out: String = skin_dir.path_join(SKIN_MAT_NAME + ".res")
	if ResourceSaver.save(mat, mat_out) != OK:
		printerr("GhostGirlHumanizerImporter: Failed saving ", mat_out)
		return false
	print("GhostGirlHumanizerImporter: Saved skin material ", mat_out)
	return true


## Finds the first file inside [param dir_path] matching [param ext].
func _find_file_with_ext(dir_path: String, ext: String) -> String:
	var files: PackedStringArray = DirAccess.get_files_at(dir_path)
	files.sort()
	for file_name: String in files:
		if file_name.get_extension().to_lower() == ext:
			return dir_path.path_join(file_name)
	return ""


## Runs a full Humanizer build smoke check with default-RETARGETED and all GhostGirl assets.
func _run_smoke_check(imported_ids: Array[String]) -> bool:
	var reg_script: GDScript = (
		ResourceLoader.load("res://addons/humanizer/scripts/services/registry.gd") as GDScript
	)
	var config_script: GDScript = (
		ResourceLoader.load("res://addons/humanizer/scripts/resources/human_config.gd") as GDScript
	)
	var equip_script: GDScript = (
		ResourceLoader.load("res://addons/humanizer/scripts/resources/equipment.gd") as GDScript
	)
	var hum_script: GDScript = (
		ResourceLoader.load("res://addons/humanizer/scripts/core/humanizer.gd") as GDScript
	)

	reg_script.call("load_all")
	reg_script.call("_get_rigs")

	if not HumanizerTargetService.data.has(TARGET_KEY):
		printerr("GhostGirlHumanizerImporter: Smoke fail - missing target ", TARGET_KEY)
		return false

	var reg_equip_var: Variant = reg_script.get("equipment")
	if not (reg_equip_var is Dictionary):
		printerr("GhostGirlHumanizerImporter: Smoke fail - registry.equipment invalid")
		return false
	var reg_equip: Dictionary = reg_equip_var as Dictionary

	for equip_id: String in imported_ids:
		if not reg_equip.has(equip_id):
			printerr("GhostGirlHumanizerImporter: Smoke fail - missing equip ", equip_id)
			return false

	var config: Resource = config_script.new()
	config.set("rig", "default-RETARGETED")
	config.set("skin_color", Color.WHITE)
	config.set("hair_color", Color.WHITE)
	config.call("set_targets", {TARGET_KEY: 1.0})

	var body_equip: Resource = equip_script.new("Body-Default", SKIN_MAT_NAME)
	config.call("add_equipment", body_equip)
	for equip_id: String in imported_ids:
		var equip: Resource = equip_script.new(equip_id, equip_id)
		config.call("add_equipment", equip)

	var humanizer: Resource = hum_script.new()
	await humanizer.call("load_config_async", config)
	var body_raw: Variant = humanizer.call("get_CharacterBody3D", false)
	if not (body_raw is Node):
		printerr("GhostGirlHumanizerImporter: Smoke fail - get_CharacterBody3D returned null")
		return false

	var character_node: Node = body_raw as Node
	var skel: Node = character_node.get_node_or_null("GeneralSkeleton")
	var anim_tree: Node = character_node.get_node_or_null("AnimationTree")
	var avatar: Node = character_node.get_node_or_null("Avatar")
	var ok: bool = skel is Skeleton3D and anim_tree is AnimationTree and avatar is MeshInstance3D
	if ok:
		var skel_3d: Skeleton3D = skel as Skeleton3D
		var anim_node: AnimationTree = anim_tree as AnimationTree
		var avatar_mi: MeshInstance3D = avatar as MeshInstance3D
		if skel_3d.get_bone_count() <= 0:
			printerr("GhostGirlHumanizerImporter: Smoke fail - GeneralSkeleton has 0 bones")
			ok = false
		if not (anim_node.tree_root is AnimationNodeBlendTree):
			printerr("GhostGirlHumanizerImporter: Smoke fail - AnimationTree missing BlendTree")
			ok = false
		var expected_surfaces: int = imported_ids.size() + 1
		if avatar_mi.mesh == null or avatar_mi.mesh.get_surface_count() < expected_surfaces:
			printerr("GhostGirlHumanizerImporter: Smoke fail - missing surfaces on Avatar")
			ok = false
		else:
			for surf_i: int in range(avatar_mi.mesh.get_surface_count()):
				var surf_mat: Material = avatar_mi.mesh.surface_get_material(surf_i)
				if not (surf_mat is StandardMaterial3D):
					printerr(
						"GhostGirlHumanizerImporter: Smoke fail - non-StandardMaterial3D ", surf_i
					)
					ok = false
					break
				var std_mat: StandardMaterial3D = surf_mat as StandardMaterial3D
				if std_mat.albedo_texture == null:
					printerr(
						"GhostGirlHumanizerImporter: Smoke fail - null albedo_texture ", surf_i
					)
					ok = false
					break
				var surf_arrs: Array = avatar_mi.mesh.surface_get_arrays(surf_i)
				var raw_verts: Variant = surf_arrs[Mesh.ARRAY_VERTEX]
				var raw_bones: Variant = surf_arrs[Mesh.ARRAY_BONES]
				var raw_weights: Variant = surf_arrs[Mesh.ARRAY_WEIGHTS]
				if not (
					raw_verts is PackedVector3Array
					and raw_bones is PackedInt32Array
					and raw_weights is PackedFloat32Array
				):
					printerr(
						"GhostGirlHumanizerImporter: Smoke fail - missing skin arrays ", surf_i
					)
					ok = false
					break
				var v_cnt: int = (raw_verts as PackedVector3Array).size()
				var b_cnt: int = (raw_bones as PackedInt32Array).size()
				var w_cnt: int = (raw_weights as PackedFloat32Array).size()
				if v_cnt == 0 or b_cnt != v_cnt * 8 or w_cnt != v_cnt * 8:
					printerr(
						"GhostGirlHumanizerImporter: Smoke fail - skin mismatch surf=",
						surf_i,
						" v=",
						v_cnt,
						" b=",
						b_cnt,
						" w=",
						w_cnt
					)
					ok = false
					break
	else:
		printerr("GhostGirlHumanizerImporter: Smoke fail - missing GeneralSkeleton/AnimationTree")

	character_node.queue_free()
	await process_frame
	return ok
