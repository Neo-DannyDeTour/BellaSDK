#!/usr/bin/env python3
"""Unified audio effect and soundscape generator.

Supports both:
1. ElevenLabs Sound Effects API (44.1 kHz studio-grade weapon transients and foley).
2. Local AudioLDM2 (offline on-demand ambient soundscapes and textured SFX).
"""

from __future__ import annotations

import argparse
import gc
import os
import subprocess
import sys
from pathlib import Path


def resolve_output_path(raw_path: str) -> Path:
    """Resolve raw path or Godot res:// URI to an absolute filesystem Path."""
    if raw_path.startswith("res://"):
        project_root = Path(__file__).resolve().parent.parent
        sub_path = raw_path[len("res://") :].lstrip("/\\")
        return project_root / sub_path
    return Path(raw_path).resolve()


def generate_with_elevenlabs(
    prompt: str,
    output_path: Path,
    duration: float,
    api_key: str,
) -> int:
    """Generate audio via ElevenLabs Sound Effects API and export 16-bit PCM WAV."""
    import requests

    print(f"[ElevenLabs] Generating SFX for prompt: '{prompt}' ({duration:.1f}s)...")
    url = "https://api.elevenlabs.io/v1/sound-generation"
    headers = {
        "xi-api-key": api_key,
        "Content-Type": "application/json",
    }
    payload = {
        "text": prompt,
        "duration_seconds": duration,
        "prompt_influence": 0.35,
    }

    response = requests.post(url, headers=headers, json=payload, timeout=60)
    if response.status_code != 200:
        print(f"[ElevenLabs] API Error ({response.status_code}): {response.text}")
        return 1

    temp_mp3 = output_path.with_suffix(".temp.mp3")
    with open(temp_mp3, "wb") as f:
        f.write(response.content)

    print(f"[ElevenLabs] Converting to 16-bit PCM WAV: {output_path}...")
    conv_result = subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-i",
            str(temp_mp3),
            "-acodec",
            "pcm_s16le",
            "-ar",
            "44100",
            str(output_path),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if temp_mp3.exists():
        temp_mp3.unlink()

    if conv_result.returncode != 0:
        print(f"[ElevenLabs] FFmpeg conversion failed: {conv_result.stderr.decode('utf-8')}")
        return 1

    file_size_kb = output_path.stat().st_size / 1024.0
    print(f"SAVED: {output_path}")
    print(f"SPEC: 44100 Hz, stereo PCM_16, {duration:.1f}s, {file_size_kb:.1f} KB")
    return 0


def generate_with_audioldm(
    prompt: str,
    output_path: Path,
    duration: float,
    steps: int,
    guidance_scale: float,
    negative_prompt: str,
    seed: int | None,
    force_cpu: bool,
) -> int:
    """Generate audio via local AudioLDM2 with immediate VRAM cleanup."""
    import numpy as np
    import scipy.io.wavfile
    import torch
    from diffusers import AudioLDM2Pipeline

    device = "cpu"
    dtype = torch.float32

    if not force_cpu and torch.cuda.is_available():
        device = "cuda"
        dtype = torch.float16
        print(f"[AudioLDM2] Using GPU: {torch.cuda.get_device_name(0)} (float16)")
    else:
        print("[AudioLDM2] Using CPU (float32)")

    generator = None
    if seed is not None:
        generator = torch.Generator(device=device).manual_seed(seed)

    pipe = AudioLDM2Pipeline.from_pretrained("cvssp/audioldm2", torch_dtype=dtype)
    pipe = pipe.to(device)

    if device == "cuda":
        pipe.enable_attention_slicing()

    print(f"[AudioLDM2] Generating waveform for prompt: '{prompt}'...")
    output = pipe(
        prompt=prompt,
        negative_prompt=negative_prompt,
        num_inference_steps=steps,
        audio_length_in_s=duration,
        guidance_scale=guidance_scale,
        generator=generator,
    )

    audio_data = output.audios[0]
    max_val = float(np.max(np.abs(audio_data)))
    normalized = audio_data / max_val if max_val > 0.0 else audio_data
    pcm16_data = (normalized * 32767.0).astype(np.int16)

    sample_rate: int = int(getattr(pipe.vocoder.config, "sampling_rate", 16000))
    scipy.io.wavfile.write(str(output_path), rate=sample_rate, data=pcm16_data)

    file_size_kb = output_path.stat().st_size / 1024.0
    print(f"SAVED: {output_path}")
    print(f"SPEC: {sample_rate} Hz, {duration:.1f}s, {file_size_kb:.1f} KB")

    del pipe
    del output
    del audio_data
    gc.collect()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()

    print("VRAM cache flushed successfully.")
    return 0


def main() -> int:
    """Main CLI entrypoint routing to ElevenLabs or local AudioLDM2."""
    from dotenv import load_dotenv

    # Load workspace .env if present
    env_path = Path(__file__).resolve().parent.parent / ".env"
    if env_path.exists():
        load_dotenv(dotenv_path=env_path)

    parser = argparse.ArgumentParser(
        description="Generate SFX and soundscapes via ElevenLabs or local AudioLDM2"
    )
    parser.add_argument(
        "--prompt",
        "-p",
        required=True,
        type=str,
        help="Text prompt describing sound effect or soundscape",
    )
    parser.add_argument(
        "--output",
        "-o",
        required=True,
        type=str,
        help="Destination path (e.g. res://assets/audio/sfx/shotgun.wav)",
    )
    parser.add_argument(
        "--duration",
        "-d",
        type=float,
        default=2.0,
        help="Audio duration in seconds (default: 2.0)",
    )
    parser.add_argument(
        "--backend",
        "-b",
        choices=["auto", "elevenlabs", "local"],
        default="auto",
        help="Backend selector (auto detects ElevenLabs key or falls back to local)",
    )
    parser.add_argument(
        "--api-key",
        type=str,
        default=None,
        help="Explicit ElevenLabs API key (overrides ELEVENLABS_API_KEY environment var)",
    )
    parser.add_argument(
        "--steps",
        "-s",
        type=int,
        default=25,
        help="Diffusion inference steps for local AudioLDM2 (default: 25)",
    )
    parser.add_argument(
        "--guidance-scale",
        "-g",
        type=float,
        default=3.5,
        help="Classifier-free guidance scale for local AudioLDM2 (default: 3.5)",
    )
    parser.add_argument(
        "--negative-prompt",
        "-n",
        type=str,
        default="low quality, muffled, distorted, hiss, high noise floor",
        help="Negative prompt for local AudioLDM2",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        help="Optional random seed for local AudioLDM2",
    )
    parser.add_argument(
        "--cpu",
        action="store_true",
        help="Force CPU execution for local AudioLDM2",
    )

    args = parser.parse_args()

    duration: float = max(0.5, min(30.0, float(args.duration)))
    output_path = resolve_output_path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    eleven_key = args.api_key or os.environ.get("ELEVENLABS_API_KEY", "").strip()

    # Route backend
    use_elevenlabs = False
    if args.backend == "elevenlabs":
        use_elevenlabs = True
    elif args.backend == "auto" and eleven_key:
        use_elevenlabs = True

    if use_elevenlabs:
        if not eleven_key:
            print("Error: ElevenLabs selected but no ELEVENLABS_API_KEY provided.")
            return 1
        return generate_with_elevenlabs(
            prompt=args.prompt,
            output_path=output_path,
            duration=duration,
            api_key=eleven_key,
        )

    return generate_with_audioldm(
        prompt=args.prompt,
        output_path=output_path,
        duration=duration,
        steps=int(args.steps),
        guidance_scale=float(args.guidance_scale),
        negative_prompt=args.negative_prompt,
        seed=args.seed,
        force_cpu=args.cpu,
    )


if __name__ == "__main__":
    sys.exit(main())
