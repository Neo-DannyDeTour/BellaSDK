# BellaSDK Directory Structure & Domain Architecture

Defines the project layout of BellaSDK (Godot 4.7.1 / Forward Plus / Jolt Physics).

---

## High-Level Layout

```
BellaSDK/
├── assets/          # Static art, audio, materials, 3D models, decals, fonts, HDRs
├── core/            # Engine architecture, autoloads, singletons, pools, utilities
├── dynamic_ocean/   # Ocean simulation meshes and compute shaders
├── enemies/         # AI characters, drones, turrets, and combatants
├── environment/     # World geometry, weather, soundscapes, signs, lighting
├── interactables/   # Doors, buttons, cables, sockets, valves, ragdolls, pickups
├── levels/          # Playable level scenes, chunks, testbeds, and blockouts
├── player/          # First-person controller, cameras, and player systems
├── props/           # Modular props (gates, crates, etc.)
├── scenes/          # Standalone preview and showcase scenes
├── shaders/         # Custom `.gdshader` files
├── test/            # GUT unit tests (`test/unit/`) and visual test grids
├── tools/           # In-editor utilities, Blender/TRELLIS/SFX pipelines, CI helpers
├── translations/    # Localization CSVs and compiled `.translation` resources
├── triggers/        # Hazard fields, teleport portals, arrival/attractor triggers
├── ui/              # User interface panels, HUDs, menus, and debug overlays
├── vfx/             # Visual effects (smoke, blood, impacts, particles, shaders)
├── weapons/         # Weapon scenes, viewmodels, and ballistics
└── world/           # World streaming and chunk management
```

---

## Key Domain Notes

- **`assets/`**: Organized under `assets/audio/`, `assets/decals/`, `assets/dev_meshes/`, `assets/fonts/`, `assets/materials/`, `assets/models/`.
- **`core/`**: Shared systems (`CollisionLayers`, `NodeQuery`, `AudioPool`, `MaterialCache`, `MathUtils`, `Utilities`, `ObjectPool`, `StateMachine`, `Events`, `SaveManager`, `GraphicsManager`, `SpikeForensics`).
- **`tools/`**:
  - `tools/blender/`: Headless Blender generators (`run.py`, `postprocess_trellis.py`, `common/`).
  - `tools/scripts/`: Asset & lint scripts (`trellis_asset_gen.py`, `colab_asset_sync.py`, `format_and_lint.sh`).
  - `tools/generate_sfx.py`: ElevenLabs / AudioLDM2 SFX generator.
- **`test/unit/`**: GUT 9.7.1 unit tests (`res://test/unit/test_*.gd`) configured via `.gutconfig.json`.
