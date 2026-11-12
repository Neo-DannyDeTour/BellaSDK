"""Procedural High-Poly Gothic Arch generator for headless Blender.
Creates a continuous, manifold stone archway with pointed gothic vault,
radial voussoirs, stepped archivolts, molded impost capitals, stepped plinths,
engaged colonnettes, crown cornice, stone mortar courses, and exports to GLB.
"""
import math
import os
import sys
import bmesh
import bpy


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def get_lancet_arc_point(
    half_w: float, spring_z: float, apex_z: float, side: float, t: float
) -> tuple[float, float, float]:
    """Computes (x, z, normal_angle) along a pointed Gothic lancet arc.

    side = -1.0 for left arc (from x = -half_w up to x = 0),
    side = +1.0 for right arc (from x = +half_w up to x = 0).
    t in [0.0, 1.0] where 0.0 is springing line and 1.0 is apex.
    """
    c_x = half_w * 0.65
    term1 = (half_w + c_x) ** 2 - c_x**2 + spring_z**2 - apex_z**2
    c_z = term1 / (2.0 * (spring_z - apex_z))
    radius = math.sqrt(c_x**2 + (apex_z - c_z) ** 2)

    if side < 0.0:
        center_x = c_x
        ang_start = math.atan2(spring_z - c_z, -half_w - center_x)
        ang_end = math.atan2(apex_z - c_z, 0.0 - center_x)
    else:
        center_x = -c_x
        ang_start = math.atan2(spring_z - c_z, half_w - center_x)
        ang_end = math.atan2(apex_z - c_z, 0.0 - center_x)

    ang = ang_start + t * (ang_end - ang_start)
    px = center_x + radius * math.cos(ang)
    pz = c_z + radius * math.sin(ang)
    return px, pz, ang


def make_pointed_arch_cutter(
    name: str,
    half_w: float,
    spring_z: float,
    apex_z: float,
    y_min: float,
    y_max: float,
    base_z: float = -0.1,
    segs: int = 24,
) -> bpy.types.Object:
    """Creates a solid 3D prism cutter for pointed Gothic arch boolean difference."""
    pts: list[tuple[float, float]] = []
    pts.append((half_w, base_z))
    pts.append((-half_w, base_z))
    pts.append((-half_w, spring_z))

    for i in range(1, segs):
        t = i / float(segs)
        px, pz, _ = get_lancet_arc_point(half_w, spring_z, apex_z, -1.0, t)
        pts.append((px, pz))
    pts.append((0.0, apex_z))

    for i in range(segs - 1, 0, -1):
        t = i / float(segs)
        px, pz, _ = get_lancet_arc_point(half_w, spring_z, apex_z, 1.0, t)
        pts.append((px, pz))
    pts.append((half_w, spring_z))

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


def make_voussoir_wedge(
    name: str,
    r_inner: float,
    r_outer: float,
    spring_z: float,
    apex_in: float,
    apex_out: float,
    side: float,
    t0: float,
    t1: float,
    y_min: float,
    y_max: float,
) -> bpy.types.Object:
    """Builds a 3D radial wedge stone (voussoir) along the Gothic arch ring."""
    tm = 0.5 * (t0 + t1)
    x_i0, z_i0, _ = get_lancet_arc_point(r_inner, spring_z, apex_in, side, t0)
    x_im, z_im, _ = get_lancet_arc_point(r_inner, spring_z, apex_in, side, tm)
    x_i1, z_i1, _ = get_lancet_arc_point(r_inner, spring_z, apex_in, side, t1)

    x_o1, z_o1, _ = get_lancet_arc_point(r_outer, spring_z, apex_out, side, t1)
    x_om, z_om, _ = get_lancet_arc_point(r_outer, spring_z, apex_out, side, tm)
    x_o0, z_o0, _ = get_lancet_arc_point(r_outer, spring_z, apex_out, side, t0)

    pts = [
        (x_i0, z_i0),
        (x_im, z_im),
        (x_i1, z_i1),
        (x_o1, z_o1),
        (x_om, z_om),
        (x_o0, z_o0),
    ]
    if side > 0.0:
        pts.reverse()

    bm = bmesh.new()
    vf = [bm.verts.new((x, y_max, z)) for x, z in pts]
    vb = [bm.verts.new((x, y_min, z)) for x, z in pts]
    bm.faces.new(vf)
    bm.faces.new(reversed(vb))
    n = len(pts)
    for i in range(n):
        ni = (i + 1) % n
        bm.faces.new([vf[i], vb[i], vb[ni], vf[ni]])

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()

    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    return obj


def add_box_part(
    name: str, loc: tuple[float, float, float], dims: tuple[float, float, float]
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = dims
    bpy.ops.object.transform_apply(scale=True, location=True)
    return obj


def create_gothic_arch_geometry(subdivide_high: bool = True) -> bpy.types.Object:
    """Generates contiguous, watertight Gothic Arch geometry.

    When subdivide_high=True, applies 2-segment bevel, subdivision, and cloud relief
    for the high-poly sculpt target.
    When subdivide_high=False, applies a clean 1-segment architectural chamfer and skips
    subdivision/mortar boolean cuts to produce an ultra-clean low-poly game mesh!
    """
    spring_z = 2.55
    # 1. Core wall block slightly inset so stepped architectural orders read clearly
    arch_block = add_box_part("Arch_HighPoly", (0.0, 0.0, 2.0), (2.88, 0.68, 3.92))

    parts_to_union: list[bpy.types.Object] = []

    # 2. Two-tier stepped plinth bases (Left and Right)
    for sign in (-1.0, 1.0):
        px = sign * 1.19
        parts_to_union.append(
            add_box_part(f"PlinthLower_{sign}", (px, 0.0, 0.14), (0.62, 0.80, 0.28))
        )
        parts_to_union.append(
            add_box_part(f"PlinthUpper_{sign}", (px, 0.0, 0.34), (0.56, 0.75, 0.20))
        )

        # Engaged jamb pilasters (outer and inner vertical stone orders)
        parts_to_union.append(
            add_box_part(f"OuterPier_{sign}", (sign * 1.38, 0.0, 1.92), (0.22, 0.74, 3.60))
        )
        parts_to_union.append(
            add_box_part(f"InnerJamb_{sign}", (sign * 1.01, 0.0, 1.44), (0.20, 0.74, 2.20))
        )

        # 3. Clustered engaged column shafts with base rings and necking rings
        cyl_verts = 16 if subdivide_high else 10
        for y_sign in (-1.0, 1.0):
            # Main outer shaft
            sx_main = sign * 1.17
            sy_main = y_sign * 0.33
            bpy.ops.mesh.primitive_cylinder_add(
                radius=0.075,
                depth=2.04,
                vertices=cyl_verts,
                location=(sx_main, sy_main, 1.42),
            )
            s_main = bpy.context.active_object
            bpy.ops.object.transform_apply(scale=True, location=True)
            parts_to_union.append(s_main)

            # Inner reveal colonnette
            sx_in = sign * 0.96
            sy_in = y_sign * 0.25
            bpy.ops.mesh.primitive_cylinder_add(
                radius=0.055,
                depth=2.04,
                vertices=cyl_verts,
                location=(sx_in, sy_in, 1.42),
            )
            s_in = bpy.context.active_object
            bpy.ops.object.transform_apply(scale=True, location=True)
            parts_to_union.append(s_in)

        # 4. Multi-tier molded Impost Capitals at springing line (Z = 2.38 to 2.66)
        parts_to_union.append(
            add_box_part(f"CapNeck_{sign}", (px, 0.0, 2.41), (0.58, 0.75, 0.08))
        )
        parts_to_union.append(
            add_box_part(f"CapBell_{sign}", (px, 0.0, 2.50), (0.62, 0.78, 0.12))
        )
        parts_to_union.append(
            add_box_part(f"CapAbacus_{sign}", (px, 0.0, 2.60), (0.64, 0.80, 0.10))
        )

    # 5. Stepped Crown Cornice / Entablature at top (Z = 3.74 to 4.00)
    parts_to_union.append(
        add_box_part("CorniceFrieze", (0.0, 0.0, 3.79), (2.94, 0.75, 0.12))
    )
    parts_to_union.append(
        add_box_part("CorniceCrown", (0.0, 0.0, 3.92), (3.00, 0.80, 0.16))
    )

    # Fuse base piers, shafts, capitals, and cornice first
    for part in parts_to_union:
        mod = arch_block.modifiers.new(name="UnionPart", type="BOOLEAN")
        mod.operation = "UNION"
        mod.object = part
        mod.solver = "EXACT"
        bpy.context.view_layer.objects.active = arch_block
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(part, do_unlink=True)

    # 6. Cut pointed Gothic vault opening and stepped archivolt orders
    arc_segs = 24 if subdivide_high else 14
    c_inner = make_pointed_arch_cutter(
        "CutterInner", 0.90, spring_z, 3.52, -0.55, 0.55, -0.1, segs=arc_segs
    )
    c_step_f = make_pointed_arch_cutter(
        "CutterStepF", 0.99, spring_z, 3.60, 0.25, 0.55, spring_z, segs=arc_segs
    )
    c_step_b = make_pointed_arch_cutter(
        "CutterStepB", 0.99, spring_z, 3.60, -0.55, -0.25, spring_z, segs=arc_segs
    )

    for cutter in [c_inner, c_step_f, c_step_b]:
        mod = arch_block.modifiers.new(name="CutArch", type="BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.object = cutter
        mod.solver = "EXACT"
        bpy.context.view_layer.objects.active = arch_block
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cutter, do_unlink=True)

    # 7. Radial Voussoir Stones along the Pointed Arch Ring + Central Keystone
    voussoirs: list[bpy.types.Object] = []
    num_voussoirs = 7
    for side in (-1.0, 1.0):
        for idx in range(num_voussoirs):
            t0 = (idx + 0.08) / float(num_voussoirs)
            t1 = (idx + 0.90) / float(num_voussoirs)
            if idx == 0:
                t0 = 0.04
            if idx == num_voussoirs - 1:
                t1 = 0.85
            vw_out = make_voussoir_wedge(
                f"VoussoirOut_{side}_{idx}",
                0.96,
                1.17,
                spring_z + 0.06,
                3.58,
                3.72,
                side,
                t0,
                t1,
                -0.37,
                0.37,
            )
            voussoirs.append(vw_out)

    # Inner continuous soffit rib molding (intrados band)
    for side in (-1.0, 1.0):
        rib = make_voussoir_wedge(
            f"IntradosRib_{side}",
            0.892,
            0.995,
            spring_z + 0.06,
            3.510,
            3.605,
            side,
            0.03,
            0.84,
            -0.23,
            0.23,
        )
        voussoirs.append(rib)

    # Prominent tapered Keystone crowning the apex
    keystone = add_box_part("Keystone", (0.0, 0.0, 3.63), (0.30, 0.78, 0.30))
    voussoirs.append(keystone)

    for v_obj in voussoirs:
        mod = arch_block.modifiers.new(name="UnionVoussoir", type="BOOLEAN")
        mod.operation = "UNION"
        mod.object = v_obj
        mod.solver = "EXACT"
        bpy.context.view_layer.objects.active = arch_block
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(v_obj, do_unlink=True)

    if subdivide_high:
        # 8. Horizontal Ashlar Mortar Groove Cutters on High-Poly only (baked into Normal & AO!)
        groove_cutters: list[bpy.types.Object] = []
        for z_course in (0.85, 1.25, 1.65, 2.05, 2.95, 3.35):
            for y_face in (-0.34, 0.34):
                groove_cutters.append(
                    add_box_part(
                        f"MortarH_{z_course}_{y_face}",
                        (0.0, y_face, z_course),
                        (3.10, 0.04, 0.018),
                    )
                )
            for x_side in (-1.49, 1.49):
                groove_cutters.append(
                    add_box_part(
                        f"MortarSide_{z_course}_{x_side}",
                        (x_side, 0.0, z_course),
                        (0.05, 0.85, 0.018),
                    )
                )

        for gc in groove_cutters:
            mod = arch_block.modifiers.new(name="CutMortar", type="BOOLEAN")
            mod.operation = "DIFFERENCE"
            mod.object = gc
            mod.solver = "EXACT"
            bpy.context.view_layer.objects.active = arch_block
            bpy.ops.object.modifier_apply(modifier=mod.name)
            bpy.data.objects.remove(gc, do_unlink=True)

        # 9. Stone Bevel modifier for crisp chamfered stone edges (2 segments on high-poly)
        bev_mod = arch_block.modifiers.new(name="StoneBevel", type="BEVEL")
        bev_mod.width = 0.010
        bev_mod.segments = 2
        bev_mod.limit_method = "ANGLE"
        bev_mod.angle_limit = math.radians(40.0)
        bev_mod.use_clamp_overlap = True
        bpy.context.view_layer.objects.active = arch_block
        bpy.ops.object.modifier_apply(modifier=bev_mod.name)

        # 10. Subdivide and apply procedural stone surface relief (protecting Z <= 0.01 floor plane)
        sub_mod = arch_block.modifiers.new(name="StoneSubdiv", type="SUBSURF")
        sub_mod.subdivision_type = "SIMPLE"
        sub_mod.levels = 1
        sub_mod.render_levels = 1
        bpy.ops.object.modifier_apply(modifier=sub_mod.name)

        vgroup = arch_block.vertex_groups.new(name="DisplaceGroup")
        displace_indices = [v.index for v in arch_block.data.vertices if v.co.z > 0.01]
        vgroup.add(displace_indices, 1.0, "REPLACE")

        tex = bpy.data.textures.new("StoneNoise", type="CLOUDS")
        tex.noise_scale = 0.16
        disp_mod = arch_block.modifiers.new(name="StoneRelief", type="DISPLACE")
        disp_mod.texture = tex
        disp_mod.vertex_group = "DisplaceGroup"
        disp_mod.strength = 0.004
        bpy.ops.object.modifier_apply(modifier=disp_mod.name)

    # 11. Smooth shading (preserve exact boolean topology without destructive remove_doubles)
    bpy.ops.object.select_all(action="DESELECT")
    arch_block.select_set(True)
    bpy.context.view_layer.objects.active = arch_block
    bpy.ops.object.shade_smooth()

    while arch_block.data.uv_layers:
        arch_block.data.uv_layers.remove(arch_block.data.uv_layers[0])

    return arch_block


def add_stone_material(obj: bpy.types.Object) -> None:
    """Assigns rich procedural Weathered Gothic Limestone material for baking."""
    obj.data.materials.clear()
    mat = bpy.data.materials.new(name="GothicStoneHighPolyMat")
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links

    bsdf = nodes.get("Principled BSDF")
    tex_coord = nodes.new(type="ShaderNodeTexCoord")

    # 1. Macro mottled weathering noise
    noise_macro = nodes.new(type="ShaderNodeTexNoise")
    noise_macro.inputs["Scale"].default_value = 3.2
    noise_macro.inputs["Detail"].default_value = 6.0
    noise_macro.inputs["Roughness"].default_value = 0.65
    links.new(tex_coord.outputs["Object"], noise_macro.inputs["Vector"])

    # 2. High-frequency limestone pore & grain noise
    noise_micro = nodes.new(type="ShaderNodeTexNoise")
    noise_micro.inputs["Scale"].default_value = 28.0
    noise_micro.inputs["Detail"].default_value = 10.0
    noise_micro.inputs["Roughness"].default_value = 0.78
    links.new(tex_coord.outputs["Object"], noise_micro.inputs["Vector"])

    # 3. Voronoi cellular stone variation
    voronoi = nodes.new(type="ShaderNodeTexVoronoi")
    voronoi.inputs["Scale"].default_value = 6.5
    links.new(tex_coord.outputs["Object"], voronoi.inputs["Vector"])

    # Blend macro + micro into ColorRamp for authentic aged warm-gray limestone
    mix_fac = nodes.new(type="ShaderNodeMix")
    mix_fac.data_type = "FLOAT"
    mix_fac.inputs["Factor"].default_value = 0.45
    links.new(noise_macro.outputs["Fac"], mix_fac.inputs["A"])
    links.new(noise_micro.outputs["Fac"], mix_fac.inputs["B"])

    color_ramp = nodes.new(type="ShaderNodeValToRGB")
    cr = color_ramp.color_ramp
    cr.elements[0].position = 0.18
    cr.elements[0].color = (0.31, 0.29, 0.26, 1.0)
    cr.elements[1].position = 0.82
    cr.elements[1].color = (0.56, 0.53, 0.48, 1.0)
    el_mid = cr.elements.new(0.50)
    el_mid.color = (0.45, 0.43, 0.39, 1.0)

    links.new(mix_fac.outputs["Result"], color_ramp.inputs["Fac"])
    links.new(color_ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.86

    # 4. Procedural micro-bump for chiselled limestone pores in normal bake
    bump = nodes.new(type="ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    bump.inputs["Distance"].default_value = 0.008
    links.new(noise_micro.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

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
