"""Renders the game's sound files into assets/audio/.

    python3 tools/audio/make_assets.py [porch|clean|wide]

UI sounds come from the chosen palette in synth.py. The world loops are
real field recordings, made by field_recordings.py.
"""
import os, subprocess, sys, tempfile
import numpy as np
import synth

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")


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
    for name, x in synth.ui_palette(style).items():
        encode(x, os.path.join(ROOT, "ui", name + ".ogg"), 44100)
    print("wrote", ROOT)
