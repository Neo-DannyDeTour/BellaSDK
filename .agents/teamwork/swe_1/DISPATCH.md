## 2026-11-11T05:08:58Z

This is a single self-contained fix; keep it small and focused. Fix the broken gothic arch prop and procedural asset pipeline in `props/gothic_arch/` so the arch vault cleanly connects to the side pillars without severed mesh geometry, inverted normals, or voxel remesh artifacts for production use in BellaSDK.

Integrity mode: development

## Requirements

### R1. Arch Geometry & Pillar Connection
The arch procedural generation in `props/gothic_arch/generate_high_poly.py` must produce continuous, manifold stone archway geometry where the pointed vault connects solidly to the side pillars, capitals, and plinths without floating pieces, gaps, severed geometry, or inverted normals.

### R2. High-to-Low Bake and Texture Generation
The retopology and baking harness in `props/gothic_arch/bake_gothic_arch.py` must produce a clean low-poly mesh with valid, non-overlapping UVs and bake Normal, ORM (Ambient Occlusion, Roughness, Metallic), and Albedo texture maps without voxel remeshing holes, baking ray misses, or black artifacts.

### R3. Engine Scene Integration
The exported low-poly GLB and textures must integrate into the Godot 4 scene (`props/gothic_arch/gothic_arch.tscn`), loading the material shader and controller script without missing resources, broken node references, or transform mismatches.

## Acceptance Criteria

### Mesh Geometry & Integrity
- [ ] `generate_high_poly.py` runs headlessly in Blender and exports high-poly geometry with an unbroken, contiguous connection between the pointed arch vault and pillars.
- [ ] The generated mesh contains no disconnected floating geometry, open holes between vault and pillars, or inverted face normals.

### Baking & Asset Pipeline
- [ ] `bake_gothic_arch.py` executes headlessly in Blender without errors, producing `gothic_arch.glb` within the target triangle budget.
- [ ] Low-poly UVs are non-overlapping and unwrapped within [0, 1] UV space.
- [ ] Baked Normal, ORM, and Albedo maps are exported without projection ray misses or black seam artifacts.

### Godot 4 Scene Verification
- [ ] `props/gothic_arch/gothic_arch.tscn` opens and instantiates cleanly in Godot 4 headlessly.
- [ ] The arch mesh renders with the custom stone shader (`gothic_arch_stone.gdshader`) and baked textures assigned.

Working directory: .agents/teamwork/swe_1/
Identity: SWE Light Orchestrator
Original Request Path: /home/dkd/Documents/BellaSDK/.agents/teamwork/ORIGINAL_REQUEST.md
