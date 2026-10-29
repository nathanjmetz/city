class_name NearPeople
extends Node3D
## Ready-made people (MakeHuman, art/people/*.glb) for the town's walkers
## nearest the camera, on the desktop app only (Nathan, 2026-10-25: lean on
## ready-made art for the desktop download, keep the browser light). Each
## one plays its walk in step with the walker it stands in for; WalkerView
## skips those walkers. Farther off, and in the browser, the code-grown
## figures carry on as before.
##
## Each walker keeps one model, a man's or a woman's as their far figure
## is, and wears what that figure wears (WalkerView.dress): the model's top,
## bottoms and hair are recoloured to the person's own, keeping the cloth's
## folds and seams, so nobody changes clothes as the camera comes closer.
## In the cold months people get a model with long sleeves, and in short
## sleeves a long-sleeved outfit is cut to a T-shirt.

const FOLDER := "res://art/people"
const NEAR := 30.0        # metres (times GraphicsQuality.detail)
const MAX := 24           # at most this many at once
const WALK_SPEED := 1.4   # m/s the baked walk cycle is made for

## Each outfit's mean brightness of its top and bottoms (sRGB, from
## tools/people/make_masks.py, which draws art/people/masks), and whether it
## has long sleeves.
const SUITS := {
	"female_casualsuit01": {"top": 0.533, "bottoms": 0.513, "long": false},
	"female_elegantsuit01": {"top": 0.238, "bottoms": 0.286, "long": true},
	"male_casualsuit03": {"top": 0.193, "bottoms": 0.365, "long": true},
	"male_casualsuit05": {"top": 0.24, "bottoms": 0.364, "long": true},
	"male_worksuit01": {"top": 0.0, "bottoms": 0.53, "long": false, "rare": true},
}
## Each hair's mean brightness (sRGB), for recolouring it.
const HAIRS := {"long01": 0.131, "bob02": 0.595, "ponytail01": 0.253, "braid01": 0.08, "short02": 0.248,
	"short03": 0.227, "bob01": 0.5, "short01": 0.25, "short04": 0.25}
## WalkerView's shader colours (linear), by outfit index.
const BOTTOMS := [Color(0.2, 0.22, 0.3), Color(0.022, 0.036, 0.089), Color(0.073, 0.133, 0.274),
	Color(0.234, 0.342, 0.508), Color(0.013, 0.013, 0.014), Color(0.54, 0.434, 0.243), Color(0.069, 0.069, 0.072),
	Color(0.133, 0.147, 0.073)]
const HAIR_COLOURS := [Color(0.16, 0.11, 0.07), Color(0.01, 0.009, 0.008), Color(0.45, 0.3, 0.133), Color(0.48, 0.46, 0.43)]
## School backpacks, linear, as the walkers' shader colours them
## (WalkerView HATS * 1.4 + 0.02), so a child's pack is the same near and far.
const PACK_COLOURS := [Color(0.034, 0.034, 0.035), Color(0.258, 0.258, 0.272), Color(0.048, 0.062, 0.146),
	Color(0.65, 0.038, 0.038), Color(1.0, 0.206, 0.02), Color(0.258, 0.038, 0.051), Color(1.0, 0.986, 0.776),
	Color(0.188, 0.206, 0.11)]

const CLOTH_SHADER := """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D mask_tex : filter_linear;
uniform bool body = false;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;
uniform bool hair = false;
uniform float top_mean = 0.3;
uniform float bottom_mean = 0.3;
instance uniform vec4 top_col = vec4(0.0);
instance uniform vec4 bottom_col = vec4(0.0);
void vertex() {
	// The body is drawn whole under the clothes, which hug it closely, so
	// it pokes through as they move: below the collar it's drawn a little
	// thinner. Face and hands are left as they are.
	if (body) {
		VERTEX -= NORMAL * 0.012 * (1.0 - smoothstep(1.22, 1.32, VERTEX.y));
	}
}
void fragment() {
	vec4 t = texture(albedo_tex, UV);
	vec3 c = t.rgb;
	// Recolour by brightness against the part's mean, so the folds, seams
	// and stripes stay; alpha 0 in a colour leaves that part as made.
	float l = dot(t.rgb, vec3(0.3, 0.59, 0.11));
	if (hair) {
		if (top_col.a > 0.5) {
			c = top_col.rgb * clamp(l / top_mean, 0.0, 3.0);
		}
		ALPHA = t.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	} else {
		vec3 m = texture(mask_tex, UV).rgb;
		if (top_col.a > 0.5 && m.r > 0.5) {
			c = top_col.rgb * clamp(l / top_mean, 0.0, 2.5);
		} else if (bottom_col.a > 0.5 && m.g > 0.5) {
			c = bottom_col.rgb * clamp(l / bottom_mean, 0.0, 2.5);
		}
	}
	ALBEDO = c;
	ROUGHNESS = 0.85;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
"""

## Walker ids drawn here this frame (WalkerView leaves them out).
static var drawn := {}

var traffic: TrafficSim
var tick_fraction: Callable
## [{scene, female, long, suit (MeshInstance3D name), hair}] per model.
var _models := []
var _pools := {}          # model * 2 + short sleeves -> [{node, player, walker, suit, hair}]
var _short := {}          # model index -> its outfit's mesh cut to short sleeves
var _shader: Shader
var _materials := {}      # texture path -> ShaderMaterial


## Whether ready-made people can be drawn here: the desktop app, with the
## art present (the browser export leaves art/people out).
static func available() -> bool:
	return not OS.has_feature("web") and DirAccess.dir_exists_absolute(FOLDER)


func setup(t: TrafficSim, frac: Callable) -> void:
	traffic = t
	tick_fraction = frac
	_shader = Shader.new()
	_shader.code = CLOTH_SHADER
	var files := DirAccess.get_files_at(FOLDER)
	files.sort()
	for f in files:
		if not f.ends_with(".glb"):
			continue
		var s := load(FOLDER + "/" + f) as PackedScene
		if s == null:
			continue
		# What it wears, from its parts' names (Human_female_casualsuit01).
		var probe := s.instantiate()
		var suit := ""
		var top := 0.0  # the top of its head, hair and all
		for mi in probe.find_children("*", "MeshInstance3D", true, false):
			var n := String(mi.name).trim_prefix("Human_")
			if SUITS.has(n):
				suit = n
			var xf: Transform3D = mi.transform
			var up: Node = mi.get_parent()
			while up != null and up != probe:
				if up is Node3D:
					xf = (up as Node3D).transform * xf
				up = up.get_parent()
			top = maxf(top, (xf * (mi as MeshInstance3D).get_aabb()).end.y)
		probe.free()
		_models.append({"scene": s, "female": suit.begins_with("female"), "long": SUITS.get(suit, {}).get("long", true),
			"rare": SUITS.get(suit, {}).get("rare", false), "overalls": suit == "male_worksuit01",
			"height": top if top > 1.0 else 1.7})


## The model a person is drawn with: one of their figure's (WalkerView.figure:
## 1 is a woman's), with long sleeves when they're in them, the same each
## time.
func _model_for(person: int, outfit: int, who := {}) -> int:
	var female := WalkerView.figure(person, who) == 1
	var long := outfit & 8 != 0
	var picks := []
	for pass_ in 3:
		for i in _models.size():
			var m: Dictionary = _models[i]
			if (pass_ >= 2 or m.female == female) and (pass_ >= 1 or not long or m.long):
				# Bib overalls are a farmer's, now and then in town: a fifth
				# as likely as the rest.
				for k in (1 if m.rare else 5):
					picks.append(i)
		if not picks.is_empty():
			break
	return int(picks[(hash([person, "model"]) >> 2) % picks.size()])


func _take(model: int, short := false) -> Dictionary:
	var key := model * 2 + int(short)
	var pool: Array = _pools.get(key, [])
	_pools[key] = pool
	for e in pool:
		if int(e.walker) == -1:
			return e
	var node := (_models[model].scene as PackedScene).instantiate() as Node3D
	add_child(node)
	var players := node.find_children("*", "AnimationPlayer", true, false)
	var player: AnimationPlayer = players[0] if not players.is_empty() else null
	if player != null and not player.get_animation_list().is_empty():
		var anim := player.get_animation(player.get_animation_list()[0])
		anim.loop_mode = Animation.LOOP_LINEAR
		player.play(player.get_animation_list()[0])
	var e := {"node": node, "player": player, "walker": -1, "suit": null, "hair": null, "overalls": _models[model].overalls}
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var n := String(mi.name).trim_prefix("Human_")
		if SUITS.has(n):
			e.suit = mi
			mi.material_override = _material(mi, SUITS[n], false)
			if short:
				if not _short.has(model):
					_short[model] = _cut_sleeves(mi)
				mi.mesh = _short[model]
		elif n.ends_with("_generic"):
			mi.material_override = _material(mi, {"top": 1.0, "bottoms": 1.0}, false, true)
		elif HAIRS.has(n):
			e.hair = mi
			mi.material_override = _material(mi, {"top": HAIRS[n], "bottoms": 1.0}, true)
	e.pack = _backpack(node)
	pool.append(e)
	return e


## A school backpack on the model's back, riding on the spine, hidden until
## a child on the school walk wears it.
func _backpack(node: Node3D) -> MeshInstance3D:
	var sks := node.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return null
	var sk: Skeleton3D = sks[0]
	var bone := sk.find_bone("spine02")
	if bone < 0:
		return null
	var at := BoneAttachment3D.new()
	at.bone_name = "spine02"
	sk.add_child(at)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.27, 0.32, 0.13)
	box.mesh = bm
	box.material_override = StandardMaterial3D.new()
	(box.material_override as StandardMaterial3D).roughness = 0.85
	# The model faces +Z, so its back is -Z: set out behind the spine, in
	# the bone's own frame.
	var rest := sk.get_bone_global_rest(bone)
	box.transform = Transform3D(rest.basis.inverse(), rest.basis.inverse() * Vector3(0.0, -0.02, -0.15))
	box.visible = false
	at.add_child(box)
	return box


## Bones whose part of a sleeve a short-sleeved shirt leaves bare: the
## lower upper arm, the forearm and the hand.
const BARE_BONES := ["upperarm02", "lowerarm01", "lowerarm02", "wrist", "finger", "metacarpal", "thumb"]


## The outfit's mesh with its sleeves cut to short ones: every triangle of
## the top that rides mostly on the lower arm goes, and the arm under it
## shows (the body is whole under the clothes). The models are all made
## with long sleeves or none; summer wants a T-shirt.
static func _cut_sleeves(mi: MeshInstance3D) -> Mesh:
	var src: Mesh = mi.mesh
	var a: Array = src.surface_get_arrays(0)
	var bare := {}
	if mi.skin != null:
		for i in mi.skin.get_bind_count():
			var name := String(mi.skin.get_bind_name(i)).to_lower()
			for b in BARE_BONES:
				if name.begins_with(b):
					bare[i] = true
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var per := bones.size() / maxi(verts.size(), 1)
	var on_arm := PackedByteArray()
	on_arm.resize(verts.size())
	for v in verts.size():
		var w := 0.0
		for k in per:
			if bare.has(bones[v * per + k]):
				w += weights[v * per + k]
		on_arm[v] = 1 if w > 0.5 else 0
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var kept := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if on_arm[idx[t]] + on_arm[idx[t + 1]] + on_arm[idx[t + 2]] >= 2:
			continue
		kept.append_array([idx[t], idx[t + 1], idx[t + 2]])
	a[Mesh.ARRAY_INDEX] = kept
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, src.surface_get_format(0) & ~Mesh.ARRAY_FORMAT_INDEX | Mesh.ARRAY_FORMAT_INDEX)
	out.surface_set_material(0, src.surface_get_material(0))
	return out


## The recolouring material for a part, made once for each texture.
func _material(mi: MeshInstance3D, means: Dictionary, hair: bool, body := false) -> Material:
	var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
	if src == null or src.albedo_texture == null:
		return null
	var key := src.albedo_texture.resource_path
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("albedo_tex", src.albedo_texture)
	m.set_shader_parameter("hair", hair)
	m.set_shader_parameter("body", body)
	# The means are sRGB; the texture reads linear.
	m.set_shader_parameter("top_mean", maxf(pow(float(means.top), 2.2), 0.001))
	m.set_shader_parameter("bottom_mean", maxf(pow(float(means.bottoms), 2.2), 0.001))
	if src.normal_enabled and src.normal_texture != null:
		m.set_shader_parameter("normal_tex", src.normal_texture)
		m.set_shader_parameter("has_normal", true)
	if not hair and not body:
		var suit := String(mi.name).trim_prefix("Human_")
		var mask := FOLDER + "/masks/" + suit + ".png"
		if ResourceLoader.exists(mask):
			m.set_shader_parameter("mask_tex", load(mask))
	_materials[key] = m
	return m


## Puts the person's own clothes and hair on a model.
static func _wear(e: Dictionary, worn: Array) -> void:
	var o := int(worn[1])
	if e.get("overalls", false):
		o = (o & ~7) | (1 + (o & 7) % 3)  # overalls come in denim
	var top: Color = worn[0]
	if e.suit != null:
		var mi: MeshInstance3D = e.suit
		mi.set_instance_shader_parameter("top_col", Color(top, 1.0))
		mi.set_instance_shader_parameter("bottom_col", Color(BOTTOMS[o & 7], 1.0))
	if e.hair != null:
		(e.hair as MeshInstance3D).set_instance_shader_parameter("top_col", Color(HAIR_COLOURS[(o >> 9) & 3], 1.0))


func _process(_delta: float) -> void:
	drawn.clear()
	if traffic == null or _models.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	Terrain.shift = Terrain.shift_for(self)
	var eye := cam.global_position
	var reach := NEAR * GraphicsQuality.detail
	var frac: float = tick_fraction.call()
	var month := WalkerView.month_of(traffic)
	var near := []
	for w in traffic.walkers:
		var pose := traffic.walker_pose(w, frac)
		var p: Vector3 = Terrain.stand(pose[0])
		var d := p.distance_to(eye)
		if d < reach:
			near.append([d, w, pose, p])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var n := mini(near.size(), MAX)
	var keep := {}
	for i in n:
		keep[int(near[i][1].id)] = true
	# Models whose walker has gone out of reach are free again.
	for model in _pools:
		for e in _pools[model]:
			if int(e.walker) != -1 and not keep.has(int(e.walker)):
				e.walker = -1
				(e.node as Node3D).visible = false
	for i in n:
		var w: Dictionary = near[i][1]
		var pose: Array = near[i][2]
		var p: Vector3 = near[i][3]
		var person := int(w.person)
		var who: Dictionary = traffic._sim.people.people.get(person, {}) if traffic._sim != null else {}
		var worn := WalkerView.dress(person, month, int(who.get("age", -1)))
		var model := _model_for(person, int(worn[1]), who)
		# A long-sleeved outfit is cut to a T-shirt for someone in short
		# sleeves.
		var short: bool = int(worn[1]) & 8 == 0 and _models[model].long
		# The same walker keeps the same person while it stays near.
		var e: Dictionary = {}
		for k in _pools.get(model * 2 + int(short), []):
			if int(k.walker) == int(w.id):
				e = k
				break
		if e.is_empty():
			e = _take(model, short)
			e.walker = int(w.id)
			_wear(e, worn)
		if e.get("pack") != null:
			var age := int(who.get("age", -1))
			(e.pack as MeshInstance3D).visible = age >= 5 and age <= 11
			((e.pack as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = \
				(PACK_COLOURS[(int(worn[1]) >> 6) & 7] as Color).linear_to_srgb()
		var dir: Vector3 = pose[1]
		if dir.length() < 0.5:
			dir = Vector3.FORWARD
		var node: Node3D = e.node
		node.visible = true
		# The model faces +Z; turn it to walk along `dir`. Sized to the
		# person's own height (WalkerView.build), so a child walking to school
		# is a child's size close up too, and takes quicker, shorter steps.
		var size: float = WalkerView.build(person, who).y * 1.7 / float(_models[model].height)
		node.global_transform = Transform3D(Basis.looking_at(-Vector3(dir.x, 0.0, dir.z).normalized(), Vector3.UP).scaled(Vector3.ONE * size), p)
		if e.player != null:
			e.player.speed_scale = float(w.get("v", WALK_SPEED)) / WALK_SPEED / size
		drawn[int(w.id)] = true
	Terrain.shift = Vector2.ZERO
