# Scanning: capture guide (phone)

Goal: game-ready 3D assets (mesh + PBR textures) of real places, built as a **modular kit**:
props, materials and façade pieces — not whole streets in one go.

## Light (most important for correct textures)
- **Overcast day**, or full shade. No hard sun, no sharp shadows: whatever light is in the photo ends
  up baked into the texture, and the game lights it again.
- Avoid wet surfaces and reflections (shop windows, polished metal) unless that is the point.
- Same session, same light: don't mix morning and afternoon on one object.

## Camera settings
- Photos > video. If you shoot video: 4K, 30 fps, move **slowly**, no stabilisation crop.
- Lock focus/exposure (long-press on most phones). No HDR, no beauty/portrait mode, no zoom.
- Every point of the object must appear in **3+ photos** with **60–80 % overlap** between neighbours.

## How to move
| Asset | How | Photos |
|---|---|---|
| **Prop** (bench, fountain, bin, manhole cover) | 3 rings around it: low (knee), middle (chest), high (arms up, looking down). One photo every ~10–15° | 60–150 |
| **Material** (panot tiles, brick, render, cobbles) | ~1×1 m patch, camera parallel to the surface at ~1 m, grid of overlapping shots + 4 oblique shots | 20–40 |
| **Façade** (ground + first floor) | Walk parallel to the wall at 3–5 m, one photo per step; repeat from the other side of the street, then oblique shots at corners and recesses (doors, balconies) | 80–300 per 10 m |
| **Detail** (door, balcony, sign base) | Like a prop, closer, plus straight-on shots | 40–100 |

## Scale and colour (optional, improves accuracy)
- Put a known object in the first shots (A4 sheet, 1 m tape) for real-world scale.
- A grey card / colour checker in one shot helps correct white balance.

## People, cars, legal
- Shoot when the street is quiet; people and cars moving through are removed automatically, but
  fewer is better.
- Faces and number plates are blurred in processing. Real shop signs and brands are replaced with
  fictional ones before anything goes into a game.
- Use only your own photos (no Google Maps/3D Tiles imagery).
- No drones without the required permits.

## Naming
`SCAN-<area>_<asset>_<YYYYMMDD>/` with the photos inside, e.g. `SCAN-raval_banco-plaza_20261008/`.
