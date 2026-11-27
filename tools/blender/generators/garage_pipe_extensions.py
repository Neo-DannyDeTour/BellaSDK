"""Headless Blender generator for Rusty Pipe Kit Extensions with PBR & Beveled Flanges.

Exports to assets/models/pipes/:
  - pipe_t_junction.glb
  - pipe_cross_4way.glb
  - pipe_valve_wheel.glb
  - pipe_reducer.glb
  - pipe_wall_bracket.glb
  - pipe_broken_end.glb
  - pipe_thin_straight_2m.glb
  - pipe_thin_bend_90.glb
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

REPO_ROOT: str = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT_DIR: str = os.path.join(REPO_ROOT, "assets", "models", "pipes")


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for col in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for blk in list(col):
            if blk.users == 0:
                col.remove(blk)


def detect_pipe_radius() -> float:
    ref = os.path.join(OUT_DIR, "pipe_straight_1m.glb")
    if not os.path.isfile(ref):
        return 0.14
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=ref)
    xs: list[float] = []
    zs: list[float] = []
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH" and "col" not in obj.name and "Cube" not in obj.name:
            for v in obj.data.vertices:
                w = obj.matrix_world @ v.co
                xs.append(w.x)
                zs.append(w.z)
    if not xs or not zs:
        return 0.14
    span = min(max(xs) - min(xs), max(zs) - min(zs))
    # Cap at 0.25m for versatile garage/industrial pipe scale
    r = max(0.08, min(0.25, span * 0.5))
    print(f"[garage_pipe_extensions] Pipe radius: {r:.4f}m")
    return r


def add_cyl(
    bm: bmesh.types.BMesh,
    p0: Vector,
    p1: Vector,
    r0: float,
    r1: float | None = None,
    segs: int = 18,
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
    bmesh.ops.create_cone(
        bm,
        cap_ends=cap,
        cap_tris=False,
        segments=segs,
        radius1=r0,
        radius2=r1,
        depth=ln,
        matrix=xf,
    )


def add_flange(bm: bmesh.types.BMesh, center: Vector, normal: Vector, pipe_r: float) -> None:
    n = normal.normalized()
    p0 = center - n * 0.018
    p1 = center + n * 0.018
    add_cyl(bm, p0, p1, pipe_r * 1.32, pipe_r * 1.32, 18, True)
    up = Vector((0.0, 0.0, 1.0)) if abs(n.z) < 0.9 else Vector((1.0, 0.0, 0.0))
    u = n.cross(up).normalized()
    v = n.cross(u).normalized()
    br = pipe_r * 1.18
    for i in range(6):
        ang = i * (math.tau / 6.0)
        b_pos = center + (u * math.cos(ang) + v * math.sin(ang)) * br
        add_cyl(bm, b_pos - n * 0.028, b_pos + n * 0.028, pipe_r * 0.075, pipe_r * 0.075, 6, True)


def add_box(bm: bmesh.types.BMesh, p0: tuple[float, float, float], p1: tuple[float, float, float]) -> None:
    x0, y0, z0 = p0
    x1, y1, z1 = p1
    cx, cy, cz = (x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5
    sx, sy, sz = abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)
    m = Matrix.Translation((cx, cy, cz)) @ Matrix.Diagonal((sx, sy, sz, 1.0))
    bmesh.ops.create_cube(bm, size=1.0, matrix=m)


def export_pipe(name: str, bm: bmesh.types.BMesh, filename: str, bevel: bool = True) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    if bevel:
        bevel_sharp_edges(bm, offset=0.002, angle_deg=42.0)

    mesh = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.smooth = True
    thresh = math.radians(38.0)
    for e in bm.edges:
        if len(e.link_faces) == 2:
            e.smooth = e.calc_face_angle(0.0) <= thresh
        else:
            e.smooth = False
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(load_project_pbr("rusted_steel", "M_Rusty_Pipe", metallic_fallback=0.72))

    apply_metric_box_uv(obj, tiles_per_m=1.25)

    out_path = os.path.join(OUT_DIR, filename)
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
    print(f"[garage_pipe_extensions] Exported: {out_path}")


def main() -> None:
    r = detect_pipe_radius()
    arm = max(0.35, r * 3.2)
    r_thin = r * 0.55

    clear_scene()
    bm = bmesh.new()
    add_cyl(bm, Vector((-arm, 0.0, 0.0)), Vector((arm, 0.0, 0.0)), r)
    add_cyl(bm, Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, arm)), r)
    add_flange(bm, Vector((-arm + 0.02, 0.0, 0.0)), Vector((1.0, 0.0, 0.0)), r)
    add_flange(bm, Vector((arm - 0.02, 0.0, 0.0)), Vector((1.0, 0.0, 0.0)), r)
    add_flange(bm, Vector((0.0, 0.0, arm - 0.02)), Vector((0.0, 0.0, 1.0)), r)
    export_pipe("pipe_t_junction", bm, "pipe_t_junction.glb")

    clear_scene()
    bm = bmesh.new()
    add_cyl(bm, Vector((-arm, 0.0, 0.0)), Vector((arm, 0.0, 0.0)), r)
    add_cyl(bm, Vector((0.0, 0.0, -arm)), Vector((0.0, 0.0, arm)), r)
    for pt, nrm in (
        (Vector((-arm + 0.02, 0.0, 0.0)), Vector((1.0, 0.0, 0.0))),
        (Vector((arm - 0.02, 0.0, 0.0)), Vector((1.0, 0.0, 0.0))),
        (Vector((0.0, 0.0, -arm + 0.02)), Vector((0.0, 0.0, 1.0))),
        (Vector((0.0, 0.0, arm - 0.02)), Vector((0.0, 0.0, 1.0))),
    ):
        add_flange(bm, pt, nrm, r)
    export_pipe("pipe_cross_4way", bm, "pipe_cross_4way.glb")

    clear_scene()
    bm = bmesh.new()
    add_cyl(bm, Vector((-arm * 0.85, 0.0, 0.0)), Vector((arm * 0.85, 0.0, 0.0)), r)
    add_flange(bm, Vector((-arm * 0.85 + 0.02, 0.0, 0.0)), Vector((1.0, 0.0, 0.0)), r)
    add_flange(bm, Vector((arm * 0.85 - 0.02, 0.0, 0.0)), Vector((1.0, 0.0, 0.0)), r)
    add_cyl(bm, Vector((0.0, 0.0, 0.0)), Vector((0.0, -r * 1.9, 0.0)), r * 0.55)
    add_cyl(bm, Vector((0.0, -r * 1.9, 0.0)), Vector((0.0, -r * 2.9, 0.0)), r * 0.22)
    wy = -r * 2.9
    wheel_r = r * 1.85
    rim_r = r * 0.14
    segs = 20
    for i in range(segs):
        a0 = i * (math.tau / segs)
        a1 = (i + 1) * (math.tau / segs)
        p0 = Vector((math.cos(a0) * wheel_r, wy, math.sin(a0) * wheel_r))
        p1 = Vector((math.cos(a1) * wheel_r, wy, math.sin(a1) * wheel_r))
        add_cyl(bm, p0, p1, rim_r, rim_r, 8, True)
    for i in range(4):
        ang = i * (math.tau / 4.0)
        p_rim = Vector((math.cos(ang) * wheel_r, wy, math.sin(ang) * wheel_r))
        add_cyl(bm, Vector((0.0, wy, 0.0)), p_rim, rim_r * 0.85, rim_r * 0.85, 8, True)
    export_pipe("pipe_valve_wheel", bm, "pipe_valve_wheel.glb")

    clear_scene()
    bm = bmesh.new()
    add_cyl(bm, Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 0.14)), r, r)
    add_cyl(bm, Vector((0.0, 0.0, 0.14)), Vector((0.0, 0.0, 0.36)), r, r_thin)
    add_cyl(bm, Vector((0.0, 0.0, 0.36)), Vector((0.0, 0.0, 0.50)), r_thin, r_thin)
    add_flange(bm, Vector((0.0, 0.0, 0.02)), Vector((0.0, 0.0, 1.0)), r)
    add_flange(bm, Vector((0.0, 0.0, 0.48)), Vector((0.0, 0.0, 1.0)), r_thin)
    export_pipe("pipe_reducer", bm, "pipe_reducer.glb")

    clear_scene()
    bm = bmesh.new()
    add_box(bm, (-r * 1.9, -0.025, -0.045), (r * 1.9, 0.0, 0.045))
    cy = -r * 1.35
    add_box(bm, (-r * 1.3, cy, -0.03), (-r * 1.05, 0.0, 0.03))
    add_box(bm, (r * 1.05, cy, -0.03), (r * 1.3, 0.0, 0.03))
    add_cyl(bm, Vector((0.0, cy, -0.035)), Vector((0.0, cy, 0.035)), r * 1.15, r * 1.15, 18, False)
    export_pipe("pipe_wall_bracket", bm, "pipe_wall_bracket.glb")

    clear_scene()
    bm = bmesh.new()
    add_flange(bm, Vector((0.0, 0.0, 0.02)), Vector((0.0, 0.0, 1.0)), r)
    segs = 18
    inner_r = r * 0.84
    h_base = 0.55
    outer_bot, outer_top, inner_bot, inner_top = [], [], [], []
    for i in range(segs):
        ang = i * (math.tau / segs)
        jag = 0.06 * math.sin(ang * 3.0) + 0.035 * math.cos(ang * 5.0)
        z_top = h_base + jag
        ca, sa = math.cos(ang), math.sin(ang)
        outer_bot.append(bm.verts.new((ca * r, sa * r, 0.0)))
        outer_top.append(bm.verts.new((ca * r, sa * r, z_top)))
        inner_bot.append(bm.verts.new((ca * inner_r, sa * inner_r, 0.0)))
        inner_top.append(bm.verts.new((ca * inner_r, sa * inner_r, z_top)))
    for i in range(segs):
        j = (i + 1) % segs
        bm.faces.new((outer_bot[i], outer_bot[j], outer_top[j], outer_top[i]))
        bm.faces.new((inner_top[i], inner_top[j], inner_bot[j], inner_bot[i]))
        bm.faces.new((outer_top[i], outer_top[j], inner_top[j], inner_top[i]))
    export_pipe("pipe_broken_end", bm, "pipe_broken_end.glb", bevel=False)

    clear_scene()
    bm = bmesh.new()
    add_cyl(bm, Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 2.0)), r_thin)
    add_flange(bm, Vector((0.0, 0.0, 0.02)), Vector((0.0, 0.0, 1.0)), r_thin)
    add_flange(bm, Vector((0.0, 0.0, 1.98)), Vector((0.0, 0.0, 1.0)), r_thin)
    export_pipe("pipe_thin_straight_2m", bm, "pipe_thin_straight_2m.glb")

    clear_scene()
    bm = bmesh.new()
    bend_r = 0.30
    steps = 10
    pts = [
        Vector((bend_r - bend_r * math.cos(i * (math.pi * 0.5 / steps)), 0.0, bend_r * math.sin(i * (math.pi * 0.5 / steps))))
        for i in range(steps + 1)
    ]
    for i in range(steps):
        add_cyl(bm, pts[i], pts[i + 1], r_thin, r_thin, 14, True)
    add_flange(bm, pts[0] + Vector((0.0, 0.0, 0.02)), Vector((0.0, 0.0, 1.0)), r_thin)
    add_flange(bm, pts[-1] - Vector((0.02, 0.0, 0.0)), Vector((1.0, 0.0, 0.0)), r_thin)
    export_pipe("pipe_thin_bend_90", bm, "pipe_thin_bend_90.glb")


if __name__ == "__main__":
    main()
