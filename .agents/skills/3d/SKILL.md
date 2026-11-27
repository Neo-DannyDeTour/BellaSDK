---
name: 3d
description: Generates game-ready 3D models and Godot 4 ORM materials via Hybrid sourcing (Blender MCP Poly Haven/Sketchfab, TRELLIS.2 / MCP generate_3d, or procedural bpy), tiered Swarm Builder+Critic QA, headless Blender cleanup, and BellaSDK asset ingestion.
metadata:
  icon: box
---

# 3D Asset Generator Skill (`/3d`)

Generates non-slop 3D assets via Hybrid sourcing, structured concept plates, TRELLIS.2 / Blender MCP, headless Blender UV-safe cleanup, visual turntable QA, and Godot 4 `ORMMaterial3D` compilation.

## Activation
- Slash command: `/3d`
- Mention: `@3d`
- Prompt: `generate 3d model`, `create 3d prop`, `trellis generate`

---

## Default Art Direction Lock
Unless user specifies an override tag (`stylized`, `plush`, `retro`), enforce **Gritty Semi-Realistic / Post-Soviet Industrial Gothic**:
- Grounded physical proportions, believable industrial/worn CMF, weathered matte-to-scuffed surfaces.
- Avoid neon emissive clutter, plastic gloss, floating bits, or cartoon proportions.

### Semi-Realistic 2004 HL2 / Alyx Vance Humanoid Standard
For hero/NPC humanoids (such as Bella):
- **Ortho-Fitted Silhouette**: Fit base mesh silhouette directly to front, 90-degree side, and back orthographic reference plates before baking blendshapes or fitting eyes/lashes/garments.
- **3-View Seamless Head Projection**: Project front, mirrored side, and back head views onto a dedicated 2K UV atlas (`[0.04, 0.96]`) with smooth view-angle blending, harmonized skin tone, and zero cutoff seams at neck/ears.
- **Slim Athletic-Realistic Proportions**: Maintain natural waist, ribcage, and limbs without inflated thighs/hips; keep glute/bust curves anatomically grounded and garments close-fitting.
- **Matte-Satin Skin + Baked Facial AO**: Bake subtle HL2-style facial AO (eye creases, nostrils, under-lip, forehead bang shadow) into albedo/ORM; pair with isotropic micro-pore normals, roughness `>= 0.52`, low specular (`~0.25..0.30`), and restrained SSS.
- **Natural Eyes with Upper-Eyelid Shadow**: Sample natural iris hues from reference (no neon emission/glow) and bake/apply an upper-eyelid shadow gradient across the top ~25% of the eye.
- **Sculpted Layered Hair Mass + Soft Cards**: Pair a head-hugging cap (center part + ash shadow) with organic C-curl locks and brow-grazing cards; keep albedo midtones (`0.48..0.84`) with bleed-padded alpha=0 borders so strands never blow out to `#FFFFFF` or fringe black.

---

## Hybrid Source Priority (Pick Cheapest High-Fidelity Path)
1. **CC0 / Library First (Blender MCP `search_assets` -> `import_asset`)**: Standard real-world props (barrels, crates, furniture, industrial clutter) from Poly Haven / Sketchfab / Poly Pizza. Scale via `world_bounding_box` and run `postprocess_trellis.py` for Godot ORM + grounding.
2. **AI 3D Gen (`TRELLIS.2` / Blender MCP `generate_3d`)**: Bespoke organic props, hero characters, or custom silhouettes not found in libraries.
3. **Procedural Blender `bpy` (`tools/blender/run.py`)**: Modular architectural kits, clean walls, pipes, doors, and hard-surface assets requiring exact snap dimensions.

---

## Execution Tier & Swarm Policy
- **Solo (Default — single simple prop)**: 1 agent runs pipeline + self-checks 4-angle QA sheet (`render_qa_sheet.py turntable` or Blender MCP `look`).
- **Swarm — Hero Asset (Best-of-N + Visual Critic)**:
  - Spawn `builder` (owns generation + Blender cleanup) + `critic` (read-only visual QA on concept plates + 4-angle turntable renders).
  - `builder` generates 2–3 concept plates or candidate seeds -> `critic` selects winner and audits final turntable for melted backs, floating islands, UV stretch, and scale -> `builder` fixes defects before handoff.
- **Swarm — Multi-Prop Pack / Kit**:
  - Spawn parallel headless `builder-1..N` (1 distinct slug per worker via `trellis_asset_gen.py` or `tools/blender/run.py`) + 1 `critic`.
- **Hard Rule**: Live Blender MCP (`execute_blender_code` / `look`) shares 1 viewport. Never run 2 workers against live Blender MCP concurrently; use 1 live `builder` or run parallel workers headless.

---

## Gate 1 — Tight Engine & Topology Lock (1 Round)
Ask 1 tight round with concrete defaults before sourcing/generating:
1. **Role & Layer**: `Layer 1 Environment` (static), `Layer 2 Player` (hero/rigged), or `Layer 3 Interactive` (rigid/door/pickup).
2. **Source Strategy**: `Blender MCP search_assets` (CC0 library), `TRELLIS.2 single-view` (simple organic), `TRELLIS.2 multi-view` (3 plates: front/side/back for asymmetric props & A-pose characters), `Blender MCP generate_3d`, or `Procedural bpy`.
3. **Execution Tier**: `Solo` (single prop) vs `Swarm` (Hero Builder+Critic or Multi-Prop Batch).
4. **Sub-Mesh Split**: Single manifold mesh vs `--keep-separate` articulated pivots.
5. **Scale & Budgets**:
   - Mandatory `--target-height` in meters (e.g. `1.68` hero, `0.9` barrel, `0.45` crate).
   - Tri budget: `800–2,000` static props | `1,500–3,500` interactive | `6,000–12,000` hero characters.
6. **Material Preset**: `stone | plaster | wood | metal | fabric | wet`.

Wait for confirmation before Gate 2.

---

## Gate 2 — Concept Plate Prompts (`image-generator`)
*(Skip if sourcing from Blender MCP `search_assets` or pure procedural `bpy`.)*

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

### Template C: Humanoid Character 3-View Turnaround (For Multi-View + AccuRIG/UniRig)
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

Run via `.venv/bin/python` (connects to `microsoft/TRELLIS.2` with fallback to `trellis-community/TRELLIS`, runs headless Blender `tools/blender/postprocess_trellis.py` for UV-safe decimation, bottom-center `min_y = 0` grounding, normal recalc, texture extraction, albedo delighting, ORM packing, and `ORMMaterial3D` `.tres` assembly):

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
- `--space <hf_space>`: Optional HF Space override (`microsoft/TRELLIS.2` default).
- Token resolution order: `--hf-token` -> `HF_TOKEN` env -> `.env` `HF_TOKEN` -> `~/.cache/huggingface/token`.

---

## Post-Generation Visual & Technical QA Gate (Mandatory)
Before handoff, verify `assets/models/<slug>/`:
1. **Manifest & ORM**: `asset_manifest.json` reports `uv_layers >= 1`, `tri_count <= budget`, non-null `dimensions_m`, and `collision_hint`; `<slug>.tres` links albedo, ORM, and normal maps.
2. **4-Angle Visual Turntable Check**: Render Front/Right/Back/3-4 contact sheet (or inspect via Blender MCP `look`) and view via `read_file`:
   ```bash
   /snap/bin/blender --background --python tools/blender/render_qa_sheet.py -- \
     turntable --input assets/models/<slug>/<slug>.glb \
     --output /tmp/<slug>_qa_turntable.png
   ```
   **Reject and fix** if back-face melted/hollow, floating islands appear, UVs visibly smear, or silhouette diverges from concept plate. Delete `/tmp/<slug>_qa_turntable.png` after pass.
3. **Godot Collision**: Assign shape from `collision_hint` (`BoxShape3D` / `ConvexPolygonShape3D` for dynamic/interactive; never `ConcavePolygonShape3D` on `RigidBody3D`).
