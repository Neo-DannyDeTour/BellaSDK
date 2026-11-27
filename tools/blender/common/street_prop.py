"""Shared helpers for procedural domestic/street props (headless Blender + numpy/PIL).

One prop script = one `PropSpec` (regions + geometry callback). This module owns:
- 2048x2048 atlas (2x2 tiles of 1024) with ORM/albedo/normal generated from numpy noise
- `Builder`: bmesh primitives (box, cylinder, loft, quad) with per-face tile UVs
- GLB export, asset_manifest.json, ORMMaterial3D .tres and props/<slug>/<slug>.tscn

Texture stage runs under system python (`--gen-textures`); mesh stage runs in Blender.
"""

from __future__ import annotations

import json
import math
import random
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional

try:  # mathutils only exists inside Blender
    from mathutils import Matrix, Vector
except ImportError:  # pragma: no cover
    Matrix = Vector = None  # type: ignore

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
TEX_SIZE: int = 2048
TILE: int = 1024
DENS: float = 0.25  # uv units per meter inside a tile (tile = 2m)
INSET: float = 0.004
FONT_BOLD: str = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_COND: str = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"


@dataclass
class Region:
    """One 1024x1024 atlas tile: base material + optional PIL decal painter."""

    kind: str  # paint | steel | fabric | decal
    rgb: tuple[int, int, int]
    wear: float = 0.4
    rough: float = 0.6
    metal: float = 0.0
    nrm: float = 1.0
    decal: Optional[Callable[["object", "object"], None]] = None  # (PIL.Image, rng)


@dataclass
class PropSpec:
    """Everything the common pipeline needs to build one prop."""

    slug: str
    node_name: str
    mat_name: str
    ref_image: str
    target_h: float
    tri_budget: int
    regions: list[Region]
    build: Callable[["Builder"], None]
    script_path: Path
    body: str = "static"  # static | rigid
    # collision boxes in Godot axes: (name, size(x,y,z), pos(x,y,z))
    collision: list[tuple[str, tuple[float, float, float], tuple[float, float, float]]] = field(
        default_factory=list
    )
    mass: float = 5.0
    seed: int = 1

    @property
    def asset_dir(self) -> Path:
        return REPO_ROOT / "assets" / "models" / self.slug

    @property
    def tex_dir(self) -> Path:
        return self.asset_dir / "textures"


# --------------------------------------------------------------------------- rotations
def rx(deg: float) -> "Matrix":
    return Matrix.Rotation(math.radians(deg), 3, "X")


def ry(deg: float) -> "Matrix":
    return Matrix.Rotation(math.radians(deg), 3, "Y")


def rz(deg: float) -> "Matrix":
    return Matrix.Rotation(math.radians(deg), 3, "Z")


def rrect_ring(cx: float, cy: float, w: float, d: float, r: float, seg: int, z: float,
               shrink: float = 0.0, dy: float = 0.0) -> list:
    """CCW (from +Z) rounded-rect polygon at height z; `shrink` insets every side."""
    hw = w * 0.5 - shrink
    hd = d * 0.5 - shrink
    rr = max(min(r - shrink * 0.5, hw, hd), 0.004)
    corners = [(hw - rr, -(hd - rr), -90.0), (hw - rr, hd - rr, 0.0),
               (-(hw - rr), hd - rr, 90.0), (-(hw - rr), -(hd - rr), 180.0)]
    pts = []
    for ccx, ccy, a0 in corners:
        for k in range(seg + 1):
            a = math.radians(a0 + 90.0 * k / seg)
            pts.append(Vector((cx + ccx + rr * math.cos(a), cy + dy + ccy + rr * math.sin(a), z)))
    return pts


# --------------------------------------------------------------------------- mesh builder
_BOX_FACES = {
    "front": ((-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)),
    "back": ((1, 1, -1), (-1, 1, -1), (-1, 1, 1), (1, 1, 1)),
    "left": ((-1, 1, -1), (-1, -1, -1), (-1, -1, 1), (-1, 1, 1)),
    "right": ((1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)),
    "bottom": ((-1, -1, -1), (-1, 1, -1), (1, 1, -1), (1, -1, -1)),
    "top": ((-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)),
}
ALL_BUT_FRONT = ("back", "left", "right", "top", "bottom")


class Builder:
    """bmesh primitive builder; Blender axes: +Z up, front faces -Y."""

    def __init__(self, seed: int = 1) -> None:
        import bmesh

        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.rng = random.Random(seed)

    # -- uv helpers
    @staticmethod
    def tile_uv(region: int, u: float, v: float) -> tuple[float, float]:
        col, row = region % 2, region // 2
        return (col * 0.5 + INSET + u * (0.5 - 2 * INSET), row * 0.5 + INSET + v * (0.5 - 2 * INSET))

    def _face(self, verts: list, region: int, smooth: bool, frame: Optional[tuple],
              uv_rect: Optional[tuple]) -> None:
        face = self.bm.faces.new(verts)
        face.smooth = smooth
        pts = [v.co.copy() for v in verts]
        nrm = (pts[1] - pts[0]).cross(pts[2] - pts[0])
        if nrm.length < 1e-12 and len(pts) > 3:
            nrm = (pts[2] - pts[0]).cross(pts[3] - pts[0])
        if frame is not None:
            centre, rinv = frame
            pts = [rinv @ (p - centre) for p in pts]
            nrm = rinv @ nrm
        ax = max(range(3), key=lambda i: abs(nrm[i]))
        s = 1.0 if nrm[ax] >= 0 else -1.0
        if ax == 0:
            ab = [(s * p.y, p.z) for p in pts]
        elif ax == 1:
            ab = [(-s * p.x, p.z) for p in pts]
        else:
            ab = [(s * p.x, p.y) for p in pts]
        a_min, a_max = min(a for a, _ in ab), max(a for a, _ in ab)
        b_min, b_max = min(b for _, b in ab), max(b for _, b in ab)
        col, row = region % 2, region // 2
        if uv_rect is not None:
            u0, v0, u1, v1 = uv_rect
            da, db = max(a_max - a_min, 1e-9), max(b_max - b_min, 1e-9)
            uvs = [self.tile_uv(region, u0 + (a - a_min) / da * (u1 - u0),
                                v0 + (b - b_min) / db * (v1 - v0)) for a, b in ab]
        else:
            half = 0.25 - INSET
            ca, cb = 0.5 * (a_min + a_max), 0.5 * (b_min + b_max)
            ea, eb = 0.5 * (a_max - a_min) * DENS, 0.5 * (b_max - b_min) * DENS
            oa = self.rng.uniform(-1, 1) * max(half - ea, 0.0)
            ob = self.rng.uniform(-1, 1) * max(half - eb, 0.0)
            cu, cv = col * 0.5 + 0.25 + oa, row * 0.5 + 0.25 + ob
            lo_u, hi_u = col * 0.5 + INSET, col * 0.5 + 0.5 - INSET
            lo_v, hi_v = row * 0.5 + INSET, row * 0.5 + 0.5 - INSET
            uvs = [(min(max(cu + (a - ca) * DENS, lo_u), hi_u),
                    min(max(cv + (b - cb) * DENS, lo_v), hi_v)) for a, b in ab]
        for loop, uv in zip(face.loops, uvs):
            loop[self.uv].uv = uv

    # -- primitives
    def add_box(self, center, size, region: int, skip: tuple = (), rot=None,
                taper: tuple = (1.0, 1.0), uv_rects: Optional[dict] = None,
                smooth: bool = False) -> None:
        c = Vector(center)
        rm = rot.to_3x3() if rot is not None else Matrix.Identity(3)
        hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        cache: dict = {}

        def vert(key: tuple):
            if key not in cache:
                lx, ly, lz = key[0] * hx, key[1] * hy, key[2] * hz
                if key[2] > 0:
                    lx, ly = lx * taper[0], ly * taper[1]
                cache[key] = self.bm.verts.new(c + rm @ Vector((lx, ly, lz)))
            return cache[key]

        frame = (c, rm.inverted())
        for name, keys in _BOX_FACES.items():
            if name in skip:
                continue
            self._face([vert(k) for k in keys], region, smooth, frame,
                       (uv_rects or {}).get(name))

    def add_plate(self, center, size, region: int, uv_rect: Optional[tuple] = None) -> None:
        """Front-facing (-Y) single-sided plate, size = (w, thickness, h)."""
        self.add_box(center, size, region, skip=ALL_BUT_FRONT,
                     uv_rects={"front": uv_rect} if uv_rect else None)

    def add_cyl(self, center, r: float, length: float, region: int, segs: int = 8, rot=None,
                r_top: Optional[float] = None, smooth: bool = True,
                caps: tuple = (True, True)) -> None:
        c = Vector(center)
        rm = rot.to_3x3() if rot is not None else Matrix.Identity(3)
        rt = r if r_top is None else r_top

        def ring(rad: float, z: float) -> list:
            return [self.bm.verts.new(c + rm @ Vector((rad * math.cos(2 * math.pi * i / segs),
                                                         rad * math.sin(2 * math.pi * i / segs), z)))
                    for i in range(segs)]

        frame = (c, rm.inverted())
        bot, top = ring(r, -length * 0.5), ring(rt, length * 0.5)
        for i in range(segs):
            j = (i + 1) % segs
            self._face([bot[i], bot[j], top[j], top[i]], region, smooth, frame, None)
        if caps[1]:
            self._face(ring(rt, length * 0.5), region, False, frame, None)
        if caps[0]:
            self._face(list(reversed(ring(r, -length * 0.5))), region, False, frame, None)

    def add_loft(self, rings: list, region: int, caps: tuple = (True, True),
                 smooth: bool = False) -> None:
        """Skin CCW rings (list[list[Vector]], bottom -> top)."""
        vr = [[self.bm.verts.new(p) for p in ring] for ring in rings]
        n = len(rings[0])
        for k in range(len(rings) - 1):
            for i in range(n):
                j = (i + 1) % n
                self._face([vr[k][i], vr[k][j], vr[k + 1][j], vr[k + 1][i]], region, smooth, None, None)
        if caps[1]:
            self._face([self.bm.verts.new(p) for p in rings[-1]], region, False, None, None)
        if caps[0]:
            self._face([self.bm.verts.new(p) for p in reversed(rings[0])], region, False, None, None)

    def add_quad(self, pts: list, region: int, uvs: list) -> None:
        """Explicit quad/ngon; uvs are tile fractions (0..1) per point."""
        verts = [self.bm.verts.new(Vector(p)) for p in pts]
        face = self.bm.faces.new(verts)
        face.smooth = False
        for loop, (u, v) in zip(face.loops, uvs):
            loop[self.uv].uv = self.tile_uv(region, u, v)


# --------------------------------------------------------------------------- textures
def _fbm(rng, h: int, w: int, cells=(3, 8, 24, 96), weights=(0.45, 0.30, 0.15, 0.10)):
    import numpy as np
    from PIL import Image

    acc = np.zeros((h, w), dtype=np.float32)
    for c, wt in zip(cells, weights):
        g = rng.random((c, c)).astype(np.float32)
        acc += wt * np.asarray(Image.fromarray(g).resize((w, h), Image.Resampling.BICUBIC), dtype=np.float32)
    lo, hi = float(acc.min()), float(acc.max())
    return (acc - lo) / max(hi - lo, 1e-6)


def _streaks(rng, h: int, w: int, cy: int = 3, cx: int = 70):
    import numpy as np
    from PIL import Image

    g = rng.random((cy, cx)).astype(np.float32)
    a = np.asarray(Image.fromarray(g).resize((w, h), Image.Resampling.BICUBIC), dtype=np.float32)
    return (a - a.min()) / max(float(a.max() - a.min()), 1e-6)


def _paint_tile(reg: Region, rng):
    """Return albedo(H,W,3 float 0..255), rough, metal, ao, height arrays for one tile."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter

    h = w = TILE
    base = np.array(reg.rgb, dtype=np.float32)
    m1 = _fbm(rng, h, w)
    m2 = _fbm(rng, h, w, cells=(10, 40, 160, 320), weights=(0.3, 0.3, 0.25, 0.15))
    streak = _streaks(rng, h, w)
    dirt = np.clip((streak - 0.52) / 0.35, 0.0, 1.0) * 0.16

    if reg.kind == "fabric":
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        weave = (np.sin(xx * 2 * math.pi / 6.0) * np.sin(yy * 2 * math.pi / 6.0)) * 0.5 + 0.5
        stain = np.clip((0.46 - m1) / 0.28, 0.0, 1.0)
        alb = base[None, None, :] * (0.84 + 0.28 * m1 + 0.10 * (m2 - 0.5))[..., None]
        alb *= (0.91 + 0.09 * weave)[..., None]
        alb *= (1.0 - 0.24 * stain - dirt * 0.7)[..., None]
        rough = np.clip(reg.rough + 0.08 * (m2 - 0.5), 0.65, 1.0)
        metal = np.zeros((h, w), dtype=np.float32)
        ao = np.clip(0.84 + 0.16 * weave - 0.15 * stain, 0.55, 1.0)
        height = 0.7 * weave + 0.3 * m2
        return alb, rough, metal, ao, height

    chips = np.clip((m2 - (0.80 - 0.18 * reg.wear)) / 0.06, 0.0, 1.0)
    alb = base[None, None, :] * (0.80 + 0.40 * m1)[..., None] * (1.0 - dirt)[..., None]
    rust = np.where((m1 > 0.5)[..., None], np.array([78, 42, 24], np.float32),
                    np.array([120, 120, 124], np.float32))
    alb = alb * (1.0 - chips[..., None]) + rust * chips[..., None]

    scratch = Image.new("L", (w, h), 0)
    sd = ImageDraw.Draw(scratch)
    for _ in range(int(60 * reg.wear)):
        x0, y0 = rng.integers(0, w), rng.integers(0, h)
        ang = rng.uniform(0, math.pi)
        ln = rng.integers(20, 140)
        sd.line([(x0, y0), (x0 + ln * math.cos(ang), y0 + ln * math.sin(ang))], fill=int(rng.integers(90, 200)),
                width=int(rng.integers(1, 3)))
    sc = np.asarray(scratch.filter(ImageFilter.GaussianBlur(0.7)), dtype=np.float32) / 255.0
    alb = alb + sc[..., None] * (38.0 * reg.wear + 10.0)

    rough = np.clip(reg.rough + 0.30 * (m1 - 0.5) + 0.20 * chips - 0.12 * sc, 0.25, 0.95)
    metal = np.clip(reg.metal + chips * 0.7 + sc * 0.5 * reg.wear, 0.0, 1.0)
    ao = np.clip(0.90 + 0.10 * m2 - 0.30 * dirt, 0.5, 1.0)
    height = 0.5 * m2 + 0.3 * m1 - 0.6 * chips - 0.3 * sc
    return alb, rough, metal, ao, height


def generate_textures(spec: PropSpec) -> None:
    """Build albedo / normal / ORM atlas PNGs and the ORMMaterial3D .tres."""
    import numpy as np
    from PIL import Image

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr  # noqa: E402

    tex = spec.tex_dir
    tex.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(spec.seed)
    alb_a = np.zeros((TEX_SIZE, TEX_SIZE, 3), np.float32)
    nrm_a = np.zeros((TEX_SIZE, TEX_SIZE, 3), np.float32)
    rough_a = np.zeros((TEX_SIZE, TEX_SIZE), np.float32)
    metal_a = np.zeros((TEX_SIZE, TEX_SIZE), np.float32)
    ao_a = np.zeros((TEX_SIZE, TEX_SIZE), np.float32)

    regions = list(spec.regions)
    while len(regions) < 4:
        regions.append(regions[0])
    for idx, reg in enumerate(regions[:4]):
        col, row = idx % 2, idx // 2
        x0, y0 = col * TILE, (1 - row) * TILE  # tile row 0 = bottom half (V 0..0.5)
        alb, rough, metal, ao, height = _paint_tile(reg, rng)
        if reg.decal is not None:
            img = Image.fromarray(np.clip(alb, 0, 255).astype(np.uint8))
            reg.decal(img, rng)
            alb = np.asarray(img, dtype=np.float32)
        gy, gx = np.gradient(height)
        k = 14.0 * reg.nrm
        nx, ny, nz = -gx * k, gy * k, np.ones_like(height)
        ln = np.sqrt(nx * nx + ny * ny + nz * nz)
        nrm = np.stack([nx / ln, ny / ln, nz / ln], axis=-1) * 0.5 + 0.5
        sl = (slice(y0, y0 + TILE), slice(x0, x0 + TILE))
        alb_a[sl], nrm_a[sl] = np.clip(alb, 30, 240), nrm * 255.0
        rough_a[sl], metal_a[sl], ao_a[sl] = rough, metal, ao

    albedo_p = tex / f"{spec.slug}_albedo.png"
    normal_p = tex / f"{spec.slug}_normal.png"
    orm_p = tex / f"{spec.slug}_orm.png"
    Image.fromarray(alb_a.astype(np.uint8)).save(albedo_p)
    Image.fromarray(np.clip(nrm_a, 0, 255).astype(np.uint8)).save(normal_p)
    tmp = {}
    for name, arr in (("ao", ao_a), ("rough", rough_a), ("metal", metal_a)):
        tmp[name] = tex / f"_tmp_{name}.png"
        Image.fromarray(np.clip(arr * 255.0, 0, 255).astype(np.uint8), mode="L").save(tmp[name])
    process_pbr.pack_orm(tmp["ao"], tmp["rough"], str(tmp["metal"]), orm_p, target_size=(TEX_SIZE, TEX_SIZE))
    for p in tmp.values():
        p.unlink(missing_ok=True)
    process_pbr.generate_godot_tres(
        material_name=spec.mat_name, albedo_path=albedo_p, normal_path=normal_p, orm_path=orm_p,
        height_path=None, output_tres=spec.asset_dir / f"{spec.slug}.tres", triplanar=False)
    print(f"[Textures] {spec.slug}: albedo/normal/orm + .tres")


def font(path: str, size: int):
    from PIL import ImageFont

    return ImageFont.truetype(path, size)


# --------------------------------------------------------------------------- build / export
def _make_material(spec: PropSpec):
    import bpy

    tex = spec.tex_dir
    mat = bpy.data.materials.new(name=spec.mat_name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    def tex_node(suffix: str, cs: str):
        node = nt.nodes.new("ShaderNodeTexImage")
        img = bpy.data.images.load(str((tex / f"{spec.slug}_{suffix}.png").resolve()), check_existing=True)
        img.colorspace_settings.name = cs
        node.image = img
        return node

    nt.links.new(tex_node("albedo", "sRGB").outputs["Color"], bsdf.inputs["Base Color"])
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex_node("orm", "Non-Color").outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.inputs["Strength"].default_value = 0.85
    nt.links.new(tex_node("normal", "Non-Color").outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def _write_tscn(spec: PropSpec) -> Path:
    rigid = spec.body == "rigid"
    layer, mask, vis = (4, 7, 4) if rigid else (1, 0, 1)
    n = len(spec.collision)
    lines = [
        f"[gd_scene load_steps={3 + n} format=3]", "",
        f'[ext_resource type="PackedScene" path="res://assets/models/{spec.slug}/{spec.slug}.glb" id="1_glb"]',
        f'[ext_resource type="Material" path="res://assets/models/{spec.slug}/{spec.slug}.tres" id="2_mat"]', "",
    ]
    for i, (_, size, _) in enumerate(spec.collision):
        lines += [f'[sub_resource type="BoxShape3D" id="BoxShape3D_{i + 1}"]',
                  f"size = Vector3({size[0]}, {size[1]}, {size[2]})", ""]
    lines += [f'[node name="{spec.node_name}" type="{"RigidBody3D" if rigid else "StaticBody3D"}"]',
              f"collision_layer = {layer}", f"collision_mask = {mask}"]
    if rigid:
        lines.append(f"mass = {spec.mass}")
    lines += ["", '[node name="Model" parent="." instance=ExtResource("1_glb")]', "",
              f'[node name="{spec.node_name}" parent="Model" index="0"]',
              f"layers = {vis}", 'surface_material_override/0 = ExtResource("2_mat")', ""]
    for i, (name, _, pos) in enumerate(spec.collision):
        lines += [f'[node name="{name}" type="CollisionShape3D" parent="."]',
                  f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {pos[0]}, {pos[1]}, {pos[2]})",
                  f'shape = SubResource("BoxShape3D_{i + 1}")', ""]
    lines.append('[editable path="Model"]')
    path = REPO_ROOT / "props" / spec.slug / f"{spec.slug}.tscn"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def build_and_export(spec: PropSpec) -> None:
    """Build mesh in Blender, ground + scale to target height, export GLB + manifest + tscn."""
    import bpy

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    needed = [spec.tex_dir / f"{spec.slug}_{s}.png" for s in ("albedo", "normal", "orm")]
    if not all(p.is_file() for p in needed) or not (spec.asset_dir / f"{spec.slug}.tres").is_file():
        subprocess.run(["/usr/bin/python3", str(spec.script_path), "--gen-textures"], check=True)

    clean_scene()
    b = Builder(spec.seed)
    spec.build(b)
    mesh = bpy.data.meshes.new(spec.node_name)
    b.bm.to_mesh(mesh)
    b.bm.free()
    mesh.materials.append(_make_material(spec))
    obj = bpy.data.objects.new(spec.node_name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    min_z = min(v.co.z for v in mesh.vertices)
    height = max(v.co.z for v in mesh.vertices) - min_z
    k = spec.target_h / max(height, 1e-6)
    for v in mesh.vertices:
        v.co.x, v.co.y, v.co.z = v.co.x * k, v.co.y * k, (v.co.z - min_z) * k
    mesh.update()
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    xs, ys, zs = ([getattr(v.co, a) for v in mesh.vertices] for a in "xyz")
    dims = [round(max(xs) - min(xs), 4), round(max(zs) - min(zs), 4), round(max(ys) - min(ys), 4)]
    assert tris <= spec.tri_budget, f"{spec.slug}: {tris} tris > {spec.tri_budget}"
    export_godot_glb(spec.asset_dir / f"{spec.slug}.glb", export_animations=False, export_morph=False)

    layer = "Layer 3 Interactive" if spec.body == "rigid" else "Layer 1 Environment"
    manifest = {
        "prop_slug": spec.slug, "tri_count": tris, "tri_budget": spec.tri_budget,
        "uv_layers": len(mesh.uv_layers), "min_y": round(min(zs), 4), "dimensions_m": dims,
        "layer": layer, "target_layer": layer,
        "collision_hint": "Compound BoxShape3D" if len(spec.collision) > 1 else "BoxShape3D",
        "generator": "procedural_bpy", "ref_image": spec.ref_image, "reference_image": spec.ref_image,
        "material": f"res://assets/models/{spec.slug}/{spec.slug}.tres",
        "mesh": f"res://assets/models/{spec.slug}/{spec.slug}.glb",
    }
    (spec.asset_dir / "asset_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    _write_tscn(spec)
    print(f"[OK] {spec.slug}: tris={tris}/{spec.tri_budget}, dims_m={dims}, uv_layers={len(mesh.uv_layers)}")


def main(spec: PropSpec) -> None:
    """CLI entry: `--gen-textures` (system python) or Blender mesh build."""
    if "--gen-textures" in sys.argv:
        generate_textures(spec)
    else:
        build_and_export(spec)
