# Janitor Critical Learnings

- `RenderingDevice` RIDs (such as those for compute shaders, buffers, and textures) bypass Godot's normal garbage collection and must be manually freed using `rd.free_rid()` during `NOTIFICATION_PREDELETE` to prevent severe VRAM leaks.
- VRAM Leaks in Godot 4: `RenderingDevice` RIDs (like compute pipelines, uniform sets, and storage buffers) bypass standard Godot Garbage Collection. They must be manually freed using `rd.free_rid(rid)` prior to clearing arrays or resetting references, particularly during `NOTIFICATION_PREDELETE` or active resource regeneration.

## 🧹 Janitor Log - Duplicate Texture Cleanup

- Identified a batch of unused `godiva` duplicate PNG texture maps in `shared/` (`shared/godiva_Godiva_*` and `shared/godiva_godiva_*`) using a python script.
- Verified these textures were purely orphaned assets via rigorous code and file search, confirming they were absent from any scripts (`.gd`), `.tscn`, or `.tres` files, aside from some redundant cached importer configurations.
- Successfully reclaimed repository space and removed memory bloat without affecting the core geometry file `shared/godiva.glb`.
