# Technical Analysis: Blender Mantaflow Headless Bake & Spritesheet Pipeline

## Executive Summary
This investigation surveys the runtime environment and verifies the headless execution parameters for Blender Mantaflow explosion baking, 8x8 flipbook assembling, and Godot 4 asset importing. All required CLI binaries (`blender`, `python3`, `montage`, `ffmpeg`, `godot`, `gdlint`) are installed and functional on Ubuntu.

---

## 1. System & Binary Survey

| Binary | System Path | Version | Verification Command & Result |
|---|---|---|---|
| `blender` | `/snap/bin/blender` | Blender 5.2.2 LTS (hash `d13f752e3b9c`) | `blender --version` -> exited 0 |
| `python3` | `/usr/bin/python3` | Python 3.14.4 (PIL / Pillow 11.x available) | `python3 -c "import PIL; print(PIL.__file__)"` -> valid |
| `montage` | `/usr/bin/montage` | ImageMagick 7.1.2-18 Q16 x86_64 | `montage --version` -> exited 0 |
| `ffmpeg` | `/usr/bin/ffmpeg` | ffmpeg version 8.0.1-3ubuntu2 | `ffmpeg -version` -> exited 0 |
| `godot` | `/usr/bin/godot` | Godot Engine v4.7.1.stable.official.a13da4feb | `godot --version` -> exited 0 |
| `gdlint` | `/home/dkd/.local/bin/gdlint` | gdlint 4.5.0 | `gdlint --version` -> exited 0 |

### Blender Embedded Python
- Python Version inside Blender: `Python 3.13.13` (GCC 14.2.1).
- Installed addons: `io_anim_bvh`, `io_curve_svg`, `io_mesh_uv_layout`, `io_scene_fbx`, `io_scene_gltf2`, `cycles`, `pose_library`, `bl_pkg`, `blender_mcp`.
- `PIL` is NOT installed inside Blender's embedded Python. Spritesheet packing should be executed via `montage` (ImageMagick) or via system `/usr/bin/python3` calling `PIL`.

---

## 2. Blender Render Engine Analysis (EEVEE vs Cycles)

1. **Enum Identifier**:
   - In Blender 5.2.2 LTS, the render engine enum values are `('BLENDER_EEVEE', 'BLENDER_WORKBENCH', 'CYCLES')`.
   - `BLENDER_EEVEE_NEXT` was a transitional identifier in Blender 4.1 beta; in 4.2+ and 5.x LTS, the rewritten EEVEE engine is registered directly as `BLENDER_EEVEE`. Attempting to assign `BLENDER_EEVEE_NEXT` throws:
     `TypeError: enum "BLENDER_EEVEE_NEXT" not found in ('BLENDER_EEVEE', 'BLENDER_WORKBENCH', 'CYCLES')`.
   - Use `scene.render.engine = 'BLENDER_EEVEE'`.

2. **Headless Execution Without DISPLAY**:
   - Both `BLENDER_EEVEE` and `CYCLES` render headlessly in background mode without X11 or DISPLAY server errors.
   - Tested render throughput at 256x256 RGBA:
     - `BLENDER_EEVEE`: ~0.425s per frame.
     - `CYCLES` (16 samples): ~1.2s per frame.
   - For 64 frames: `BLENDER_EEVEE` renders all 64 frames in ~20-25 seconds total.
   - Transparency: `scene.render.film_transparent = True` produces crisp transparent RGBA PNG frames (verified via pixel extrema test).

---

## 3. Blender Mantaflow RNA API Mapping

Testing in Blender 5.2.2 identified the exact RNA property names and nuances:

### Domain Settings (`domain_modifier.domain_settings`)
- `ds.domain_type = 'GAS'`
- `ds.resolution_max = 128` (Benchmarked: 64 divisions bakes 64 frames in 15.2s; 128 divisions takes ~90-120s).
- `ds.time_scale = 1.3`
- `ds.use_dissolve_smoke = True`
- `ds.dissolve_speed = 45` (Corresponds to "Dissolve Time" in UI).
- `ds.use_dissolve_smoke_log = True` (Corresponds to "Slow dissolve" checkbox in UI; `use_dissolve_smoke_slow` does NOT exist in RNA).
- `ds.burning_rate = 0.65` (Corresponds to "Reaction Speed" in UI; default is 0.75).
- `ds.flame_smoke = 3.0`
- `ds.flame_vorticity = 0.45`
- `ds.vorticity = 0.45`
- `ds.cache_type = 'ALL'`
- `ds.cache_frame_start = 1`
- `ds.cache_frame_end = 64`
- `ds.cache_directory = <temp_path>` (Enables isolated baking and trivial cleanup).

### Flow Settings (`flow_modifier.flow_settings`)
- `fs.flow_type = 'BOTH'` (Corresponds to "Fire + Smoke" in UI; `'FIRE_SMOKE'` does NOT exist in RNA).
- `fs.flow_behavior = 'INFLOW'`
- `fs.use_initial_velocity = True` (Mandatory for velocity parameters to take effect).
- `fs.velocity_normal = 8.0`
- `fs.velocity_random = 2.5`
- `fs.fuel_amount = 1.8`
- `fs.surface_distance = 1.0` (Corresponds to "Surface Emission" in UI).
- **Emission Window (Frames 1-3 only)**:
  ```python
  fs.use_inflow = True
  fs.keyframe_insert(data_path="use_inflow", frame=1)
  fs.keyframe_insert(data_path="use_inflow", frame=3)
  fs.use_inflow = False
  fs.keyframe_insert(data_path="use_inflow", frame=4)
  ```

### Baking Operators
- `bpy.ops.fluid.bake_all()`: Official Mantaflow baking operator when the domain object is selected and active. Verified: bakes all 64 frames to disk headlessly.
- Notice: `bpy.ops.ptcache.bake_all()` operates on legacy point cache systems and attempts to bake 250 frames of generic physics; `bpy.ops.fluid.bake_all()` specifically triggers the Mantaflow gas solver.
- Cleanup operator: `bpy.ops.fluid.free_all()` or `shutil.rmtree(cache_dir, ignore_errors=True)`.

### Camera & Bounding Setup
- Domain Box: 6m x 6m x 6m centered at `(0, 0, 2.0)`. Bounds are `[-3.0, 3.0]` in X/Y, `[-1.0, 5.0]` in Z.
- Camera:
  - Location: `(0.0, -7.5, 2.0)`
  - Rotation: `(math.radians(90.0), 0.0, 0.0)`
  - Type: `ORTHO`
  - Orthographic Scale: `7.0` (provides 0.5m buffer on all sides to prevent fireball edge clipping).

### Principled Volume Shader Setup
- Material on Domain with node tree:
  - `ShaderNodeVolumePrincipled` linked to `ShaderNodeOutputMaterial.inputs['Volume']`.
  - `ShaderNodeAttribute` (`attribute_name = "flame"`) -> `ShaderNodeValToRGB` (Color Ramp: black -> orange -> bright yellow) -> `vol_node.inputs['Emission Color']`.
  - `ShaderNodeAttribute` (`attribute_name = "flame"`) -> `ShaderNodeMath` (Multiply by 15.0) -> `vol_node.inputs['Emission Strength']`.
  - `vol_node.inputs['Density Attribute'].default_value = 'density'`
  - `vol_node.inputs['Density'].default_value = 5.0`
  - `vol_node.inputs['Blackbody Intensity'].default_value = 1.0`
  - `vol_node.inputs['Temperature Attribute'].default_value = 'flame'`

---

## 4. Spritesheet Assembly Tooling

Tested 64 dummy 256x256 frames assembled into a 2048x2048 8x8 grid:
1. **`montage` (ImageMagick)**:
   - Command: `montage /tmp/frames/frame_*.png -tile 8x8 -geometry 256x256+0+0 -background none /path/to/explosion_core_8x8.png`
   - Verified output: 2048x2048 PNG, 8-bit sRGB with RGBA transparency. Execution time: 0.59s.
2. **Python Pillow (`/usr/bin/python3`)**:
   - Inline script using `Image.new('RGBA', (2048, 2048), (0, 0, 0, 0))` and `sheet.paste(...)`.
   - Verified output: 2048x2048 PNG, RGBA transparency. Execution time: 0.13s.
3. **Pipeline Recommendation**:
   - In `tools/generate_explosion_flipbook.py`:
     Check `shutil.which("montage")`. If present, run `montage` command. If not present, fall back to executing `/usr/bin/python3` with Pillow script.

---

## 5. Godot 4.7.1 Asset Import & GUT Testing

1. **Headless Editor Asset Import**:
   - `godot --headless --editor --quit` executes cleanly in ~15-20s, generating `.import` files and UIDs for new PNG and shader assets.
2. **GUT Testing**:
   - System GUT version is 9.7.1 on Godot 4.7.1.
   - Running GUT with `-gtest=res://test/unit/<test_name>.gd` triggers directory scanning from `.gutconfig.json` (`"dirs": ["res://test/unit"]`), which scans all 104 tests and fails on existing unrelated compile errors (such as `test_smoke_explosion_vfx.gd:35` referencing non-existent `preview_active`).
   - **Critical Fix for Isolated Testing**:
     Pass `-gdir="" -gtest=res://test/unit/<test_name>.gd`.
     Verified: `godot --headless -s addons/gut/gut_cmdln.gd -gdir="" -gtest=res://test/unit/test_collision_layers.gd` executes in 0.44s and exits cleanly with code 0.
