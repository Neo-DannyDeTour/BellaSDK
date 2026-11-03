"""Build a pre-fractured concrete wall panel with an inner rebar grid and export it as GLB.

Run inside Blender (live via MCP, or headless):
    blender --background --python tools/blender/build_wall_panel.py

Blender axes: X = width, Z = height, Y = thickness (front face = -Y -> Godot +Z after glTF Y-up).
Origin = bottom-centre of the panel. All chunk meshes stay in panel space (object at origin) so the
Godot baker can merge them without transforms.

Fracture = 2D Voronoi in XZ (every cell spans full thickness -> any removal is a breach).
Cells are built by bisecting the slab with the half-space between seed pairs -> always convex.

Naming contract (consumed by wall_panel_baker.gd):
    chunk_###          free chunk
    anchor_chunk_###   chunk touching top or bottom face (support graph root)
    rebar              joined rebar grid
Material slots on chunks: 0 = concrete_outer (original slab faces), 1 = concrete_inner (cut faces).
"""

import math
import os
import random

import bmesh
import bpy
from mathutils import Vector

# --- Parameters -----------------------------------------------------------------------------
PANEL_WIDTH: float = 2.0
PANEL_HEIGHT: float = 3.0
PANEL_THICKNESS: float = 0.25
CHUNK_COUNT: int = 42
CENTER_BIAS: float = 0.4  # fraction of seeds drawn from a gaussian around the panel centre
RNG_SEED: int = 1337
MIN_SEED_SPACING: float = 0.12  # rejects slivers that would make degenerate hulls

REBAR_RADIUS: float = 0.006  # 12 mm bar
REBAR_SPACING: float = 0.2
REBAR_COVER: float = 0.065  # distance from each face to bar centre
REBAR_SIDES: int = 8

COLLECTION_NAME: str = "DestructibleWall"
EXPORT_PATH: str = os.path.join(
	os.path.expanduser("~"),
	"Documents/BellaSDK/interactables/destructible_wall/models/wall_panel_2x3.glb",
)
EPS: float = 1e-4


def _get_material(name: str, color: tuple, metallic: float, roughness: float) -> bpy.types.Material:
	mat = bpy.data.materials.get(name)
	if mat is None:
		mat = bpy.data.materials.new(name)
		mat.use_nodes = True
	bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
	bsdf.inputs["Base Color"].default_value = color
	bsdf.inputs["Metallic"].default_value = metallic
	bsdf.inputs["Roughness"].default_value = roughness
	return mat


def _reset_collection() -> bpy.types.Collection:
	col = bpy.data.collections.get(COLLECTION_NAME)
	if col is not None:
		for obj in list(col.objects):
			bpy.data.objects.remove(obj, do_unlink=True)
	else:
		col = bpy.data.collections.new(COLLECTION_NAME)
		bpy.context.scene.collection.children.link(col)
	return col


def _generate_seeds() -> list:
	rng = random.Random(RNG_SEED)
	half_w = PANEL_WIDTH * 0.5
	seeds: list = []
	attempts = 0
	while len(seeds) < CHUNK_COUNT and attempts < 20000:
		attempts += 1
		if rng.random() < CENTER_BIAS:
			x = rng.gauss(0.0, PANEL_WIDTH * 0.18)
			z = rng.gauss(PANEL_HEIGHT * 0.5, PANEL_HEIGHT * 0.15)
		else:
			x = rng.uniform(-half_w, half_w)
			z = rng.uniform(0.0, PANEL_HEIGHT)
		if abs(x) > half_w - 0.02 or z < 0.02 or z > PANEL_HEIGHT - 0.02:
			continue
		p = Vector((x, 0.0, z))
		if all((p - s).length >= MIN_SEED_SPACING for s in seeds):
			seeds.append(p)
	return seeds


def _box_bmesh() -> bmesh.types.BMesh:
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	for v in bm.verts:
		v.co.x *= PANEL_WIDTH
		v.co.y *= PANEL_THICKNESS
		v.co.z = (v.co.z + 0.5) * PANEL_HEIGHT
	return bm


def _is_outer_face(face: bmesh.types.BMFace) -> bool:
	c = face.calc_center_median()
	half_w = PANEL_WIDTH * 0.5
	half_t = PANEL_THICKNESS * 0.5
	return (
		abs(abs(c.x) - half_w) < EPS
		or abs(abs(c.y) - half_t) < EPS
		or abs(c.z) < EPS
		or abs(c.z - PANEL_HEIGHT) < EPS
	)


def _box_project_uv(bm: bmesh.types.BMesh) -> None:
	uv_layer = bm.loops.layers.uv.verify()
	for face in bm.faces:
		n = face.normal
		ax = max(range(3), key=lambda i: abs(n[i]))
		for loop in face.loops:
			co = loop.vert.co
			if ax == 0:
				loop[uv_layer].uv = (co.y, co.z)
			elif ax == 1:
				loop[uv_layer].uv = (co.x, co.z)
			else:
				loop[uv_layer].uv = (co.x, co.y)


def _build_cell(seed: Vector, seeds: list) -> bmesh.types.BMesh:
	bm = _box_bmesh()
	for other in seeds:
		if other is seed:
			continue
		normal = (other - seed).normalized()
		mid = (seed + other) * 0.5
		geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
		res = bmesh.ops.bisect_plane(
			bm, geom=geom, dist=EPS, plane_co=mid, plane_no=normal,
			clear_outer=True, clear_inner=False,
		)
		cut_edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
		if cut_edges:
			bmesh.ops.contextual_create(bm, geom=cut_edges)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=EPS)
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	for face in bm.faces:
		face.material_index = 0 if _is_outer_face(face) else 1
	_box_project_uv(bm)
	return bm


def _build_chunks(col: bpy.types.Collection, mat_outer, mat_inner) -> tuple:
	seeds = _generate_seeds()
	anchors = 0
	for i, seed in enumerate(seeds):
		bm = _build_cell(seed, seeds)
		zs = [v.co.z for v in bm.verts]
		is_anchor = min(zs) < EPS or max(zs) > PANEL_HEIGHT - EPS
		anchors += int(is_anchor)
		name = ("anchor_chunk_%03d" if is_anchor else "chunk_%03d") % i
		mesh = bpy.data.meshes.new(name)
		bm.to_mesh(mesh)
		bm.free()
		mesh.materials.append(mat_outer)
		mesh.materials.append(mat_inner)
		obj = bpy.data.objects.new(name, mesh)
		col.objects.link(obj)
	return len(seeds), anchors


def _add_bar(bm: bmesh.types.BMesh, start: Vector, end: Vector) -> None:
	direction = end - start
	length = direction.length
	ret = bmesh.ops.create_cone(
		bm, cap_ends=True, segments=REBAR_SIDES, radius1=REBAR_RADIUS,
		radius2=REBAR_RADIUS, depth=length,
	)
	rot = Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized()).to_matrix()
	center = (start + end) * 0.5
	for v in ret["verts"]:
		v.co = rot @ v.co + center


def _build_rebar(col: bpy.types.Collection, mat_rebar) -> int:
	bm = bmesh.new()
	half_w = PANEL_WIDTH * 0.5
	half_t = PANEL_THICKNESS * 0.5
	bars = 0
	for layer_y in (-half_t + REBAR_COVER, half_t - REBAR_COVER):
		# Vertical bars sit slightly outside horizontals so the two sets don't intersect.
		vy = layer_y + math.copysign(REBAR_RADIUS * 2.0, layer_y)
		x = -half_w + REBAR_SPACING * 0.5
		while x < half_w - EPS:
			_add_bar(bm, Vector((x, vy, 0.0)), Vector((x, vy, PANEL_HEIGHT)))
			bars += 1
			x += REBAR_SPACING
		z = REBAR_SPACING * 0.5
		while z < PANEL_HEIGHT - EPS:
			_add_bar(bm, Vector((-half_w, layer_y, z)), Vector((half_w, layer_y, z)))
			bars += 1
			z += REBAR_SPACING
	mesh = bpy.data.meshes.new("rebar")
	bm.to_mesh(mesh)
	bm.free()
	mesh.materials.append(mat_rebar)
	for poly in mesh.polygons:
		poly.use_smooth = True
	obj = bpy.data.objects.new("rebar", mesh)
	col.objects.link(obj)
	return bars


def _export(col: bpy.types.Collection) -> None:
	os.makedirs(os.path.dirname(EXPORT_PATH), exist_ok=True)
	bpy.ops.object.select_all(action="DESELECT")
	for obj in col.objects:
		obj.select_set(True)
	bpy.ops.export_scene.gltf(
		filepath=EXPORT_PATH, export_format="GLB", use_selection=True,
		export_yup=True, export_apply=True,
	)


def build() -> None:
	mat_outer = _get_material("concrete_outer", (0.55, 0.55, 0.52, 1.0), 0.0, 0.9)
	mat_inner = _get_material("concrete_inner", (0.42, 0.41, 0.38, 1.0), 0.0, 1.0)
	mat_rebar = _get_material("rebar_steel", (0.25, 0.2, 0.17, 1.0), 1.0, 0.6)
	col = _reset_collection()
	chunk_count, anchor_count = _build_chunks(col, mat_outer, mat_inner)
	bar_count = _build_rebar(col, mat_rebar)
	_export(col)
	print("build_wall_panel: chunks=%d anchors=%d bars=%d -> %s"
		% (chunk_count, anchor_count, bar_count, EXPORT_PATH))


build()
