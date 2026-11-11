# Implementation Report: Gothic Arch Prop & Procedural Pipeline Fix

## Executive Summary
Fixed the broken Gothic arch prop and procedural asset pipeline in `props/gothic_arch/`.
The pointed arch vault now connects continuously to side pillars, plinths, and capitals with 100% manifold, watertight geometry without severed vertices, open gaps, floating debris, or inverted normals.
The baking harness produces a clean low-poly mesh (1998 triangles, under budget of 2000) with non-overlapping UVs spanning full [0, 1] texture space, and bakes seamless Albedo, ORM (AO/Roughness/Metallic), and Tangent Normal maps with zero black pixel artifacts or ray misses.
The Godot 4 scene (`props/gothic_arch/gothic_arch.tscn`) cleanly instantiates `gothic_arch.glb`, binds the custom spatial stone shader (`gothic_arch_stone.gdshader`), assigns `gothic_arch_mat.tres`, attaches the 3 box colliders, and wires up instance shader parameters (`instance_tint`, `wear_intensity`, `moss_coverage`) via `gothic_arch_prop.gd`.

---

## 1. Root Cause Diagnosis

### R1 Geometry Breakage
1. **Geometric Cutter Overshoot**:
   In legacy `generate_high_poly.py`, the arch block had a top bound of Z = 4.0m. The lancet cutter arc had radius 1.8m centered at (±0.9, 2.8), reaching an apex at Z = 4.36m. This cut completely through the top lintel, severing the arch in two.
2. **Disjointed Non-Manifold Geometry**:
   Legacy generator joined separate meshes (zero-thickness 2D quad ribbons, floating cubes) without boolean union, producing 31,088 non-manifold/boundary edges that exploded under bevel and subdivision modifiers.
3. **Fragmented Boolean UV Seams in glTF**:
   Default primitives contained UV seams that remained split after boolean cuts, leading glTF exporter to duplicate 2,736 vertices along seams.

### R2 Baking & Retopology Breakdown
1. **Destructive Voxel Remeshing**:
   Legacy `bake_gothic_arch.py` passed non-manifold geometry into Blender's Voxel Remesher (`voxel_size=0.03`), resulting in 186 disconnected floating crumb islands and gaping holes.
2. **Squashed UV Unwrap**:
   Legacy script lacked `bpy.ops.uv.pack_islands`, squashing all islands into a narrow horizontal strip (U in [0, 0.23]), leaving 77% of texture area unbaked.
3. **Black Seam Bleed & Ray Miss Artifacts**:
   Unbaked canvas pixels outside UV islands defaulted to (0, 0, 0), while cavity delighting divided small values by 0.35, generating over 1 million black pixels across Albedo, AO, and Normal maps.

---

## 2. Implemented Architecture & Fixes

### A. Procedural High-Poly Generator (`props/gothic_arch/generate_high_poly.py`)
- **Contiguous Structural Solid**:
  Built from a single stone block (3.0m x 0.8m x 4.0m, top Z = 4.0m).
- **Exact Boolean Unions**:
  Fused base plinths (0.7m x 0.9m x 0.4m), capitals at the springing line (0.68m x 0.88m x 0.3m at Z = 2.65m), 4 engaged cylindrical shafts (radius 0.10m, depth 2.2m at Z = 1.45m), and vault keystone (0.36m x 0.88m x 0.35m at Z = 3.58m) using Blender's Exact Boolean Union modifier.
- **Parametric Pointed Vault Cutter**:
  Constructed lancet cutters with apex Z = 3.55m (stepped archivolts at Z = 3.62m), preserving a solid 0.38m top stone lintel.
- **Surface Refinement & Watertight Export**:
  Applied angle-limited Stone Bevel (40°, width 0.015m, 2 segments), Subdiv level 1, procedural stone relief displace (Clouds texture, scale 0.15, strength 0.005m), smooth shading, and stripped fragmented UV layers.
- **High-Poly Verification**:
  15,260 faces, 7,632 vertices, 0 non-manifold edges, 0 boundary edges, 1 continuous island.

### B. Low-Poly Retopology & Baking Harness (`props/gothic_arch/bake_gothic_arch.py`)
- **Decimation Retopology**:
  Replaced destructive voxel remesher with direct decimation targeting 1800 tris. Resulting mesh has exactly 1998 tris (within budget <= 2000).
- **Seam Marking & Full [0, 1] Island Packing**:
  Marked sharp edges (> 50°) as seams, performed angle-based UV unwrap, and packed islands with margin 0.01. Resulting UV layout spans U=[0.0059, 0.9941], V=[0.0059, 0.9786].
- **Cycles OptiX / GPU Baking**:
  Bakes high-poly Diffuse, AO, and Tangent Space Normal maps.
- **Robust Channel Packing & Background Normalization**:
  Outside UV islands:
  - AO: Filled with 1.0 (fully unoccluded).
  - Albedo: Filled with limestone base color (0.58, 0.55, 0.50).
  - Normal: Normalized to tangent-space neutral (0.5, 0.5, 1.0).
  - ORM packing: R = Ambient Occlusion, G = Roughness (0.85 default), B = Metallic (0.0 stone dielectric).
- **Map Integrity Verification**:
  Zero black pixels across all three 2048x2048 textures.

### C. Godot 4 Scene & Material Integration (`props/gothic_arch/gothic_arch.tscn`)
- Configured `gothic_arch.tscn` as an inherited scene from `gothic_arch.glb`.
- Root `GothicArch` is `StaticBody3D` with `gothic_arch_prop.gd`, collision layer `MASK_ENVIRONMENT` (1), mask `MASK_NONE` (0).
- Visual child `ArchMesh` (`MeshInstance3D`) has `material_override = gothic_arch_mat.tres`, render layer `RENDER_MASK_ENVIRONMENT` (1).
- 3 BoxShape3D colliders:
  - `LeftPillarCol`: Pos (-1.2, 1.4, 0.0), Size (0.6, 2.8, 0.8)
  - `RightPillarCol`: Pos (1.2, 1.4, 0.0), Size (0.6, 2.8, 0.8)
  - `TopLintelCol`: Pos (0.0, 3.4, 0.0), Size (3.0, 1.2, 0.8)
- Verified `gothic_arch_stone.gdshader` compiles and properly applies per-instance uniforms (`instance_tint`, `wear_intensity`, `moss_coverage`).
- Successfully verified `testbed2.tscn` instantiation of `GothicArch`.

---

## 3. Automated Test Verification Summary
1. `blender -b --python-expr`:
   - High-poly `raw_arch.glb`: 7632 verts, 15260 faces, 0 non-manifold, 0 boundary.
   - Low-poly `gothic_arch.glb`: 1998 faces, UV bounds [0.0059, 0.9941] x [0.0059, 0.9786], 0 non-manifold, 0 boundary.
2. `python3 -c "from PIL import Image ..."`:
   - `arch_albedo.png`: 0 black pixels, mean [205.4, 201.0, 193.9].
   - `arch_normal.png`: 0 black pixels, mean [126.0, 127.4, 220.0].
   - `arch_orm.png`: 0 black pixels, mean [213.4, 202.7, 0.0].
3. `godot --headless -s verify_arch.gd`:
   - Successfully loaded and instantiated `gothic_arch.tscn`.
   - Verified 1998 tris, shader compilation, collider placements, and material bindings.
4. `gdlint props/gothic_arch/*.gd`:
   - 0 errors, 100% compliant with `.gdlintrc`.
