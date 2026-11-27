# Dynamic Ocean System for Godot 4

Self-contained dynamic ocean system with GPU-driven FFT wave simulation, clipmap surface mesh, cascade parameters, and foam/spray particles.

## Contents
- `dynamic_ocean.tscn`: Root ocean scene ready to drop into any 3D level.
- `ocean.gd`: Master ocean node script managing quality settings, cascades, player tracking, and material bindings.
- `wave_generator.gd`: Compute-shader wave generation pipeline.
- `wave_cascade_parameters.gd`: Resource definition for wave cascades (wind, direction, tile scale, foam).
- `waveheight_script.gd`: Buoyancy sample helper for querying wave heights at arbitrary global coordinates.
- `materials/`:
  - `mat_ocean.tres`: Ocean surface shader material.
  - `mat_spray.tres`: Spray particle process material.
- `shaders/`:
  - `ocean_water.gdshader`: Ocean surface visual shader.
  - `ocean_spray.gdshader`: Spray quad visual shader.
  - `ocean_spray_particle.gdshader`: Spray compute/particle shader.
  - `compute/`: GLSL compute shaders (`downsample_compute.glsl`, `fft_butterfly.glsl`, `fft_compute.glsl`, `fft_unpack.glsl`, `spectrum_compute.glsl`, `spectrum_modulate.glsl`, `transpose.glsl`).
- `meshes/`: Pre-tessellated clipmap meshes (`clipmap_low.obj`, `clipmap_high.obj`, `clipmap_high_8k.obj`).
- `textures/`: Particle textures (`ocean_spray.png`).
- `sounds/`: Ambient ocean audio tracks (`Ocean.wav`, `StormOcean.wav`).

## External Engine Requirement
- Requires `RenderingContext` (`RenderingDevice` helper wrapper) in your project to dispatch compute shaders. If porting into a project without BellaSDK, ensure `res://core/render_context.gd` (or an equivalent RD wrapper) is present.
