"""Makes the railroad's sounds in assets/audio/world/rail/, all in code from
the real machines' numbers:

    python3 tools/rail/rail_sounds.py            # render all
    python3 tools/rail/rail_sounds.py horn       # just one

- horn: a Nathan P5 five-chime air horn, the standard horn on US freight and
  Amtrak engines, chord D#4 F#4 G#4 B4 D#5 (a B6 chord). Held steady; the
  game blows it in the FRA pattern by turning it on and off.
- diesel: an EMD 16-645 two-stroke V16 (a GP38's prime mover), Roots-blown,
  at about notch 3: 16 firings a turn at 450 rpm, 120 a second. The game
  pitches it up with the throttle.
- crossing_bell: a mechanical crossing bell struck 150 times a minute (AREMA:
  100 to 325 strokes a minute).

Each loop is seamless and mono (the game places it in 3D), levelled with
the same steps as the town's other world loops (tools/audio/field_recordings.py).
"""
import os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "audio"))
import field_recordings as fr  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "assets", "audio", "world", "rail")
SR = fr.SR
RNG = np.random.default_rng(11)


def shaped_noise(n, lo, hi):
    """Noise between `lo` and `hi` Hz that loops: made in the frequency domain."""
    spec = np.fft.rfft(RNG.normal(0, 1, n))
    f = np.fft.rfftfreq(n, 1 / SR)
    spec[(f < lo) | (f > hi)] = 0
    x = np.fft.irfft(spec, n)
    return x / (np.std(x) + 1e-12)


def lowpass(x, hz):
    """Gentle low-pass in the frequency domain (circular, so the loop stays seamless)."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    spec /= 1 + (f / hz) ** 2
    return np.fft.irfft(spec, len(x))


def horn():
    """Five chimes, each a buzzing reed through its bell: strong harmonics
    falling off slowly, a little flutter, and air rushing past."""
    secs = 4.0
    n = int(secs * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f in [311.1, 370.0, 415.3, 493.9, 622.3]:
        # Whole cycles in the loop so it's seamless; a slow flutter of a few cents.
        f = round(f * secs) / secs
        wobble = 0.003 * f / (5.0 / secs) * np.sin(2 * np.pi * (5.0 / secs) * t + RNG.uniform(0, 6.28))
        phase = 2 * np.pi * f * t + wobble
        note = np.zeros(n)
        for h in range(1, int(9000 / f)):
            # The bell's flare lifts the 2 to 3 kHz band, as on a real horn.
            boost = 1.0 + 1.5 * np.exp(-((h * f - 2500) / 900) ** 2)
            note += boost * np.sin(h * phase + RNG.uniform(0, 6.28)) / h ** 0.9
        out += note
    out += 0.08 * np.std(out) * shaped_noise(n, 800, 6000)
    write("horn", fr.level(out, -11), 22050)


def diesel():
    """Sixteen cylinders firing in turn, each a little different, so the
    engine growls once a turn and drones 16 times a turn; the blower whines."""
    secs = 6.0
    n = int(secs * SR)
    t = np.arange(n) / SR
    rev = round(450 / 60 * secs) / secs  # whole turns in the loop
    fire = rev * 16
    out = np.zeros(n)
    strength = 1.0 + 0.35 * RNG.uniform(-1, 1, 16)
    pt = np.arange(int(0.03 * SR)) / SR
    pulse = np.exp(-pt / 0.006) * np.sin(2 * np.pi * 95 * pt)
    burst = RNG.normal(0, 1, len(pt)) * np.exp(-pt / 0.003)
    k = 0
    while k / fire < secs - 1e-9:
        at = int(round(k / fire * SR))
        s = strength[k % 16] * (1 + 0.05 * RNG.normal())
        idx = (at + np.arange(len(pt))) % n
        np.add.at(out, idx, s * (pulse + 0.25 * burst))
        k += 1
    out = lowpass(out, 900)
    # Exhaust rumble, and the Roots blower's whine.
    out += 0.5 * np.std(out) * shaped_noise(n, 30, 250)
    whine = round(fire * 6.5 * secs) / secs
    out += 0.06 * np.std(out) * np.sin(2 * np.pi * whine * t)
    write("diesel", fr.level(out, -12), 22050)


def crossing_bell():
    """A mechanical crossing bell: a hammer striking a bronze gong 150 times a
    minute. A gong's partials are inharmonic; the high ones die away fast."""
    rate = 150 / 60.0
    strokes = 10
    n = int(strokes / rate * SR)
    out = np.zeros(n)
    t = np.arange(int(1.6 * SR)) / SR
    partials = [(1.0, 1.0, 0.9), (2.0, 0.5, 0.45), (2.76, 0.42, 0.3), (5.4, 0.22, 0.14), (8.93, 0.1, 0.07)]
    f0 = 1180.0
    for k in range(strokes):
        hit = np.zeros_like(t)
        for ratio, amp, tau in partials:
            hit += amp * np.sin(2 * np.pi * f0 * ratio * t + RNG.uniform(0, 6.28)) * np.exp(-t / tau)
        # The hammer's click.
        hit += RNG.normal(0, 1, len(t)) * np.exp(-t / 0.004) * 0.6
        hit *= 1.0 + RNG.uniform(-0.06, 0.06)
        at = int(k / rate * SR)
        # Wrap the ring-out of the last strokes onto the start: a seamless loop.
        idx = (at + np.arange(len(t))) % n
        np.add.at(out, idx, hit)
    write("crossing_bell", fr.level(out, -12), 22050)


def write(name, x, rate):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".ogg")
    fr.encode(x, path, rate, 3)
    print("%-14s %5.1fs %6.1f KB" % (name, len(x) / SR, os.path.getsize(path) / 1024))


if __name__ == "__main__":
    for name in sys.argv[1:] or ["horn", "diesel", "crossing_bell"]:
        {"horn": horn, "diesel": diesel, "crossing_bell": crossing_bell}[name]()
