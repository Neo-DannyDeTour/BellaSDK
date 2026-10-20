## Procedural background Gothic cathedral using [ArrayMesh] and [SurfaceTool].
@tool
class_name GothicCathedral
extends MeshInstance3D

## Emitted when cathedral mesh finishes rebuilding.
signal cathedral_rebuilt

## Render layer mask for Environment (Layer 1).
const ENV_RENDER_LAYER: int = 1

@export_group("Dimensions")

## Length of the main nave along the Z axis.
@export var nave_length: float = 60.0:
	set(value):
		nave_length = maxf(20.0, value)
		_request_rebuild()

## Width of the central nave along the X axis.
@export var nave_width: float = 16.0:
	set(value):
		nave_width = maxf(8.0, value)
		_request_rebuild()

## Height of the central nave walls before the roof.
@export var nave_height: float = 28.0:
	set(value):
		nave_height = maxf(10.0, value)
		_request_rebuild()

## Height of the twin western entrance towers.
@export var tower_height: float = 48.0:
	set(value):
		tower_height = maxf(20.0, value)
		_request_rebuild()

## Number of structural bays (controls buttress count).
@export var bay_count: int = 6:
	set(value):
		bay_count = maxi(3, value)
		_request_rebuild()

@export_group("Material")

## Optional custom old stone albedo texture. Uses procedural noise if null.
@export var stone_albedo: Texture2D = null:
	set(value):
		stone_albedo = value
		_update_material()

## Optional custom old stone normal texture. Uses procedural noise if null.
@export var stone_normal: Texture2D = null:
	set(value):
		stone_normal = value
		_update_material()

## UV world-space scale for triplanar stone mapping.
@export var uv_scale: float = 0.15:
	set(value):
		uv_scale = maxf(0.01, value)
		_update_material()


## Initializes render layers, optimization flags, mesh, and material.
func _ready() -> void:
	print("GothicCathedral: Initializing background cathedral node.")
	layers = ENV_RENDER_LAYER
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_rebuild_mesh()
	_update_material()


## Safely triggers mesh regeneration when properties change in the editor.
func _request_rebuild() -> void:
	print("GothicCathedral: Rebuild requested via property setter.")
	if is_instance_valid(self) and is_inside_tree():
		_rebuild_mesh()


## Generates the complete cathedral [ArrayMesh] using [SurfaceTool].
func _rebuild_mesh() -> void:
	print("GothicCathedral: Rebuilding procedural Gothic cathedral ArrayMesh.")
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var roof_h: float = nave_height * 0.45
	var aisle_w: float = nave_width * 0.45
	var aisle_h: float = nave_height * 0.55

	# 1. Central Nave & Pitched Roof
	_add_box(
		st, Vector3(0.0, nave_height * 0.5, 0.0), Vector3(nave_width, nave_height, nave_length)
	)
	_add_roof(st, Vector3(0.0, nave_height, 0.0), Vector3(nave_width, roof_h, nave_length), false)

	# 2. Side Aisles
	var left_x: float = -(nave_width * 0.5 + aisle_w * 0.5)
	var right_x: float = nave_width * 0.5 + aisle_w * 0.5
	_add_box(st, Vector3(left_x, aisle_h * 0.5, 0.0), Vector3(aisle_w, aisle_h, nave_length * 0.92))
	_add_box(
		st, Vector3(right_x, aisle_h * 0.5, 0.0), Vector3(aisle_w, aisle_h, nave_length * 0.92)
	)

	# 3. Transept (Cross Wing) & Roof
	var trans_span: float = nave_width + aisle_w * 2.8
	var trans_len: float = nave_width * 1.1
	var trans_z: float = -nave_length * 0.1
	_add_box(
		st, Vector3(0.0, nave_height * 0.5, trans_z), Vector3(trans_span, nave_height, trans_len)
	)
	_add_roof(st, Vector3(0.0, nave_height, trans_z), Vector3(trans_span, roof_h, trans_len), true)

	# 4. Central Crossing Tower & Fleche Spire
	var cross_w: float = nave_width * 0.75
	var cross_h: float = nave_height + roof_h + 10.0
	_add_box(st, Vector3(0.0, cross_h * 0.5, trans_z), Vector3(cross_w, cross_h, cross_w))
	_add_spire(st, Vector3(0.0, cross_h, trans_z), cross_w * 0.45, 22.0)

	# 5. Twin Western Facade Towers & Spires
	var t_width: float = aisle_w * 1.15
	var front_z: float = nave_length * 0.5 - t_width * 0.35
	var spire_h: float = tower_height * 0.55

	_add_box(
		st, Vector3(left_x, tower_height * 0.5, front_z), Vector3(t_width, tower_height, t_width)
	)
	_add_spire(st, Vector3(left_x, tower_height, front_z), t_width * 0.48, spire_h)

	_add_box(
		st, Vector3(right_x, tower_height * 0.5, front_z), Vector3(t_width, tower_height, t_width)
	)
	_add_spire(st, Vector3(right_x, tower_height, front_z), t_width * 0.48, spire_h)

	# 6. Structural Bays, Piers & Flying Buttresses
	_build_buttresses(st, aisle_w, aisle_h)

	st.index()
	st.generate_normals()
	st.generate_tangents()
	mesh = st.commit()
	cathedral_rebuilt.emit()


## Adds the exterior piers, pinnacles, and sloped flying buttress flyers.
func _build_buttresses(st: SurfaceTool, aisle_w: float, aisle_h: float) -> void:
	print("GothicCathedral: Generating flying buttress bays.")
	var step_z: float = (nave_length * 0.8) / float(bay_count)
	var start_z: float = -nave_length * 0.4 + step_z * 0.5
	var pier_w: float = 2.0
	var pier_d: float = 2.8
	var pier_h: float = nave_height * 0.85
	var outer_x: float = nave_width * 0.5 + aisle_w + pier_d * 0.4

	for i: int in range(bay_count):
		var z_pos: float = start_z + float(i) * step_z
		for side: float in [-1.0, 1.0]:
			var px: float = outer_x * side
			# Outer vertical pier + pinnacle spire
			_add_box(st, Vector3(px, pier_h * 0.5, z_pos), Vector3(pier_d, pier_h, pier_w))
			_add_spire(st, Vector3(px, pier_h, z_pos), pier_w * 0.45, 5.5)

			# Upper & Lower Flying Arches (sloped struts)
			var inner_x: float = (nave_width * 0.5) * side
			_add_strut(
				st,
				Vector3(px, aisle_h * 1.05, z_pos),
				Vector3(inner_x, nave_height * 0.9, z_pos),
				1.1,
				1.4
			)
			_add_strut(
				st,
				Vector3(px, aisle_h * 0.75, z_pos),
				Vector3(inner_x, nave_height * 0.68, z_pos),
				1.1,
				1.2
			)


## Appends an axis-aligned box to the provided [SurfaceTool].
func _add_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	#print("GothicCathedral: Adding box geometry at ", center)
	var hs: Vector3 = size * 0.5
	var v0: Vector3 = center + Vector3(-hs.x, -hs.y, -hs.z)
	var v1: Vector3 = center + Vector3(hs.x, -hs.y, -hs.z)
	var v2: Vector3 = center + Vector3(hs.x, hs.y, -hs.z)
	var v3: Vector3 = center + Vector3(-hs.x, hs.y, -hs.z)
	var v4: Vector3 = center + Vector3(-hs.x, -hs.y, hs.z)
	var v5: Vector3 = center + Vector3(hs.x, -hs.y, hs.z)
	var v6: Vector3 = center + Vector3(hs.x, hs.y, hs.z)
	var v7: Vector3 = center + Vector3(-hs.x, hs.y, hs.z)

	_add_quad(st, v4, v5, v6, v7)  # Front (+Z)
	_add_quad(st, v1, v0, v3, v2)  # Back (-Z)
	_add_quad(st, v0, v4, v7, v3)  # Left (-X)
	_add_quad(st, v5, v1, v2, v6)  # Right (+X)
	_add_quad(st, v7, v6, v2, v3)  # Top (+Y)


## Appends a pitched triangular prism roof to the [SurfaceTool].
func _add_roof(st: SurfaceTool, base_center: Vector3, size: Vector3, along_x: bool) -> void:
	#print("GothicCathedral: Adding pitched roof at ", base_center)
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	var h: float = size.y

	var b0: Vector3 = base_center + Vector3(-hx, 0.0, -hz)
	var b1: Vector3 = base_center + Vector3(hx, 0.0, -hz)
	var b2: Vector3 = base_center + Vector3(hx, 0.0, hz)
	var b3: Vector3 = base_center + Vector3(-hx, 0.0, hz)

	if not along_x:
		var t_back: Vector3 = base_center + Vector3(0.0, h, -hz)
		var t_front: Vector3 = base_center + Vector3(0.0, h, hz)
		_add_quad(st, b0, b3, t_front, t_back)
		_add_quad(st, b2, b1, t_back, t_front)
		_add_tri(st, b3, b2, t_front)
		_add_tri(st, b1, b0, t_back)
	else:
		var t_left: Vector3 = base_center + Vector3(-hx, h, 0.0)
		var t_right: Vector3 = base_center + Vector3(hx, h, 0.0)
		_add_quad(st, b1, b0, t_left, t_right)
		_add_quad(st, b3, b2, t_right, t_left)
		_add_tri(st, b0, b3, t_left)
		_add_tri(st, b2, b1, t_right)


## Appends an 8-sided octagonal spire cone to the [SurfaceTool].
func _add_spire(st: SurfaceTool, base_center: Vector3, radius: float, height: float) -> void:
	#print("GothicCathedral: Adding octagonal spire at ", base_center)
	var sides: int = 8
	var tip: Vector3 = base_center + Vector3(0.0, height, 0.0)
	for i: int in range(sides):
		var a0: float = TAU * float(i) / float(sides)
		var a1: float = TAU * float(i + 1) / float(sides)
		var p0: Vector3 = base_center + Vector3(cos(a0), 0.0, sin(a0)) * radius
		var p1: Vector3 = base_center + Vector3(cos(a1), 0.0, sin(a1)) * radius
		_add_tri(st, p0, p1, tip)


## Appends a sloped rectangular flyer strut between two points.
func _add_strut(
	st: SurfaceTool, p_start: Vector3, p_end: Vector3, width: float, thickness: float
) -> void:
	#print("GothicCathedral: Adding flying buttress strut from ", p_start)
	var hw: float = width * 0.5
	var ht: float = thickness * 0.5
	var s0: Vector3 = p_start + Vector3(0.0, -ht, -hw)
	var s1: Vector3 = p_start + Vector3(0.0, -ht, hw)
	var s2: Vector3 = p_start + Vector3(0.0, ht, hw)
	var s3: Vector3 = p_start + Vector3(0.0, ht, -hw)

	var e0: Vector3 = p_end + Vector3(0.0, -ht, -hw)
	var e1: Vector3 = p_end + Vector3(0.0, -ht, hw)
	var e2: Vector3 = p_end + Vector3(0.0, ht, hw)
	var e3: Vector3 = p_end + Vector3(0.0, ht, -hw)

	_add_quad(st, s1, e1, e2, s2)
	_add_quad(st, e0, s0, s3, e3)
	_add_quad(st, s3, s2, e2, e3)
	_add_quad(st, s0, e0, e1, s1)


## Appends two triangles forming a quad with planar UV coordinates.
func _add_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	var u: float = v0.distance_to(v1) * 0.2
	var v: float = v1.distance_to(v2) * 0.2
	st.set_uv(Vector2(0.0, v))
	st.add_vertex(v0)
	st.set_uv(Vector2(u, v))
	st.add_vertex(v1)
	st.set_uv(Vector2(u, 0.0))
	st.add_vertex(v2)

	st.set_uv(Vector2(0.0, v))
	st.add_vertex(v0)
	st.set_uv(Vector2(u, 0.0))
	st.add_vertex(v2)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(v3)


## Appends a single triangle with planar UV coordinates.
func _add_tri(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3) -> void:
	var u: float = v0.distance_to(v1) * 0.2
	var v: float = v0.distance_to(v2) * 0.2
	st.set_uv(Vector2(0.0, v))
	st.add_vertex(v0)
	st.set_uv(Vector2(u, v))
	st.add_vertex(v1)
	st.set_uv(Vector2(u * 0.5, 0.0))
	st.add_vertex(v2)


## Builds or updates the triplanar weathered stone [StandardMaterial3D].
func _update_material() -> void:
	print("GothicCathedral: Updating old stone material.")
	if not is_instance_valid(self):
		return

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.50, 0.47)
	mat.roughness = 0.92
	mat.uv1_triplanar = true
	mat.uv1_triplanar_sharpness = 4.0
	mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)

	if stone_albedo != null:
		mat.albedo_texture = stone_albedo
	else:
		var noise: FastNoiseLite = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.frequency = 0.045
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 4

		var ramp: Gradient = Gradient.new()
		ramp.set_color(0, Color(0.28, 0.27, 0.25))
		ramp.set_color(1, Color(0.68, 0.65, 0.60))

		var alb_tex: NoiseTexture2D = NoiseTexture2D.new()
		alb_tex.width = 512
		alb_tex.height = 512
		alb_tex.seamless = true
		alb_tex.color_ramp = ramp
		alb_tex.noise = noise
		mat.albedo_texture = alb_tex

		if stone_normal == null:
			var norm_tex: NoiseTexture2D = NoiseTexture2D.new()
			norm_tex.width = 512
			norm_tex.height = 512
			norm_tex.seamless = true
			norm_tex.as_normal_map = true
			norm_tex.bump_strength = 6.0
			norm_tex.noise = noise
			mat.normal_enabled = true
			mat.normal_texture = norm_tex

	if stone_normal != null:
		mat.normal_enabled = true
		mat.normal_texture = stone_normal

	material_override = mat
