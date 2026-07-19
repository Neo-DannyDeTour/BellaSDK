# Illusionist's Journal

## CRITICAL LEARNINGS
- Shader compilation stutters: Specific to this project's asset pipeline, ensure custom shaders are simple and avoid heavy dynamic texture sampling unless cached.
- Visual clutter issues: Previous VFX PRs showed performance drops with excessive particle counts. Enforce strict `one_shot = true` and `queue_free()` for transient bursts to maintain 60 FPS.
