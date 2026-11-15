---
name: 3d
description: Generates game-ready 3D models and Godot 4 ORM materials from concept plates using Microsoft TRELLIS API, headless Blender cleanup, and automated BellaSDK asset ingestion.
metadata:
  icon: box
---

# 3D Asset Generator Skill (`/3d`)

Generates non-slop 3D assets via structured concept plates, Microsoft TRELLIS (single or multi-view), headless Blender 5.3 UV-safe cleanup, albedo delighting, and Godot 4 `ORMMaterial3D` compilation.

## Activation
- Slash command: `/3d`
- Mention: `@3d`
- Prompt: `generate 3d model`, `create 3d prop`, `trellis generate`

---

## Default Art Direction Lock
Unless user specifies an override tag (`stylized`, `plush`, `retro`), enforce **Gritty Semi-Realistic / Post-Soviet Industrial Gothic**:
- Grounded physical proportions, believable industrial/worn CMF, weathered matte-to-scuffed surfaces.
- Avoid neon emissive clutter, plastic gloss, floating bits, or cartoon proportions.

---

## Gate 1 — Tight Engine & Topology Lock (1 Round)
Ask 1 tight round with concrete defaults before generating concept plates:
1. **Role & Layer**: `Layer 1 Environment` (static), `Layer 2 Player` (hero/rigged), or `Layer 3 Interactive` (rigid/door/pickup).
2. **Mesh Strategy**: `TRELLIS single-view` (simple organic/clutter props), `TRELLIS multi-view` (3 plates: front/side/back for asymmetric props & A-pose characters), or `Procedural Blender bpy` (`tools/blender/run.py` — preferred for clean modular walls, crates, pipes, architectural kits).
3. **Sub-Mesh Split**: Single manifold mesh vs `--keep-separate` articulated pivots.
4. **Scale & Budgets**:
   - Mandatory `--target-height` in meters (e.g. `1.68` hero, `0.9` barrel, `0.45` crate).
   - Tri budget: `800–2,000` static props | `1,500–3,500` interactive | `6,000–12,000` hero characters.
5. **Material Preset**: `stone | plaster | wood | metal | fabric | wet`.

Wait for confirmation before Gate 2.

---

## Gate 2 — Concept Plate Prompts (`image-generator`)

### Anti-Slop Plate Rules
- **NEVER** pass dark spotlight vignettes, floor shadows, perspective wide-angle distortion, or cluttered backgrounds into TRELLIS.
- **NO thin disconnected geometry**: avoid loose wires, antennae, chains, thin straps, or stray hair strands (marching cubes breaks or blobs them; add cables/chains in Godot/Blender separately).

### Template A: Static / Interactive Prop (3/4 View)
```text
Isolated single [OBJECT] asset for 3D modeling, gritty semi-realistic post-Soviet industrial aesthetic, [MATERIALS AND WEAR: e.g., chipped olive-drab enamel paint over dark rusted steel, matte black vulcanized rubber seals, realistic grime in recesses], centered three-quarter orthographic-style view with zero perspective distortion, clean solid manifold silhouette with chunky readable bevels and zero thin floating wires or loose straps, flat even shadowless diffuse studio lighting, uniform solid #808080 neutral gray background, zero floor plane, zero cast shadows, zero vignette, sharp focus edge-to-edge.
```

### Template B: Symmetric / Hard-Surface Front Plate
```text
Isolated single [OBJECT] asset, straight-on orthographic front elevation, gritty weathered industrial CMF [MATERIALS AND WEAR], solid manifold geometry with heavy chamfers and no delicate gaps, flat shadowless diffuse studio lighting, uniform solid #808080 neutral gray background, zero floor shadow, zero perspective distortion, edge-to-edge crisp detail.
```

### Template C: Humanoid Character 3-View Turnaround (For Multi-View + AccuRIG)
Generate 3 separate square plates (`_front.png`, `_side.png`, `_back.png`) locking identical costume, colors, and proportions:
```text
Full-body character concept turnaround, pure orthographic [front / 90-degree left side profile / back] view, symmetrical standing A-pose with arms angled 45 degrees down from torso and fingers slightly separated, feet hip-width apart facing straight forward, [CHARACTER DESCRIPTION & GRITTY OUTFIT CMF], clean sculpted manifold forms with zero stray floating hair strands or thin dangling straps, flat even shadowless studio lighting, uniform solid #808080 neutral gray background, zero floor shadow, zero perspective distortion, full body centered from head to boots with margin.
```

### Gate 2 Visual Inspection (Mandatory Before Gate 3)
Inspect generated image(s) via `read_file`. **Reject and regenerate** if:
- Ground shadow, spotlight cone, or gradient background appears.
- Parts are cropped at canvas borders.
- Limbs/fingers are fused or thin floating cables appear.

---

## Gate 3 & 4 — Automated Generation, Blender Cleanup & Godot ORM

Run via `.venv/bin/python` (automatically runs `/snap/bin/blender` `tools/blender/postprocess_trellis.py` for UV-safe decimation, bottom-center `min_y = 0` grounding, normal recalc, texture extraction, albedo delighting, ORM packing, and `ORMMaterial3D` `.tres` assembly):

### Single-View Prop
```bash
./.venv/bin/python tools/scripts/trellis_asset_gen.py \
  --image "<front_plate.png>" \
  --slug "<prop_slug>" \
  --layer "Layer 3 Interactive" \
  --preset metal \
  --tri-budget 2000 \
  --target-height 0.85
```

### Multi-View Hero / Complex Asset
```bash
./.venv/bin/python tools/scripts/trellis_asset_gen.py \
  --image "<front_plate.png>" \
  --multi-images "<side_plate.png>" "<back_plate.png>" \
  --multiimage-algo stochastic \
  --slug "<asset_slug>" \
  --layer "Layer 2 Player" \
  --preset fabric \
  --tri-budget 8000 \
  --target-height 1.68
```

### Key Flags
- `--target-height <m>`: Required for accurate Godot meter scale (baked directly into vertices, `scale = (1,1,1)`).
- `--preset <stone|plaster|wood|metal|fabric|wet>`: Calibrates derived roughness & normal strength.
- `--metallic` / `--roughness`: Optional numeric overrides.
- `--keep-separate`: Preserve multi-part sub-meshes instead of joining.
- `--skip-delight`: Keep raw extracted albedo if already flat-lit.
- Token resolution order: `--hf-token` -> `HF_TOKEN` env -> `.env` `HF_TOKEN` -> `~/.cache/huggingface/token`.

---

## Post-Generation QA Gate
Before handoff, verify `res://assets/models/<slug>/`:
1. `asset_manifest.json` reports `uv_layers >= 1`, `tri_count <= budget`, non-null `dimensions_m`, and `collision_hint`.
2. `<slug>.tres` links `<slug>_albedo.png`, `<slug>_orm.png`, and `<slug>_normal.png` (not blank uniform ORM unless source mesh was untextured).
3. In Godot: assign collision shape from `collision_hint` (`BoxShape3D` / `ConvexPolygonShape3D` for dynamic/interactive; never `ConcavePolygonShape3D` on `RigidBody3D`).
