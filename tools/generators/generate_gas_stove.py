#!/usr/bin/env python3
"""Generates HL2-style low-poly gas_stove.glb and 256x256 texture atlas."""

import math
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
import trimesh


def generate_atlas(path: Path) -> Image.Image:
    """Generates procedural 256x256 texture atlas with enamel body and burner plate."""
    size: int = 256
    rng: np.random.Generator = np.random.default_rng(42)
    img: np.ndarray = np.zeros((size, size, 3), dtype=np.uint8)

    # Top half (y: 0..128) = Side/Body dirty cream enamel with vertical streaks
    base_cream: np.ndarray = np.array([205, 198, 178], dtype=np.float32)
    streak_noise: np.ndarray = rng.normal(0.0, 12.0, (1, size, 1))
    fine_noise: np.ndarray = rng.normal(0.0, 8.0, (128, size, 3))

    y_grad: np.ndarray = np.linspace(0.0, 1.0, 128).reshape(128, 1, 1)
    edge_grime: np.ndarray = np.clip(np.abs(y_grad - 0.5) * 2.0, 0.0, 1.0) ** 2.2
    rust_tint: np.ndarray = np.array([75, 55, 38], dtype=np.float32)

    body_tex: np.ndarray = base_cream + streak_noise + fine_noise
    body_tex = body_tex * (1.0 - edge_grime * 0.65) + rust_tint * (edge_grime * 0.65)
    img[0:128, :, :] = np.clip(body_tex, 0, 255).astype(np.uint8)

    # Bottom half (y: 128..256) = Top dark rusted cast-iron plate + 4 octagonal burners
    base_iron: np.ndarray = np.array([38, 30, 24], dtype=np.float32)
    rust_patch: np.ndarray = rng.normal(0.0, 10.0, (128, size, 3))
    rust_patch[:, :, 0] += 8.0
    top_tex: np.ndarray = np.clip(base_iron + rust_patch, 15, 85).astype(np.uint8)
    img[128:256, :, :] = top_tex

    pil_img: Image.Image = Image.fromarray(img, mode="RGB")
    draw: ImageDraw.ImageDraw = ImageDraw.Draw(pil_img)

    # Draw 4 octagonal grey burner rings + dark center holes in bottom-half UV space
    # UV y: 0.0..0.5 maps to pixel y: 128..256
    burner_centers: list[tuple[int, int]] = [
        (72, 162),
        (184, 162),
        (72, 222),
        (184, 222),
    ]
    outer_r: float = 22.0
    inner_r: float = 9.0

    for cx, cy in burner_centers:
        outer_pts: list[tuple[float, float]] = []
        inner_pts: list[tuple[float, float]] = []
        for i in range(8):
            angle: float = i * (math.pi / 4.0) + (math.pi / 8.0)
            outer_pts.append((cx + math.cos(angle) * outer_r, cy + math.sin(angle) * outer_r))
            inner_pts.append((cx + math.cos(angle) * inner_r, cy + math.sin(angle) * inner_r))
        draw.polygon(outer_pts, fill=(96, 94, 88), outline=(55, 45, 38))
        draw.polygon(inner_pts, fill=(24, 20, 18))

    path.parent.mkdir(parents=True, exist_ok=True)
    pil_img.save(str(path))
    return pil_img


def create_box_part(
    extents: tuple[float, float, float],
    center_y: float,
    uv_side_range: tuple[float, float, float, float],
    uv_top_range: tuple[float, float, float, float],
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Generates explicit vertices, triangles, and unshared UV coordinates for a box part."""
    hx, hy, hz = extents[0] * 0.5, extents[1] * 0.5, extents[2] * 0.5
    y0, y1 = center_y - hy, center_y + hy

    # 6 faces, 4 verts each (24 verts total for crisp UVs and hard normals)
    faces_verts: list[list[list[float]]] = [
        # Front (+Z)
        [[-hx, y0, hz], [hx, y0, hz], [hx, y1, hz], [-hx, y1, hz]],
        # Back (-Z)
        [[hx, y0, -hz], [-hx, y0, -hz], [-hx, y1, -hz], [hx, y1, -hz]],
        # Right (+X)
        [[hx, y0, hz], [hx, y0, -hz], [hx, y1, -hz], [hx, y1, hz]],
        # Left (-X)
        [[-hx, y0, -hz], [-hx, y0, hz], [-hx, y1, hz], [-hx, y1, -hz]],
        # Top (+Y)
        [[-hx, y1, hz], [hx, y1, hz], [hx, y1, -hz], [-hx, y1, -hz]],
        # Bottom (-Y)
        [[-hx, y0, -hz], [hx, y0, -hz], [hx, y0, hz], [-hx, y0, hz]],
    ]

    su0, sv0, su1, sv1 = uv_side_range
    tu0, tv0, tu1, tv1 = uv_top_range

    verts: list[list[float]] = []
    uvs: list[list[float]] = []
    tris: list[list[int]] = []

    for f_idx, f_v in enumerate(faces_verts):
        base: int = f_idx * 4
        verts.extend(f_v)
        if f_idx == 4:
            uvs.extend([[tu0, tv0], [tu1, tv0], [tu1, tv1], [tu0, tv1]])
        else:
            uvs.extend([[su0, sv0], [su1, sv0], [su1, sv1], [su0, sv1]])
        tris.extend([[base, base + 1, base + 2], [base, base + 2, base + 3]])

    return (
        np.array(verts, dtype=np.float32),
        np.array(tris, dtype=np.int32),
        np.array(uvs, dtype=np.float32),
    )


def build_stove_glb(
    glb_path: Path = Path("assets/props/gas_stove/gas_stove.glb"),
    albedo_path: Path = Path("assets/props/gas_stove/gas_stove_albedo.png"),
) -> None:
    """Combines 3 box components into low-poly stove mesh and exports GLB."""
    glb_path.parent.mkdir(parents=True, exist_ok=True)
    tex: Image.Image = generate_atlas(albedo_path)

    # Total height = 0.78m, centered at Y=0 (-0.39 to +0.39)
    # 1. Bottom dark recessed plinth: 0.82 x 0.03 x 0.52
    v1, t1, u1 = create_box_part(
        (0.82, 0.03, 0.52), -0.375, (0.05, 0.05, 0.25, 0.25), (0.05, 0.05, 0.25, 0.25)
    )
    # 2. Main white/grime body: 0.83 x 0.72 x 0.53
    v2, t2, u2 = create_box_part(
        (0.83, 0.72, 0.53), 0.0, (0.0, 0.52, 1.0, 0.98), (0.05, 0.05, 0.25, 0.25)
    )
    # 3. Top overhanging cast-iron hob: 0.85 x 0.03 x 0.55
    v3, t3, u3 = create_box_part(
        (0.85, 0.03, 0.55), 0.375, (0.05, 0.05, 0.25, 0.25), (0.0, 0.0, 1.0, 0.48)
    )

    verts: np.ndarray = np.vstack([v1, v2, v3])
    tris: np.ndarray = np.vstack([t1, t2 + len(v1), t3 + len(v1) + len(v2)])
    uvs: np.ndarray = np.vstack([u1, u2, u3])

    visual: trimesh.visual.TextureVisuals = trimesh.visual.TextureVisuals(uv=uvs, image=tex)
    mesh: trimesh.Trimesh = trimesh.Trimesh(
        vertices=verts, faces=tris, visual=visual, process=False
    )
    mesh.export(str(glb_path))
    print(f"Exported {glb_path} ({len(tris)} tris) and {albedo_path}")


if __name__ == "__main__":
    build_stove_glb()
