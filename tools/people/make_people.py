"""Makes a few dressed people with MakeHuman (MPFB) for a look in the game.

Run: Blender -b --python make_people.py -- <asset pack zip> <out dir>
Each person: body from macro settings, a skin, eyes, eyebrows, hair and
clothes from MakeHuman's own CC0 system assets, arms lowered from the
A-pose, exported as one GLB with the pose applied.
"""
import bpy, sys, os, glob, math

argv = sys.argv[sys.argv.index("--") + 1:]
pack, out_dir = argv[0], argv[1]
os.makedirs(out_dir, exist_ok=True)

from bl_ext.user_default.mpfb.services.locationservice import LocationService
from bl_ext.user_default.mpfb.services.assetservice import AssetService
from bl_ext.user_default.mpfb.services.humanservice import HumanService

data = LocationService.get_user_data()
if not glob.glob(os.path.join(data, "clothes", "*")):
    AssetService.fix_and_extract_asset_pack_zip(pack, data)
print("DATA", data, sorted(os.listdir(data)))


def find(kind, *names):
    """The first asset file of a kind whose path contains one of the names."""
    files = glob.glob(os.path.join(data, kind, "**", "*.mhclo" if kind != "skins" else "*.mhmat"), recursive=True)
    if kind == "eyes":
        files = glob.glob(os.path.join(data, kind, "**", "*.mhclo"), recursive=True)
    for n in names:
        for f in files:
            # From the start of the name, so "male_" never picks "female_".
            if os.path.basename(f).lower().startswith(n):
                return f
    for n in names:
        for f in files:
            if n in os.path.basename(f).lower():
                return f
    return files[0] if files else None


import random

COUNT = int(argv[2]) if len(argv) > 2 else 3
TEX = 1024


def person(i):
    """One person's look from its seed, mixed roughly like Grant County."""
    r = random.Random(1000 + i)
    male = r.random() < 0.49
    g = "male" if male else "female"
    eth = r.choices(["caucasian", "african", "asian"], [86, 10, 4])[0]
    age_key = r.choices(["young", "middleage", "old"], [35, 40, 25])[0]
    age = {"young": r.uniform(0.38, 0.5), "middleage": r.uniform(0.55, 0.72), "old": r.uniform(0.78, 0.95)}[age_key]
    if male:
        hair = r.choice(["short01", "short02", "short03", "short04"] + (["afro01"] if eth == "african" else []))
        outfit = r.choices(["male_casualsuit0%d" % r.randint(1, 6), "male_worksuit01", "male_elegantsuit01"], [70, 20, 10])[0]
    else:
        hair = r.choice(["bob01", "bob02", "braid01", "long01", "ponytail01"] + (["afro01"] if eth == "african" else []))
        outfit = r.choices(["female_casualsuit0%d" % r.randint(1, 2), "female_elegantsuit01", "female_sportsuit01"], [65, 20, 15])[0]
    clothes = [(outfit,), ("shoes0%d" % r.randint(1, 6),)]
    if male and age_key == "old" and r.random() < 0.2:
        clothes.append(("fedora01",))
    return {"name": "person%02d" % i,
            "macro": {"gender": 1.0 if male else 0.0, "age": age, "muscle": r.uniform(0.35, 0.65),
                      "weight": r.uniform(0.35, 0.85), "height": r.uniform(0.3, 0.7)},
            "race": {"caucasian": 1.0 if eth == "caucasian" else 0.0, "african": 1.0 if eth == "african" else 0.0,
                     "asian": 1.0 if eth == "asian" else 0.0},
            "skin": ("%s_%s_%s" % (age_key, eth, g),), "hair": (hair,), "clothes": clothes,
            "proxy": "%s_generic" % g}


PEOPLE = [person(i) for i in range(COUNT)]

for p in PEOPLE:
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    macro = {"gender": p["macro"]["gender"], "age": p["macro"]["age"], "muscle": p["macro"]["muscle"],
             "weight": p["macro"]["weight"], "height": p["macro"]["height"], "proportions": 0.5, "cupsize": 0.5,
             "firmness": 0.5, "race": p["race"]}
    try:
        b = HumanService.create_human(macro_detail_dict=macro)
    except TypeError:
        b = HumanService.create_human()
    # The skeleton first, so the body, hair and clothes added next all follow it.
    rig = None
    try:
        rig = HumanService.add_builtin_rig(b, "default")
    except Exception as e:
        print("RIG FAIL", e)
    # The lighter body (a proxy mesh) carries the skin; the full base mesh is hidden.
    proxy = glob.glob(os.path.join(data, "proxymeshes", p["proxy"], "*.proxy")) + \
        glob.glob(os.path.join(data, "proxymeshes", p["proxy"], "*.mhclo"))
    body = None
    if proxy:
        try:
            body = HumanService.add_mhclo_asset(proxy[0], b, asset_type="Proxymeshes", subdiv_levels=0)
        except Exception as e:
            print("PROXY FAIL", e)
    skin = find("skins", *p["skin"])
    if skin:
        try:
            HumanService.set_character_skin(skin, b, bodyproxy=body, skin_type="MAKESKIN")
        except Exception as e:
            print("SKIN FAIL", e)
    for kind, names in (("eyes", ("brown", "blue")), ("eyebrows", ("eyebrow001",)), ("hair", p["hair"])):
        f = find(kind, *names)
        if f:
            try:
                HumanService.add_mhclo_asset(f, b, asset_type=kind.capitalize(), subdiv_levels=0)
            except Exception as e:
                print("ASSET FAIL", kind, e)
    for names in p["clothes"]:
        f = find("clothes", *names)
        if f:
            try:
                HumanService.add_mhclo_asset(f, b, asset_type="Clothes", subdiv_levels=0)
            except Exception as e:
                print("CLOTHES FAIL", names, e)
    if rig is not None:
        bpy.context.view_layer.objects.active = rig
        bpy.ops.object.mode_set(mode="POSE")
        for side, sign in (("L", 1), ("R", -1)):
            pb = rig.pose.bones.get("upperarm01.%s" % side)
            if pb:
                pb.rotation_mode = "XYZ"
                pb.rotation_euler = (0.0, 0.0, sign * math.radians(-37))  # A-pose is about 40 deg off the side
        bpy.ops.object.mode_set(mode="OBJECT")
    if body is not None:
        b.hide_set(True)
    for img in bpy.data.images:
        if img.size[0] > TEX:
            img.scale(TEX, TEX * img.size[1] // max(img.size[0], 1))
    print("PERSON", p["name"], p["skin"][0], p["hair"][0], [c[0] for c in p["clothes"]])
    out = os.path.join(out_dir, p["name"] + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=True, export_animations=False,
                              export_skins=False, export_morph=False, use_visible=True,
                              export_image_format="JPEG")
    print("EXPORTED", out)
