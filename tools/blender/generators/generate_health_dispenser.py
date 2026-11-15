"""Procedural Blender 5.x generator for the Gothic Health Dispenser,
multi-layer glass reservoir cage, and rigged organic tentacle tip nozzle.

Coordinates are authored so that Blender's glTF exporter (export_yup=True)
produces meshes natively in Godot's +X Right, +Y Up, +Z Forward space with
Transform3D.IDENTITY on ChassisModel (zero 90-degree scene rotation).

Run via:
    python3 tools/blender/run.py tools/blender/generators/generate_health_dispenser.py
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[3]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

import bmesh
import bpy
import mathutils

from tools.blender.common.armature import (
    add_bone,
    create_action,
    create_armature,
    parent_mesh_to_armature,
    push_action_to_nla,
)
from tools.blender.common.exporter import clean_scene, export_godot_glb
from tools.blender.common.materials import assign_material, create_pbr_material

OUT_DIR = Path("assets/models/health_dispenser")


def _g_pos(gx: float, gy: float, gz: float) -> tuple[float, float, float]:
    """Convert Godot (+X right, +Y up, +Z forward) to Blender (+X, -Y, +Z)."""
    return (gx, -gz, gy)


def _g_size(sx: float, sy: float, sz: float) -> tuple[float, float, float]:
    """Convert Godot box dimensions (width X, height Y, depth Z) to Blender."""
    return (sx, sz, sy)


def _add_planar_uvs(bm: bmesh.types.BMesh, scale: float = 1.0) -> None:
    """Generate clean box/triplanar UVs on a bmesh so textures never stretch."""
    uv_layer = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co = loop.vert.co
            if ax >= ay and ax >= az:
                u, v = co.y * scale, co.z * scale
            elif ay >= ax and ay >= az:
                u, v = co.x * scale, co.z * scale
            else:
                u, v = co.x * scale, co.y * scale
            loop[uv_layer].uv = (u, v)


def _link_box_g(
    name: str,
    size_g: tuple[float, float, float],
    loc_g: tuple[float, float, float],
    mat: bpy.types.Material,
    bevel: float = 0.006,
    rot_g_z: float = 0.0,
    rot_g_x: float = 0.0,
) -> bpy.types.Object:
    """Create a beveled box in Godot coordinates (+X right, +Y up, +Z forward)."""
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=_g_size(*size_g), verts=bm.verts)
    if bevel > 0.0:
        bmesh.ops.bevel(
            bm,
            geom=list(bm.edges),
            offset=bevel,
            segments=2,
            affect="EDGES",
        )
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _add_planar_uvs(bm, scale=1.0)
    bm.to_mesh(mesh)
    bm.free()
    obj.location = _g_pos(*loc_g)
    # Godot Z rotation (roll in XY front plane) = rotation around Blender -Y
    # Godot X rotation (pitch in YZ plane) = rotation around Blender +X
    obj.rotation_euler = (rot_g_x, -rot_g_z, 0.0)
    assign_material(obj, mat)
    return obj


def _link_cylinder_g(
    name: str,
    radius1: float,
    radius2: float,
    depth: float,
    segments: int,
    loc_g: tuple[float, float, float],
    axis: str,
    mat: bpy.types.Material,
    cap_ends: bool = True,
    bevel: float = 0.003,
) -> bpy.types.Object:
    """Create a cylinder in Godot coordinates aligned along 'Y' (vertical) or 'Z' (forward)."""
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=cap_ends,
        cap_tris=False,
        segments=segments,
        radius1=radius1,
        radius2=radius2,
        depth=depth,
    )
    if bevel > 0.0 and cap_ends:
        boundary_edges = [
            e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-4
        ]
        if boundary_edges:
            bmesh.ops.bevel(
                bm,
                geom=boundary_edges,
                offset=bevel,
                segments=2,
                affect="EDGES",
            )
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _add_planar_uvs(bm, scale=2.0)
    bm.to_mesh(mesh)
    bm.free()
    obj.location = _g_pos(*loc_g)
    if axis == "Y":
        # Native cone axis is Blender Z = Godot Y (vertical)
        obj.rotation_euler = (0.0, 0.0, 0.0)
    elif axis == "Z":
        # Rotate 90 deg around X so cylinder axis lies along Blender Y = Godot Z (forward)
        obj.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
    elif axis == "X":
        obj.rotation_euler = (0.0, math.pi * 0.5, 0.0)
    assign_material(obj, mat)
    return obj


def _link_torus_ring_g(
    name: str,
    major_radius: float,
    minor_radius: float,
    loc_g: tuple[float, float, float],
    axis: str,
    mat: bpy.types.Material,
    major_segs: int = 28,
    minor_segs: int = 10,
) -> bpy.types.Object:
    """Create a hollow torus retaining band/collar (never a solid clipping disc)."""
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()

    ring_verts: list[list[bmesh.types.BMVert]] = []
    for i in range(major_segs):
        theta = (i / major_segs) * math.tau
        ct, st = math.cos(theta), math.sin(theta)
        sub_ring: list[bmesh.types.BMVert] = []
        for j in range(minor_segs):
            phi = (j / minor_segs) * math.tau
            r = major_radius + minor_radius * math.cos(phi)
            z = minor_radius * math.sin(phi)
            sub_ring.append(bm.verts.new((r * ct, r * st, z)))
        ring_verts.append(sub_ring)

    for i in range(major_segs):
        i_next = (i + 1) % major_segs
        for j in range(minor_segs):
            j_next = (j + 1) % minor_segs
            bm.faces.new(
                (
                    ring_verts[i][j],
                    ring_verts[i_next][j],
                    ring_verts[i_next][j_next],
                    ring_verts[i][j_next],
                )
            )

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _add_planar_uvs(bm, scale=3.0)
    bm.to_mesh(mesh)
    bm.free()
    obj.location = _g_pos(*loc_g)
    if axis == "Y":
        # Torus hole is along Blender Z = Godot Y (vertical around glass tank)
        obj.rotation_euler = (0.0, 0.0, 0.0)
    elif axis == "Z":
        # Torus hole is along Blender Y = Godot Z (forward pipe collar)
        obj.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
    assign_material(obj, mat)
    return obj


def _link_hollow_glass_tube_g(
    name: str,
    inner_radius: float,
    outer_radius: float,
    height: float,
    loc_g: tuple[float, float, float],
    mat: bpy.types.Material,
    segments: int = 32,
) -> bpy.types.Object:
    """Create a vertical hollow open-ended glass cylinder shell with physical wall thickness."""
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()

    half_h = height * 0.5
    outer_bot: list[bmesh.types.BMVert] = []
    outer_top: list[bmesh.types.BMVert] = []
    inner_bot: list[bmesh.types.BMVert] = []
    inner_top: list[bmesh.types.BMVert] = []

    for s in range(segments):
        ang = (s / segments) * math.tau
        ca, sa = math.cos(ang), math.sin(ang)
        outer_bot.append(bm.verts.new((ca * outer_radius, sa * outer_radius, -half_h)))
        outer_top.append(bm.verts.new((ca * outer_radius, sa * outer_radius, half_h)))
        inner_bot.append(bm.verts.new((ca * inner_radius, sa * inner_radius, -half_h)))
        inner_top.append(bm.verts.new((ca * inner_radius, sa * inner_radius, half_h)))

    for s in range(segments):
        sn = (s + 1) % segments
        # Outer wall (normals outward)
        bm.faces.new((outer_bot[s], outer_bot[sn], outer_top[sn], outer_top[s]))
        # Inner wall (normals inward)
        bm.faces.new((inner_bot[sn], inner_bot[s], inner_top[s], inner_top[sn]))
        # Top & bottom glass rims
        bm.faces.new((outer_top[s], outer_top[sn], inner_top[sn], inner_top[s]))
        bm.faces.new((inner_bot[s], inner_bot[sn], outer_bot[sn], outer_bot[s]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _add_planar_uvs(bm, scale=1.5)
    bm.to_mesh(mesh)
    bm.free()
    obj.location = _g_pos(*loc_g)
    assign_material(obj, mat)
    return obj


def _add_rivet_spheres_g(
    bm: bmesh.types.BMesh,
    points_g: list[tuple[float, float, float]],
    radius: float = 0.012,
) -> None:
    for gx, gy, gz in points_g:
        mat_loc = mathutils.Matrix.Translation(_g_pos(gx, gy, gz))
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius, matrix=mat_loc)


def _set_bezier_keyframes(action: bpy.types.Action) -> None:
    fcurves = list(getattr(action, "fcurves", []))
    if not fcurves and hasattr(action, "layers"):
        for layer in action.layers:
            for strip in getattr(layer, "strips", []):
                for bag in getattr(strip, "channelbags", []):
                    fcurves.extend(getattr(bag, "fcurves", []))
    for fcurve in fcurves:
        for kp in fcurve.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.handle_left_type = "AUTO_CLAMPED"
            kp.handle_right_type = "AUTO_CLAMPED"


def generate_chassis() -> None:
    clean_scene()

    mat_rust = create_pbr_material(
        "RustedIron",
        base_color=(0.20, 0.14, 0.11, 1.0),
        metallic=0.78,
        roughness=0.58,
    )
    mat_gothic = create_pbr_material(
        "GothicWroughtMetal",
        base_color=(0.16, 0.17, 0.19, 1.0),
        metallic=0.88,
        roughness=0.42,
    )
    mat_brass = create_pbr_material(
        "TarnishedBrass",
        base_color=(0.68, 0.52, 0.26, 1.0),
        metallic=0.88,
        roughness=0.34,
    )
    mat_dial = create_pbr_material(
        "GaugeDial",
        base_color=(0.76, 0.72, 0.60, 1.0),
        metallic=0.05,
        roughness=0.55,
    )
    mat_screen_bg = create_pbr_material(
        "ScreenBacking",
        base_color=(0.03, 0.06, 0.04, 1.0),
        metallic=0.1,
        roughness=0.22,
    )
    mat_glass = create_pbr_material(
        "VesselGlass",
        base_color=(0.72, 0.94, 0.80, 0.18),
        metallic=0.0,
        roughness=0.06,
    )

    # 1. Main Rusted Steel Backplate (1.50 x 1.50 x 0.14, front face at Z = +0.07)
    _link_box_g("Backplate", (1.50, 1.50, 0.14), (0.0, 0.0, 0.0), mat_rust, bevel=0.01)

    # Vertical panel seam strips dividing left (tentacle), center (arch), right (vessel)
    _link_box_g("PanelSeam_L", (0.024, 1.36, 0.018), (-0.31, 0.0, 0.076), mat_gothic, bevel=0.004)
    _link_box_g("PanelSeam_R", (0.024, 1.36, 0.018), (0.31, 0.0, 0.076), mat_gothic, bevel=0.004)

    # 2. Brass & Wrought-Iron Perimeter Frame + Ornate Corner Filigree
    _link_box_g("TrimTop", (1.52, 0.08, 0.045), (0.0, 0.715, 0.082), mat_gothic, bevel=0.01)
    _link_box_g("TrimBottom", (1.52, 0.08, 0.045), (0.0, -0.715, 0.082), mat_gothic, bevel=0.01)
    _link_box_g("TrimLeft", (0.08, 1.36, 0.045), (-0.715, 0.0, 0.082), mat_gothic, bevel=0.01)
    _link_box_g("TrimRight", (0.08, 1.36, 0.045), (0.715, 0.0, 0.082), mat_gothic, bevel=0.01)

    # Prominent Tarnished Brass outer & inner border rails on all 4 edges
    _link_box_g("BrassEdgeOuterTop", (1.54, 0.026, 0.056), (0.0, 0.752, 0.086), mat_brass, bevel=0.006)
    _link_box_g("BrassEdgeOuterBot", (1.54, 0.026, 0.056), (0.0, -0.752, 0.086), mat_brass, bevel=0.006)
    _link_box_g("BrassEdgeOuterLeft", (0.026, 1.54, 0.056), (-0.752, 0.0, 0.086), mat_brass, bevel=0.006)
    _link_box_g("BrassEdgeOuterRight", (0.026, 1.54, 0.056), (0.752, 0.0, 0.086), mat_brass, bevel=0.006)

    _link_box_g("BrassTrimInnerTop", (1.38, 0.030, 0.048), (0.0, 0.668, 0.088), mat_brass, bevel=0.006)
    _link_box_g("BrassTrimInnerBot", (1.38, 0.030, 0.048), (0.0, -0.668, 0.088), mat_brass, bevel=0.006)
    _link_box_g("BrassTrimInnerLeft", (0.030, 1.32, 0.048), (-0.668, 0.0, 0.088), mat_brass, bevel=0.006)
    _link_box_g("BrassTrimInnerRight", (0.030, 1.32, 0.048), (0.668, 0.0, 0.088), mat_brass, bevel=0.006)

    # Ornate Brass Gothic Corner Filigree Plates
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            tag = f"{int(sx)}_{int(sy)}"
            _link_box_g(
                f"BrassCornerPlate_{tag}",
                (0.22, 0.22, 0.054),
                (sx * 0.64, sy * 0.64, 0.092),
                mat_brass,
                bevel=0.01,
            )
            _link_box_g(
                f"CornerInlay_{tag}",
                (0.15, 0.15, 0.058),
                (sx * 0.64, sy * 0.64, 0.096),
                mat_gothic,
                bevel=0.008,
            )
            _link_box_g(
                f"BrassCornerDiamond_{tag}",
                (0.09, 0.09, 0.064),
                (sx * 0.65, sy * 0.65, 0.104),
                mat_brass,
                bevel=0.006,
                rot_g_z=math.pi * 0.25,
            )

    # Upper-left Gothic Relief Cross (matching reference image between socket and arch)
    _link_box_g("BrassCrossVert", (0.032, 0.22, 0.032), (-0.31, 0.49, 0.092), mat_brass, bevel=0.005)
    _link_box_g("BrassCrossHoriz", (0.14, 0.032, 0.032), (-0.31, 0.53, 0.092), mat_brass, bevel=0.005)
    _link_box_g(
        "BrassCrossCenter",
        (0.048, 0.048, 0.038),
        (-0.31, 0.53, 0.096),
        mat_brass,
        bevel=0.005,
        rot_g_z=math.pi * 0.25,
    )

    # Rivets across perimeter and vertical panel seams
    rivet_mesh = bpy.data.meshes.new("Rivets_Mesh")
    rivet_obj = bpy.data.objects.new("Rivets", rivet_mesh)
    bpy.context.collection.objects.link(rivet_obj)
    bm_riv = bmesh.new()
    riv_pts: list[tuple[float, float, float]] = []
    for i in range(9):
        t = -0.60 + i * 0.15
        riv_pts.append((t, 0.715, 0.106))
        riv_pts.append((t, -0.715, 0.106))
        riv_pts.append((-0.715, t, 0.106))
        riv_pts.append((0.715, t, 0.106))
        # Vertical panel seam rivets
        riv_pts.append((-0.285, t * 0.9, 0.082))
        riv_pts.append((0.285, t * 0.9, 0.082))
    _add_rivet_spheres_g(bm_riv, riv_pts, radius=0.012)
    bm_riv.to_mesh(rivet_mesh)
    bm_riv.free()
    assign_material(rivet_obj, mat_gothic)

    # 3. Central Pointed Tarnished Brass Gothic Cathedral Arch Frame
    _link_box_g("ScreenBacking", (0.44, 0.58, 0.02), (0.0, 0.06, 0.08), mat_screen_bg, bevel=0.002)

    # Stepped outer & inner brass pilasters
    for side in (-1.0, 1.0):
        stag = "L" if side < 0 else "R"
        _link_box_g(
            f"BrassBezelOuter_{stag}",
            (0.068, 0.64, 0.072),
            (side * 0.255, 0.04, 0.106),
            mat_brass,
            bevel=0.009,
        )
        _link_box_g(
            f"BrassBezelStep_{stag}",
            (0.036, 0.60, 0.084),
            (side * 0.228, 0.04, 0.114),
            mat_brass,
            bevel=0.006,
        )
        # Pointed Gothic Arch Rafters (Outer & Inner brass molding)
        _link_box_g(
            f"BrassGothicArchOuter_{stag}",
            (0.32, 0.068, 0.076),
            (side * 0.135, 0.445, 0.108),
            mat_brass,
            bevel=0.009,
            rot_g_z=side * -0.58,
        )
        _link_box_g(
            f"BrassGothicArchInner_{stag}",
            (0.28, 0.036, 0.088),
            (side * 0.120, 0.425, 0.116),
            mat_brass,
            bevel=0.006,
            rot_g_z=side * -0.58,
        )

    _link_box_g("BrassBezelBottom", (0.56, 0.068, 0.076), (0.0, -0.255, 0.108), mat_brass, bevel=0.009)
    _link_box_g("BrassBezelBottomLip", (0.48, 0.034, 0.088), (0.0, -0.232, 0.116), mat_brass, bevel=0.006)
    _link_box_g(
        "BrassGothicKeystone",
        (0.072, 0.072, 0.088),
        (0.0, 0.515, 0.114),
        mat_brass,
        bevel=0.008,
        rot_g_z=math.pi * 0.25,
    )

    # Tympanum Backing + Analog Gauge inside upper Gothic Arch (Y = 0.35)
    _link_box_g("ArchTympanum", (0.42, 0.22, 0.045), (0.0, 0.34, 0.092), mat_gothic, bevel=0.006)
    _link_box_g("BrassArchDivider", (0.46, 0.034, 0.082), (0.0, 0.22, 0.112), mat_brass, bevel=0.006)

    _link_cylinder_g(
        "BrassTopGaugeCase", 0.112, 0.112, 0.052, 28, (0.0, 0.355, 0.122), "Z", mat_brass
    )
    _link_torus_ring_g("BrassTopGaugeBezel", 0.104, 0.014, (0.0, 0.355, 0.148), "Z", mat_brass)
    _link_cylinder_g(
        "TopGaugeFace", 0.092, 0.092, 0.016, 28, (0.0, 0.355, 0.144), "Z", mat_dial
    )
    _link_box_g(
        "TopGaugeNeedle",
        (0.010, 0.072, 0.010),
        (-0.014, 0.345, 0.156),
        mat_gothic,
        bevel=0.001,
        rot_g_z=0.68,
    )
    _link_cylinder_g(
        "BrassTopGaugePin", 0.014, 0.014, 0.018, 12, (0.0, 0.355, 0.156), "Z", mat_brass
    )

    # 4. Bottom Gargoyle / Beast-Head Spout & Brass Valve Handle (Y = -0.30 .. -0.54)
    _link_box_g("BrassSpoutEscutcheon", (0.22, 0.18, 0.045), (0.0, -0.36, 0.092), mat_brass, bevel=0.01)
    _link_cylinder_g("BrassSpoutNeck", 0.042, 0.046, 0.11, 16, (0.0, -0.35, 0.14), "Z", mat_brass)
    # Valve stem + T-handle above spout
    _link_cylinder_g("BrassValveStem", 0.016, 0.016, 0.07, 12, (0.0, -0.29, 0.155), "Y", mat_brass)
    _link_box_g("BrassValveBar", (0.15, 0.022, 0.026), (0.0, -0.255, 0.155), mat_brass, bevel=0.005)
    # Gargoyle Beast Head (Cranium, Snout, Cheek Horns, Open Lower Jaw, Fangs)
    _link_box_g("GargoyleSkull", (0.11, 0.10, 0.10), (0.0, -0.35, 0.20), mat_gothic, bevel=0.014)
    _link_box_g(
        "GargoyleSnout",
        (0.082, 0.065, 0.11),
        (0.0, -0.365, 0.255),
        mat_gothic,
        bevel=0.012,
        rot_g_x=0.22,
    )
    for sx in (-1.0, 1.0):
        _link_box_g(
            f"GargoyleEar_{int(sx)}",
            (0.026, 0.065, 0.042),
            (sx * 0.052, -0.30, 0.20),
            mat_gothic,
            bevel=0.006,
            rot_g_z=sx * -0.35,
            rot_g_x=-0.25,
        )
        _link_box_g(
            f"BrassGargoyleBrow_{int(sx)}",
            (0.036, 0.020, 0.035),
            (sx * 0.028, -0.325, 0.245),
            mat_brass,
            bevel=0.004,
            rot_g_z=sx * 0.28,
        )
        # Upper & Lower Beast Fangs
        _link_cylinder_g(
            f"BrassGargoyleFangTop_{int(sx)}",
            0.009,
            0.002,
            0.038,
            8,
            (sx * 0.026, -0.395, 0.285),
            "Y",
            mat_brass,
            bevel=0.0,
        )
    # Open gaping lower jaw chute
    _link_box_g(
        "GargoyleLowerJaw",
        (0.074, 0.13, 0.065),
        (0.0, -0.445, 0.235),
        mat_gothic,
        bevel=0.01,
        rot_g_x=0.32,
    )

    # 5. Left-Side Pipe Elbow Socket (Bottom-Left) + Upper Tentacle Socket (Top-Left)
    # Bottom-left heavy riveted pipe elbow (X = -0.50, Y = -0.48 -> curves up to Y = -0.34, Z = 0.22)
    _link_cylinder_g(
        "LowerPipeWallFlange", 0.145, 0.145, 0.042, 24, (-0.50, -0.46, 0.09), "Z", mat_gothic
    )
    _link_torus_ring_g("BrassLowerFlangeRing", 0.125, 0.012, (-0.50, -0.46, 0.112), "Z", mat_brass)
    _link_cylinder_g(
        "LowerPipeHoriz", 0.092, 0.096, 0.15, 20, (-0.50, -0.46, 0.16), "Z", mat_gothic
    )
    _link_cylinder_g(
        "LowerPipeElbowJoint", 0.098, 0.094, 0.14, 20, (-0.50, -0.42, 0.21), "Y", mat_gothic
    )
    _link_cylinder_g(
        "LowerPipeUpMouth", 0.092, 0.102, 0.11, 20, (-0.50, -0.35, 0.22), "Y", mat_rust
    )
    _link_torus_ring_g("LowerPipeMouthCollar", 0.098, 0.016, (-0.50, -0.30, 0.22), "Y", mat_gothic)
    _link_torus_ring_g("BrassLowerPipeWire", 0.096, 0.007, (-0.50, -0.38, 0.22), "Y", mat_brass)

    # Top-left upper socket where S-curved tentacle tip emerges/rests (X = -0.50, Y = 0.42)
    _link_cylinder_g(
        "BrassUpperSocketFlange", 0.092, 0.092, 0.038, 20, (-0.50, 0.42, 0.09), "Z", mat_brass
    )
    _link_torus_ring_g("BrassUpperSocketCollar", 0.076, 0.014, (-0.50, 0.42, 0.112), "Z", mat_brass)
    _link_cylinder_g(
        "UpperSocketHole", 0.066, 0.066, 0.025, 20, (-0.50, 0.42, 0.105), "Z", mat_screen_bg
    )

    # 6. Right-Side Multi-Layer Glass Vessel & Brass/Iron Cradle (X = +0.52, Y = 0.02, Z = 0.19)
    # All tank cylinders & torus bands use axis="Y" (strictly vertical -> ZERO clipping circles!)
    _link_cylinder_g(
        "TankCapBottom", 0.132, 0.128, 0.075, 24, (0.52, -0.375, 0.19), "Y", mat_gothic
    )
    _link_cylinder_g(
        "BrassTankLipBottom", 0.138, 0.138, 0.024, 24, (0.52, -0.335, 0.19), "Y", mat_brass
    )
    _link_cylinder_g(
        "TankDomeBottom", 0.075, 0.122, 0.065, 24, (0.52, -0.435, 0.19), "Y", mat_gothic
    )

    _link_cylinder_g(
        "TankCapTop", 0.128, 0.132, 0.075, 24, (0.52, 0.415, 0.19), "Y", mat_gothic
    )
    _link_cylinder_g(
        "BrassTankLipTop", 0.138, 0.138, 0.024, 24, (0.52, 0.375, 0.19), "Y", mat_brass
    )
    _link_cylinder_g(
        "TankDomeTop", 0.122, 0.075, 0.065, 24, (0.52, 0.475, 0.19), "Y", mat_gothic
    )

    # Brass feed pipes & top valve
    _link_cylinder_g(
        "BrassTankNeckTop", 0.042, 0.048, 0.06, 16, (0.52, 0.525, 0.19), "Y", mat_brass
    )
    _link_cylinder_g(
        "BrassTankPipeTop", 0.026, 0.026, 0.15, 14, (0.52, 0.59, 0.16), "Y", mat_brass
    )
    _link_cylinder_g(
        "BrassTankPipeBot", 0.028, 0.028, 0.15, 14, (0.52, -0.51, 0.17), "Y", mat_brass
    )

    # Wall mounting brackets holding the tank cradle to the backplate
    _link_box_g("TankWallBracketTop", (0.14, 0.065, 0.14), (0.52, 0.415, 0.12), mat_gothic, bevel=0.008)
    _link_box_g("TankWallBracketBot", (0.14, 0.065, 0.14), (0.52, -0.375, 0.12), mat_gothic, bevel=0.008)

    # Hollow Torus Brass Retaining Bands & Wire Wraps around the outside of the glass tube (r > 0.105)
    for band_y in (-0.18, -0.14, 0.18, 0.22):
        _link_torus_ring_g(
            f"BrassTankWire_{band_y:.2f}",
            0.108,
            0.0055,
            (0.52, band_y, 0.19),
            "Y",
            mat_brass,
        )

    # Two thin vertical brass guard rods flanking the glass vessel
    for rod_ang in (-0.65, 0.65):
        rx = 0.52 + math.sin(rod_ang) * 0.114
        rz = 0.19 + math.cos(rod_ang) * 0.114
        _link_cylinder_g(
            f"BrassTankGuardRod_{rod_ang:.2f}",
            0.006,
            0.006,
            0.70,
            10,
            (rx, 0.02, rz),
            "Y",
            mat_brass,
            bevel=0.0,
        )

    # Outer Hollow Glass Vessel Shell (inner_r=0.098, outer_r=0.103, height=0.70 at (0.52, 0.02, 0.19))
    _link_hollow_glass_tube_g(
        "GlassVesselOuter",
        inner_radius=0.098,
        outer_radius=0.103,
        height=0.70,
        loc_g=(0.52, 0.02, 0.19),
        mat=mat_glass,
        segments=32,
    )

    # Small Brass Pressure Gauge near top-left of tank (X = 0.36, Y = 0.49)
    _link_cylinder_g(
        "BrassSideGaugeRim", 0.068, 0.068, 0.038, 20, (0.36, 0.49, 0.102), "Z", mat_brass
    )
    _link_torus_ring_g("BrassSideGaugeBezel", 0.062, 0.009, (0.36, 0.49, 0.122), "Z", mat_brass)
    _link_cylinder_g(
        "SideGaugeFace", 0.054, 0.054, 0.012, 20, (0.36, 0.49, 0.118), "Z", mat_dial
    )
    _link_box_g(
        "SideGaugeNeedle",
        (0.006, 0.042, 0.006),
        (0.368, 0.496, 0.128),
        mat_gothic,
        bevel=0.001,
        rot_g_z=-0.62,
    )

    # 7. Articulated Twin Iron Shutter Doors (Armature + `close` clip at 60 FPS)
    arm = create_armature("ChassisArmature")
    add_bone(arm, "Root", _g_pos(0.0, 0.0, 0.0), _g_pos(0.0, 0.2, 0.0), use_deform=False)
    add_bone(
        arm,
        "Shutter_L",
        _g_pos(-0.22, -0.02, 0.135),
        _g_pos(-0.22, 0.18, 0.135),
        parent_name="Root",
    )
    add_bone(
        arm,
        "Shutter_R",
        _g_pos(0.22, -0.02, 0.135),
        _g_pos(0.22, 0.18, 0.135),
        parent_name="Root",
    )
    bpy.ops.object.mode_set(mode="OBJECT")

    door_l = _link_box_g(
        "ShutterDoorLeft", (0.22, 0.44, 0.022), (-0.11, -0.01, 0.135), mat_gothic, bevel=0.004
    )
    door_r = _link_box_g(
        "ShutterDoorRight", (0.22, 0.44, 0.022), (0.11, -0.01, 0.135), mat_gothic, bevel=0.004
    )

    for door_obj, bone_name in ((door_l, "Shutter_L"), (door_r, "Shutter_R")):
        vg = door_obj.vertex_groups.new(name=bone_name)
        vg.add([v.index for v in door_obj.data.vertices], 1.0, "REPLACE")
        parent_mesh_to_armature(door_obj, arm, auto_weights=False)

    # Animate `close` clip: Frame 0 open outward -> Frame 22 slam shut -> Frame 36 settle
    action = create_action(arm, "close")
    bpy.context.scene.render.fps = 60
    bpy.ops.object.mode_set(mode="POSE")
    pb_l = arm.pose.bones["Shutter_L"]
    pb_r = arm.pose.bones["Shutter_R"]
    pb_l.rotation_mode = "XYZ"
    pb_r.rotation_mode = "XYZ"

    # Bone axis is along +Y (vertical in Godot, +Z in Blender); local Y rotation swings door open
    open_rad = math.radians(102.0)
    keyframes = [
        (0, open_rad),
        (5, math.radians(107.0)),
        (22, 0.0),
        (27, math.radians(5.0)),
        (36, 0.0),
    ]
    for frame, angle in keyframes:
        pb_l.rotation_euler = (0.0, -angle, 0.0)
        pb_r.rotation_euler = (0.0, angle, 0.0)
        pb_l.keyframe_insert(data_path="rotation_euler", frame=frame)
        pb_r.keyframe_insert(data_path="rotation_euler", frame=frame)

    _set_bezier_keyframes(action)
    bpy.ops.object.mode_set(mode="OBJECT")
    push_action_to_nla(arm, action, track_name="close")

    export_godot_glb(OUT_DIR / "health_dispenser_chassis.glb", export_animations=True)


def generate_conduit_segment() -> None:
    clean_scene()
    mat_conduit = create_pbr_material(
        "ConduitRibbedMetal",
        base_color=(0.24, 0.25, 0.27, 1.0),
        metallic=0.85,
        roughness=0.45,
    )

    mesh = bpy.data.meshes.new("ConduitSegment_Mesh")
    obj = bpy.data.objects.new("ConduitSegment", mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()

    rings = 32
    segs = 14
    height = 1.0
    for r in range(rings + 1):
        t = r / rings
        z = -height * 0.5 + t * height
        rad = 0.026 + 0.008 * (0.5 + 0.5 * math.sin(t * math.pi * 16.0))
        ring_verts = []
        for s in range(segs):
            ang = (s / segs) * math.tau
            v = bm.verts.new((math.cos(ang) * rad, math.sin(ang) * rad, z))
            ring_verts.append(v)
        if r > 0:
            prev_ring = bm.verts[-segs * 2 : -segs]
            for s in range(segs):
                s_next = (s + 1) % segs
                bm.faces.new((prev_ring[s], prev_ring[s_next], ring_verts[s_next], ring_verts[s]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _add_planar_uvs(bm, scale=2.0)
    bm.to_mesh(mesh)
    bm.free()
    assign_material(obj, mat_conduit)
    export_godot_glb(OUT_DIR / "conduit_segment.glb", export_animations=False)


def generate_octopus_nozzle() -> None:
    """Generate a tapered curling organic tentacle tip with suction cups and subtle inner fangs.

    Built along Blender +Z so that glTF export (export_yup=True) aligns the tip
    along Godot +Y (0.0 -> +0.24m), seamlessly continuing the procedural tentacle body.
    """
    clean_scene()
    mat_flesh = create_pbr_material(
        "OctopusFlesh",
        base_color=(0.25, 0.12, 0.35, 1.0),
        metallic=0.0,
        roughness=0.11,
    )
    mat_sucker = create_pbr_material(
        "OctopusSucker",
        base_color=(0.56, 0.28, 0.40, 1.0),
        metallic=0.0,
        roughness=0.16,
    )
    mat_fang = create_pbr_material(
        "ChitinFang",
        base_color=(0.76, 0.70, 0.55, 1.0),
        metallic=0.05,
        roughness=0.30,
    )

    # 1. Smoothly tapered curling organic tentacle tip along Blender +Z (Godot +Y: 0.0 -> 0.24m)
    body_mesh = bpy.data.meshes.new("NozzleBody_Mesh")
    body_obj = bpy.data.objects.new("NozzleBody", body_mesh)
    bpy.context.collection.objects.link(body_obj)
    bm = bmesh.new()

    rings = 20
    segs = 18
    uv_layer = bm.loops.layers.uv.verify()
    ring_list: list[list[bmesh.types.BMVert]] = []

    for r in range(rings + 1):
        t = r / rings
        # Godot +Y = Blender +Z; slight graceful organic curl toward +Y (Godot -Z) near tip
        z_height = t * 0.22
        curl_offset_y = (t * t) * 0.028
        # Matches procedural tentacle tip radius (0.028m at t=0 -> tapers to 0.011m at tip)
        rad = 0.028 * (1.0 - 0.60 * (t**1.15))
        cur_ring: list[bmesh.types.BMVert] = []
        for s in range(segs):
            ang = (s / segs) * math.tau
            vx = math.cos(ang) * rad
            vy = math.sin(ang) * rad + curl_offset_y
            cur_ring.append(bm.verts.new((vx, vy, z_height)))
        ring_list.append(cur_ring)

    for r in range(rings):
        for s in range(segs):
            sn = (s + 1) % segs
            face = bm.faces.new(
                (ring_list[r][s], ring_list[r][sn], ring_list[r + 1][sn], ring_list[r + 1][s])
            )
            for loop in face.loops:
                co = loop.vert.co
                loop[uv_layer].uv = (
                    math.atan2(co.y, co.x) / math.tau + 0.5,
                    co.z * 4.0,
                )

    # Cap tip cleanly
    tip_center = bm.verts.new((0.0, 0.028, 0.228))
    for s in range(segs):
        sn = (s + 1) % segs
        bm.faces.new((ring_list[rings][s], ring_list[rings][sn], tip_center))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(body_mesh)
    bm.free()
    assign_material(body_obj, mat_flesh)

    # 2. Paired rows of raised fleshy suction cups along front-outer side (Blender -Y = Godot +Z)
    sucker_mesh = bpy.data.meshes.new("Suckers_Mesh")
    sucker_obj = bpy.data.objects.new("Suckers", sucker_mesh)
    bpy.context.collection.objects.link(sucker_obj)
    bm_s = bmesh.new()
    for row in range(5):
        t = (row + 0.5) / 5.5
        z_pos = t * 0.20
        curl_y = (t * t) * 0.028
        base_rad = 0.028 * (1.0 - 0.60 * (t**1.15))
        sucker_r = 0.012 * (1.0 - 0.45 * t)
        for side in (-1.0, 1.0):
            x_pos = side * base_rad * 0.48
            y_pos = -base_rad * 0.88 + curl_y
            mat_t = mathutils.Matrix.Translation((x_pos, y_pos, z_pos)) @ mathutils.Matrix.Rotation(
                math.pi * 0.5, 4, "X"
            )
            bmesh.ops.create_cone(
                bm_s,
                cap_ends=True,
                cap_tris=False,
                segments=12,
                radius1=sucker_r,
                radius2=sucker_r * 0.76,
                depth=sucker_r * 0.85,
                matrix=mat_t,
            )
    bmesh.ops.recalc_face_normals(bm_s, faces=bm_s.faces)
    _add_planar_uvs(bm_s, scale=6.0)
    bm_s.to_mesh(sucker_mesh)
    bm_s.free()
    assign_material(sucker_obj, mat_sucker)

    # 3. Rigged subtle chitinous mouth fangs at the very tip (for heal `bite` animation)
    arm = create_armature("NozzleArmature")
    add_bone(arm, "NozzleRoot", (0.0, 0.0, 0.0), (0.0, 0.0, 0.16), use_deform=True)
    fang_count = 4
    for i in range(fang_count):
        ang = (i / fang_count) * math.tau + (math.pi * 0.25)
        fx = math.cos(ang) * 0.010
        fy = math.sin(ang) * 0.010 + 0.026
        add_bone(
            arm,
            f"Fang_{i}",
            (fx, fy, 0.21),
            (fx * 0.5, fy, 0.25),
            parent_name="NozzleRoot",
        )
    bpy.ops.object.mode_set(mode="OBJECT")

    for static_part in (body_obj, sucker_obj):
        vg = static_part.vertex_groups.new(name="NozzleRoot")
        vg.add([v.index for v in static_part.data.vertices], 1.0, "REPLACE")
        parent_mesh_to_armature(static_part, arm, auto_weights=False)

    for i in range(fang_count):
        ang = (i / fang_count) * math.tau + (math.pi * 0.25)
        fx = math.cos(ang) * 0.010
        fy = math.sin(ang) * 0.010 + 0.026
        f_mesh = bpy.data.meshes.new(f"Fang_{i}_Mesh")
        f_obj = bpy.data.objects.new(f"Fang_{i}", f_mesh)
        bpy.context.collection.objects.link(f_obj)
        bm_f = bmesh.new()
        bmesh.ops.create_cone(
            bm_f,
            cap_ends=True,
            cap_tris=False,
            segments=8,
            radius1=0.0045,
            radius2=0.0008,
            depth=0.036,
        )
        bmesh.ops.recalc_face_normals(bm_f, faces=bm_f.faces)
        bm_f.to_mesh(f_mesh)
        bm_f.free()
        f_obj.location = (fx, fy, 0.225)
        f_obj.rotation_euler = (-math.sin(ang) * 0.35, math.cos(ang) * 0.35, 0.0)
        assign_material(f_obj, mat_fang)

        vg = f_obj.vertex_groups.new(name=f"Fang_{i}")
        vg.add([v.index for v in f_obj.data.vertices], 1.0, "REPLACE")
        parent_mesh_to_armature(f_obj, arm, auto_weights=False)

    # Animate `bite` clip at 60 FPS (frames 0..24)
    action = create_action(arm, "bite")
    bpy.context.scene.render.fps = 60
    bpy.ops.object.mode_set(mode="POSE")
    for i in range(fang_count):
        pb = arm.pose.bones[f"Fang_{i}"]
        pb.rotation_mode = "XYZ"
        for frame, x_rot in ((0, 0.0), (8, -0.48), (14, 0.38), (24, 0.0)):
            pb.rotation_euler = (x_rot, 0.0, 0.0)
            pb.keyframe_insert(data_path="rotation_euler", frame=frame)
    _set_bezier_keyframes(action)
    bpy.ops.object.mode_set(mode="OBJECT")
    push_action_to_nla(arm, action, track_name="bite")

    export_godot_glb(OUT_DIR / "octopus_nozzle.glb", export_animations=True)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    generate_chassis()
    generate_conduit_segment()
    generate_octopus_nozzle()
    print("[HealthDispenser] All 3 GLBs exported successfully.")


if __name__ == "__main__":
    main()
