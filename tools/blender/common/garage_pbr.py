"""Shared PBR texture loader, 2.5mm bevel helper, and metric box UV utility for Old Garage models."""

from __future__ import annotations

import math
from pathlib import Path
import bmesh
import bpy

from common.materials import create_pbr_material

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
MATERIALS_DIR: Path = REPO_ROOT / "assets" / "materials"


def _load_img(path: Path, non_color: bool = False) -> bpy.types.Image | None:
    if not path.is_file():
        return None
    img = bpy.data.images.load(str(path.resolve()), check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def load_project_pbr(
    slug: str,
    mat_name: str | None = None,
    metallic_fallback: float = 0.0,
    roughness_fallback: float = 0.65,
    normal_strength: float = 0.85,
    base_tint: tuple[float, float, float, float] = (1.0, 1.0, 1.0, 1.0),
) -> bpy.types.Material:
    """Load an existing BellaSDK PBR texture set from assets/materials/<slug>/textures/."""
    tex_dir = MATERIALS_DIR / slug / "textures"
    albedo = _load_img(tex_dir / f"{slug}_albedo.png", non_color=False)
    rough = _load_img(tex_dir / f"{slug}_roughness.png", non_color=True)
    normal = _load_img(tex_dir / f"{slug}_normal.png", non_color=True)
    metallic_img = _load_img(tex_dir / f"{slug}_metallic.png", non_color=True)

    resolved_name = mat_name or f"M_{slug}"
    mat = create_pbr_material(
        name=resolved_name,
        base_color=base_tint,
        metallic=1.0 if metallic_img is not None else metallic_fallback,
        roughness=1.0 if rough is not None else roughness_fallback,
        base_color_image=albedo,
        roughness_image=rough,
        normal_image=normal,
        normal_strength=normal_strength,
    )

    if metallic_img is not None and mat.use_nodes:
        tree = mat.node_tree
        bsdf = tree.nodes.get("Principled BSDF")
        if bsdf is not None and "Metallic" in bsdf.inputs:
            m_node = tree.nodes.new("ShaderNodeTexImage")
            m_node.image = metallic_img
            m_node.image.colorspace_settings.name = "Non-Color"
            m_node.location = (-400, 150)
            tree.links.new(m_node.outputs["Color"], bsdf.inputs["Metallic"])

    return mat


def bevel_sharp_edges(
    bm: bmesh.types.BMesh,
    offset: float = 0.0025,
    angle_deg: float = 35.0,
) -> None:
    """Chamfer sharp hard-surface edges (>= angle_deg) so specular rim highlights read cleanly."""
    thresh = math.radians(angle_deg)
    edges: list[bmesh.types.BMEdge] = []
    for e in bm.edges:
        if len(e.link_faces) == 2:
            if e.calc_face_angle(0.0) >= thresh:
                edges.append(e)
    if not edges:
        return
    bmesh.ops.bevel(
        bm,
        geom=edges,
        offset=offset,
        offset_type="OFFSET",
        segments=1,
        profile=0.5,
        affect="EDGES",
        clamp_overlap=True,
    )


def apply_metric_box_uv(obj: bpy.types.Object, tiles_per_m: float = 1.0) -> None:
    """Assign clean metric box UVs aligned to dominant face normals."""
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in f.loops:
            co = loop.vert.co * tiles_per_m
            if az >= ax and az >= ay:
                loop[uv].uv = (co.x, co.y)
            elif ay >= ax and ay >= az:
                loop[uv].uv = (co.x, co.z)
            else:
                loop[uv].uv = (co.y, co.z)
    bm.to_mesh(mesh)
    bm.free()
