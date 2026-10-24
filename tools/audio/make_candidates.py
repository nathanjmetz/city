"""Cuts the Sound picker's options (web/sfx/) from free CC0 sound packs.

Usage: python3 tools/audio/make_candidates.py SOURCE_DIR

SOURCE_DIR holds kenney/<pack>/Audio/*.ogg (https://kenney.nl audio packs)
and vcsl/... (the Versilian Community Sample Library, as .ogg). Every option
is trimmed of the silence before it, cut to a length that suits the sound,
faded out, made mono and brought to the same peak as the game's own sound
(0 dBFS), so the picker compares recordings, not loudness. Two-note and
three-note options (doorbell, milestone) are real instrument notes laid
one after another.

Writes web/sfx/<sound id>/<option name>.ogg and web/sfx/candidates.json, which the
picker reads (scripts/audio/sound_picker.gd).
"""

import glob
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "web", "sfx")
KENNEY = "Kenney (CC0)"
VCSL = "Versilian Community Sample Library (CC0)"

# Longest each sound may run, in seconds.
LENGTH = {"ui/click": 0.4, "ui/tool": 0.7, "ui/road": 0.9, "ui/build": 1.4, "ui/bulldoze": 1.2,
          "ui/money": 1.2, "ui/milestone": 3.5, "ui/doorbell": 3.5}

# sound id -> [(name, source kind, [file patterns], gap between notes in seconds)]
OPTIONS = {
    "ui/click": [
        ("Soft click", "k", ["interface-sounds/Audio/click_001"]),
        ("Tick", "k", ["interface-sounds/Audio/tick_001"]),
        ("Desk switch", "k", ["ui-audio/Audio/click1"]),
        ("Light switch", "k", ["ui-audio/Audio/switch2"]),
        ("Wood block, soft", "v", ["*Woodblock*/*wood_click_pp_rr1"]),
        ("Pencil tap", "k", ["impact-sounds/Audio/impactWood_light_002"]),
        ("Marimba, high and soft", "v", ["*Marimba*/*C6_soft_01"]),
        ("Playing card down", "k", ["casino-audio/Audio/card-place-2"]),
    ],
    "ui/tool": [
        ("Select", "k", ["interface-sounds/Audio/select_001"]),
        ("Toggle", "k", ["interface-sounds/Audio/toggle_001"]),
        ("Switch", "k", ["interface-sounds/Audio/switch_002"]),
        ("Paper slide", "k", ["casino-audio/Audio/card-slide-1"]),
        ("Book page", "k", ["rpg-audio/Audio/bookFlip1"]),
        ("Vibraphone, soft", "v", ["*Vibraphone/Soft Mallets/*soft_C5_v1_rr1*"]),
        ("Wood block", "v", ["*Woodblock*/*wood_click_mp"]),
    ],
    "ui/road": [
        ("Plank set down", "k", ["impact-sounds/Audio/impactPlank_medium_000"]),
        ("Wood knock", "k", ["impact-sounds/Audio/impactWood_medium_001"]),
        ("Soft drop", "k", ["interface-sounds/Audio/drop_001"]),
        ("Pencil line", "k", ["interface-sounds/Audio/scratch_002"]),
        ("Card laid down", "k", ["casino-audio/Audio/card-place-1"]),
        ("Marimba", "v", ["*Marimba*/*C4_med_01"]),
        ("Thud", "k", ["impact-sounds/Audio/impactSoft_medium_000"]),
    ],
    "ui/build": [
        ("Heavy wood", "k", ["impact-sounds/Audio/impactWood_heavy_000"]),
        ("Plank", "k", ["impact-sounds/Audio/impactPlank_medium_002"]),
        ("Drop", "k", ["interface-sounds/Audio/drop_002"]),
        ("Confirm", "k", ["interface-sounds/Audio/confirmation_001"]),
        ("Book set down", "k", ["rpg-audio/Audio/bookPlace1"]),
        ("Low marimba", "v", ["*Marimba*/*G2_med_01"]),
        ("Harp roll", "v", ["*Concert Harp/*KSHarp_C5_mf1", "*Concert Harp/*KSHarp_E5_mf1", "*Concert Harp/*KSHarp_G5_mf1"], 0.06),
        ("Soft heavy thud", "k", ["impact-sounds/Audio/impactSoft_heavy_000"]),
    ],
    "ui/bulldoze": [
        ("Rubble", "k", ["impact-sounds/Audio/impactMining_000"]),
        ("Plank knocked over", "k", ["impact-sounds/Audio/impactPlank_medium_004"]),
        ("Heavy wood", "k", ["impact-sounds/Audio/impactWood_heavy_003"]),
        ("Metal", "k", ["impact-sounds/Audio/impactMetal_medium_000"]),
        ("Close", "k", ["interface-sounds/Audio/close_001"]),
        ("Back", "k", ["interface-sounds/Audio/back_001"]),
        ("Thump", "k", ["impact-sounds/Audio/impactPunch_medium_000"]),
    ],
    "ui/money": [
        ("Coins in hand", "k", ["rpg-audio/Audio/handleCoins"]),
        ("Coins, more", "k", ["rpg-audio/Audio/handleCoins2"]),
        ("Chips stacked", "k", ["casino-audio/Audio/chips-stack-1"]),
        ("Chips clink", "k", ["casino-audio/Audio/chips-collide-1"]),
        ("Chip laid down", "k", ["casino-audio/Audio/chip-lay-1"]),
        ("Glockenspiel ding", "v", ["*Glockenspiel/*glock_soft_C7_03"]),
        ("Confirm", "k", ["interface-sounds/Audio/confirmation_002"]),
    ],
    "ui/milestone": [
        ("Glockenspiel C-G-C", "v", ["*Glockenspiel/*glock_medium_C5_01", "*Glockenspiel/*glock_medium_G5_01", "*Glockenspiel/*glock_medium_C6_01"], 0.16),
        ("Harp C-E-G", "v", ["*Concert Harp/*KSHarp_C5_mf1", "*Concert Harp/*KSHarp_E5_mf1", "*Concert Harp/*KSHarp_G5_mf1"], 0.16),
        ("Vibraphone C-E-G", "v", ["*Vibraphone/Soft Mallets/*soft_C3_v2_rr1*", "*Vibraphone/Soft Mallets/*soft_E3_v2_rr1*", "*Vibraphone/Soft Mallets/*soft_G3_v2_rr1*"], 0.16),
        ("Marimba C-G-C", "v", ["*Marimba*/*C4_med_01", "*Marimba*/*G4_med_01", "*Marimba*/*C6_med_01"], 0.14),
        ("Pizzicato strings", "k", ["music-jingles/Audio/Pizzicato jingles/jingles_PIZZI00"]),
        ("Pizzicato strings 2", "k", ["music-jingles/Audio/Pizzicato jingles/jingles_PIZZI03"]),
        ("Steel drum", "k", ["music-jingles/Audio/Steel jingles/jingles_STEEL00"]),
        ("Confirm", "k", ["interface-sounds/Audio/confirmation_004"]),
    ],
    "ui/doorbell": [
        ("Hand chimes E-C", "v", ["*Hand Chimes/*sus_E5_r01*", "*Hand Chimes/*sus_C5_r01*"], 0.45),
        ("Tubular bells E-C", "v", ["*Tubular Bells 1/*chimes_E4_pp_rr3", "*Tubular Bells 1/*chimes_C4_p_rr1"], 0.5),
        ("Vibraphone E-C", "v", ["*Vibraphone/Soft Mallets/*soft_E5_v1_rr1*", "*Vibraphone/Soft Mallets/*soft_C5_v1_rr1*"], 0.4),
        ("Glockenspiel G-C", "v", ["*Glockenspiel/*glock_soft_G5_01", "*Glockenspiel/*glock_soft_C5_02"], 0.4),
        ("Harp E-C", "v", ["*Concert Harp/*KSHarp_E5_mf1", "*Concert Harp/*KSHarp_C5_mf1"], 0.4),
        ("Shop door bell", "k", ["impact-sounds/Audio/impactBell_heavy_000"]),
        ("Bong", "k", ["interface-sounds/Audio/bong_001"]),
    ],
}


def find(src, kind, pattern):
    base = os.path.join(src, "kenney" if kind == "k" else "vcsl")
    hits = sorted(glob.glob(os.path.join(base, "**", pattern + ".ogg"), recursive=True))
    if not hits:
        hits = sorted(glob.glob(os.path.join(base, pattern + ".ogg")))
    if not hits:
        sys.exit("not found: " + pattern)
    return hits[0]


def peak(path):
    """The loudest sample in a file, in dBFS."""
    out = subprocess.run(["ffmpeg", "-nostdin", "-i", path, "-af", "volumedetect", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    return float(out.split("max_volume:")[1].split("dB")[0])


def cut(sound, files, gap, out):
    length = LENGTH[sound]
    inputs, chain = [], []
    for i, f in enumerate(files):
        inputs += ["-i", f]
        delay = int(i * gap * 1000)
        # Each note to full level first: some samples are recorded very quietly.
        chain.append(f"[{i}:a]aformat=channel_layouts=mono,volume={-1.0 - peak(f)}dB,silenceremove=start_periods=1:start_threshold=-50dB,adelay={delay}[n{i}]")
    mix = "".join(f"[n{i}]" for i in range(len(files)))
    chain.append(f"{mix}amix=inputs={len(files)}:normalize=0,atrim=0:{length},afade=t=out:st={max(length - 0.25, 0.05)}:d=0.25[m]")
    tmp = out + ".wav"
    subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y", *inputs, "-filter_complex", ";".join(chain),
                    "-map", "[m]", "-ar", "44100", tmp], check=True)
    top = peak(tmp)
    subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-i", tmp, "-af", f"volume={-0.3 - top}dB",
                    "-map_metadata", "-1", "-c:a", "libvorbis", "-q:a", "4", out], check=True)
    os.remove(tmp)


def main():
    src = sys.argv[1]
    listing = {}
    for sound, options in OPTIONS.items():
        folder = os.path.join(OUT, sound)
        os.makedirs(folder, exist_ok=True)
        listing[sound] = []
        for opt in options:
            name, kind, patterns = opt[:3]
            gap = opt[3] if len(opt) > 3 else 0.0
            # Named for what it is, so a pick kept on a computer stays right if the list changes.
            slug = "".join(c if c.isalnum() else "-" for c in name.lower()).strip("-").replace("--", "-")
            cut(sound, [find(src, kind, p) for p in patterns], gap, os.path.join(folder, slug + ".ogg"))
            listing[sound].append({"file": f"{sound}/{slug}.ogg", "name": name, "source": KENNEY if kind == "k" else VCSL})
    with open(os.path.join(OUT, "candidates.json"), "w") as f:
        json.dump({"sounds": listing}, f, indent="\t")
    print(sum(len(v) for v in listing.values()), "options")


if __name__ == "__main__":
    main()
