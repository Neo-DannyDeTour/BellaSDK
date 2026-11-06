---
name: pbr
description: Generates seamless PBR materials (Albedo, Normal, Roughness, Height, AO) and Godot 4 ORMMaterial3D resources using Nuno Silva's seamless prompt algorithm and 60 FPS ORM channel packing.
metadata:
  icon: texture
---

# PBR Material Generator Skill (`/pbr`)

Automated and interactive PBR texture generator implementing Nuno Silva's seamless AI algorithm, companion map derivation, and Godot 4 60 FPS ORM material compilation.

## Activation
Trigger this skill when creating or tuning game-ready PBR materials:
- Slash command: `/pbr`
- Mention: `@pbr`
- Prompt: `create pbr material`, `generate seamless pbr`, `pbr craft`

---

## Algorithm & Execution Workflow

### Phase 1: Surface Grilling Protocol (Mandatory)
Before generating any image or prompt, stress-test the material specification with the user. Ask 1 tight round covering the 4 core surface attributes (always provide recommended values):
1. **Material Taxonomy & Identity**: Exact surface type (e.g. weathered concrete, dark herringbone oak parquet, chipped limestone bricks, hammered copper).
2. **Roughness & Surface Wear**: Micro-scratches, matte porosity, wet sheen, worn contact paths.
3. **Height Nuance & Contrast Level**: Structural depth, chipped/slanted edges, bevels. Must specify contrast tier (`medium contrast` is mandatory per Nuno Silva algorithm).
4. **Conductivity (Metallic)**: Dielectric ($0.0$ for stone/wood/dirt) vs Conductor ($1.0$ or packed mask for raw metals).

Wait for user confirmation or adjustment before proceeding to Phase 2.

---

### Phase 2: Seamless Albedo Generation (The "Magic Prompt")
Generate the base color texture using the exact minimal prompt formula proven to avoid tiling seams:

```text
Create a seamless texture on all sides of [material name], Albedo
```

**Generation Invariants**:
- **Prompt Adherence**: Do NOT use prompt expansion, modifiers, or "creative enhancements". Pass the exact formula.
- **Resolution**: High resolution ($2048 \times 2048$ or $4096 \times 4096$).
- **Variations**: Request 4 variations via `image-generator` subagent so the best seamless candidate can be picked.
- **Save Location**: `res://assets/materials/<material_slug>/textures/<material_slug>_albedo.png`.

---

### Phase 3: Seam Inspection & Offset Verification
Execute the offset test algorithm (Photoshop Offset filter equivalent: wraps $W/2$, $H/2$):

```bash
python3 .agents/skills/pbr/scripts/process_pbr.py check-seams res://assets/materials/<material_slug>/textures/<material_slug>_albedo.png --save-offset res://assets/materials/<material_slug>/textures/<material_slug>_offset.png
```

- **Threshold**: Boundary delta $\le 12.0$.
- **Automated Blend Fallback**: If seams are detected ($> 12.0$), run boundary crossfade blending:
  ```bash
  python3 .agents/skills/pbr/scripts/process_pbr.py blend-seams res://assets/materials/<material_slug>/textures/<material_slug>_albedo.png -o res://assets/materials/<material_slug>/textures/<material_slug>_albedo.png --radius 32
  ```

---

### Phase 4: Companion Map Derivation (Image-to-Image)
Feed the validated Albedo as image reference into the generator to produce matching PBR maps:

1. **Normal Map**:
   - Prompt: `Generate a normal map texture`
   - Output: `<material_slug>_normal.png`
2. **Roughness Map**:
   - Prompt: `Generate the roughness map`
   - Output: `<material_slug>_roughness.png`
3. **Height / Displacement Map**:
   - Prompt: `Generate the height map texture. [slanted/chipped surface nuances], medium contrast`
   - Output: `<material_slug>_height.png`
   - *Rule*: Always enforce `medium contrast` in prompt to prevent flat or clipping displacement.
4. **Ambient Occlusion Map**:
   - Prompt: `Generate ambient occlusion map`
   - Output: `<material_slug>_ao.png`

---

### Phase 5: Godot 4 60 FPS ORM Packing & Resource Assembly
Godot 4 performance rules mandate packing Occlusion, Roughness, and Metallic into a single 3-channel texture (`_orm.png`) to cut sampler count from 5 to 3:
- **Red**: Ambient Occlusion (fallback: 255)
- **Green**: Roughness
- **Blue**: Metallic (float $0.0$ to $1.0$ or texture map)

Run channel packer and `.tres` builder:
```bash
# 1. Pack ORM
python3 .agents/skills/pbr/scripts/process_pbr.py pack-orm \
  --ao res://assets/materials/<material_slug>/textures/<material_slug>_ao.png \
  --roughness res://assets/materials/<material_slug>/textures/<material_slug>_roughness.png \
  --metallic 0.0 \
  --output res://assets/materials/<material_slug>/textures/<material_slug>_orm.png

# 2. Build Godot ORMMaterial3D Resource
python3 .agents/skills/pbr/scripts/process_pbr.py build-tres \
  --name <material_slug> \
  --albedo res://assets/materials/<material_slug>/textures/<material_slug>_albedo.png \
  --normal res://assets/materials/<material_slug>/textures/<material_slug>_normal.png \
  --orm res://assets/materials/<material_slug>/textures/<material_slug>_orm.png \
  --height res://assets/materials/<material_slug>/textures/<material_slug>_height.png \
  --height-scale 0.05 \
  --output res://assets/materials/<material_slug>/<material_slug>.tres
```

---

## BellaSDK Engine Integration Rules
1. **Material Sharing**: Never call `.duplicate()` on materials at runtime. Reference via `MaterialCache` or instance uniform overrides.
2. **UV Scaling**: Default `uv1_scale = Vector3(1, 1, 1)` in `.tres`. Adjust in inspector or code per object metric.
3. **Release Footprint**: All temporary offset previews (`*_offset.png`) can be purged before commit to avoid repo bloat.
