"""Procedural High-Poly Gothic Arch generator for headless Blender.
Creates a continuous, manifold stone archway with pointed gothic vault,
archivolts, capitals, plinths, stone texture relief, and exports to GLB.
"""
import math
import os
import sys
import bmesh
import bpy


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_pointed_arch_cutter(
    name: str,
    half_w: float,
    apex_z: float,
    y_min: float,
    y_max: float,
    base_z: float = -0.1,
) -> bpy.types.Object:
    """Creates a solid 3D prism cutter for pointed Gothic arch boolean difference.

    Forms an unbroken equilateral/lancet pointed arch profile extending
    from base_z up to the vault apex.
    """
    c_x = half_w * 0.667
    term1 = (half_w + c_x) ** 2 - c_x**2 + 2.8**2 - apex_z**2
    c_z = term1 / (2.0 * (2.8 - apex_z))
    radius = math.sqrt(c_x**2 + (apex_z - c_z) ** 2)

    pts = []
    # Bottom opening starting from base_z
    pts.append((half_w, base_z))
    pts.append((-half_w, base_z))
    pts.append((-half_w, 2.8))

    # Left arc from (-half_w, 2.8) up to apex (0.0, apex_z)
    ang_start = math.atan2(2.8 - c_z, -half_w - c_x)
    ang_end = math.atan2(apex_z - c_z, 0.0 - c_x)
    segs = 24
    for i in range(1, segs):
        t = i / float(segs)
        a = ang_start + t * (ang_end - ang_start)
        pts.append((c_x + radius * math.cos(a), c_z + radius * math.sin(a)))
    pts.append((0.0, apex_z))

    # Right arc from apex (0.0, apex_z) down to (half_w, 2.8)
    ang_r_start = math.atan2(apex_z - c_z, 0.0 - (-c_x))
    ang_r_end = math.atan2(2.8 - c_z, half_w - (-c_x))
    for i in range(1, segs):
        t = i / float(segs)
        a = ang_r_start + t * (ang_r_end - ang_r_start)
        pts.append((-c_x + radius * math.cos(a), c_z + radius * math.sin(a)))
    pts.append((half_w, 2.8))

    bm = bmesh.new()
    verts_front = [bm.verts.new((x, y_max, z)) for x, z in pts]
    verts_back = [bm.verts.new((x, y_min, z)) for x, z in pts]

    bm.faces.new(verts_front)
    bm.faces.new(reversed(verts_back))

    n = len(pts)
    for i in range(n):
        next_i = (i + 1) % n
        bm.faces.new(
            [verts_front[i], verts_back[i], verts_back[next_i], verts_front[next_i]]
        )

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()

    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    return obj


def create_gothic_arch_geometry() -> bpy.types.Object:
    """Generates contiguous, watertight high-poly Gothic Arch geometry.

    Ensures the vault cleanly connects to the side pillars, capitals, and plinths
    without severed geometry, gaps, floating pieces, or inverted normals.
    """
    # 1. Main contiguous arch block (X: -1.5 to 1.5, Y: -0.4 to 0.4, Z: 0.0 to 4.0)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 2.0))
    arch_block = bpy.context.active_object
    arch_block.name = "Arch_HighPoly"
    arch_block.scale = (3.0, 0.8, 4.0)
    bpy.ops.object.transform_apply(scale=True, location=True)

    parts_to_union = []

    # 2. Base plinths (Left and Right, stepped wider: X: 0.70, Y: 0.90, Z: 0.40)
    for sign in (-1.0, 1.0):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sign * 1.2, 0.0, 0.2))
        plinth = bpy.context.active_object
        plinth.scale = (0.7, 0.9, 0.4)
        bpy.ops.object.transform_apply(scale=True, location=True)
        parts_to_union.append(plinth)

    # 3. Capital moldings at springing line (Z: 2.45 to 2.75, scale=(0.70, 0.92, 0.30))
    for sign in (-1.0, 1.0):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(sign * 1.2, 0.0, 2.60))
        cap = bpy.context.active_object
        cap.scale = (0.70, 0.92, 0.30)
        bpy.ops.object.transform_apply(scale=True, location=True)
        parts_to_union.append(cap)

    # 4. Engaged column shafts along pillar faces (Z: 0.35 to 2.45, capped under capital)
    for sign in (-1.0, 1.0):
        for y_off in (-0.37, 0.37):
            bpy.ops.mesh.primitive_cylinder_add(
                radius=0.08, depth=2.1, vertices=16, location=(sign * 1.2, y_off, 1.40)
            )
            shaft = bpy.context.active_object
            bpy.ops.object.transform_apply(scale=True, location=True)
            parts_to_union.append(shaft)

    # Fuse base architectural features into a single watertight solid via Exact Boolean Union
    for part in parts_to_union:
        mod = arch_block.modifiers.new(name="UnionPart", type="BOOLEAN")
        mod.operation = "UNION"
        mod.object = part
        mod.solver = "EXACT"
        bpy.context.view_layer.objects.active = arch_block
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(part, do_unlink=True)

    # 5. Cutters for pointed vault opening and concentric stepped archivolts
    # Inner vault opening (through full depth: Y from -0.50 to 0.50, floor to apex)
    c_inner = make_pointed_arch_cutter("CutterInner", 0.90, 3.55, -0.50, 0.50, -0.1)
    # Front archivolt stepped recess (above capitals: Z >= 2.75, Y: 0.28 to 0.50)
    c_front = make_pointed_arch_cutter("CutterFront", 0.96, 3.62, 0.28, 0.50, 2.75)
    # Back archivolt stepped recess (above capitals: Z >= 2.75, Y: -0.50 to -0.28)
    c_back = make_pointed_arch_cutter("CutterBack", 0.96, 3.62, -0.50, -0.28, 2.75)

    for cutter in [c_inner, c_front, c_back]:
        mod = arch_block.modifiers.new(name="CutArch", type="BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.object = cutter
        mod.solver = "EXACT"
        bpy.context.view_layer.objects.active = arch_block
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cutter, do_unlink=True)

    # 6. Keystone at vault apex (Z: 3.55 to 3.85) - unioned AFTER cutters to crown cleanly
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 3.70))
    keystone = bpy.context.active_object
    keystone.scale = (0.36, 0.92, 0.30)
    bpy.ops.object.transform_apply(scale=True, location=True)
    mod = arch_block.modifiers.new(name="UnionKeystone", type="BOOLEAN")
    mod.operation = "UNION"
    mod.object = keystone
    mod.solver = "EXACT"
    bpy.context.view_layer.objects.active = arch_block
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(keystone, do_unlink=True)

    # 7. Stone Bevel modifier for realistic architectural chamfers
    bev_mod = arch_block.modifiers.new(name="StoneBevel", type="BEVEL")
    bev_mod.width = 0.015
    bev_mod.segments = 2
    bev_mod.limit_method = "ANGLE"
    bev_mod.angle_limit = math.radians(40.0)
    bpy.ops.object.modifier_apply(modifier=bev_mod.name)

    # 8. Procedural Displace modifier for chiselled stone surface relief
    # Protect bottom floor (Z <= 0.01) from displace to guarantee flat floor seating
    vgroup = arch_block.vertex_groups.new(name="DisplaceGroup")
    displace_indices = [v.index for v in arch_block.data.vertices if v.co.z > 0.01]
    vgroup.add(displace_indices, 1.0, "REPLACE")

    tex = bpy.data.textures.new("StoneNoise", type="CLOUDS")
    tex.noise_scale = 0.15
    disp_mod = arch_block.modifiers.new(name="StoneRelief", type="DISPLACE")
    disp_mod.texture = tex
    disp_mod.vertex_group = "DisplaceGroup"
    disp_mod.strength = 0.005
    bpy.ops.object.modifier_apply(modifier=disp_mod.name)

    # 9. Smooth shading to ensure connected vertex normals in glTF export
    bpy.ops.object.select_all(action="DESELECT")
    arch_block.select_set(True)
    bpy.context.view_layer.objects.active = arch_block
    bpy.ops.object.shade_smooth()

    # Clear fragmented UV layers from boolean cuts so glTF does not split seam vertices
    while arch_block.data.uv_layers:
        arch_block.data.uv_layers.remove(arch_block.data.uv_layers[0])

    return arch_block


def add_stone_material(obj: bpy.types.Object) -> None:
    """Assigns procedural stone limestone material for high-poly baking."""
    mat = bpy.data.materials.new(name="GothicStoneHighPolyMat")
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links

    bsdf = nodes.get("Principled BSDF")

    tex_noise = nodes.new(type="ShaderNodeTexNoise")
    tex_noise.inputs["Scale"].default_value = 8.0
    tex_noise.inputs["Detail"].default_value = 6.0
    tex_noise.inputs["Roughness"].default_value = 0.7

    color_ramp = nodes.new(type="ShaderNodeValToRGB")
    color_ramp.color_ramp.elements[0].position = 0.2
    color_ramp.color_ramp.elements[0].color = (0.42, 0.40, 0.36, 1.0)
    color_ramp.color_ramp.elements[1].position = 0.8
    color_ramp.color_ramp.elements[1].color = (0.65, 0.62, 0.58, 1.0)

    links.new(tex_noise.outputs["Fac"], color_ramp.inputs["Fac"])
    links.new(color_ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85

    obj.data.materials.append(mat)


def main() -> None:
    outpath = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "raw_arch.glb"
    clear_scene()
    high_obj = create_gothic_arch_geometry()
    add_stone_material(high_obj)

    bpy.ops.object.select_all(action="DESELECT")
    high_obj.select_set(True)
    bpy.context.view_layer.objects.active = high_obj

    os.makedirs(os.path.dirname(os.path.abspath(outpath)), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=outpath,
        use_selection=True,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
    )
    print(f"[HighPolyArch] Successfully generated and exported to: {outpath}")


if __name__ == "__main__":
    main()
