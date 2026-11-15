"""Clean a downloaded vehicle photo scan for the game (Blender bpy, headless).

usage: PYTHONPATH=/tmp/bpyenv python3 -P tools/vehicles/bake_vehicle.py IN.(glb|gltf) OUT.glb LENGTH_M [flip]

Writes one .glb holding three meshes, "ultra", "near" and "far" (the tiers
VehicleModels builds), each with its own texture size. Convention as in
VehicleModels: metres, y up, front bumper at z = 0, the body running +z,
centred on x, wheels on y = 0.

Steps, all automatic so ninety scans run unattended:
  1. join every part and apply transforms;
  2. cut the scanned ground (flat faces at the very bottom) and loose bits;
  3. lay the long axis along z; the end with red lamps in the photo is the
     rear (pass "flip" to override);
  4. scale to the real bumper-to-bumper length;
  5. add dark glass: photo scans leave windshields torn or see-through, so a
     closed shell just inside the greenhouse shows through every hole;
  6. vertex colours: alpha 0.4 for the scanned body ("fixed colour" in
     VehicleMaterial), 0.1 for the glass;
  7. decimate to each tier's budget and shrink its texture.
"""
import math, os, sys
import bpy, bmesh
import numpy as np
from mathutils import Matrix, Vector

BUDGET = {"ultra": 30000, "near": 6000, "far": 800}
TEX = {"ultra": 2048, "near": 1024, "far": 256}


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    # Parents (Sketchfab wraps everything in a rotated root) baked in first.
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    for o in list(bpy.data.objects):
        if o != ob:
            bpy.data.objects.remove(o)
    return ob


def verts(ob):
    a = np.empty(len(ob.data.vertices) * 3)
    ob.data.vertices.foreach_get("co", a)
    return a.reshape(-1, 3)


def drop_ground(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    zs = [v.co.z for v in bm.verts]
    lo, hi = min(zs), max(zs)
    cut = lo + (hi - lo) * 0.04
    kill = [f for f in bm.faces if all(v.co.z < cut for v in f.verts) and abs(f.normal.z) > 0.8]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    # Loose islands much smaller than the car (ground flecks, floating bits).
    bm.verts.ensure_lookup_table()
    seen, islands = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, isl = [v], []
        seen.add(v.index)
        while stack:
            u = stack.pop()
            isl.append(u)
            for e in u.link_edges:
                w = e.other_vert(u)
                if w.index not in seen:
                    seen.add(w.index)
                    stack.append(w)
        islands.append(isl)
    big = max(len(i) for i in islands)
    small = [v for i in islands if len(i) < big * 0.002 for v in i]
    bmesh.ops.delete(bm, geom=small, context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()


def _texture(ob):
    for m in ob.data.materials:
        if m and m.node_tree:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image:
                    return n.image
    return None


def _redness_by_end(ob, axis_len, lo, hi, h, z0):
    """Mean lamp-red of the photo near each end of the long (y) axis."""
    img = _texture(ob)
    if img is None:
        return 0.0, 0.0
    w, hgt = img.size
    px = np.empty(w * hgt * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(hgt, w, 4)
    me = ob.data
    uv = np.empty(len(me.loops) * 2)
    me.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    vi = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", vi)
    co = verts(ob)[vi]
    u = np.clip((uv[:, 0] % 1.0) * (w - 1), 0, w - 1).astype(int)
    v = np.clip((uv[:, 1] % 1.0) * (hgt - 1), 0, hgt - 1).astype(int)
    c = px[v, u]
    red = np.clip(c[:, 0] - np.maximum(c[:, 1], c[:, 2]) - 0.15, 0, 1)
    mid = (co[:, 2] - z0 > h * 0.35) & (co[:, 2] - z0 < h * 0.8)
    end = axis_len * 0.12
    a = red[mid & (co[:, 1] > hi - end)].mean() if np.any(mid & (co[:, 1] > hi - end)) else 0.0
    b = red[mid & (co[:, 1] < lo + end)].mean() if np.any(mid & (co[:, 1] < lo + end)) else 0.0
    return float(a), float(b)


def orient(ob, length, flip):
    p = verts(ob)
    if np.ptp(p[:, 0]) > np.ptp(p[:, 1]):
        ob.data.transform(Matrix.Rotation(math.radians(90), 4, "Z"))
    p = verts(ob)
    lo, hi = p.min(0), p.max(0)
    red_hi, red_lo = _redness_by_end(ob, hi[1] - lo[1], lo[1], hi[1], hi[2] - lo[2], lo[2])
    # Front goes to Blender +y (glTF z = 0); the red-lamp end to -y.
    if (red_hi > red_lo) != (flip == "flip"):
        ob.data.transform(Matrix.Rotation(math.radians(180), 4, "Z"))
    p = verts(ob)
    lo, hi = p.min(0), p.max(0)
    ob.data.transform(Matrix.Translation(Vector((-(lo[0] + hi[0]) / 2, -hi[1], -lo[2]))))
    ob.data.transform(Matrix.Scale(length / (hi[1] - lo[1]), 4))
    ob.data.update()
    return red_hi, red_lo


def glass_shell(ob):
    """A closed convex shell just inside the cabin: windows read as dark
    glass wherever the scan left holes."""
    p = verts(ob)
    h = p[:, 2].max()
    hw = np.ptp(p[:, 0]) / 2
    keep = p[(p[:, 2] > h * 0.68) & (np.abs(p[:, 0]) < hw * 0.82)]
    bm = bmesh.new()
    for q in keep[:: max(1, len(keep) // 4000)]:
        bm.verts.new(q)
    res = bmesh.ops.convex_hull(bm, input=bm.verts)
    junk = {g for g in res["geom_interior"] + res["geom_unused"] if isinstance(g, bmesh.types.BMVert)}
    bmesh.ops.delete(bm, geom=list(junk), context="VERTS")
    c = Vector((0, sum(v.co.y for v in bm.verts) / len(bm.verts), h * 0.68))
    for v in bm.verts:
        d = v.co - c
        v.co = c + Vector((d.x * 0.95, d.y * 0.97, d.z * 0.96))
    me = bpy.data.meshes.new("glass")
    bm.to_mesh(me)
    bm.free()
    g = bpy.data.objects.new("glass", me)
    bpy.context.scene.collection.objects.link(g)
    mat = bpy.data.materials.new("vehicle_glass")
    mat.diffuse_color = (0.02, 0.02, 0.025, 1)
    me.materials.append(mat)
    return g


def body_colour(ob):
    """The paint colour: median photo colour on the doors (side-facing,
    mid height). Stored in the vertex colour so the game can calm sky glare
    baked into roofs and hoods toward it."""
    img = _texture(ob)
    if img is None:
        return (0.5, 0.5, 0.5)
    w, hgt = img.size
    px = np.empty(w * hgt * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(hgt, w, 4)
    me = ob.data
    uv = np.empty(len(me.loops) * 2)
    me.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    vi = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", vi)
    nrm = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("normal", nrm)
    nrm = nrm.reshape(-1, 3)[vi]
    co = verts(ob)[vi]
    h = co[:, 2].max()
    pick = (np.abs(nrm[:, 0]) > 0.75) & (co[:, 2] > h * 0.4) & (co[:, 2] < h * 0.62)
    u = np.clip((uv[pick, 0] % 1.0) * (w - 1), 0, w - 1).astype(int)
    v = np.clip((uv[pick, 1] % 1.0) * (hgt - 1), 0, hgt - 1).astype(int)
    c = np.median(px[v, u, :3], axis=0) if len(u) else np.array([0.5, 0.5, 0.5])
    return tuple(float(x) for x in c)


def paint_code(ob, alpha, rgb=(1.0, 1.0, 1.0)):
    me = ob.data
    attr = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    data = np.tile([rgb[0], rgb[1], rgb[2], alpha], len(me.loops))
    attr.data.foreach_set("color_srgb", data)
    me.color_attributes.active_color = attr


def decimate(ob, faces):
    n = len(ob.data.polygons)
    if n > faces:
        m = ob.modifiers.new("dec", "DECIMATE")
        m.ratio = faces / n
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.ops.object.modifier_apply(modifier="dec")


def tier_copy(body, glass, tier):
    b = body.copy()
    b.data = body.data.copy()
    bpy.context.scene.collection.objects.link(b)
    decimate(b, BUDGET[tier])
    img = _texture(body)
    if img is not None:
        m = body.data.materials[0].copy()
        im = img.copy()
        im.name = "%s_%s" % (img.name.split(".")[0], tier)
        if im.size[0] > TEX[tier]:
            im.scale(TEX[tier], int(TEX[tier] * im.size[1] / im.size[0]))
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE":
                n.image = im
        b.data.materials.clear()
        b.data.materials.append(m)
    gl = glass.copy()
    gl.data = glass.data.copy()
    bpy.context.scene.collection.objects.link(gl)
    bpy.ops.object.select_all(action="DESELECT")
    b.select_set(True)
    gl.select_set(True)
    bpy.context.view_layer.objects.active = b
    bpy.ops.object.join()
    b.name = tier
    b.data.name = tier
    return b


def reencode_images(path):
    """Blender's JPEGs fail in Godot's libjpeg-turbo loader (ERR 43);
    write them again with Pillow, rebuilding the GLB's binary chunk."""
    import io, json, struct
    from PIL import Image
    b = open(path, "rb").read()
    jl = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    bin0 = 20 + jl + 8
    old = b[bin0:bin0 + struct.unpack("<I", b[20 + jl:24 + jl])[0]]
    swap = {}
    for im in j.get("images", []):
        bv = j["bufferViews"][im["bufferView"]]
        o = bv.get("byteOffset", 0)
        buf = io.BytesIO()
        Image.open(io.BytesIO(old[o:o + bv["byteLength"]])).convert("RGB").save(buf, "JPEG", quality=85)
        swap[im["bufferView"]] = buf.getvalue()
    new = bytearray()
    for i, bv in enumerate(j["bufferViews"]):
        o = bv.get("byteOffset", 0)
        data = swap.get(i, old[o:o + bv["byteLength"]])
        while len(new) % 4:
            new.append(0)
        bv["byteOffset"] = len(new)
        bv["byteLength"] = len(data)
        new += data
    while len(new) % 4:
        new.append(0)
    j["buffers"][0]["byteLength"] = len(new)
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(new))
    out += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(new), 0x004E4942) + bytes(new)
    open(path, "wb").write(out)


def main():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    src, out, length = a[0], a[1], float(a[2])
    flip = a[3] if len(a) > 3 else ""
    body = load(src)
    drop_ground(body)
    red = orient(body, length, flip)
    glass = glass_shell(body)
    paint = body_colour(body)
    paint_code(body, 0.4, paint)
    paint_code(glass, 0.1)
    tiers = [tier_copy(body, glass, t) for t in ("ultra", "near", "far")]
    for o in list(bpy.data.objects):
        if o not in tiers:
            bpy.data.objects.remove(o)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_image_format="JPEG",
                              export_jpeg_quality=85, export_vertex_color="ACTIVE",
                              export_all_vertex_colors=False)
    reencode_images(out)
    p = verts(tiers[0])
    print("paint", ["%.2f" % c for c in paint])
    print("baked %s: %s faces, %.2f x %.2f x %.2f m, lamp red front/back %.3f/%.3f, %d KB" % (
        os.path.basename(out), "/".join(str(len(t.data.polygons)) for t in tiers),
        np.ptp(p[:, 0]), np.ptp(p[:, 2]), np.ptp(p[:, 1]), red[0], red[1], os.path.getsize(out) // 1024))


main()
