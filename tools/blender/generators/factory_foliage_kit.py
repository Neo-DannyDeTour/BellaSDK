"""Procedural Blender generator for clean-room overgrown factory foliage assets.

Generates 3 modular foliage GLBs in assets/models/foliage/:
- ivy_wall_patch.glb: ~2.4m x 2.8m x 0.3m creeping wall ivy (stems + 52 leaf cards).
- concrete_crack_weeds.glb: ~0.95m x 0.45m x 0.45m ground crack weed cluster (20 cards).
- overgrown_tree.glb: ~6.5m gnarled yard deciduous tree (roots, 3-level branches, 38 cards).

Conventions:
- Origin at bottom-center (Blender Z=0 -> Godot min_y=0, centered on X and Y).
- Leaf/grass cards use clean non-overlapping [0, 1] UV1 per card (Blender V=1 top,
  V=0 bottom -> flips on glTF export to Godot V=0 top, V=1 bottom).
- Bark limbs use continuous parallel-transport cylindrical UVs with seamless wrap.
- Named material slots for Godot ORM / alpha-scissored material assignment.
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
from mathutils import Matrix, Vector

from common.exporter import clean_scene, export_godot_glb
from common.materials import create_pbr_material


def _create_foliage_materials() -> dict[str, bpy.types.Material]:
    """Create clean-room placeholder PBR materials matching Godot slot names."""
    return {
        "bark": create_pbr_material(
            name="bark",
            base_color=(0.22, 0.16, 0.11, 1.0),
            metallic=0.0,
            roughness=0.90,
        ),
        "ivy_leaves": create_pbr_material(
            name="ivy_leaves",
            base_color=(0.18, 0.28, 0.12, 1.0),
            metallic=0.0,
            roughness=0.72,
        ),
        "weed_blades": create_pbr_material(
            name="weed_blades",
            base_color=(0.28, 0.32, 0.16, 1.0),
            metallic=0.0,
            roughness=0.78,
        ),
        "canopy_leaves": create_pbr_material(
            name="canopy_leaves",
            base_color=(0.24, 0.28, 0.13, 1.0),
            metallic=0.0,
            roughness=0.74,
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
    v_tile_meters: float = 1.2,
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

    for idx, (pt, rad, (_, n_vec, b_vec)) in enumerate(zip(points, radii, frames)):
        ring: list[bmesh.types.BMVert] = []
        for s in range(radial_segs):
            theta = (2.0 * math.pi * s) / radial_segs
            # Subtle organic bark fluting on thicker sections
            flute = 1.0 + (0.06 * math.sin(3.0 * theta + idx * 0.7) if rad > 0.08 else 0.0)
            offset = (n_vec * math.cos(theta) + b_vec * math.sin(theta)) * (rad * flute)
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
    anchor_mode: str = "center",
    clamp_min_z: float | None = 0.0,
    clamp_max_y: float | None = None,
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

            if anchor_mode == "bottom":
                local_x = centered_u * width
                local_y = v_frac * height
                # Blades droop outward smoothly from rooted bottom toward tip
                arch_offset = bend_arch * (v_frac ** 1.65)
                cup_offset = -cup_depth * (centered_u * 2.0) ** 2 * v_frac
            elif anchor_mode == "stem":
                # Anchored at bottom-center stem attachment, gentle bow outward
                local_x = centered_u * width
                local_y = v_frac * height
                arch_offset = bend_arch * math.sin(v_frac * math.pi * 0.85)
                cup_offset = -cup_depth * (centered_u * 2.0) ** 2
            else:
                # Canopy dome centered at origin
                local_x = centered_u * width
                local_y = (v_frac - 0.5) * height
                r2 = (centered_u * 2.0) ** 2 + ((v_frac - 0.5) * 2.0) ** 2
                arch_offset = bend_arch * max(0.0, 1.0 - 0.55 * r2)
                cup_offset = 0.0

            pos = origin + r_unit * local_x + u_unit * local_y + n_unit * (arch_offset + cup_offset)
            if clamp_min_z is not None and pos.z < clamp_min_z:
                pos.z = clamp_min_z
            if clamp_max_y is not None and pos.y > clamp_max_y:
                pos.y = clamp_max_y
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
) -> dict[str, object]:
    """Commit BMesh to Blender object, normalize origin if needed, and export GLB."""
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

    # Guarantee exact min_z = 0.0 in Blender (min_y = 0.0 in Godot)
    min_z = min(v.co.z for v in mesh.vertices)
    if abs(min_z) > 1e-5:
        for v in mesh.vertices:
            v.co.z -= min_z
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


def generate_ivy_wall_patch(output_dir: Path) -> dict[str, object]:
    """Generate ~2.4m x 2.8m x 0.3m creeping wall ivy GLB with bark stems and 52 leaf cards."""
    clean_scene()
    rng = random.Random(4101)
    mats = _create_foliage_materials()

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    # 1. Branching woody vine stems along Godot Z=0..0.06 (Blender Y=-0.06..0.0)
    main_stems_spec = [
        (-0.55, 2.55, -0.35),
        (-0.12, 2.74, 0.12),
        (0.28, 2.66, 0.42),
        (0.68, 2.25, 0.92),
    ]
    stem_anchors: list[tuple[Vector, Vector]] = []

    for idx, (x0, h_max, x_drift) in enumerate(main_stems_spec):
        segs = 11
        pts: list[Vector] = []
        rads: list[float] = []
        for i in range(segs + 1):
            t = i / segs
            px = x0 + x_drift * (t ** 1.1) + 0.11 * math.sin(t * math.pi * 2.4 + idx * 1.3)
            px = max(-1.10, min(1.10, px))
            py = -(0.024 + 0.024 * (0.5 + 0.5 * math.sin(t * math.pi * 3.1 + idx)))
            pz = t * h_max
            pts.append(Vector((px, py, pz)))
            rads.append(0.022 * (1.0 - 0.72 * t))

        _add_branch_tube(
            bm,
            uv_layer,
            pts,
            rads,
            radial_segs=6,
            mat_index=0,
            u_repeats=1.0,
            v_tile_meters=0.5,
            clamp_min_z=0.0,
        )
        for i in range(1, len(pts)):
            tangent = (pts[i] - pts[i - 1]).normalized()
            stem_anchors.append((pts[i], tangent))

        # 3 lateral tendril forks per main stem
        for fork_t, side in ((0.28, -1.0), (0.54, 1.0), (0.76, -1.0)):
            f_idx = max(1, min(segs - 1, int(fork_t * segs)))
            base_pt = pts[f_idx]
            branch_pts: list[Vector] = []
            branch_rads: list[float] = []
            b_len = rng.uniform(0.45, 0.75)
            b_steps = 5
            for bi in range(b_steps + 1):
                bt = bi / b_steps
                bx = base_pt.x + side * b_len * bt * rng.uniform(0.75, 1.05)
                bx = max(-1.15, min(1.15, bx))
                by = -(0.026 + 0.020 * math.sin(bt * math.pi * 0.8 + idx))
                bz = min(2.74, base_pt.z + bt * b_len * 0.58 + 0.04 * math.sin(bt * math.pi))
                branch_pts.append(Vector((bx, by, bz)))
                branch_rads.append(0.012 * (1.0 - 0.65 * bt))

            _add_branch_tube(
                bm,
                uv_layer,
                branch_pts,
                branch_rads,
                radial_segs=5,
                mat_index=0,
                u_repeats=1.0,
                v_tile_meters=0.5,
                clamp_min_z=0.0,
            )
            for bi in range(1, len(branch_pts)):
                btan = (branch_pts[bi] - branch_pts[bi - 1]).normalized()
                stem_anchors.append((branch_pts[bi], btan))

    # 2. 52 angled/curved quad leaf cards with full [0, 1] UV1 mapping
    # Choose 52 evenly spread + jittered anchor samples from stem_anchors
    target_cards = 52
    chosen_indices = [
        int(i * (len(stem_anchors) - 1) / (target_cards - 1)) for i in range(target_cards)
    ]
    for card_i, a_idx in enumerate(chosen_indices):
        anchor_pt, _ = stem_anchors[a_idx]
        # Card sits forward of stems in Godot +Z (Blender -Y), within 0.30m depth
        card_size = rng.uniform(0.34, 0.50)
        card_w = card_size * rng.uniform(0.88, 1.12)
        card_h = card_size * rng.uniform(0.92, 1.16)

        # Tilt outward from wall (-Y in Blender = +Z in Godot) so leaves catch light
        yaw = rng.uniform(-0.55, 0.55)
        pitch_out = rng.uniform(0.34, 0.80)  # tilt top away from wall
        roll = rng.uniform(-0.50, 0.50)

        rot = (
            Matrix.Rotation(yaw, 3, "Z")
            @ Matrix.Rotation(-pitch_out, 3, "X")
            @ Matrix.Rotation(roll, 3, "Y")
        )
        right_vec = rot @ Vector((1.0, 0.0, 0.0))
        # Base up vector points upward (+Z) with outward tilt (-Y)
        up_vec = rot @ Vector((0.0, 0.0, 1.0))

        # Offset slightly off stem and keep inside ~2.4m x 2.8m x 0.3m envelope
        jitter = Vector(
            (
                rng.uniform(-0.08, 0.08),
                -rng.uniform(0.020, 0.095),
                rng.uniform(-0.06, 0.04),
            )
        )
        card_origin = anchor_pt + jitter
        card_origin.x = max(-0.98, min(0.98, card_origin.x))
        card_origin.z = max(0.02, min(2.42, card_origin.z))
        # Ensure outer tip stays within ~0.30m depth (Blender Y >= -0.30)
        if card_origin.y < -0.14:
            card_origin.y = -0.14

        _add_curved_card(
            bm=bm,
            uv_layer=uv_layer,
            origin=card_origin,
            right_dir=right_vec,
            up_dir=up_vec,
            width=card_w,
            height=card_h,
            cols=2,
            rows=2,
            mat_index=1,
            bend_arch=-0.055,  # bow outward toward -Y (Godot +Z)
            cup_depth=-0.025,
            anchor_mode="stem",
            clamp_min_z=0.0,
            clamp_max_y=0.0,
        )

    # Clamp vertices to stay strictly within ~2.4m x 2.8m x 0.30m (Godot Z >= 0.0)
    for v in bm.verts:
        v.co.y = max(-0.30, min(0.0, v.co.y))
        v.co.x = max(-1.20, min(1.20, v.co.x))
        v.co.z = max(0.0, min(2.80, v.co.z))

    return _finalize_bmesh_and_export(
        "ivy_wall_patch",
        bm,
        [mats["bark"], mats["ivy_leaves"]],
        output_dir,
    )


def generate_concrete_crack_weeds(output_dir: Path) -> dict[str, object]:
    """Generate ~0.95m x 0.45m x 0.45m ground-crack grass/weed cluster (20 crossed cards)."""
    clean_scene()
    rng = random.Random(4102)
    mats = _create_foliage_materials()

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    # 5 tufts along an S-curved concrete crack spanning ~0.95m along X
    tuft_centers = [
        (-0.34, 0.025, 0.82),
        (-0.17, -0.020, 1.00),
        (0.00, 0.015, 1.08),
        (0.18, -0.025, 0.96),
        (0.35, 0.020, 0.80),
    ]

    # 4 crossed/angled cards per tuft = 20 cards total (within 16-24 requirement)
    for t_idx, (cx, cy, h_scale) in enumerate(tuft_centers):
        base_yaw = t_idx * 0.42
        for c_idx in range(4):
            yaw = base_yaw + c_idx * (math.pi * 0.25) + rng.uniform(-0.14, 0.14)
            tilt = rng.uniform(0.08, 0.28)
            card_w = rng.uniform(0.24, 0.34)
            card_h = rng.uniform(0.33, 0.45) * h_scale

            rot_z = Matrix.Rotation(yaw, 3, "Z")
            right_vec = rot_z @ Vector((1.0, 0.0, 0.0))
            # Lean outward slightly along card normal
            tilt_dir = rot_z @ Vector((0.0, 1.0, 0.0))
            up_vec = (Vector((0.0, 0.0, 1.0)) + tilt_dir * tilt).normalized()

            origin = Vector(
                (
                    cx + rng.uniform(-0.045, 0.045),
                    cy + rng.uniform(-0.045, 0.045),
                    0.0,
                )
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
                rows=3,
                mat_index=0,
                bend_arch=rng.uniform(0.055, 0.095),
                cup_depth=0.018,
                anchor_mode="bottom",
                clamp_min_z=0.0,
            )

    # Ensure clean target footprint ~0.95m x 0.45m x 0.45m
    for v in bm.verts:
        v.co.x = max(-0.475, min(0.475, v.co.x))
        v.co.y = max(-0.225, min(0.225, v.co.y))
        v.co.z = max(0.0, min(0.455, v.co.z))

    return _finalize_bmesh_and_export(
        "concrete_crack_weeds",
        bm,
        [mats["weed_blades"]],
        output_dir,
    )


def generate_overgrown_tree(output_dir: Path) -> dict[str, object]:
    """Generate ~6.5m gnarled yard deciduous tree (roots, trunk, 3-level branches, 38 cards)."""
    clean_scene()
    rng = random.Random(4103)
    mats = _create_foliage_materials()

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    # 1. Gnarled main trunk (Level 0) from Z=0.0 to Z=2.75m
    trunk_pts = [
        Vector((0.00, 0.00, 0.00)),
        Vector((0.02, -0.01, 0.45)),
        Vector((0.06, 0.03, 1.00)),
        Vector((0.03, 0.07, 1.60)),
        Vector((-0.03, 0.05, 2.20)),
        Vector((-0.06, 0.02, 2.75)),
    ]
    trunk_rads = [0.30, 0.23, 0.20, 0.185, 0.165, 0.135]
    _add_branch_tube(
        bm,
        uv_layer,
        trunk_pts,
        trunk_rads,
        radial_segs=10,
        mat_index=0,
        u_repeats=2.0,
        v_tile_meters=1.4,
        clamp_min_z=0.0,
    )

    # 2. Flared roots (5 buttresses anchored cleanly at Z=0.0)
    for r_i in range(5):
        angle = (2.0 * math.pi * r_i) / 5.0 + rng.uniform(-0.18, 0.18)
        dir_xy = Vector((math.cos(angle), math.sin(angle), 0.0))
        reach = rng.uniform(0.50, 0.66)
        root_pts = [
            Vector((0.0, 0.0, 0.68)) + dir_xy * 0.10,
            dir_xy * (reach * 0.42) + Vector((0.0, 0.0, 0.30)),
            dir_xy * (reach * 0.78) + Vector((0.0, 0.0, 0.09)),
            dir_xy * reach + Vector((0.0, 0.0, 0.00)),
        ]
        root_rads = [0.115, 0.095, 0.065, 0.026]
        _add_branch_tube(
            bm,
            uv_layer,
            root_pts,
            root_rads,
            radial_segs=7,
            mat_index=0,
            u_repeats=1.0,
            v_tile_meters=1.0,
            clamp_min_z=0.0,
        )

    # 3. Level 1 Primary Boughs -> Level 2 Secondary -> Level 3 Tertiary Twigs
    canopy_anchors: list[tuple[Vector, Vector]] = []
    bough_specs = [
        (trunk_pts[3], 0.35, 0.78, 1.35, 0.120),
        (trunk_pts[4], 1.65, 0.72, 1.45, 0.115),
        (trunk_pts[4], 2.95, 0.75, 1.40, 0.115),
        (trunk_pts[5], 4.25, 0.68, 1.35, 0.110),
        (trunk_pts[5], 5.45, 0.56, 1.45, 0.110),
    ]

    for b_idx, (start_pt, azim, pitch_rad, length, base_r) in enumerate(bough_specs):
        dir_1 = Vector(
            (
                math.cos(azim) * math.cos(pitch_rad),
                math.sin(azim) * math.cos(pitch_rad),
                math.sin(pitch_rad),
            )
        ).normalized()
        mid_1 = start_pt + dir_1 * (length * 0.52) + Vector((0.0, 0.0, 0.12))
        end_1 = start_pt + dir_1 * length + Vector((0.05 * math.sin(b_idx), 0.0, 0.08))
        pts_1 = [start_pt, mid_1, end_1]
        rads_1 = [base_r, base_r * 0.78, base_r * 0.58]
        _add_branch_tube(
            bm,
            uv_layer,
            pts_1,
            rads_1,
            radial_segs=7,
            mat_index=0,
            u_repeats=1.0,
            v_tile_meters=1.2,
            clamp_min_z=0.0,
        )

        # Level 2 Secondary Branches (2-3 per primary bough)
        sec_count = 3 if b_idx in (1, 3, 4) else 2
        for s_idx in range(sec_count):
            sec_origin = mid_1 if s_idx == 0 and sec_count == 3 else end_1
            spread = (s_idx - (sec_count - 1) * 0.5) * 0.58 + rng.uniform(-0.10, 0.10)
            az_2 = azim + spread
            el_2 = pitch_rad + rng.uniform(-0.12, 0.24)
            len_2 = rng.uniform(0.75, 1.00)
            dir_2 = Vector(
                (
                    math.cos(az_2) * math.cos(el_2),
                    math.sin(az_2) * math.cos(el_2),
                    math.sin(el_2),
                )
            ).normalized()
            mid_2 = sec_origin + dir_2 * (len_2 * 0.5) + Vector((0.0, 0.0, 0.06))
            end_2 = sec_origin + dir_2 * len_2
            r2 = base_r * 0.56
            _add_branch_tube(
                bm,
                uv_layer,
                [sec_origin, mid_2, end_2],
                [r2, r2 * 0.75, r2 * 0.52],
                radial_segs=6,
                mat_index=0,
                u_repeats=1.0,
                v_tile_meters=1.0,
                clamp_min_z=0.0,
            )
            canopy_anchors.append((end_2, dir_2))

            # Level 3 Tertiary Twigs (2 per secondary branch)
            for t_idx in range(2):
                twig_origin = mid_2 if t_idx == 0 else end_2
                az_3 = az_2 + (-0.42 if t_idx == 0 else 0.42) + rng.uniform(-0.14, 0.14)
                el_3 = el_2 + rng.uniform(-0.12, 0.28)
                len_3 = rng.uniform(0.45, 0.68)
                dir_3 = Vector(
                    (
                        math.cos(az_3) * math.cos(el_3),
                        math.sin(az_3) * math.cos(el_3),
                        math.sin(el_3),
                    )
                ).normalized()
                end_3 = twig_origin + dir_3 * len_3
                # Keep top twigs under ~5.95m so leaf cards top out near 6.50m
                if end_3.z > 5.85:
                    end_3.z = 5.85
                mid_3 = (twig_origin + end_3) * 0.5 + Vector((0.0, 0.0, 0.04))
                r3 = r2 * 0.50
                _add_branch_tube(
                    bm,
                    uv_layer,
                    [twig_origin, mid_3, end_3],
                    [r3, r3 * 0.70, 0.014],
                    radial_segs=5,
                    mat_index=0,
                    u_repeats=1.0,
                    v_tile_meters=0.8,
                    clamp_min_z=0.0,
                )
                canopy_anchors.append((end_3, dir_3))

    # 4. 38 angled crossed canopy branch-leaf cards (within 30-45 requirement)
    target_cards = 38
    for c_idx in range(target_cards):
        anchor_pt, branch_dir = canopy_anchors[c_idx % len(canopy_anchors)]
        # Alternate crossed orientations (horizontal umbrella vs pitched side planes)
        yaw = rng.uniform(0.0, 2.0 * math.pi)
        pitch = rng.uniform(0.32, 0.92) if (c_idx % 2 == 0) else rng.uniform(0.95, 1.38)
        roll = rng.uniform(-0.45, 0.45)

        rot = (
            Matrix.Rotation(yaw, 3, "Z")
            @ Matrix.Rotation(pitch, 3, "X")
            @ Matrix.Rotation(roll, 3, "Y")
        )
        right_vec = rot @ Vector((1.0, 0.0, 0.0))
        up_vec = rot @ Vector((0.0, 0.0, 1.0))

        card_w = rng.uniform(1.15, 1.55)
        card_h = rng.uniform(1.10, 1.50)
        offset = branch_dir * rng.uniform(0.04, 0.20) + Vector(
            (rng.uniform(-0.16, 0.16), rng.uniform(-0.16, 0.16), rng.uniform(-0.08, 0.18))
        )
        card_origin = anchor_pt + offset
        # Ensure tree apex lands cleanly around 6.45..6.55m
        if c_idx == 0:
            card_origin = Vector((0.05, -0.05, 5.82))
            card_h = 1.38
        elif card_origin.z + card_h * 0.5 > 6.50:
            card_origin.z = 6.48 - card_h * 0.5

        _add_curved_card(
            bm=bm,
            uv_layer=uv_layer,
            origin=card_origin,
            right_dir=right_vec,
            up_dir=up_vec,
            width=card_w,
            height=card_h,
            cols=2,
            rows=2,
            mat_index=1,
            bend_arch=rng.uniform(0.14, 0.24),
            cup_depth=0.0,
            anchor_mode="center",
            clamp_min_z=2.10,
        )

    return _finalize_bmesh_and_export(
        "overgrown_tree",
        bm,
        [mats["bark"], mats["canopy_leaves"]],
        output_dir,
    )


def main() -> None:
    """Entry point for tools/blender/run.py or direct blender --background --python."""
    try:
        sdk_root = Path(__file__).resolve().parent.parent.parent.parent
        output_dir = sdk_root / "assets" / "models" / "foliage"
        generate_ivy_wall_patch(output_dir)
        generate_concrete_crack_weeds(output_dir)
        generate_overgrown_tree(output_dir)
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
