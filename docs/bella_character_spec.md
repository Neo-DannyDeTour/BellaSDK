# Bella Canonical Character Specification

Defines the canonical likeness, anatomy, topology, lookdev shaders, and first-person body setup for **Bella** (`BellaSDK` / Godot 4.7.1 Forward+).

---

## 1. Identity & Likeness Targets

- **Aesthetic**: Semi-realistic 2004 Half-Life 2 / Alyx Vance style grounded in post-Soviet realism.
- **Face Likeness**: Kazakh-Russian Eurasian (`asian=0.46`, `caucasian=0.54`, `african=0.0`, `age=0.28`), refined nose bridge/tip, high cheekbones, delicate heart/V-jaw, natural non-pouty lips, and relaxed hooded-almond eyelids resting over the upper ~15–20% of the iris.
- **Hair**: Layered platinum-blonde bob (`Bella_Hair_Cap` with center scalp part + ash interior shadow; `Bella_Hair_Cards` with organic C-curl locks and soft brow-grazing bangs).
- **Eyes**: Natural medium-dark hazel-olive irises with subtle upper-eyelid shadow gradient, warm-white sclera, and crisp limbal ring.

---

## 2. Body Proportions & Garments

- **Height**: `1.64m` standing (`Bella_Head` + `Bella_Body` seamless neck partition at `Z = 1.385m`).
- **Build**: Slim athletic-curvy frame (`weight=0.22`, `muscle=0.34`, `proportions=0.56`), shapely full bust (`cupsize=0.84`, `firmness=0.74`) on a slim ribcage, lean waist, slender athletic legs, and firm, perky, smoothly rounded buttocks (`buttocks-volume-incr=0.34`) without bloated hips or thighs.
- **Outfit**: Fitted black short-sleeve V-neck mini-dress (`M_bella_v2_dress_black`) with crisp white lapel collar and cuff trim (`M_bella_v2_white_trim`), sleek slim A-line pleated mini-skirt (`M_bella_v2_skirt`), sheer dark stockings (`M_bella_v2_stockings`), buckled combat boots (`M_bella_v2_boots` + `M_bella_v2_boot_buckles`), fingerless gloves with brass accents (`M_bella_v2_gloves` + `M_bella_v2_glove_brass`), and round thin-rimmed glasses.

---

## 3. Topology, Blendshapes & GLB Assets

- **Static Master**: `assets/models/bella_v2/bella_v2.glb`
  - **15 Modular Meshes** (`EXPECTED_15_MESHES`):
    - `Bella_Body`, `Bella_Dress`, `Bella_Skirt`, `Bella_Boots`, `Bella_Gloves`
    - `Bella_Head`, `Bella_Eye_L`, `Bella_Eye_R`, `Bella_Eyelashes`
    - `Bella_Teeth_Upper`, `Bella_Teeth_Lower`, `Bella_Tongue`
    - `Bella_Hair_Cap`, `Bella_Hair_Cards`, `Bella_Glasses`
  - **Facial Blendshapes**: 52 standard ARKit keys (`ARKIT_52`) on `Bella_Head`; 6 eyelid keys (`EYELASH_6`) on `Bella_Eyelashes`.
  - **Dedicated 2K Head Atlas**: `Bella_Head` UVs occupy `[0.04, 0.96]` for 3-view (front/side/back) seamless projection and baked facial AO.
- **NPC Rigged**: `assets/models/bella_v2/bella_v2_rigged.glb` (27 bones, 15 meshes, 52/6 ARKit keys, 60 FPS `idle`, `walk`, `run`).
- **FPS Player Rigged**: `assets/models/bella_v2/bella_player.glb` (22 bones, 7 meshes, 11 60 FPS loops; `Bella_Body` and `Bella_Dress` bisected at `Z = 1.355m` with back/side collar split into `Bella_CollarShadow`).

---

## 4. 2004 Alyx Vance Lookdev & Shader Targets

- **Skin (`shaders/character_skin_sss.gdshader` -> `bella_v2_face.tres`, `bella_v2_body_skin.tres`)**:
  - Matte-satin porcelain finish (`ROUGHNESS` clamped `0.52..0.84`, `specular_amount <= 0.30`), restrained `sss_mode_skin` transmittance, isotropic tileable micro-pore normal (`bella_v2_skin_micro_normal.png` at `detail_normal_scale ~ 0.03`), and baked facial AO.
- **Eyes (`shaders/character_eye.gdshader` -> `bella_v2_eye.tres`)**:
  - Natural hazel-olive depth (`iris_brightness ~ 1.0`, zero neon glow), subtle inner-scatter floor lift (`~0.015`), wet cornea clearcoat (`clearcoat_amount=1.0`, `clearcoat_roughness=0.02`), subtle iris parallax (`0.015`), limbal darkening (`0.25`), and upper-eyelid shadow darkening.
- **Hair & Lashes (`shaders/character_hair_cards.gdshader` -> `bella_v2_hair.tres`, `bella_v2_eyelashes.tres`)**:
  - `ALPHA_SCISSOR_THRESHOLD` (`~0.45..0.48`, zero `ALPHA_HASH` stipple), `cull_disabled`, smooth anisotropy (`~0.50`), bleed-padded alpha=0 borders, and restrained platinum midtones (`0.48..0.84` albedo, soft `BACKLIGHT`/`RIM`) so strands never blow out to `#FFFFFF`.
- **Collar & Skirt (`bella_v2_white_trim.tres`, `bella_v2_dress_black.tres`, `bella_v2_skirt.tres`)**:
  - `cull_mode = 2` (double-sided) so collar folds and skirt hems render cleanly from all angles.

---

## 5. FPS Body Layers & Look-Down POV Spec

- **Scene Wiring**: `player/player.tscn` (`Camera3D` `near = 0.025`, `cull_mask = 1048573` excluding Layer 2) + `npcs/bella/bella_player.tscn` (`BellaModel` rotated 180 deg around Y) + `player/player_body_controller.gd`.
- **Render Layers**:
  - **Layer 1 (`ENV_LAYER_MESHES`)**: `Bella_TorsoLegs`, `Bella_Dress`, `Bella_Skirt`, `Bella_Boots` (visible in first-person + casts shadows).
  - **Layer 2 (`PLAYER_LAYER_MESHES`)**: `Bella_Arms`, `Bella_Gloves`, `Bella_CollarShadow` (culled from FPS camera while casting shadows via `SHADOW_CASTING_SETTING_ON`).
- **Look-Down Framing (`-75` to `-89` deg, standing & crouching)**: Smooth pitch-driven alignment (`LOOK_DOWN_Z_OFFSET = 0.13`, `CROUCH_BODY_Y_OFFSET = -0.18`, `CROUCH_BODY_Z_OFFSET = 0.04`) frames anterior chest skin, white V-neck trim, bust, and legs/boots cleanly with zero hollow neck hole, zero floating collar ring, and zero near-plane clipping.

---

## 6. Reference Image Paths

- **Head / Face**:
  - `/home/dkd/Downloads/Tunnel Vision/Bella_ref_front_head.jpeg`
  - `/home/dkd/Downloads/Tunnel Vision/Bella_ref_side_head.jpeg`
  - `/home/dkd/Downloads/Tunnel Vision/Bella_ref_back_head.jpeg`
  - `/home/dkd/Downloads/Tunnel Vision/Bella_haircut_ref.jpeg`
- **Body & Proportions**:
  - `/home/dkd/Downloads/Tunnel Vision/Bella_swimsuit_side.png`
  - `/home/dkd/Downloads/Tunnel Vision/Bella_body_side_ref.jpeg`
  - `/home/dkd/Downloads/Tunnel Vision/Bella_body_back_ref.jpeg`
  - `/home/dkd/Downloads/Tunnel Vision/bella-tpose.png`
- **FPS POV Target**:
  - `/home/dkd/Downloads/Tunnel Vision/proper_view_DELETE.png`
