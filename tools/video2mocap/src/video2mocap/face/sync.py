"""Synchronise two takes (body video A, face video B) from their audio: a clap at the start of each
take, or the same line spoken in both. Result: offset in seconds such that  t_B = t_A + offset."""
from __future__ import annotations

from pathlib import Path

import numpy as np

ENV_HZ = 200  # envelope sample rate (5 ms resolution)


def audio_envelope(video: str | Path) -> np.ndarray:
    """Mono RMS envelope at ENV_HZ."""
    import av

    with av.open(str(video)) as c:
        if not c.streams.audio:
            raise RuntimeError(f"{video} has no audio track (record with sound to sync)")
        s = c.streams.audio[0]
        sr = s.rate
        chunks = []
        for fr in c.decode(s):
            a = fr.to_ndarray().astype(np.float32)
            chunks.append(a.mean(axis=0) if a.ndim == 2 else a)
    x = np.concatenate(chunks)
    if np.abs(x).max() > 1.5:  # integer PCM
        x = x / 32768.0
    hop = sr // ENV_HZ
    n = len(x) // hop
    return np.sqrt((x[: n * hop].reshape(n, hop) ** 2).mean(axis=1) + 1e-12)


def detect_clap(env: np.ndarray, search_s: float = 10.0, k: float = 8.0) -> float:
    """Time (s) of the first sharp transient: a clap is a jump far above the background level."""
    e = env[: int(search_s * ENV_HZ)]
    onset = np.maximum(np.diff(np.log(e + 1e-6)), 0)
    thr = np.median(onset) + k * (np.median(np.abs(onset - np.median(onset))) + 1e-6)
    peaks = np.where((onset > thr) & (e[1:] > 4 * np.median(e)))[0]
    if peaks.size == 0:
        raise RuntimeError("no clap found in the first seconds")
    return float((peaks[0] + 1) / ENV_HZ)


def offset_by_audio(env_a: np.ndarray, env_b: np.ndarray, max_lag_s: float = 30.0) -> tuple[float, float]:
    """Cross-correlate log envelopes. Returns (offset_s with t_B = t_A + offset, confidence 0..1)."""
    a = np.log(env_a + 1e-6)
    b = np.log(env_b + 1e-6)
    a = (a - a.mean()) / (a.std() + 1e-9)
    b = (b - b.mean()) / (b.std() + 1e-9)
    n = len(a) + len(b) - 1
    nfft = 1 << (n - 1).bit_length()
    xc = np.fft.irfft(np.fft.rfft(b, nfft) * np.conj(np.fft.rfft(a, nfft)), nfft)
    lags = np.concatenate([np.arange(0, len(b)), np.arange(-len(a) + 1, 0)])
    xc = np.concatenate([xc[: len(b)], xc[nfft - len(a) + 1 :]])
    keep = np.abs(lags) <= max_lag_s * ENV_HZ
    best = np.argmax(np.where(keep, xc, -np.inf))
    conf = float(xc[best] / min(len(a), len(b)))
    return float(lags[best] / ENV_HZ), max(0.0, min(1.0, conf))


def sync_offset(video_a: str | Path, video_b: str | Path, method: str = "auto") -> dict:
    ea, eb = audio_envelope(video_a), audio_envelope(video_b)
    out = {}
    if method in ("auto", "clap"):
        try:
            ca, cb = detect_clap(ea), detect_clap(eb)
            out = {"method": "clap", "offset_s": cb - ca, "clap_a_s": ca, "clap_b_s": cb}
        except RuntimeError as e:
            if method == "clap":
                raise
            out["clap_error"] = str(e)
    if method == "audio" or (method == "auto" and "offset_s" not in out):
        off, conf = offset_by_audio(ea, eb)
        out.update({"method": "audio", "offset_s": off, "confidence": conf})
    return out
