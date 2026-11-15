---
name: audio-generation
description: Generates dry, spatialization-ready sound effects (SFX), weapon blasts, loops, and soundscapes using ElevenLabs SFX API or local AudioLDM2 with FFmpeg silence trimming, normalization, and seamless loop crossfading.
metadata:
  icon: volume-2
---

# Audio Generation Skill (`/audio-generation`, `/sound`)

Generates Godot 3D-ready sound effects and seamless loops directly into `res://assets/audio/` with automatic zero-latency trimming and EBU R128 loudness normalization.

## Activation
- Slash command: `/audio-generation`, `/sound`
- Mention: `@audio-generation`, `@sound`

## Supported Backends
1. **ElevenLabs Sound Effects (Cloud — Best for Weapons, Mechanical Foley, Impacts)**:
   - 44.1 kHz PCM, crisp ballistic transients, zero VRAM overhead.
   - Auto-selected when `ELEVENLABS_API_KEY` is set in `.env`.
2. **AudioLDM2 (Local GPU — Best for Offline Ambience & Drones)**:
   - 16 kHz PCM, runs on-demand with automatic VRAM flush.
   - Used when no key is set or with `--backend local`.

---

## Godot 3D Audio Anti-Slop Rules
1. **Dry Anechoic Source Rule**: NEVER prompt `"big hall reverb"`, `"echoing canyon"`, or `"cinematic room tail"` on in-world 3D SFX. Baked reverb breaks `AudioStreamPlayer3D` attenuation and Godot `AudioBus` room reverb! Always keep point-source SFX **dry, close-mic**.
2. **Mono for 3D Point Sources**: Pass `--mono` for gunshots, footsteps, valves, doors, and impacts played via `AudioStreamPlayer3D` / `AudioPool.play_sfx_3d()`. Keep stereo for UI and ambient beds.
3. **Zero Trigger Latency**: `generate_sfx.py` runs FFmpeg `silenceremove` by default so ElevenLabs MP3 encoder padding does not delay weapon fire or button clicks.
4. **Loudness Consistency**: Normalized to `-14 LUFS / -3 dBTP` by default (`--no-normalize` only for ultra-quiet UI whispers).
5. **Anti-Machine-Gun Variations**: Generate 3 variations (`_01.wav`, `_02.wav`, `_03.wav`) for repeated gameplay sounds (shots, footsteps, impacts).
6. **Seamless Loops**: Pass `--loop-crossfade 0.35` (or `0.5–0.8` for ambience) on looping motors/hums/rain so Godot `AudioStreamWAV` loop boundaries never click.

---

## Acoustic Prompt Anatomy & Templates

Formula:
`[Physical Source & Material] + [Mechanical Excitation] + [Transient -> Body -> Tail] + [Close-Mic Dry Anechoic]`

### Template A: Ballistic / Weapon Shot (`--mono --duration 1.2`)
```text
Close-mic dry anechoic recording of [WEAPON: e.g. 12-gauge pump-action shotgun blast], sharp explosive crack transient, heavy low-mid chest thump and crisp metallic bolt slap, very short tight dry decay, zero room reverb, zero echo, single isolated shot.
```

### Template B: Mechanical / Door / Valve (`--mono --duration 1.5`)
```text
Close-mic dry studio foley of [MECHANISM: e.g. heavy rusted cast-iron industrial gate valve turning], gritty metal-on-metal friction grind, sharp mechanical latch clack, short deadened stop with zero room echo, clean isolated foley.
```

### Template C: Continuous Loop (`--mono --duration 5.0 --loop-crossfade 0.4`)
```text
Steady continuous uniform loop of [SOURCE: e.g. old Soviet electric diesel generator idling], consistent cyclic mechanical rumble and subtle belt whir at constant RPM, flat steady volume with no starts, stops, or sudden transients, dry close-mic recording.
```

### Template D: Atmospheric Soundscape (`--backend local --duration 10.0 --loop-crossfade 0.8`)
```text
Dark post-Soviet industrial interior ambience, distant low ventilation rumble, subtle cold air draft through concrete corridor, sparse metallic pipe creak, steady uniform texture, no speech, no music.
```

Default AudioLDM2 `--negative-prompt`:
`music, speech, singing, heavy reverb, cathedral echo, muffled, clipping, distorted, hiss`

---

## Execution Command

```bash
# Dry 3D SFX (mono, silence-trimmed, normalized)
/home/dkd/ai_audio_env/bin/python tools/generate_sfx.py \
  --prompt "<acoustic template>" \
  --output "res://assets/audio/sfx/<name>_01.wav" \
  --duration 1.2 \
  --mono

# Seamless Mechanical Loop
/home/dkd/ai_audio_env/bin/python tools/generate_sfx.py \
  --prompt "<loop template>" \
  --output "res://assets/audio/sfx/<name>_loop.wav" \
  --duration 5.0 \
  --mono \
  --loop-crossfade 0.4
```

### Key Options
- `--backend auto|elevenlabs|local`: Backend selector.
- `--prompt-influence <0.0-1.0>`: ElevenLabs strictness (default `0.45`).
- `--mono`: Downmix to 1 channel for `AudioStreamPlayer3D`.
- `--loop-crossfade <sec>`: Wrap-crossfades tail into head for click-free Godot loop import.
- `--no-trim-silence` / `--no-normalize`: Disable default FFmpeg cleanup passes.
- `--steps 25` / `--seed <int>`: Local AudioLDM2 controls.
