# Bakes res://art/noise: truly periodic noise with the same spectrum and
# histogram as the old seamless NoiseTexture2D, without its seam bands.
# First: godot --headless -s tools/noise_refs.gd ; then: python3 tools/bake_noise.py
import glob, os, numpy as np
from PIL import Image
src = "/tmp/noise_refs"
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "noise")
for ref_path in sorted(glob.glob(src + "/ref_*.png")):
    key = os.path.basename(ref_path)[4:-4]
    size, freq, octv, seed = key.split("_")
    S = int(size)
    ref = np.array(Image.open(ref_path)).astype(np.float64)
    raw = np.array(Image.open(f"{src}/raw_{key}.png")).astype(np.float64)
    raw -= raw.mean()
    w = np.hanning(raw.shape[0])
    P = np.abs(np.fft.fft2(raw * np.outer(w, w))) ** 2
    f = np.fft.fftfreq(raw.shape[0])
    kr = np.hypot(*np.meshgrid(f, f, indexing="ij"))
    bins = np.linspace(0, 0.75, 200)
    idx = np.digitize(kr.ravel(), bins)
    prof = np.array([P.ravel()[idx == i].mean() if np.any(idx == i) else 0 for i in range(1, len(bins))])
    centers = (bins[:-1] + bins[1:]) / 2
    fs = np.fft.fftfreq(S)
    ks = np.hypot(*np.meshgrid(fs, fs, indexing="ij"))
    amp = np.sqrt(np.interp(ks, centers, prof, right=0))
    amp[0, 0] = 0
    rng = np.random.default_rng(int(seed) * 7919 + S)
    white = np.fft.fft2(rng.standard_normal((S, S)))
    n = np.real(np.fft.ifft2(white * amp))
    # Histogram match to the old texture so every shader's thresholds hold.
    order = np.argsort(n.ravel())
    matched = np.empty(S * S)
    matched[order] = np.sort(ref.ravel())
    Image.fromarray(matched.reshape(S, S).astype(np.uint8), "L").save(f"{out}/noise_{key}.png")
    print(key, ref.std(), matched.std())
