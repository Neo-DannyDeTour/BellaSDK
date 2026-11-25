import os
import math
import bpy
import bmesh

OUTPUT_PATH = "assets/models/props/tombstone/tombstone.glb"


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def arch_profile(arch_steps: int = 12) -> list[tuple[float, float]]:
    """Returns 2D (x, z) profile of the main headstone body (CCW order)."""
    half_w = 0.31
    shoulder_z = 0.90
    arch_start_x = 0.28
    arch_start_z = 0.94
    apex_z = 1.40

    pts_right: list[tuple[float, float]] = [
        (half_w, 0.22),
        (half_w, shoulder_z),
        (arch_start_x, arch_start_z),
    ]

    for i in range(1, arch_steps + 1):
        t = i / arch_steps
        x = arch_start_x * (1.0 - math.pow(t, 1.35))
        z = arch_start_z + (apex_z - arch_start_z) * math.sin(t * math.pi * 0.5)
        pts_right.append((x, z))

    pts_left: list[tuple[float, float]] = [
        (-x, z) for (x, z) in reversed(pts_right[:-1])
    ]
    return pts_right + pts_left


def add_box_tier(
    bm: bmesh.types.BMesh,
    w: float,
    d: float,
    z0: float,
    z1: float,
    bevel_top: float = 0.0,
) -> None:
    hw, hd = w * 0.5, d * 0.5
    hw_top = hw - bevel_top
    hd_top = hd - bevel_top

    v0 = bm.verts.new((-hw, -hd, z0))
    v1 = bm.verts.new((hw, -hd, z0))
    v2 = bm.verts.new((hw, hd, z0))
    v3 = bm.verts.new((-hw, hd, z0))

    v4 = bm.verts.new((-hw_top, -hd_top, z1))
    v5 = bm.verts.new((hw_top, -hd_top, z1))
    v6 = bm.verts.new((hw_top, hd_top, z1))
    v7 = bm.verts.new((-hw_top, hd_top, z1))

    bm.faces.new((v0, v3, v2, v1))  # Bottom
    bm.faces.new((v4, v5, v6, v7))  # Top
    bm.faces.new((v0, v1, v5, v4))  # Front (-Y)
    bm.faces.new((v1, v2, v6, v5))  # Right (+X)
    bm.faces.new((v2, v3, v7, v6))  # Back (+Y)
    bm.faces.new((v3, v0, v4, v7))  # Left (-X)


def build_tombstone_mesh() -> bpy.types.Object:
    bm = bmesh.new()

    # Tier 1: Bottom plinth (0.80m x 0.25m, z: 0.00 -> 0.12)
    add_box_tier(bm, 0.80, 0.25, 0.00, 0.12, bevel_top=0.01)

    # Tier 2: Upper plinth step (0.72m x 0.20m, z: 0.12 -> 0.22)
    add_box_tier(bm, 0.72, 0.20, 0.12, 0.22, bevel_top=0.015)

    # Tier 3: Main arched slab (depth 0.14m -> y in [-0.07, 0.07])
    profile = arch_profile(arch_steps=12)
    hy = 0.07
    front_verts = [bm.verts.new((x, -hy, z)) for (x, z) in profile]
    back_verts = [bm.verts.new((x, hy, z)) for (x, z) in profile]

    n = len(profile)
    for i in range(n):
        nxt = (i + 1) % n
        bm.faces.new((front_verts[i], front_verts[nxt], back_verts[nxt], back_verts[i]))

    bm.faces.new(tuple(reversed(back_verts)))
    front_face = bm.faces.new(tuple(front_verts))

    # Inset front face to create raised outer border (thickness 0.035m, depth 0.018m)
    bmesh.ops.inset_individual(
        bm,
        faces=[front_face],
        thickness=0.035,
        depth=-0.018,
        use_even_offset=True,
    )
    recessed_face = front_face

    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()

    # Vertex Color Layer ("Col") & UV Layer ("UVMap")
    col_layer = bm.loops.layers.color.new("Col")
    uv_layer = bm.loops.layers.uv.new("UVMap")

    # Bounding box of recessed face for normalized [0, 1] UV mapping
    r_xs = [v.co.x for v in recessed_face.verts]
    r_zs = [v.co.z for v in recessed_face.verts]
    min_x, max_x = min(r_xs), max(r_xs)
    min_z, max_z = min(r_zs), max(r_zs)
    span_x = max(max_x - min_x, 0.001)
    span_z = max(max_z - min_z, 0.001)

    for face in bm.faces:
        is_recessed = face == recessed_face
        nrm = face.normal
        for loop in face.loops:
            co = loop.vert.co
            if is_recessed:
                loop[col_layer] = (1.0, (co.z / 1.40), 0.0, 1.0)
                u = (co.x - min_x) / span_x
                v = (co.z - min_z) / span_z
                loop[uv_layer].uv = (u, v)
            else:
                loop[col_layer] = (0.0, (co.z / 1.40), 0.0, 1.0)
                if abs(nrm.y) > 0.5:
                    loop[uv_layer].uv = (co.x + 0.5, co.z / 1.40)
                elif abs(nrm.x) > 0.5:
                    loop[uv_layer].uv = (co.y + 0.5, co.z / 1.40)
                else:
                    loop[uv_layer].uv = (co.x + 0.5, co.y + 0.5)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("TombstoneMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("TombstoneMesh", mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def main() -> None:
    clear_scene()
    build_tombstone_mesh()

    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_PATH,
        export_format="GLB",
        export_apply=True,
        export_yup=True,
        export_vertex_color="ACTIVE",
        export_texcoords=True,
        export_normals=True,
    )
    print(f"Exported: {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
