"""Procedural Blender generator for overgrown factory foliage expansion GLBs.

Generates 6 modular foliage GLBs in assets/models/foliage/:
- shrub_plant_01.glb: 0.65m H compact broadleaf yard shrub (woody stems + leaf cards, <= 600 tris)
- shrub_plant_02.glb: 0.95m H medium broadleaf yard shrub (woody stems + leaf cards, <= 600 tris)
- shrub_plant_03.glb: 1.25m H tall broadleaf thicket shrub (woody stems + leaf cards, <= 600 tris)
- grass_clump_01.glb: 0.45m H crossed curved wild grass tuft (<= 250 tris)
- grass_clump_02.glb: 0.70m H tall crossed wild reed/grass tuft (<= 250 tris)
- grass_leaf_cluster.glb: 0.35m H low sprawling grass rosette cluster (<= 250 tris)

Conventions:
- Origin at bottom-center (Blender Z=0 -> Godot min_y=0, centered on X and Y).
- Leaf/grass cards use clean non-overlapping [0, 1] UV1 per card (Blender V=1 top,
  V=0 bottom -> flips on glTF export to Godot V=0 top, V=1 bottom).
- Woody stems use continuous parallel-transport cylindrical UVs.
- Explicit material slots for Godot ORM / alpha-scissored material assignment.
"""

from __future__ import annotations

import math
import random
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


def _create_foliage_materials() -> dict[str, bpy.types.Material]:
    """Create clean-room placeholder PBR materials matching Godot slot names."""
    return {
        "overgrown_bark": create_pbr_material(
            name="overgrown_bark",
            base_color=(0.22, 0.16, 0.11, 1.0),
            metallic=0.0,
            roughness=0.90,
        ),
        "foliage_broadleaf_atlas": create_pbr_material(
            name="foliage_broadleaf_atlas",
            base_color=(0.20, 0.30, 0.13, 1.0),
            metallic=0.0,
            roughness=0.72,
        ),
        "foliage_weeds_atlas": create_pbr_material(
            name="foliage_weeds_atlas",
            base_color=(0.27, 0.32, 0.16, 1.0),
            metallic=0.0,
            roughness=0.76,
        ),
    }


def _parallel_transport_frames(points: list[Vector]) -> list[tuple[Vector, Vector, Vector]]:
    """Compute twist-free (tangent, normal, binormal) orthonormal frames along a polyline."""
    count = len(points)
    tangents: list[Vector] = []
    for i in range(count):
        if i == 0:
            t = points[1] - points[0]
        elif i == count - 1:
            t = points[-1] - points[-2]
        else:
            t = points[i + 1] - points[i - 1]
        if t.length < 1e-6:
            t = Vector((0.0, 0.0, 1.0))
        else:
            t.normalize()
        tangents.append(t)

    ref = Vector((1.0, 0.0, 0.0))
    if abs(tangents[0].dot(ref)) > 0.9:
        ref = Vector((0.0, 1.0, 0.0))
    n0 = tangents[0].cross(ref).normalized()
    b0 = tangents[0].cross(n0).normalized()

    frames: list[tuple[Vector, Vector, Vector]] = [(tangents[0], n0, b0)]
    for i in range(1, count):
        t_prev, n_prev, _ = frames[-1]
        t_curr = tangents[i]
        rot_axis = t_prev.cross(t_curr)
        if rot_axis.length > 1e-6:
            rot_axis.normalize()
            angle = math.acos(max(-1.0, min(1.0, t_prev.dot(t_curr))))
            rot_mat = Matrix.Rotation(angle, 3, rot_axis)
            n_curr = (rot_mat @ n_prev).normalized()
        else:
            n_curr = n_prev.copy()
        n_curr = (n_curr - t_curr * n_curr.dot(t_curr)).normalized()
        b_curr = t_curr.cross(n_curr).normalized()
        frames.append((t_curr, n_curr, b_curr))
    return frames


def _add_branch_tube(
    bm: bmesh.types.BMesh,
    uv_layer: bmesh.types.BMLayerItem,
    points: list[Vector],
    radii: list[float],
    radial_segs: int,
    mat_index: int,
    u_repeats: float = 1.0,
    v_tile_meters: float = 0.8,
    cap_end: bool = True,
    clamp_min_z: float | None = 0.0,
) -> None:
    """Sweep a tapered tube along points with parallel-transport frames and smooth bark UVs."""
    if len(points) < 2 or len(points) != len(radii):
        return

    frames = _parallel_transport_frames(points)
    rings: list[list[bmesh.types.BMVert]] = []
    arc_lengths: list[float] = [0.0]
    for i in range(1, len(points)):
        arc_lengths.append(arc_lengths[-1] + (points[i] - points[i - 1]).length)

    for pt, rad, (_, n_vec, b_vec) in zip(points, radii, frames):
        ring: list[bmesh.types.BMVert] = []
        for s in range(radial_segs):
            theta = (2.0 * math.pi * s) / radial_segs
            offset = (n_vec * math.cos(theta) + b_vec * math.sin(theta)) * rad
            pos = pt + offset
            if clamp_min_z is not None and pos.z < clamp_min_z:
                pos.z = clamp_min_z
            ring.append(bm.verts.new(pos))
        rings.append(ring)

    inv_v = 1.0 / max(0.05, v_tile_meters)
    for r_idx in range(len(rings) - 1):
        ring_a = rings[r_idx]
        ring_b = rings[r_idx + 1]
        va = arc_lengths[r_idx] * inv_v
        vb = arc_lengths[r_idx + 1] * inv_v
        for s in range(radial_segs):
            s_next = (s + 1) % radial_segs
            ua = (s / radial_segs) * u_repeats
            ub = ((s + 1) / radial_segs) * u_repeats
            face = bm.faces.new((ring_a[s], ring_a[s_next], ring_b[s_next], ring_b[s]))
            face.material_index = mat_index
            face.smooth = True
            uvs = ((ua, va), (ub, va), (ub, vb), (ua, vb))
            for loop, uv in zip(face.loops, uvs):
                loop[uv_layer].uv = uv

    if cap_end and radii[-1] > 0.002:
        tip_face = bm.faces.new(rings[-1])
        tip_face.material_index = mat_index
        tip_face.smooth = True
        for loop in tip_face.loops:
            loop[uv_layer].uv = (0.5, arc_lengths[-1] * inv_v)


def _add_curved_card(
    bm: bmesh.types.BMesh,
    uv_layer: bmesh.types.BMLayerItem,
    origin: Vector,
    right_dir: Vector,
    up_dir: Vector,
    width: float,
    height: float,
    cols: int,
    rows: int,
    mat_index: int,
    bend_arch: float = 0.04,
    cup_depth: float = 0.02,
    anchor_mode: str = "bottom",
    clamp_min_z: float | None = 0.0,
) -> None:
    """Build a subdivided curved quad card with exact [0, 1] UV1 per card.

    Blender UV convention: U in [0, 1] left->right, V=0 at card bottom, V=1 at card top.
    On glTF export (export_yup=True), V flips cleanly to Godot top=0, bottom=1.
    """
    r_unit = right_dir.normalized()
    u_unit = up_dir.normalized()
    n_unit = r_unit.cross(u_unit).normalized()

    grid: list[list[bmesh.types.BMVert]] = []
    for iy in range(rows + 1):
        v_frac = iy / rows
        row_verts: list[bmesh.types.BMVert] = []
        for ix in range(cols + 1):
            u_frac = ix / cols
            centered_u = u_frac - 0.5

            local_x = centered_u * width
            local_y = v_frac * height
            if anchor_mode == "bottom":
                arch_offset = bend_arch * (v_frac ** 1.65)
                cup_offset = -cup_depth * (centered_u * 2.0) ** 2 * v_frac
            else:
                arch_offset = bend_arch * math.sin(v_frac * math.pi * 0.85)
                cup_offset = -cup_depth * (centered_u * 2.0) ** 2

            pos = origin + r_unit * local_x + u_unit * local_y + n_unit * (arch_offset + cup_offset)
            if clamp_min_z is not None and pos.z < clamp_min_z:
                pos.z = clamp_min_z
            row_verts.append(bm.verts.new(pos))
        grid.append(row_verts)

    for iy in range(rows):
        v0 = iy / rows
        v1 = (iy + 1) / rows
        for ix in range(cols):
            u0 = ix / cols
            u1 = (ix + 1) / cols
            face = bm.faces.new(
                (
                    grid[iy][ix],
                    grid[iy][ix + 1],
                    grid[iy + 1][ix + 1],
                    grid[iy + 1][ix],
                )
            )
            face.material_index = mat_index
            face.smooth = True
            uvs = ((u0, v0), (u1, v0), (u1, v1), (u0, v1))
            for loop, uv in zip(face.loops, uvs):
                loop[uv_layer].uv = uv


def _finalize_bmesh_and_export(
    name: str,
    bm: bmesh.types.BMesh,
    materials: list[bpy.types.Material],
    output_dir: Path,
    target_height: float,
) -> dict[str, object]:
    """Commit BMesh to Blender object, normalize exact min_z=0 & height, and export GLB."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    for mat in materials:
        mesh.materials.append(mat)

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    # Guarantee exact min_z = 0.0 and exact target height in Blender Z-up
    min_z = min(v.co.z for v in mesh.vertices)
    if abs(min_z) > 1e-6:
        for v in mesh.vertices:
            v.co.z -= min_z
    max_z = max(v.co.z for v in mesh.vertices)
    if max_z > 1e-5 and abs(max_z - target_height) > 1e-4:
        scale_z = target_height / max_z
        for v in mesh.vertices:
            v.co.z *= scale_z
    mesh.update()

    tri_count = sum(max(1, len(p.vertices) - 2) for p in mesh.polygons)
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    # Godot Y-up mapping: (X, Y, Z)_godot = (X, Z, -Y)_blender
    godot_bbox = {
        "min": (round(min(xs), 4), round(min(zs), 4), round(-max(ys), 4)),
        "max": (round(max(xs), 4), round(max(zs), 4), round(-min(ys), 4)),
        "size": (
            round(max(xs) - min(xs), 4),
            round(max(zs) - min(zs), 4),
            round(max(ys) - min(ys), 4),
        ),
    }

    out_path = output_dir / f"{name}.glb"
    export_godot_glb(
        filepath=out_path,
        export_animations=False,
        apply_modifiers=True,
        save_blend=False,
    )
    print(f"[{name}] tris={tri_count} godot_bbox={godot_bbox} path={out_path}")
    return {"name": name, "path": out_path, "tris": tri_count, "godot_bbox": godot_bbox}


def _generate_shrub(
    name: str,
    seed: int,
    target_height: float,
    stem_count: int,
    fork_count: int,
    card_count: int,
    spread_radius: float,
    card_size_range: tuple[float, float],
    output_dir: Path,
) -> dict[str, object]:
    """Generate a broadleaf overgrown yard shrub with woody stems and alpha-scissored leaf cards."""
    clean_scene()
    rng = random.Random(seed)
    mats = _create_foliage_materials()

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    anchors: list[tuple[Vector, Vector]] = []
    stem_height_cap = target_height * 0.72
    base_rad = 0.016 + 0.012 * (target_height / 1.25)

    for s_idx in range(stem_count):
        az = (2.0 * math.pi * s_idx) / stem_count + rng.uniform(-0.22, 0.22)
        pitch_tilt = rng.uniform(0.32, 0.62)  # tilt outward from vertical
        stem_len = stem_height_cap * rng.uniform(0.76, 1.02)
        dir_xy = Vector((math.cos(az), math.sin(az), 0.0))

        # 3-segment curved woody cane rooted at Z=0
        p0 = dir_xy * rng.uniform(0.01, 0.04)
        pts: list[Vector] = []
        rads: list[float] = []
        segs = 3
        for i in range(segs + 1):
            t = i / segs
            radial_reach = spread_radius * 0.68 * (t ** 0.92) * math.sin(pitch_tilt + 0.35)
            wz = stem_len * (t ** 0.88)
            wobble = Vector((rng.uniform(-0.02, 0.02), rng.uniform(-0.02, 0.02), 0.0)) * t
            pts.append(p0 + dir_xy * radial_reach + Vector((0.0, 0.0, wz)) + wobble)
            rads.append(base_rad * (1.0 - 0.68 * t))

        _add_branch_tube(
            bm,
            uv_layer,
            pts,
            rads,
            radial_segs=5,
            mat_index=0,
            u_repeats=1.0,
            v_tile_meters=0.6,
            clamp_min_z=0.0,
        )
        for i in range(1, len(pts)):
            tan = (pts[i] - pts[i - 1]).normalized()
            anchors.append((pts[i], tan))

        # Secondary forks branching off upper half of stem
        forks_here = (fork_count // stem_count) + (1 if s_idx < (fork_count % stem_count) else 0)
        for f_idx in range(forks_here):
            base_pt = pts[1] if f_idx % 2 == 0 else pts[2]
            f_az = az + rng.uniform(-0.85, 0.85)
            f_el = rng.uniform(0.35, 0.95)
            f_len = stem_len * rng.uniform(0.35, 0.55)
            f_dir = Vector(
                (
                    math.cos(f_az) * math.cos(f_el),
                    math.sin(f_az) * math.cos(f_el),
                    math.sin(f_el),
                )
            ).normalized()
            mid_pt = base_pt + f_dir * (f_len * 0.52)
            end_pt = base_pt + f_dir * f_len
            f_r = base_rad * 0.45
            _add_branch_tube(
                bm,
                uv_layer,
                [base_pt, mid_pt, end_pt],
                [f_r, f_r * 0.72, 0.004],
                radial_segs=4,
                mat_index=0,
                u_repeats=1.0,
                v_tile_meters=0.5,
                clamp_min_z=0.0,
            )
            anchors.append((mid_pt, f_dir))
            anchors.append((end_pt, f_dir))

    # Populate angled curved broadleaf cards anchored at stem nodes (V=0 bottom -> V=1 top)
    for c_idx in range(card_count):
        anchor_pt, branch_dir = anchors[c_idx % len(anchors)]
        yaw = rng.uniform(0.0, 2.0 * math.pi)
        # Mix upright crown cards and splayed perimeter cards for lush 3D volume
        tilt_out = rng.uniform(0.28, 0.95) if (c_idx % 3 != 0) else rng.uniform(0.10, 0.35)
        roll = rng.uniform(-0.35, 0.35)

        rot = (
            Matrix.Rotation(yaw, 3, "Z")
            @ Matrix.Rotation(tilt_out, 3, "X")
            @ Matrix.Rotation(roll, 3, "Y")
        )
        right_vec = rot @ Vector((1.0, 0.0, 0.0))
        up_vec = rot @ Vector((0.0, 0.0, 1.0))

        card_w = rng.uniform(card_size_range[0], card_size_range[1])
        card_h = card_w * rng.uniform(0.95, 1.15)
        origin = anchor_pt + branch_dir * rng.uniform(-0.04, 0.04) + Vector(
            (rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03), rng.uniform(-0.02, 0.03))
        )

        _add_curved_card(
            bm=bm,
            uv_layer=uv_layer,
            origin=origin,
            right_dir=right_vec,
            up_dir=up_vec,
            width=card_w,
            height=card_h,
            cols=2,
            rows=2,
            mat_index=1,
            bend_arch=rng.uniform(0.035, 0.075),
            cup_depth=0.015,
            anchor_mode="stem",
            clamp_min_z=0.02,
        )

    return _finalize_bmesh_and_export(
        name,
        bm,
        [mats["overgrown_bark"], mats["foliage_broadleaf_atlas"]],
        output_dir,
        target_height=target_height,
    )


def _generate_grass_tuft(
    name: str,
    seed: int,
    target_height: float,
    card_count: int,
    spread_radius: float,
    tilt_range: tuple[float, float],
    card_width_range: tuple[float, float],
    arch_range: tuple[float, float],
    output_dir: Path,
) -> dict[str, object]:
    """Generate crossed curved wild grass/reed tuft (slot 0: foliage_weeds_atlas)."""
    clean_scene()
    rng = random.Random(seed)
    mats = _create_foliage_materials()

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    # Arrange cards in inner core + outer ring crossed fans so silhouette works from all 360 angles
    inner_n = card_count // 3
    outer_n = card_count - inner_n

    for i in range(card_count):
        is_inner = i < inner_n
        ring_idx = i if is_inner else (i - inner_n)
        ring_total = inner_n if is_inner else outer_n

        yaw = (2.0 * math.pi * ring_idx) / max(1, ring_total) + rng.uniform(-0.24, 0.24)
        # Rotate card normal radially outward + cross diagonal slices
        rot_z = Matrix.Rotation(yaw, 3, "Z")
        right_vec = rot_z @ Vector((1.0, 0.0, 0.0))
        out_dir = rot_z @ Vector((0.0, 1.0, 0.0))

        tilt = rng.uniform(tilt_range[0] * 0.45, tilt_range[1] * 0.65) if is_inner else rng.uniform(tilt_range[0], tilt_range[1])
        up_vec = (Vector((0.0, 0.0, 1.0)) + out_dir * tilt).normalized()

        radial_off = rng.uniform(0.0, spread_radius * (0.28 if is_inner else 0.72))
        offset_ang = yaw + rng.uniform(-0.6, 0.6)
        origin = Vector(
            (
                math.cos(offset_ang) * radial_off,
                math.sin(offset_ang) * radial_off,
                0.0,
            )
        )

        card_w = rng.uniform(card_width_range[0], card_width_range[1])
        h_frac = rng.uniform(0.88, 1.05) if is_inner else rng.uniform(0.68, 0.94)
        card_h = target_height * h_frac

        _add_curved_card(
            bm=bm,
            uv_layer=uv_layer,
            origin=origin,
            right_dir=right_vec,
            up_dir=up_vec,
            width=card_w,
            height=card_h,
            cols=2,
            rows=3,
            mat_index=0,
            bend_arch=rng.uniform(arch_range[0], arch_range[1]),
            cup_depth=0.014,
            anchor_mode="bottom",
            clamp_min_z=0.0,
        )

    return _finalize_bmesh_and_export(
        name,
        bm,
        [mats["foliage_weeds_atlas"]],
        output_dir,
        target_height=target_height,
    )


def main() -> None:
    """Entry point for tools/blender/run.py or direct blender --background --python."""
    try:
        sdk_root = Path(__file__).resolve().parent.parent.parent.parent
        output_dir = sdk_root / "assets" / "models" / "foliage"
        output_dir.mkdir(parents=True, exist_ok=True)

        _generate_shrub(
            name="shrub_plant_01",
            seed=5201,
            target_height=0.65,
            stem_count=4,
            fork_count=4,
            card_count=36,
            spread_radius=0.38,
            card_size_range=(0.24, 0.34),
            output_dir=output_dir,
        )
        _generate_shrub(
            name="shrub_plant_02",
            seed=5202,
            target_height=0.95,
            stem_count=5,
            fork_count=5,
            card_count=38,
            spread_radius=0.56,
            card_size_range=(0.32, 0.46),
            output_dir=output_dir,
        )
        _generate_shrub(
            name="shrub_plant_03",
            seed=5203,
            target_height=1.25,
            stem_count=5,
            fork_count=6,
            card_count=40,
            spread_radius=0.72,
            card_size_range=(0.40, 0.56),
            output_dir=output_dir,
        )
        _generate_grass_tuft(
            name="grass_clump_01",
            seed=5204,
            target_height=0.45,
            card_count=18,
            spread_radius=0.18,
            tilt_range=(0.12, 0.34),
            card_width_range=(0.28, 0.40),
            arch_range=(0.055, 0.095),
            output_dir=output_dir,
        )
        _generate_grass_tuft(
            name="grass_clump_02",
            seed=5205,
            target_height=0.70,
            card_count=18,
            spread_radius=0.22,
            tilt_range=(0.10, 0.30),
            card_width_range=(0.36, 0.50),
            arch_range=(0.08, 0.14),
            output_dir=output_dir,
        )
        _generate_grass_tuft(
            name="grass_leaf_cluster",
            seed=5206,
            target_height=0.35,
            card_count=18,
            spread_radius=0.24,
            tilt_range=(0.24, 0.52),
            card_width_range=(0.28, 0.42),
            arch_range=(0.07, 0.12),
            output_dir=output_dir,
        )
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
