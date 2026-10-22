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
SOURCES = {}


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
    rms = np.sqrt(np.mean(x ** 2)) + 1e-12
    x = x * (10 ** (rms_db / 20) / rms)
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
