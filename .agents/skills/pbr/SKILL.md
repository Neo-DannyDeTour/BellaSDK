---
name: pbr
description: Generates seamless PBR materials (Albedo, Normal, Roughness, Height, AO) and Godot 4 ORMMaterial3D resources via Poly Haven CC0 lookup or flat-lit synthesis, seam verification, ORM channel packing, and 3D shader-ball QA.
metadata:
  icon: texture
---

# PBR Material Generator Skill (`/pbr`)

Generates tileable, physically grounded Godot 4 `ORMMaterial3D` materials without perspective warp, baked shadows, macro-tiling checkerboard, or misaligned AI normal maps.

## Activation
- Slash command: `/pbr`
- Mention: `@pbr`
- Prompt: `create pbr material`, `generate seamless pbr`, `pbr craft`

---

## Execution Tier & Swarm Policy
- **Solo (Default — 1 material)**: 1 agent runs phases + inspects offset wrap and 3D shader-ball QA sheet.
- **Swarm — Material Pack / Biome Set (`>= 3` materials)**:
  - Spawn parallel headless `builder-1..N` (1 material slug per worker) + 1 `critic` (audits `*_offset.png` seam checks and `render_qa_sheet.py pbr` shader-ball renders for macro-tiling repetition, plastic roughness, and value consistency across the set).

---

## Phase 0: CC0 Scan Check First (Blender MCP)
For standard real-world materials (concrete, brick, plaster, asphalt, wood planks, rusted metal), check **Poly Haven** via Blender MCP `search_assets` before generating synthetic textures. Real photogrammetry scans have accurate normal/roughness/AO alignment. Proceed to Phase 1 only when a custom surface or art-directed look is needed.

---

## Phase 1: Tight Surface Grilling (1 Round)
Ask 1 tight round with recommended defaults before generating images:
1. **Taxonomy & Physical Span**: Exact surface + real-world tile size (default: `2m x 2m`, e.g., `weathered post-Soviet poured concrete slab with hairline cracks`).
2. **Material Preset**: `stone | plaster | wood | metal | fabric | wet` (controls roughness curve & normal relief).
3. **Mixed-Material Check**: Single material type vs mixed dielectric+metal (e.g., chipped paint over bare steel — requires explicit metallic mask in Phase 5).
4. **Shader Mode**: Standard UV (`uv1_scale`) vs `uv1_triplanar` (for walls/floors/terrain — disables heightmap automatically to prevent shader errors).

Wait for confirmation before Phase 2.

---

## Phase 2: Seamless Flat-Lit Albedo Generation

### Anti-Slop Albedo Rules
- **NEVER** accept angled camera perspective, directional sunlight shadows, lens vignette, or high-contrast blown highlights/pure black crevices.
- **Keep sRGB values in physical PBR bounds** (`30–240` sRGB; `process_pbr.py --delight` enforces this).
- **Avoid img2img map hallucination**: Do NOT prompt `image-generator` for `"Generate a normal map"` or `"Generate roughness map"` — diffusion generators misalign pixels and produce noisy normal artifacts. Derive companion maps deterministically in Phase 4 (or bake/mask in Blender for mixed materials).

### Prompt Template A — `image-generator` (Natural-Language Seamless Ortho)
```text
Seamless tileable PBR albedo texture scan, strict 90-degree top-down flat orthographic camera covering a [2m x 2m] flat surface of [EXACT MATERIAL + WEAR DESCRIPTION], continuous uniform pattern from edge to edge with zero central focal point, flat overcast shadowless diffuse lighting with zero directional shadows and zero ambient occlusion darkening, matte calibrated mid-tone base color avoiding pure black or pure white, sharp edge-to-edge focus, zero perspective tilt, zero vignette.
```

### Prompt Template B — Flux / Midjourney / SDXL (Native `--tile` Support)
```text
Create a seamless texture on all sides of [EXACT MATERIAL], flat 90-degree top-down orthographic surface scan covering [2m x 2m], overcast shadowless diffuse lighting, pure PBR albedo --tile
```

Generate 2–4 candidates in `assets/materials/<slug>/textures/` and inspect via `read_file` before Phase 3.

---

## Phase 3: Seam Inspection & Offset Verification

*(Always pass relative filesystem paths `assets/...` — never `res://` — to Python CLI tools.)*

Run offset wrap test (shifts image `W/2, H/2` so tile edges meet in the center):
```bash
python3 .agents/skills/pbr/scripts/process_pbr.py check-seams \
  assets/materials/<slug>/textures/<slug>_albedo.png \
  --save-offset assets/materials/<slug>/textures/<slug>_offset.png
```
Inspect `<slug>_offset.png` with `read_file`:
- **Pass**: Boundary delta `<= 12.0` AND zero visible line/shift in `<slug>_offset.png`.
- **Fail on structured grid** (bricks, tiles, planks, panels): **Do NOT run `blend-seams`** (linear crossfade creates blurry double-bricks). Regenerate or crop to clean repeating motif.
- **Fail on organic noise** (concrete, plaster, dirt, asphalt, rust):
```bash
python3 .agents/skills/pbr/scripts/process_pbr.py blend-seams \
  assets/materials/<slug>/textures/<slug>_albedo.png \
  -o assets/materials/<slug>/textures/<slug>_albedo.png \
  --radius 32
```

---

## Phase 4: Delighting & Companion Map Derivation
Run `derive-maps` with `--delight` and the matching material `--preset`:
```bash
python3 .agents/skills/pbr/scripts/process_pbr.py derive-maps \
  assets/materials/<slug>/textures/<slug>_albedo.png \
  --out-dir assets/materials/<slug>/textures \
  --slug <slug> \
  --preset <stone|plaster|wood|metal|fabric|wet> \
  --delight
```
Outputs pixel-aligned `<slug>_albedo.png` (delit + `[30, 240]` sRGB clamped), `<slug>_normal.png` (Godot `+Y` OpenGL), `<slug>_height.png`, `<slug>_ao.png`, and preset-calibrated `<slug>_roughness.png`.

Optional overrides: `--normal-strength <float>`, `--base-roughness <float>`, `--metallic`, `--delight-strength <0.0-1.0>`.

**Mixed-Material Caveat**: Luminance-derived roughness/metallic cannot separate matte rust/paint from bare glossy steel. For mixed surfaces, generate or paint a grayscale `<slug>_metallic.png` mask (white = bare metal, black = dielectric) and pass it to `pack-orm --metallic <mask.png>`.

---

## Phase 5: Godot 4 ORM Packing, `.tres` Assembly & 3D Shader-Ball QA

```bash
# 1. Pack ORM (R=AO, G=Roughness, B=Metallic — scalar 0.0/1.0 or mask PNG path)
python3 .agents/skills/pbr/scripts/process_pbr.py pack-orm \
  --ao assets/materials/<slug>/textures/<slug>_ao.png \
  --roughness assets/materials/<slug>/textures/<slug>_roughness.png \
  --metallic 0.0 \
  --output assets/materials/<slug>/textures/<slug>_orm.png

# 2. Build ORMMaterial3D .tres (add --triplanar for walls/floors; omit --height unless parallax needed)
python3 .agents/skills/pbr/scripts/process_pbr.py build-tres \
  --name <slug> \
  --albedo assets/materials/<slug>/textures/<slug>_albedo.png \
  --normal assets/materials/<slug>/textures/<slug>_normal.png \
  --orm assets/materials/<slug>/textures/<slug>_orm.png \
  --triplanar \
  --output assets/materials/<slug>/<slug>.tres
```

### Mandatory 3D Shader-Ball & Tiling QA
Render a 2x2 tiled plane + shader ball sphere (or inspect via Blender MCP `look`) and view via `read_file`:
```bash
/snap/bin/blender --background --python tools/blender/render_qa_sheet.py -- \
  pbr --albedo assets/materials/<slug>/textures/<slug>_albedo.png \
  --normal assets/materials/<slug>/textures/<slug>_normal.png \
  --orm assets/materials/<slug>/textures/<slug>_orm.png \
  --output /tmp/<slug>_pbr_qa.png
```
**Reject and retune** if obvious repeating spots create a macro checkerboard on the 2x2 plane, specular looks wet/plastic on matte presets, or normal relief looks inverted/noisy. Delete `/tmp/<slug>_pbr_qa.png` after pass.

---

## BellaSDK Engine Integration Rules
1. Never combine `heightmap_enabled = true` with `uv1_triplanar = true` (`build-tres` blocks this).
2. Never `.duplicate()` materials at runtime; use `MaterialCache` or `set_instance_shader_parameter()`.
3. Delete temporary `*_offset.png` and `/tmp/*_qa.png` previews after verification.
