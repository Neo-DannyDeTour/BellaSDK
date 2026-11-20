import math
import os
import bmesh
import bpy
import mathutils


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def create_procedural_material():
    mat = bpy.data.materials.new(name="WasherMat")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    # 512x512 procedural retro texture (aged cream enamel + dark console + dial + drum)
    img_size = 512
    img = bpy.data.images.new("WasherTex", width=img_size, height=img_size)
    pixels = [0.0] * (img_size * img_size * 4)

    for y in range(img_size):
        for x in range(img_size):
            idx = (y * img_size + x) * 4
            grime = ((x * 37 ^ y * 13) % 100) / 1500.0
            edge_dist = min(x, y, img_size - 1 - x, img_size - 1 - y) / 40.0
            vignette = min(1.0, edge_dist) * 0.15 + 0.85

            if y > int(img_size * 0.75):
                # Dark control console trim
                r, g, b = 0.12 - grime, 0.11 - grime, 0.10 - grime
                if (
                    int(img_size * 0.1) < x < int(img_size * 0.85)
                    and int(img_size * 0.80) < y < int(img_size * 0.94)
                ):
                    if x > int(img_size * 0.68):
                        r, g, b = 0.65, 0.64, 0.60
                    else:
                        r, g, b = 0.22, 0.15, 0.14
                        if abs(y - int(img_size * 0.87)) < 3:
                            r, g, b = 0.75, 0.72, 0.65
            elif y < int(img_size * 0.15):
                # Dark interior steel drum / dial accent
                r, g, b = 0.18 - grime * 0.5, 0.19 - grime * 0.5, 0.20 - grime * 0.5
            else:
                # Aged yellowish-cream enamel body
                r = (0.78 - grime) * vignette
                g = (0.75 - grime) * vignette
                b = (0.60 - grime) * vignette

            pixels[idx] = max(0.0, min(1.0, r))
            pixels[idx + 1] = max(0.0, min(1.0, g))
            pixels[idx + 2] = max(0.0, min(1.0, b))
            pixels[idx + 3] = 1.0

    img.pixels = pixels
    img.pack()

    bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.58
    bsdf.inputs["Metallic"].default_value = 0.18

    tex_node = nodes.new(type="ShaderNodeTexImage")
    tex_node.image = img

    out_node = nodes.new(type="ShaderNodeOutputMaterial")
    links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])
    return mat


def map_uv_box(obj, uv_bounds):
    u_min, v_min, u_max, v_max = uv_bounds
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv_layer = mesh.uv_layers.active.data
    for poly in mesh.polygons:
        for loop_idx in poly.loop_indices:
            uv = uv_layer[loop_idx].uv
            uv[0] = u_min + (uv[0] % 1.0) * (u_max - u_min)
            uv[1] = v_min + (uv[1] % 1.0) * (v_max - v_min)


def set_smooth_shading(obj):
    for poly in obj.data.polygons:
        poly.use_smooth = True


def math_rot_x(angle):
    return mathutils.Matrix.Rotation(angle, 3, "X")


def create_obj_from_bm(name, bm, mat, uv_bounds):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + "Mesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    map_uv_box(obj, uv_bounds)
    set_smooth_shading(obj)
    return obj


def build_washer_body(mat):
    # Main cabinet: 0.68m W (X), 0.70m D (Y in Blender), 0.85m H (Z in Blender)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(0.68, 0.70, 0.85), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(0.0, 0.0, 0.425), verts=bm.verts)

    # Inset top face and extrude recessed cavity
    bm.faces.ensure_lookup_table()
    top_face = max(bm.faces, key=lambda f: f.calc_center_median().z)
    bmesh.ops.inset_individual(bm, faces=[top_face], thickness=0.10, depth=0.0)
    ext = bmesh.ops.extrude_face_region(bm, geom=[top_face])
    ext_verts = [v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0.0, 0.0, -0.50), verts=ext_verts)

    # Mid-poly bevel on cabinet edges for crisp specular highlights
    bmesh.ops.bevel(
        bm,
        geom=list(bm.edges),
        offset=0.015,
        segments=3,
        affect="EDGES",
        clamp_overlap=True,
    )
    body_obj = create_obj_from_bm("WasherBody", bm, mat, (0.05, 0.20, 0.95, 0.70))

    # Cylindrical inner wash drum + central agitator post (mid-poly detail)
    drum_bm = bmesh.new()
    bmesh.ops.create_cone(
        drum_bm,
        cap_ends=True,
        cap_tris=False,
        segments=28,
        radius1=0.21,
        radius2=0.22,
        depth=0.46,
    )
    bmesh.ops.translate(drum_bm, vec=(0.0, -0.02, 0.59), verts=drum_bm.verts)
    # Hollow out top of drum cylinder
    drum_bm.faces.ensure_lookup_table()
    drum_top = max(drum_bm.faces, key=lambda f: f.calc_center_median().z)
    bmesh.ops.inset_individual(drum_bm, faces=[drum_top], thickness=0.022, depth=0.0)
    drum_ext = bmesh.ops.extrude_face_region(drum_bm, geom=[drum_top])
    drum_ext_verts = [v for v in drum_ext["geom"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(drum_bm, vec=(0.0, 0.0, -0.40), verts=drum_ext_verts)
    # Central agitator cone
    bmesh.ops.create_cone(
        drum_bm,
        cap_ends=True,
        cap_tris=False,
        segments=16,
        radius1=0.065,
        radius2=0.032,
        depth=0.26,
    )
    for v in drum_bm.verts[-32:]:
        v.co.z += 0.52
        v.co.y -= 0.02
    drum_obj = create_obj_from_bm("WasherDrum", drum_bm, mat, (0.05, 0.02, 0.30, 0.12))

    # Slanted rear control console (+Y in Blender = -Z in Godot)
    console_bm = bmesh.new()
    bmesh.ops.create_cube(console_bm, size=1.0)
    bmesh.ops.scale(console_bm, vec=(0.68, 0.16, 0.16), verts=console_bm.verts)
    for v in console_bm.verts:
        if v.co.z > 0 and v.co.y < 0:
            v.co.y += 0.06
    bmesh.ops.bevel(
        console_bm,
        geom=list(console_bm.edges),
        offset=0.01,
        segments=2,
        affect="EDGES",
        clamp_overlap=True,
    )
    bmesh.ops.translate(console_bm, vec=(0.0, 0.27, 0.93), verts=console_bm.verts)
    console_obj = create_obj_from_bm("Console", console_bm, mat, (0.05, 0.76, 0.95, 0.98))

    # Beveled rotary dial knob + 2 selector buttons on console
    dial_bm = bmesh.new()
    bmesh.ops.create_cone(
        dial_bm,
        cap_ends=True,
        cap_tris=False,
        segments=24,
        radius1=0.034,
        radius2=0.028,
        depth=0.032,
    )
    bmesh.ops.bevel(
        dial_bm,
        geom=list(dial_bm.edges),
        offset=0.004,
        segments=2,
        affect="EDGES",
        clamp_overlap=True,
    )
    bmesh.ops.rotate(
        dial_bm, cent=(0, 0, 0), matrix=math_rot_x(math.radians(-68)), verts=dial_bm.verts
    )
    bmesh.ops.translate(dial_bm, vec=(0.20, 0.19, 0.94), verts=dial_bm.verts)

    for btn_x in (-0.18, -0.11):
        btn_bm = bmesh.new()
        bmesh.ops.create_cone(
            btn_bm,
            cap_ends=True,
            cap_tris=False,
            segments=16,
            radius1=0.014,
            radius2=0.012,
            depth=0.02,
        )
        bmesh.ops.rotate(
            btn_bm, cent=(0, 0, 0), matrix=math_rot_x(math.radians(-68)), verts=btn_bm.verts
        )
        bmesh.ops.translate(btn_bm, vec=(btn_x, 0.195, 0.935), verts=btn_bm.verts)
        mesh_tmp = bpy.data.meshes.new("TmpBtn")
        btn_bm.to_mesh(mesh_tmp)
        btn_bm.free()
        dial_bm.from_mesh(mesh_tmp)
        bpy.data.meshes.remove(mesh_tmp)

    dial_obj = create_obj_from_bm("Dial", dial_bm, mat, (0.05, 0.02, 0.30, 0.12))

    # Rear hinge knuckles mounted at Y = 0.16, Z = 0.85
    hinge_bm = bmesh.new()
    for hx in (-0.18, 0.18):
        k_bm = bmesh.new()
        bmesh.ops.create_cone(
            k_bm,
            cap_ends=True,
            cap_tris=False,
            segments=14,
            radius1=0.014,
            radius2=0.014,
            depth=0.05,
        )
        bmesh.ops.rotate(
            k_bm,
            cent=(0, 0, 0),
            matrix=mathutils.Matrix.Rotation(math.radians(90), 3, "Y"),
            verts=k_bm.verts,
        )
        bmesh.ops.translate(k_bm, vec=(hx, 0.16, 0.858), verts=k_bm.verts)
        mesh_tmp = bpy.data.meshes.new("TmpHinge")
        k_bm.to_mesh(mesh_tmp)
        k_bm.free()
        hinge_bm.from_mesh(mesh_tmp)
        bpy.data.meshes.remove(mesh_tmp)
    hinge_obj = create_obj_from_bm("Hinges", hinge_bm, mat, (0.05, 0.02, 0.30, 0.12))

    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = body_obj
    for o in (body_obj, drum_obj, console_obj, dial_obj, hinge_obj):
        o.select_set(True)
    bpy.ops.object.join()
    return body_obj


def build_washer_door(mat):
    # Hinged lid: origin at rear hinge (Y = +0.16, Z = 0.85), extends forward (-Y)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(0.48, 0.44, 0.024), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(0.0, -0.22, 0.012), verts=bm.verts)
    bmesh.ops.bevel(
        bm,
        geom=list(bm.edges),
        offset=0.008,
        segments=3,
        affect="EDGES",
        clamp_overlap=True,
    )
    door_obj = create_obj_from_bm("WasherDoor", bm, mat, (0.15, 0.25, 0.85, 0.65))
    door_obj.location = (0.0, 0.16, 0.85)

    # Beveled front handle lip
    handle_bm = bmesh.new()
    bmesh.ops.create_cube(handle_bm, size=1.0)
    bmesh.ops.scale(handle_bm, vec=(0.14, 0.028, 0.014), verts=handle_bm.verts)
    bmesh.ops.translate(handle_bm, vec=(0.0, -0.41, 0.028), verts=handle_bm.verts)
    bmesh.ops.bevel(
        handle_bm,
        geom=list(handle_bm.edges),
        offset=0.004,
        segments=2,
        affect="EDGES",
        clamp_overlap=True,
    )
    handle_obj = create_obj_from_bm("Handle", handle_bm, mat, (0.15, 0.25, 0.85, 0.65))
    handle_obj.location = (0.0, 0.16, 0.85)

    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = door_obj
    door_obj.select_set(True)
    handle_obj.select_set(True)
    bpy.ops.object.join()
    return door_obj


def main():
    clear_scene()
    mat = create_procedural_material()
    body = build_washer_body(mat)
    door = build_washer_door(mat)
    door.parent = body
    door.matrix_parent_inverse = body.matrix_world.inverted()

    repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    out_dir = os.path.join(repo_root, "assets", "models", "props", "washing_machine")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "washing_machine.glb")

    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        export_apply=True,
        export_yup=True,
    )
    tri_count = sum(
        len(p.vertices) - 2
        for obj in bpy.data.objects
        if obj.type == "MESH"
        for p in obj.data.polygons
    )
    print(f"Exported: {out_path} (tris={tri_count})")


if __name__ == "__main__":
    main()
