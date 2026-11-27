---
name: 3d
description: Generates game-ready 3D models and Godot 4 ORM materials via Props (Poly Haven CC0 / TRELLIS / procedural bpy) and Two-Track Hero Humans (Blender MPFB2 + Face Projection + local ComfyUI Hunyuan3D-2mv), tiered Swarm Builder+Critic QA, headless Blender cleanup, and BellaSDK asset ingestion.
metadata:
  icon: box
---

# 3D Asset Generator Skill (`/3d`)

Generates non-slop 3D assets via structured concept plates, **strict separation between Props and Hero Humans**, local ComfyUI (`Hunyuan3D-2mv`), Blender 5.3 (`MPFB2` + orthographic face projection), headless cleanup, visual turntable/face QA, and Godot 4 `ORMMaterial3D` compilation.

## Activation
- Slash command: `/3d`
- Mention: `@3d`
- Prompt: `generate 3d model`, `create 3d prop`, `create 3d character`, `trellis generate`

---

## Default Art Direction Lock
Unless user specifies an override tag (`stylized`, `plush`, `retro`), enforce **Gritty Semi-Realistic / Post-Soviet Industrial Gothic**:
- Grounded physical proportions, believable industrial/worn CMF, weathered matte-to-scuffed surfaces.
- Avoid neon emissive clutter, plastic gloss, floating bits, or cartoon proportions.

---

## Asset Class Split (Props vs. Hero Humans — MANDATORY)

### 1. Props & Architecture (`800–3,500` tris)
Pick the cheapest high-fidelity path:
1. **CC0 / Library First (Blender MCP `search_assets` -> `import_asset`)**: Standard real-world props (barrels, crates, furniture, industrial clutter). Scale via `world_bounding_box` and run `postprocess_trellis.py`.
2. **AI 3D Gen (`tools/scripts/comfy_3d_gen.py` or `tools/scripts/trellis_asset_gen.py`)**: Bespoke organic props not found in libraries.
3. **Procedural Blender `bpy` (`tools/blender/run.py`)**: Modular architectural kits, walls, pipes, doors, and hard-surface assets requiring exact snap dimensions.

### 2. Hero Humans & Realistic Characters (`35,000–60,000` tris)
> **HARD RULE**: NEVER route a realistic human character through legacy `trellis-community/TRELLIS` (v1) or squash a full-body human to `10,000` tris on 1 single UV sheet (leaves ~300 tris / ~150px for the face). Always pass `--no-v1-fallback` if calling `trellis_asset_gen.py`.

Choose between two production tracks:
- **Track A — Anatomical Rig-Ready Hero (`MPFB2` + Face Projection + `ComfyUI` Garment/Hair)** *(Recommended for NPCs/playable humans)*:
  1. Generate anatomical base mesh via Blender 5.3 + MPFB2 (`tools/blender/build_human_base.py`) with clean quad topology, stripped helper geometry, and separate `Body` + `Head` material slots.
  2. Project crisp `ref_detail` / `ref_front` portrait plate onto a dedicated `2048x2048` Head UV map via `tools/blender/project_face_texture.py` (Cycles `DIFFUSE` color-only bake, zero baked shadows).
  3. Generate bespoke garments, cloaks, or sculpted hair masses via local ComfyUI (`tools/scripts/comfy_3d_gen.py`, `Hunyuan3D-2mv`, `--lowvram`), fit to the MPFB2 body in Blender, and export multi-slot GLB (`Head 2K` + Godot 4 Forward+ SSS, `Eyes`, `Hair`, `Outfit 2K–4K`).
- **Track B — High-Res AI Full-Body (`ComfyUI Hunyuan3D-2mv` + Face Projection Polish)** *(Fastest for complex costumed figures/statues)*:
  1. Run local ComfyUI multi-view (`tools/scripts/comfy_3d_gen.py --front ... --left ... --back ... --tri-budget 45000 --target-height 1.68 --vram-mode lowvram`).
  2. Run `tools/blender/project_face_texture.py` over the head region to lock 1:1 eyes, freckles, and facial likeness from `ref_front` / `ref_detail`.

---

## Execution Tier & Swarm Policy
- **Solo (Default — single simple prop)**: 1 agent runs pipeline + self-checks 4-angle QA sheet (`render_qa_sheet.py turntable`).
- **Swarm — Hero Asset / Character (Best-of-N + Visual Critic)**:
  - Spawn `builder` (owns generation + Blender cleanup) + `critic` (read-only visual QA on concept plates + 4-angle turntable + close-up face sheet).
  - **Hard Rule**: Live Blender MCP (`execute_blender_code` / `look`) shares 1 viewport. Never run 2 workers against live Blender MCP concurrently; run parallel workers headless.
  - **Hard Rule**: Local ComfyUI shares 1 GPU (`RTX 4070 8 GB VRAM`). Never run 2 ComfyUI generation jobs concurrently.

---

## Gate 1 — Tight Engine & Topology Lock (1 Round)
Ask 1 tight round with concrete defaults before sourcing/generating:
1. **Asset Class & Layer**: `Prop (Layer 1/3)` vs `Hero Human (Layer 2 Player)` (selects Track A or Track B).
2. **Source Strategy**:
   - Props: `Blender MCP search_assets` | `ComfyUI Hunyuan3D-2` | `TRELLIS.2` | `Procedural bpy`.
   - Humans: `Track A (MPFB2 + Face Projection + ComfyUI Garment)` | `Track B (ComfyUI Hunyuan3D-2mv High-Res + Face Projection)`.
3. **Execution Tier**: `Solo` vs `Swarm` (Hero Builder+Critic or Multi-Prop Batch).
4. **Sub-Mesh & Material Split**: Single manifold (props) vs `--keep-separate --preserve-materials` (multi-slot humans: Head/Eyes/Hair/Outfit).
5. **Scale & Budgets**:
   - Mandatory `--target-height` in meters (`1.68` hero, `0.9` barrel, `0.45` crate).
   - Tri budget: `800–2,000` static props | `1,500–3,500` interactive | `35,000–60,000` hero humans.
6. **Material Preset**: `stone | plaster | wood | metal | fabric | wet` (+ Godot 4 Forward+ skin SSS for humans).

Wait for confirmation before Gate 2.

---

## Gate 2 — Concept Plate Prompts (`image-generator`)
*(Skip if sourcing from Blender MCP `search_assets` or pure procedural `bpy`.)*

### Anti-Slop Plate Rules
- **NEVER** pass dark spotlight vignettes, floor shadows, perspective wide-angle distortion, or cluttered backgrounds into 3D generators.
- **NO thin disconnected geometry**: avoid loose wires, antennae, chains, thin straps, or stray hair strands.

### Template A: Static / Interactive Prop (3/4 View)
```text
Isolated single [OBJECT] asset for 3D modeling, gritty semi-realistic post-Soviet industrial aesthetic, [MATERIALS AND WEAR], centered three-quarter orthographic-style view with zero perspective distortion, clean solid manifold silhouette with chunky readable bevels and zero thin floating wires or loose straps, flat even shadowless diffuse studio lighting, uniform solid #808080 neutral gray background, zero floor plane, zero cast shadows, zero vignette, sharp focus edge-to-edge.
```

### Template C: Humanoid Character 3-View Turnaround + Detail Sheet
Generate 3 square orthographic turnaround plates (`_front.png`, `_side.png`, `_back.png`) + 1 close-up portrait/material sheet (`_detail.png`) locking identical costume, colors, and proportions:
```text
Full-body character concept turnaround, pure orthographic [front / 90-degree left side profile / back] view, symmetrical standing A-pose with arms angled 45 degrees down from torso and fingers slightly separated, feet hip-width apart facing straight forward, [CHARACTER DESCRIPTION & OUTFIT CMF], clean sculpted manifold forms with zero stray floating hair strands or thin dangling straps, flat even shadowless studio lighting, uniform solid #808080 neutral gray background, zero floor shadow, zero perspective distortion, full body centered from head to boots with margin.
```

---

## Gate 3 & 4 — Automated Generation, Blender Cleanup & Godot ORM

### Track A: MPFB2 Anatomical Base + Face Projection (Blender 5.3 Headless)
```bash
# 1. Build clean anatomical MPFB2 human base with separate Body/Head slots
/snap/bin/blender --background --python tools/blender/build_human_base.py -- \
  --output assets/models/<slug>/<slug>_base.glb \
  --save-blend assets/models/<slug>/<slug>_base.blend \
  --name <slug> --gender 0.0 --target-height 1.68

# 2. Project crisp front portrait plate onto 2K Head UV (Cycles DIFFUSE color bake)
/snap/bin/blender --background --python tools/blender/project_face_texture.py -- \
  --input assets/models/<slug>/<slug>_base.glb \
  --image assets/models/<slug>/references/<slug>_ref_detail.png \
  --output-tex assets/models/<slug>/<slug>_head_albedo.png \
  --output-glb assets/models/<slug>/<slug>.glb \
  --uv-size 2048
```

### Track B / Custom Garment: Local ComfyUI Hunyuan3D-2mv (`--lowvram`)
```bash
./.venv/bin/python tools/scripts/comfy_3d_gen.py \
  --front assets/models/<slug>/references/<slug>_ref_front.png \
  --left assets/models/<slug>/references/<slug>_ref_side.png \
  --back assets/models/<slug>/references/<slug>_ref_back.png \
  --slug <slug> \
  --tri-budget 45000 \
  --target-height 1.68 \
  --vram-mode lowvram
```

### Props / Organic HF Space Fallback (`TRELLIS.2`)
```bash
./.venv/bin/python tools/scripts/trellis_asset_gen.py \
  --image "<front_plate.png>" \
  --slug "<prop_slug>" \
  --layer "Layer 3 Interactive" \
  --preset metal \
  --tri-budget 2000 \
  --target-height 0.85 \
  --no-v1-fallback
```

---

## Post-Generation Visual & Technical QA Gate (Mandatory)
Before handoff, verify `assets/models/<slug>/`:
1. **Manifest & ORM**: `asset_manifest.json` reports `uv_layers >= 1`, `tri_count <= budget`, non-null `dimensions_m`, and `collision_hint`; `.tres` links valid albedo, ORM, and normal maps.
2. **4-Angle Turntable Check**:
   ```bash
   /snap/bin/blender --background --python tools/blender/render_qa_sheet.py -- \
     turntable --input assets/models/<slug>/<slug>.glb \
     --output /tmp/<slug>_qa_turntable.png
   ```
3. **Hero Human Close-Up Face Likeness Check (HARD GATE)**:
   ```bash
   /snap/bin/blender --background --python tools/blender/render_qa_sheet.py -- \
     face --input assets/models/<slug>/<slug>.glb \
     --output /tmp/<slug>_qa_face.png --tile-size 448
   ```
   Compare `/tmp/<slug>_qa_face.png` side-by-side against `<slug>_ref_front.png` via `read_file`. **HARD REJECT** if eyes are blurred/asymmetric blobs, nose/lips are melted, low-poly faceting shows on cheeks/chin, or face diverges from the reference likeness. Delete `/tmp/<slug>_qa_*.png` after pass.
4. **Godot Collision**: Assign shape from `collision_hint` (`BoxShape3D` / `ConvexPolygonShape3D` for dynamic/interactive; never `ConcavePolygonShape3D` on `RigidBody3D`).
