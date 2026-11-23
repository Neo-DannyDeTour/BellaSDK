# Review loop: correcting motion with a human or an AI reviewer

1. `v2m run` (or `v2m post`) produces `clean.npz` + `metrics.json` per person.
2. `v2m review clean.npz --track-dir <track> --out sheet.png` picks key frames:
   - extreme poses (local minima of pose speed — the poses an animator would key),
   - frames where the estimator is least confident,
   - frames with the highest 2D reprojection error (when keypoints and camera are available),
   - plus enough coverage that no gap is larger than 2·T/N frames.
   Each tile shows the video frame with the projected skeleton (when available) and front/side
   views. Left = blue, right = red, contacts = green squares.
3. The reviewer compares and writes `edits.json`. Rules for AI reviewers:
   - Only fix what the video clearly contradicts. Never "beautify": the goal is fidelity.
   - Name the frame(s) and the evidence in `note`.
   - Prefer small local rotations with `falloff` ≥ 3 frames; never edit a single frame without falloff.
   - Contact errors (foot sliding while visibly planted, or planted while visibly lifted) are fixed
     with `set_contact`, then re-run `v2m post` so the foot lock is recomputed.
4. `v2m edit clean.npz edits.json --out fixed.npz`, then review again until the sheet matches.
   Every edit is stored in `meta.history`, so the result is reproducible and auditable.

## Edit operations

| op | fields | effect |
|---|---|---|
| `rotate` | `joint`, `frames`, `euler_deg`, `order` (XYZ), `space` (`local`/`parent`), `falloff` | adds a rotation to a joint |
| `set_rotation` | `joint`, `frames`, `euler_deg`, `order`, `falloff` | blends a joint towards an absolute local rotation |
| `offset_root` | `frames`, `delta_m`, `falloff` | moves the whole body |
| `set_contact` | `joint`, `frames`, `value` | forces contact on/off for the next foot lock |
| `trim` | `frames` | keeps only that inclusive range |
