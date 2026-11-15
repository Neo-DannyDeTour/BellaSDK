---
name: factory
description: Software factory pipeline for BellaSDK. Auto-detects required asset/audit skills (3d, pbr, animate, audio-generation, automation) from feature prompts, locks specs, dispatches sequential asset + parallel code workers, and runs Godot 4.7.1 verification.
---

# BellaSDK Software Factory

Repeatable multi-stage pipeline: **Intake & Route -> Dispatch (Assets -> Code) -> Verify -> Ship**.

## Stage 1: Intake, Auto-Detection & Locked Spec
1. **Auto-Detect Activities**: Scan the prompt for implicit asset, art, audio, or audit needs (never require explicit `/3d`, `/animate`, etc.):
   | Prompt Signal | Skill / Agent | Skill Path / Target |
   | :--- | :--- | :--- |
   | 3D meshes, props, characters, weapons, vehicles | `3d` (+ `image-generator` if no concept plate) | `.agents/skills/3d/SKILL.md` |
   | Rigging, skinning, animations, mocap, retargeting | `animate` (after `3d` if mesh is new) | `.agents/skills/animate/SKILL.md` |
   | Seamless textures, surfaces, ORM materials | `pbr` | `.agents/skills/pbr/SKILL.md` |
   | SFX, loops, footsteps, weapon blasts, ambience | `audio-generation` | `.agents/skills/audio-generation/SKILL.md` |
   | 2D UI icons, HUD art, concept plates | `image-generator` subagent | `invoke_subagent` |
   | FPS/perf optimization, architecture/scene audit | `automation`, `godot-performance-audit`, `godot-arch-check` | `.agents/skills/automation/SKILL.md` |
   *(Read each triggered `SKILL.md` before executing its pipeline, or delegate to a worker that reads it.)*
2. Inspect existing callers, signals, and `docs/DIRECTORY_STRUCTURE.md`.
3. Run Grilling on open architectural branches, edge cases, and scene dependencies.
4. Output a concise **Locked Spec** (detected skills, asset outputs, files, signals, node contracts, acceptance tests) and wait for `go`.

## Stage 2: Dispatch (Assets First -> Code & Scenes)
### Phase 2A: Asset Pipelines (if any detected)
Run asset skills before scene/GDScript wiring so real `.import`/`.uid` files exist on disk:
- Run `image-generator` -> `3d` -> `animate` sequentially when chained; run `pbr` and `audio-generation` in parallel.
- Trigger Godot headless import if needed so `.uid` files exist before Phase 2B.

### Phase 2B: Code & Scene Implementation
Choose execution mode by scope:
- **Single-module / tight coupling**: Work directly or use `invoke_subagent` (`godot-specialist`).
- **Multi-file / parallelizable**: Use `swarm` (`action: "add"`, `workspace: "share"` for editors, `inherit` for reviewers/testers):
  - `builder-*`: Implement assigned slice per Locked Spec and `GEMINI.md` typing rules.
  - `verifier`: Run Stage 3 gates and report failures back to `builder-*`.

## Stage 3: Automated Quality Gate
All checks must pass before shipping:
1. `gdformat --check <changed_files>`
2. `gdlint <changed_files>`
3. `godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit -gignore_pause`
4. Run `automation` / `godot-performance-audit` / `godot-arch-check` if triggered in Stage 1.

## Stage 4: Ship
1. Land worker changes into main working copy and `kill` finished swarm workers.
2. Output concise diff summary + `Skipped:` / `Risk:` audit.
3. Propose conventional commit (`<type>(<scope>): <summary>` <= 72 chars) if requested.
