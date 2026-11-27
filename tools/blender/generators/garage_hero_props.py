"""Headless Blender generator for Old Garage Hero Props & Cobweb Cards (Full PBR + Bevels).

Generates:
  - assets/models/gas_lamp/gas_lamp.glb (0.34m vintage kerosene storm lantern)
  - assets/models/car_engine_v8/car_engine_v8.glb (0.78m detailed rusted V8 engine block)
  - assets/models/old_mattress/old_mattress.glb (1.92m x 0.95m x 0.22m stained tufted mattress)
  - assets/models/cobwebs/cobweb_corner.glb, cobweb_drape.glb, cobweb_fence.glb
"""

from __future__ import annotations

import math
import os
import sys
import bpy
import bmesh
from mathutils import Matrix, Vector

_BLENDER_DIR: str = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if _BLENDER_DIR not in sys.path:
    sys.path.insert(0, _BLENDER_DIR)

from common.garage_pbr import apply_metric_box_uv, bevel_sharp_edges, load_project_pbr  # noqa: E402
from common.materials import create_pbr_material  # noqa: E402

REPO_ROOT: str = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
MODELS_ROOT: str = os.path.join(REPO_ROOT, "assets", "models")


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for col in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for blk in list(col):
            if blk.users == 0:
                col.remove(blk)


def make_alpha_mat(
    name: str,
    color: tuple[float, float, float, float],
    alpha: float = 1.0,
    emission: tuple[float, float, float, float] | None = None,
    emission_strength: float = 0.0,
    alpha_tex_path: str | None = None,
) -> bpy.types.Material:
    mat = create_pbr_material(
        name=name,
        base_color=color,
        metallic=0.05,
        roughness=0.22 if alpha < 1.0 else 0.92,
        emission_color=emission,
        emission_strength=emission_strength,
    )
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    if bsdf and alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        if hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
    if bsdf and alpha_tex_path and os.path.isfile(alpha_tex_path):
        img = bpy.data.images.load(alpha_tex_path, check_existing=True)
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = img
        links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        if hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
    return mat


def add_box(
    bm: bmesh.types.BMesh,
    p0: tuple[float, float, float],
    p1: tuple[float, float, float],
    mat_idx: int = 0,
    xform: Matrix | None = None,
) -> None:
    x0, y0, z0 = p0
    x1, y1, z1 = p1
    cx, cy, cz = (x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5
    sx, sy, sz = max(abs(x1 - x0), 1e-4), max(abs(y1 - y0), 1e-4), max(abs(z1 - z0), 1e-4)
    m = Matrix.Translation((cx, cy, cz)) @ Matrix.Diagonal((sx, sy, sz, 1.0))
    if xform is not None:
        m = xform @ m
    res = bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    vset = set(res["verts"])
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = mat_idx


def add_cyl(
    bm: bmesh.types.BMesh,
    p0: Vector,
    p1: Vector,
    r0: float,
    r1: float | None = None,
    segs: int = 18,
    mat_idx: int = 0,
    cap: bool = True,
) -> None:
    if r1 is None:
        r1 = r0
    v = p1 - p0
    ln = v.length
    if ln < 1e-5:
        return
    rot = v.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    xf = Matrix.Translation((p0 + p1) * 0.5) @ rot
    res = bmesh.ops.create_cone(
        bm, cap_ends=cap, cap_tris=False, segments=segs, radius1=r0, radius2=r1, depth=ln, matrix=xf
    )
    vset = set(res["verts"])
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = mat_idx


def add_tube(bm: bmesh.types.BMesh, pts: list[Vector], radius: float, segs: int = 10, mat_idx: int = 0) -> None:
    rings: list[list[bmesh.types.BMVert]] = []
    for i, p in enumerate(pts):
        t = (pts[1] - pts[0]) if i == 0 else ((pts[-1] - pts[-2]) if i == len(pts) - 1 else (pts[i + 1] - pts[i - 1]))
        t = t.normalized() if t.length > 1e-6 else Vector((0.0, 0.0, 1.0))
        up = Vector((0.0, 0.0, 1.0)) if abs(t.z) < 0.9 else Vector((1.0, 0.0, 0.0))
        u = t.cross(up).normalized()
        v = t.cross(u).normalized()
        rings.append([bm.verts.new(p + (u * math.cos(s * math.tau / segs) + v * math.sin(s * math.tau / segs)) * radius) for s in range(segs)])
    for i in range(len(rings) - 1):
        for s in range(segs):
            ns = (s + 1) % segs
            f = bm.faces.new((rings[i][s], rings[i][ns], rings[i + 1][ns], rings[i + 1][s]))
            f.material_index = mat_idx


def export_hero(
    subdir: str,
    filename: str,
    bm: bmesh.types.BMesh,
    mats: list[bpy.types.Material],
    uv_scale: float = 1.5,
    smooth_angle_deg: float = 38.0,
    bevel_offset: float = 0.0,
) -> None:
    out_dir = os.path.join(MODELS_ROOT, subdir)
    os.makedirs(out_dir, exist_ok=True)
    name = filename.replace(".glb", "")
    if bevel_offset > 0.0:
        bevel_sharp_edges(bm, offset=bevel_offset, angle_deg=38.0)

    mesh = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if len(e.link_faces) == 2:
            e.smooth = e.calc_face_angle(0.0) <= math.radians(smooth_angle_deg)
        else:
            e.smooth = False
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for m in mats:
        obj.data.materials.append(m)

    apply_metric_box_uv(obj, tiles_per_m=uv_scale)

    out_path = os.path.join(out_dir, filename)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_normals=True,
        export_texcoords=True,
    )
    print(f"[garage_hero_props] Exported: {out_path}")


def build_gas_lamp() -> None:
    clear_scene()
    m_green = load_project_pbr("olive_drab_ammo_metal", "M_GasLamp_RustedGreen", metallic_fallback=0.45)
    m_brass = load_project_pbr("tarnished_brass", "M_GasLamp_Brass", metallic_fallback=0.88)
    m_glass = make_alpha_mat(
        "M_GasLamp_GlassGlobe",
        (0.92, 0.84, 0.66, 1.0),
        alpha=0.52,
        emission=(1.0, 0.68, 0.26, 1.0),
        emission_strength=1.4,
    )
    bm = bmesh.new()

    add_cyl(bm, Vector((0, 0, 0.0)), Vector((0, 0, 0.015)), 0.092, 0.088, 24, 0)
    add_cyl(bm, Vector((0, 0, 0.015)), Vector((0, 0, 0.058)), 0.086, 0.084, 24, 0)
    add_cyl(bm, Vector((0, 0, 0.058)), Vector((0, 0, 0.088)), 0.084, 0.048, 24, 0)

    add_cyl(bm, Vector((0, 0, 0.088)), Vector((0, 0, 0.108)), 0.042, 0.046, 20, 1)
    add_cyl(bm, Vector((0, 0, 0.108)), Vector((0, 0, 0.125)), 0.022, 0.016, 16, 1)
    add_cyl(bm, Vector((0.045, -0.032, 0.068)), Vector((0.056, -0.040, 0.086)), 0.014, 0.015, 12, 1)
    add_cyl(bm, Vector((0.038, 0.0, 0.098)), Vector((0.068, 0.0, 0.098)), 0.005, 0.005, 8, 1)
    add_cyl(bm, Vector((0.066, 0.0, 0.098)), Vector((0.074, 0.0, 0.098)), 0.013, 0.013, 12, 1)

    globe_z = [0.108, 0.130, 0.168, 0.205, 0.228]
    globe_r = [0.044, 0.056, 0.060, 0.054, 0.042]
    for i in range(len(globe_z) - 1):
        add_cyl(bm, Vector((0, 0, globe_z[i])), Vector((0, 0, globe_z[i + 1])), globe_r[i], globe_r[i + 1], 24, 2, cap=False)

    add_cyl(bm, Vector((0, 0, 0.228)), Vector((0, 0, 0.244)), 0.048, 0.058, 24, 0)
    add_cyl(bm, Vector((0, 0, 0.244)), Vector((0, 0, 0.295)), 0.044, 0.040, 20, 0)
    add_cyl(bm, Vector((0, 0, 0.295)), Vector((0, 0, 0.305)), 0.054, 0.048, 22, 0)
    add_cyl(bm, Vector((0, 0, 0.305)), Vector((0, 0, 0.322)), 0.042, 0.030, 20, 0)

    for sx in (-1.0, 1.0):
        pts = [
            Vector((sx * 0.066, 0.0, 0.072)),
            Vector((sx * 0.095, 0.0, 0.095)),
            Vector((sx * 0.096, 0.0, 0.245)),
            Vector((sx * 0.074, 0.0, 0.278)),
            Vector((sx * 0.042, 0.0, 0.284)),
        ]
        add_tube(bm, pts, 0.011, 10, 0)

    for ang_deg in (40.0, 140.0, 220.0, 320.0):
        ang = math.radians(ang_deg)
        ca, sa = math.cos(ang), math.sin(ang)
        pts = [
            Vector((ca * 0.052, sa * 0.052, 0.105)),
            Vector((ca * 0.066, sa * 0.066, 0.168)),
            Vector((ca * 0.052, sa * 0.052, 0.236)),
        ]
        add_tube(bm, pts, 0.004, 8, 0)

    ring_pts = [
        Vector((math.cos(i * math.tau / 16) * 0.026, math.sin(i * math.tau / 16) * 0.026, 0.332))
        for i in range(17)
    ]
    add_tube(bm, ring_pts, 0.004, 8, 0)

    export_hero("gas_lamp", "gas_lamp.glb", bm, [m_green, m_brass, m_glass], uv_scale=3.2)


def build_car_engine_v8() -> None:
    clear_scene()
    m_iron = load_project_pbr("crane_iron", "M_Engine_CastIronRust", metallic_fallback=0.80)
    m_valve = load_project_pbr("rusty_orange_metal", "M_Engine_OrangeValveCover", metallic_fallback=0.55)
    m_steel = load_project_pbr("pillar_rusted_truss_steel", "M_Engine_DarkSteel", metallic_fallback=0.78)
    bm = bmesh.new()

    add_box(bm, (-0.18, -0.34, 0.0), (0.18, 0.26, 0.18), 0)
    add_box(bm, (-0.20, -0.36, 0.16), (0.20, 0.36, 0.22), 0)
    add_box(bm, (-0.22, -0.38, 0.22), (0.22, 0.38, 0.44), 0)

    for sx in (-1.0, 1.0):
        rot = Matrix.Rotation(math.radians(-sx * 42.0), 4, "Y")
        xf_bank = Matrix.Translation((sx * 0.22, 0.0, 0.44)) @ rot
        add_box(bm, (-0.11, -0.36, -0.06), (0.11, 0.36, 0.11), 0, xf_bank)
        add_box(bm, (-0.095, -0.34, 0.11), (0.095, 0.34, 0.21), 1, xf_bank)
        for r_off in (-0.05, 0.0, 0.05):
            add_box(bm, (r_off - 0.008, -0.31, 0.21), (r_off + 0.008, 0.31, 0.222), 1, xf_bank)

        collector = Vector((sx * 0.40, 0.06, 0.26))
        for cy in (-0.24, -0.08, 0.08, 0.24):
            port = Vector((sx * 0.30, cy, 0.42))
            mid = Vector((sx * 0.42, cy * 0.85, 0.37))
            add_tube(bm, [port, mid, collector], 0.026, 8, 0)
        add_cyl(bm, collector, collector + Vector((0.0, 0.08, -0.04)), 0.042, 0.042, 12, 0)

    add_box(bm, (-0.16, -0.30, 0.44), (0.16, 0.30, 0.58), 0)
    add_box(bm, (-0.10, -0.10, 0.58), (0.10, 0.10, 0.70), 2)
    add_cyl(bm, Vector((0.0, 0.0, 0.70)), Vector((0.0, 0.0, 0.78)), 0.105, 0.10, 20, 2)

    add_box(bm, (-0.19, -0.44, 0.20), (0.19, -0.38, 0.46), 0)
    add_cyl(bm, Vector((0.0, -0.50, 0.24)), Vector((0.0, -0.43, 0.24)), 0.095, 0.095, 20, 2)
    add_cyl(bm, Vector((0.0, -0.51, 0.42)), Vector((0.0, -0.43, 0.42)), 0.075, 0.075, 18, 2)
    add_cyl(bm, Vector((-0.26, -0.46, 0.34)), Vector((-0.26, -0.32, 0.34)), 0.068, 0.068, 16, 2)
    add_cyl(bm, Vector((-0.26, -0.51, 0.34)), Vector((-0.26, -0.46, 0.34)), 0.040, 0.040, 14, 2)
    add_cyl(bm, Vector((0.18, -0.49, 0.31)), Vector((0.18, -0.43, 0.31)), 0.044, 0.044, 14, 2)
    add_cyl(bm, Vector((0.0, 0.38, 0.30)), Vector((0.0, 0.52, 0.30)), 0.18, 0.13, 20, 0)

    export_hero(
        "car_engine_v8",
        "car_engine_v8.glb",
        bm,
        [m_iron, m_valve, m_steel],
        uv_scale=1.8,
        bevel_offset=0.0025,
    )


def build_old_mattress() -> None:
    clear_scene()
    m_fabric = load_project_pbr("stained_mattress_ticking", "M_Mattress_StainedTicking", metallic_fallback=0.0)
    bm = bmesh.new()

    w, l, h = 0.95, 1.92, 0.22
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(w, l, h), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(0.0, 0.0, h * 0.5), verts=bm.verts)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=6, use_grid_fill=True)

    tufts = [(tx, ty) for tx in (-0.26, 0.0, 0.26) for ty in (-0.64, -0.32, 0.0, 0.32, 0.64)]
    for v in bm.verts:
        nx_u = v.co.x / (w * 0.5)
        ny_u = v.co.y / (l * 0.5)
        corner_r = math.hypot(max(0.0, abs(nx_u) - 0.82), max(0.0, abs(ny_u) - 0.88))
        if corner_r > 0.0:
            v.co.x *= 1.0 - corner_r * 0.12
            v.co.y *= 1.0 - corner_r * 0.06
        if v.co.z > h * 0.7:
            sag = -0.022 * (1.0 - min(1.0, nx_u * nx_u + ny_u * ny_u * 0.6))
            puff = 0.015 * math.sin((v.co.x + 0.5) * 6.0) * math.cos(v.co.y * 5.0)
            dimple = 0.0
            for tx, ty in tufts:
                d2 = (v.co.x - tx) ** 2 + (v.co.y - ty) ** 2
                if d2 < 0.018:
                    dimple -= 0.024 * (1.0 - d2 / 0.018)
            v.co.z += sag + puff + dimple
        elif v.co.z > 0.02 and v.co.z < h * 0.7:
            v.co.x *= 1.025
            v.co.y *= 1.012

    min_z = min(v.co.z for v in bm.verts)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0.0, 0.0, -min_z))

    export_hero("old_mattress", "old_mattress.glb", bm, [m_fabric], uv_scale=1.0, smooth_angle_deg=65.0)


def build_cobwebs() -> None:
    tex_path = os.path.join(MODELS_ROOT, "cobwebs", "cobweb_alpha.png")

    def export_card(filename: str, pts: list[tuple[float, float, float]], uvs: list[tuple[float, float]]) -> None:
        clear_scene()
        mat = make_alpha_mat("M_Cobweb_Alpha", (0.85, 0.86, 0.84, 1.0), alpha_tex_path=tex_path)
        bm = bmesh.new()
        verts = [bm.verts.new(p) for p in pts]
        f = bm.faces.new(verts)
        uv_layer = bm.loops.layers.uv.verify()
        for loop, uv_co in zip(f.loops, uvs):
            loop[uv_layer].uv = uv_co
        verts_b = [bm.verts.new((p[0], p[1] + 0.004, p[2])) for p in reversed(pts)]
        fb = bm.faces.new(verts_b)
        for loop, uv_co in zip(fb.loops, reversed(uvs)):
            loop[uv_layer].uv = uv_co

        out_dir = os.path.join(MODELS_ROOT, "cobwebs")
        os.makedirs(out_dir, exist_ok=True)
        mesh = bpy.data.meshes.new(filename)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(filename, mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(mat)
        bpy.ops.export_scene.gltf(
            filepath=os.path.join(out_dir, filename),
            export_format="GLB",
            use_selection=False,
            export_apply=True,
            export_yup=True,
            export_materials="EXPORT",
            export_normals=True,
            export_texcoords=True,
        )
        print(f"[garage_hero_props] Exported: {os.path.join(out_dir, filename)}")

    export_card(
        "cobweb_corner.glb",
        [(0.0, 0.0, 1.2), (1.2, 0.0, 1.2), (1.2, 0.0, 0.0), (0.0, 0.0, 0.0)],
        [(0.0, 1.0), (1.0, 1.0), (1.0, 0.0), (0.0, 0.0)],
    )
    export_card(
        "cobweb_drape.glb",
        [(-0.9, 0.0, 0.0), (0.9, 0.0, 0.0), (0.9, 0.0, -0.9), (-0.9, 0.0, -0.9)],
        [(0.0, 1.0), (1.0, 1.0), (1.0, 0.0), (0.0, 0.0)],
    )
    export_card(
        "cobweb_fence.glb",
        [(-0.7, 0.0, 1.4), (0.7, 0.0, 1.4), (0.7, 0.0, 0.0), (-0.7, 0.0, 0.0)],
        [(0.0, 1.0), (1.0, 1.0), (1.0, 0.0), (0.0, 0.0)],
    )


def main() -> None:
    build_gas_lamp()
    build_car_engine_v8()
    build_old_mattress()
    build_cobwebs()


if __name__ == "__main__":
    main()
