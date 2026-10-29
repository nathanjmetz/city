class_name WalkerView
extends Node3D
## Draws people out walking: on the sidewalk, crossing at corners, from the
## car to the door. Everyone is simulated; only those near the camera are
## drawn, like Cities: Skylines' pedestrians. Legs and arms swing in the
## vertex shader, in step with the distance walked, so feet don't slide.

## Metres from the camera beyond which walkers aren't drawn on a full
## desktop; the graphics tier sets its own (people_m), and a most-at-once
## (people) that pulls the reach in on a crowded street.
const FAR := 320.0
## Metres a person covers in one full walk cycle (two steps). A typical adult
## step is about 0.7 m at 1.3-1.4 m/s (Fruin, Pedestrian Planning and Design).
const STRIDE := 1.4
## Metres (times GraphicsQuality.detail) out to which people are drawn at
## each detail, closest first: faces and smooth bodies within the first two,
## then simpler and simpler; past the last, the simplest.
const REACH := [15.0, 40.0, 90.0, 180.0]
const SHIRTS := [Color(0.62, 0.16, 0.14), Color(0.16, 0.3, 0.55), Color(0.85, 0.82, 0.74),
	Color(0.24, 0.42, 0.26), Color(0.9, 0.62, 0.2), Color(0.35, 0.35, 0.38), Color(0.55, 0.38, 0.6),
	Color(0.12, 0.12, 0.14), Color(0.7, 0.75, 0.82), Color(0.78, 0.45, 0.42),
	Color(0.95, 0.95, 0.93), Color(0.2, 0.55, 0.62), Color(0.82, 0.74, 0.3), Color(0.45, 0.28, 0.18),
	Color(0.9, 0.5, 0.62), Color(0.3, 0.2, 0.42), Color(0.5, 0.6, 0.35), Color(0.75, 0.2, 0.3)]

var traffic: TrafficSim
var tick_fraction: Callable
var _mm: MultiMesh
## How far walkers are drawn now (GraphicsQuality.fit_reach).
var _reach := FAR
## The second figure: narrower shoulders, wider hips, longer hair.
var _mm2: MultiMesh
## Every figure at every detail: index figure * 5 + detail (0 farthest to
## 4 closest).
var _mms := []
## The instance drawing each of _mms, for turning shadows on and off.
var _insts := []
## Person -> [top, outfit, month] (dress), kept while the month holds.
var _worn := {}
const _NONE := [Color.WHITE, 0, -1]


func setup(t: TrafficSim, fraction: Callable) -> void:
	traffic = t
	tick_fraction = fraction


func _ready() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	# White instance colours: the browser's renderer multiplies vertex COLOR
	# by the instance colour even without use_colors, and that is black.
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = _person_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	# The shirt (vertex alpha 0) takes each person's own colour. Each limb
	# swings about its hip or shoulder (UV.y) one way or the other (UV.x),
	# by the walk phase in the instance's custom alpha. The body dips as the
	# legs spread, so the feet stay on the ground.
	mat.shader.code = """shader_type spatial;
render_mode cull_disabled;
varying vec3 tint;
// The Compatibility renderer (the browser) hands INSTANCE_CUSTOM's rgb
// over as if it were an sRGB colour, already turned linear (alpha comes
// through as is); undo that so custom data reads as on the desktop.
vec4 custom_data(vec4 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	c.rgb = mix(c.rgb * 12.92, 1.055 * pow(max(c.rgb, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c.rgb));
#endif
	return c;
}
// What each person has on (WalkerView.dress): bottoms and hat colours.
// Linear colours (the custom tint goes straight into ALBEDO); index 0 is
// the old plain trousers and hair, which the browser keeps.
const vec3 BOTTOMS[8] = vec3[](vec3(0.2, 0.22, 0.3), vec3(0.022, 0.036, 0.089), vec3(0.073, 0.133, 0.274),
	vec3(0.234, 0.342, 0.508), vec3(0.013, 0.013, 0.014), vec3(0.54, 0.434, 0.243), vec3(0.069, 0.069, 0.072), vec3(0.133, 0.147, 0.073));
const vec3 HATS[8] = vec3[](vec3(0.01, 0.01, 0.011), vec3(0.17, 0.17, 0.18), vec3(0.02, 0.03, 0.09),
	vec3(0.45, 0.013, 0.013), vec3(1.0, 0.133, 0.0), vec3(0.17, 0.013, 0.022), vec3(0.75, 0.69, 0.54), vec3(0.12, 0.133, 0.064));
const vec3 HAIRS[4] = vec3[](vec3(0.16, 0.11, 0.07), vec3(0.01, 0.009, 0.008), vec3(0.45, 0.3, 0.133), vec3(0.48, 0.46, 0.43));
const vec3 SKIN = vec3(0.66, 0.47, 0.36);
void vertex() {
	vec4 custom = custom_data(INSTANCE_CUSTOM);
	// Vertex alpha says which part this is: 0 the top (the person's own
	// colour), 0.25 a forearm (skin or sleeve), 0.5 trousers above the knee
	// (0.56 round the hips, where a coat comes down to),
	// 0.75 below it (or bare legs in shorts), 0.9 hair (or a hat), 0.97
	// hair a hat leaves showing, 1 as is.
	float part = COLOR.a;
	tint = part < 0.1 ? custom.rgb : COLOR.rgb;
	float worn = 0.0;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	worn = floor(custom.a + 0.0005);
#endif
	int o = int(worn);
	vec3 bottoms = BOTTOMS[o & 7];
	// A winter coat stands a little off the body and hangs past the waist.
	bool coat = (o & 2048) != 0;
	bool hips = part > 0.53 && part < 0.6;
	if (coat && (part < 0.35 || hips)) {
		VERTEX.xz *= 1.1;
	}
	if (part > 0.15 && part < 0.35 && (o & 8) != 0) {
		tint = custom.rgb;
	} else if (coat && hips) {
		tint = custom.rgb;
	} else if (part > 0.4 && part < 0.6) {
		tint = bottoms * COLOR.rgb;
	} else if (part > 0.65 && part < 0.82 && (o & 16) == 0) {
		tint = bottoms * COLOR.rgb / SKIN;
	} else if (part > 0.85 && part < 0.93 && (o & 32) != 0) {
		tint = HATS[(o >> 6) & 7];
	} else if (part > 0.85 && part < 0.99) {
		tint = HAIRS[(o >> 9) & 3];
	}
	// A school backpack (0.62), folded away inside the body unless worn.
	if (part > 0.6 && part < 0.65) {
		if ((o & 8192) != 0) {
			tint = HATS[(o >> 6) & 7] * 1.4 + vec3(0.02);
		} else {
			VERTEX = vec3(0.0, 1.2, 0.0);
		}
	}
	float ph = (custom.a - worn) * 6.2831853;
	float a = UV.x * 0.42 * sin(ph);
	float c = cos(a);
	float s = sin(a);
	float y = VERTEX.y - UV.y;
	VERTEX.yz = vec2(UV.y + y * c - VERTEX.z * s, y * s + VERTEX.z * c);
	NORMAL.yz = vec2(NORMAL.y * c - NORMAL.z * s, NORMAL.y * s + NORMAL.z * c);
	VERTEX.y -= 0.84 * (1.0 - cos(0.42 * sin(ph)));  // keeps the feet on the ground
	// Seated (on a porch chair, a bench, at a bus stop's bench): thighs out
	// level in front, shins straight down from the knee, hands in the lap,
	// the hips down at seat height (about 0.45 m).
	if ((o & 4096) != 0) {
		const float HIP = 0.88;
		const float KNEE = 0.47;
		if (UV.x != 0.0 && UV.y > 0.8 && UV.y < 0.95) {
			if (VERTEX.y >= KNEE) {
				VERTEX.yz = vec2(HIP - VERTEX.z, VERTEX.y - HIP);
				NORMAL.yz = vec2(-NORMAL.z, NORMAL.y);
			} else {
				VERTEX.y += HIP - KNEE;
				VERTEX.z -= HIP - KNEE;
			}
		} else if (UV.x != 0.0) {
			float la = 0.45;
			float ly = VERTEX.y - UV.y;
			VERTEX.yz = vec2(UV.y + ly * cos(la) - VERTEX.z * sin(la), ly * sin(la) + VERTEX.z * cos(la));
		}
		VERTEX.y -= HIP - KNEE;
	}
}
void fragment() { ALBEDO = tint; ROUGHNESS = 0.9; }
"""
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_mm2 = MultiMesh.new()
	_mm2.transform_format = MultiMesh.TRANSFORM_3D
	_mm2.use_colors = true
	_mm2.use_custom_data = true
	_mm2.mesh = _person_mesh(1)
	var mi2 := MultiMeshInstance3D.new()
	mi2.multimesh = _mm2
	mi2.material_override = mat
	mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi2)
	for kind in 2:
		for lod in 5:
			if lod == 2:
				_mms.append(_mm if kind == 0 else _mm2)
				_insts.append(mi if kind == 0 else mi2)
				continue
			var m := MultiMesh.new()
			m.transform_format = MultiMesh.TRANSFORM_3D
			m.use_colors = true
			m.use_custom_data = true
			m.mesh = _person_mesh(kind, lod)
			var inst := MultiMeshInstance3D.new()
			inst.multimesh = m
			inst.material_override = mat
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(inst)
			_mms.append(m)
			_insts.append(inst)


func _process(_delta: float) -> void:
	# Neighbors' cities are drawn moved over to their place on the land.
	Terrain.shift = Terrain.shift_for(self)
	_draw_walkers()
	Terrain.shift = Vector2.ZERO


func _draw_walkers() -> void:
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3.ZERO
	var frac: float = tick_fraction.call()
	var full := float(GraphicsQuality.knob("people_m", FAR))
	_reach = minf(_reach, full)
	var counts := []
	counts.resize(mms_count())
	counts.fill(0)
	var mms := _mms
	var people: Dictionary = traffic._sim.people.people if traffic._sim != null else {}
	# How far each detail reaches grows with what the machine can draw
	# (GraphicsQuality.detail): faces and smooth bodies close up, simple
	# figures far off, sooner in the browser.
	var reach: Array = []
	for r in REACH:
		reach.append(float(r) * GraphicsQuality.detail)
	# Clothes for the month the town shows (July while seasons are off);
	# the browser's renderer keeps everyone in the plain outfit.
	var month := month_of(traffic)
	var desktop := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	for w in traffic.walkers:
		var pose := traffic.walker_pose(w, frac)
		var p: Vector3 = Terrain.stand(pose[0])
		if p.distance_to(eye) > _reach:
			continue
		if NearPeople.drawn.has(int(w.id)):
			continue  # a ready-made person stands in for this one up close
		var d := p.distance_to(eye)
		var lod := 0
		for r in reach.size():
			if d < float(reach[r]):
				lod = 4 - r
				break
		var who: Dictionary = people.get(int(w.person), {})
		var kind := figure(int(w.person), who) * 5 + lod
		var mm: MultiMesh = mms[kind]
		var n: int = counts[kind]
		if n >= mm.instance_count:
			mm.instance_count = maxi(n * 2, 64)
		var dir: Vector3 = pose[1]
		if dir.length() < 0.5:
			dir = Vector3.FORWARD
		var body := build(int(w.person), who)
		mm.set_instance_transform(n, Transform3D(Basis.looking_at(Vector3(dir.x, 0.0, dir.z).normalized(), Vector3.UP).scaled(body), p))
		mm.set_instance_color(n, skin_tone(int(w.person)))
		# Standing at the kerb, the phase stays put: feet together if it's 0.
		var worn: Array = _worn.get(int(w.person), _NONE)
		if worn[2] != month:
			worn = dress(int(w.person), month, _age(int(w.person)))
			worn.append(month)
			if _worn.size() > 50000:
				_worn.clear()
			_worn[int(w.person)] = worn
		var shirt: Color = worn[0]
		# Stride grows with height (about 0.41 of it in a walk), and each
		# person's own gait a little longer or shorter, so a crowd doesn't
		# step in time.
		var stride: float = STRIDE * body.y * (0.92 + float((hash(int(w.person)) >> 12) & 15) / 15.0 * 0.16)
		shirt.a = fposmod(float(pose[2]), stride) / stride
		if desktop:
			var age := int(who.get("age", -1))
			shirt.a = minf(shirt.a, 0.999) + float(int(worn[1]) | (BACKPACK if age >= 5 and age <= 11 else 0))
		mm.set_instance_custom_data(n, shirt)
		counts[kind] = n + 1
	# On a full desktop (High and up) the nearer figures cast a shadow, as
	# people on a sunny sidewalk do: from above, the shadow reads as much
	# as the person. The far, simplest figures and the browser go without.
	var shade: bool = bool(GraphicsQuality.knob("photo", false)) and not OS.has_feature("web")
	for i in _insts.size():
		(_insts[i] as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
			if shade and i % 5 >= 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var total := 0
	for i in mms.size():
		(mms[i] as MultiMesh).visible_instance_count = counts[i]
		total += int(counts[i])
	_reach = GraphicsQuality.fit_reach(_reach, total, int(GraphicsQuality.knob("people", GraphicsQuality.NO_CAP)), full)


## Tops in the colours a Midwestern crowd wears (sRGB, as picked from
## street photos): mostly white, greys, black and navy, then blues, reds,
## greens and earth tones, a few brights.
const TOPS := [Color(0.92, 0.92, 0.9), Color(0.92, 0.92, 0.9), Color(0.62, 0.62, 0.62), Color(0.62, 0.62, 0.62),
	Color(0.3, 0.3, 0.31), Color(0.12, 0.12, 0.13), Color(0.12, 0.12, 0.13), Color(0.15, 0.2, 0.33),
	Color(0.15, 0.2, 0.33), Color(0.2, 0.33, 0.62), Color(0.6, 0.7, 0.82), Color(0.48, 0.13, 0.17),
	Color(0.72, 0.15, 0.15), Color(0.18, 0.33, 0.23), Color(0.42, 0.43, 0.3), Color(0.72, 0.62, 0.47),
	Color(0.42, 0.3, 0.22), Color(0.81, 0.73, 0.57), Color(0.85, 0.6, 0.65), Color(0.38, 0.28, 0.5),
	Color(0.2, 0.45, 0.48), Color(0.85, 0.45, 0.2), Color(0.6, 0.18, 0.15), Color(0.88, 0.85, 0.76)]
## Coats for the cold months, as worn in north-central Indiana: mostly dark
## parkas and puffers, brown duck work coats, some red, royal blue and tan.
const COATS := [Color(0.1, 0.1, 0.11), Color(0.14, 0.17, 0.28), Color(0.28, 0.28, 0.29), Color(0.33, 0.35, 0.26),
	Color(0.6, 0.45, 0.27), Color(0.4, 0.12, 0.15), Color(0.65, 0.13, 0.13), Color(0.18, 0.3, 0.6),
	Color(0.7, 0.62, 0.48), Color(0.1, 0.1, 0.11), Color(0.28, 0.28, 0.29)]
## The share of people in a coat, in long sleeves, in shorts and in a hat
## each month (January first), from Marion's normal daily highs (NOAA
## 1991-2020: about 33°F in January to 84°F in July): coats below about
## 45°F, shorts above about 75°F (and the one hardy soul in January), knit
## hats in deep winter and ball caps in summer.
const COAT_SHARE := [0.92, 0.88, 0.6, 0.25, 0.05, 0.0, 0.0, 0.0, 0.04, 0.22, 0.6, 0.9]
const SLEEVE_SHARE := [1.0, 1.0, 0.85, 0.6, 0.3, 0.12, 0.08, 0.1, 0.25, 0.6, 0.9, 1.0]
const SHORTS_SHARE := [0.02, 0.02, 0.04, 0.1, 0.3, 0.5, 0.55, 0.5, 0.3, 0.08, 0.03, 0.02]
const HAT_SHARE := [0.45, 0.4, 0.15, 0.08, 0.1, 0.14, 0.15, 0.14, 0.1, 0.08, 0.15, 0.4]
## Bottoms, by the shader's BOTTOMS: navy, dark, mid and light denim,
## black, khaki, charcoal, olive. Blue jeans most of all (the old navy
## stays the browser's).
const BOTTOM_WEIGHTS := [0, 30, 25, 9, 13, 12, 7, 4]


## What a person has on this month, the same whenever they're seen: their
## top (or coat) colour and the shader's outfit bits (bottoms 0-2, long
## sleeves 3, shorts 4, hat 5, hat colour 6-8, hair colour 9-10, coat 11). Each
## person feels the cold their own way, so coats come out a few at a time
## as fall turns.
static func dress(person: int, month: int, age := -1) -> Array:
	var m := clampi(month, 1, 12) - 1
	var cold := float(hash([person, "cold"]) & 1023) / 1024.0
	var top: Color = TOPS[(hash(person) >> 4) % TOPS.size()]
	var o := 0
	var roll := (hash([person, "bottoms"]) & 0xffff) % 100
	for i in BOTTOM_WEIGHTS.size():
		roll -= int(BOTTOM_WEIGHTS[i])
		if roll < 0:
			o = i
			break
	if cold < float(COAT_SHARE[m]):
		top = COATS[(hash([person, "coat"]) >> 3) % COATS.size()]
		o |= 8 | 2048
	elif cold < float(SLEEVE_SHARE[m]):
		o |= 8
	if 1.0 - cold < float(SHORTS_SHARE[m]):
		o |= 16
	var hat := float(hash([person, "hat"]) & 1023) / 1024.0
	if hat < float(HAT_SHARE[m]):
		# Knit hats in black, grey, navy, red, blaze orange, maroon and cream;
		# caps in summer mostly navy, red, khaki-ish cream and olive.
		var winter := m <= 2 or m >= 10
		var colours := [0, 1, 2, 3, 4, 5, 6, 0] if winter else [2, 3, 6, 7, 0, 2]
		o |= 32 | int(colours[(hash([person, "hat colour"]) >> 2) % colours.size()]) << 6
	var hr := (hash([person, "hair"]) & 0xffff) % 100
	var hair := 0 if hr < 50 else (1 if hr < 68 else 2)
	if age >= 55 and (hash([person, "grey"]) & 0xff) % 100 < clampi((age - 45) * 3, 0, 90):
		hair = 3
	o |= hair << 9
	return [top.srgb_to_linear(), o]


## Skin tones as a tint on the figure (it darkens or lightens the skin; the
## clothes a touch with it), weighted roughly like Grant County, Indiana
## (Census 2020: about 85% white, 8% Black, 5% Hispanic, 2% other).
const SKIN_TONES := [[Color(1.22, 1.18, 1.15), 30], [Color(1.12, 1.06, 1.02), 30], [Color(1.0, 1.0, 1.0), 25],
	[Color(0.86, 0.82, 0.8), 6], [Color(0.66, 0.6, 0.58), 5], [Color(0.48, 0.43, 0.42), 4]]


static func skin_tone(person: int) -> Color:
	var roll := (hash([person, "skin"]) & 0xffff) % 100
	for t in SKIN_TONES:
		roll -= int(t[1])
		if roll < 0:
			return t[0]
	return Color.WHITE


## For pictures only (tools/street_people_shot.gd): the month people dress
## for, when there's no town to say. The game never sets it.
static var month_override := -1


## The month people dress for: the one the town shows (July while seasons
## are off).
static func month_of(t: TrafficSim) -> int:
	if month_override > 0:
		return month_override
	return DayNight.visible_month(t._sim) if t != null and t._sim != null else 7


func _age(person: int) -> int:
	if traffic._sim == null or not traffic._sim.people.people.has(person):
		return -1
	return int(traffic._sim.people.people[person].age)


func mms_count() -> int:
	return _mms.size()


## Which figure a person is drawn with: the woman's (1) for a woman, by
## her first name (PersonNames.FIRST runs man, woman, man...), so Mary on
## the sidewalk is drawn as a woman; about half each for anyone unknown.
static func figure(person: int, who := {}) -> int:
	if who.has("first"):
		var i := PersonNames.FIRST.find(String(who.first))
		if i >= 0:
			return i % 2
	return (hash([person, "figure"]) >> 3) & 1


## Each person's own height and build, the same every time they're seen,
## from who they are: a man about 1.75 m and a woman about 1.62 m give or
## take 7 cm, a teenager shorter by their age, and someone past 70 a few
## centimetres down (CDC NHANES 2015-2018 adult heights and growth charts).
## Slight to heavy at any age. The mesh is 1.7 m. Without a person (tools),
## a mix of adults and about one in eight a child, as before.
## Outfit bit for a seated person (the shader bends them into a chair).
const SEATED := 4096
## Outfit bit for a school backpack: children 5 to 11 out walking are on the
## way to or from school (BusNet._school_walks), the only walks they make.
const BACKPACK := 8192

## Median heights by age, 0 to 17, in cm (CDC 2000 growth charts).
const BOY_CM := [50, 76, 87, 96, 103, 110, 116, 122, 128, 133, 138, 143, 149, 156, 164, 170, 173, 175]
const GIRL_CM := [49, 74, 86, 95, 102, 109, 115, 121, 127, 133, 138, 144, 151, 157, 160, 162, 162, 162]


static func build(person: int, who := {}) -> Vector3:
	var h := hash(person)
	var tall := 0.9 + float(h & 255) / 255.0 * 0.2
	var wide := 0.85 + float((h >> 8) & 255) / 255.0 * 0.45
	if who.has("age"):
		var age := int(who.age)
		var woman := figure(person, who) == 1
		var m := (1.62 if woman else 1.75) + (float(h & 255) / 255.0 - 0.5) * 0.14
		if age < 18:
			# Children and teens at their age's height (CDC growth charts,
			# medians), keeping their place above or below it.
			var grown: float = (GIRL_CM if woman else BOY_CM)[clampi(age, 0, 17)] / 100.0
			m *= grown / (1.62 if woman else 1.75)
			wide = minf(wide, 0.85 + float(age - 10) * 0.03)
			wide = minf(wide, m / 1.7 * 1.05)
		elif age > 70:
			m -= float(age - 70) * 0.004
		tall = m / 1.7
	elif (h >> 16) % 8 == 0:
		tall = 0.6 + float((h >> 20) & 15) / 15.0 * 0.15
		wide = 0.75 + float((h >> 24) & 15) / 15.0 * 0.15
	return Vector3(wide, tall, lerpf(wide, 1.0, 0.4))


## A person about 1.7 m tall: legs, arms, body and head, coloured by the
## shirt. Each arm swings with the opposite leg, as people walk.
## The detail the shape helpers build at: 0 farthest to 4 closest.
static var _lod := 2


static func _person_mesh(kind := 0, lod := 2) -> Mesh:
	# A person about 1.7 m tall in real proportions (step one away from
	# toy blocks, Nathan 2026-10-25: "they currently look like Legos or
	# Roblox"): tapered round limbs, a pelvis and a chest broader at the
	# shoulders, a neck, an oval head with hair, hands and shoes.
	_lod = lod
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Parts the shader dresses (see its vertex alpha): trousers white (the
	# shader picks their colour), shins, forearms and hair in their own.
	var trousers := Color(1, 1, 1, 0.5)
	var skin := Color(0.66, 0.47, 0.36)
	var shin := Color(skin, 0.75)
	var forearm := Color(skin, 0.25)
	var hair := Color(0.16, 0.11, 0.07, 0.9)
	var shoe := Color(0.12, 0.11, 0.1)
	var shirt := Color(1, 1, 1, 0)
	const HIP := 0.88
	const SHOULDER := 1.4
	for side in [-1.0, 1.0]:
		var x: float = side * 0.095
		var leg := Vector2(-side, HIP)  # each leg swings opposite its arm
		_limb(st, Vector3(x, HIP, 0.0), Vector3(x, 0.47, 0.0), Vector2(0.078, 0.082), Vector2(0.055, 0.058), trousers, leg)
		_limb(st, Vector3(x, 0.47, 0.0), Vector3(x, 0.08, 0.0), Vector2(0.052, 0.056), Vector2(0.038, 0.042), shin, leg)
		_box(st, Vector3(x, 0.04, -0.035), Vector3(0.048, 0.04, 0.12), shoe, leg)
		var ax: float = side * (0.195 if kind == 1 else 0.215)
		var arm := Vector2(side, SHOULDER)
		_limb(st, Vector3(ax, SHOULDER, 0.0), Vector3(side * 0.235, 1.12, 0.0), Vector2(0.05, 0.052), Vector2(0.043, 0.045), shirt, arm)
		_limb(st, Vector3(side * 0.235, 1.12, 0.0), Vector3(side * 0.245, 0.86, -0.01), Vector2(0.04, 0.042), Vector2(0.032, 0.034), forearm, arm)
		_blob(st, Vector3(side * 0.247, 0.81, -0.012), Vector3(0.032, 0.05, 0.042), skin, arm, 6, 4)
	# Hips and pelvis in the trousers, then the shirt up to the shoulders.
	var hips := 1.08 if kind == 1 else 1.0
	var chest := 0.9 if kind == 1 else 1.0
	_limb(st, Vector3(0.0, 0.84, 0.0), Vector3(0.0, 1.0, 0.0), Vector2(0.175 * hips, 0.112), Vector2(0.158 * hips, 0.104), Color(trousers, 0.56))
	_limb(st, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.27, 0.0), Vector2(0.158 * hips * 0.95, 0.104), Vector2(0.19 * chest, 0.115), shirt)
	_limb(st, Vector3(0.0, 1.27, 0.0), Vector3(0.0, 1.41, 0.0), Vector2(0.19 * chest, 0.115), Vector2(0.215 * chest, 0.105), shirt, Vector2.ZERO, 8)
	_limb(st, Vector3(0.0, 1.41, 0.0), Vector3(0.0, 1.46, 0.0), Vector2(0.215 * chest, 0.105), Vector2(0.09, 0.07), shirt, Vector2.ZERO, 8)  # shoulders slope in to the neck
	_limb(st, Vector3(0.0, 1.45, 0.0), Vector3(0.0, 1.54, 0.0), Vector2(0.05, 0.052), Vector2(0.046, 0.048), skin)
	# A backpack on the back, shown only for a child on the school walk
	# (BACKPACK); the shader folds it away for everyone else.
	if lod >= 1:
		_blob(st, Vector3(0.0, 1.2, 0.17), Vector3(0.14 * chest, 0.16, 0.075), Color(0.3, 0.3, 0.3, 0.62), Vector2.ZERO, 6, 4)
	_blob(st, Vector3(0.0, 1.625, -0.005), Vector3(0.082, 0.108, 0.098), skin, Vector2.ZERO, 8, 6)
	# Hair over the crown and back of the head; the face stays bare.
	_blob(st, Vector3(0.0, 1.665, 0.022), Vector3(0.091, 0.092, 0.1), hair, Vector2.ZERO, 8, 6)
	if kind == 1:
		# Longer hair, down past the collar at the back.
		_blob(st, Vector3(0.0, 1.55, 0.05), Vector3(0.085, 0.12, 0.06), Color(hair, 0.97), Vector2.ZERO, 8, 6)
	if lod >= 3:
		# Close up, a face: nose, ears, eyes, brows and mouth.
		var dark := Color(0.08, 0.06, 0.05)
		_blob(st, Vector3(0.0, 1.612, -0.101), Vector3(0.013, 0.022, 0.018), skin, Vector2.ZERO, 6, 4)
		for side in [-1.0, 1.0]:
			_blob(st, Vector3(side * 0.083, 1.62, 0.004), Vector3(0.011, 0.024, 0.016), skin, Vector2.ZERO, 6, 4)
			_blob(st, Vector3(side * 0.031, 1.643, -0.09), Vector3(0.011, 0.007, 0.006), dark, Vector2.ZERO, 6, 4)
			_blob(st, Vector3(side * 0.032, 1.665, -0.09), Vector3(0.017, 0.004, 0.007), Color(hair, 0.97), Vector2.ZERO, 6, 2)
		_blob(st, Vector3(0.0, 1.578, -0.094), Vector3(0.02, 0.005, 0.006), Color(0.45, 0.22, 0.2), Vector2.ZERO, 6, 2)
	if lod >= 3:
		st.index()  # shared corners: smooth shading close up
	st.generate_normals()
	return st.commit()


## A tapered round limb (an elliptical frustum) from `a` to `b`, with radii
## `ra` and `rb` (x across, z front to back), capped at both ends.
static func _limb(st: SurfaceTool, a: Vector3, b: Vector3, ra: Vector2, rb: Vector2, col: Color,
		swing := Vector2.ZERO, sides := 6) -> void:
	sides = [4, maxi(4, sides - 2), sides, sides * 3 / 2, sides * 2][_lod]
	var ring_a := []
	var ring_b := []
	for i in sides:
		var t := TAU * i / sides
		ring_a.append(a + Vector3(cos(t) * ra.x, 0.0, sin(t) * ra.y))
		ring_b.append(b + Vector3(cos(t) * rb.x, 0.0, sin(t) * rb.y))
	for i in sides:
		var j := (i + 1) % sides
		_tri(st, [ring_a[i], ring_b[i], ring_b[j]], col, swing)
		_tri(st, [ring_a[i], ring_b[j], ring_a[j]], col, swing)
		_tri(st, [a, ring_a[i], ring_a[j]], col, swing)
		_tri(st, [b, ring_b[j], ring_b[i]], col, swing)


## A rounded blob (an ellipsoid) for heads, hair, hands and shoulders.
static func _blob(st: SurfaceTool, c: Vector3, r: Vector3, col: Color, swing := Vector2.ZERO,
		around := 8, up := 6) -> void:
	around = [4, maxi(4, around - 2), around, around * 3 / 2, around * 2][_lod]
	up = [2, maxi(2, up - 2), up, up * 3 / 2, up * 2][_lod]
	for i in up:
		var v0 := PI * i / up - PI * 0.5
		var v1 := PI * (i + 1) / up - PI * 0.5
		for k in around:
			var u0 := TAU * k / around
			var u1 := TAU * (k + 1) / around
			var p := func(u: float, v: float) -> Vector3:
				return c + Vector3(cos(v) * cos(u) * r.x, sin(v) * r.y, cos(v) * sin(u) * r.z)
			_tri(st, [p.call(u0, v0), p.call(u0, v1), p.call(u1, v1)], col, swing)
			_tri(st, [p.call(u0, v0), p.call(u1, v1), p.call(u1, v0)], col, swing)


static func _tri(st: SurfaceTool, pts: Array, col: Color, swing: Vector2) -> void:
	for q in pts:
		st.set_color(col)
		st.set_uv(swing)
		st.add_vertex(q)


## A box; `swing` is the limb's swing direction (0 for none) and pivot height.
static func _box(st: SurfaceTool, c: Vector3, h: Vector3, col: Color, swing := Vector2.ZERO) -> void:
	var corners := []
	for i in 8:
		corners.append(c + Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		for t in [[0, 1, 2], [0, 2, 3]]:
			for k in t:
				st.set_color(col)
				st.set_uv(swing)
				st.add_vertex(corners[f[k]])


## Coat colours of the dogs people walk (sRGB): black, yellow and chocolate
## Labs (the most kept breed in the US for decades, AKC), goldens, a grey
## and white, a tan mutt.
const DOG_COATS := [Color(0.08, 0.07, 0.07), Color(0.86, 0.7, 0.45), Color(0.33, 0.21, 0.13),
	Color(0.78, 0.5, 0.24), Color(0.82, 0.81, 0.78), Color(0.55, 0.4, 0.25), Color(0.08, 0.07, 0.07)]
## Metres a trotting dog covers in one cycle of its legs.
const DOG_STRIDE := 0.8


## A medium dog (a Lab is about 0.57 m at the shoulder) facing -z, its feet
## at y 0, in the walkers' own shader: the coat takes the instance's colour
## (vertex alpha 0) and the legs trot in diagonal pairs about the shoulder
## and hip, like a person's arms and legs.
static func _dog_mesh(lod := 3) -> Mesh:
	_lod = lod
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var coat := Color(1, 1, 1, 0)
	var dark := Color(0.04, 0.035, 0.03)
	const TOP := 0.44
	for side in [-1.0, 1.0]:
		var x: float = side * 0.075
		for end in [[-0.21, side], [0.23, -side]]:
			var z: float = end[0]
			var swing := Vector2(end[1], TOP)
			_limb(st, Vector3(x, TOP, z), Vector3(x, 0.2, z + 0.01), Vector2(0.045, 0.05), Vector2(0.03, 0.032), coat, swing)
			_limb(st, Vector3(x, 0.2, z + 0.01), Vector3(x, 0.035, z), Vector2(0.026, 0.028), Vector2(0.024, 0.026), coat, swing)
			_blob(st, Vector3(x, 0.025, z - 0.02), Vector3(0.032, 0.025, 0.045), coat, swing, 6, 4)
	# Barrel of a body, deep in the chest, a neck up to the head.
	_blob(st, Vector3(0.0, 0.45, 0.02), Vector3(0.12, 0.13, 0.33), coat, Vector2.ZERO, 10, 6)
	_blob(st, Vector3(0.0, 0.44, -0.2), Vector3(0.115, 0.14, 0.14), coat, Vector2.ZERO, 8, 6)
	_blob(st, Vector3(0.0, 0.55, -0.3), Vector3(0.07, 0.1, 0.08), coat, Vector2.ZERO, 8, 5)
	_blob(st, Vector3(0.0, 0.63, -0.37), Vector3(0.075, 0.075, 0.09), coat, Vector2.ZERO, 8, 6)
	_blob(st, Vector3(0.0, 0.6, -0.46), Vector3(0.042, 0.04, 0.06), coat, Vector2.ZERO, 8, 4)
	_blob(st, Vector3(0.0, 0.615, -0.515), Vector3(0.018, 0.016, 0.014), dark, Vector2.ZERO, 6, 4)
	for side in [-1.0, 1.0]:
		# Drop ears, and the eyes.
		_blob(st, Vector3(side * 0.07, 0.6, -0.35), Vector3(0.018, 0.055, 0.04), coat, Vector2.ZERO, 6, 4)
		_blob(st, Vector3(side * 0.035, 0.655, -0.44), Vector3(0.01, 0.01, 0.008), dark, Vector2.ZERO, 6, 4)
	# The tail, carried out and down behind.
	for i in 7:
		var t := float(i) / 6.0
		_blob(st, Vector3(0.0, 0.47 - t * t * 0.16, 0.33 + t * 0.2), Vector3(0.024, 0.024, 0.045) * (1.0 - t * 0.4), coat, Vector2.ZERO, 6, 4)
	st.generate_normals()
	return st.commit()


## A dog's coat colour and size (0.6 a beagle to 1.1 a shepherd), the same
## every time.
static func dog_of(seed: int) -> Array:
	var coat: Color = DOG_COATS[(hash([seed, "dog"]) >> 3) % DOG_COATS.size()]
	return [coat.srgb_to_linear(), 0.6 + float(hash([seed, "dog size"]) & 255) / 255.0 * 0.5]
