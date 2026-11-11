## 2026-11-11T05:24:43Z
You are Explorer 2 for the Project Survey phase.
Your working directory is: /home/dkd/Documents/BellaSDK/.agents/teamwork/explorer_survey_2/
You must create your working directory files (e.g. progress.md, analysis.md, handoff.md) inside this directory.

MANDATORY FIRST STEP: Read /home/dkd/Documents/BellaSDK/.agents/teamwork/ORIGINAL_REQUEST.md before doing anything else.

Your objective:
Investigate Godot VFX conventions, existing reference files, and BellaSDK architecture requirements.
Specifically:
1. Inspect `res://vfx/explosion_shockwave.gdshader`:
   - What shader type is it (`spatial`, `canvas_item`)?
   - What uniforms does it define (e.g. `distortion_strength`, `radius`, `thickness`, `feather`, etc.)?
   - How does it sample `SCREEN_TEXTURE`? What mesh type does it expect?
2. Inspect `res://test/unit/test_smoke_explosion_vfx.gd`:
   - How is the GUT test constructed?
   - What assertions and setup/teardown methods are used?
   - How does it instantiate VFX scenes and test properties?
3. Survey existing VFX scenes and particle materials in `res://` to understand standard node structure, QuadMesh orientation, standard materials.
4. Review BellaSDK project rules (in `GEMINI.md`, `res://core/`):
   - Strict typing rules (`untyped_declaration = 2`, `inferred_declaration = 1`, etc.).
   - `.gdlintrc` formatting constraints (100 char limit, tab indent, class-definitions-order, leading underscore rules).
   - Event architecture, signal connections, tween handling (`Utilities.reset_tween()` / standard Tween lifecycle).
   - Node caching, `assert()` in `_ready()`, `##` BBCode docstrings.
5. Record all findings in `/home/dkd/Documents/BellaSDK/.agents/teamwork/explorer_survey_2/analysis.md` and provide a complete handoff report in `/home/dkd/Documents/BellaSDK/.agents/teamwork/explorer_survey_2/handoff.md`.
6. Send a completion message to orchestrator with summary and links to the files.
