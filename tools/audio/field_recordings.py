"""Turns curated field recordings into the game's world loops in assets/audio/world/.

    python3 tools/audio/field_recordings.py            # download (cached) and render all
    python3 tools/audio/field_recordings.py birds_day  # just one

Every source is a real recording on Wikimedia Commons under a free license
(public domain, CC0 or CC BY; never share-alike or non-commercial). Each
entry says which stretch of the recording to use, how to clean it up, and
why it was picked. The stretch is made into a seamless loop by crossfading
its tail into its head, then turned to mono (the game places it in 3D),
levelled and compressed small for the web build.

Credits for every file are in assets/audio/LICENSES.md; keep them in step
with SOURCES when a recording changes.
"""
import json, os, subprocess, sys, time, urllib.parse, urllib.request
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "audio", "world")
CACHE = os.path.join(HERE, ".cache")
UA = "NeighborsCityBuilder/0.1 (https://github.com/nathanjmetz/city)"
SR = 44100

# name: Commons file, start and length (s), crossfade (s), band (Hz),
# output rate, target loudness (dBFS RMS), and why it fits the game.
SOURCES = {
    "birds_day": dict(file="Birds singing in garden.ogg", start=1, length=44, fade=3, band=(150, 0),
                      rate=22050, rms=-11, why="Songbirds in a garden: the backyard sound of a summer morning."),
    "crickets_night": dict(file="Pterophylla camellifolia singing.wav", start=1.5, length=9.5, fade=1.5,
                           band=(1500, 0), rate=22050, rms=-16,
                           why="Common true katydid, recorded in Naperville, Illinois: the Midwest summer night."),
    "leaves": dict(file="Rustling leaves (Gravity Sound).wav", start=2, length=13, fade=2, band=(200, 0),
                   rate=22050, rms=-12, why="Wind in yard trees."),
    "corn_field": dict(file="Meadow (Gravity Sound).wav", start=0, length=40, fade=3, band=(120, 0),
                       rate=22050, rms=-16, why="Wind and insects over tall grass, heard across a field."),
    "wind_high": dict(file="Wind in forest (Gravity Sound).wav", start=3, length=44, fade=4, band=(60, 0),
                      rate=22050, rms=-12, why="Broad, steady wind for when the camera is high up."),
    "rooftop_hvac": dict(file="Resident air-conditioned out door unit.ogg", start=1, length=26, fade=2,
                         band=(50, 0), rate=22050, rms=-12, why="An outdoor AC unit: shop rooftops in summer."),
    "industry_hum": dict(file="WWS Graindryer.ogg", start=2, length=30, fade=3, band=(40, 0), rate=22050,
                         rms=-11, why="A working grain dryer: the drone of rural Midwest industry."),
    "traffic_far": dict(file="Highway from bridge center.ogg", start=40, length=60, fade=4, band=(40, 6000),
                        rate=22050, rms=-14, why="Highway traffic from a bridge: the far-off roll of town traffic."),
}


def fetch(url):
    for i in range(10):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            return urllib.request.urlopen(req, timeout=120).read()
        except Exception as e:
            print("  retry", i, e)
            time.sleep(min(20 * (i + 1), 120))
    raise SystemExit("could not fetch " + url)


def source_file(title):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, title.replace("/", "_"))
    if not os.path.exists(path):
        q = urllib.parse.urlencode({"action": "query", "format": "json", "titles": "File:" + title,
                                    "prop": "imageinfo", "iiprop": "url"})
        pages = json.loads(fetch("https://commons.wikimedia.org/w/api.php?" + q))["query"]["pages"]
        url = next(iter(pages.values()))["imageinfo"][0]["url"]
        data = fetch(url)
        with open(path, "wb") as f:
            f.write(data)
    return path


def decode(path, start, length, band):
    """Mono float samples of [start, start + length], band-limited by ffmpeg."""
    lo, hi = band
    af = ["pan=mono|c0=0.5*c0+0.5*c1" if channels(path) > 1 else "anull"]
    if lo:
        af.append("highpass=f=%d:poles=2" % lo)
    if hi:
        af.append("lowpass=f=%d:poles=2" % hi)
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-ss", str(start), "-t", str(length),
           "-i", path, "-af", ",".join(af), "-ar", str(SR), "-ac", "1", "-f", "f32le", "-"]
    return np.frombuffer(subprocess.run(cmd, check=True, capture_output=True).stdout, np.float32).astype(np.float64)


def channels(path):
    cmd = ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=channels",
           "-of", "csv=p=0", path]
    return int(subprocess.run(cmd, check=True, capture_output=True, text=True).stdout.strip() or 1)


def make_loop(x, fade):
    """Fold the last `fade` seconds over the start with an equal-power crossfade,
    so the end runs straight back into the beginning without a seam."""
    n = int(fade * SR)
    body, tail = x[:-n].copy(), x[-n:]
    t = np.linspace(0.0, np.pi / 2, n)
    body[:n] = body[:n] * np.sin(t) + tail * np.cos(t)
    return body


def level(x, rms_db):
    """Bring the loop to `rms_db`, then tame the odd loud peak (a close bird,
    a passing truck) with a smooth limiter instead of turning it all down."""
    rms = np.sqrt(np.mean(x ** 2)) + 1e-12
    x = x * (10 ** (rms_db / 20) / rms)
    block = 256
    n = len(x) // block * block
    env = np.abs(x[:n]).reshape(-1, block).max(1)
    env = np.maximum(env, np.roll(env, 1))
    env = np.maximum(env, np.roll(env, -1))
    gain = np.minimum(1.0, 0.9 / (env + 1e-12))
    gain = np.convolve(np.concatenate([gain[-4:], gain, gain[:4]]), np.ones(5) / 5, "same")[4:-4]
    gain = np.minimum(gain, 1.0)
    x = x.copy()
    x[:n] *= np.repeat(gain, block)
    peak = np.max(np.abs(x))
    return x * (0.95 / peak) if peak > 0.95 else x


def encode(x, path, rate, quality):
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "f64le", "-ar", str(SR), "-ac", "1",
           "-i", "-", "-ar", str(rate), "-c:a", "libvorbis", "-q:a", str(quality), path]
    subprocess.run(cmd, input=x.astype("<f8").tobytes(), check=True)


def render(name):
    s = SOURCES[name]
    x = decode(source_file(s["file"]), s["start"], s["length"] + s["fade"], s["band"])
    x = level(make_loop(x, s["fade"]), s["rms"])
    path = os.path.join(OUT, name + ".ogg")
    encode(x, path, s["rate"], s.get("quality", 2))
    print("%-16s %5.1fs %6.1f KB  <- %s" % (name, len(x) / SR, os.path.getsize(path) / 1024, s["file"]))


if __name__ == "__main__":
    for name in sys.argv[1:] or SOURCES:
        render(name)
