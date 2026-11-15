#!/usr/bin/env python3
"""Unified audio effect and soundscape generator (/audio-generation, /sound).

Supports both:
1. ElevenLabs Sound Effects API (44.1 kHz studio-grade weapon transients and foley).
2. Local AudioLDM2 (offline on-demand ambient soundscapes and textured SFX).

Includes FFmpeg post-processing for zero-latency silence trimming, EBU R128
loudness normalization (-14 LUFS / -3 dBTP), and seamless loop crossfading.
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


def _probe_duration(wav_path: Path) -> float:
    res = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(wav_path),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if res.returncode != 0:
        return 0.0
    try:
        return float(res.stdout.decode("utf-8").strip())
    except ValueError:
        return 0.0


def postprocess_audio(
    input_path: Path,
    output_path: Path,
    sample_rate: int = 44100,
    mono: bool = False,
    trim_silence: bool = True,
    normalize: bool = True,
    loop_crossfade: float = 0.0,
) -> int:
    """Convert to 16-bit PCM WAV, trim leading silence, normalize, and optionally loop-crossfade."""
    temp_clean = output_path.with_suffix(".clean.wav")
    filters: list[str] = []

    if trim_silence:
        filters.append("silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.004")

    if normalize:
        filters.append("loudnorm=I=-14:TP=-3.0:LRA=7")

    cmd = ["ffmpeg", "-y", "-i", str(input_path)]
    if filters:
        cmd.extend(["-af", ",".join(filters)])
    if mono:
        cmd.extend(["-ac", "1"])
    cmd.extend(["-acodec", "pcm_s16le", "-ar", str(sample_rate), str(temp_clean)])

    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if res.returncode != 0:
        print(f"[FFmpeg] Post-process failed: {res.stderr.decode('utf-8')}", file=sys.stderr)
        return 1

    if loop_crossfade > 0.0:
        dur = _probe_duration(temp_clean)
        fade = min(loop_crossfade, max(0.05, dur * 0.25))
        if dur > fade * 2.2:
            # Overlap tail [dur-fade, dur] with head [0, fade] starting from t=fade so end matches t=fade
            fc = (
                f"[0:a]asplit=2[a][b];"
                f"[a]atrim=start={fade:.4f},asetpts=PTS-STARTPTS[body];"
                f"[b]atrim=start=0:end={fade:.4f},asetpts=PTS-STARTPTS[head];"
                f"[body][head]acrossfade=d={fade:.4f}:c1=tri:c2=tri[out]"
            )
            loop_cmd = [
                "ffmpeg",
                "-y",
                "-i",
                str(temp_clean),
                "-filter_complex",
                fc,
                "-map",
                "[out]",
                "-acodec",
                "pcm_s16le",
                "-ar",
                str(sample_rate),
                str(output_path),
            ]
            loop_res = subprocess.run(loop_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
            if temp_clean.exists():
                temp_clean.unlink()
            if loop_res.returncode != 0:
                print(
                    f"[FFmpeg] Loop crossfade failed: {loop_res.stderr.decode('utf-8')}",
                    file=sys.stderr,
                )
                return 1
            return 0

    temp_clean.replace(output_path)
    return 0


def generate_with_elevenlabs(
    prompt: str,
    output_path: Path,
    duration: float,
    api_key: str,
    prompt_influence: float,
    mono: bool,
    trim_silence: bool,
    normalize: bool,
    loop_crossfade: float,
) -> int:
    """Generate audio via ElevenLabs Sound Effects API and export normalized 16-bit PCM WAV."""
    import requests

    print(f"[ElevenLabs] Generating SFX: '{prompt}' ({duration:.1f}s, influence={prompt_influence})...")
    url = "https://api.elevenlabs.io/v1/sound-generation"
    headers = {
        "xi-api-key": api_key,
        "Content-Type": "application/json",
    }
    payload = {
        "text": prompt,
        "duration_seconds": duration,
        "prompt_influence": prompt_influence,
    }

    response = requests.post(url, headers=headers, json=payload, timeout=60)
    if response.status_code != 200:
        print(f"[ElevenLabs] API Error ({response.status_code}): {response.text}", file=sys.stderr)
        return 1

    temp_mp3 = output_path.with_suffix(".temp.mp3")
    temp_mp3.write_bytes(response.content)

    rc = postprocess_audio(
        input_path=temp_mp3,
        output_path=output_path,
        sample_rate=44100,
        mono=mono,
        trim_silence=trim_silence,
        normalize=normalize,
        loop_crossfade=loop_crossfade,
    )
    if temp_mp3.exists():
        temp_mp3.unlink()
    if rc != 0:
        return rc

    final_dur = _probe_duration(output_path) or duration
    file_size_kb = output_path.stat().st_size / 1024.0
    print(f"SAVED: {output_path}")
    print(f"SPEC: 44100 Hz, {'mono' if mono else 'stereo'} PCM_16, {final_dur:.2f}s, {file_size_kb:.1f} KB")
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
    mono: bool,
    trim_silence: bool,
    normalize: bool,
    loop_crossfade: float,
) -> int:
    """Generate audio via local AudioLDM2 with VRAM cleanup and FFmpeg post-processing."""
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

    generator = torch.Generator(device=device).manual_seed(seed) if seed is not None else None

    pipe = AudioLDM2Pipeline.from_pretrained("cvssp/audioldm2", torch_dtype=dtype)
    pipe = pipe.to(device)
    if device == "cuda":
        pipe.enable_attention_slicing()

    print(f"[AudioLDM2] Generating waveform: '{prompt}'...")
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
    raw_wav = output_path.with_suffix(".raw.wav")
    scipy.io.wavfile.write(str(raw_wav), rate=sample_rate, data=pcm16_data)

    del pipe, output, audio_data
    gc.collect()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()

    rc = postprocess_audio(
        input_path=raw_wav,
        output_path=output_path,
        sample_rate=sample_rate,
        mono=mono,
        trim_silence=trim_silence,
        normalize=normalize,
        loop_crossfade=loop_crossfade,
    )
    if raw_wav.exists():
        raw_wav.unlink()
    if rc != 0:
        return rc

    final_dur = _probe_duration(output_path) or duration
    file_size_kb = output_path.stat().st_size / 1024.0
    print(f"SAVED: {output_path}")
    print(f"SPEC: {sample_rate} Hz, PCM_16, {final_dur:.2f}s, {file_size_kb:.1f} KB")
    return 0


def main() -> int:
    """Main CLI entrypoint routing to ElevenLabs or local AudioLDM2."""
    from dotenv import load_dotenv

    env_path = Path(__file__).resolve().parent.parent / ".env"
    if env_path.exists():
        load_dotenv(dotenv_path=env_path)

    parser = argparse.ArgumentParser(
        description="Generate SFX and soundscapes via ElevenLabs or local AudioLDM2"
    )
    parser.add_argument("--prompt", "-p", required=True, type=str, help="Acoustic description prompt")
    parser.add_argument("--output", "-o", required=True, type=str, help="Destination .wav path (supports res://)")
    parser.add_argument("--duration", "-d", type=float, default=2.0, help="Duration seconds (0.5-30.0)")
    parser.add_argument(
        "--backend",
        "-b",
        choices=["auto", "elevenlabs", "local"],
        default="auto",
        help="Backend selector",
    )
    parser.add_argument("--api-key", type=str, default=None, help="Override ELEVENLABS_API_KEY")
    parser.add_argument("--prompt-influence", type=float, default=0.45, help="ElevenLabs prompt strictness (0-1)")
    parser.add_argument("--steps", "-s", type=int, default=25, help="Local AudioLDM2 diffusion steps")
    parser.add_argument("--guidance-scale", "-g", type=float, default=3.5, help="Local AudioLDM2 guidance")
    parser.add_argument(
        "--negative-prompt",
        "-n",
        type=str,
        default="music, speech, singing, heavy reverb, cathedral echo, muffled, clipping, distorted, hiss",
        help="Negative prompt for local AudioLDM2",
    )
    parser.add_argument("--seed", type=int, default=None, help="Random seed for local AudioLDM2")
    parser.add_argument("--cpu", action="store_true", help="Force CPU execution for local AudioLDM2")
    parser.add_argument("--mono", action="store_true", help="Downmix to mono (recommended for Godot 3D SFX)")
    parser.add_argument("--no-trim-silence", action="store_true", help="Keep leading silence")
    parser.add_argument("--no-normalize", action="store_true", help="Skip -14 LUFS loudness normalization")
    parser.add_argument(
        "--loop-crossfade",
        type=float,
        default=0.0,
        help="Crossfade overlap seconds to make seamless loop (e.g. 0.35)",
    )

    args = parser.parse_args()
    duration = max(0.5, min(30.0, float(args.duration)))
    output_path = resolve_output_path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    eleven_key = args.api_key or os.environ.get("ELEVENLABS_API_KEY", "").strip()
    use_elevenlabs = args.backend == "elevenlabs" or (args.backend == "auto" and bool(eleven_key))

    if use_elevenlabs:
        if not eleven_key:
            print("Error: ElevenLabs selected but no ELEVENLABS_API_KEY provided.", file=sys.stderr)
            return 1
        return generate_with_elevenlabs(
            prompt=args.prompt,
            output_path=output_path,
            duration=duration,
            api_key=eleven_key,
            prompt_influence=float(args.prompt_influence),
            mono=args.mono,
            trim_silence=not args.no_trim_silence,
            normalize=not args.no_normalize,
            loop_crossfade=float(args.loop_crossfade),
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
        mono=args.mono,
        trim_silence=not args.no_trim_silence,
        normalize=not args.no_normalize,
        loop_crossfade=float(args.loop_crossfade),
    )


if __name__ == "__main__":
    sys.exit(main())
