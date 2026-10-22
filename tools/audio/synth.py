"""Offline sound generator for Neighbors.

Everything here is built from code (numpy only): UI sounds and placeholder
city ambience. Run `python3 tools/audio/synth.py OUT_DIR` to render WAVs.
"""
import sys, os, wave
import numpy as np

SR = 44100
rng = np.random.default_rng(7)


def t_arr(dur):
    return np.arange(int(dur * SR)) / SR


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def fft_filter(x, lo=None, hi=None, order=2):
    """Zero-phase Butterworth-shaped band filter in the frequency domain."""
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR) + 1e-9
    g = np.ones_like(f)
    if hi:
        g /= np.sqrt(1 + (f / hi) ** (2 * order))
    if lo:
        g /= np.sqrt(1 + (lo / f) ** (2 * order))
    return np.fft.irfft(X * g, n)


def conv(x, ir):
    n = len(x) + len(ir) - 1
    m = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[:n]


def reverb(st, t60=2.2, wet=0.3, bright=6000):
    """Stereo convolution reverb with a decaying-noise impulse response."""
    tt = t_arr(t60 * 1.2)
    out = []
    for ch in range(2):
        ir = rng.standard_normal(len(tt)) * np.exp(-6.9 * tt / t60)
        ir = fft_filter(ir, lo=120, hi=bright)
        ir[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
        ir /= np.sqrt(np.sum(ir ** 2))
        out.append(conv(st[ch], ir))
    n = max(len(o) for o in out)
    res = np.zeros((2, n))
    res[:, : st.shape[1]] += st * (1 - wet)
    for ch in range(2):
        res[ch, : len(out[ch])] += out[ch] * wet
    return res


def place(buf, x, start, pan=0.0, gain=1.0):
    i = int(start * SR)
    if i >= buf.shape[1]:
        return
    x = x[: buf.shape[1] - i]
    l = np.cos((pan + 1) * np.pi / 4)
    r = np.sin((pan + 1) * np.pi / 4)
    buf[0, i : i + len(x)] += x * l * gain
    buf[1, i : i + len(x)] += x * r * gain


def norm(st, peak=0.89):
    m = np.max(np.abs(st)) + 1e-9
    return st * (peak / m)


def write_wav(path, st):
    st = np.clip(st, -1, 1)
    data = (st.T * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


# ---------------------------------------------------------------- instruments

def pluck(f, dur, bright=0.5, damp=0.996):
    """Karplus-Strong plucked string, vectorized one period at a time."""
    N = max(2, int(SR / f))
    total = int(dur * SR)
    y = np.zeros(total + 2 * N)
    burst = rng.uniform(-1, 1, N)
    burst = fft_filter(np.tile(burst, 4), hi=1500 + bright * 9000)[:N]
    y[:N] = burst
    k = 1
    while k * N < total + N:
        a = k * N
        prev = y[a - N : a]
        prev2 = y[a - N - 1 : a - 1] if a - N - 1 >= 0 else np.concatenate([[0], prev[:-1]])
        y[a : a + N] = damp * 0.5 * (prev + prev2)
        k += 1
    y = y[:total]
    y *= np.minimum(1, (total - np.arange(total)) / (0.05 * SR))
    return y


def epiano(f, dur, vel=1.0):
    t = t_arr(dur)
    idx = 1.8 * vel * np.exp(-t * 3.0)
    car = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * t))
    tine = 0.22 * vel * np.sin(2 * np.pi * f * 7.0 * t) * np.exp(-t * 18)
    env = np.exp(-t * 1.1) * np.minimum(1, t / 0.004)
    rel = np.minimum(1, (dur - t) / 0.15)
    return (car + tine) * env * rel


def mallet(f, dur, hard=0.5):
    t = t_arr(dur)
    y = np.sin(2 * np.pi * f * t) * np.exp(-t * 2.8)
    y += 0.35 * hard * np.sin(2 * np.pi * f * 3.93 * t) * np.exp(-t * 14)
    y += 0.12 * hard * np.sin(2 * np.pi * f * 9.9 * t) * np.exp(-t * 40)
    return y * np.minimum(1, t / 0.002)


def pad(f, dur, attack=1.5, bright=2500):
    t = t_arr(dur)
    y = np.zeros_like(t)
    for det in (-0.08, 0.0, 0.07):
        ff = midi(0) * 0 + f * 2 ** (det / 12)
        ph = rng.uniform(0, 2 * np.pi)
        for k in range(1, 14):
            y += np.sin(2 * np.pi * ff * k * t + ph * k) / k
    y = fft_filter(y, hi=bright)
    env = np.minimum(1, t / attack) * np.minimum(1, (dur - t) / attack)
    return y * env * 0.12


def steel(notes, dur, vib=5.2):
    """Pedal-steel-ish voice: a sine stack that glides between notes."""
    t = t_arr(dur)
    seg = len(t) // len(notes)
    fr = np.repeat([midi(n) for n in notes], seg)
    fr = np.concatenate([fr, np.full(len(t) - len(fr), fr[-1])])
    k = int(0.25 * SR)
    fr = np.convolve(fr, np.ones(k) / k, mode="same")
    fr[: k // 2] = fr[k // 2]
    fr[-k // 2 :] = fr[-k // 2 - 1]
    fr *= 1 + 0.004 * np.sin(2 * np.pi * vib * t) * np.minimum(1, t / 1.5)
    ph = 2 * np.pi * np.cumsum(fr) / SR
    y = np.sin(ph) + 0.4 * np.sin(2 * ph) + 0.15 * np.sin(3 * ph)
    env = np.minimum(1, t / 0.6) * np.minimum(1, (dur - t) / 1.0)
    return y * env * 0.25


def bass(f, dur):
    t = t_arr(dur)
    y = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(4 * np.pi * f * t)
    return y * np.exp(-t * 1.6) * np.minimum(1, t / 0.01) * np.minimum(1, (dur - t) / 0.05)


def noise(dur, lo=None, hi=None, order=2):
    return fft_filter(rng.standard_normal(int(dur * SR)), lo, hi, order)


def thud(dur=0.35, f0=140, f1=48):
    t = t_arr(dur)
    fr = f1 + (f0 - f1) * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t * 11)


def shaker(dur=0.12):
    t = t_arr(dur)
    return noise(dur, lo=5000, hi=11000) * np.exp(-t * 35) * np.minimum(1, t / 0.01)


# ---------------------------------------------------------------- UI sound palettes
# Each palette returns the same set of named sounds so the game can swap them.

UI_NAMES = ["click", "tool", "road", "build", "bulldoze", "money", "milestone"]


def mix(*layers):
    """Sum (sound, delay_seconds, gain) layers into one mono buffer."""
    n = max(int(d * SR) + len(x) for x, d, g in layers)
    out = np.zeros(n)
    for x, d, g in layers:
        i = int(d * SR)
        out[i : i + len(x)] += x * g
    return out


def crumble(d=0.7, hi=3000):
    y = np.zeros(int(d * SR))
    for _ in range(26):
        g = noise(0.05, 300, hi) * np.exp(-t_arr(0.05) * 60)
        i = int(rng.uniform(0, 0.45) * SR)
        y[i : i + len(g)] += g * rng.uniform(0.2, 0.6)
    return y * np.exp(-t_arr(d) * 3)


def ui_palette(style):
    s = {}
    swish = lambda d, lo, hi, k: noise(d, lo, hi) * np.exp(-t_arr(d) * k)
    if style == "porch":  # wooden, marimba-like, acoustic
        tone = lambda n, d=0.5, h=0.6: mallet(midi(n), d, hard=h)
        s["click"] = mix((tone(84, 0.12, 0.8), 0, 0.5), (swish(0.12, 1500, 5000, 90), 0, 0.15))
        s["tool"] = mix((tone(79, 0.3, 0.8), 0, 0.6), (tone(86, 0.4, 0.8), 0.07, 0.6))
        s["road"] = mix((swish(0.35, 200, 1800, 9), 0, 0.35), (tone(67, 0.3, 0.5), 0.05, 0.5))
        s["build"] = mix((thud(0.4, 160, 60), 0, 0.7), (tone(79, 0.3), 0.08, 0.4))
        s["money"] = mix((tone(88, 0.3, 1.0), 0, 0.5), (tone(93, 0.6, 1.0), 0.08, 0.5))
        s["milestone"] = mix(*[(pluck(midi(n), 1.6, 0.6), i * 0.11, 0.5) for i, n in enumerate([67, 71, 74, 79])])
        hi = 2500
    elif style == "clean":  # soft glassy sines, modern UI
        def tone(n, d=0.3, dec=14):
            t = t_arr(d)
            return (np.sin(2 * np.pi * midi(n) * t) + 0.2 * np.sin(4 * np.pi * midi(n) * t)) * np.exp(-t * dec) * np.minimum(1, t / 0.003)
        s["click"] = tone(91, 0.08, 60) * 0.45
        s["tool"] = mix((tone(81, 0.25), 0, 0.45), (tone(88, 0.25), 0.06, 0.45))
        s["road"] = mix((swish(0.3, 400, 3000, 14), 0, 0.25), (tone(69, 0.3, 10), 0, 0.45))
        s["build"] = mix((thud(0.35, 130, 55), 0, 0.6), (epiano(midi(76), 0.5), 0.03, 0.25))
        s["money"] = mix((epiano(midi(86), 0.6), 0, 0.4), (epiano(midi(93), 0.6), 0.09, 0.4))
        s["milestone"] = mix(*[(epiano(midi(n), 1.4), i * 0.1, 0.35) for i, n in enumerate([74, 78, 81, 86, 90])])
        hi = 3500
    else:  # wide: felt, muted, airy
        def tone(n, d=0.6):
            t = t_arr(d)
            y = np.sin(2 * np.pi * midi(n) * t) + 0.3 * np.sin(2 * np.pi * midi(n) * 2.01 * t) * np.exp(-t * 6)
            return y * np.exp(-t * 6) * np.minimum(1, t / 0.008)
        s["click"] = fft_filter(tone(81, 0.15), hi=2500) * 0.6
        s["tool"] = mix((tone(76, 0.4), 0, 0.4), (tone(83, 0.4), 0.08, 0.4))
        s["road"] = mix((swish(0.45, 150, 1200, 7), 0, 0.35), (tone(64, 0.45), 0, 0.3))
        s["build"] = mix((thud(0.45, 120, 50), 0, 0.7), (tone(76, 0.4), 0.06, 0.3))
        s["money"] = mix((tone(88, 0.7), 0, 0.35), (tone(92, 0.7), 0.1, 0.35))
        s["milestone"] = mix((steel([64, 68, 71, 76], 2.2), 0, 1.4), *[(tone(n, 1.5), i * 0.3, 0.25) for i, n in enumerate([76, 80, 83, 88])])
        hi = 2000
    s["bulldoze"] = mix((crumble(0.7, hi), 0, 1.0), (thud(0.4, 110, 40), 0, 0.8))
    for k in s:
        f = int(0.015 * SR)
        s[k][-f:] *= np.linspace(1, 0, f)  # no click at the tail
        s[k] = s[k] / (np.max(np.abs(s[k])) + 1e-9) * 0.8
    return s


def ui_demo(style):
    s = ui_palette(style)
    times = [0.2, 0.9, 1.6, 2.6, 3.6, 4.8, 5.8]
    buf = np.zeros((2, int(8.5 * SR)))
    for name, at in zip(UI_NAMES, times):
        place(buf, s[name], at, 0.0, 0.8 if name != "click" else 0.6)
    return reverb(buf, t60=0.6, wet=0.12), s


# ---------------------------------------------------------------- ambience

def bird_chirp(f0=3500, dur=0.09, sweep=1500):
    t = t_arr(dur)
    fr = f0 + sweep * np.sin(np.pi * t / dur)
    return np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.sin(np.pi * t / dur) ** 2


def robin_phrase():
    parts = []
    for _ in range(rng.integers(3, 6)):
        f0 = rng.uniform(2200, 3600)
        parts.append(bird_chirp(f0, rng.uniform(0.07, 0.16), rng.uniform(-900, 1400)))
        parts.append(np.zeros(int(rng.uniform(0.03, 0.09) * SR)))
    return np.concatenate(parts)


def sparrow_trill():
    c = bird_chirp(rng.uniform(4200, 5200), 0.035, -1400)
    gap = np.zeros(int(0.025 * SR))
    return np.concatenate([np.concatenate([c, gap])] * int(rng.integers(5, 10)))


def car_pass(dur=4.0, speed=1.0):
    t = t_arr(dur)
    bell = np.exp(-((t - dur / 2) / (0.55 / speed)) ** 2)
    body = noise(dur, 60, 700) * 0.8 + noise(dur, 700, 2500) * 0.25 * bell
    hum = np.sin(2 * np.pi * np.cumsum(np.where(t < dur / 2, 92, 80)) / SR) * 0.15
    return (body + hum) * bell, np.tanh((t - dur / 2) * 2.2 * speed)


def ambience(length=30.0):
    """Zoomed out (wind, far-off town hum) blending to street level (birds, cars)."""
    n = int(length * SR)
    t = t_arr(length)
    buf = np.zeros((2, n))
    zoom = np.clip((t - 9) / 6, 0, 1)  # 0 = high above, 1 = street level
    gust = 0.6 + 0.4 * np.sin(2 * np.pi * 0.07 * t) * np.sin(2 * np.pi * 0.023 * t + 1)
    for ch in range(2):
        wind = noise(length, 150, 900) * gust * (1 - 0.65 * zoom)
        hum = noise(length, None, 220, 3) * 1.6 * (1 - 0.4 * zoom)
        leaves = noise(length, 2500, 8000) * 0.06 * gust * zoom
        buf[ch] += wind * 0.5 + hum * 0.6 + leaves
    for at in np.arange(15.0, length - 3, 1.7):
        if rng.random() < 0.55:
            place(buf, robin_phrase(), at + rng.uniform(0, 0.8), rng.uniform(-0.8, 0.8), 0.05)
        elif rng.random() < 0.5:
            place(buf, sparrow_trill(), at, rng.uniform(-0.8, 0.8), 0.035)
    for at in [10.5, 16.0, 19.5, 24.0, 27.0]:
        y, panc = car_pass(4.0, rng.uniform(0.8, 1.2))
        if rng.random() < 0.5:
            panc = -panc
        i = int(at * SR)
        y = y[: n - i]
        panc = panc[: len(y)]
        gz = zoom[i : i + len(y)]
        buf[0, i : i + len(y)] += y * np.cos((panc + 1) * np.pi / 4) * 0.5 * gz
        buf[1, i : i + len(y)] += y * np.sin((panc + 1) * np.pi / 4) * 0.5 * gz
    fade = np.minimum(1, np.minimum(t / 1.5, (length - t) / 1.5))
    return norm(buf * fade, 0.7)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "audio_out"
    os.makedirs(out, exist_ok=True)
    for key in ("porch", "clean", "wide"):
        demo, _ = ui_demo(key)
        write_wav(f"{out}/ui_{key}.wav", norm(demo, 0.8))
        print("done", key, flush=True)
    write_wav(f"{out}/ambience.wav", ambience())
    print("done ambience")
