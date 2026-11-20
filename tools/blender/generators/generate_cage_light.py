"""Procedural bulkhead cage light generator for BellaSDK."""

import math
import os
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector


def clear_scene() -> None:
    """Reset Blender scene to empty factory state."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def create_material(
    name: str,
    base_color: tuple,
    metallic: float,
    roughness: float,
    emission: tuple = (0.0, 0.0, 0.0),
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    """Create a Principled BSDF material with optional emission."""
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = base_color
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
            bsdf.inputs["Emission Strength"].default_value = emission_strength
        elif "Emission" in bsdf.inputs:
            bsdf.inputs["Emission"].default_value = (*emission, 1.0)
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def add_oval_ring(
    bm: bmesh.types.BMesh,
    rx: float,
    ry: float,
    z0: float,
    z1: float,
    thickness: float,
    segs: int,
    mat_idx: int,
) -> None:
    """Add an extruded oval baseplate ring with mounting lug protrusions."""
    verts_inner_0 = []
    verts_outer_0 = []
    verts_inner_1 = []
    verts_outer_1 = []

    for i in range(segs):
        angle = (2.0 * math.pi * i) / segs
        ca = math.cos(angle)
        sa = math.sin(angle)
        # Apply slight mounting lug protrusions at 4 corner angles
        lug = 0.0
        for lug_angle in (0.35, math.pi - 0.35, -0.35, -math.pi + 0.35):
            if abs(math.atan2(sa, ca) - lug_angle) < 0.22:
                lug = 0.012

        v_i0 = bm.verts.new((ca * (rx - thickness), z0, sa * (ry - thickness)))
        v_o0 = bm.verts.new((ca * (rx + lug), z0, sa * (ry + lug * 0.6)))
        v_i1 = bm.verts.new((ca * (rx - thickness), z1, sa * (ry - thickness)))
        v_o1 = bm.verts.new((ca * (rx + lug * 0.5), z1, sa * (ry + lug * 0.3)))

        verts_inner_0.append(v_i0)
        verts_outer_0.append(v_o0)
        verts_inner_1.append(v_i1)
        verts_outer_1.append(v_o1)

    for i in range(segs):
        nxt = (i + 1) % segs
        faces = [
            bm.faces.new(
                (verts_inner_1[i], verts_outer_1[i], verts_outer_1[nxt], verts_inner_1[nxt])
            ),
            bm.faces.new(
                (verts_outer_0[i], verts_inner_0[i], verts_inner_0[nxt], verts_outer_0[nxt])
            ),
            bm.faces.new(
                (verts_outer_0[i], verts_outer_0[nxt], verts_outer_1[nxt], verts_outer_1[i])
            ),
            bm.faces.new(
                (verts_inner_1[i], verts_inner_1[nxt], verts_inner_0[nxt], verts_inner_0[i])
            ),
        ]
        for f in faces:
            f.material_index = mat_idx
            f.smooth = False


def add_profile_swept_bar(
    bm: bmesh.types.BMesh,
    path_pts: list,
    bar_w: float,
    bar_d: float,
    mat_idx: int,
) -> None:
    """Sweep a rectangular bar profile along a 3D point list."""
    rings = []
    count = len(path_pts)
    for i, pt in enumerate(path_pts):
        if i == 0:
            tangent = (path_pts[i + 1] - pt).normalized()
        elif i == count - 1:
            tangent = (pt - path_pts[i - 1]).normalized()
        else:
            tangent = (path_pts[i + 1] - path_pts[i - 1]).normalized()

        normal = Vector((pt.x * 1.2, max(pt.y, 0.001), pt.z * 0.7)).normalized()
        binormal = tangent.cross(normal).normalized()
        normal = binormal.cross(tangent).normalized()

        hw = bar_w * 0.5
        hd = bar_d * 0.5
        c0 = pt - binormal * hw - normal * hd
        c1 = pt + binormal * hw - normal * hd
        c2 = pt + binormal * hw + normal * hd
        c3 = pt - binormal * hw + normal * hd
        rings.append([bm.verts.new(c0), bm.verts.new(c1), bm.verts.new(c2), bm.verts.new(c3)])

    for i in range(count - 1):
        r0 = rings[i]
        r1 = rings[i + 1]
        for j in range(4):
            jn = (j + 1) % 4
            f = bm.faces.new((r0[j], r0[jn], r1[jn], r1[j]))
            f.material_index = mat_idx
            f.smooth = False

    for cap_ring, flip in ((rings[0], True), (rings[-1], False)):
        verts = list(reversed(cap_ring)) if flip else cap_ring
        f = bm.faces.new(verts)
        f.material_index = mat_idx
        f.smooth = False


def add_glass_dome(
    bm: bmesh.types.BMesh,
    rx: float,
    ry: float,
    rz: float,
    z_offset: float,
    u_segs: int,
    v_segs: int,
    mat_idx: int,
) -> None:
    """Add a smooth ellipsoidal glass bulb dome."""
    rings = []
    for v in range(v_segs):
        phi = (math.pi * 0.5 * v) / v_segs
        cp = math.cos(phi)
        sp = math.sin(phi)
        ring = []
        for u in range(u_segs):
            theta = (2.0 * math.pi * u) / u_segs
            x = math.cos(theta) * rx * cp
            z = math.sin(theta) * ry * cp
            y = z_offset + rz * sp
            ring.append(bm.verts.new((x, y, z)))
        rings.append(ring)

    tip = bm.verts.new((0.0, z_offset + rz, 0.0))

    for v in range(v_segs - 1):
        r0 = rings[v]
        r1 = rings[v + 1]
        for u in range(u_segs):
            un = (u + 1) % u_segs
            f = bm.faces.new((r0[u], r0[un], r1[un], r1[u]))
            f.material_index = mat_idx
            f.smooth = True

    last_ring = rings[-1]
    for u in range(u_segs):
        un = (u + 1) % u_segs
        f = bm.faces.new((last_ring[u], last_ring[un], tip))
        f.material_index = mat_idx
        f.smooth = True


def build_cage_light() -> bpy.types.Object:
    """Build the bulkhead cage light mesh, materials, and Smart UV projection."""
    mesh = bpy.data.meshes.new("CageLightMesh")
    obj = bpy.data.objects.new("CageLight", mesh)
    bpy.context.collection.objects.link(obj)

    mat_metal = create_material(
        "Mat_Cage_Metal", (0.22, 0.20, 0.18, 1.0), metallic=0.85, roughness=0.65
    )
    mat_glass = create_material(
        "Mat_Bulb_Glass",
        (0.95, 0.78, 0.42, 1.0),
        metallic=0.0,
        roughness=0.35,
        emission=(1.0, 0.72, 0.28),
        emission_strength=2.5,
    )
    obj.data.materials.append(mat_metal)
    obj.data.materials.append(mat_glass)

    bm = bmesh.new()

    rx_base = 0.095
    ry_base = 0.175
    cage_depth = 0.125

    # 1. Baseplate oval ring (Mat 0)
    add_oval_ring(
        bm, rx=rx_base, ry=ry_base, z0=0.0, z1=0.018, thickness=0.022, segs=24, mat_idx=0
    )

    # 2. Central vertical rib (Mat 0)
    v_pts = []
    steps = 14
    for i in range(steps + 1):
        t = -math.pi * 0.5 + (math.pi * i) / steps
        ct = math.cos(t)
        st = math.sin(t)
        y_protrude = 0.012 + cage_depth * (abs(ct) ** 0.75)
        z_height = (ry_base - 0.008) * math.copysign(abs(st) ** 0.85, st)
        v_pts.append(Vector((0.0, y_protrude, z_height)))
    add_profile_swept_bar(bm, v_pts, bar_w=0.016, bar_d=0.012, mat_idx=0)

    # 3. Three horizontal ribs (Mat 0)
    for z_frac in (-0.48, 0.0, 0.48):
        z_pos = z_frac * ry_base
        norm_z = abs(z_pos) / ry_base
        local_rx = (rx_base - 0.006) * math.sqrt(max(0.0, 1.0 - norm_z * norm_z))
        local_depth = 0.012 + cage_depth * ((1.0 - norm_z * norm_z) ** 0.42)

        h_pts = []
        h_steps = 12
        for i in range(h_steps + 1):
            t = -math.pi * 0.5 + (math.pi * i) / h_steps
            st = math.sin(t)
            ct = math.cos(t)
            x = local_rx * math.copysign(abs(st) ** 0.85, st)
            y = 0.010 + (local_depth - 0.010) * (abs(ct) ** 0.75)
            h_pts.append(Vector((x, y, z_pos)))
        add_profile_swept_bar(bm, h_pts, bar_w=0.015, bar_d=0.012, mat_idx=0)

    # 4. Inner Glass Bulb Dome (Mat 1)
    add_glass_dome(
        bm,
        rx=rx_base - 0.018,
        ry=ry_base - 0.018,
        rz=cage_depth - 0.018,
        z_offset=0.012,
        u_segs=20,
        v_segs=8,
        mat_idx=1,
    )

    # Rotate so +Y in Blender becomes -Y (exports as +Z forward in glTF / Godot)
    bmesh.ops.rotate(
        bm, verts=bm.verts, cent=(0.0, 0.0, 0.0), matrix=Matrix.Rotation(math.pi, 3, "Z")
    )
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    bm.to_mesh(mesh)
    bm.free()

    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")

    return obj


if __name__ == "__main__":
    clear_scene()
    build_cage_light()
    repo_root = Path(__file__).resolve().parents[3]
    out_dir = repo_root / "assets" / "models" / "props" / "cage_light"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = str(out_dir / "cage_light.glb")
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print(f"Exported: {out_path}")
