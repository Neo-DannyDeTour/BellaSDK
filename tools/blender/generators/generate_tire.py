import bpy
import bmesh
import math
import os
import sys


def get_output_path() -> str:
    argv = sys.argv
    if "--" in argv:
        args = argv[argv.index("--") + 1:]
        if args:
            return os.path.abspath(args[0])
    return os.path.abspath("./tire_carcass.glb")


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def generate_tire_textures(size: int = 1024) -> tuple:
    albedo_img = bpy.data.images.new("Tire_Albedo", width=size, height=size, alpha=False)
    normal_img = bpy.data.images.new("Tire_Normal", width=size, height=size, alpha=False)
    normal_img.colorspace_settings.name = "Non-Color"
    rough_img = bpy.data.images.new("Tire_Roughness", width=size, height=size, alpha=False)
    rough_img.colorspace_settings.name = "Non-Color"

    albedo_px = [0.0] * (size * size * 4)
    normal_px = [0.0] * (size * size * 4)
    rough_px = [0.0] * (size * size * 4)

    height_grid = [0.0] * (size * size)
    blocks = 28.0

    for y in range(size):
        v = y / float(size)
        in_tread = 0.24 <= v <= 0.76
        v_tread = (v - 0.24) / 0.52 if in_tread else 0.0

        for x in range(size):
            u = x / float(size)
            idx = y * size + x

            # Pseudo-noise for dirt and rubber grain
            n1 = math.sin(u * 37.0 * math.tau + math.cos(v * 29.0 * math.tau))
            n2 = math.cos(u * 113.0 * math.tau - math.sin(v * 97.0 * math.tau))
            grunge = (n1 * 0.6 + n2 * 0.4) * 0.5 + 0.5

            h = 0.0
            if in_tread:
                d_center = abs(v_tread - 0.5)
                # 3 circumferential main grooves
                g_center = max(0.0, 1.0 - d_center / 0.032)
                g_side = max(0.0, 1.0 - abs(d_center - 0.22) / 0.028)
                groove = max(g_center, g_side)

                # Asymmetric chevron lug slits
                sign = 1.0 if v_tread > 0.5 else -1.0
                phase = (u * blocks + sign * d_center * 2.2) % 1.0
                lug_gap = max(0.0, 1.0 - abs(phase - 0.5) / 0.09)

                # Shoulder notches
                shoulder_mask = max(0.0, (d_center - 0.32) / 0.18)
                phase_sh = (u * (blocks * 0.5)) % 1.0
                sh_gap = max(0.0, 1.0 - abs(phase_sh - 0.5) / 0.14) * shoulder_mask

                cut = max(groove, lug_gap * 0.85, sh_gap * 0.9)
                h = (1.0 - cut) * 1.0 + grunge * 0.08
            else:
                # Sidewall scuff rings & inner cavity smooth falloff
                outer_wall = (0.14 <= v < 0.24) or (0.76 < v <= 0.86)
                if outer_wall:
                    rib = 0.12 * math.sin(v * 180.0 * math.tau)
                    h = 0.25 + rib + grunge * 0.06
                else:
                    h = 0.1 + grunge * 0.03

            height_grid[idx] = h

            # Albedo & Roughness
            # Dark cavity inside (v < 0.12 or v > 0.88), dusty mud in tread grooves & sidewalls
            cavity_ao = 1.0
            if v < 0.14:
                cavity_ao = max(0.25, v / 0.14)
            elif v > 0.86:
                cavity_ao = max(0.25, (1.0 - v) / 0.14)

            dirt_mask = max(0.0, (1.0 - h) * 0.55 + grunge * 0.35 - 0.25) * cavity_ao
            base_r = (0.11 + dirt_mask * 0.14) * cavity_ao
            base_g = (0.11 + dirt_mask * 0.12) * cavity_ao
            base_b = (0.10 + dirt_mask * 0.08) * cavity_ao

            p4 = idx * 4
            albedo_px[p4] = base_r
            albedo_px[p4 + 1] = base_g
            albedo_px[p4 + 2] = base_b
            albedo_px[p4 + 3] = 1.0

            rough_val = min(0.96, max(0.62, 0.74 + dirt_mask * 0.22 - h * 0.08))
            rough_px[p4] = rough_val
            rough_px[p4 + 1] = rough_val
            rough_px[p4 + 2] = rough_val
            rough_px[p4 + 3] = 1.0

    # Finite-difference tangent normal map from height_grid
    strength = 5.5
    for y in range(size):
        y_up = (y + 1) % size
        y_dn = (y - 1) % size
        for x in range(size):
            x_rt = (x + 1) % size
            x_lt = (x - 1) % size

            dx = (height_grid[y * size + x_rt] - height_grid[y * size + x_lt]) * strength
            dy = (height_grid[y_up * size + x] - height_grid[y_dn * size + x]) * strength
            dz = 1.0
            inv_len = 1.0 / math.sqrt(dx * dx + dy * dy + dz * dz)

            p4 = (y * size + x) * 4
            normal_px[p4] = (-dx * inv_len) * 0.5 + 0.5
            normal_px[p4 + 1] = (-dy * inv_len) * 0.5 + 0.5
            normal_px[p4 + 2] = (dz * inv_len) * 0.5 + 0.5
            normal_px[p4 + 3] = 1.0

    albedo_img.pixels.foreach_set(albedo_px)
    normal_img.pixels.foreach_set(normal_px)
    rough_img.pixels.foreach_set(rough_px)

    albedo_img.pack()
    normal_img.pack()
    rough_img.pack()
    return albedo_img, normal_img, rough_img


def build_material(albedo_img, normal_img, rough_img) -> bpy.types.Material:
    mat = bpy.data.materials.new(name="M_TireRubber")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out_node = nodes.new(type="ShaderNodeOutputMaterial")
    bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    bsdf.inputs["Metallic"].default_value = 0.0

    tex_albedo = nodes.new(type="ShaderNodeTexImage")
    tex_albedo.image = albedo_img

    tex_rough = nodes.new(type="ShaderNodeTexImage")
    tex_rough.image = rough_img

    tex_norm = nodes.new(type="ShaderNodeTexImage")
    tex_norm.image = normal_img

    norm_map = nodes.new(type="ShaderNodeNormalMap")
    norm_map.inputs["Strength"].default_value = 1.25

    links.new(tex_albedo.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(tex_rough.outputs["Color"], bsdf.inputs["Roughness"])
    links.new(tex_norm.outputs["Color"], norm_map.inputs["Color"])
    links.new(norm_map.outputs["Normal"], bsdf.inputs["Normal"])
    links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])

    return mat


def create_tire_mesh(mat: bpy.types.Material) -> bpy.types.Object:
    # Profile (r, z, v_coord) — Open C-carcass with inner cavity return lip
    # Outer radius = 0.325m (Ø 0.65m), Inner bead radius = 0.19m (Ø 0.38m), Width = 0.22m
    profile = [
        (0.225, -0.072, 0.00),  # 0: Bottom inner bead inside lip
        (0.190, -0.082, 0.07),  # 1: Bottom inner bead rim edge
        (0.245, -0.110, 0.15),  # 2: Bottom sidewall lower bulge
        (0.305, -0.102, 0.24),  # 3: Bottom shoulder corner
        (0.323, -0.068, 0.33),  # 4: Tread lower crown
        (0.326,  0.000, 0.50),  # 5: Tread center crown
        (0.323,  0.068, 0.67),  # 6: Tread upper crown
        (0.305,  0.102, 0.76),  # 7: Top shoulder corner
        (0.245,  0.110, 0.85),  # 8: Top sidewall upper bulge
        (0.190,  0.082, 0.93),  # 9: Top inner bead rim edge
        (0.225,  0.072, 1.00),  # 10: Top inner bead inside lip
        (0.292,  0.068, 0.94),  # 11: Inner cavity top wall
        (0.302,  0.000, 0.88),  # 12: Inner cavity center crown
        (0.292, -0.068, 0.06),  # 13: Inner cavity bottom wall
    ]

    radial_segs = 24
    prof_count = len(profile)

    mesh = bpy.data.meshes.new("TireCarcassMesh")
    obj = bpy.data.objects.new("TireCarcass", mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    # Create vertices with (radial_segs + 1) seam column for clean UVs, then weld or map per-loop
    rings = []
    for i in range(radial_segs):
        angle = (i / float(radial_segs)) * math.tau
        ca = math.cos(angle)
        sa = math.sin(angle)
        ring_verts = []
        for r, z, _ in profile:
            v = bm.verts.new((r * ca, r * sa, z))
            ring_verts.append(v)
        rings.append(ring_verts)

    bm.verts.ensure_lookup_table()

    # Connect quads around circumference and closed profile loop
    # UV v-coords wrap cleanly along outer tread (0..10) and inner cavity (10..0)
    v_coords_closed = [p[2] for p in profile] + [profile[0][2]]

    for i in range(radial_segs):
        i_next = (i + 1) % radial_segs
        u0 = i / float(radial_segs)
        u1 = (i + 1) / float(radial_segs)

        for j in range(prof_count):
            j_next = (j + 1) % prof_count
            v00 = rings[i][j]
            v10 = rings[i_next][j]
            v11 = rings[i_next][j_next]
            v01 = rings[i][j_next]

            face = bm.faces.new((v00, v10, v11, v01))
            face.smooth = True

            # Assign continuous cylindrical UVs
            v_curr = profile[j][2]
            v_nxt = v_coords_closed[j + 1]
            face.loops[0][uv_layer].uv = (u0, v_curr)
            face.loops[1][uv_layer].uv = (u1, v_curr)
            face.loops[2][uv_layer].uv = (u1, v_nxt)
            face.loops[3][uv_layer].uv = (u0, v_nxt)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    # Harden bead rim edges for crisp silhouette while keeping tread/sidewall smooth
    mesh.data.materials.append(mat) if hasattr(mesh, "data") else mesh.materials.append(mat)
    return obj


def main() -> None:
    out_path = get_output_path()
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    clear_scene()
    albedo_img, normal_img, rough_img = generate_tire_textures(size=512)
    mat = build_material(albedo_img, normal_img, rough_img)
    create_tire_mesh(mat)

    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_yup=True,
    )
    print(f"Exported hollow tire carcass to: {out_path}")


if __name__ == "__main__":
    main()
