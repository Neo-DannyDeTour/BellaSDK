@tool
## Procedural 3D lightning strike VFX using [GPUParticles3D] and [ArrayMesh].
class_name LightningStrikeVFX
extends GPUParticles3D

## Emitted when a manual lightning strike is triggered via [method trigger_strike].
signal strike_triggered(world_position: Vector3)

## Surface index for the vertical lightning bolt ribbon.
const SURFACE_BOLT: int = 0
## Surface index for the horizontal ground impact mark.
const SURFACE_MARK: int = 1
## Surface index for the expanding shockwave cylinder.
const SURFACE_WAVE: int = 2
## Default render layer mask (Layer 1 Environment + Layer 10 Volumetrics).
const DEFAULT_RENDER_LAYERS: int = (1 << 0) | (1 << 9)

## Shader applied to surface 0 (vertical lightning bolt).
@export var bolt_shader: Shader
## Shader applied to surface 1 (ground impact mark).
@export var mark_shader: Shader
## Shader applied to surface 2 (shockwave cylinder).
@export var wave_shader: Shader

@export_group("Bolt Geometry")
## Height of the generated lightning bolt ribbon in meters.
@export var bolt_height: float = 8.0
## Width of the generated lightning bolt ribbon in meters.
@export var bolt_width: float = 0.85
## Number of vertical subdivisions along the bolt ribbon.
@export var bolt_segments: int = 16
## Horizontal zig-zag offset amplitude for the bolt vertices.
@export var bolt_kink_amount: float = 0.22

@export_group("Impact Geometry")
## Size of the ground impact mark quad in meters.
@export var mark_size: float = 2.4
## Bottom radius of the shockwave cylinder in meters.
@export var wave_bottom_radius: float = 0.75
## Top radius of the shockwave cylinder in meters.
@export var wave_top_radius: float = 1.25
## Height of the shockwave cylinder in meters.
@export var wave_height: float = 1.1
## Radial segments for the shockwave cylinder.
@export var wave_radial_segments: int = 24


## Initializes the procedural [ArrayMesh] and materials when entering the tree.
func _ready() -> void:
	print("LightningStrikeVFX: Initializing procedural lightning mesh and shaders.")
	layers = DEFAULT_RENDER_LAYERS
	rebuild_mesh()


## Triggers a single lightning burst at [param world_position].
func trigger_strike(world_position: Vector3) -> void:
	print("LightningStrikeVFX: Triggering strike at ", world_position)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	global_position = world_position
	restart()
	emitting = true
	strike_triggered.emit(world_position)


## Rebuilds the 3-surface [ArrayMesh] and assigns [ShaderMaterial] passes.
func rebuild_mesh() -> void:
	print("LightningStrikeVFX: Rebuilding 3-surface procedural ArrayMesh.")
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var mesh: ArrayMesh = ArrayMesh.new()
	_append_bolt_surface(mesh)
	_append_mark_surface(mesh)
	_append_wave_surface(mesh)
	_apply_surface_materials(mesh)
	draw_pass_1 = mesh


## Appends the subdivided vertical bolt ribbon as surface 0 on [param mesh].
func _append_bolt_surface(mesh: ArrayMesh) -> void:
	#print("LightningStrikeVFX: Generating surface 0 (bolt ribbon).")
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_w: float = bolt_width * 0.5
	var seg_count: int = maxi(bolt_segments, 2)

	for i: int in range(seg_count + 1):
		var t: float = float(i) / float(seg_count)
		var y_pos: float = (1.0 - t) * bolt_height
		var envelope: float = sin(t * PI)
		var kink_x: float = sin(float(i) * 2.3) * bolt_kink_amount * envelope
		var kink_z: float = cos(float(i) * 1.7) * (bolt_kink_amount * 0.5) * envelope

		st.set_normal(Vector3.BACK)
		st.set_uv(Vector2(0.0, t))
		st.add_vertex(Vector3(-half_w + kink_x, y_pos, kink_z))

		st.set_normal(Vector3.BACK)
		st.set_uv(Vector2(1.0, t))
		st.add_vertex(Vector3(half_w + kink_x, y_pos, kink_z))

	for i: int in range(seg_count):
		var row_a: int = i * 2
		var row_b: int = (i + 1) * 2
		st.add_index(row_a)
		st.add_index(row_b)
		st.add_index(row_a + 1)

		st.add_index(row_a + 1)
		st.add_index(row_b)
		st.add_index(row_b + 1)

	st.commit(mesh)


## Appends the horizontal ground mark quad as surface 1 on [param mesh].
func _append_mark_surface(mesh: ArrayMesh) -> void:
	#print("LightningStrikeVFX: Generating surface 1 (ground impact mark).")
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_s: float = mark_size * 0.5
	var y_offset: float = 0.02

	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(Vector3(-half_s, y_offset, -half_s))

	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(Vector3(half_s, y_offset, -half_s))

	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(Vector3(half_s, y_offset, half_s))

	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(Vector3(-half_s, y_offset, half_s))

	st.add_index(0)
	st.add_index(1)
	st.add_index(2)
	st.add_index(0)
	st.add_index(2)
	st.add_index(3)

	st.commit(mesh)


## Appends the open tapered shockwave cylinder as surface 2 on [param mesh].
func _append_wave_surface(mesh: ArrayMesh) -> void:
	#print("LightningStrikeVFX: Generating surface 2 (shockwave cylinder).")
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rad_segs: int = maxi(wave_radial_segments, 8)
	for i: int in range(rad_segs + 1):
		var u: float = float(i) / float(rad_segs)
		var angle: float = u * TAU
		var dir_x: float = cos(angle)
		var dir_z: float = sin(angle)
		var normal: Vector3 = Vector3(-dir_x, 0.0, -dir_z).normalized()

		st.set_normal(normal)
		st.set_uv(Vector2(u, 0.0))
		st.add_vertex(Vector3(dir_x * wave_top_radius, wave_height, dir_z * wave_top_radius))

		st.set_normal(normal)
		st.set_uv(Vector2(u, 1.0))
		st.add_vertex(Vector3(dir_x * wave_bottom_radius, 0.0, dir_z * wave_bottom_radius))

	for i: int in range(rad_segs):
		var top_a: int = i * 2
		var bot_a: int = top_a + 1
		var top_b: int = (i + 1) * 2
		var bot_b: int = top_b + 1

		st.add_index(top_a)
		st.add_index(bot_a)
		st.add_index(top_b)

		st.add_index(top_b)
		st.add_index(bot_a)
		st.add_index(bot_b)

	st.commit(mesh)


## Applies shader materials to each surface of [param mesh].
func _apply_surface_materials(mesh: ArrayMesh) -> void:
	print("LightningStrikeVFX: Applying ShaderMaterials to mesh surfaces.")
	if bolt_shader != null and mesh.get_surface_count() > SURFACE_BOLT:
		var bolt_mat: ShaderMaterial = ShaderMaterial.new()
		bolt_mat.shader = bolt_shader
		mesh.surface_set_material(SURFACE_BOLT, bolt_mat)

	if mark_shader != null and mesh.get_surface_count() > SURFACE_MARK:
		var mark_mat: ShaderMaterial = ShaderMaterial.new()
		mark_mat.shader = mark_shader
		mesh.surface_set_material(SURFACE_MARK, mark_mat)

	if wave_shader != null and mesh.get_surface_count() > SURFACE_WAVE:
		var wave_mat: ShaderMaterial = ShaderMaterial.new()
		wave_mat.shader = wave_shader
		mesh.surface_set_material(SURFACE_WAVE, wave_mat)
