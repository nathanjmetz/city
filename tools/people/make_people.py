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
            if n in os.path.basename(f).lower():
                return f
    return files[0] if files else None


PEOPLE = [
    {"name": "man", "macro": {"gender": 1.0, "age": 0.5, "muscle": 0.55, "weight": 0.55},
     "skin": ("young_caucasian_male", "male"), "hair": ("short02", "short"),
     "clothes": [("male_casualsuit", "casualsuit", "shirt"), ("jeans", "pants"), ("shoes01", "shoes")]},
    {"name": "woman", "macro": {"gender": 0.0, "age": 0.45, "muscle": 0.5, "weight": 0.5},
     "skin": ("young_caucasian_female", "female"), "hair": ("ponytail", "long", "bob"),
     "clothes": [("female_casualsuit", "casualsuit", "dress"), ("shoes02", "shoes")]},
    {"name": "older", "macro": {"gender": 1.0, "age": 0.85, "muscle": 0.45, "weight": 0.7},
     "skin": ("old_caucasian_male", "old", "male"), "hair": ("short04", "short"),
     "clothes": [("male_worksuit", "worksuit", "sweater"), ("shoes03", "shoes")]},
]

for p in PEOPLE:
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    macro = {"gender": p["macro"]["gender"], "age": p["macro"]["age"], "muscle": p["macro"]["muscle"],
             "weight": p["macro"]["weight"], "height": 0.5, "proportions": 0.5, "cupsize": 0.5, "firmness": 0.5,
             "race": {"african": 0.15, "asian": 0.1, "caucasian": 0.75}}
    try:
        b = HumanService.create_human(macro_detail_dict=macro)
    except TypeError:
        b = HumanService.create_human()
    skin = find("skins", *p["skin"])
    if skin:
        try:
            HumanService.set_character_skin(skin, b, skin_type="MAKESKIN")
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
    # Arms down from the modelling A-pose, through a rig, then baked in.
    try:
        rig = HumanService.add_builtin_rig(b, "default")
        bpy.context.view_layer.objects.active = rig
        bpy.ops.object.mode_set(mode="POSE")
        for side, sign in (("l", 1), ("r", -1)):
            for name in ("upperarm01.%s" % side, "upperarm01.%s" % side.upper()):
                pb = rig.pose.bones.get(name)
                if pb:
                    pb.rotation_mode = "XYZ"
                    pb.rotation_euler = (0.0, 0.0, sign * math.radians(-60))
        bpy.ops.object.mode_set(mode="OBJECT")
    except Exception as e:
        print("RIG FAIL", e)
    print("PERSON", p["name"], [o.name for o in bpy.data.objects])
    out = os.path.join(out_dir, p["name"] + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=True, export_animations=False,
                              export_skins=False, export_morph=False)
    print("EXPORTED", out)
