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


# --- Walking (WALK=1): one walk cycle baked into a vertex animation texture ---
# The standard way games draw crowds: every frame of the cycle stores each
# vertex's position in a float texture (EXR), and the game's shader plays it
# back, so hundreds of people walk with no skeleton each.
FRAMES = 16


def bake_walk(name, rig, out_dir):
    import numpy as np
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.visible_get()]
    for o in meshes:
        for m in list(o.modifiers):
            if m.type != "ARMATURE":
                bpy.context.view_layer.objects.active = o
                try:
                    bpy.ops.object.modifier_apply(modifier=m.name)
                except Exception:
                    o.modifiers.remove(m)
    # One texture-coordinate set for all parts (same name, so the join merges
    # them), so the walk lookup added after is the second set (UV2 in Godot).
    for o in meshes:
        uvs = o.data.uv_layers
        keep = uvs.active
        for layer in [l for l in uvs if l != keep]:
            uvs.remove(layer)
        if keep is not None:
            keep.name = "UVMap"
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    main = max(meshes, key=lambda o: len(o.data.vertices))
    bpy.context.view_layer.objects.active = main
    bpy.ops.object.join()
    if not any(m.type == "ARMATURE" for m in main.modifiers):
        mod = main.modifiers.new("Armature", "ARMATURE")
        mod.object = rig
    n = len(main.data.vertices)
    width = 2048
    rows = (n + width - 1) // width
    # The walk: thighs swing 24 deg, knees bend on the swing, arms swing
    # opposite the legs; 16 frames a stride.
    import math as m
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    frames = []
    for f in range(FRAMES):
        ph = 2 * m.pi * f / FRAMES
        for side, sgn in (("L", 1), ("R", -1)):
            s = sgn * m.sin(ph)
            th = rig.pose.bones.get("upperleg01.%s" % side)
            kn = rig.pose.bones.get("lowerleg01.%s" % side)
            ar = rig.pose.bones.get("upperarm01.%s" % side)
            if th:
                th.rotation_mode = "XYZ"
                th.rotation_euler = (m.radians(24) * s, 0, 0)
            if kn:
                kn.rotation_mode = "XYZ"
                kn.rotation_euler = (m.radians(-38) * max(0.0, m.sin(ph * sgn + m.pi * 0.35)), 0, 0)
            if ar:
                ar.rotation_mode = "XYZ"
                ar.rotation_euler = (m.radians(-16) * s, 0, sgn * m.radians(-37))
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        ev = main.evaluated_get(dg)
        me = ev.to_mesh()
        co = np.empty(len(me.vertices) * 3, dtype=np.float32)
        me.vertices.foreach_get("co", co)
        ev.to_mesh_clear()
        # In scene space, as the exported file places it.
        mw = np.array(main.matrix_world, dtype=np.float32)
        co = co.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3]
        frames.append(co)
    bpy.ops.object.mode_set(mode="OBJECT")
    # Texture: FRAMES blocks of `rows` rows, `width` vertices a row; RGB is
    # the vertex position (Blender: x right, y back, z up; the game swaps).
    img = np.zeros((FRAMES * rows, width, 4), dtype=np.float32)
    img[..., 3] = 1.0
    for f, co in enumerate(frames):
        block = np.zeros((rows * width, 3), dtype=np.float32)
        block[:n] = co
        img[f * rows:(f + 1) * rows, :, :3] = block.reshape(rows, width, 3)
    tex = bpy.data.images.new(name + "_walk", width, FRAMES * rows, alpha=True, float_buffer=True)
    tex.pixels.foreach_set(img[::-1].ravel())  # Blender images run bottom-up
    tex.filepath_raw = os.path.join(out_dir, name + "_walk.exr")
    tex.file_format = "OPEN_EXR"
    tex.save()
    # Each vertex's place in the texture, as a second UV set.
    uv = main.data.uv_layers.new(name="vat")
    loops_v = np.empty(len(main.data.loops), dtype=np.int32)
    main.data.loops.foreach_get("vertex_index", loops_v)
    uvs = np.zeros((len(loops_v), 2), dtype=np.float32)
    uvs[:, 0] = (loops_v % width + 0.5) / width
    uvs[:, 1] = (loops_v // width + 0.5) / (FRAMES * rows)
    uv.data.foreach_set("uv", uvs.ravel())
    print("BAKED", name, n, "vertices", width, "x", FRAMES * rows, "uv sets", [l.name for l in main.data.uv_layers])
    return main



def keyframe_walk(rig):
    """The walk as a looping action on the skeleton (frames 1-17), for engines
    that play skeletons (Godot's AnimationPlayer)."""
    import math as m
    # Arms down becomes the resting pose itself (the meshes keep the posed
    # shape, the skeleton takes it as rest), so the walk only swings them.
    for o in [o for o in bpy.data.objects if o.type == "MESH" and o.visible_get()]:
        mods = [md for md in o.modifiers if md.type == "ARMATURE"]
        if mods:
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.modifier_apply(modifier=mods[0].name)
            md = o.modifiers.new("Armature", "ARMATURE")
            md.object = rig
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.animation_data_create()
    act = bpy.data.actions.new("walk")
    rig.animation_data.action = act
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    for f in range(FRAMES + 1):
        ph = 2 * m.pi * f / FRAMES
        for side, sgn in (("L", 1), ("R", -1)):
            s = sgn * m.sin(ph)
            for bone, rot in (("upperleg01.%s" % side, (m.radians(24) * s, 0, 0)),
                              ("lowerleg01.%s" % side, (m.radians(-38) * max(0.0, m.sin(ph * sgn + m.pi * 0.35)), 0, 0)),
                              ("upperarm01.%s" % side, (m.radians(-16) * s, 0, 0))):
                pb = rig.pose.bones.get(bone)
                if pb:
                    pb.rotation_mode = "XYZ"
                    pb.rotation_euler = rot
                    pb.keyframe_insert("rotation_euler", frame=f + 1)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = FRAMES + 1


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
            # The modelling pose bends the elbows forward: let the forearms hang.
            fa = rig.pose.bones.get("lowerarm01.%s" % side)
            if fa:
                fa.rotation_mode = "XYZ"
                fa.rotation_euler = (math.radians(float(os.environ.get("ELBOW", "-40"))), 0.0, 0.0)
        bpy.ops.object.mode_set(mode="OBJECT")
    if body is not None:
        b.hide_set(True)
    for img in bpy.data.images:
        if img.size[0] > TEX:
            img.scale(TEX, TEX * img.size[1] // max(img.size[0], 1))
    animated = os.environ.get("ANIM") == "1" and rig is not None
    if animated:
        keyframe_walk(rig)
    elif os.environ.get("WALK") == "1" and rig is not None:
        bake_walk(p["name"], rig, out_dir)
    print("PERSON", p["name"], p["skin"][0], p["hair"][0], [c[0] for c in p["clothes"]])
    out = os.path.join(out_dir, p["name"] + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=not animated,
                              export_animations=animated, export_skins=animated, export_morph=False,
                              use_visible=True, export_image_format="JPEG")
    print("EXPORTED", out)
