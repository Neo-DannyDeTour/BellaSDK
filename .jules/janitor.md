# Janitor Critical Learnings

- `RenderingDevice` RIDs (such as those for compute shaders, buffers, and textures) bypass Godot's normal garbage collection and must be manually freed using `rd.free_rid()` during `NOTIFICATION_PREDELETE` to prevent severe VRAM leaks.
- VRAM Leaks in Godot 4: `RenderingDevice` RIDs (like compute pipelines, uniform sets, and storage buffers) bypass standard Godot Garbage Collection. They must be manually freed using `rd.free_rid(rid)` prior to clearing arrays or resetting references, particularly during `NOTIFICATION_PREDELETE` or active resource regeneration.
