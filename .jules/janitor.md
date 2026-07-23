# Janitor Critical Learnings

- `RenderingDevice` RIDs (such as those for compute shaders, buffers, and textures) bypass Godot's normal garbage collection and must be manually freed using `rd.free_rid()` during `NOTIFICATION_PREDELETE` to prevent severe VRAM leaks.
