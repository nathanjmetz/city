"""Masks for recolouring the ready-made people's clothes (NearPeople).

Run: python3 tools/people/make_masks.py
For each clothes texture in art/people, writes art/people/masks/<suit>.png:
red where the top is (shirt, blouse, sweater), green where the bottoms are
(jeans, skirt, overalls), and prints each part's mean brightness, which
NearPeople.SUITS keeps so the shader can recolour by brightness and keep the
cloth's folds and seams. Also paints the MakeHuman logo off the T-shirt and
the body suit off the 'special suit' skins. Run it once on fresh art.
"""
import glob, os, colorsys
from PIL import Image, ImageFilter

HERE = os.path.join(os.path.dirname(__file__), "..", "..", "art", "people")
OUT = os.path.join(HERE, "masks")
os.makedirs(OUT, exist_ok=True)


def lum(p):
    return 0.3 * p[0] + 0.59 * p[1] + 0.11 * p[2]


def bluish(p):
    h, s, v = colorsys.rgb_to_hsv(p[0] / 255, p[1] / 255, p[2] / 255)
    # Faded denim is pale, but still bluer than it is red.
    return 0.5 < h < 0.7 and (s > 0.25 or s > 0.08 and p[2] > p[0] + 12) and v > 0.2


def classify(suit, x, y, p):
    """'top', 'bottoms' or None for a pixel at (x, y) in 0..1 UV."""
    if suit == "female_casualsuit01":
        # Tee panels across the top half, its sleeves bottom right; cropped
        # jeans bottom left.
        if y < 0.5 or x > 0.72 and y > 0.6:
            return "top"
        return "bottoms"
    if suit == "female_elegantsuit01":
        # The grey skirt top left, the striped blouse's pieces round it.
        return "bottoms" if y < 0.52 and x < 0.76 else "top"
    if suit == "male_worksuit01":
        # Bib overalls: only the denim.
        return "bottoms" if bluish(p) else None
    return "bottoms" if bluish(p) else "top"


def clean_skin(f):
    """The 'special suit' skins have a sci-fi body suit painted on, which
    shows on bare arms and legs: paint it over in the skin's own colour."""
    im = Image.open(f).convert("RGB")
    w, h = im.size
    px = im.load()
    mask = Image.new("L", (w, h))
    mp = mask.load()
    skin = []
    for y in range(h):
        for x in range(w):
            if x >= 0.78 * w:
                continue  # the head, face and hair
            r, g, b = px[x, y]
            _, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if y < 0.86 * h and (s < 0.28 and v < 0.75 or r > 180 and g < 150 and b < 90 and s > 0.6):
                mp[x, y] = 255
            else:
                skin.append((r, g, b))
    skin.sort(key=sum)
    fill = Image.new("RGB", (w, h), skin[len(skin) // 2])
    mask = mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(2))
    Image.composite(fill, im, mask).save(f)


def main():
    for f in sorted(glob.glob(os.path.join(HERE, "person*_special_suit.png"))):
        clean_skin(f)
    done = set()
    for f in sorted(glob.glob(os.path.join(HERE, "person*_*suit*_diffuse.png"))):
        suit = os.path.basename(f).split("_", 1)[1].rsplit("_diffuse", 1)[0]
        im = Image.open(f).convert("RGB")
        if suit == "female_casualsuit01":
            # The MakeHuman logo on the front: cover it with plain shirt cloth
            # from just beside it.
            w, h = im.size
            box = (int(0.715 * w), int(0.15 * h), int(0.885 * w), int(0.34 * h))
            patch = im.crop((int(0.54 * w), box[1], int(0.54 * w) + box[2] - box[0], box[3]))
            im.paste(patch, box[:2])
            im.save(f)
        if suit in done:
            continue
        done.add(suit)
        w, h = im.size
        # Each pixel's part, then the most common part round it, so faded
        # denim and dark stripes go with the cloth they're on.
        parts = Image.new("L", (w, h))
        px, pp = im.load(), parts.load()
        for y in range(h):
            for x in range(w):
                p = px[x, y]
                if max(p) < 18:
                    continue  # the black around the pieces
                part = classify(suit, x / w, y / h, p)
                if part is not None:
                    pp[x, y] = 1 if part == "top" else 2
        parts = parts.filter(ImageFilter.ModeFilter(9))
        pp = parts.load()
        mask = Image.new("RGB", (w, h))
        mp = mask.load()
        sums = {"top": [0.0, 0], "bottoms": [0.0, 0]}
        for y in range(h):
            for x in range(w):
                k = pp[x, y]
                if k == 0:
                    continue
                part = "top" if k == 1 else "bottoms"
                mp[x, y] = (255, 0, 0) if k == 1 else (0, 255, 0)
                sums[part][0] += lum(px[x, y]) / 255
                sums[part][1] += 1
        mask.save(os.path.join(OUT, suit + ".png"))
        means = {k: round(v[0] / max(v[1], 1), 3) for k, v in sums.items()}
        print('"%s": %s,' % (suit, means))


main()
