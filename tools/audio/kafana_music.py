"""Kafana music for Do Zore, composed and played by this script (original tunes, no recordings).

Every song in data/songs.json gets its own tune in the style of its genre, and every venue a softer
tune the band plays between requests:

- starogradske: a slow waltz in harmonic minor, the accordion singing the tune over guitar
  oom-pa-pa and a double bass;
- izvorna: a fast kolo in 2/4, accordion runs over its own left-hand bass and chords and a tapan;
- tamburica: tamburica tremolo over bugarija chords on the off-beats, berda on the beat and a violin
  joining in the second half;
- narodnjaci: 7/8 (2+2+3) in the hijaz mode, accordion and violin trading phrases over darbuka.

The instruments are synthesised (additive reeds, plucked strings by Karplus-Strong, bowed strings,
drums from tuned noise) and mixed in a small room. Each tune is a seamless loop.

    python tools/audio/kafana_music.py [out_dir]     (default client/assets/audio)

Needs numpy, scipy and ffmpeg with libvorbis.
"""
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, fftconvolve, lfilter, sosfilt

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def envelope(n, attack, release, sustain_curve=None):
    env = np.ones(n)
    a = min(n, max(1, int(attack * SR)))
    r = min(n - a, max(1, int(release * SR))) if n > a else 0
    env[:a] = np.linspace(0.0, 1.0, a) ** 1.5
    if r > 0:
        env[n - r:] *= np.linspace(1.0, 0.0, r) ** 1.5
    if sustain_curve is not None:
        env *= sustain_curve
    return env


# ---------------------------------------------------------------------------------------------
# Instruments: each returns a mono buffer for one note.
# ---------------------------------------------------------------------------------------------

def reed(freq, dur, vel, bright=1.0):
    """Accordion: two reeds a few cents apart (the musette beat), odd harmonics strong like a reed,
    a soft attack and the bellows' slight swell and tremolo."""
    n = int((dur + 0.08) * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for detune in (-0.0024, 0.0024):
        f = freq * (1.0 + detune)
        k = 1
        while k * f < 9000.0 and k <= 18:
            amp = (1.0 if k % 2 else 0.55) / k ** (1.05 - 0.25 * bright)
            out += amp * np.sin(2 * np.pi * f * k * t + k * 0.7)
            k += 1
    swell = 0.9 + 0.1 * np.sin(np.pi * np.clip(t / max(dur, 0.05), 0, 1))
    trem = 1.0 + 0.05 * np.sin(2 * np.pi * 5.3 * t)
    env = envelope(n, 0.018, 0.07, swell * trem)
    return out * env * vel * 0.12


def pluck(freq, dur, vel, bright=0.6, decay=0.996, body=0.0):
    """A plucked string (Karplus-Strong): guitar, tamburica, berda."""
    n = int((dur + 0.6) * SR)
    period = max(2, int(round(SR / freq)))
    rng = np.random.default_rng(int(freq * 1000) % 99991)
    burst = rng.uniform(-1, 1, period)
    # Brightness: soften the pick.
    b, a = butter(1, min(0.99, 0.15 + 0.8 * bright), btype="low")
    burst = lfilter(b, a, burst)
    x = np.zeros(n)
    x[:period] = burst
    a_coef = np.zeros(period + 2)
    a_coef[0] = 1.0
    a_coef[period] = -decay * 0.5
    a_coef[period + 1] = -decay * 0.5
    y = lfilter([1.0], a_coef, x)
    if body:
        sos = butter(2, [180.0, 2600.0], btype="band", fs=SR, output="sos")
        y = y * (1 - body) + sosfilt(sos, y) * body * 2.0
    stop = int(dur * SR)
    damp = np.ones(n)
    if stop < n:
        tail = min(n - stop, int(0.08 * SR))
        damp[stop:stop + tail] = np.linspace(1, 0, tail)
        damp[stop + tail:] = 0
    return y * damp * vel * 0.5


def bowed(freq, dur, vel):
    """Violin: a bowed saw with vibrato that comes in after the attack, through a wooden body."""
    n = int((dur + 0.12) * SR)
    t = np.arange(n) / SR
    vib_depth = 0.0045 * np.clip((t - 0.15) / 0.25, 0, 1)
    f_inst = freq * (1.0 + vib_depth * np.sin(2 * np.pi * 5.6 * t))
    phase = 2 * np.pi * np.cumsum(f_inst) / SR
    out = np.zeros(n)
    k = 1
    while k * freq < 10000.0 and k <= 24:
        out += np.sin(k * phase) / k
        k += 1
    sos = butter(2, [250.0, 4200.0], btype="band", fs=SR, output="sos")
    out = sosfilt(sos, out)
    env = envelope(n, 0.07, 0.1)
    return out * env * vel * 0.35


def tapan_boom(vel):
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    f = 48 + 40 * np.exp(-t * 18)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7)
    rng = np.random.default_rng(3)
    click = rng.uniform(-1, 1, n) * np.exp(-t * 90) * 0.4
    return (body + click) * vel * 0.9


def tapan_stick(vel):
    n = int(0.08 * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(5)
    sos = butter(2, [1800.0, 6000.0], btype="band", fs=SR, output="sos")
    return sosfilt(sos, rng.uniform(-1, 1, n)) * np.exp(-t * 60) * vel * 0.9


def darbuka(kind, vel):
    if kind == "doum":
        n = int(0.35 * SR)
        t = np.arange(n) / SR
        f = 95 + 30 * np.exp(-t * 30)
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 11) * vel * 0.8
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(7 if kind == "tek" else 11)
    sos = butter(2, [2200.0, 7000.0] if kind == "tek" else [900.0, 3000.0], btype="band", fs=SR, output="sos")
    ring = np.sin(2 * np.pi * (520 if kind == "tek" else 330) * t) * 0.3
    return (sosfilt(sos, rng.uniform(-1, 1, n)) + ring) * np.exp(-t * 55) * vel * 0.75


def bell(freqs, decay, vel):
    n = int(decay * 3 * SR)
    t = np.arange(n) / SR
    out = sum(np.sin(2 * np.pi * f * t) * np.exp(-t / (decay * (1.0 - 0.1 * i))) / (1 + i * 0.6) for i, f in enumerate(freqs))
    return out * envelope(n, 0.002, 0.02) * vel * 0.3


# ---------------------------------------------------------------------------------------------
# Mixing
# ---------------------------------------------------------------------------------------------

class Mix:
    def __init__(self, seconds):
        self.n = int(seconds * SR) + SR * 3
        self.buf = np.zeros((self.n, 2))

    def add(self, mono, at_seconds, pan=0.0, gain=1.0):
        start = int(at_seconds * SR)
        if start >= self.n:
            return
        mono = mono[: self.n - start]
        left = np.cos((pan + 1) * np.pi / 4)
        right = np.sin((pan + 1) * np.pi / 4)
        self.buf[start:start + len(mono), 0] += mono * left * gain
        self.buf[start:start + len(mono), 1] += mono * right * gain


def room(stereo, amount=0.16, seconds=1.1):
    """A small wooden room: a decaying, slightly darkened noise tail, different in each ear."""
    rng = np.random.default_rng(42)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.copy(stereo)
    sos = butter(1, 3500.0, btype="low", fs=SR, output="sos")
    for ch in range(2):
        ir = rng.normal(0, 1, n) * np.exp(-t * 5.5)
        ir = sosfilt(sos, ir)
        ir[: int(0.012 * SR)] = 0
        ir /= np.sqrt(np.sum(ir ** 2))
        out[:, ch] += fftconvolve(stereo[:, ch], ir)[: len(stereo)] * amount
    return out


def master(stereo):
    stereo = stereo - np.mean(stereo, axis=0)
    rms = np.sqrt(np.mean(stereo ** 2)) + 1e-9
    stereo *= 0.13 / rms
    # Soft limiting.
    return np.tanh(stereo * 1.15) / np.tanh(1.15) * 0.92


def write_ogg(stereo, path, quality=3):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wavfile.write(tmp.name, SR, (np.clip(stereo, -1, 1) * 32767).astype(np.int16))
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp.name, "-c:a", "libvorbis", "-q:a", str(quality), path], check=True)
    os.unlink(tmp.name)


def loop(render, seconds):
    """Renders two passes and keeps the second, so the room's tail from the end carries over the
    start and the loop has no seam."""
    mix = Mix(seconds * 2)
    render(mix, 0.0)
    render(mix, seconds)
    wet = room(mix.buf)
    start = int(seconds * SR)
    return master(wet[start:start + int(seconds * SR)])


# ---------------------------------------------------------------------------------------------
# Composition
# ---------------------------------------------------------------------------------------------

SCALES = {
    "harmonic_minor": [0, 2, 3, 5, 7, 8, 11],
    "major": [0, 2, 4, 5, 7, 9, 11],
    "mixolydian": [0, 2, 4, 5, 7, 9, 10],
    "hijaz": [0, 1, 4, 5, 7, 8, 10],
}

# Chords as scale degrees (0-based) of their root; quality from the scale.
STYLES = {
    "starogradske": {"scale": "harmonic_minor", "beats": 3, "bpm": (92, 108),
                     "a": [0, 3, 4, 0, 5, 3, 4, 0], "b": [5, 3, 0, 4, 0, 3, 4, 0],
                     "rhythms": [[2, 1], [1.5, 0.5, 1], [1, 1, 1], [3], [1, 0.5, 0.5, 1], [2, 0.5, 0.5]]},
    "izvorna": {"scale": "mixolydian", "beats": 2, "bpm": (138, 156),
                "a": [0, 4, 0, 4, 0, 3, 4, 0], "b": [3, 0, 4, 0, 3, 0, 4, 0],
                "rhythms": [[0.5, 0.5, 0.5, 0.5], [0.25, 0.25, 0.5, 0.5, 0.5], [0.5, 0.25, 0.25, 1], [1, 0.5, 0.5]]},
    "tamburica": {"scale": "major", "beats": 2, "bpm": (112, 124),
                  "a": [0, 0, 4, 4, 4, 4, 0, 0], "b": [3, 3, 0, 0, 4, 4, 0, 0],
                  "rhythms": [[1, 1], [2], [0.5, 0.5, 1], [1, 0.5, 0.5], [1.5, 0.5]]},
    "narodnjaci": {"scale": "hijaz", "beats": 3.5, "bpm": (128, 140),
                   "a": [0, 0, 6, 0, 3, 6, 0, 0], "b": [3, 3, 6, 6, 2, 6, 0, 0],
                   "rhythms": [[1, 1, 1.5], [0.5, 0.5, 1, 1.5], [2, 1.5], [1, 0.5, 0.5, 1.5], [1, 1, 0.5, 0.5, 0.5]]},
}


def chord_tones(scale, degree, tonic):
    steps = SCALES[scale]
    return [tonic + steps[(degree + i) % 7] + 12 * ((degree + i) // 7) for i in (0, 2, 4)]


def scale_note(scale, tonic, index):
    steps = SCALES[scale]
    return tonic + steps[index % 7] + 12 * (index // 7)


def nearest_index(scale, tonic, midi):
    best, best_d = 0, 1e9
    for i in range(-14, 28):
        d = abs(scale_note(scale, tonic, i) - midi)
        if d < best_d:
            best, best_d = i, d
    return best


def compose(style, rng, tonic):
    """A tune as (bar, beat, beats, midi) notes: an 8-bar A strain played twice, an 8-bar B strain
    higher up, and the A strain again. Each 4-bar phrase follows an arch (rising to a peak in its
    third bar and falling to a close: on the fifth at the half-way cadence, on the tonic at the
    end), a two-bar motif rides on the arch, strong beats land on the chord's tones and the rest
    pass between them by step."""
    s = STYLES[style]
    scale = s["scale"]
    bars = s["a"] + s["a"] + s["b"] + s["a"]
    motif_rhythm = [int(rng.choice(len(s["rhythms"]))) for _ in range(2)]
    motif = [int(x) for x in rng.choice([0, 1, 2, -1, 1, 0, -2, 1], size=8)]
    base = nearest_index(scale, tonic, tonic + 12)
    notes = []
    for bar, degree in enumerate(bars):
        section_b = 16 <= bar < 24
        phrase_bar = bar % 4
        closing = bar % 8 == 7
        half = bar % 8 == 3
        if bar % 8 in (2, 5) and rng.random() < 0.5:
            rhythm = s["rhythms"][int(rng.choice(len(s["rhythms"])))]
        else:
            rhythm = s["rhythms"][motif_rhythm[bar % 2]]
        if closing or half:
            rhythm = [s["beats"] - 1.0, 1.0] if s["beats"] >= 3 else [s["beats"]]
        lift = 3 if section_b else 0
        start = base + 2 + lift
        peak = start + int(rng.integers(3, 6))
        end = base + (7 if closing and bar >= 24 else 0) * 0 + (4 if half else 0) + lift
        tones = chord_tones(scale, degree, tonic + 12 * (1 + (1 if section_b and degree != 0 else 0)))
        beat = 0.0
        for k, length in enumerate(rhythm):
            x = (phrase_bar + beat / s["beats"]) / 4.0
            arch = start + (peak - start) * np.sin(np.pi * min(1.0, x / 0.75) / 2) if x < 0.75 else peak + (end - peak) * (x - 0.75) / 0.25
            desired = int(round(arch)) + motif[(k + 3 * (bar % 2)) % len(motif)]
            strong = beat == 0 or length >= 1.5 or (s["beats"] >= 3 and beat == 2)
            if (closing or half) and k == len(rhythm) - 1:
                target = scale_note(scale, tonic, end) if half else tonic + 12 + (12 if section_b else 0)
                index = nearest_index(scale, tonic, target)
            elif strong:
                want = scale_note(scale, tonic, desired)
                pool = [t + 12 * o for t in tones for o in (-1, 0, 1)]
                index = nearest_index(scale, tonic, min(pool, key=lambda m: abs(m - want)))
            else:
                index = desired
            notes.append((bar, beat, length, scale_note(scale, tonic, index)))
            beat += length
    return bars, notes


# ---------------------------------------------------------------------------------------------
# Arrangements
# ---------------------------------------------------------------------------------------------

def arrange(style, seed, soft=False):
    rng = np.random.default_rng(seed)
    s = STYLES[style]
    tonic = int(rng.choice([50, 52, 55, 57] if style != "narodnjaci" else [50, 52, 55]))
    bpm = float(rng.uniform(*s["bpm"])) * (0.85 if soft else 1.0)
    beat = 60.0 / bpm if style != "narodnjaci" else 60.0 / bpm  # narodnjaci: beats are eighth-note pairs
    bars, notes = compose(style, rng, tonic)
    bar_len = s["beats"] * beat
    seconds = len(bars) * bar_len
    lead_gain = 0.75 if soft else 1.0
    scale = s["scale"]

    def ornament(mix, at, length, midi, vel, voice, pan):
        # A quick upper mordent on long, accented notes, the way kafana players decorate the tune.
        if length >= 1.0 and rng.random() < 0.45:
            grace = scale_note(scale, tonic, nearest_index(scale, tonic, midi) + 1)
            g = 0.06
            mix.add(voice(hz(midi), g, vel * 0.8), at, pan)
            mix.add(voice(hz(grace), g, vel * 0.8), at + g, pan)
            mix.add(voice(hz(midi), length * beat - 2 * g, vel), at + 2 * g, pan)
        else:
            mix.add(voice(hz(midi), length * beat * 0.96, vel), at, pan)

    def render(mix, offset):
        r = np.random.default_rng(seed + 1)
        for bar, degree in enumerate(bars):
            t0 = offset + bar * bar_len
            tones = chord_tones(scale, degree, tonic)
            root = tones[0] - 12
            if style == "starogradske":
                mix.add(pluck(hz(root - 12), beat * 2.6, 0.9, bright=0.3, decay=0.997), t0, -0.1, 0.9)
                for b in (1, 2):
                    for i, m in enumerate(tones):
                        mix.add(pluck(hz(m), beat * 0.8, 0.45, bright=0.55, body=0.4), t0 + b * beat + i * 0.012, 0.35, 0.6)
                mix.add(pluck(hz(root), beat * 0.9, 0.6, bright=0.4, body=0.3), t0, 0.35, 0.6)
            elif style == "izvorna":
                for b in range(2):
                    mix.add(reed(hz(root - 12 if b == 0 else tones[2] - 24), beat * 0.45, 0.5, bright=0.4), t0 + b * beat, -0.3, 0.5)
                    for m in tones:
                        mix.add(reed(hz(m - 12), beat * 0.3, 0.22, bright=0.5), t0 + b * beat + beat * 0.5, -0.3, 0.45)
                    mix.add(tapan_boom(0.9 if b == 0 else 0.6), t0 + b * beat, 0.0, 0.0 if soft else 0.8)
                    mix.add(tapan_stick(0.5), t0 + b * beat + beat * 0.5, 0.15, 0.0 if soft else 0.7)
                    mix.add(tapan_stick(0.35), t0 + b * beat + beat * 0.75, 0.15, 0.0 if soft else 0.6)
            elif style == "tamburica":
                for b in range(2):
                    mix.add(pluck(hz(root - 12 if b == 0 else tones[2] - 24), beat * 0.9, 0.85, bright=0.35, decay=0.996), t0 + b * beat, -0.15, 0.85)
                    for i, m in enumerate(tones):
                        mix.add(pluck(hz(m), beat * 0.35, 0.4, bright=0.8, decay=0.99), t0 + b * beat + beat * 0.5 + i * 0.008, 0.3, 0.55)
            elif style == "narodnjaci":
                pattern = [(0.0, "doum"), (1.0, "tek"), (2.0, "doum"), (2.5, "ka"), (3.0, "tek")]
                for at, kind in pattern:
                    mix.add(darbuka(kind, 0.8), t0 + at * beat, 0.1 if kind != "doum" else 0.0, 0.0 if soft else 0.9)
                for at in (0.0, 1.0, 2.0):
                    mix.add(pluck(hz(root - 12 if at != 1.0 else tones[2] - 24), beat * 0.8, 0.85, bright=0.3), t0 + at * beat, -0.1, 0.8)
                for at in (1.0, 3.0):
                    for m in tones:
                        mix.add(reed(hz(m - 12), beat * 0.4, 0.2, bright=0.5), t0 + at * beat, -0.35, 0.5)
        for bar, at, length, midi in notes:
            t = offset + bar * bar_len + at * beat
            vel = 0.9 if at == 0 else 0.75
            vel *= lead_gain
            if style == "tamburica":
                # Long notes are played with tremolo: the pick going back and forth.
                if length >= 1.0:
                    step = 1.0 / 13.0
                    k = 0.0
                    while k < length * beat - 0.02:
                        mix.add(pluck(hz(midi), step * 1.6, vel * (0.75 if k else 0.95), bright=0.85, decay=0.992), t + k, 0.15)
                        k += step
                else:
                    mix.add(pluck(hz(midi), length * beat, vel, bright=0.85, decay=0.994), t, 0.15)
                if 16 <= bar < 32 and not soft:
                    mix.add(bowed(hz(midi - 12), length * beat * 0.95, vel * 0.55), t, -0.4, 0.8)
            elif style == "narodnjaci" and 16 <= bar < 24 and not soft:
                ornament(mix, t, length, midi, vel, bowed, 0.3)
            else:
                ornament(mix, t, length, midi, vel, lambda f, d, v: reed(f, d, v, bright=0.8), 0.1)
        # The singer's part is the violin in the B strain of starogradske, doubling an octave down.
        if style == "starogradske" and not soft:
            for bar, at, length, midi in notes:
                if 16 <= bar < 24:
                    mix.add(bowed(hz(midi - 12), length * beat * 0.95, 0.45), offset + bar * bar_len + at * beat, -0.35)

    return loop(render, seconds), seconds


def sfx(kind):
    mix = Mix(3.0)
    if kind == "coin":
        mix.add(bell([1975, 2960, 3950], 0.18, 0.9), 0.0)
        mix.add(bell([2637, 3950, 5270], 0.25, 0.9), 0.08)
    elif kind == "clink":
        mix.add(bell([2840, 4130, 5960, 7420], 0.22, 0.8), 0.0, -0.1)
        mix.add(bell([3120, 4510, 6380], 0.18, 0.5), 0.05, 0.1)
    elif kind == "pour":
        rng = np.random.default_rng(9)
        n = int(0.7 * SR)
        t = np.arange(n) / SR
        sos = butter(2, [400.0, 1800.0], btype="band", fs=SR, output="sos")
        mix.add(sosfilt(sos, rng.uniform(-1, 1, n)) * np.sin(np.pi * t / 0.7) * (1 + 0.5 * np.sin(2 * np.pi * 23 * t)) * 0.6, 0.0)
    elif kind == "break":
        rng = np.random.default_rng(13)
        n = int(0.6 * SR)
        t = np.arange(n) / SR
        sos = butter(2, 3000.0, btype="high", fs=SR, output="sos")
        mix.add(sosfilt(sos, rng.uniform(-1, 1, n)) * np.exp(-t * 9) * 0.9, 0.0)
        for i in range(6):
            mix.add(bell([3000 + 900 * i, 4700 + 700 * i], 0.08, 0.4), 0.02 + 0.05 * i, (-1) ** i * 0.3)
    elif kind == "sting":
        for i, m in enumerate([62, 66, 69]):
            mix.add(reed(hz(m), 0.5, 0.6), 0.0 + i * 0.03, 0.0)
    elif kind == "fanfare":
        for i, m in enumerate([57, 61, 64, 69]):
            mix.add(reed(hz(m), 0.16, 0.8), i * 0.13, 0.0)
        for m in [57, 61, 64, 69, 73]:
            mix.add(reed(hz(m), 1.4, 0.55), 0.55, 0.0)
            mix.add(pluck(hz(m), 1.4, 0.4, bright=0.8), 0.55, 0.3)
        mix.add(tapan_boom(1.0), 0.55)
    wet = room(mix.buf, 0.12)
    end = np.max(np.nonzero(np.max(np.abs(wet), axis=1) > 1e-4)) + 1
    wet = wet[:end]
    peak = np.max(np.abs(wet)) + 1e-9
    return wet / peak * 0.8


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "client", "assets", "audio")
    os.makedirs(os.path.join(out, "songs"), exist_ok=True)
    os.makedirs(os.path.join(out, "sfx"), exist_ok=True)
    songs = json.load(open(os.path.join(ROOT, "data", "songs.json")))
    songs = songs.get("songs", songs) if isinstance(songs, dict) else songs
    for k, song in enumerate(songs):
        stereo, seconds = arrange(str(song["genre"]), 1000 + k * 37)
        write_ogg(stereo, os.path.join(out, "songs", song["id"] + ".ogg"))
        print(f"{song['id']}: {song['genre']}, {seconds:.1f} s")
    for venue, style in {"birtija": "izvorna", "kafana": "starogradske", "restoran": "tamburica", "splav": "narodnjaci"}.items():
        stereo, seconds = arrange(style, 5000 + len(venue), soft=True)
        write_ogg(stereo, os.path.join(out, "songs", "between_" + venue + ".ogg"))
        print(f"between_{venue}: {style}, {seconds:.1f} s")
    for kind in ["coin", "clink", "pour", "break", "sting", "fanfare"]:
        write_ogg(sfx(kind), os.path.join(out, "sfx", kind + ".ogg"), 4)
        print("sfx", kind)


if __name__ == "__main__":
    main()
