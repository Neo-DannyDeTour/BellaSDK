"""Shared helpers for procedural domestic props (textures, bmesh kit, GLB, manifest, tscn).

Each prop script in tools/blender/props/ defines a config dict plus a build function and calls
[method run_prop]. Texture mode uses numpy/PIL only (no bpy). Mesh mode needs Blender.

Atlas layout (2048x2048, 4 regions, each 1024x1024):
    region 0 = lower-left, 1 = lower-right, 2 = upper-left, 3 = upper-right (image space).
"""

from __future__ import annotations

import json
import math
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
TEX_SIZE: int = 2048
SHARP_ANGLE: float = math.radians(35.0)


# ---------------------------------------------------------------------------
# Pure-python ring helpers (CCW seen from +Z)
# ---------------------------------------------------------------------------
def rrect(cx: float, cy: float, z: float, w: float, d: float, r: float, n: int = 4) -> list:
    """Return CCW rounded-rectangle ring points (4 * n points) at height z."""
    r = max(0.004, min(r, w * 0.5 - 1e-4, d * 0.5 - 1e-4))
    pts: list = []
    for sx, sy, a0 in ((1, 1, 0.0), (-1, 1, 90.0), (-1, -1, 180.0), (1, -1, 270.0)):
        ccx = cx + sx * (w * 0.5 - r)
        ccy = cy + sy * (d * 0.5 - r)
        for k in range(n):
            a = math.radians(a0 + 90.0 * k / (n - 1))
            pts.append((ccx + r * math.cos(a), ccy + r * math.sin(a), z))
    return pts


def ellipse(
    cx: float, cy: float, z: float, w: float, d: float, n: int = 20, power: float = 2.0
) -> list:
    """Return CCW super-ellipse ring points at height z (power 2 = ellipse)."""
    pts: list = []
    e = 2.0 / power
    for k in range(n):
        t = 2.0 * math.pi * k / n
        c, s = math.cos(t), math.sin(t)
        x = math.copysign(abs(c) ** e, c) * w * 0.5
        y = math.copysign(abs(s) ** e, s) * d * 0.5
        pts.append((cx + x, cy + y, z))
    return pts


def arc_path(
    center: tuple, radius: float, a0: float, a1: float, n: int, plane: str = "xz"
) -> list:
    """Return n points on an arc (degrees) in the xz or yz plane around center."""
    out: list = []
    for k in range(n):
        a = math.radians(a0 + (a1 - a0) * k / (n - 1))
        u, v = radius * math.cos(a), radius * math.sin(a)
        if plane == "xz":
            out.append((center[0] + u, center[1], center[2] + v))
        else:
            out.append((center[0], center[1] + u, center[2] + v))
    return out


# ---------------------------------------------------------------------------
# Texture atlas (numpy + PIL)
# ---------------------------------------------------------------------------
def _smoothstep(np: Any, a: float, b: float, x: Any) -> Any:
    t = np.clip((x - a) / max(b - a, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _noise(np: Any, image_cls: Any, rng: Any, size: int, cy: int, cx: int) -> Any:
    grid = rng.random((cy + 1, cx + 1)).astype(np.float32)
    img = image_cls.fromarray(grid, mode="F").resize((size, size), image_cls.Resampling.BICUBIC)
    return np.clip(np.asarray(img, dtype=np.float32), 0.0, 1.0)


def _fbm(np: Any, image_cls: Any, rng: Any, size: int, base: int, octaves: int) -> Any:
    total = np.zeros((size, size), dtype=np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        cells = base * (2**o)
        total += amp * _noise(np, image_cls, rng, size, cells, cells)
        norm += amp
        amp *= 0.5
    total /= norm
    lo, hi = float(total.min()), float(total.max())
    return (total - lo) / max(hi - lo, 1e-6)


def _region_maps(spec: dict, rng: Any, size: int, np: Any, image_cls: Any) -> dict:
    low = _fbm(np, image_cls, rng, size, 3, 4)
    mid = _fbm(np, image_cls, rng, size, 10, 4)
    hi = _fbm(np, image_cls, rng, size, 48, 3)

    base = np.array(spec["base"], dtype=np.float32)
    var = float(spec.get("var", 0.08))
    alb = base[None, None, :] * (1.0 + var * (low - 0.5) * 2.0)[..., None]
    alb *= (1.0 + 0.05 * (hi - 0.5))[..., None]

    grime = float(spec.get("grime", 0.0))
    gmask = _smoothstep(np, 0.45, 0.88, 0.65 * low + 0.35 * mid) * grime
    grime_tint = np.array([0.88, 0.82, 0.68], dtype=np.float32)
    alb *= (1.0 - 0.42 * gmask)[..., None] * (1.0 - gmask[..., None] * (1.0 - grime_tint))

    rust = float(spec.get("rust", 0.0))
    rmask = np.zeros((size, size), dtype=np.float32)
    if rust > 0.0:
        field = 0.55 * mid + 0.45 * hi
        rmask = _smoothstep(np, 0.80 - 0.28 * rust, 0.92 - 0.28 * rust, field) * min(1.0, rust * 2.5)
        rust_col = np.array([118.0, 62.0, 32.0], dtype=np.float32)
        rust_tex = rust_col[None, None, :] * (0.70 + 0.5 * hi)[..., None]
        alb = alb * (1.0 - rmask[..., None]) + rust_tex * rmask[..., None]

    rough = float(spec.get("rough", 0.5)) + float(spec.get("rough_var", 0.06)) * (hi - 0.5) * 2.0
    rough = rough + 0.20 * gmask + 0.32 * rmask
    metal = float(spec.get("metal", 0.0)) * (1.0 - 0.85 * rmask)
    ao = np.clip(0.97 - 0.20 * gmask - 0.18 * rmask - 0.06 * (1.0 - mid), 0.60, 1.0)

    height = 0.35 * mid + 0.65 * hi + 0.30 * rmask
    k = float(spec.get("normal", 2.2))
    gy, gx = np.gradient(height)
    nrm = np.stack([-gx * k, gy * k, np.ones_like(height)], axis=-1)
    nrm /= np.sqrt(np.sum(nrm * nrm, axis=-1, keepdims=True))
    return {"alb": alb, "rough": rough, "metal": metal, "ao": ao, "nrm": nrm}


def generate_atlas(
    cfg: dict, painter: Callable[[int, dict, int], None] | None = None
) -> None:
    """Write albedo/normal/ORM atlas PNGs plus the ORMMaterial3D .tres for a prop."""
    import numpy as np
    from PIL import Image

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr  # noqa: E402

    paths = _paths(cfg)
    paths["tex_dir"].mkdir(parents=True, exist_ok=True)
    half = TEX_SIZE // 2
    rng = np.random.default_rng(int(cfg.get("seed", 7)))

    alb_f = np.zeros((TEX_SIZE, TEX_SIZE, 3), dtype=np.float32)
    nrm_f = np.zeros((TEX_SIZE, TEX_SIZE, 3), dtype=np.float32)
    rough_f = np.zeros((TEX_SIZE, TEX_SIZE), dtype=np.float32)
    metal_f = np.zeros((TEX_SIZE, TEX_SIZE), dtype=np.float32)
    ao_f = np.zeros((TEX_SIZE, TEX_SIZE), dtype=np.float32)

    for idx, spec in enumerate(cfg["regions"]):
        maps = _region_maps(spec, rng, half, np, Image)
        if painter is not None:
            painter(idx, maps, half)
        r0 = (1 - idx // 2) * half
        c0 = (idx % 2) * half
        sl = (slice(r0, r0 + half), slice(c0, c0 + half))
        alb_f[sl] = maps["alb"]
        nrm_f[sl] = maps["nrm"]
        rough_f[sl] = maps["rough"]
        metal_f[sl] = maps["metal"]
        ao_f[sl] = maps["ao"]

    Image.fromarray(np.clip(alb_f, 30.0, 240.0).astype(np.uint8), mode="RGB").save(
        paths["albedo"], format="PNG"
    )
    nrm_u8 = np.clip((nrm_f * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    Image.fromarray(nrm_u8, mode="RGB").save(paths["normal"], format="PNG")

    tmp = {k: paths["tex_dir"] / f"_tmp_{k}.png" for k in ("ao", "rough", "metal")}
    for key, arr in (("ao", ao_f), ("rough", np.clip(rough_f, 0.06, 0.95)), ("metal", metal_f)):
        Image.fromarray(np.clip(arr * 255.0, 0, 255).astype(np.uint8), mode="L").save(tmp[key])
    process_pbr.pack_orm(
        tmp["ao"], tmp["rough"], str(tmp["metal"]), paths["orm"], target_size=(TEX_SIZE, TEX_SIZE)
    )
    for p in tmp.values():
        p.unlink(missing_ok=True)

    process_pbr.generate_godot_tres(
        material_name=cfg["mat_name"],
        albedo_path=paths["albedo"],
        normal_path=paths["normal"],
        orm_path=paths["orm"],
        height_path=None,
        output_tres=paths["tres"],
        triplanar=False,
    )
    print(f"[Textures] {cfg['slug']} atlas + {paths['tres'].name} written")


def _paths(cfg: dict) -> dict:
    slug: str = cfg["slug"]
    asset_dir = REPO_ROOT / "assets" / "models" / slug
    tex_dir = asset_dir / "textures"
    return {
        "asset_dir": asset_dir,
        "tex_dir": tex_dir,
        "glb": asset_dir / f"{slug}.glb",
        "tres": asset_dir / f"{slug}.tres",
        "manifest": asset_dir / "asset_manifest.json",
        "albedo": tex_dir / f"{slug}_albedo.png",
        "normal": tex_dir / f"{slug}_normal.png",
        "orm": tex_dir / f"{slug}_orm.png",
        "tscn": REPO_ROOT / "props" / slug / f"{slug}.tscn",
    }


# ---------------------------------------------------------------------------
# bmesh kit
# ---------------------------------------------------------------------------
class Kit:
    """Thin bmesh builder: lofts, tubes, boxes, cylinders tagged by atlas region."""

    def __init__(self) -> None:
        import bmesh

        self.bmesh = bmesh
        self.bm = bmesh.new()

    def loft(self, rings: list, region: Any, cap_start: bool = True, cap_end: bool = True) -> None:
        """Skin equal-length CCW rings into a closed solid; region may be a per-strip list."""
        bm = self.bm
        vr = [[bm.verts.new(p) for p in ring] for ring in rings]
        n = len(rings[0])
        for k in range(len(rings) - 1):
            reg = region[k] if isinstance(region, (list, tuple)) else region
            for i in range(n):
                j = (i + 1) % n
                f = bm.faces.new((vr[k][i], vr[k][j], vr[k + 1][j], vr[k + 1][i]))
                f.material_index = reg
        first = region[0] if isinstance(region, (list, tuple)) else region
        last = region[-1] if isinstance(region, (list, tuple)) else region
        if cap_start:
            bm.faces.new(list(reversed(vr[0]))).material_index = first
        if cap_end:
            bm.faces.new(vr[-1]).material_index = last

    def tube(self, pts: list, radius: Any, segs: int, region: int, cap: bool = True) -> None:
        """Sweep a circle along a polyline using parallel-transport frames."""
        from mathutils import Vector

        path = [Vector(p) for p in pts]
        tans = []
        for i in range(len(path)):
            a = path[max(i - 1, 0)]
            b = path[min(i + 1, len(path) - 1)]
            tans.append((b - a).normalized())
        ref = Vector((0, 0, 1)) if abs(tans[0].z) < 0.9 else Vector((1, 0, 0))
        nrm = tans[0].cross(ref).normalized()
        rings: list = []
        for i, p in enumerate(path):
            if i > 0:
                nrm = (nrm - tans[i] * nrm.dot(tans[i])).normalized()
            bino = tans[i].cross(nrm)
            r = radius[i] if isinstance(radius, (list, tuple)) else radius
            ring = []
            for k in range(segs):
                t = 2.0 * math.pi * k / segs
                q = p + (nrm * math.cos(t) + bino * math.sin(t)) * r
                ring.append((q.x, q.y, q.z))
            rings.append(ring)
        self.loft(rings, region, cap, cap)

    def box(self, center: tuple, size: tuple, region: int, bevel: float = 0.0) -> None:
        """Add an axis-aligned box, optionally with a 1-segment bevel."""
        from mathutils import Matrix, Vector

        bmesh = self.bmesh
        before = set(self.bm.faces)
        ret = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = ret["verts"]
        xf = Matrix.Translation(Vector(center)) @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
        bmesh.ops.transform(self.bm, matrix=xf, verts=verts)
        if bevel > 0.0:
            vset = set(verts)
            edges = [e for e in self.bm.edges if all(v in vset for v in e.verts)]
            bmesh.ops.bevel(
                self.bm,
                geom=edges,
                offset=bevel,
                offset_type="OFFSET",
                segments=1,
                profile=0.5,
                affect="EDGES",
                clamp_overlap=True,
            )
        for f in self.bm.faces:
            if f not in before:
                f.material_index = region

    def cyl(
        self,
        center: tuple,
        axis: tuple,
        radius: float,
        depth: float,
        segs: int,
        region: int,
        radius2: float | None = None,
    ) -> None:
        """Add a capped cylinder/cone along axis."""
        from mathutils import Matrix, Vector

        bmesh = self.bmesh
        before = set(self.bm.faces)
        rot = Vector((0.0, 0.0, 1.0)).rotation_difference(Vector(axis).normalized())
        mat = Matrix.Translation(Vector(center)) @ rot.to_matrix().to_4x4()
        bmesh.ops.create_cone(
            self.bm,
            cap_ends=True,
            cap_tris=False,
            segments=segs,
            radius1=radius,
            radius2=radius if radius2 is None else radius2,
            depth=depth,
            matrix=mat,
        )
        for f in self.bm.faces:
            if f not in before:
                f.material_index = region


# ---------------------------------------------------------------------------
# Build + export
# ---------------------------------------------------------------------------
def _unwrap_regions(mesh: Any, region_ids: list) -> None:
    import bpy

    mesh.uv_layers.new(name="UVMap")
    for rid in region_ids:
        if not any(p.material_index == rid for p in mesh.polygons):
            continue
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_mode(type="FACE")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.object.mode_set(mode="OBJECT")
        for p in mesh.polygons:
            if p.material_index == rid:
                p.select = True
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.015)
        bpy.ops.object.mode_set(mode="OBJECT")

        uv = mesh.uv_layers.active.data
        polys = [p for p in mesh.polygons if p.material_index == rid]
        us = [uv[li].uv.x for p in polys for li in p.loop_indices]
        vs = [uv[li].uv.y for p in polys for li in p.loop_indices]
        if not us or not vs:
            continue
        u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
        du, dv = max(u1 - u0, 1e-6), max(v1 - v0, 1e-6)
        qu = 0.015 + 0.5 * (rid % 2)
        qv = 0.015 + 0.5 * (rid // 2)
        for p in polys:
            for li in p.loop_indices:
                c = uv[li].uv
                c.x = qu + (c.x - u0) / du * 0.47
                c.y = qv + (c.y - v0) / dv * 0.47


def _make_material(cfg: dict, paths: dict) -> Any:
    import bpy

    mat = bpy.data.materials.new(name=cfg["mat_name"])
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    def img_node(path: Path, srgb: bool) -> Any:
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = bpy.data.images.load(str(path.resolve()), check_existing=True)
        node.image.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
        return node

    alb = img_node(paths["albedo"], True)
    nt.links.new(alb.outputs["Color"], bsdf.inputs["Base Color"])
    orm = img_node(paths["orm"], False)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    nrm = img_node(paths["normal"], False)
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.inputs["Strength"].default_value = 0.85
    nt.links.new(nrm.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def _write_tscn(cfg: dict, paths: dict, dims: list) -> None:
    slug, node = cfg["slug"], cfg["node_name"]
    rigid = cfg["body"] == "rigid"
    body = "RigidBody3D" if rigid else "StaticBody3D"
    layer, mask = (4, 7) if rigid else (1, 0)
    lines = [
        "[gd_scene load_steps=4 format=3]",
        "",
        f'[ext_resource type="PackedScene" path="res://assets/models/{slug}/{slug}.glb" id="1_glb"]',
        f'[ext_resource type="Material" path="res://assets/models/{slug}/{slug}.tres" id="2_mat"]',
        "",
        '[sub_resource type="BoxShape3D" id="BoxShape3D_1"]',
        f"size = Vector3({dims[0]}, {dims[1]}, {dims[2]})",
        "",
        f'[node name="{node}" type="{body}"]',
        f"collision_layer = {layer}",
        f"collision_mask = {mask}",
    ]
    if rigid:
        lines.append(f"mass = {cfg.get('mass', 5.0)}")
    lines += [
        "",
        '[node name="Model" parent="." instance=ExtResource("1_glb")]',
        "",
        f'[node name="{node}" parent="Model" index="0"]',
        f"layers = {4 if rigid else 1}",
        'surface_material_override/0 = ExtResource("2_mat")',
        "",
        '[node name="CollisionShape3D" type="CollisionShape3D" parent="."]',
        f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.0, {round(dims[1] / 2.0, 4)}, 0.0)",
        'shape = SubResource("BoxShape3D_1")',
        "",
        '[editable path="Model"]',
        "",
    ]
    paths["tscn"].parent.mkdir(parents=True, exist_ok=True)
    paths["tscn"].write_text("\n".join(lines), encoding="utf-8")


def build_and_export(cfg: dict, build_fn: Callable[[Kit], None]) -> None:
    """Run build_fn, finalize mesh, UV-map, bake to meters, export GLB + manifest + tscn."""
    import bpy

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    paths = _paths(cfg)
    if not all(paths[k].is_file() for k in ("albedo", "normal", "orm", "tres")):
        subprocess.run(
            ["/usr/bin/python3", str(Path(cfg["script"]).resolve()), "--gen-textures"], check=True
        )
    clean_scene()
    kit = Kit()
    build_fn(kit)
    bm = kit.bm
    kit.bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if len(e.link_faces) != 2 or e.calc_face_angle(0.0) > SHARP_ANGLE:
            e.smooth = False

    name = cfg["node_name"]
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    n_regions = len(cfg["regions"])
    for r in range(n_regions):
        mesh.materials.append(bpy.data.materials.new(name=f"_region_{r}"))
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    _unwrap_regions(mesh, list(range(n_regions)))

    for p in mesh.polygons:
        p.material_index = 0
    mesh.materials.clear()
    mesh.materials.append(_make_material(cfg, paths))

    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    cx, cy, z0 = 0.5 * (min(xs) + max(xs)), 0.5 * (min(ys) + max(ys)), min(zs)
    for v in mesh.vertices:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= z0
    mesh.update()
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    tri_count = sum(len(p.vertices) - 2 for p in mesh.polygons)
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    dims = [
        round(max(xs) - min(xs), 4),
        round(max(zs) - min(zs), 4),
        round(max(ys) - min(ys), 4),
    ]
    assert tri_count <= cfg["tri_budget"], f"tri budget {tri_count}>{cfg['tri_budget']}"
    export_godot_glb(paths["glb"], export_animations=False, export_morph=False)

    layer = "Layer 3 Interactive" if cfg["body"] == "rigid" else "Layer 1 Environment"
    slug = cfg["slug"]
    manifest = {
        "prop_slug": slug,
        "tri_count": tri_count,
        "tri_budget": cfg["tri_budget"],
        "uv_layers": len(mesh.uv_layers),
        "min_y": round(min(zs), 4),
        "dimensions_m": dims,
        "layer": layer,
        "target_layer": layer,
        "collision_hint": "BoxShape3D",
        "generator": "procedural_bpy",
        "ref_image": cfg["ref_image"],
        "reference_image": cfg["ref_image"],
        "material": f"res://assets/models/{slug}/{slug}.tres",
        "mesh": f"res://assets/models/{slug}/{slug}.glb",
    }
    paths["manifest"].write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    _write_tscn(cfg, paths, dims)
    print(f"[OK] {slug}: tris={tri_count}/{cfg['tri_budget']} dims_m={dims} uv={len(mesh.uv_layers)}")


def run_prop(
    cfg: dict,
    build_fn: Callable[[Kit], None],
    painter: Callable[[int, dict, int], None] | None = None,
) -> None:
    """Entry point: '--gen-textures' writes the atlas, otherwise build the mesh in Blender."""
    if "--gen-textures" in sys.argv:
        generate_atlas(cfg, painter)
    else:
        build_and_export(cfg, build_fn)
