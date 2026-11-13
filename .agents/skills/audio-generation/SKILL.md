---
name: audio-generation
description: Generates custom sound effects (SFX), weapon blasts, and soundscapes using ElevenLabs SFX API or local AudioLDM2 with automatic VRAM cleanup.
metadata:
  icon: volume-2
---

# Audio Generation Skill (`/audio-generation`, `/sound`)

Generates game-ready audio effects (weapon blasts, gunshots, impacts, mechanical clicks, debris, ambient soundscapes) directly into the project repository.

## Activation
- Slash command: `/audio-generation`, `/sound`
- Mention: `@audio-generation`, `@sound`

## Supported Backends

1. **ElevenLabs Sound Effects (Cloud, Recommended for Weapons)**:
   - 44.1 kHz stereo, instant ballistic transients, zero VRAM overhead.
   - Automatically activates when `ELEVENLABS_API_KEY` is set in `.env`.
2. **AudioLDM2 (Local GPU, Offline, Recommended for Ambience)**:
   - 16 kHz mono, on-demand execution, zero persistent VRAM lock.
   - Used when no API key is set or when `--backend local` is specified.

---

## Execution Command

```bash
/home/dkd/ai_audio_env/bin/python tools/generate_sfx.py \
  --prompt "<detailed acoustic description>" \
  --output "res://assets/audio/sfx/<name>.wav" \
  --duration <seconds>
```

### Options:
- `--backend auto`: Uses ElevenLabs if API key exists, otherwise local AudioLDM2.
- `--backend elevenlabs`: Forces ElevenLabs API.
- `--backend local`: Forces offline local AudioLDM2.
- `--duration <seconds>`: Length in seconds (default: 2.0).
- `--steps 25`: Diffusion steps (local backend only).
