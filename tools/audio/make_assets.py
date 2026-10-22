"""Renders the game's sound files into assets/audio/.

    python3 tools/audio/make_assets.py [porch|clean|wide]

UI sounds come from the chosen palette in synth.py. Most world loops are
real field recordings made by field_recordings.py; the few with no good free
recording yet (a passing car, a transformer's hum) are built here. Every loop is made periodic, so it repeats
without a seam: noise is filtered in the frequency domain (which wraps
around) and every slow wobble fits a whole number of times into the loop.
"""
import os, subprocess, sys, tempfile
import numpy as np
import synth
from synth import SR, rng, t_arr, fft_filter, mallet, midi, bird_chirp

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")
WORLD_SR = 22050


def loop_noise(dur, lo=None, hi=None, order=2):
    return fft_filter(rng.standard_normal(int(dur * SR)), lo, hi, order)


def wobble(dur, cycles, depth, phase=0.0):
    t = t_arr(dur)
    return 1 + depth * np.sin(2 * np.pi * cycles * t / dur + phase)


def wrap_add(buf, x, at):
    """Adds x at sample `at`, wrapping round the end so the loop stays seamless."""
    n = len(buf)
    idx = (np.arange(len(x)) + at) % n
    np.add.at(buf, idx, x)


def car_engine(dur=4.0):
    """A passing family car at city speed: engine firing note, exhaust and tyre roar."""
    t = t_arr(dur)
    f = 36.0  # ~2,100 rpm on a four-cylinder: 2 firings per revolution
    eng = sum(np.sin(2 * np.pi * f * k * t + rng.uniform(0, 6)) / k ** 1.2 for k in range(1, 9))
    eng *= wobble(dur, 12, 0.08)
    tyre = loop_noise(dur, 250, 1400)
    tyre = tyre / np.std(tyre) * 0.25
    rumble = loop_noise(dur, None, 120, 3)
    rumble = rumble / np.std(rumble) * 0.35
    return eng * 0.5 + tyre + rumble


def wind_high(dur=12.0):
    """Wind as heard from high above: broad, slow gusts."""
    a = loop_noise(dur, 80, 700)
    b = loop_noise(dur, 400, 1800)
    return a * wobble(dur, 2, 0.45) + 0.4 * b * wobble(dur, 3, 0.6, 1.0)


def leaves(dur=10.0):
    """Wind in yard trees: soft high rustle in gusts."""
    x = loop_noise(dur, 2000, 7000)
    return x * wobble(dur, 2, 0.6) * wobble(dur, 5, 0.3, 2.0)


def birds_day(dur=16.0):
    """Robins and house sparrows, the common Midwest yard birds."""
    buf = np.zeros(int(dur * SR))
    for at in np.arange(0.3, dur, 1.3):
        at += rng.uniform(0, 0.6)
        if rng.random() < 0.5:
            x = synth.robin_phrase()
        else:
            x = synth.sparrow_trill()
        wrap_add(buf, x * rng.uniform(0.4, 1.0), int(at * SR))
    return buf


def crickets_night(dur=8.0):
    """Field crickets: ~4.6 kHz pulses in chirps of three, several insects."""
    buf = np.zeros(int(dur * SR))
    for _ in range(6):
        f0 = rng.uniform(4300, 4900)
        period = dur / int(rng.integers(10, 16))
        start = rng.uniform(0, period)
        pulse_t = t_arr(0.018)
        pulse = np.sin(2 * np.pi * f0 * pulse_t) * np.sin(np.pi * pulse_t / 0.018)
        g = rng.uniform(0.3, 1.0)
        for c in np.arange(start, dur, period):
            for k in range(3):
                wrap_add(buf, pulse * g, int((c + k * 0.03) * SR))
    return buf


def industry_hum(dur=6.0):
    """Light industry: 60 Hz electrical hum, a ventilation fan and machine clatter."""
    t = t_arr(dur)
    hum = sum(np.sin(2 * np.pi * 60 * k * t) / k for k in (1, 2, 3, 4, 6))
    fan = loop_noise(dur, 150, 900)
    fan = fan / np.std(fan) * 0.6
    buf = hum * 0.4 + fan
    clank = synth.thud(0.25, 400, 180) * 0.6 + synth.noise(0.25, 1500, 5000) * np.exp(-t_arr(0.25) * 30) * 0.4
    for i in range(int(dur / 0.75)):
        if i % 4 != 3:
            wrap_add(buf, clank * (0.8 if i % 2 else 0.5), int(i * 0.75 * SR))
    return buf


def rooftop_hvac(dur=5.0):
    """Shop rooftop units: a steady fan and compressor drone."""
    t = t_arr(dur)
    fan = loop_noise(dur, 90, 600)
    fan = fan / np.std(fan)
    comp = sum(np.sin(2 * np.pi * 120 * k * t) / k ** 1.5 for k in range(1, 5))
    return fan + 0.35 * comp


def transformer(dur=4.0):
    """Substation and pump house: the 120 Hz magnetostriction hum of transformers."""
    t = t_arr(dur)
    hiss = loop_noise(dur, 100, 400)
    return sum(np.sin(2 * np.pi * 120 * k * t + k) / k ** 1.3 for k in range(1, 7)) + 0.1 * hiss / np.std(hiss)


def corn_field(dur=12.0):
    """Wind through tall corn: dry leaf rustle in waves, plus summer insects."""
    rustle = loop_noise(dur, 1200, 6000)
    rustle *= wobble(dur, 3, 0.7) * wobble(dur, 7, 0.25, 1.3)
    t = t_arr(dur)
    cicada = loop_noise(dur, 3800, 5200, 4) * (0.5 + 0.5 * np.sin(2 * np.pi * 60 * t / dur * 4) ** 2)
    return rustle + 0.25 * cicada


WORLD = {
    "car_engine": car_engine,
    "transformer": transformer,
}


def encode(x, path, rate, mono=True, quality=3):
    x = np.asarray(x)
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
    st = np.vstack([x, x]) if x.ndim == 1 else x
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tmp = f.name
    synth.write_wav(tmp, st)
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", tmp, "-ar", str(rate)]
    if mono:
        cmd += ["-ac", "1"]
    cmd += ["-c:a", "libvorbis", "-q:a", str(quality), path]
    subprocess.run(cmd, check=True)
    os.remove(tmp)


if __name__ == "__main__":
    style = sys.argv[1] if len(sys.argv) > 1 else "porch"
    os.makedirs(os.path.join(ROOT, "ui"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "world"), exist_ok=True)
    for name, x in synth.ui_palette(style).items():
        encode(x, os.path.join(ROOT, "ui", name + ".ogg"), 44100)
    for name, fn in WORLD.items():
        encode(fn(), os.path.join(ROOT, "world", name + ".ogg"), WORLD_SR)
    print("wrote", ROOT)
