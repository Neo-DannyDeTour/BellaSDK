"""Procedural Blender generator for modular factory roof gable and terrace parapet shells.

Generates 3 modular shell GLBs in assets/models/factory_shells/:
1. roof_arch_wall.glb        - 4.0m W x 1.80m H x 0.35m D barrel-vault concrete gable infill
                               with curved rusted-steel arch rim flange, keystone collar,
                               bottom chord tie-beam & recessed circular louvered vent.
2. terrace_parapet_4m.glb    - 4.0m W x 1.15m H x 0.35m D rooftop parapet with lower curb lip,
                               twin end pilasters, rainwater scupper & sloped steel coping cap.
3. terrace_parapet_corner.glb - 1.0m x 1.0m x 1.15m H L-shaped 90-degree parapet corner
                               (Godot Leg A: X[-0.5..0.5], Z[-0.5..-0.15] -> Blender Y[0.15..0.5];
                               Godot Leg B: X[-0.5..-0.15], Z[-0.5..0.5] -> Blender Y[-0.5..0.5]).

Conventions:
- Origin at bottom-center (Blender Z=0 -> Godot min_y=0, centered on X and Y).
- Godot Y-up export (export_yup=True): Godot +X = Blender +X, +Y = +Z, +Z = -Y.
- Clean world-metric cubic box UVs (2.0m tile).
- Material slots strictly ordered: [0: concrete, 1: steel].
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parent.parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bmesh
import bpy
from common.exporter import clean_scene, export_godot_glb
from common.materials import assign_material, create_pbr_material
from mathutils import Matrix, Vector

# Shared modular dimensions (meters) matching factory_wall_kit.py
WALL_WIDTH = 4.0
WALL_THICK = 0.35
PANEL_RECESS_THICK = 0.29
PILASTER_WIDTH = 0.22

# Roof arch wall constants
ARCH_HEIGHT = 1.80
ARCH_CENTER_Z = -0.25
ARCH_OUTER_R = 2.05  # Z(x=0)=1.80, Z(x=+/-2.0)=0.20
ARCH_INNER_R = 1.95
VENT_CENTER_Z = 0.91
VENT_OPEN_R = 0.42

# Terrace parapet constants
PARAPET_HEIGHT = 1.15
CURB_HEIGHT = 0.18
COPING_BASE_Z = 1.07
COPING_DRIP_Z = 1.045
COPING_EDGE_Z = 1.112
COPING_RIDGE_Z = 1.142
COPING_CLEAT_RIDGE_Z = 1.150
COPING_HALF_D = 0.20  # 0.40m D cap


def _create_kit_materials() -> tuple[bpy.types.Material, bpy.types.Material]:
    """Create 'concrete' and 'steel' material slots for Godot ORM reassignment."""
    concrete_mat = create_pbr_material(
        name="concrete",
        base_color=(0.44, 0.43, 0.41, 1.0),
        metallic=0.0,
        roughness=0.88,
    )
    steel_mat = create_pbr_material(
        name="steel",
        base_color=(0.24, 0.16, 0.12, 1.0),
        metallic=0.82,
        roughness=0.62,
    )
    return concrete_mat, steel_mat


def _add_box(
    name: str,
    size: tuple[float, float, float],
    location: tuple[float, float, float],
    bevel_width: float = 0.006,
    rotation_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    """Create a scaled cube with applied rotation/scale and optional bevel modifier."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    obj.rotation_euler = tuple(math.radians(a) for a in rotation_deg)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bevel_width > 0.0:
        bev = obj.modifiers.new(name="Bevel", type="BEVEL")
        bev.width = bevel_width
        bev.segments = 1
        bev.limit_method = "ANGLE"
        bev.angle_limit = math.radians(30.0)
    return obj


def _add_rivet(
    name: str,
    center: tuple[float, float, float],
    axis: str = "Y",
    radius: float = 0.015,
    depth: float = 0.022,
    segments: int = 6,
) -> bpy.types.Object:
    """Create a chunky low-poly manifold hex rivet head."""
    rot_euler = (math.radians(90.0), 0.0, 0.0) if axis == "Y" else (0.0, 0.0, 0.0)
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=segments,
        radius=radius,
        depth=depth,
        end_fill_type="NGON",
        location=center,
        rotation=rot_euler,
    )
    obj = bpy.context.active_object
    obj.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return obj


def _apply_box_uvs(obj: bpy.types.Object, tile_meters: float = 2.0) -> None:
    """Generate clean world-metric cubic box UVs (2.0m tile) on the final merged mesh."""
    mesh = obj.data
    uv_obj = mesh.uv_layers.active
    if uv_obj is None:
        uv_obj = mesh.uv_layers[0] if len(mesh.uv_layers) > 0 else mesh.uv_layers.new(name="UVMap")
        mesh.uv_layers.active = uv_obj
    uv_layer = uv_obj.data

    inv_tile = 1.0 / tile_meters
    for poly in mesh.polygons:
        nx, ny, nz = abs(poly.normal.x), abs(poly.normal.y), abs(poly.normal.z)
        for loop_idx in poly.loop_indices:
            vert = mesh.vertices[mesh.loops[loop_idx].vertex_index].co
            if nx >= ny and nx >= nz:
                u, v = vert.y * inv_tile, vert.z * inv_tile
            elif ny >= nx and ny >= nz:
                u, v = vert.x * inv_tile, vert.z * inv_tile
            else:
                u, v = vert.x * inv_tile, vert.y * inv_tile
            uv_layer[loop_idx].uv = (u, v)


def _finalize_and_export(
    name: str,
    concrete_parts: list[bpy.types.Object],
    steel_parts: list[bpy.types.Object],
    concrete_mat: bpy.types.Material,
    steel_mat: bpy.types.Material,
    output_dir: Path,
) -> dict[str, object]:
    """Apply modifiers, assign [0: concrete, 1: steel] slots, join, UV-map, and export GLB."""
    for part in concrete_parts:
        bpy.context.view_layer.objects.active = part
        for mod in list(part.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        part.data.materials.clear()
        assign_material(part, concrete_mat)

    for part in steel_parts:
        bpy.context.view_layer.objects.active = part
        for mod in list(part.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        part.data.materials.clear()
        assign_material(part, steel_mat)

    all_parts = concrete_parts + steel_parts
    bpy.ops.object.select_all(action="DESELECT")
    for part in all_parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = concrete_parts[0]
    bpy.ops.object.join()

    obj = bpy.context.active_object
    obj.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    _apply_box_uvs(obj, tile_meters=2.0)

    tri_count = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    bbox_blender = (
        round(min(xs), 4),
        round(max(xs), 4),
        round(min(ys), 4),
        round(max(ys), 4),
        round(min(zs), 4),
        round(max(zs), 4),
    )
    bbox_godot = (
        round(min(xs), 4),
        round(max(xs), 4),
        round(min(zs), 4),
        round(max(zs), 4),
        round(-max(ys), 4),
        round(-min(ys), 4),
    )
    slots = [(i, m.name) for i, m in enumerate(obj.data.materials)]

    out_path = output_dir / f"{name}.glb"
    export_godot_glb(
        filepath=out_path,
        export_animations=False,
        apply_modifiers=True,
        save_blend=False,
    )
    print(
        f"[{name}] slots={slots} tris={tri_count} "
        f"blender_bbox={bbox_blender} godot_bbox={bbox_godot} path={out_path}"
    )
    return {
        "name": name,
        "path": out_path,
        "slots": slots,
        "tris": tri_count,
        "blender_bbox": bbox_blender,
        "godot_bbox": bbox_godot,
    }


def _mesh_from_bmesh(name: str, bm: bmesh.types.BMesh) -> bpy.types.Object:
    """Convert a BMesh into a scene mesh object with recalculated outward normals."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.loops.layers.uv.verify()
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def _build_arch_concrete_tympanum(name: str) -> bpy.types.Object:
    """Build barrel-vault concrete gable infill with clean circular vent cutout."""
    bm = bmesh.new()
    half_y = PANEL_RECESS_THICK * 0.5
    r_arch = 1.965
    z_base = 0.20

    # 24 outer loop points ordered CCW around (0, VENT_CENTER_Z):
    # 17 arch points from right spring -> crown -> left spring + 7 bottom chord points.
    a_start = math.atan2(z_base - ARCH_CENTER_Z, math.sqrt(r_arch * r_arch - (z_base - ARCH_CENTER_Z) ** 2))
    a_end = math.pi - a_start
    n_arch = 17
    outer_pts: list[tuple[float, float]] = []
    for i in range(n_arch):
        ang = a_start + (a_end - a_start) * (float(i) / float(n_arch - 1))
        outer_pts.append((r_arch * math.cos(ang), ARCH_CENTER_Z + r_arch * math.sin(ang)))

    x_left, _ = outer_pts[-1]
    x_right, _ = outer_pts[0]
    n_bot = 7
    for i in range(1, n_bot + 1):
        frac = float(i) / float(n_bot + 1)
        outer_pts.append((x_left + (x_right - x_left) * frac, z_base))

    # Match each outer point to the exact angular direction on the inner circular cutout
    n_loop = len(outer_pts)
    inner_pts: list[tuple[float, float]] = []
    for ox, oz in outer_pts:
        phi = math.atan2(oz - VENT_CENTER_Z, ox)
        inner_pts.append((VENT_OPEN_R * math.cos(phi), VENT_CENTER_Z + VENT_OPEN_R * math.sin(phi)))

    out_front = [bm.verts.new((x, -half_y, z)) for x, z in outer_pts]
    out_back = [bm.verts.new((x, half_y, z)) for x, z in outer_pts]
    in_front = [bm.verts.new((x, -half_y, z)) for x, z in inner_pts]
    in_back = [bm.verts.new((x, half_y, z)) for x, z in inner_pts]

    for i in range(n_loop):
        j = (i + 1) % n_loop
        # Front face (facing -Y)
        bm.faces.new((out_front[i], out_front[j], in_front[j], in_front[i]))
        # Back face (facing +Y)
        bm.faces.new((out_back[j], out_back[i], in_back[i], in_back[j]))
        # Outer rim wall
        bm.faces.new((out_front[j], out_front[i], out_back[i], out_back[j]))
        # Inner circular vent cutout wall
        bm.faces.new((in_front[i], in_front[j], in_back[j], in_back[i]))

    return _mesh_from_bmesh(name, bm)


def _build_arch_steel_rim_flange(name: str, segments: int = 20) -> bpy.types.Object:
    """Build stepped outer rusted-steel arch rim flange (0.06m proud of recessed concrete)."""
    bm = bmesh.new()

    # Cross-section in (radius, Y): stepped T/channel flange proud on both -Y and +Y
    # Concrete face is at +/-0.145; outer flange reaches +/-0.205 (0.06m proud).
    r_in = ARCH_INNER_R
    r_step = 2.008
    r_out = ARCH_OUTER_R
    y_web = 0.180
    y_flange = 0.205
    profile = [
        (r_in, -y_web),
        (r_step, -y_web),
        (r_step, -y_flange),
        (r_out, -y_flange),
        (r_out, y_flange),
        (r_step, y_flange),
        (r_step, y_web),
        (r_in, y_web),
    ]

    z_spring = 0.20
    a_start = math.atan2(z_spring - ARCH_CENTER_Z, math.sqrt(r_out * r_out - (z_spring - ARCH_CENTER_Z) ** 2))
    a_end = math.pi - a_start

    rings: list[list[bmesh.types.BMVert]] = []
    for s in range(segments + 1):
        ang = a_start + (a_end - a_start) * (float(s) / float(segments))
        ca, sa = math.cos(ang), math.sin(ang)
        ring = [bm.verts.new((r * ca, y, ARCH_CENTER_Z + r * sa)) for r, y in profile]
        rings.append(ring)

    n_prof = len(profile)
    for s in range(segments):
        r0 = rings[s]
        r1 = rings[s + 1]
        for k in range(n_prof):
            kn = (k + 1) % n_prof
            bm.faces.new((r0[k], r0[kn], r1[kn], r1[k]))

    # End caps at right and left spring ends
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])

    return _mesh_from_bmesh(name, bm)


def _build_ring_collar(
    name: str,
    center: tuple[float, float],
    r_inner: float,
    r_outer: float,
    half_y: float,
    segments: int = 20,
) -> bpy.types.Object:
    """Build a closed circular cylindrical collar/bezel lying in the XZ plane."""
    bm = bmesh.new()
    cx, cz = center
    in_f: list[bmesh.types.BMVert] = []
    in_b: list[bmesh.types.BMVert] = []
    out_f: list[bmesh.types.BMVert] = []
    out_b: list[bmesh.types.BMVert] = []
    for i in range(segments):
        ang = 2.0 * math.pi * (float(i) / float(segments))
        ca, sa = math.cos(ang), math.sin(ang)
        in_f.append(bm.verts.new((cx + r_inner * ca, -half_y, cz + r_inner * sa)))
        in_b.append(bm.verts.new((cx + r_inner * ca, half_y, cz + r_inner * sa)))
        out_f.append(bm.verts.new((cx + r_outer * ca, -half_y, cz + r_outer * sa)))
        out_b.append(bm.verts.new((cx + r_outer * ca, half_y, cz + r_outer * sa)))

    for i in range(segments):
        j = (i + 1) % segments
        bm.faces.new((out_f[i], out_f[j], in_f[j], in_f[i]))
        bm.faces.new((out_b[j], out_b[i], in_b[i], in_b[j]))
        bm.faces.new((out_f[j], out_f[i], out_b[i], out_b[j]))
        bm.faces.new((in_f[i], in_f[j], in_b[j], in_b[i]))

    return _mesh_from_bmesh(name, bm)


def generate_roof_arch_wall(output_dir: Path) -> dict[str, object]:
    """Generate 4.0m W x 1.80m H x 0.35m D barrel-vault concrete gable infill."""
    clean_scene()
    concrete_mat, steel_mat = _create_kit_materials()

    concrete_parts: list[bpy.types.Object] = []
    # Stepped concrete base lip (Z: 0.00..0.11 full 0.35m D, Z: 0.11..0.21 stepped 0.32m D)
    concrete_parts.append(
        _add_box(
            "Arch_Base_Lip_Low",
            (WALL_WIDTH, WALL_THICK, 0.11),
            (0.0, 0.0, 0.055),
            bevel_width=0.006,
        )
    )
    concrete_parts.append(
        _add_box(
            "Arch_Base_Lip_Step",
            (WALL_WIDTH - 0.04, 0.32, 0.10),
            (0.0, 0.0, 0.16),
            bevel_width=0.005,
        )
    )
    # Recessed concrete arched tympanum infill with circular cutout
    concrete_parts.append(_build_arch_concrete_tympanum("Arch_Concrete_Tympanum"))
    # Subtle vertical concrete pilaster ribs flanking the central vent
    for tag, rx in (("L", -0.88), ("R", 0.88)):
        concrete_parts.append(
            _add_box(
                f"Arch_Rib_{tag}",
                (0.11, PANEL_RECESS_THICK + 0.025, 1.08),
                (rx, 0.0, 0.84),
                bevel_width=0.004,
            )
        )

    steel_parts: list[bpy.types.Object] = []
    # Curved outer rusted-steel arch rim flange (0.06m proud of recessed concrete)
    steel_parts.append(_build_arch_steel_rim_flange("Arch_Steel_Rim_Flange", segments=20))

    # Riveted steel keystone collar at crown (top flush at Z=1.800m)
    steel_parts.append(
        _add_box(
            "Arch_Keystone_Collar",
            (0.38, 0.425, 0.25),
            (0.0, 0.0, 1.665),
            bevel_width=0.008,
        )
    )
    steel_parts.append(
        _add_box(
            "Arch_Keystone_Cap",
            (0.44, 0.435, 0.064),
            (0.0, 0.0, 1.768),
            bevel_width=0.006,
        )
    )
    for rx in (-0.12, 0.12):
        for rz in (1.59, 1.70):
            for side in (-1.0, 1.0):
                steel_parts.append(
                    _add_rivet(
                        f"Arch_Keystone_Rivet_{rx}_{rz}_{side}",
                        (rx, side * 0.214, rz),
                        axis="Y",
                        radius=0.015,
                        depth=0.020,
                    )
                )

    # Bottom chord steel tie-beam (I-section) + spring gusset plates + center splice
    steel_parts.append(
        _add_box(
            "Arch_TieBeam_BotFlange",
            (WALL_WIDTH, WALL_THICK + 0.02, 0.03),
            (0.0, 0.0, 0.195),
            bevel_width=0.004,
        )
    )
    steel_parts.append(
        _add_box(
            "Arch_TieBeam_Web",
            (WALL_WIDTH - 0.02, 0.24, 0.08),
            (0.0, 0.0, 0.25),
            bevel_width=0.0,
        )
    )
    steel_parts.append(
        _add_box(
            "Arch_TieBeam_TopFlange",
            (WALL_WIDTH - 0.04, WALL_THICK + 0.02, 0.03),
            (0.0, 0.0, 0.305),
            bevel_width=0.004,
        )
    )
    # Corner gussets tying arch rim ends into the bottom chord tie-beam
    for tag, sign in (("L", -1.0), ("R", 1.0)):
        steel_parts.append(
            _add_box(
                f"Arch_Spring_Gusset_{tag}",
                (0.32, 0.415, 0.26),
                (sign * 1.84, 0.0, 0.31),
                bevel_width=0.005,
            )
        )
        for gx, gz in ((sign * 1.92, 0.25), (sign * 1.76, 0.25), (sign * 1.88, 0.37)):
            for side in (-1.0, 1.0):
                steel_parts.append(
                    _add_rivet(
                        f"Arch_Gusset_Rivet_{tag}_{gx}_{gz}_{side}",
                        (gx, side * 0.209, gz),
                        axis="Y",
                        radius=0.014,
                        depth=0.018,
                    )
                )

    # Center tie-beam splice collar
    steel_parts.append(
        _add_box(
            "Arch_TieBeam_Splice",
            (0.34, 0.39, 0.155),
            (0.0, 0.0, 0.25),
            bevel_width=0.004,
        )
    )

    # Recessed circular louvered steel vent grill in center
    steel_parts.append(
        _build_ring_collar(
            "Arch_Vent_Bezel",
            center=(0.0, VENT_CENTER_Z),
            r_inner=0.385,
            r_outer=0.455,
            half_y=0.175,
            segments=20,
        )
    )
    steel_parts.append(
        _build_ring_collar(
            "Arch_Vent_InnerSleeve",
            center=(0.0, VENT_CENTER_Z),
            r_inner=0.375,
            r_outer=0.415,
            half_y=0.142,
            segments=20,
        )
    )
    # Center vertical louver mullion bar
    steel_parts.append(
        _add_box(
            "Arch_Vent_CenterMullion",
            (0.032, 0.12, 0.74),
            (0.0, 0.0, VENT_CENTER_Z),
            bevel_width=0.003,
        )
    )
    # 7 angled steel louver blades inside the circular opening
    for idx in range(-3, 4):
        dz = idx * 0.092
        r_eff = abs(dz) + 0.030
        blade_w = 2.0 * math.sqrt(max(0.01, 0.372 * 0.372 - r_eff * r_eff))
        steel_parts.append(
            _add_box(
                f"Arch_Vent_Louver_{idx + 3}",
                (blade_w, 0.092, 0.014),
                (0.0, 0.0, VENT_CENTER_Z + dz),
                bevel_width=0.002,
                rotation_deg=(36.0, 0.0, 0.0),
            )
        )

    return _finalize_and_export(
        "roof_arch_wall", concrete_parts, steel_parts, concrete_mat, steel_mat, output_dir
    )


def _build_parapet_panel_with_scupper(name: str) -> bpy.types.Object:
    """Build recessed concrete parapet panel with a 0.24m x 0.12m bottom-center scupper cutout."""
    bm = bmesh.new()
    hy = PANEL_RECESS_THICK * 0.5
    x_min, x_max = -1.78, 1.78
    z_bot, z_top = CURB_HEIGHT, COPING_BASE_Z
    sx0, sx1 = -0.12, 0.12
    sz_top = CURB_HEIGHT + 0.12  # 0.30m

    # 8 outer + cutout perimeter points (inverted-T cutout at bottom center)
    pts = [
        (x_min, z_bot),
        (sx0, z_bot),
        (sx0, sz_top),
        (sx1, sz_top),
        (sx1, z_bot),
        (x_max, z_bot),
        (x_max, z_top),
        (x_min, z_top),
    ]
    # Split cleanly into 3 quads on front/back so faces remain strictly convex
    front_v = [bm.verts.new((x, -hy, z)) for x, z in pts]
    back_v = [bm.verts.new((x, hy, z)) for x, z in pts]
    # Add two interior split verts on top edge aligned with sx0 and sx1
    f_top_l = bm.verts.new((sx0, -hy, z_top))
    f_top_r = bm.verts.new((sx1, -hy, z_top))
    b_top_l = bm.verts.new((sx0, hy, z_top))
    b_top_r = bm.verts.new((sx1, hy, z_top))

    # Front quads: Left panel, Center header above scupper, Right panel
    bm.faces.new((front_v[0], front_v[1], f_top_l, front_v[7]))
    bm.faces.new((front_v[2], front_v[3], f_top_r, f_top_l))
    bm.faces.new((front_v[4], front_v[5], front_v[6], f_top_r))

    # Back quads
    bm.faces.new((back_v[1], back_v[0], back_v[7], b_top_l))
    bm.faces.new((back_v[3], back_v[2], b_top_l, b_top_r))
    bm.faces.new((back_v[5], back_v[4], b_top_r, back_v[6]))

    # Perimeter thickness quads
    perim_f = [front_v[0], front_v[1], front_v[2], front_v[3], front_v[4], front_v[5], front_v[6], f_top_r, f_top_l, front_v[7]]
    perim_b = [back_v[0], back_v[1], back_v[2], back_v[3], back_v[4], back_v[5], back_v[6], b_top_r, b_top_l, back_v[7]]
    n_p = len(perim_f)
    for i in range(n_p):
        j = (i + 1) % n_p
        bm.faces.new((perim_f[j], perim_f[i], perim_b[i], perim_b[j]))

    return _mesh_from_bmesh(name, bm)


def _coping_profile_yz(expand: float = 0.0) -> list[tuple[float, float]]:
    """Return closed 2D coping flashing profile in (local_cross, z) with drip lips."""
    hw = COPING_HALF_D + expand
    y_in_skirt = 0.180 + expand * 0.5
    z_drip = COPING_DRIP_Z - expand * 0.5
    z_seat = COPING_BASE_Z
    z_edge = COPING_EDGE_Z + expand
    z_ridge = COPING_RIDGE_Z + expand
    return [
        (-y_in_skirt, z_drip),
        (-y_in_skirt, z_seat),
        (y_in_skirt, z_seat),
        (y_in_skirt, z_drip),
        (hw, z_drip),
        (hw, z_edge),
        (0.0, z_ridge),
        (-hw, z_edge),
        (-hw, z_drip),
    ]


def _build_linear_coping_segment(
    name: str,
    x_min: float,
    x_max: float,
    expand: float = 0.0,
) -> bpy.types.Object:
    """Build sloped rusted-steel coping flashing cap (or cleat) along X."""
    bm = bmesh.new()
    prof = _coping_profile_yz(expand=expand)
    v0 = [bm.verts.new((x_min, y, z)) for y, z in prof]
    v1 = [bm.verts.new((x_max, y, z)) for y, z in prof]
    n_p = len(prof)
    for i in range(n_p):
        j = (i + 1) % n_p
        bm.faces.new((v0[i], v0[j], v1[j], v1[i]))
    bm.faces.new(list(reversed(v0)))
    bm.faces.new(v1)
    return _mesh_from_bmesh(name, bm)


def generate_terrace_parapet_4m(output_dir: Path) -> dict[str, object]:
    """Generate 4.0m W x 1.15m H x 0.35m D rooftop terrace parapet with scupper & steel coping."""
    clean_scene()
    concrete_mat, steel_mat = _create_kit_materials()

    concrete_parts: list[bpy.types.Object] = []
    # Lower curb lip (0.18m H)
    concrete_parts.append(
        _add_box(
            "Parapet_Curb",
            (WALL_WIDTH, WALL_THICK, CURB_HEIGHT),
            (0.0, 0.0, CURB_HEIGHT * 0.5),
            bevel_width=0.010,
        )
    )
    # Twin end pilasters (x = +/-1.89)
    upper_h = COPING_BASE_Z - CURB_HEIGHT
    upper_z = CURB_HEIGHT + upper_h * 0.5
    for tag, sign in (("L", -1.0), ("R", 1.0)):
        concrete_parts.append(
            _add_box(
                f"Parapet_Pilaster_{tag}",
                (PILASTER_WIDTH, WALL_THICK, upper_h),
                (sign * 1.89, 0.0, upper_z),
                bevel_width=0.008,
            )
        )
    # Recessed center concrete panel with 0.24m x 0.12m bottom-center scupper opening
    concrete_parts.append(_build_parapet_panel_with_scupper("Parapet_Panel_Recessed"))

    steel_parts: list[bpy.types.Object] = []
    # Recessed rainwater scupper drainage sleeve (0.24m x 0.12m outer collar at Z[0.18, 0.30])
    scup_w = 0.24
    scup_h = 0.12
    scup_d = WALL_THICK  # proud of 0.29m recessed panel on both faces
    scup_t = 0.016
    steel_parts.append(
        _add_box(
            "Parapet_Scupper_Bot",
            (scup_w, scup_d, scup_t),
            (0.0, 0.0, CURB_HEIGHT + scup_t * 0.5),
            bevel_width=0.002,
        )
    )
    steel_parts.append(
        _add_box(
            "Parapet_Scupper_Top",
            (scup_w, scup_d, scup_t),
            (0.0, 0.0, CURB_HEIGHT + scup_h - scup_t * 0.5),
            bevel_width=0.002,
        )
    )
    for tag, sign in (("L", -1.0), ("R", 1.0)):
        steel_parts.append(
            _add_box(
                f"Parapet_Scupper_Side_{tag}",
                (scup_t, scup_d, scup_h - 2.0 * scup_t),
                (sign * (scup_w * 0.5 - scup_t * 0.5), 0.0, CURB_HEIGHT + scup_h * 0.5),
                bevel_width=0.002,
            )
        )
    # Center debris strainer pin inside scupper slot
    steel_parts.append(
        _add_box(
            "Parapet_Scupper_Strainer",
            (0.020, 0.045, scup_h - 2.0 * scup_t),
            (0.0, 0.0, CURB_HEIGHT + scup_h * 0.5),
            bevel_width=0.002,
        )
    )

    # Sloped rusted-steel coping flashing cap (0.40m D x 0.08m H) with drip lips & seam cleats
    steel_parts.append(_build_linear_coping_segment("Parapet_Coping_Cap", -2.0, 2.0, expand=0.0))
    for cx in (-1.30, 0.0, 1.30):
        steel_parts.append(
            _build_linear_coping_segment(
                f"Parapet_Coping_Cleat_{cx}",
                cx - 0.021,
                cx + 0.021,
                expand=0.008,
            )
        )

    return _finalize_and_export(
        "terrace_parapet_4m", concrete_parts, steel_parts, concrete_mat, steel_mat, output_dir
    )


def _build_corner_curb(name: str) -> bpy.types.Object:
    """Build unified L-shaped lower concrete curb lip (0.18m H) matching Godot corner polarity.

    Godot Leg A: X[-0.5, +0.5], Z[-0.5, -0.15] -> Blender Y[+0.15, +0.50]
    Godot Leg B: X[-0.5, -0.15], Z[-0.5, +0.5] -> Blender Y[-0.50, +0.50]
    """
    bm = bmesh.new()
    # Build two strictly non-overlapping chamfered blocks (corner+LegA & LegB wing) OR single L-extrusion.
    # Single L-extrusion with clean top edge chamfer:
    pts = [
        (-0.50, -0.50),
        (-0.15, -0.50),
        (-0.15, 0.15),
        (0.50, 0.15),
        (0.50, 0.50),
        (-0.50, 0.50),
    ]
    bot = [bm.verts.new((x, y, 0.0)) for x, y in pts]
    top = [bm.verts.new((x, y, CURB_HEIGHT)) for x, y in pts]
    mid_v_bot = bm.verts.new((-0.15, 0.50, 0.0))
    mid_v_top = bm.verts.new((-0.15, 0.50, CURB_HEIGHT))

    # Split top & bottom L into two strictly convex rectangles at X = -0.15
    # Left leg (X[-0.50, -0.15], Y[-0.50, +0.50]) & Right wing (X[-0.15, +0.50], Y[+0.15, +0.50])
    bm.faces.new((bot[1], bot[0], bot[5], mid_v_bot))
    bm.faces.new((bot[2], mid_v_bot, bot[4], bot[3]))
    bm.faces.new((top[0], top[1], mid_v_top, top[5]))
    bm.faces.new((mid_v_top, top[2], top[3], top[4]))

    perim_b = [bot[0], bot[1], bot[2], bot[3], bot[4], mid_v_bot, bot[5]]
    perim_t = [top[0], top[1], top[2], top[3], top[4], mid_v_top, top[5]]
    n_p = len(perim_b)
    for i in range(n_p):
        j = (i + 1) % n_p
        bm.faces.new((perim_b[i], perim_b[j], perim_t[j], perim_t[i]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # Bevel top rim edges cleanly
    top_edges = [
        e for e in bm.edges
        if all(abs(v.co.z - CURB_HEIGHT) < 1e-4 for v in e.verts)
        and not (abs(e.verts[0].co.x - (-0.15)) < 1e-4 and abs(e.verts[1].co.x - (-0.15)) < 1e-4 and abs(e.verts[0].co.y - 0.15) < 1e-4)
    ]
    # Exclude internal split edge (-0.15, 0.15)->(-0.15, 0.50) from bevel
    outer_top_edges = [
        e for e in top_edges
        if not (
            abs(e.verts[0].co.x + 0.15) < 1e-4
            and abs(e.verts[1].co.x + 0.15) < 1e-4
            and min(e.verts[0].co.y, e.verts[1].co.y) >= 0.149
        )
    ]
    bmesh.ops.bevel(
        bm,
        geom=outer_top_edges,
        offset=0.008,
        offset_type="OFFSET",
        segments=1,
        profile=0.5,
        affect="EDGES",
        clamp_overlap=True,
    )
    return _mesh_from_bmesh(name, bm)


def _build_mitered_corner_coping(name: str) -> bpy.types.Object:
    """Build 90-deg mitered sloped steel coping cap matching Godot LegA & LegB polarity.

    Leg A centerline: Blender Y = +0.325 (Godot Z = -0.325), X in [-0.325-y_loc, +0.50]
    Leg B centerline: Blender X = -0.325, Y in [-0.50, +0.325+x_loc]
    Miter diagonal plane: X + Y = 0 (Y = -X).
    """
    bm = bmesh.new()
    prof = _coping_profile_yz(expand=0.0)
    n_p = len(prof)

    # Leg A: end at X = +0.50, miter at X = -(0.325 + y_loc)
    ring_a_end = [bm.verts.new((0.50, 0.325 + y_loc, z)) for y_loc, z in prof]
    ring_miter = [bm.verts.new((-(0.325 + y_loc), 0.325 + y_loc, z)) for y_loc, z in prof]
    # Leg B: end at Y = -0.50 (Godot Z = +0.50), shares ring_miter vertex-for-vertex!
    ring_b_end = [bm.verts.new((-0.325 - y_loc, -0.50, z)) for y_loc, z in prof]

    for i in range(n_p):
        j = (i + 1) % n_p
        bm.faces.new((ring_miter[i], ring_miter[j], ring_a_end[j], ring_a_end[i]))
        bm.faces.new((ring_b_end[i], ring_b_end[j], ring_miter[j], ring_miter[i]))

    bm.faces.new(ring_a_end)
    bm.faces.new(list(reversed(ring_b_end)))
    return _mesh_from_bmesh(name, bm)


def _build_miter_diagonal_cleat(name: str, width: float = 0.044) -> bpy.types.Object:
    """Build standing-seam cleat straddling the 45-degree corner miter joint along X + Y = 0."""
    bm = bmesh.new()
    prof = _coping_profile_yz(expand=0.008)
    n_p = len(prof)
    # Diagonal unit normal perpendicular to line X + Y = 0 is (1/sqrt(2), 1/sqrt(2))
    d = (width * 0.5) / math.sqrt(2.0)

    def _clamp_xy(px: float, py: float) -> tuple[float, float]:
        return max(-0.533, min(-0.117, px)), max(0.117, min(0.533, py))

    ring_0 = [
        bm.verts.new((*_clamp_xy(-(0.325 + y_loc) - d, (0.325 + y_loc) - d), z))
        for y_loc, z in prof
    ]
    ring_1 = [
        bm.verts.new((*_clamp_xy(-(0.325 + y_loc) + d, (0.325 + y_loc) + d), z))
        for y_loc, z in prof
    ]

    for i in range(n_p):
        j = (i + 1) % n_p
        bm.faces.new((ring_0[i], ring_0[j], ring_1[j], ring_1[i]))
    bm.faces.new(list(reversed(ring_0)))
    bm.faces.new(ring_1)
    return _mesh_from_bmesh(name, bm)


def _build_leg_b_coping_cleat(name: str, y_center: float, length_y: float = 0.042) -> bpy.types.Object:
    """Build standing-seam coping cleat along Leg B (running along Y at X = -0.325)."""
    bm = bmesh.new()
    prof = _coping_profile_yz(expand=0.008)
    n_p = len(prof)
    hy = length_y * 0.5
    v0 = [bm.verts.new((-0.325 - y_loc, y_center - hy, z)) for y_loc, z in prof]
    v1 = [bm.verts.new((-0.325 - y_loc, y_center + hy, z)) for y_loc, z in prof]
    for i in range(n_p):
        j = (i + 1) % n_p
        bm.faces.new((v0[i], v0[j], v1[j], v1[i]))
    bm.faces.new(list(reversed(v0)))
    bm.faces.new(v1)
    return _mesh_from_bmesh(name, bm)


def _build_leg_a_coping_cleat(name: str, x_center: float, length_x: float = 0.042) -> bpy.types.Object:
    """Build standing-seam coping cleat along Leg A (running along X at Y = +0.325)."""
    bm = bmesh.new()
    prof = _coping_profile_yz(expand=0.008)
    n_p = len(prof)
    hx = length_x * 0.5
    v0 = [bm.verts.new((x_center - hx, 0.325 + y_loc, z)) for y_loc, z in prof]
    v1 = [bm.verts.new((x_center + hx, 0.325 + y_loc, z)) for y_loc, z in prof]
    for i in range(n_p):
        j = (i + 1) % n_p
        bm.faces.new((v0[i], v0[j], v1[j], v1[i]))
    bm.faces.new(list(reversed(v0)))
    bm.faces.new(v1)
    return _mesh_from_bmesh(name, bm)


def generate_terrace_parapet_corner(output_dir: Path) -> dict[str, object]:
    """Generate 1.0m x 1.0m x 1.15m H L-shaped 90-degree parapet corner."""
    clean_scene()
    concrete_mat, steel_mat = _create_kit_materials()

    upper_h = COPING_BASE_Z - CURB_HEIGHT
    upper_z = CURB_HEIGHT + upper_h * 0.5

    concrete_parts: list[bpy.types.Object] = []
    # L-shaped lower curb lip (0.18m H)
    concrete_parts.append(_build_corner_curb("Corner_Curb"))
    # Reinforced square outer corner pilaster (X[-0.50, -0.15], Y[+0.15, +0.50])
    concrete_parts.append(
        _add_box(
            "Corner_Pilaster",
            (WALL_THICK, WALL_THICK, upper_h),
            (-0.325, 0.325, upper_z),
            bevel_width=0.010,
        )
    )
    # Recessed Leg A concrete panel (X[-0.15, +0.50], Y[+0.18, +0.47], Godot Z[-0.47, -0.18])
    concrete_parts.append(
        _add_box(
            "Corner_LegA_Panel",
            (0.65, PANEL_RECESS_THICK, upper_h),
            (0.175, 0.325, upper_z),
            bevel_width=0.006,
        )
    )
    # Recessed Leg B concrete panel (X[-0.47, -0.18], Y[-0.50, +0.15], Godot Z[-0.15, +0.50])
    concrete_parts.append(
        _add_box(
            "Corner_LegB_Panel",
            (PANEL_RECESS_THICK, 0.65, upper_h),
            (-0.325, -0.175, upper_z),
            bevel_width=0.006,
        )
    )

    steel_parts: list[bpy.types.Object] = []
    # Mitered sloped steel coping flashing cap
    steel_parts.append(_build_mitered_corner_coping("Corner_Coping_Cap"))
    # Miter corner cleat + one standing-seam cleat per leg
    steel_parts.append(_build_miter_diagonal_cleat("Corner_Coping_MiterCleat"))
    steel_parts.append(_build_leg_a_coping_cleat("Corner_Coping_Cleat_LegA", x_center=0.18))
    steel_parts.append(_build_leg_b_coping_cleat("Corner_Coping_Cleat_LegB", y_center=-0.18))

    return _finalize_and_export(
        "terrace_parapet_corner", concrete_parts, steel_parts, concrete_mat, steel_mat, output_dir
    )


def main() -> None:
    """Entry point for Blender headless generation of roof & parapet shells."""
    try:
        sdk_root = Path(__file__).resolve().parent.parent.parent.parent
        output_dir = sdk_root / "assets" / "models" / "factory_shells"
        generate_roof_arch_wall(output_dir)
        generate_terrace_parapet_4m(output_dir)
        generate_terrace_parapet_corner(output_dir)
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
