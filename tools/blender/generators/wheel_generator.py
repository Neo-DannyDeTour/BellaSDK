#!/usr/bin/env python3
"""
Procedural HL2-style car wheel generator for Blender 3.6 / 4.x / 5.x.
Generates manifold 3D tire + stamped steel rim mesh, synthesizes 1024x1024 PBR
textures (BaseColor, Normal, Roughness, Metallic) via numpy, packs textures,
and exports a self-contained .glb file.
"""

import math
import os
import tempfile
import bmesh
import bpy
import numpy as np

# ==============================================================================
# CONFIGURATION
# ==============================================================================
OUTPUT_GLB_PATH: str = os.path.abspath(
    os.path.join(
        os.path.dirname(__file__),
        "..",
        "..",
        "..",
        "assets",
        "models",
        "props",
        "wheel",
        "hl2_wheel.glb",
    )
)
TEX_SIZE: int = 1024
RADIAL_SEGMENTS: int = 80  # Divisible by 16 (vent holes) and 5 (lug holes)
OUTER_RADIUS: float = 0.33
RIM_RADIUS: float = 0.185
BORE_RADIUS: float = 0.042
TIRE_HALF_WIDTH: float = 0.108


def clear_scene() -> None:
    """Remove existing objects, meshes, materials, and images."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def generate_pbr_textures() -> dict[str, bpy.types.Image]:
    """Synthesize UV-matched Albedo, Normal, Roughness, and Metallic maps."""
    res = TEX_SIZE
    # u: circumferential [0, 1], v: radial profile from center bore (0) to inner bead (1)
    u_lin = np.linspace(0.0, 1.0, res, endpoint=False, dtype=np.float32)
    v_lin = np.linspace(0.0, 1.0, res, dtype=np.float32)
    u, v = np.meshgrid(u_lin, v_lin)

    # Deterministic multi-frequency procedural grunge noise
    grunge = (
        0.50 * np.sin(u * 2.0 * np.pi * 7.0 + v * 19.0)
        + 0.30 * np.cos(u * 2.0 * np.pi * 23.0 - v * 41.0)
        + 0.20 * np.sin(u * 2.0 * np.pi * 61.0 + v * 97.0)
    )
    grunge = np.clip(0.5 + 0.5 * grunge, 0.0, 1.0)

    rng = np.random.default_rng(seed=42)
    micro_grain = rng.uniform(-0.04, 0.04, size=(res, res)).astype(np.float32)

    # Masks by V coordinate bands
    rim_mask = (v <= 0.38).astype(np.float32)
    sidewall_top_mask = ((v > 0.38) & (v <= 0.54)).astype(np.float32)
    tread_mask = ((v > 0.54) & (v <= 0.80)).astype(np.float32)
    sidewall_bot_mask = (v > 0.80).astype(np.float32)

    # --- Heightfield (for Normal Map + Cavity Darkening) ---
    height = np.zeros((res, res), dtype=np.float32)

    # 1. Tire Tread Pattern (4 main grooves + 5 ribs with angled chevron blocks)
    tread_v = np.clip((v - 0.54) / 0.26, 0.0, 1.0)
    groove_centers = [0.20, 0.40, 0.60, 0.80]
    groove_mask = np.zeros_like(v)
    for gc in groove_centers:
        groove_mask += np.exp(-((tread_v - gc) ** 2) / (2.0 * 0.018**2))
    groove_mask = np.clip(groove_mask, 0.0, 1.0)

    # Angled lateral sipes across tread ribs
    chevron_phase = np.abs(tread_v - 0.5) * 3.5
    sipes = np.sin((u * 40.0 + chevron_phase) * 2.0 * np.pi)
    tread_blocks = np.clip((sipes + 0.55) * 3.0, 0.0, 1.0) * (1.0 - groove_mask)
    height += tread_mask * (tread_blocks * 0.85 - groove_mask * 0.65)

    # 2. Sidewall Scuffing & Mold Ribs
    sw_rings = 0.12 * np.sin(v * 280.0)
    height += (sidewall_top_mask + sidewall_bot_mask) * (sw_rings + micro_grain * 1.5)

    # 3. Rim Stamped Rings, 16 Vent Holes, 5 Lug Sockets
    vent_u = (u * 16.0) % 1.0 - 0.5
    vent_v = (v - 0.275) / 0.032
    vent_dist = np.sqrt(vent_u**2 + vent_v**2)
    vent_hole_mask = (np.clip(1.0 - vent_dist * 2.6, 0.0, 1.0) * rim_mask).astype(np.float32)

    lug_u = (u * 5.0) % 1.0 - 0.5
    lug_v = (v - 0.135) / 0.028
    lug_dist = np.sqrt(lug_u**2 + lug_v**2)
    lug_hole_mask = (np.clip(1.0 - lug_dist * 3.0, 0.0, 1.0) * rim_mask).astype(np.float32)

    rim_stamp = 0.25 * np.cos((v / 0.38) * 6.0 * np.pi)
    height += rim_mask * (rim_stamp - 1.2 * vent_hole_mask - 1.0 * lug_hole_mask)
    height += micro_grain * 0.5

    # --- Albedo (Base Color) ---
    albedo = np.zeros((res, res, 3), dtype=np.float32)

    # Gunmetal weathered steel + rust/dust patches on rim
    steel_col = np.array([0.22, 0.23, 0.24], dtype=np.float32)
    rust_col = np.array([0.28, 0.19, 0.13], dtype=np.float32)
    rim_rgb = (
        steel_col[None, None, :] * (1.0 - 0.35 * grunge[:, :, None])
        + rust_col[None, None, :] * (0.35 * (grunge[:, :, None] ** 2))
    )
    hole_darkening = np.clip(1.0 - 0.88 * (vent_hole_mask + lug_hole_mask), 0.08, 1.0)
    rim_rgb *= hole_darkening[:, :, None]

    # Charcoal rubber + dried gravel/mud dust on sidewalls & tread
    rubber_dark = np.array([0.09, 0.095, 0.10], dtype=np.float32)
    mud_dust = np.array([0.23, 0.21, 0.18], dtype=np.float32)
    tire_rgb = (
        rubber_dark[None, None, :]
        + mud_dust[None, None, :] * (0.38 * grunge[:, :, None])
    )
    # Darken tread grooves (baked cavity AO) and highlight raised tread blocks
    tread_ao = 1.0 - tread_mask * (0.55 * groove_mask - 0.15 * tread_blocks)
    tire_rgb *= tread_ao[:, :, None]

    albedo = rim_rgb * rim_mask[:, :, None] + tire_rgb * (1.0 - rim_mask[:, :, None])
    albedo = np.clip(albedo + micro_grain[:, :, None] * 0.25, 0.02, 0.95)

    # --- Metallic & Roughness ---
    metallic = rim_mask * (0.72 - 0.55 * (vent_hole_mask + lug_hole_mask) - 0.25 * grunge)
    metallic = np.clip(metallic, 0.0, 1.0)

    roughness = (
        rim_mask * (0.46 + 0.28 * grunge + 0.35 * (vent_hole_mask + lug_hole_mask))
        + (1.0 - rim_mask) * (0.82 + 0.12 * grunge + 0.12 * groove_mask * tread_mask)
    )
    roughness = np.clip(roughness, 0.15, 0.98)

    # --- Tangent-Space Normal Map from Heightfield Gradients ---
    dy, dx = np.gradient(height)
    normal_strength = 4.5
    nx = -dx * normal_strength
    ny = -dy * normal_strength
    nz = np.ones_like(height)
    norm_len = np.sqrt(nx**2 + ny**2 + nz**2)
    normal_rgb = np.stack(
        [0.5 + 0.5 * (nx / norm_len), 0.5 + 0.5 * (ny / norm_len), 0.5 + 0.5 * (nz / norm_len)],
        axis=-1,
    )

    def build_bpy_image(name: str, rgb: np.ndarray, is_data: bool) -> bpy.types.Image:
        img = bpy.data.images.new(name=name, width=res, height=res, alpha=False)
        rgba = np.ones((res, res, 4), dtype=np.float32)
        rgba[:, :, :3] = np.clip(rgb, 0.0, 1.0)
        img.pixels.foreach_set(rgba.ravel())
        img.colorspace_settings.name = "Non-Color" if is_data else "sRGB"
        tmp_path = os.path.join(tempfile.gettempdir(), f"{name}.png")
        img.filepath_raw = tmp_path
        img.file_format = "PNG"
        img.save()
        img.pack()
        return img

    return {
        "base_color": build_bpy_image("HL2_Wheel_BaseColor", albedo, is_data=False),
        "normal": build_bpy_image("HL2_Wheel_Normal", normal_rgb, is_data=True),
        "roughness": build_bpy_image(
            "HL2_Wheel_Roughness", np.repeat(roughness[:, :, None], 3, axis=2), is_data=True
        ),
        "metallic": build_bpy_image(
            "HL2_Wheel_Metallic", np.repeat(metallic[:, :, None], 3, axis=2), is_data=True
        ),
    }


def create_wheel_material(textures: dict[str, bpy.types.Image]) -> bpy.types.Material:
    """Create glTF-compliant Principled BSDF material linked to baked image textures."""
    mat = bpy.data.materials.new(name="M_HL2_Wheel")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out_node = nodes.new(type="ShaderNodeOutputMaterial")
    bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])

    tex_bc = nodes.new(type="ShaderNodeTexImage")
    tex_bc.image = textures["base_color"]
    links.new(tex_bc.outputs["Color"], bsdf.inputs["Base Color"])

    tex_met = nodes.new(type="ShaderNodeTexImage")
    tex_met.image = textures["metallic"]
    links.new(tex_met.outputs["Color"], bsdf.inputs["Metallic"])

    tex_rough = nodes.new(type="ShaderNodeTexImage")
    tex_rough.image = textures["roughness"]
    links.new(tex_rough.outputs["Color"], bsdf.inputs["Roughness"])

    tex_norm = nodes.new(type="ShaderNodeTexImage")
    tex_norm.image = textures["normal"]
    norm_map = nodes.new(type="ShaderNodeNormalMap")
    norm_map.inputs["Strength"].default_value = 1.25
    links.new(tex_norm.outputs["Color"], norm_map.inputs["Color"])
    links.new(norm_map.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


def build_wheel_mesh(mat: bpy.types.Material) -> bpy.types.Object:
    """Construct manifold 3D wheel geometry with inset vent/lug holes and 3D tread ribs."""
    # Cross-section profile: (radius, z_height, v_coord)
    # Center of wheel rests at Z = TIRE_HALF_WIDTH so bottom sits flush on Z = 0.0
    zc = TIRE_HALF_WIDTH
    profile: list[tuple[float, float, float]] = [
        # --- Stamped Steel Rim (v: 0.00 -> 0.38) ---
        (BORE_RADIUS, zc + 0.015, 0.00),          # 0: Inner axle bore lip
        (BORE_RADIUS, zc + 0.042, 0.04),          # 1: Axle bore top edge
        (0.068, zc + 0.044, 0.09),                # 2: Raised center hub dome
        (0.082, zc + 0.032, 0.11),                # 3: Lug ring inner edge
        (0.108, zc + 0.032, 0.16),                # 4: Lug ring outer edge (Band 3 = 5 Lugs)
        (0.125, zc + 0.048, 0.21),                # 5: Intermediate stamped ridge
        (0.142, zc + 0.025, 0.24),                # 6: Deep dish inner edge
        (0.166, zc + 0.028, 0.31),                # 7: Vent ring outer edge (Band 6 = 16 Vents)
        (0.178, zc + 0.062, 0.35),                # 8: Rim step flange
        (RIM_RADIUS, zc + 0.068, 0.38),           # 9: Rim outer bead lip
        # --- Top Sidewall (v: 0.38 -> 0.54) ---
        (0.215, zc + 0.088, 0.43),                # 10: Inner sidewall rise
        (0.265, zc + 0.108, 0.48),                # 11: Max sidewall bulge
        (0.312, zc + 0.096, 0.54),                # 12: Top tire shoulder
        # --- Tire Crown & 4 Circumferential Tread Grooves (v: 0.54 -> 0.80) ---
        (OUTER_RADIUS, zc + 0.076, 0.57),         # 13: Rib 1 outer edge
        (OUTER_RADIUS, zc + 0.052, 0.59),         # 14: Groove 1 top
        (OUTER_RADIUS - 0.007, zc + 0.046, 0.60), # 15: Groove 1 floor
        (OUTER_RADIUS, zc + 0.040, 0.61),         # 16: Rib 2 top
        (OUTER_RADIUS, zc + 0.016, 0.64),         # 17: Groove 2 top
        (OUTER_RADIUS - 0.007, zc + 0.008, 0.65), # 18: Groove 2 floor
        (OUTER_RADIUS, zc - 0.008, 0.69),         # 19: Center rib
        (OUTER_RADIUS - 0.007, zc - 0.016, 0.70), # 20: Groove 3 floor
        (OUTER_RADIUS, zc - 0.024, 0.71),         # 21: Rib 4 top
        (OUTER_RADIUS, zc - 0.046, 0.74),         # 22: Groove 4 top
        (OUTER_RADIUS - 0.007, zc - 0.052, 0.75), # 23: Groove 4 floor
        (OUTER_RADIUS, zc - 0.058, 0.76),         # 24: Rib 5 top
        (OUTER_RADIUS, zc - 0.076, 0.80),         # 25: Bottom shoulder edge
        # --- Bottom Sidewall & Back Rim Bead (v: 0.80 -> 1.00) ---
        (0.312, zc - 0.096, 0.84),                # 26: Bottom tire shoulder
        (0.265, zc - 0.108, 0.90),                # 27: Bottom sidewall bulge
        (RIM_RADIUS, zc - 0.072, 0.96),           # 28: Bottom tire bead
        (0.145, zc - 0.055, 0.98),                # 29: Inner barrel drop
        (BORE_RADIUS, zc + 0.015, 1.00),          # 30: Close loop back to bore
    ]

    # Name avoiding Godot -wheel suffix rule (which auto-creates VehicleWheel3D)
    mesh = bpy.data.meshes.new("SM_HL2_CarTire")
    obj = bpy.data.objects.new("SM_HL2_CarTire", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    num_pts = len(profile) - 1  # Last point closes to index 0
    ring_verts: list[list[bmesh.types.BMVert]] = []

    for i in range(RADIAL_SEGMENTS):
        angle = (2.0 * math.pi * i) / RADIAL_SEGMENTS
        cos_a = math.cos(angle)
        sin_a = math.sin(angle)
        col_verts: list[bmesh.types.BMVert] = []
        for p_idx in range(num_pts):
            r, z, _ = profile[p_idx]
            # Subtle 3D tread lug relief on crown ribs
            if p_idx in (13, 16, 19, 21, 24) and (i % 2 == 0):
                r += 0.0022
            v = bm.verts.new((r * cos_a, r * sin_a, z))
            col_verts.append(v)
        ring_verts.append(col_verts)

    bm.verts.ensure_lookup_table()

    lug_faces: list[bmesh.types.BMFace] = []
    vent_faces: list[bmesh.types.BMFace] = []

    for i in range(RADIAL_SEGMENTS):
        i_next = (i + 1) % RADIAL_SEGMENTS
        u0 = i / float(RADIAL_SEGMENTS)
        u1 = (i + 1) / float(RADIAL_SEGMENTS)

        for j in range(num_pts):
            j_next = (j + 1) % num_pts
            v0 = profile[j][2]
            v1 = profile[j + 1][2]

            f = bm.faces.new(
                (
                    ring_verts[i][j],
                    ring_verts[i_next][j],
                    ring_verts[i_next][j_next],
                    ring_verts[i][j_next],
                )
            )
            f.smooth = True

            # Assign seamless polar/band UVs
            f.loops[0][uv_layer].uv = (u0, v0)
            f.loops[1][uv_layer].uv = (u1, v0)
            f.loops[2][uv_layer].uv = (u1, v1)
            f.loops[3][uv_layer].uv = (u0, v1)

            # Collect 5 Lug sockets (Band j==3) & 16 Vent holes (Band j==6)
            if j == 3 and (i % (RADIAL_SEGMENTS // 5) == 1):
                lug_faces.append(f)
            elif j == 6 and (i % (RADIAL_SEGMENTS // 16) == 2):
                vent_faces.append(f)

    # Inset and recess 3D rim ventilation holes & lug sockets
    hole_targets = lug_faces + vent_faces
    if hole_targets:
        res_inset = bmesh.ops.inset_individual(
            bm, faces=hole_targets, thickness=0.0035, depth=-0.010
        )
        for f in res_inset.get("faces", []):
            f.smooth = False

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    return obj


def export_glb(obj: bpy.types.Object, filepath: str) -> None:
    """Select generated wheel and export packed binary glTF (.glb)."""
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
    )
    print(f"[OK] Exported GLB -> {filepath}")


def main() -> None:
    clear_scene()
    textures = generate_pbr_textures()
    mat = create_wheel_material(textures)
    wheel_obj = build_wheel_mesh(mat)
    export_glb(wheel_obj, OUTPUT_GLB_PATH)


if __name__ == "__main__":
    main()
