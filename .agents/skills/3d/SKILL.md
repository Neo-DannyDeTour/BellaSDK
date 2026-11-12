---
name: 3d
description: Generates game-ready 3D models and Godot 4 ORM materials from concept plates using Microsoft TRELLIS API and automated BellaSDK asset ingestion.
metadata:
  icon: box
---

# 3D Asset Generator Skill (`/3d`)

Automated 3D model generator implementing Microsoft TRELLIS image-to-3D inference, mesh simplification (quadric decimation), and Godot 4 ORM material packing.

## Activation
Trigger this skill when generating 3D models, props, or environment geometry from reference images:
- Slash command: `/3d`
- Mention: `@3d`
- Prompt: `generate 3d model`, `create 3d prop`, `trellis generate`

---

## 4-Gate Interrogator Pipeline

Before executing generation, enforce the 4-Gate Interrogator Pipeline:
1. **Gate 1 — Engine Spec & Topology Lock**:
   - Confirm target layer (`Layer 1 Environment`, `Layer 2 Player`, `Layer 3 Interactive`).
   - Confirm sub-mesh split (single manifold mesh vs articulated door/pivot).
   - Confirm tri budget (default: 2,000 for props).
2. **Gate 2 — Concept Plate Isolation**:
   - Auto-crop bounding box to isolate object from vignette/spotlights.
   - Pad onto `#808080` neutral gray canvas for clean silhouette extraction.
3. **Gate 3 — Mesh Generation & Retopo**:
   - Invoke TRELLIS `/preprocess_image` and `/generate_and_extract_glb`.
   - Simplify mesh using `trimesh.simplify_quadric_decimation()` to match tri budget.
4. **Gate 4 — Delighted PBR & Godot 4 ORM**:
   - Pack ORM texture (`R = AO`, `G = Roughness`, `B = Metallic`).
   - Generate Godot 4 `.tres` resource (`ORMMaterial3D`).
   - Write `asset_manifest.json` metadata.

---

## Direct CLI Execution

```bash
./.venv/bin/python tools/scripts/trellis_asset_gen.py \
  --image "<path_to_reference_image>" \
  --slug "<prop_slug>" \
  --layer "Layer 1 Environment" \
  --tri-budget 2000 \
  --metallic 0.0 \
  --roughness 0.7
```

### CLI Arguments
- `--image`: Path to local reference plate (PNG/JPEG).
- `--slug`: Name identifier (creates `res://assets/models/<slug>/`).
- `--layer`: Target collision layer (default: `"Layer 1 Environment"`).
- `--tri-budget`: Maximum face count (default: `2000`).
- `--metallic`: Metallic float value between 0.0 and 1.0 (default: `0.0`).
- `--roughness`: Roughness float value between 0.0 and 1.0 (default: `0.7`).
- `--output-dir`: Optional custom output directory.
- `--seed`: Generation seed (default: `42`).
