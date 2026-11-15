#!/usr/bin/env python3
"""Procedural generator, rigger, and 60 FPS animator for the Imp enemy.

Builds the squat armored mechanical Imp (1.15m height, <= 8000 tris) with
short thick armored legs and wide piston feet (no pogo springs), generates
PBR textures + ORMMaterial3D .tres + asset_manifest.json, rigs a 14-bone
armature, bakes 8 Bezier animation clips at 60 FPS, and exports
assets/models/imp/imp_rigged.glb.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Dict, List, Tuple

_TOOL_DIR = Path(__file__).resolve().parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bmesh
import bpy
import mathutils
from common.armature import (
    add_bone,
    create_action,
    create_armature,
    push_action_to_nla,
)
from common.exporter import clean_scene, export_godot_glb
from common.materials import assign_material, create_pbr_material

BONE_NAMES: List[str] = [
    "Root",
    "Pelvis",
    "Spine",
    "Head",
    "Arm_L",
    "Forearm_L",
    "Arm_R",
    "Forearm_R",
    "Thigh_L",
    "Shin_L",
    "Foot_L",
    "Thigh_R",
    "Shin_R",
    "Foot_R",
]

CLIP_SPECS: Dict[str, Tuple[int, bool]] = {
    "idle": (120, True),
    "run": (48, True),
    "jump": (54, False),
    "charge_lightning": (72, False),
    "stack_mount": (54, False),
    "dive_bomb": (48, False),
    "hit_react": (30, False),
    "death": (66, False),
}


def _set_smooth_and_bevel(obj: bpy.types.Object, bevel_width: float = 0.006) -> None:
    """Apply subtle bevel and smooth shading to a mechanical part."""
    bev = obj.modifiers.new(name="Bevel", type="BEVEL")
    bev.width = bevel_width
    bev.segments = 1
    bev.limit_method = "ANGLE"
    bev.angle_limit = math.radians(35.0)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bev.name)
    for poly in obj.data.polygons:
        poly.use_smooth = True


def _tag_part(
    obj: bpy.types.Object,
    bone_name: str,
    material: bpy.types.Material,
    parts_list: List[bpy.types.Object],
) -> bpy.types.Object:
    """Assign material and 1.0 vertex weight to bone_name before joining."""
    assign_material(obj, material)
    vg = obj.vertex_groups.new(name=bone_name)
    all_verts = [v.index for v in obj.data.vertices]
    if all_verts:
        vg.add(all_verts, 1.0, "REPLACE")
    parts_list.append(obj)
    return obj


def _add_box(
    name: str,
    loc: Tuple[float, float, float],
    scale: Tuple[float, float, float],
    rot: Tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel: float = 0.008,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        _set_smooth_and_bevel(obj, bevel)
    return obj


def _add_cyl(
    name: str,
    loc: Tuple[float, float, float],
    radius: float,
    depth: float,
    verts: int = 16,
    rot: Tuple[float, float, float] = (0.0, 0.0, 0.0),
    scale: Tuple[float, float, float] = (1.0, 1.0, 1.0),
    bevel: float = 0.005,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        _set_smooth_and_bevel(obj, bevel)
    return obj


def _add_sphere(
    name: str,
    loc: Tuple[float, float, float],
    radius: float,
    segs: int = 18,
    rings: int = 12,
    scale: Tuple[float, float, float] = (1.0, 1.0, 1.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segs, ring_count=rings, radius=radius, location=loc
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def _add_cone(
    name: str,
    loc: Tuple[float, float, float],
    r1: float,
    r2: float,
    depth: float,
    verts: int = 12,
    rot: Tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(
        vertices=verts, radius1=r1, radius2=r2, depth=depth, location=loc, rotation=rot
    )
    obj = bpy.context.active_object
    obj.name = name
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def _add_cyl_between(
    name: str,
    p0: Tuple[float, float, float],
    p1: Tuple[float, float, float],
    radius: float,
    verts: int = 12,
    bevel: float = 0.004,
) -> bpy.types.Object:
    """Create a cylinder spanning exact world points p0 -> p1."""
    v0 = mathutils.Vector(p0)
    v1 = mathutils.Vector(p1)
    delta = v1 - v0
    mid = (v0 + v1) * 0.5
    rot = delta.normalized().to_track_quat("Z", "Y").to_euler()
    return _add_cyl(name, (mid.x, mid.y, mid.z), radius, delta.length, verts=verts, rot=tuple(rot), bevel=bevel)


def _add_cone_between(
    name: str,
    p0: Tuple[float, float, float],
    p1: Tuple[float, float, float],
    r1: float,
    r2: float,
    verts: int = 12,
) -> bpy.types.Object:
    """Create a tapered cone spanning exact world points p0 (r1) -> p1 (r2)."""
    v0 = mathutils.Vector(p0)
    v1 = mathutils.Vector(p1)
    delta = v1 - v0
    mid = (v0 + v1) * 0.5
    rot = delta.normalized().to_track_quat("Z", "Y").to_euler()
    return _add_cone(name, (mid.x, mid.y, mid.z), r1, r2, delta.length, verts=verts, rot=tuple(rot))


def _add_box_between(
    name: str,
    p0: Tuple[float, float, float],
    p1: Tuple[float, float, float],
    width: float,
    thickness: float,
    bevel: float = 0.006,
) -> bpy.types.Object:
    """Create a beveled box spanning exact world points p0 -> p1 along local Z."""
    v0 = mathutils.Vector(p0)
    v1 = mathutils.Vector(p1)
    delta = v1 - v0
    mid = (v0 + v1) * 0.5
    rot = delta.normalized().to_track_quat("Z", "Y").to_euler()
    return _add_box(name, (mid.x, mid.y, mid.z), (width, thickness, delta.length), rot=tuple(rot), bevel=bevel)


def _add_coil_spring(
    name: str,
    loc: Tuple[float, float, float],
    coil_radius: float = 0.042,
    wire_radius: float = 0.0085,
    height: float = 0.25,
    turns: float = 6.0,
    steps_per_turn: int = 12,
    ring_segs: int = 6,
) -> bpy.types.Object:
    """Build a clean low-poly helical coil spring centered on Z=[0, height] at loc."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    total_steps = int(turns * steps_per_turn) + 1
    rings: List[List[bmesh.types.BMVert]] = []

    for i in range(total_steps):
        t = i / float(total_steps - 1)
        angle = t * turns * 2.0 * math.pi
        cz = t * height
        cx = math.cos(angle) * coil_radius
        cy = math.sin(angle) * coil_radius
        center = mathutils.Vector((cx, cy, cz))

        tangent = mathutils.Vector((
            -math.sin(angle) * coil_radius * turns * 2.0 * math.pi,
            math.cos(angle) * coil_radius * turns * 2.0 * math.pi,
            height,
        )).normalized()
        radial = mathutils.Vector((math.cos(angle), math.sin(angle), 0.0)).normalized()
        binormal = tangent.cross(radial).normalized()

        ring_verts: List[bmesh.types.BMVert] = []
        for j in range(ring_segs):
            phi = (j / float(ring_segs)) * 2.0 * math.pi
            offset = (radial * math.cos(phi) + binormal * math.sin(phi)) * wire_radius
            ring_verts.append(bm.verts.new(center + offset))
        rings.append(ring_verts)

    for i in range(len(rings) - 1):
        r0 = rings[i]
        r1 = rings[i + 1]
        for j in range(ring_segs):
            jn = (j + 1) % ring_segs
            bm.faces.new((r0[j], r0[jn], r1[jn], r1[j]))

    # Cap ends
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    obj.location = loc
    bpy.context.collection.objects.link(obj)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def _make_tile_noise(gx: int, gy: int, seed: int) -> List[float]:
    """Build a deterministic tileable [0, 1] float grid of size gx * gy."""
    table: List[float] = [0.0] * (gx * gy)
    for j in range(gy):
        for i in range(gx):
            h = (i * 374761393 + j * 668265263 + seed * 1442695041) & 0xFFFFFFFF
            h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
            h = h ^ (h >> 16)
            table[j * gx + i] = (h & 0xFFFF) / 65535.0
    return table


def _sample_tile_noise(table: List[float], gx: int, gy: int, fx: float, fy: float) -> float:
    """Bilinear smoothstep sample from a tileable noise grid."""
    tx = (fx * gx) % gx
    ty = (fy * gy) % gy
    ix0 = int(tx)
    iy0 = int(ty)
    ix1 = (ix0 + 1) % gx
    iy1 = (iy0 + 1) % gy
    sx = tx - ix0
    sy = ty - iy0
    sx = sx * sx * (3.0 - 2.0 * sx)
    sy = sy * sy * (3.0 - 2.0 * sy)
    r0 = iy0 * gx
    r1 = iy1 * gx
    n00 = table[r0 + ix0]
    n10 = table[r0 + ix1]
    n01 = table[r1 + ix0]
    n11 = table[r1 + ix1]
    nx0 = n00 + (n10 - n00) * sx
    nx1 = n01 + (n11 - n01) * sx
    return nx0 + (nx1 - nx0) * sy


def _generate_pbr_textures(out_dir: Path, size: int = 1024) -> Tuple[Path, Path, Path]:
    """Generate procedural directional brushed-steel albedo, ORM, and normal PNGs."""
    out_dir.mkdir(parents=True, exist_ok=True)
    albedo_path = out_dir / "imp_albedo.png"
    orm_path = out_dir / "imp_orm.png"
    normal_path = out_dir / "imp_normal.png"

    img_alb = bpy.data.images.new("ImpAlbedo", width=size, height=size)
    img_orm = bpy.data.images.new("ImpORM", width=size, height=size)
    img_nrm = bpy.data.images.new("ImpNormal", width=size, height=size)

    alb_pixels = [0.0] * (size * size * 4)
    orm_pixels = [0.0] * (size * size * 4)
    nrm_pixels = [0.0] * (size * size * 4)
    height_buf = [0.0] * (size * size)

    # Tileable anisotropic brushed-steel & grime grids (zero diagonal sine stripes)
    brush_coarse = _make_tile_noise(12, 256, seed=11)
    brush_fine = _make_tile_noise(24, 512, seed=29)
    grime_low = _make_tile_noise(8, 8, seed=43)
    grime_mid = _make_tile_noise(24, 24, seed=71)

    rivet_centers = (
        (0.085, 0.085),
        (0.915, 0.085),
        (0.085, 0.915),
        (0.915, 0.915),
        (0.500, 0.085),
        (0.500, 0.915),
    )
    rivet_r = 0.026
    rivet_halo_r = 0.044
    rivet_r2 = rivet_r * rivet_r
    rivet_halo_r2 = rivet_halo_r * rivet_halo_r

    # Pass 1: height + albedo + ORM
    for y in range(size):
        fy = y / float(size)
        py = (fy * 4.0) % 1.0
        dy_edge = py if py < 0.5 else 1.0 - py
        # Deterministic per-row micro-streak variation
        row_h = ((y * 2654435761) & 0xFFFF) / 65535.0
        for x in range(size):
            fx = x / float(size)
            px = (fx * 4.0) % 1.0
            dx_edge = px if px < 0.5 else 1.0 - px

            # Anisotropic horizontal brushed steel micro-grain
            b0 = _sample_tile_noise(brush_coarse, 12, 256, fx, fy)
            b1 = _sample_tile_noise(brush_fine, 24, 512, fx, fy)
            brush = 0.55 * b0 + 0.30 * b1 + 0.15 * row_h

            # Organic recessed grime patches
            g0 = _sample_tile_noise(grime_low, 8, 8, fx, fy)
            g1 = _sample_tile_noise(grime_mid, 24, 24, fx, fy)
            grime_noise = 0.65 * g0 + 0.35 * g1

            # Chamfered armor panel seam groove
            edge_dist = dx_edge if dx_edge < dy_edge else dy_edge
            seam = 0.0
            if edge_dist < 0.024:
                t = 1.0 - (edge_dist / 0.024)
                seam = t * t

            # Subtle riveted armor relief near panel corners & mid-edges
            rivet_h = 0.0
            rivet_ring = 0.0
            if px < 0.14 or px > 0.86 or (0.44 < px < 0.56):
                if py < 0.14 or py > 0.86:
                    for rx, ry in rivet_centers:
                        ddx = px - rx
                        ddy = py - ry
                        d2 = ddx * ddx + ddy * ddy
                        if d2 < rivet_r2:
                            rivet_h = math.sqrt(1.0 - d2 / rivet_r2)
                            break
                        if d2 < rivet_halo_r2:
                            t_halo = 1.0 - (math.sqrt(d2) - rivet_r) / (rivet_halo_r - rivet_r)
                            if t_halo > rivet_ring:
                                rivet_ring = t_halo

            recess = max(seam, rivet_ring * 0.65)
            grime = max(0.0, min(1.0, grime_noise * 0.72 + recess * 0.55))

            base_steel = 0.44 + 0.14 * (brush - 0.5) - 0.20 * grime - 0.12 * seam + 0.10 * rivet_h
            oxide_tint = max(0.0, grime - 0.45) * 0.14

            r = max(0.05, min(1.0, base_steel + oxide_tint * 0.8))
            g = max(0.05, min(1.0, base_steel + oxide_tint * 0.4))
            b = max(0.05, min(1.0, base_steel * 1.04))

            ao = max(0.28, min(1.0, (0.94 - 0.24 * grime_noise) * (1.0 - 0.55 * seam) * (1.0 - 0.30 * rivet_ring)))
            rough = max(0.22, min(0.88, 0.28 + 0.28 * grime + 0.24 * seam - 0.08 * rivet_h))
            metal = max(0.35, 0.90 - 0.38 * seam - 0.22 * max(0.0, grime - 0.5))

            h = 0.50 + 0.045 * (brush - 0.5) + 0.03 * (g0 - 0.5) - 0.24 * seam + 0.22 * rivet_h - 0.05 * rivet_ring
            height_buf[y * size + x] = h

            idx = (y * size + x) * 4
            alb_pixels[idx] = r
            alb_pixels[idx + 1] = g
            alb_pixels[idx + 2] = b
            alb_pixels[idx + 3] = 1.0

            orm_pixels[idx] = ao
            orm_pixels[idx + 1] = rough
            orm_pixels[idx + 2] = metal
            orm_pixels[idx + 3] = 1.0

    # Pass 2: normal map from height derivatives
    strength = 2.2
    for y in range(size):
        ym = (y - 1) % size
        yp = (y + 1) % size
        for x in range(size):
            xm = (x - 1) % size
            xp = (x + 1) % size
            dx = (height_buf[y * size + xp] - height_buf[y * size + xm]) * strength
            dy = (height_buf[yp * size + x] - height_buf[ym * size + x]) * strength
            nx, ny, nz = -dx, -dy, 1.0
            inv_len = 1.0 / math.sqrt(nx * nx + ny * ny + nz * nz)
            idx = (y * size + x) * 4
            nrm_pixels[idx] = 0.5 + 0.5 * (nx * inv_len)
            nrm_pixels[idx + 1] = 0.5 + 0.5 * (ny * inv_len)
            nrm_pixels[idx + 2] = 0.5 + 0.5 * (nz * inv_len)
            nrm_pixels[idx + 3] = 1.0

    img_alb.pixels.foreach_set(alb_pixels)
    img_orm.pixels.foreach_set(orm_pixels)
    img_nrm.pixels.foreach_set(nrm_pixels)

    img_alb.filepath_raw = str(albedo_path)
    img_alb.file_format = "PNG"
    img_alb.save()

    img_orm.filepath_raw = str(orm_path)
    img_orm.file_format = "PNG"
    img_orm.save()

    img_nrm.filepath_raw = str(normal_path)
    img_nrm.file_format = "PNG"
    img_nrm.save()

    return albedo_path, orm_path, normal_path


def _write_tres_and_manifest(
    out_dir: Path,
    tri_count: int,
    uv_layers: int,
    dims_godot: Tuple[float, float, float],
) -> None:
    """Write imp.tres (ORMMaterial3D) and asset_manifest.json."""
    tres_content = (
        '[gd_resource type="ORMMaterial3D" load_steps=4 format=3]\n\n'
        '[ext_resource type="Texture2D" path="res://assets/models/imp/imp_albedo.png" id="1_albedo"]\n'
        '[ext_resource type="Texture2D" path="res://assets/models/imp/imp_orm.png" id="2_orm"]\n'
        '[ext_resource type="Texture2D" path="res://assets/models/imp/imp_normal.png" id="3_normal"]\n\n'
        "[resource]\n"
        'resource_name = "M_imp"\n'
        'albedo_texture = ExtResource("1_albedo")\n'
        'orm_texture = ExtResource("2_orm")\n'
        "roughness = 1.0\n"
        "metallic = 1.0\n"
        "normal_enabled = true\n"
        'normal_texture = ExtResource("3_normal")\n'
        "uv1_scale = Vector3(1.0, 1.0, 1.0)\n"
    )
    (out_dir / "imp.tres").write_text(tres_content, encoding="utf-8")

    manifest = {
        "prop_slug": "imp",
        "assets": ["imp.glb", "imp_rigged.glb"],
        "tri_count": tri_count,
        "uv_layers": uv_layers,
        "target_layer": "Layer 3 Interactive",
        "physics_layer": "Layer 5 Enemies",
        "collision_hint": "CapsuleShape3D or ConvexPolygonShape3D (character enemy)",
        "generator": "Blender 5.3 Procedural Rigged Imp",
        "preset": "metal",
        "dimensions_m": [round(d, 4) for d in dims_godot],
        "scale": [1.0, 1.0, 1.0],
        "bones": BONE_NAMES,
        "animations": list(CLIP_SPECS.keys()),
        "fps": 60,
    }
    (out_dir / "asset_manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )


def _build_imp_mesh(out_dir: Path) -> Tuple[bpy.types.Object, float]:
    """Construct the chunky fat-imp mechanical mesh (1.15m tall, facing +Y -> -Z in Godot)."""
    albedo_path, _, normal_path = _generate_pbr_textures(out_dir, size=1024)
    alb_img = bpy.data.images.load(str(albedo_path), check_existing=True)
    nrm_img = bpy.data.images.load(str(normal_path), check_existing=True)

    mat_steel = create_pbr_material(
        name="Mat_Imp_Steel",
        base_color=(0.68, 0.70, 0.72, 1.0),
        metallic=0.88,
        roughness=0.40,
        base_color_image=alb_img,
        normal_image=nrm_img,
        normal_strength=1.0,
    )
    mat_trim = create_pbr_material(
        name="Mat_Imp_Trim",
        base_color=(0.36, 0.34, 0.32, 1.0),
        metallic=0.84,
        roughness=0.48,
        base_color_image=alb_img,
        normal_image=nrm_img,
        normal_strength=0.8,
    )
    mat_optics = create_pbr_material(
        name="Mat_Imp_Optics",
        base_color=(0.12, 0.72, 1.0, 1.0),
        metallic=0.05,
        roughness=0.12,
        emission_color=(0.12, 0.72, 1.0, 1.0),
        emission_strength=8.0,
    )
    mat_core = create_pbr_material(
        name="Mat_Imp_CoreGlow",
        base_color=(0.04, 0.20, 0.30, 1.0),
        metallic=0.2,
        roughness=0.5,
        emission_color=(0.12, 0.72, 1.0, 1.0),
        emission_strength=4.5,
    )
    mat_mouth = create_pbr_material(
        name="Mat_Imp_MouthDark",
        base_color=(0.03, 0.03, 0.04, 1.0),
        metallic=0.25,
        roughness=0.88,
    )

    parts: List[bpy.types.Object] = []

    # 1. Pelvis (chunky rounded armored hip bowl)
    _tag_part(
        _add_sphere("Pelvis_Bowl", (0.0, 0.0, 0.37), 0.20, segs=18, rings=10, scale=(1.12, 0.96, 0.72)),
        "Pelvis",
        mat_steel,
        parts,
    )
    _tag_part(
        _add_box("Pelvis_Codpiece", (0.0, -0.14, 0.35), (0.14, 0.12, 0.14), bevel=0.01),
        "Pelvis",
        mat_trim,
        parts,
    )

    # 2. Spine / Barrel Torso (segmented weathered steel chestplate + electric blue core glow seams)
    _tag_part(
        _add_cyl("Torso_Barrel", (0.0, 0.0, 0.54), 0.22, 0.25, verts=18, scale=(1.12, 0.96, 1.0)),
        "Spine",
        mat_steel,
        parts,
    )
    _tag_part(
        _add_box("Torso_ChestPlate", (0.0, -0.15, 0.57), (0.34, 0.14, 0.18), bevel=0.012),
        "Spine",
        mat_steel,
        parts,
    )
    _tag_part(
        _add_box("Torso_ChestSeamGlow", (0.0, -0.155, 0.502), (0.31, 0.125, 0.016), bevel=0.002),
        "Spine",
        mat_core,
        parts,
    )
    _tag_part(
        _add_box("Torso_BellyPlate", (0.0, -0.16, 0.45), (0.30, 0.12, 0.10), bevel=0.01),
        "Spine",
        mat_trim,
        parts,
    )
    _tag_part(
        _add_box("Torso_BackPack", (0.0, 0.18, 0.55), (0.28, 0.12, 0.22), bevel=0.012),
        "Spine",
        mat_trim,
        parts,
    )
    _tag_part(
        _add_cyl("Torso_NeckGlow", (0.0, 0.0, 0.67), 0.15, 0.04, verts=16),
        "Spine",
        mat_core,
        parts,
    )
    for side, sx in [("L", 1.0), ("R", -1.0)]:
        _tag_part(
            _add_box(f"Torso_SideVent_{side}", (sx * 0.245, -0.02, 0.545), (0.025, 0.11, 0.018), bevel=0.002),
            "Spine",
            mat_core,
            parts,
        )

    # 3. Head / Helmet (oversized rounded dome, connected horns, brow, electric blue optics, jagged jaw)
    _tag_part(
        _add_sphere("Head_Dome", (0.0, 0.0, 0.86), 0.23, segs=20, rings=14, scale=(1.04, 1.0, 0.96)),
        "Head",
        mat_steel,
        parts,
    )
    _tag_part(
        _add_box("Head_JawRim", (0.0, -0.11, 0.72), (0.34, 0.20, 0.08), bevel=0.01),
        "Head",
        mat_steel,
        parts,
    )
    _tag_part(
        _add_box("Head_MouthCavity", (0.0, -0.145, 0.77), (0.28, 0.12, 0.075), bevel=0.002),
        "Head",
        mat_mouth,
        parts,
    )
    _tag_part(
        _add_box("Head_MouthCoreSlit", (0.0, -0.195, 0.77), (0.15, 0.028, 0.014), bevel=0.002),
        "Head",
        mat_core,
        parts,
    )
    # Jagged upper & lower teeth (sharp metallic grin)
    for i, tx in enumerate([-0.11, -0.055, 0.0, 0.055, 0.11]):
        _tag_part(
            _add_cone(f"Tooth_Up_{i}", (tx, -0.21, 0.795), 0.024, 0.002, 0.052, verts=6, rot=(math.pi, 0.0, 0.0)),
            "Head",
            mat_steel,
            parts,
        )
        _tag_part(
            _add_cone(f"Tooth_Lo_{i}", (tx + 0.024, -0.21, 0.745), 0.024, 0.002, 0.052, verts=6),
            "Head",
            mat_steel,
            parts,
        )
    # Nose ridge
    _tag_part(
        _add_box("Head_Nose", (0.0, -0.23, 0.855), (0.038, 0.05, 0.065), bevel=0.005),
        "Head",
        mat_trim,
        parts,
    )
    # Glowing electric-blue optic eyes + evil V-angled brow ridges + ear bolts + connected curved horns
    for side, sx in [("L", 1.0), ("R", -1.0)]:
        _tag_part(
            _add_cyl(f"Eye_Socket_{side}", (sx * 0.09, -0.20, 0.88), 0.052, 0.055, verts=14, rot=(math.radians(90), 0.0, 0.0)),
            "Head",
            mat_trim,
            parts,
        )
        _tag_part(
            _add_sphere(f"Eye_Optic_{side}", (sx * 0.09, -0.222, 0.88), 0.038, segs=12, rings=8),
            "Head",
            mat_optics,
            parts,
        )
        # Evil angry V-brow: inner side angled DOWN, outer side angled UP
        _tag_part(
            _add_box(f"Brow_{side}", (sx * 0.095, -0.225, 0.935), (0.105, 0.055, 0.032), rot=(0.0, sx * math.radians(-24), 0.0), bevel=0.004),
            "Head",
            mat_steel,
            parts,
        )
        _tag_part(
            _add_cyl(f"EarDrum_{side}", (sx * 0.23, 0.0, 0.84), 0.05, 0.05, verts=12, rot=(0.0, math.radians(90), 0.0)),
            "Head",
            mat_trim,
            parts,
        )
        # Connected curved horns: skull socket -> Horn_Base -> spherical joint collar -> Horn_Tip
        h_p0 = (sx * 0.125, 0.0, 1.00)
        h_p1 = (sx * 0.185, 0.02, 1.11)
        h_p2 = (sx * 0.215, -0.03, 1.21)
        _tag_part(
            _add_cyl_between(f"Horn_Socket_{side}", (sx * 0.115, 0.0, 0.99), (sx * 0.145, 0.007, 1.045), 0.060, verts=12, bevel=0.004),
            "Head",
            mat_trim,
            parts,
        )
        _tag_part(
            _add_cone_between(f"Horn_Base_{side}", h_p0, h_p1, 0.054, 0.034, verts=12),
            "Head",
            mat_steel,
            parts,
        )
        _tag_part(
            _add_sphere(f"Horn_Joint_{side}", h_p1, 0.037, segs=10, rings=6),
            "Head",
            mat_trim,
            parts,
        )
        _tag_part(
            _add_cone_between(f"Horn_Tip_{side}", h_p1, h_p2, 0.034, 0.004, verts=12),
            "Head",
            mat_trim,
            parts,
        )

    # 4. Hybrid Pogo-Strut Legs: outer rigid mechanical strut + inner helical coil spring + solid ankle joints + footplate
    for side, sx in [("L", 1.0), ("R", -1.0)]:
        # Hip joint drum spanning spring & outer strut
        _tag_part(
            _add_cyl(f"HipDrum_{side}", (sx * 0.16, 0.0, 0.36), 0.068, 0.11, verts=14, rot=(0.0, math.radians(90), 0.0)),
            f"Thigh_{side}",
            mat_trim,
            parts,
        )
        # Spring upper mounting cap into hip drum
        _tag_part(
            _add_cyl(f"SpringTopCap_{side}", (sx * 0.12, 0.0, 0.335), 0.052, 0.04, verts=12),
            f"Thigh_{side}",
            mat_trim,
            parts,
        )
        # Outer rigid mechanical strut (upper = Thigh, lower = Shin)
        _tag_part(
            _add_box(f"StrutUpper_{side}", (sx * 0.205, 0.0, 0.29), (0.042, 0.055, 0.15), bevel=0.006),
            f"Thigh_{side}",
            mat_steel,
            parts,
        )
        _tag_part(
            _add_cyl(f"StrutKnee_{side}", (sx * 0.205, 0.0, 0.215), 0.038, 0.068, verts=12, rot=(0.0, math.radians(90), 0.0)),
            f"Shin_{side}",
            mat_trim,
            parts,
        )
        _tag_part(
            _add_box(f"StrutLower_{side}", (sx * 0.205, 0.0, 0.135), (0.036, 0.048, 0.155), bevel=0.006),
            f"Shin_{side}",
            mat_steel,
            parts,
        )
        # Inner helical coil spring (Z = 0.06 .. 0.33), split-weighted Thigh (top) / Shin (bottom)
        spring_obj = _add_coil_spring(
            f"PogoSpring_{side}",
            (sx * 0.12, 0.0, 0.06),
            coil_radius=0.044,
            wire_radius=0.0085,
            height=0.27,
            turns=6.0,
            steps_per_turn=10,
            ring_segs=6,
        )
        assign_material(spring_obj, mat_trim)
        vg_th = spring_obj.vertex_groups.new(name=f"Thigh_{side}")
        vg_sh = spring_obj.vertex_groups.new(name=f"Shin_{side}")
        for v in spring_obj.data.vertices:
            t_z = max(0.0, min(1.0, v.co.z / 0.27))
            vg_th.add([v.index], t_z, "REPLACE")
            vg_sh.add([v.index], 1.0 - t_z, "REPLACE")
        parts.append(spring_obj)

        # Solid ankle joints connecting spring bottom, lower strut, and footplate with zero air gaps
        _tag_part(
            _add_cyl(f"AnkleBracket_{side}", (sx * 0.12, 0.0, 0.06), 0.054, 0.042, verts=12),
            f"Foot_{side}",
            mat_trim,
            parts,
        )
        _tag_part(
            _add_sphere(f"AnkleBall_{side}", (sx * 0.205, 0.0, 0.06), 0.036, segs=10, rings=6),
            f"Foot_{side}",
            mat_trim,
            parts,
        )
        _tag_part(
            _add_cyl(f"AnkleCrossPin_{side}", (sx * 0.162, 0.0, 0.062), 0.026, 0.11, verts=10, rot=(0.0, math.radians(90), 0.0)),
            f"Foot_{side}",
            mat_steel,
            parts,
        )

        # Angled / wedged footplate resting cleanly at Z = 0.0
        _tag_part(
            _add_box(f"FootPad_{side}", (sx * 0.15, -0.025, 0.026), (0.14, 0.20, 0.052), bevel=0.008),
            f"Foot_{side}",
            mat_steel,
            parts,
        )
        _tag_part(
            _add_box(f"FootToeWedge_{side}", (sx * 0.15, -0.115, 0.024), (0.12, 0.055, 0.036), rot=(math.radians(-12), 0.0, 0.0), bevel=0.005),
            f"Foot_{side}",
            mat_trim,
            parts,
        )

    # 5. Arms, Solid Elbow/Wrist Hinges & Twin-Blade Serrated Claws
    for side, sx in [("L", 1.0), ("R", -1.0)]:
        p_sh = (sx * 0.25, 0.0, 0.62)
        p_el = (sx * 0.40, 0.0, 0.49)
        p_wr = (sx * 0.50, -0.035, 0.38)

        _tag_part(
            _add_sphere(f"Pauldron_{side}", (sx * 0.255, 0.0, 0.625), 0.088, segs=12, rings=8, scale=(1.1, 1.0, 0.88)),
            f"Arm_{side}",
            mat_steel,
            parts,
        )
        _tag_part(
            _add_cyl_between(f"UpperArm_{side}", p_sh, p_el, 0.045, verts=12, bevel=0.004),
            f"Arm_{side}",
            mat_trim,
            parts,
        )
        # Solid elbow ball joint + transverse hinge cylinder
        _tag_part(
            _add_sphere(f"ElbowBall_{side}", p_el, 0.056, segs=12, rings=8),
            f"Forearm_{side}",
            mat_trim,
            parts,
        )
        _tag_part(
            _add_cyl(f"ElbowHinge_{side}", p_el, 0.040, 0.092, verts=10, rot=(math.radians(90), 0.0, 0.0)),
            f"Arm_{side}",
            mat_steel,
            parts,
        )
        _tag_part(
            _add_box_between(f"ForearmGauntlet_{side}", p_el, p_wr, 0.082, 0.082, bevel=0.008),
            f"Forearm_{side}",
            mat_steel,
            parts,
        )
        # Solid wrist collar + knuckle ball anchoring claws directly to Forearm
        _tag_part(
            _add_cyl_between(
                f"WristCollar_{side}",
                (sx * 0.482, -0.029, 0.400),
                (sx * 0.514, -0.040, 0.365),
                0.048,
                verts=12,
                bevel=0.004,
            ),
            f"Forearm_{side}",
            mat_trim,
            parts,
        )
        _tag_part(
            _add_sphere(f"WristKnuckle_{side}", p_wr, 0.048, segs=10, rings=6),
            f"Forearm_{side}",
            mat_trim,
            parts,
        )
        # Twin serrated pincer blades rooted solidly inside WristKnuckle
        _tag_part(
            _add_cone_between(
                f"ClawUpper_{side}",
                (p_wr[0], p_wr[1], p_wr[2] + 0.016),
                (sx * 0.58, -0.11, 0.39),
                0.028,
                0.003,
                verts=6,
            ),
            f"Forearm_{side}",
            mat_steel,
            parts,
        )
        _tag_part(
            _add_cone_between(
                f"ClawLower_{side}",
                (p_wr[0], p_wr[1], p_wr[2] - 0.016),
                (sx * 0.57, -0.11, 0.29),
                0.024,
                0.003,
                verts=6,
            ),
            f"Forearm_{side}",
            mat_trim,
            parts,
        )

    # Join all parts into one clean skinned mesh
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()

    imp_mesh = bpy.context.active_object
    imp_mesh.name = "Imp_Mesh"

    # Zero Imp_Mesh origin to (0, 0, 0) in world space before grounding/scaling
    bpy.ops.object.select_all(action="DESELECT")
    imp_mesh.select_set(True)
    bpy.context.view_layer.objects.active = imp_mesh
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Ground at Z = 0.0 and verify exact 1.15m height
    min_z = min(v.co.z for v in imp_mesh.data.vertices)
    max_z = max(v.co.z for v in imp_mesh.data.vertices)
    height = max_z - min_z
    scale_factor = 1.15 / height if height > 0.0 else 1.0
    for v in imp_mesh.data.vertices:
        v.co.z -= min_z
        v.co *= scale_factor
    imp_mesh.data.update()

    # Rotate 180 deg around Z so face points +Y in Blender -> -Z in Godot (glTF Y-up)
    imp_mesh.rotation_euler = (0.0, 0.0, math.pi)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Smart UV Project so uv_layers >= 1
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")

    # Compute final stats & export unrigged imp.glb + manifest
    tri_count = sum(max(1, len(p.vertices) - 2) for p in imp_mesh.data.polygons)
    uv_layers = len(imp_mesh.data.uv_layers)
    xs = [v.co.x for v in imp_mesh.data.vertices]
    ys = [v.co.y for v in imp_mesh.data.vertices]
    zs = [v.co.z for v in imp_mesh.data.vertices]
    dims_godot = (max(xs) - min(xs), max(zs) - min(zs), max(ys) - min(ys))

    _write_tres_and_manifest(out_dir, tri_count, uv_layers, dims_godot)
    export_godot_glb(out_dir / "imp.glb", export_animations=False, apply_modifiers=True)
    return imp_mesh, scale_factor


def _build_armature(imp_mesh: bpy.types.Object, scale_factor: float = 1.0) -> bpy.types.Object:
    """Create the 14-bone Imp armature aligned +Y forward (-Z in Godot) and bind Imp_Mesh."""
    arm_obj = create_armature("Imp_Armature")
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    def _s(pt: Tuple[float, float, float]) -> Tuple[float, float, float]:
        return (pt[0] * scale_factor, pt[1] * scale_factor, pt[2] * scale_factor)

    add_bone(arm_obj, "Root", _s((0.0, 0.0, 0.0)), _s((0.0, 0.0, 0.14)))
    add_bone(arm_obj, "Pelvis", _s((0.0, 0.0, 0.34)), _s((0.0, 0.0, 0.44)), parent_name="Root")
    add_bone(arm_obj, "Spine", _s((0.0, 0.0, 0.44)), _s((0.0, 0.0, 0.68)), parent_name="Pelvis")
    add_bone(arm_obj, "Head", _s((0.0, 0.0, 0.68)), _s((0.0, 0.0, 1.05)), parent_name="Spine")

    add_bone(arm_obj, "Arm_L", _s((0.25, 0.0, 0.62)), _s((0.40, 0.0, 0.49)), parent_name="Spine")
    add_bone(arm_obj, "Forearm_L", _s((0.40, 0.0, 0.49)), _s((0.54, -0.05, 0.34)), parent_name="Arm_L")
    add_bone(arm_obj, "Arm_R", _s((-0.25, 0.0, 0.62)), _s((-0.40, 0.0, 0.49)), parent_name="Spine")
    add_bone(arm_obj, "Forearm_R", _s((-0.40, 0.0, 0.49)), _s((-0.54, -0.05, 0.34)), parent_name="Arm_R")

    add_bone(arm_obj, "Thigh_L", _s((0.16, 0.0, 0.36)), _s((0.16, 0.0, 0.22)), parent_name="Pelvis")
    add_bone(arm_obj, "Shin_L", _s((0.16, 0.0, 0.22)), _s((0.16, 0.0, 0.08)), parent_name="Thigh_L")
    add_bone(arm_obj, "Foot_L", _s((0.16, 0.0, 0.08)), _s((0.16, -0.12, 0.0)), parent_name="Shin_L")

    add_bone(arm_obj, "Thigh_R", _s((-0.16, 0.0, 0.36)), _s((-0.16, 0.0, 0.22)), parent_name="Pelvis")
    add_bone(arm_obj, "Shin_R", _s((-0.16, 0.0, 0.22)), _s((-0.16, 0.0, 0.08)), parent_name="Thigh_R")
    add_bone(arm_obj, "Foot_R", _s((-0.16, 0.0, 0.08)), _s((-0.16, -0.12, 0.0)), parent_name="Shin_R")

    # Rotate every bone matrix +180 deg around Z so positions and bone local axes face +Y (-Z in Godot)
    rz = mathutils.Matrix.Rotation(math.pi, 4, "Z")
    for bone in arm_obj.data.edit_bones:
        length = bone.length
        m_rot = rz @ bone.matrix
        bone.head = m_rot.translation
        bone.tail = m_rot.translation + m_rot.to_3x3() @ mathutils.Vector((0.0, length, 0.0))
        bone.align_roll(m_rot.to_3x3() @ mathutils.Vector((0.0, 0.0, 1.0)))

    bpy.ops.object.mode_set(mode="OBJECT")

    arm_mod = imp_mesh.modifiers.new(name="Armature", type="ARMATURE")
    arm_mod.object = arm_obj
    imp_mesh.parent = arm_obj
    return arm_obj


def _pose(
    pb: bpy.types.PoseBone,
    frame: int,
    rot_deg: Tuple[float, float, float] | None = None,
    loc: Tuple[float, float, float] | None = None,
) -> None:
    """Set pose bone rotation/location and insert Bezier keyframes."""
    if loc is not None:
        pb.location = loc
        pb.keyframe_insert(data_path="location", frame=frame)
    if rot_deg is not None:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = tuple(math.radians(a) for a in rot_deg)
        pb.keyframe_insert(data_path="rotation_euler", frame=frame)


def _finalize_action(arm_obj: bpy.types.Object, action: bpy.types.Action, name: str, end_frame: int, is_loop: bool) -> None:
    """Apply N-1 loop trim if cyclic, reset pose, and push action to NLA."""
    if is_loop:
        action.use_frame_range = True
        action.frame_start = 0
        action.frame_end = end_frame - 1
    else:
        action.use_frame_range = True
        action.frame_start = 0
        action.frame_end = end_frame

    push_action_to_nla(arm_obj, action, track_name=name)
    bpy.ops.pose.transforms_clear()


def _bake_animations(arm_obj: bpy.types.Object) -> None:
    """Bake all 8 60 FPS Bezier animations for the Imp."""
    bpy.context.scene.render.fps = 60
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    pb = arm_obj.pose.bones

    # 1. idle (120 frames, loop -> trimmed 0..119)
    act = create_action(arm_obj, "idle")
    for f, bob, sway, head_y, arm_d in [
        (0, 0.0, 0.0, 0.0, 0.0),
        (30, -0.015, 2.5, -4.0, 4.0),
        (60, 0.0, 0.0, 0.0, 0.0),
        (90, -0.015, -2.5, 4.0, -4.0),
        (120, 0.0, 0.0, 0.0, 0.0),
    ]:
        _pose(pb["Pelvis"], f, loc=(0.0, bob, 0.0), rot_deg=(0.0, sway, 0.0))
        _pose(pb["Spine"], f, rot_deg=(3.0, -sway * 0.6, 0.0))
        _pose(pb["Head"], f, rot_deg=(-2.0, 0.0, head_y))
        _pose(pb["Arm_L"], f, rot_deg=(arm_d, 0.0, -8.0))
        _pose(pb["Arm_R"], f, rot_deg=(-arm_d, 0.0, 8.0))
        _pose(pb["Forearm_L"], f, rot_deg=(-18.0, 0.0, 0.0))
        _pose(pb["Forearm_R"], f, rot_deg=(-18.0, 0.0, 0.0))
    _finalize_action(arm_obj, act, "idle", 120, True)

    # 2. run (48 frames fat-imp waddle loop, in-place -> trimmed 0..47)
    act = create_action(arm_obj, "run")
    run_keys = [
        # (frame, pel_x, pel_z, pel_roll, spine_yaw, th_l, sh_l, ft_l, th_r, sh_r, ft_r, arm_l, arm_r)
        (0, -0.035, -0.02, -7.0, 8.0, -28.0, 35.0, -8.0, 26.0, 12.0, -20.0, 26.0, -26.0),
        (12, 0.0, 0.015, 0.0, 0.0, 5.0, 48.0, -25.0, -10.0, 15.0, -5.0, 0.0, 0.0),
        (24, 0.035, -0.02, 7.0, -8.0, 26.0, 12.0, -20.0, -28.0, 35.0, -8.0, -26.0, 26.0),
        (36, 0.0, 0.015, 0.0, 0.0, -10.0, 15.0, -5.0, 5.0, 48.0, -25.0, 0.0, 0.0),
        (48, -0.035, -0.02, -7.0, 8.0, -28.0, 35.0, -8.0, 26.0, 12.0, -20.0, 26.0, -26.0),
    ]
    for f, px, pz, proll, syaw, thl, shl, ftl, thr, shr, ftr, arml, armr in run_keys:
        _pose(pb["Pelvis"], f, loc=(px, pz, 0.0), rot_deg=(6.0, proll, 0.0))
        _pose(pb["Spine"], f, rot_deg=(10.0, -proll * 0.6, syaw))
        _pose(pb["Head"], f, rot_deg=(-8.0, 0.0, -syaw * 0.5))
        _pose(pb["Thigh_L"], f, rot_deg=(thl, 0.0, 0.0))
        _pose(pb["Shin_L"], f, rot_deg=(shl, 0.0, 0.0))
        _pose(pb["Foot_L"], f, rot_deg=(ftl, 0.0, 0.0))
        _pose(pb["Thigh_R"], f, rot_deg=(thr, 0.0, 0.0))
        _pose(pb["Shin_R"], f, rot_deg=(shr, 0.0, 0.0))
        _pose(pb["Foot_R"], f, rot_deg=(ftr, 0.0, 0.0))
        _pose(pb["Arm_L"], f, rot_deg=(arml, -14.0, -12.0))
        _pose(pb["Arm_R"], f, rot_deg=(armr, 14.0, 12.0))
        _pose(pb["Forearm_L"], f, rot_deg=(-30.0, 0.0, 0.0))
        _pose(pb["Forearm_R"], f, rot_deg=(-30.0, 0.0, 0.0))
    _finalize_action(arm_obj, act, "run", 48, True)

    # 3. jump (54 frames, one-shot)
    act = create_action(arm_obj, "jump")
    jump_keys = [
        (0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0),
        (10, -0.09, 14.0, -35.0, 65.0, -30.0, -25.0),  # crouch anticipation
        (20, 0.22, -10.0, 18.0, -10.0, 15.0, 42.0),   # explosive launch
        (34, 0.28, 6.0, -28.0, 55.0, -15.0, 25.0),    # apex tuck
        (45, -0.07, 12.0, -30.0, 58.0, -25.0, -15.0), # landing compression
        (54, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0),           # settle
    ]
    for f, pz, sp_x, th, sh, ft, arm_x in jump_keys:
        _pose(pb["Pelvis"], f, loc=(0.0, pz, 0.0))
        _pose(pb["Spine"], f, rot_deg=(sp_x, 0.0, 0.0))
        _pose(pb["Head"], f, rot_deg=(-sp_x * 0.5, 0.0, 0.0))
        _pose(pb["Thigh_L"], f, rot_deg=(th, 0.0, 0.0))
        _pose(pb["Thigh_R"], f, rot_deg=(th, 0.0, 0.0))
        _pose(pb["Shin_L"], f, rot_deg=(sh, 0.0, 0.0))
        _pose(pb["Shin_R"], f, rot_deg=(sh, 0.0, 0.0))
        _pose(pb["Foot_L"], f, rot_deg=(ft, 0.0, 0.0))
        _pose(pb["Foot_R"], f, rot_deg=(ft, 0.0, 0.0))
        _pose(pb["Arm_L"], f, rot_deg=(arm_x, -18.0, 0.0))
        _pose(pb["Arm_R"], f, rot_deg=(arm_x, 18.0, 0.0))
    _finalize_action(arm_obj, act, "jump", 54, False)

    # 4. charge_lightning (72 frames, one-shot)
    act = create_action(arm_obj, "charge_lightning")
    charge_keys = [
        (0, 0.0, 0.0, 0.0, 0.0, 0.0),
        (14, -0.06, -12.0, 55.0, -28.0, -20.0),
        (28, -0.07, -18.0, 70.0, -35.0, 20.0),
        (40, -0.07, -14.0, 66.0, -32.0, -18.0),
        (52, -0.08, -20.0, 74.0, -38.0, 15.0),
        (62, -0.03, 18.0, -45.0, 35.0, 0.0),   # discharge thrust
        (72, 0.0, 0.0, 0.0, 0.0, 0.0),
    ]
    for f, pz, sp_x, arm_x, arm_y, head_z in charge_keys:
        _pose(pb["Pelvis"], f, loc=(0.0, pz, 0.0))
        _pose(pb["Spine"], f, rot_deg=(sp_x, 0.0, 0.0))
        _pose(pb["Head"], f, rot_deg=(sp_x * 0.6, 0.0, head_z * 0.2))
        _pose(pb["Thigh_L"], f, rot_deg=(-18.0 if pz < -0.02 else 0.0, 0.0, 0.0))
        _pose(pb["Thigh_R"], f, rot_deg=(-18.0 if pz < -0.02 else 0.0, 0.0, 0.0))
        _pose(pb["Shin_L"], f, rot_deg=(36.0 if pz < -0.02 else 0.0, 0.0, 0.0))
        _pose(pb["Shin_R"], f, rot_deg=(36.0 if pz < -0.02 else 0.0, 0.0, 0.0))
        _pose(pb["Arm_L"], f, rot_deg=(arm_x, arm_y, 0.0))
        _pose(pb["Arm_R"], f, rot_deg=(arm_x, -arm_y, 0.0))
        _pose(pb["Forearm_L"], f, rot_deg=(-35.0, 0.0, 0.0))
        _pose(pb["Forearm_R"], f, rot_deg=(-35.0, 0.0, 0.0))
    _finalize_action(arm_obj, act, "charge_lightning", 72, False)

    # 5. stack_mount (54 frames, one-shot)
    act = create_action(arm_obj, "stack_mount")
    stack_keys = [
        (0, 0.0, 0.0, 0.0, 0.0, 0.0),
        (12, -0.08, 16.0, -30.0, 55.0, -25.0),
        (28, 0.16, -8.0, -45.0, 80.0, 50.0),
        (42, 0.04, 8.0, -35.0, 70.0, 28.0),
        (54, 0.0, 6.0, -25.0, 50.0, 20.0),
    ]
    for f, pz, sp_x, th, sh, arm_x in stack_keys:
        _pose(pb["Pelvis"], f, loc=(0.0, pz, 0.0))
        _pose(pb["Spine"], f, rot_deg=(sp_x, 0.0, 0.0))
        _pose(pb["Thigh_L"], f, rot_deg=(th, 0.0, -10.0))
        _pose(pb["Thigh_R"], f, rot_deg=(th, 0.0, 10.0))
        _pose(pb["Shin_L"], f, rot_deg=(sh, 0.0, 0.0))
        _pose(pb["Shin_R"], f, rot_deg=(sh, 0.0, 0.0))
        _pose(pb["Arm_L"], f, rot_deg=(arm_x, -25.0, 0.0))
        _pose(pb["Arm_R"], f, rot_deg=(arm_x, 25.0, 0.0))
    _finalize_action(arm_obj, act, "stack_mount", 54, False)

    # 6. dive_bomb (48 frames, one-shot)
    act = create_action(arm_obj, "dive_bomb")
    dive_keys = [
        (0, 0.0, 0.0, 0.0, 0.0, 0.0),
        (12, 0.12, 35.0, -40.0, 85.0, -45.0),
        (26, 0.06, 75.0, -55.0, 95.0, -60.0),
        (38, -0.04, 85.0, -30.0, 60.0, -35.0),
        (48, 0.0, 20.0, -15.0, 30.0, -10.0),
    ]
    for f, pz, sp_x, th, sh, arm_x in dive_keys:
        _pose(pb["Pelvis"], f, loc=(0.0, pz, 0.0), rot_deg=(sp_x * 0.4, 0.0, 0.0))
        _pose(pb["Spine"], f, rot_deg=(sp_x * 0.6, 0.0, 0.0))
        _pose(pb["Head"], f, rot_deg=(-25.0, 0.0, 0.0))
        _pose(pb["Thigh_L"], f, rot_deg=(th, 0.0, 0.0))
        _pose(pb["Thigh_R"], f, rot_deg=(th, 0.0, 0.0))
        _pose(pb["Shin_L"], f, rot_deg=(sh, 0.0, 0.0))
        _pose(pb["Shin_R"], f, rot_deg=(sh, 0.0, 0.0))
        _pose(pb["Arm_L"], f, rot_deg=(arm_x, -22.0, 0.0))
        _pose(pb["Arm_R"], f, rot_deg=(arm_x, 22.0, 0.0))
    _finalize_action(arm_obj, act, "dive_bomb", 48, False)

    # 7. hit_react (30 frames, one-shot)
    act = create_action(arm_obj, "hit_react")
    for f, sp_x, sp_y, head_x, arm_x in [
        (0, 0.0, 0.0, 0.0, 0.0),
        (7, -24.0, 12.0, -18.0, 42.0),
        (16, -12.0, 6.0, -8.0, 22.0),
        (30, 0.0, 0.0, 0.0, 0.0),
    ]:
        _pose(pb["Pelvis"], f, loc=(0.0, -0.02 if f == 7 else 0.0, -0.03 if f == 7 else 0.0))
        _pose(pb["Spine"], f, rot_deg=(sp_x, sp_y, 0.0))
        _pose(pb["Head"], f, rot_deg=(head_x, -sp_y * 0.5, 0.0))
        _pose(pb["Arm_L"], f, rot_deg=(arm_x, -25.0, 0.0))
        _pose(pb["Arm_R"], f, rot_deg=(arm_x, 25.0, 0.0))
    _finalize_action(arm_obj, act, "hit_react", 30, False)

    # 8. death (66 frames, one-shot)
    act = create_action(arm_obj, "death")
    death_keys = [
        (0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0),
        (14, -0.06, -18.0, -25.0, 45.0, 35.0, -15.0),
        (32, -0.18, 30.0, -55.0, 95.0, -20.0, 25.0),
        (48, -0.28, 78.0, -20.0, 40.0, -45.0, 45.0),
        (66, -0.29, 86.0, -15.0, 30.0, -50.0, 50.0),
    ]
    for f, pz, pel_x, th, sh, arm_x, head_x in death_keys:
        _pose(pb["Pelvis"], f, loc=(0.0, pz, 0.0), rot_deg=(pel_x, 0.0, 0.0))
        _pose(pb["Spine"], f, rot_deg=(pel_x * 0.25, 0.0, 8.0 if f >= 32 else 0.0))
        _pose(pb["Head"], f, rot_deg=(head_x, 0.0, -12.0 if f >= 32 else 0.0))
        _pose(pb["Thigh_L"], f, rot_deg=(th, 0.0, -12.0))
        _pose(pb["Thigh_R"], f, rot_deg=(th, 0.0, 12.0))
        _pose(pb["Shin_L"], f, rot_deg=(sh, 0.0, 0.0))
        _pose(pb["Shin_R"], f, rot_deg=(sh, 0.0, 0.0))
        _pose(pb["Arm_L"], f, rot_deg=(arm_x, -38.0, 0.0))
        _pose(pb["Arm_R"], f, rot_deg=(arm_x, 38.0, 0.0))
    _finalize_action(arm_obj, act, "death", 66, False)

    bpy.ops.pose.transforms_clear()
    bpy.ops.object.mode_set(mode="OBJECT")


def main() -> None:
    clean_scene()
    sdk_root = Path(__file__).resolve().parents[2]
    out_dir = sdk_root / "assets" / "models" / "imp"

    imp_mesh, scale_factor = _build_imp_mesh(out_dir)
    arm_obj = _build_armature(imp_mesh, scale_factor=scale_factor)
    _bake_animations(arm_obj)

    export_godot_glb(
        filepath=out_dir / "imp_rigged.glb",
        export_animations=True,
        apply_modifiers=False,
        save_blend=False,
    )
    print("[rig_imp] Done: assets/models/imp/imp_rigged.glb")


if __name__ == "__main__":
    main()
