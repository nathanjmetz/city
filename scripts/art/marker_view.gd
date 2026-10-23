class_name MarkerView
extends Node3D
## Roadside historical markers (HistoricMarkers), drawn after the real ones:
##   - Indiana Historical Bureau state markers: a cast aluminium panel about
##     1.1 m wide and 1.2 m tall, dark blue with gold letters on both faces,
##     a crest on top, on a single post with the panel's bottom about 1.3 m
##     up. Title in capitals, a few lines of text, and "Indiana Historical
##     Bureau" with the year at the foot.
##   - Hoosier Homestead signs: smaller, white with green letters, at the end
##     of the farm lane.
##   - Historic district plaques: a bronze panel on a low post.
## Lettering is drawn within DRAW_RANGE (a marker is read on foot or from a
## slow car), the post and panel a bit farther. Rebuilt only when the
## markers change.

const DRAW_RANGE := 120.0
const LOOKS := {
	"state": {"panel": Color("#1d3463"), "ink": Color("#d9b24a"), "w": 1.1, "h": 1.2, "up": 1.3, "crest": true},
	"homestead": {"panel": Color("#f4f1e8"), "ink": Color("#1f6b3a"), "w": 0.9, "h": 0.6, "up": 1.1, "crest": false},
	"district": {"panel": Color("#6b4a2b"), "ink": Color("#e2c48a"), "w": 0.8, "h": 0.6, "up": 0.9, "crest": false},
}
const POST := Color("#2b2b2b")

var sim: CitySim
var _shown := -1


func setup(s: CitySim) -> void:
	sim = s
	sim.markers.changed.connect(_sync)
	_sync.call_deferred()


func _sync() -> void:
	if sim.markers.version == _shown:
		return
	_shown = sim.markers.version
	for c in get_children():
		c.queue_free()
	var was := Terrain.shift
	Terrain.shift = Terrain.shift_for(self)
	var town := _town_name("Our Town")
	for m in sim.markers.markers:
		add_child(_marker(m, town))
	Terrain.shift = was


func _marker(m: Dictionary, town: String) -> Node3D:
	var look: Dictionary = LOOKS.get(str(m.kind), LOOKS.state)
	var root := Node3D.new()
	var x := float(m.pos[0])
	var z := float(m.pos[1])
	root.position = Vector3(x, Terrain.ground_y(x, z), z)
	# The panel faces the street; the frame's -z is "toward the street".
	var face := Vector3(float(m.face[0]), 0.0, float(m.face[1]))
	if face.length() > 0.1:
		root.basis = Basis.looking_at(face.normalized(), Vector3.UP)
	var w := float(look.w)
	var h := float(look.h)
	var up := float(look.up)
	var b := CommercialBuilder.new()
	b.rng = RandomNumberGenerator.new()
	b._flat.begin(Mesh.PRIMITIVE_TRIANGLES)
	b._box("metal", Vector3(0.09, up + h * 0.5, 0.09), Vector3(0, (up + h * 0.5) * 0.5, 0), POST)
	b._box("paint", Vector3(w, h, 0.04), Vector3(0, up + h * 0.5, 0), look.panel)
	# A thin raised border, as cast markers have.
	for e in [[Vector3(w, 0.04, 0.05), Vector3(0, up + 0.02, 0)], [Vector3(w, 0.04, 0.05), Vector3(0, up + h - 0.02, 0)],
			[Vector3(0.04, h, 0.05), Vector3(-w * 0.5 + 0.02, up + h * 0.5, 0)],
			[Vector3(0.04, h, 0.05), Vector3(w * 0.5 - 0.02, up + h * 0.5, 0)]]:
		b._box("paint", e[0], e[1], look.ink)
	if look.crest:
		# The crest: a smaller arched piece with the state's name.
		b._box("paint", Vector3(w * 0.42, 0.2, 0.04), Vector3(0, up + h + 0.1, 0), look.panel)
		b._box("paint", Vector3(w * 0.22, 0.1, 0.04), Vector3(0, up + h + 0.25, 0), look.panel)
	var mi := MeshInstance3D.new()
	mi.mesh = b._commit_house()
	mi.visibility_range_end = DRAW_RANGE * 2.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var title := HistoricMarkers.filled(str(m.title), town).to_upper()
	var text := HistoricMarkers.filled(str(m.text), town)
	var foot := ("Indiana Historical Bureau, %d" % int(m.year)) if str(m.kind) == "state" \
		else ("Hoosier Homestead, %d" % int(m.year)) if str(m.kind) == "homestead" \
		else ("Local historic district, %d" % int(m.year))
	for side in [-1.0, 1.0]:
		var n := Vector3(0, 0, side)
		var at := n * 0.025
		if look.crest:
			root.add_child(_text("INDIANA", Vector3(0, up + h + 0.1, 0) + at, n, 0.07, w * 0.38, look.ink))
		root.add_child(_text(title, Vector3(0, up + h - 0.13, 0) + at, n, 0.075 * h / 1.2 + 0.02, w * 0.9, look.ink))
		root.add_child(_body(text, Vector3(0, up + h * 0.5, 0) + at, n, w * 0.86, h * 0.55, look.ink))
		root.add_child(_text(foot, Vector3(0, up + 0.08, 0) + at, n, 0.035, w * 0.8, look.ink))
	return root


static func _text(s: String, pos: Vector3, normal: Vector3, height: float, width: float, color: Color) -> Label3D:
	var l := SignText.make({"pos": pos, "normal": normal, "text": s, "height": height, "width": width,
		"color": color, "style": "franklin"})
	l.visibility_range_end = DRAW_RANGE
	return l


## A paragraph that wraps inside the panel.
static func _body(s: String, pos: Vector3, normal: Vector3, width: float, height: float, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = s
	l.font = SignText.font("serif")
	l.font_size = SignText.SIZE
	l.outline_size = 0
	l.modulate = color
	l.double_sided = false
	l.shaded = true
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Letters about 3 cm tall, smaller if it's a long story.
	var letter := clampf(height / maxf(3.0, ceilf(s.length() / 34.0)) * 0.55, 0.018, 0.034)
	l.pixel_size = letter / (SignText.SIZE * 0.7)
	l.width = width / l.pixel_size
	l.position = pos
	l.basis = Basis.looking_at(-normal, Vector3.UP)
	l.visibility_range_end = DRAW_RANGE
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return l


## The town's name (from the Session autoload, looked up at run time so
## tools that load this class before autoloads still compile).
func _town_name(fallback: String) -> String:
	var s := get_node_or_null("/root/Session")
	return str(s.current_name) if s != null and str(s.current_name) != "" else fallback
