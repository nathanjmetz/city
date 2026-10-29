class_name SignText
extends RefCounted
## Business names on real signs (Brawn): the lettering on a storefront's
## sign band, the board at the end of a farm lane, the gate sign of a
## quarry or oil lease. Text is a Label3D in the family's lettering style
## (assets/brand/fonts/signs), multichannel SDF so it stays crisp, and only
## drawn within DRAW_RANGE of the camera: past that a sign reads as a
## coloured panel anyway, the way it does from a few blocks off in a real
## town. One draw call per sign in range.
##
## A label is {pos, normal (facing out), text, height (letters at most this
## tall), width (and no wider), color, style}, in the frame of the node it
## goes on; and optionally range (metres it reads from, DRAW_RANGE if not given).

## Metres from the camera within which sign lettering is drawn, and over
## how many metres it fades out past that.
const DRAW_RANGE := 260.0
const FADE := 40.0

const FONTS := {
	"slab": "res://assets/brand/fonts/signs/AlfaSlabOne.woff",
	"serif": "res://assets/brand/fonts/signs/Bitter-Bold.woff",
	"condensed": "res://assets/brand/fonts/signs/Oswald-Bold.woff",
	"script": "res://assets/brand/fonts/signs/Yellowtail.woff",
	"franklin": "res://assets/brand/fonts/signs/LibreFranklin-Bold.woff",
}
## Font size the label is laid out at; pixel_size scales it into metres.
const SIZE := 64
## Real sign painters set these in capitals; script stays as written.
const CAPS := ["slab", "condensed", "franklin", "gothic"]

static var _fonts := {}


static func font(style: String) -> Font:
	if not _fonts.has(style):
		if not FONTS.has(style):
			_fonts[style] = Brand.sign(800)
		else:
			var f: FontFile = (load(FONTS[style]) as FontFile).duplicate()
			f.multichannel_signed_distance_field = true
			_fonts[style] = f
	return _fonts[style]


## Adds every label to `root` as a Label3D sized to fit its sign.
static func add(root: Node3D, labels: Array) -> void:
	for l in labels:
		root.add_child(make(l))


static func make(l: Dictionary) -> Label3D:
	var style := str(l.get("style", "gothic"))
	var text := str(l.text)
	if style in CAPS:
		text = text.to_upper()
	var f := font(style)
	var label := Label3D.new()
	label.text = text
	label.font = f
	label.font_size = SIZE
	label.outline_size = 0
	label.modulate = l.get("color", Color.WHITE)
	label.double_sided = false
	label.shaded = true
	label.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	var size := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE)
	# Cap height is about 0.7 of the line for these faces.
	var by_height := float(l.height) / maxf(size.y * 0.7, 1.0)
	var by_width := float(l.get("width", 1000.0)) / maxf(size.x, 1.0)
	label.pixel_size = minf(by_height, by_width)
	label.position = l.pos
	label.basis = Basis.looking_at(-l.normal, Vector3.UP)
	label.visibility_range_end = float(l.get("range", DRAW_RANGE))
	label.visibility_range_end_margin = FADE
	label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return label


## The labels for a sign panel centred at `c` (bottom edge middle), `w` wide
## and `h` tall, facing `normal`: the name, and under it "SINCE 2031" on a
## business old enough to brag about it.
static func on_panel(spec: Dictionary, c: Vector3, w: float, h: float, normal: Vector3) -> Array:
	var out := []
	var front := c + normal * 0.03
	var since := int(spec.get("since", -1))
	if since > 0:
		out.append({"pos": front + Vector3(0, h * 0.62, 0), "normal": normal, "text": spec.text, "height": h * 0.4,
			"width": w * 0.88, "color": spec.letter, "style": spec.style})
		out.append({"pos": front + Vector3(0, h * 0.2, 0), "normal": normal, "text": "SINCE %d" % since,
			"height": h * 0.13, "width": w * 0.5, "color": spec.letter, "style": "gothic"})
	else:
		out.append({"pos": front + Vector3(0, h * 0.5, 0), "normal": normal, "text": spec.text, "height": h * 0.58,
			"width": w * 0.88, "color": spec.letter, "style": spec.style})
	return out


## A roadside sign on two posts, the way a farm marks its lane or a company
## its gate: [mesh, labels], in a frame where the sign faces -z (toward the
## road) and stands on y = 0. Farm boards are about 1.5 m by 0.75 m on 4x4
## wood posts; company signs about 2.4 m by 1.2 m on steel.
static func roadside(spec: Dictionary, big := false) -> Array:
	var b := CommercialBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = hash(spec.text)
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 2.4 if big else 1.6
	var h := 1.2 if big else 0.8
	var y := 0.9 if big else 0.75
	var post := Color("#4a4c4f") if big else Color("#6b5038")
	for s in [-1.0, 1.0]:
		b._box("paint", Vector3(0.12, y + h + 0.1, 0.12), Vector3(s * (w * 0.5 - 0.15), (y + h + 0.1) * 0.5, 0.08), post)
	var panel: Color = spec.panel
	b._box("paint", Vector3(w, h, 0.06), Vector3(0, y + h * 0.5, 0), panel)
	b._box("paint", Vector3(w + 0.08, 0.06, 0.08), Vector3(0, y + h + 0.03, 0), panel.darkened(0.35))
	var normal := Vector3(0, 0, -1)
	return [b._commit_house(), on_panel(spec, Vector3(0, y, -0.03), w, h, normal)]


## Keeps a roadside sign at the road end of each business's lane, for the
## farm and industry views: refs maps a ref ("farm:3") to its lane (the
## lane's last point is on the road). Signs come and go with their business
## and are redrawn when its name or look changes.
static func sync_lanes(parent: Node3D, signs: Dictionary, sim, lanes: Dictionary, big: bool) -> void:
	for ref in signs.keys():
		if not lanes.has(ref) or signs[ref].get_meta("sign") != sim.families.sign_key(sim, ref):
			signs[ref].queue_free()
			signs.erase(ref)
	for ref in lanes:
		if signs.has(ref):
			continue
		var spec: Dictionary = sim.families.sign_of(sim, ref)
		var lane: Array = lanes[ref]
		if spec.is_empty() or lane.size() < 2:
			continue
		var node := lane_sign(spec, lane, big)
		node.set_meta("sign", sim.families.sign_key(sim, ref))
		parent.add_child(node)
		signs[ref] = node


## The sign by the road, set back past the sidewalk line and beside the
## lane, facing the road.
static func lane_sign(spec: Dictionary, lane: Array, big: bool) -> Node3D:
	var end: Vector3 = lane[lane.size() - 1]
	var into := Vector3(lane[lane.size() - 2] - end)
	into.y = 0.0
	into = into.normalized() if into.length() > 0.01 else Vector3.FORWARD
	var side := Vector3(-into.z, 0.0, into.x)
	var at := end + into * (RoadStyle.right_of_way_half() + 3.0) + side * (5.0 if big else 3.5)
	at.y = Terrain.ground_y(at.x, at.z)
	var built := roadside(spec, big)
	var node := Node3D.new()
	node.position = at
	node.basis = Basis.looking_at(-into, Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.mesh = built[0]
	node.add_child(mi)
	add(node, built[1])
	return node
