"""Procedural Blender generator for Wave 2 factory yard debris containers and trash GLBs.

Builds gritty post-Soviet industrial clutter props one at a time via `--asset <name>` (or `all`):
- bottle_01:         0.26m H narrow-neck glass bottle (<= 300 tris)
                     -> assets/models/props/factory_yard/bottle_01.glb
                     -> slots: [0: dirty_glass_bottle]
- bottle_02:         0.22m H squat industrial glass bottle (<= 300 tris)
                     -> assets/models/props/factory_yard/bottle_02.glb
                     -> slots: [0: dirty_glass_bottle]
- plastic_water_jug: 0.38m H dirty 5L HDPE water jerrycan/jug w/ molded handle (<= 500 tris)
                     -> assets/models/props/factory_yard/plastic_water_jug.glb
                     -> slots: [0: hdpe_weathered_plastic]
- garbage_bag:       0.55m H tied slumped black trash bag (<= 600 tris)
                     -> assets/models/props/factory_yard/garbage_bag.glb
                     -> slots: [0: trash_bag_plastic]

Conventions:
- Origin at bottom-center (Blender Z=0 -> Godot min_y=0, centered on X and Y).
- Godot Y-up export (export_yup=True): Godot +X = Blender +X, +Y = +Z, +Z = -Y.
- Clean UVs without smearing and explicit material slots.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parent.parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bmesh
import bpy
from common.exporter import clean_scene, export_godot_glb
from common.materials import create_pbr_material
from mathutils import Matrix, Vector

_REPO_ROOT = _TOOL_DIR.parent.parent


# ==============================================================================
# SHARED MESH & UV HELPERS
# ==============================================================================
def _apply_box_uvs(bm: bmesh.types.BMesh, tile_meters: float = 1.0) -> None:
    """Assign world-metric triplanar cubic box UVs to all face loops."""
    uv_layer = bm.loops.layers.uv.verify()
    inv_tile = 1.0 / tile_meters
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                u, v = co.x * inv_tile, co.y * inv_tile
            elif ax >= ay and ax >= az:
                u, v = co.y * inv_tile, co.z * inv_tile
            else:
                u, v = co.x * inv_tile, co.z * inv_tile
            loop[uv_layer].uv = (u, v)


def _center_xy_ground_z(bm: bmesh.types.BMesh) -> None:
    """Shift vertices so X/Y bounding box is centered at 0 and min Z sits at 0.0."""
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    cx = 0.5 * (min(xs) + max(xs))
    cy = 0.5 * (min(ys) + max(ys))
    min_z = min(zs)
    for v in bm.verts:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= min_z


def _build_lathe_with_seamless_uvs(
    bm: bmesh.types.BMesh,
    profile_rz: list[tuple[float, float]],
    segments: int,
    mat_idx: int = 0,
    v_scale: float = 2.0,
) -> None:
    """Revolve an open or closed (radius, z) profile around Z with seam-free cylindrical UVs.

    profile_rz runs from bottom to top. If first/last radius > 0, planar caps are added.
    """
    uv_layer = bm.loops.layers.uv.verify()
    rings: list[list[bmesh.types.BMVert]] = []
    for r, z in profile_rz:
        ring: list[bmesh.types.BMVert] = []
        for k in range(segments):
            ang = 2.0 * math.pi * k / segments
            ring.append(bm.verts.new((r * math.cos(ang), r * math.sin(ang), z)))
        rings.append(ring)

    # Side quads with continuous cylindrical UVs (u in [0, 1] per revolution)
    for i in range(len(rings) - 1):
        r_a = rings[i]
        r_b = rings[i + 1]
        v0 = profile_rz[i][1] * v_scale
        v1 = profile_rz[i + 1][1] * v_scale
        for k in range(segments):
            k_next = (k + 1) % segments
            u0 = k / segments
            u1 = (k + 1) / segments
            face = bm.faces.new((r_a[k], r_a[k_next], r_b[k_next], r_b[k]))
            face.material_index = mat_idx
            face.smooth = True
            uvs = ((u0, v0), (u1, v0), (u1, v1), (u0, v1))
            for loop, uv in zip(face.loops, uvs):
                loop[uv_layer].uv = uv

    # Bottom planar cap
    if profile_rz[0][0] > 1e-4:
        f_bot = bm.faces.new(list(reversed(rings[0])))
        f_bot.material_index = mat_idx
        f_bot.smooth = False
        for loop in f_bot.loops:
            co = loop.vert.co
            loop[uv_layer].uv = (0.5 + co.x * v_scale, 0.5 + co.y * v_scale)

    # Top planar cap
    if profile_rz[-1][0] > 1e-4:
        f_top = bm.faces.new(rings[-1])
        f_top.material_index = mat_idx
        f_top.smooth = False
        for loop in f_top.loops:
            co = loop.vert.co
            loop[uv_layer].uv = (0.5 + co.x * v_scale, 0.5 + co.y * v_scale)


def _finalize_and_export(
    name: str,
    bm: bmesh.types.BMesh,
    materials: list[bpy.types.Material],
    out_path: Path,
    apply_box_uv: bool = True,
    tile_meters: float = 1.0,
    auto_smooth_deg: float = 40.0,
) -> None:
    """Recalculate normals, apply smooth/sharp edges, export GLB, and log stats."""
    _center_xy_ground_z(bm)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if apply_box_uv:
        _apply_box_uvs(bm, tile_meters=tile_meters)

    thresh_rad = math.radians(auto_smooth_deg)
    for face in bm.faces:
        face.smooth = True
    for edge in bm.edges:
        if len(edge.link_faces) == 2:
            edge.smooth = edge.calc_face_angle(0.0) <= thresh_rad
        else:
            edge.smooth = False

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for mat in materials:
        mesh.materials.append(mat)

    tri_count = sum(max(1, len(p.vertices) - 2) for p in mesh.polygons)
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    bmin = (min(xs), min(ys), min(zs))
    bmax = (max(xs), max(ys), max(zs))
    gmin = (min(xs), min(zs), -max(ys))
    gmax = (max(xs), max(zs), -min(ys))

    export_godot_glb(
        filepath=out_path,
        export_animations=False,
        apply_modifiers=True,
        save_blend=False,
    )
    slots = [(i, m.name) for i, m in enumerate(mesh.materials)]
    print(
        f"[{name}] tris={tri_count} slots={slots} "
        f"blender_bbox=({bmin[0]:.3f}..{bmax[0]:.3f}, {bmin[1]:.3f}..{bmax[1]:.3f}, {bmin[2]:.3f}..{bmax[2]:.3f}) "
        f"godot_dims=({gmax[0]-gmin[0]:.3f}m W x {gmax[1]-gmin[1]:.3f}m H x {gmax[2]-gmin[2]:.3f}m D) "
        f"min_y={gmin[1]:.4f} -> {out_path}"
    )


# ==============================================================================
# 1. BOTTLE 01 (0.26m H narrow-neck glass bottle, <= 300 tris)
# ==============================================================================
def build_bottle_01(out_path: Path) -> None:
    """Generate a 0.26m tall narrow-neck industrial/beverage glass bottle."""
    clean_scene()
    glass_mat = create_pbr_material(
        "dirty_glass_bottle", (0.14, 0.20, 0.11, 1.0), metallic=0.0, roughness=0.28
    )

    bm = bmesh.new()
    # 11 rings x 12 radial segs = ~264 tris (well <= 300 tris)
    profile = [
        (0.032, 0.000),  # Heel bevel bottom
        (0.036, 0.008),  # Lower body
        (0.036, 0.135),  # Upper body shoulder start
        (0.031, 0.158),  # Curved shoulder mid
        (0.017, 0.185),  # Neck base
        (0.014, 0.242),  # Neck top under lip
        (0.017, 0.246),  # Crown lip flare
        (0.016, 0.258),  # Lip top outer
        (0.012, 0.260),  # Rim crest
        (0.009, 0.244),  # Recessed bore
    ]
    _build_lathe_with_seamless_uvs(bm, profile, segments=12, mat_idx=0, v_scale=2.0)

    _finalize_and_export(
        "bottle_01", bm, [glass_mat], out_path, apply_box_uv=False, auto_smooth_deg=55.0
    )


# ==============================================================================
# 2. BOTTLE 02 (0.22m H squat industrial glass bottle, <= 300 tris)
# ==============================================================================
def build_bottle_02(out_path: Path) -> None:
    """Generate a 0.22m tall squat wide-mouth industrial reagent glass bottle."""
    clean_scene()
    glass_mat = create_pbr_material(
        "dirty_glass_bottle", (0.18, 0.14, 0.08, 1.0), metallic=0.0, roughness=0.30
    )

    bm = bmesh.new()
    # 11 rings x 12 radial segs = ~264 tris (well <= 300 tris)
    profile = [
        (0.044, 0.000),  # Base bevel
        (0.048, 0.008),  # Lower belly
        (0.048, 0.040),  # Label recess lower ridge
        (0.046, 0.046),  # Label recess start
        (0.046, 0.105),  # Label recess end
        (0.048, 0.112),  # Upper belly ridge
        (0.048, 0.130),  # Shoulder start
        (0.023, 0.168),  # Neck base
        (0.022, 0.192),  # Neck under collar
        (0.025, 0.196),  # Heavy screw-cap / collar base
        (0.024, 0.220),  # Cap top
    ]
    _build_lathe_with_seamless_uvs(bm, profile, segments=12, mat_idx=0, v_scale=2.0)

    _finalize_and_export(
        "bottle_02", bm, [glass_mat], out_path, apply_box_uv=False, auto_smooth_deg=50.0
    )


# ==============================================================================
# 3. PLASTIC WATER JUG (0.38m H dirty 5L jerrycan/jug w/ molded handle, <= 500 tris)
# ==============================================================================
def _add_chamfered_ring_pts(hx: float, hy: float, ch: float, z: float) -> list[tuple[float, float, float]]:
    """Return 8 CCW points for a chamfered rectangular cross-section at height z."""
    c = min(ch, hx * 0.45, hy * 0.45)
    return [
        (-hx + c, -hy, z),
        (hx - c, -hy, z),
        (hx, -hy + c, z),
        (hx, hy - c, z),
        (hx - c, hy, z),
        (-hx + c, hy, z),
        (-hx, hy - c, z),
        (-hx, -hy + c, z),
    ]


def _loft_sections(
    bm: bmesh.types.BMesh,
    sections: list[list[tuple[float, float, float]]],
    mat_idx: int = 0,
    cap_bottom: bool = True,
    cap_top: bool = True,
) -> None:
    """Loft a sequence of equal-length 3D point loops into a closed or open shell."""
    rings = [[bm.verts.new(p) for p in sec] for sec in sections]
    n_pts = len(rings[0])
    for i in range(len(rings) - 1):
        r_a = rings[i]
        r_b = rings[i + 1]
        for k in range(n_pts):
            k_next = (k + 1) % n_pts
            f = bm.faces.new((r_a[k], r_a[k_next], r_b[k_next], r_b[k]))
            f.material_index = mat_idx

    if cap_bottom:
        fb = bm.faces.new(list(reversed(rings[0])))
        fb.material_index = mat_idx
    if cap_top:
        ft = bm.faces.new(rings[-1])
        ft.material_index = mat_idx


def _add_swept_bar(
    bm: bmesh.types.BMesh,
    waypoints: list[tuple[float, float, float]],
    hx: float,
    hz: float,
    mat_idx: int = 0,
) -> None:
    """Sweep a rectangular handle cross-section along 3D waypoints in the YZ plane."""
    rings: list[list[bmesh.types.BMVert]] = []
    for idx, pt in enumerate(waypoints):
        v = Vector(pt)
        if idx == 0:
            tan = (Vector(waypoints[1]) - v).normalized()
        elif idx == len(waypoints) - 1:
            tan = (v - Vector(waypoints[-2])).normalized()
        else:
            tan = (Vector(waypoints[idx + 1]) - Vector(waypoints[idx - 1])).normalized()
        right = Vector((1.0, 0.0, 0.0))
        up = right.cross(tan).normalized()
        corners = [
            v - right * hx - up * hz,
            v + right * hx - up * hz,
            v + right * hx + up * hz,
            v - right * hx + up * hz,
        ]
        rings.append([bm.verts.new(c) for c in corners])

    for i in range(len(rings) - 1):
        r_a = rings[i]
        r_b = rings[i + 1]
        for k in range(4):
            k_next = (k + 1) % 4
            f = bm.faces.new((r_a[k], r_a[k_next], r_b[k_next], r_b[k]))
            f.material_index = mat_idx

    f0 = bm.faces.new(list(reversed(rings[0])))
    f0.material_index = mat_idx
    f1 = bm.faces.new(rings[-1])
    f1.material_index = mat_idx


def build_plastic_water_jug(out_path: Path) -> None:
    """Generate a 0.38m H dirty 5L plastic water jerrycan/jug with molded handle."""
    clean_scene()
    hdpe_mat = create_pbr_material(
        "hdpe_weathered_plastic", (0.26, 0.29, 0.22, 1.0), metallic=0.0, roughness=0.78
    )

    bm = bmesh.new()
    # Body footprint: 0.19m W (X: -0.095..0.095) x 0.15m D (Y: -0.075..0.075)
    # Height: Z = 0.00 .. 0.380m (with recessed handle bay + spout + screw cap)
    body_sections = [
        _add_chamfered_ring_pts(0.088, 0.068, 0.016, 0.000),  # Bottom bevel
        _add_chamfered_ring_pts(0.095, 0.075, 0.018, 0.012),  # Lower body
        _add_chamfered_ring_pts(0.095, 0.075, 0.018, 0.105),  # Rib 1 lower
        _add_chamfered_ring_pts(0.091, 0.071, 0.017, 0.114),  # Rib 1 groove
        _add_chamfered_ring_pts(0.095, 0.075, 0.018, 0.123),  # Rib 1 upper
        _add_chamfered_ring_pts(0.095, 0.075, 0.018, 0.210),  # Rib 2 lower
        _add_chamfered_ring_pts(0.091, 0.071, 0.017, 0.219),  # Rib 2 groove
        _add_chamfered_ring_pts(0.095, 0.075, 0.018, 0.228),  # Rib 2 upper
        _add_chamfered_ring_pts(0.095, 0.075, 0.018, 0.275),  # Shoulder base
    ]
    # Tapered front-biased upper deck (leaving rear lowered under handle cutout)
    shoulder_top = [
        (-0.060, -0.064, 0.332),
        (0.060, -0.064, 0.332),
        (0.068, -0.010, 0.332),
        (0.072, 0.058, 0.285),
        (0.060, 0.068, 0.285),
        (-0.060, 0.068, 0.285),
        (-0.072, 0.058, 0.285),
        (-0.068, -0.010, 0.332),
    ]
    body_sections.append(shoulder_top)
    _loft_sections(bm, body_sections, mat_idx=0, cap_bottom=True, cap_top=True)

    # Molded hollow-grip carry handle arcing from rear shoulder (+Y) to upper spout collar
    handle_pts = [
        (0.0, 0.052, 0.282),
        (0.0, 0.054, 0.325),
        (0.0, 0.036, 0.354),
        (0.0, -0.002, 0.354),
        (0.0, -0.026, 0.332),
    ]
    _add_swept_bar(bm, handle_pts, hx=0.016, hz=0.013, mat_idx=0)

    # Front pouring neck + ribbed screw cap (Z: 0.326 .. 0.380)
    spout_center = (0.0, -0.036, 0.0)
    res_neck = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=10,
        radius1=0.024,
        radius2=0.023,
        depth=0.032,
        matrix=Matrix.Translation((spout_center[0], spout_center[1], 0.342)),
    )
    for v in res_neck["verts"]:
        for f in v.link_faces:
            f.material_index = 0

    res_cap = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=10,
        radius1=0.028,
        radius2=0.027,
        depth=0.024,
        matrix=Matrix.Translation((spout_center[0], spout_center[1], 0.368)),
    )
    for v in res_cap["verts"]:
        for f in v.link_faces:
            f.material_index = 0

    _finalize_and_export(
        "plastic_water_jug", bm, [hdpe_mat], out_path, apply_box_uv=True, tile_meters=1.0, auto_smooth_deg=42.0
    )


# ==============================================================================
# 4. GARBAGE BAG (0.55m H tied slumped black trash bag, <= 600 tris)
# ==============================================================================
def build_garbage_bag(out_path: Path) -> None:
    """Generate a 0.55m H tied slumped black polyethylene trash bag (<= 600 tris)."""
    clean_scene()
    bag_mat = create_pbr_material(
        "trash_bag_plastic", (0.045, 0.045, 0.050, 1.0), metallic=0.0, roughness=0.40
    )

    bm = bmesh.new()
    segs = 14
    # (z, base_radius, slump_x, slump_y, bulge_amp, crease_amp)
    ring_specs = [
        (0.000, 0.175, 0.000, 0.000, 0.010, 0.000),  # Grounded flat base
        (0.035, 0.220, 0.010, -0.006, 0.018, 0.004), # Gravity-settled lower skirt
        (0.095, 0.235, 0.020, -0.012, 0.022, 0.006), # Wide slumped belly
        (0.170, 0.220, 0.018, -0.010, 0.024, 0.008), # Mid lumpy trash volume
        (0.250, 0.188, 0.012, -0.006, 0.020, 0.010), # Upper taper
        (0.330, 0.140, 0.006, -0.002, 0.014, 0.014), # Gathering pleats begin
        (0.395, 0.082, 0.002, 0.000, 0.006, 0.014),  # Tightening pleats
        (0.435, 0.036, 0.000, 0.000, 0.002, 0.005),  # Tied knot waist
        (0.475, 0.054, -0.003, 0.004, 0.006, 0.012), # Flared top ruffle lower
        (0.525, 0.068, -0.005, 0.006, 0.008, 0.016), # Flared ears mid
        (0.550, 0.044, -0.004, 0.005, 0.004, 0.010), # Top gathered rim
    ]

    sections: list[list[tuple[float, float, float]]] = []
    for r_idx, (z, r_base, sx, sy, b_amp, c_amp) in enumerate(ring_specs):
        pts: list[tuple[float, float, float]] = []
        for k in range(segs):
            ang = 2.0 * math.pi * k / segs
            # Asymmetric internal trash lumps + sharp radial gathering creases near tie
            bulge = (
                0.60 * math.sin(2.0 * ang + 0.7 + r_idx * 0.25)
                + 0.40 * math.cos(3.0 * ang - 1.1 - r_idx * 0.18)
            ) * b_amp
            crease = math.cos(6.0 * ang + 0.35) * c_amp
            # Keep bottom ring flat on Z=0, slightly modulate top ears height
            z_mod = 0.0
            if r_idx >= 8:
                z_mod = 0.010 * math.sin(2.0 * ang + 0.4) * ((r_idx - 7) / 3.0)
                z_val = min(0.550, z + z_mod)
            else:
                z_val = z
            rad = max(0.022, r_base + bulge + crease)
            pts.append((sx + rad * math.cos(ang), sy + rad * math.sin(ang), z_val))
        sections.append(pts)

    _loft_sections(bm, sections, mat_idx=0, cap_bottom=True, cap_top=True)

    # Twisted tie-collar strap around knot waist (Z = 0.435m)
    res_tie = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=10,
        radius1=0.043,
        radius2=0.043,
        depth=0.018,
        matrix=Matrix.Translation((0.0, 0.0, 0.435)),
    )
    for v in res_tie["verts"]:
        for f in v.link_faces:
            f.material_index = 0

    _finalize_and_export(
        "garbage_bag", bm, [bag_mat], out_path, apply_box_uv=True, tile_meters=1.0, auto_smooth_deg=55.0
    )


def main() -> None:
    """CLI entrypoint for generating Wave 2 factory debris container GLBs."""
    parser = argparse.ArgumentParser(description="Generate factory yard debris container GLBs.")
    parser.add_argument(
        "--asset",
        default="all",
        choices=["bottle_01", "bottle_02", "plastic_water_jug", "garbage_bag", "all"],
        help="Asset to generate (default: all).",
    )
    args, _ = parser.parse_known_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])

    out_dir = _REPO_ROOT / "assets/models/props/factory_yard"
    builders = {
        "bottle_01": (build_bottle_01, out_dir / "bottle_01.glb"),
        "bottle_02": (build_bottle_02, out_dir / "bottle_02.glb"),
        "plastic_water_jug": (build_plastic_water_jug, out_dir / "plastic_water_jug.glb"),
        "garbage_bag": (build_garbage_bag, out_dir / "garbage_bag.glb"),
    }

    targets = list(builders.keys()) if args.asset == "all" else [args.asset]
    for name in targets:
        fn, out_path = builders[name]
        fn(out_path)


if __name__ == "__main__":
    main()
