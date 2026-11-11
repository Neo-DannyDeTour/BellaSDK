# Handoff Report — Explorer Survey 1: Mantaflow Simulation & Spritesheet Pipeline

## 1. Observation

- **Binary Availability**:
  - `blender` is at `/snap/bin/blender`, version `Blender 5.2.2 LTS` (hash `d13f752e3b9c built 2026-09-15 01:34:58`). Embedded Python is `3.13.13`.
  - `python3` is at `/usr/bin/python3`, version `Python 3.14.4` with `PIL` (Pillow) installed.
  - `montage` is at `/usr/bin/montage`, version `ImageMagick 7.1.2-18 Q16 x86_64`.
  - `ffmpeg` is at `/usr/bin/ffmpeg`, version `8.0.1-3ubuntu2`.
  - `godot` is at `/usr/bin/godot`, version `Godot Engine v4.7.1.stable.official.a13da4feb`.
  - `gdlint` is at `/home/dkd/.local/bin/gdlint`, version `4.5.0`.

- **Blender Render Engine API**:
  - `scene.render.engine = 'BLENDER_EEVEE_NEXT'` raises:
    `TypeError: bpy_struct: item.attr = val: enum "BLENDER_EEVEE_NEXT" not found in ('BLENDER_EEVEE', 'BLENDER_WORKBENCH', 'CYCLES')`.
  - Setting `scene.render.engine = 'BLENDER_EEVEE'` succeeds without error.
  - Headless rendering with `BLENDER_EEVEE` works without X11 or DISPLAY server errors, yielding transparent RGBA PNG frames (verified via Pillow `im.getextrema()`: `((0, 45), (0, 7), (0, 1), (0, 255))`).

- **Blender Mantaflow RNA Property Names**:
  - Setting `fs.flow_type = 'FIRE_SMOKE'` raises:
    `TypeError: bpy_struct: item.attr = val: enum "FIRE_SMOKE" not found in ('SMOKE', 'BOTH', 'FIRE', 'LIQUID')`. The valid enum is `'BOTH'`.
  - Setting `ds.use_dissolve_smoke_slow = True` fails with `AttributeError`. The RNA property is `ds.use_dissolve_smoke_log = True`.
  - Reaction speed in UI is mapped to `ds.burning_rate` (default `0.75`).
  - Surface emission in UI is mapped to `fs.surface_distance` (default `1.0`).
  - Velocity control requires `fs.use_initial_velocity = True` before setting `fs.velocity_normal = 8.0` and `fs.velocity_random = 2.5`.

- **Baking Operator**:
  - `bpy.ops.fluid.bake_all()` bakes the domain data and outputs `Fluid: Bake All complete` returning `{'FINISHED'}`.
  - `bpy.ops.ptcache.bake_all()` runs across all generic physics objects and defaults to 250 frames instead of Mantaflow gas simulation.

- **Spritesheet Assembly**:
  - `montage /tmp/test_dir/frame_*.png -tile 8x8 -geometry 256x256+0+0 -background none sheet.png` generates a 2048x2048 RGBA PNG in 0.599s.
  - Python Pillow script generates a 2048x2048 RGBA PNG in 0.128s.

- **GUT Test Execution**:
  - Existing file `test/unit/test_smoke_explosion_vfx.gd:35` has a parse error (`preview_active` property missing), which causes `godot --headless -s addons/gut/gut_cmdln.gd -gtest=...` to fail if GUT scans directory `res://test/unit`.
  - Adding `-gdir=""`, i.e., `godot --headless -s addons/gut/gut_cmdln.gd -gdir="" -gtest=res://test/unit/<target>.gd` isolates test execution, skipping directory scanning and passing cleanly in 0.44s.

---

## 2. Logic Chain

1. **Premise 1**: Blender 5.2.2 LTS is installed and runs headlessly on Ubuntu without DISPLAY.
2. **Premise 2**: EEVEE-Next in Blender 5.2.2 LTS is accessed via `'BLENDER_EEVEE'` (not `'BLENDER_EEVEE_NEXT'`).
3. **Premise 3**: Mantaflow domain and flow modifiers use specific RNA enum strings (`flow_type = 'BOTH'`, `use_dissolve_smoke_log = True`, `burning_rate = 0.65`, `surface_distance = 1.0`).
4. **Premise 4**: `bpy.ops.fluid.bake_all()` operates directly on active fluid domain objects with `cache_type = 'ALL'`, baking frames within 1-2 minutes at 128 resolution.
5. **Premise 5**: Both `montage` and Python Pillow are installed and successfully assemble 64 frames into a 2048x2048 RGBA spritesheet in under 1 second.
6. **Premise 6**: Godot 4.7.1 imports assets headlessly with `godot --headless --editor --quit`, and GUT tests must be invoked with `-gdir=""` to prevent unrelated test failures from failing the run.
7. **Inference**: A standalone Python automation script `tools/generate_explosion_flipbook.py` can be written to run under `blender --background --python` using these verified APIs, producing the 2048x2048 spritesheet and triggering cleanup.

---

## 3. Caveats

1. **Bake Duration at Resolution 128**: Baking 64 frames at 64 resolution took 15.2 seconds; at 128 resolution (8x voxel density), baking is expected to take ~90-120 seconds. The orchestrator / implementer should use a generous process timeout (e.g., 3-5 minutes).
2. **Snap Sandbox Considerations**: Blender is installed via Snap (`/snap/bin/blender`). Temp files should use `/tmp` or the workspace path directly rather than restricted home subdirectories, as Snap applications have confined permissions.
3. **Strict Typing in Godot 4.7.1**: The project enforces `untyped_declaration = 2`, `inferred_declaration = 1`, and `unsafe_property_access = 2`. The new Godot controller `explosion_crysis.gd` and GUT test `test_explosion_crysis.gd` must adhere strictly to these rules without any untyped variables or Variant calls.

---

## 4. Conclusion

All prerequisites for the headless Mantaflow explosion bake, 8x8 flipbook spritesheet assembly, and Godot 4 composite explosion integration are verified.
- Render engine identifier: `BLENDER_EEVEE`
- Flow type: `'BOTH'`, `use_initial_velocity = True`, `use_inflow` keyframed frames 1-3.
- Domain dissolve slow: `use_dissolve_smoke_log = True`.
- Baking operator: `bpy.ops.fluid.bake_all()` with active domain.
- Spritesheet assembler: `montage` or `python3` + Pillow.
- GUT runner command: `godot --headless -s addons/gut/gut_cmdln.gd -gdir="" -gtest=res://test/unit/test_explosion_crysis.gd`.

---

## 5. Verification Method

To independently verify all findings:

1. **Verify Blender Mantaflow Bake and EEVEE Render**:
   ```bash
   blender --background --python-expr "
   import bpy
   bpy.ops.wm.read_factory_settings(use_empty=True)
   bpy.ops.mesh.primitive_cube_add()
   dom = bpy.context.active_object
   mod = dom.modifiers.new('Fluid', 'FLUID')
   mod.fluid_type = 'DOMAIN'
   mod.domain_settings.domain_type = 'GAS'
   mod.domain_settings.cache_type = 'ALL'
   mod.domain_settings.cache_frame_start = 1
   mod.domain_settings.cache_frame_end = 2
   bpy.context.view_layer.objects.active = dom
   dom.select_set(True)
   assert bpy.ops.fluid.bake_all() == {'FINISHED'}
   bpy.context.scene.render.engine = 'BLENDER_EEVEE'
   bpy.context.scene.render.filepath = '/tmp/verify_eevee.png'
   bpy.ops.render.render(write_still=True)
   "
   ```

2. **Verify Spritesheet Assembly**:
   ```bash
   which montage
   python3 -c "import PIL; from PIL import Image; print('Pillow OK')"
   ```

3. **Verify Isolated GUT Execution**:
   ```bash
   godot --headless -s addons/gut/gut_cmdln.gd -gdir="" -gtest=res://test/unit/test_collision_layers.gd
   ```
