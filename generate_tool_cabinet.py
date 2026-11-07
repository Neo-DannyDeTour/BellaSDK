## Procedural Blender 4.x generator for the 2-tier asymmetric mechanic's tool cabinet.
## Run in Blender Scripting tab or headless: blender -b -P generate_tool_cabinet.py
import math
import bpy
import bmesh
from mathutils import Vector


COLLECTION_NAME: str = "Props"
OBJECT_NAME: str = "ToolCabinet"

# Overall dimensions (meters), origin at bottom-center (0, 0, 0), front = -Y
WIDTH: float = 1.10
DEPTH: float = 0.50
HEIGHT: float = 1.45


def get_or_create_material(
    name: str,
    base_color: tuple[float, float, float, float],
    metallic: float,
    roughness: float,
) -> bpy.types.Material:
    """Create or update a Principled BSDF material compatible with Blender 3.x/4.x."""
    mat: bpy.types.Material = bpy.data.materials.get(name) or bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    if bsdf is None:
        bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = base_color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def add_box(
    bm: bmesh.types.BMesh,
    min_pt: tuple[float, float, float],
    max_pt: tuple[float, float, float],
    mat_idx: int,
    cull_back: bool = False,
    cull_bottom: bool = False,
) -> None:
    """Append an axis-aligned box to BMesh with optional unseen-face culling."""
    x0, y0, z0 = min_pt
    x1, y1, z1 = max_pt

    v0 = bm.verts.new((x0, y0, z0))
    v1 = bm.verts.new((x1, y0, z0))
    v2 = bm.verts.new((x1, y1, z0))
    v3 = bm.verts.new((x0, y1, z0))
    v4 = bm.verts.new((x0, y0, z1))
    v5 = bm.verts.new((x1, y0, z1))
    v6 = bm.verts.new((x1, y1, z1))
    v7 = bm.verts.new((x0, y1, z1))

    # Winding order produces outward normals
    face_loops: list[tuple[bmesh.types.BMVert, ...]] = [
        (v0, v1, v5, v4),  # Front (-Y)
        (v1, v2, v6, v5),  # Right (+X)
        (v3, v0, v4, v7),  # Left (-X)
        (v4, v5, v6, v7),  # Top (+Z)
    ]
    if not cull_back:
        face_loops.append((v2, v3, v7, v6))  # Back (+Y)
    if not cull_bottom:
        face_loops.append((v3, v2, v1, v0))  # Bottom (-Z)

    for loop in face_loops:
        f = bm.faces.new(loop)
        f.material_index = mat_idx


def add_lock_cylinder(
    bm: bmesh.types.BMesh,
    center_xz: tuple[float, float],
    y_surface: float,
    radius: float = 0.0085,
    protrusion: float = 0.004,
    segments: int = 10,
    mat_idx: int = 2,
) -> None:
    """Append a forward-facing (-Y) polygonal lock cylinder with recessed keyhole slot."""
    cx, cz = center_xz
    y_back = y_surface
    y_front = y_surface - protrusion

    front_ring: list[bmesh.types.BMVert] = []
    back_ring: list[bmesh.types.BMVert] = []

    for i in range(segments):
        angle = (2.0 * math.pi * i) / segments
        px = cx + math.cos(angle) * radius
        pz = cz + math.sin(angle) * radius
        front_ring.append(bm.verts.new((px, y_front, pz)))
        back_ring.append(bm.verts.new((px, y_back, pz)))

    for i in range(segments):
        nxt = (i + 1) % segments
        f_side = bm.faces.new((front_ring[i], front_ring[nxt], back_ring[nxt], back_ring[i]))
        f_side.material_index = mat_idx

    f_cap = bm.faces.new(front_ring)
    f_cap.material_index = mat_idx

    # Dark keyhole slit on cylinder face
    add_box(
        bm,
        (cx - 0.0015, y_front - 0.001, cz - 0.0045),
        (cx + 0.0015, y_front, cz + 0.0045),
        mat_idx=1,
        cull_back=True,
    )


def add_drawer_column(
    bm: bmesh.types.BMesh,
    x0: float,
    x1: float,
    z_bottom: float,
    z_top: float,
    y_frame: float,
    weights: list[float],
    pull_types: list[str],
    lock_on_first: bool = False,
) -> None:
    """Populate a vertical recess with drawers, recessed cavities, and extruded silver pulls."""
    # Dark interior backing plate so gaps read as deep shadow
    y_cavity = y_frame + 0.016
    add_box(bm, (x0, y_cavity, z_bottom), (x1, y_cavity + 0.004, z_top), mat_idx=1, cull_back=True)

    gap_x = 0.004
    gap_z = 0.005
    total_h = z_top - z_bottom
    weight_sum = sum(weights)

    cur_z = z_top
    for idx, w in enumerate(weights):
        slot_h = total_h * (w / weight_sum)
        d_z1 = cur_z - gap_z
        d_z0 = cur_z - slot_h + gap_z
        cur_z -= slot_h

        dx0 = x0 + gap_x
        dx1 = x1 - gap_x
        y_drawer_front = y_frame + 0.006

        # Dark charcoal drawer body
        add_box(
            bm,
            (dx0, y_drawer_front, d_z0),
            (dx1, y_cavity, d_z1),
            mat_idx=1,
            cull_back=True,
        )

        # Extruded top-lip aluminum pull handle
        pull_h = 0.015
        pz1 = d_z1 - 0.002
        pz0 = pz1 - pull_h
        y_pull_front = y_frame - 0.006

        add_box(
            bm,
            (dx0 + 0.002, y_pull_front, pz0),
            (dx1 - 0.002, y_drawer_front, pz1),
            mat_idx=2,
            cull_back=True,
        )

        # Recessed dark grip strip along pull face
        if pull_types[idx] == "grooved":
            add_box(
                bm,
                (dx0 + 0.006, y_pull_front - 0.001, pz0 + 0.004),
                (dx1 - 0.006, y_pull_front + 0.002, pz1 - 0.004),
                mat_idx=1,
                cull_back=True,
            )

        # Optional cylinder lock below the top pull (upper-right drawer #1)
        if lock_on_first and idx == 0:
            add_lock_cylinder(
                bm,
                center_xz=((dx0 + dx1) * 0.5, pz0 - 0.014),
                y_surface=y_drawer_front,
            )


def apply_box_uvs(bm: bmesh.types.BMesh, scale: float = 1.0) -> None:
    """Assign world-space triplanar box UVs to all faces for seamless tiling/baking."""
    uv_layer = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co = loop.vert.co * scale
            if ax >= ay and ax >= az:
                loop[uv_layer].uv = (co.y, co.z)
            elif ay >= ax and ay >= az:
                loop[uv_layer].uv = (co.x, co.z)
            else:
                loop[uv_layer].uv = (co.x, co.y)


def build_tool_cabinet() -> bpy.types.Object:
    """Construct the complete tool cabinet mesh, assign materials, and link to scene."""
    mats: list[bpy.types.Material] = [
        get_or_create_material("Mat_Cabinet_Red", (0.42, 0.035, 0.03, 1.0), 0.25, 0.45),
        get_or_create_material("Mat_Drawer_Charcoal", (0.055, 0.07, 0.06, 1.0), 0.35, 0.55),
        get_or_create_material("Mat_Trim_Silver", (0.62, 0.65, 0.63, 1.0), 0.88, 0.32),
        get_or_create_material("Mat_Badge_Green", (0.08, 0.28, 0.18, 1.0), 0.20, 0.50),
        get_or_create_material("Mat_Badge_Gold", (0.55, 0.26, 0.04, 1.0), 0.40, 0.45),
    ]

    bm = bmesh.new()

    x_left = -WIDTH * 0.5        # -0.55
    x_right = WIDTH * 0.5        # +0.55
    y_front = -DEPTH * 0.5       # -0.25
    y_back = DEPTH * 0.5         # +0.25

    stile_w = 0.040
    mullion_w = 0.035
    col_l_x0 = x_left + stile_w           # -0.510
    col_l_x1 = 0.130                      # +0.130 (64cm wide left bay)
    col_r_x0 = col_l_x1 + mullion_w       # +0.165
    col_r_x1 = x_right - stile_w          # +0.510 (34.5cm wide right bay)

    # 1. Recessed dark kick-plate base (Z: 0.00 -> 0.02)
    add_box(
        bm,
        (x_left + 0.015, y_front + 0.015, 0.00),
        (x_right - 0.015, y_back - 0.015, 0.02),
        mat_idx=1,
        cull_bottom=False,
    )

    # 2. Lower cabinet structural frame (Z: 0.02 -> 0.86)
    z_low_bot = 0.02
    z_low_cav_bot = 0.055
    z_low_cav_top = 0.805
    z_mid_split = 0.860

    # Bottom rail, mid-divider rail, back core, left/right stiles, center mullion
    add_box(bm, (x_left, y_front, z_low_bot), (x_right, y_back, z_low_cav_bot), mat_idx=0)
    add_box(bm, (x_left, y_front, z_low_cav_top), (x_right, y_back, z_mid_split), mat_idx=0, cull_bottom=True)
    add_box(bm, (x_left, y_front + 0.022, z_low_cav_bot), (x_right, y_back, z_low_cav_top), mat_idx=0, cull_bottom=True)
    add_box(bm, (x_left, y_front, z_low_cav_bot), (col_l_x0, y_front + 0.022, z_low_cav_top), mat_idx=0, cull_back=True)
    add_box(bm, (col_l_x1, y_front, z_low_cav_bot), (col_r_x0, y_front + 0.022, z_low_cav_top), mat_idx=0, cull_back=True)
    add_box(bm, (col_r_x1, y_front, z_low_cav_bot), (x_right, y_front + 0.022, z_low_cav_top), mat_idx=0, cull_back=True)

    # 3. Upper chest structural frame (Z: 0.86 -> 1.45), stepped back 4mm on front
    y_up_front = y_front + 0.004
    z_up_cav_bot = 0.895
    z_up_cav_top = 1.330
    z_up_lip = 1.430

    add_box(bm, (x_left, y_up_front, z_mid_split), (x_right, y_back, z_up_cav_bot), mat_idx=0, cull_bottom=True)
    add_box(bm, (x_left, y_up_front, z_up_cav_top), (x_right, y_back, z_up_lip), mat_idx=0, cull_bottom=True)
    # Top overhanging lid rim
    add_box(bm, (x_left - 0.003, y_front - 0.002, z_up_lip), (x_right + 0.003, y_back + 0.002, HEIGHT), mat_idx=0)
    add_box(bm, (x_left, y_up_front + 0.022, z_up_cav_bot), (x_right, y_back, z_up_cav_top), mat_idx=0, cull_bottom=True)
    add_box(bm, (x_left, y_up_front, z_up_cav_bot), (col_l_x0, y_up_front + 0.022, z_up_cav_top), mat_idx=0, cull_back=True)
    add_box(bm, (col_l_x1, y_up_front, z_up_cav_bot), (col_r_x0, y_up_front + 0.022, z_up_cav_top), mat_idx=0, cull_back=True)
    add_box(bm, (col_r_x1, y_up_front, z_up_cav_bot), (x_right, y_up_front + 0.022, z_up_cav_top), mat_idx=0, cull_back=True)

    # 4. Populate 4 Drawer Bays
    # Upper Left: 5 equal shallow drawers
    add_drawer_column(
        bm, col_l_x0, col_l_x1, z_up_cav_bot, z_up_cav_top, y_up_front,
        weights=[1.0, 1.0, 1.0, 1.0, 1.0],
        pull_types=["grooved"] * 5,
    )
    # Upper Right: 3 graduated drawers + lock on top-right drawer
    add_drawer_column(
        bm, col_r_x0, col_r_x1, z_up_cav_bot, z_up_cav_top, y_up_front,
        weights=[1.0, 1.35, 1.65],
        pull_types=["grooved"] * 3,
        lock_on_first=True,
    )
    # Lower Left: 7 drawers (4 shallow, 2 medium, 1 deep bottom)
    add_drawer_column(
        bm, col_l_x0, col_l_x1, z_low_cav_bot, z_low_cav_top, y_front,
        weights=[1.0, 1.0, 1.0, 1.0, 1.35, 1.35, 1.85],
        pull_types=["grooved"] * 7,
    )
    # Lower Right: 5 shallow drawers + 1 tall bottom compartment door
    add_drawer_column(
        bm, col_r_x0, col_r_x1, z_low_cav_bot, z_low_cav_top, y_front,
        weights=[1.0, 1.0, 1.0, 1.0, 1.0, 3.55],
        pull_types=["grooved"] * 6,
    )

    # 5. Header & Mid-Rail Badges + Keyhole Locks
    # Upper header badges (left green nameplate, middle gold warning plate, right gold plate)
    add_box(bm, (-0.495, y_up_front - 0.003, 1.355), (-0.310, y_up_front, 1.392), mat_idx=3, cull_back=True)
    add_box(bm, (-0.490, y_up_front - 0.004, 1.362), (-0.315, y_up_front - 0.003, 1.372), mat_idx=2, cull_back=True)
    add_box(bm, (-0.270, y_up_front - 0.003, 1.355), (-0.060, y_up_front, 1.395), mat_idx=4, cull_back=True)
    add_box(bm, (0.095, y_up_front - 0.003, 1.358), (0.225, y_up_front, 1.390), mat_idx=4, cull_back=True)
    add_lock_cylinder(bm, center_xz=(0.015, 1.398), y_surface=y_up_front)

    # Mid-rail left badge & center lock
    add_box(bm, (-0.490, y_front - 0.003, 0.822), (-0.320, y_front, 0.852), mat_idx=3, cull_back=True)
    add_box(bm, (-0.485, y_front - 0.004, 0.828), (-0.325, y_front - 0.003, 0.838), mat_idx=4, cull_back=True)
    add_lock_cylinder(bm, center_xz=(-0.015, 0.840), y_surface=y_front)

    # Finalize BMesh -> Mesh
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    apply_box_uvs(bm, scale=1.0)

    mesh_data = bpy.data.meshes.new(f"{OBJECT_NAME}_Mesh")
    bm.to_mesh(mesh_data)
    bm.free()

    for mat in mats:
        mesh_data.materials.append(mat)

    # Replace existing object if re-running script
    old_obj = bpy.data.objects.get(OBJECT_NAME)
    if old_obj is not None:
        bpy.data.objects.remove(old_obj, do_unlink=True)

    obj = bpy.data.objects.new(OBJECT_NAME, mesh_data)

    # Link to target collection
    col = bpy.data.collections.get(COLLECTION_NAME)
    if col is None:
        col = bpy.data.collections.new(COLLECTION_NAME)
        bpy.context.scene.collection.children.link(col)
    col.objects.link(obj)

    # Non-destructive 1-segment bevel for specular edge catch
    bevel = obj.modifiers.new(name="EdgeBevel", type="BEVEL")
    bevel.width = 0.0018
    bevel.segments = 1
    bevel.limit_method = "ANGLE"
    bevel.angle_limit = math.radians(35.0)
    bevel.harden_normals = True

    print(f"[ToolCabinet] Generated '{OBJECT_NAME}' ({len(mesh_data.polygons)} tris/quads).")
    return obj


if __name__ == "__main__":
    build_tool_cabinet()
