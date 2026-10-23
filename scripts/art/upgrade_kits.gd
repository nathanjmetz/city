class_name UpgradeKits
extends RefCounted
## What a hub builds as its leader develops it, drawn on the ground (Brawn
## 2026-10-23: every decision and upgrade gets a real visual; an oil
## company "adding things" must look different). Each kit is modelled on a
## real example, named on the kit, and drawn into the hub builder `b` in its
## own local frame (-z faces the hub's drive) around centre `c`, sized to
## the footprint its hub reserves for it (Industry.ADDONS).
##
## Kits add triangles to the builder's shared surfaces, so they cost no
## extra draw calls; they rebuild only when the hub builds something.

const STEEL := Color("#6b6f73")
const PIPE := Color("#c9a020")  # safety yellow
const WHITE := Color("#e4e3dd")
const TAN := Color("#b9a57e")
const GRAVEL := Color("#8d877c")
const DARK := Color("#2e3032")
const RED := Color("#9a2a22")
const CONCRETE := Color("#b9b5ab")


# ------------------------------------------------------------------ parts

static func _strut(b: CommercialBuilder, a: Vector3, z: Vector3, w: float, col: Color) -> void:
	var d := z - a
	var len := d.length()
	if len < 0.01:
		return
	var f := d / len
	var side := (Vector3.UP if absf(f.y) < 0.95 else Vector3.RIGHT).cross(f).normalized()
	b._box("paint", Vector3(w, w, len), (a + z) * 0.5, col, Basis(side, f.cross(side), f))


## A horizontal tank or drum along x (or z), capped at both ends.
static func _drum(b: CommercialBuilder, c: Vector3, r: float, len: float, col: Color, along_x := true, segs := 14) -> void:
	var ax := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	var u := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var h := ax * len * 0.5
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := u * cos(a0) + Vector3.UP * sin(a0)
		var d1 := u * cos(a1) + Vector3.UP * sin(a1)
		var p0 := c + d0 * r
		var p1 := c + d1 * r
		var out := (d0 + d1) * 0.5
		b._quad("paint", p1 - h, p0 - h, p0 + h, p1 + h, col, [], out)
		b._tri("paint", c + h, p1 + h, p0 + h, col.darkened(0.08), [], ax)
		b._tri("paint", c - h, p0 - h, p1 - h, col.darkened(0.08), [], -ax)


static func _cone(b: CommercialBuilder, base: Vector3, r: float, h: float, col: Color, segs := 16) -> void:
	var top := base + Vector3(0, h, 0)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := base + Vector3(cos(a0), 0, sin(a0)) * r
		var p1 := base + Vector3(cos(a1), 0, sin(a1)) * r
		b._tri("paint", p1, p0, top, col, [], (p0 + p1) * 0.5 - base + Vector3(0, r, 0))


## A welded upright tank with a low cone roof.
static func _tank(b: CommercialBuilder, base: Vector3, r: float, h: float, col: Color) -> void:
	b._cylinder("paint", base + Vector3(0, 0.15, 0), r, h, col, 18 if r > 3.0 else 12)
	_cone(b, base + Vector3(0, h + 0.15, 0), r * 1.02, maxf(0.3, r * 0.12), col.darkened(0.05), 18 if r > 3.0 else 12)


## A spiral stair up a tank, as a straight run of treads (seen from afar).
static func _tank_stair(b: CommercialBuilder, base: Vector3, r: float, h: float) -> void:
	var steps := int(h / 0.6)
	for k in steps:
		var a := -0.9 + 1.6 * float(k) / steps
		var p := base + Vector3(cos(a), 0, sin(a)) * (r + 0.45) + Vector3(0, 0.4 + k * 0.6, 0)
		b._box("paint", Vector3(0.8, 0.07, 0.8), p, STEEL)


static func _pad(b: CommercialBuilder, c: Vector3, hw: float, hd: float, col := GRAVEL) -> void:
	b._flat_rect("gravel", c.x - hw, c.x + hw, c.z - hd, c.z + hd, 0.1, col)


## A pre-engineered metal building with a low gable roof (ridge along x).
static func _metal_building(b: CommercialBuilder, c: Vector3, w: float, d: float, h: float, wall: Color,
		roof := Color("#8e9aa3")) -> void:
	b._box("paint", Vector3(w + 0.2, 0.3, d + 0.2), c + Vector3(0, 0.15, 0), CONCRETE)
	b._box("metal", Vector3(w, h, d), c + Vector3(0, 0.3 + h * 0.5, 0), wall)
	b._metal_roof(c.x, c.z, 0.3 + h, w, d, roof)


## A flat-roofed box building (prep plants, mills), with a dark window band.
static func _block_building(b: CommercialBuilder, c: Vector3, w: float, d: float, h: float, wall: Color) -> void:
	b._box("paint", Vector3(w + 0.2, 0.3, d + 0.2), c + Vector3(0, 0.15, 0), CONCRETE)
	b._box("metal", Vector3(w, h, d), c + Vector3(0, 0.3 + h * 0.5, 0), wall)
	b._box("paint", Vector3(w + 0.04, 1.0, d + 0.04), c + Vector3(0, h * 0.62, 0), wall.darkened(0.45))
	b._box("paint", Vector3(w + 0.3, 0.3, d + 0.3), c + Vector3(0, h + 0.4, 0), wall.darkened(0.15))


## A covered belt conveyor (a gallery) from a to z, on bents to the ground.
static func _gallery(b: CommercialBuilder, a: Vector3, z: Vector3, col := Color("#a7aba9")) -> void:
	_strut(b, a, z, 1.6, col)
	var n := maxi(1, int(a.distance_to(z) / 12.0))
	for i in n + 1:
		var p := a.lerp(z, float(i) / n)
		if p.y > 1.2:
			b._box("paint", Vector3(0.35, p.y, 1.4), Vector3(p.x, p.y * 0.5, p.z), STEEL)


## Railroad track along z: ballast, ties and two rails, bumper posts at the ends.
static func _track_z(b: CommercialBuilder, x: float, z0: float, z1: float) -> void:
	b._flat_rect("gravel", x - 2.0, x + 2.0, z0, z1, 0.12, Color("#77736a"))
	var z := z0 + 0.4
	while z < z1 - 0.4:
		b._box("paint", Vector3(2.6, 0.16, 0.24), Vector3(x, 0.2, z), Color("#4a3c30"))
		z += 1.6
	for s in [-0.72, 0.72]:
		b._box("paint", Vector3(0.08, 0.16, z1 - z0), Vector3(x + s, 0.34, (z0 + z1) * 0.5), Color("#5d5750"))
	for e in [z0 + 0.6, z1 - 0.6]:
		b._box("paint", Vector3(2.0, 1.1, 0.5), Vector3(x, 0.6, e), Color("#c9a020"))


## A stack of pipe on a rack: joints of tubing laid in layers.
static func _pipe_rack(b: CommercialBuilder, c: Vector3, len: float, layers: int, col: Color) -> void:
	for s in [-1.0, 1.0]:
		b._box("paint", Vector3(0.3, 0.9, 2.6), c + Vector3(s * len * 0.35, 0.45, 0), STEEL)
	for i in layers:
		b._box("paint", Vector3(len, 0.12, 2.2), c + Vector3(0, 0.96 + i * 0.16, 0), col.darkened(0.04 * (i % 2)))


# ------------------------------------------------------------------ oil
# Benchmark: Illinois Basin leases in Gibson, Pike and Posey Counties,
# Indiana, and the gathering plants and crude stations that serve them.

## A lease's first tanks before it builds a full battery: two 210-barrel
## stock tanks (3 m across) and a vertical separator, as on a small stripper
## lease.
static func lease_tanks(b: CommercialBuilder, c: Vector3) -> void:
	_pad(b, c, 7.0, 4.5)
	for i in 2:
		_tank(b, c + Vector3(-2.0 + i * 4.0, 0, 0), 1.5, 4.6, TAN)
	b._cylinder("paint", c + Vector3(5.2, 0.2, -2.5), 0.55, 2.6, Color("#9a9fa2"), 10)


## Gas processing plant: a metal compressor building with exhaust stacks,
## two contactor towers and a glycol still, an elevated fin-fan cooler, two
## white NGL bullet tanks on saddles and a flare stack set apart at the
## back corner (after small Illinois Basin gathering and processing plants).
static func gas_plant(b: CommercialBuilder, c: Vector3) -> void:
	_pad(b, c, 14.0, 12.0)
	var bc := c + Vector3(-5.0, 0, -5.0)
	_metal_building(b, bc, 13.0, 8.0, 6.5, Color("#d8d6cf"))
	for i in 3:
		b._cylinder("paint", bc + Vector3(-4.0 + i * 4.0, 7.2, 1.5), 0.3, 2.6, DARK, 8)
	for i in 2:
		var t := c + Vector3(5.0 + i * 2.8, 0, -6.5)
		b._box("concrete", Vector3(2.0, 0.4, 2.0), t + Vector3(0, 0.2, 0), CONCRETE)
		b._cylinder("paint", t + Vector3(0, 0.4, 0), 0.75, 12.5, Color("#c8c2b2"), 10)
		b._box("paint", Vector3(1.9, 0.08, 1.9), t + Vector3(0, 9.0, 0), PIPE)
	b._cylinder("paint", c + Vector3(10.8, 0.3, -2.0), 0.5, 4.2, Color("#9a9fa2"), 8)  # glycol still
	# Fin-fan cooler on legs: a flat bank with two fans on top.
	var ff := c + Vector3(-3.0, 0, 3.5)
	for x in [-3.6, 3.6]:
		for z in [-1.6, 1.6]:
			b._box("paint", Vector3(0.25, 4.0, 0.25), ff + Vector3(x, 2.0, z), STEEL)
	b._box("paint", Vector3(8.0, 1.0, 3.8), ff + Vector3(0, 4.5, 0), Color("#9aa0a4"))
	for x in [-2.0, 2.0]:
		b._cylinder("paint", ff + Vector3(x, 5.0, 0), 1.5, 0.4, DARK, 12)
	# NGL bullets.
	for i in 2:
		var bt := c + Vector3(4.0, 0, 3.0 + i * 3.8)
		for x in [-3.5, 3.5]:
			b._box("paint", Vector3(0.4, 1.2, 2.4), bt + Vector3(x, 0.6, 0), CONCRETE)
		_drum(b, bt + Vector3(0, 2.1, 0), 1.5, 11.0, WHITE)
	# Pipe rack joining it up.
	_strut(b, bc + Vector3(6.5, 3.0, 0), c + Vector3(5.0, 3.0, -6.5), 0.3, STEEL)
	_strut(b, bc + Vector3(4.0, 3.0, 4.0), ff + Vector3(-4.0, 3.0, 0), 0.3, STEEL)
	# Flare, well away from the rest.
	var fl := c + Vector3(-12.0, 0, 10.0)
	b._box("concrete", Vector3(2.0, 0.3, 2.0), fl + Vector3(0, 0.15, 0), CONCRETE)
	b._cylinder("paint", fl + Vector3(0, 0.3, 0), 0.35, 17.0, Color("#8a8f92"), 8)
	b._cylinder("paint", fl + Vector3(0, 17.3, 0), 0.55, 1.2, DARK, 8)


## Pipeline connection: a LACT unit (the lease automatic custody transfer
## skid that meters crude into a pipeline) on a concrete pad beside the
## tanks, a pig launcher, and the buried line's mowed right-of-way leaving
## the yard with yellow marker posts (49 CFR 195.410), out to x = `edge`.
static func pipeline(b: CommercialBuilder, c: Vector3, edge: float) -> void:
	b._box("concrete", Vector3(7.0, 0.3, 3.4), c + Vector3(0, 0.15, 0), CONCRETE)
	b._box("paint", Vector3(1.4, 1.8, 1.0), c + Vector3(-2.4, 1.2, -0.6), Color("#d8d6cf"))  # sampler cabinet
	b._box("paint", Vector3(1.0, 0.9, 0.8), c + Vector3(-0.6, 0.75, 0.8), Color("#3d5f8a"))  # pump
	_strut(b, c + Vector3(-3.2, 0.9, 0.0), c + Vector3(3.0, 0.9, 0.0), 0.3, Color("#8a8f92"))  # meter run
	b._box("paint", Vector3(0.6, 0.6, 0.6), c + Vector3(1.0, 0.9, 0.0), DARK)  # meter
	_strut(b, c + Vector3(3.0, 0.9, 0.0), c + Vector3(3.0, 0.9, 1.4), 0.3, Color("#8a8f92"))
	# Pig launcher: a short fat barrel on stands, angled down into the ground.
	var pl := c + Vector3(3.0, 0, 3.0)
	_strut(b, pl + Vector3(-2.2, 1.3, 0), pl + Vector3(2.2, 0.7, 0), 0.6, PIPE)
	for x in [-1.5, 1.2]:
		b._box("paint", Vector3(0.2, 1.0, 0.8), pl + Vector3(x, 0.5, 0), STEEL)
	# Right-of-way: a mowed strip with marker posts every 15 m, out to the
	# yard's edge on whichever side it leaves by.
	var dir := signf(edge - pl.x)
	var x0 := pl.x + 3.0 * dir
	b._flat_rect("gravel", minf(x0, edge), maxf(x0, edge), pl.z - 3.0, pl.z + 3.0, 0.08, Color("#7f8a5a"))
	var x := x0
	while (edge - x) * dir > 0.0:
		b._box("paint", Vector3(0.1, 1.5, 0.1), Vector3(x, 0.75, pl.z - 2.6), PIPE)
		b._box("paint", Vector3(0.14, 0.3, 0.14), Vector3(x, 1.55, pl.z - 2.6), Color("#d8641c"))
		x += 15.0 * dir


## Completion and workover yard: a well-servicing rig on its carrier with
## the mast laid down, its doghouse, two 500-barrel frac tanks, and racks of
## tubing, as at the service yards that work Illinois Basin wells.
static func completion_yard(b: CommercialBuilder, c: Vector3) -> void:
	_pad(b, c, 11.0, 10.0)
	# Rig carrier: four axles, a cab and the mast on its headache rack.
	var rc := c + Vector3(-1.0, 0, -5.5)
	b._box("paint", Vector3(14.0, 1.4, 2.6), rc + Vector3(0, 1.6, 0), RED)
	b._box("paint", Vector3(2.4, 2.0, 2.6), rc + Vector3(-7.6, 2.0, 0), RED.lightened(0.1))  # cab
	for x in [-6.4, -2.8, 2.2, 5.0]:
		for z in [-1.2, 1.2]:
			b._box("paint", Vector3(1.1, 1.1, 0.5), rc + Vector3(x, 0.55, z), Color("#1e1e1e"))
	for z in [-0.8, 0.8]:
		b._box("paint", Vector3(17.0, 0.35, 0.35), rc + Vector3(1.0, 3.0, z), Color("#d9a521"))
	for i in 6:
		_strut(b, rc + Vector3(-6.0 + i * 2.8, 3.0, -0.8), rc + Vector3(-4.6 + i * 2.8, 3.0, 0.8), 0.12, Color("#d9a521"))
	b._box("paint", Vector3(0.4, 2.2, 2.4), rc + Vector3(-6.2, 3.4, 0), STEEL)  # headache rack
	# Doghouse on skids.
	b._box("paint", Vector3(6.0, 2.6, 2.6), c + Vector3(7.0, 1.4, -5.5), Color("#c9cbc8"))
	# Frac tanks: steel boxes 14 m long with a sloped front.
	for i in 2:
		var ft := c + Vector3(0.0, 0, 1.5 + i * 3.4)
		b._box("paint", Vector3(13.0, 3.0, 2.5), ft + Vector3(0.5, 1.6, 0), Color("#8a3a2c" if i == 0 else "#3d5f8a"))
		_strut(b, ft + Vector3(-6.0, 0.1, 0), ft + Vector3(-7.4, 2.4, 0), 2.4, Color("#8a3a2c" if i == 0 else "#3d5f8a"))
	_pipe_rack(b, c + Vector3(1.0, 0, 8.5), 9.6, 5, Color("#7a7d80"))


## Crude truck station and tankage: two 20,000-barrel tanks (21 m across is
## a big one; these are 14 m) inside an earthen containment berm (SPCC), and
## a two-lane unloading rack under a canopy where tank trucks pump off.
static func crude_terminal(b: CommercialBuilder, c: Vector3) -> void:
	_pad(b, c, 17.0, 14.0)
	var tz := c.z + 5.0
	b._flat_rect("gravel", c.x - 16.0, c.x + 16.0, tz - 8.5, tz + 8.5, 0.11, Color("#7d8a5a"))  # grass berm floor
	for s in [-1.0, 1.0]:
		b._box("paint", Vector3(33.0, 1.2, 1.4), Vector3(c.x, 0.6, tz + s * 8.5), Color("#6f7a4c"))
		b._box("paint", Vector3(1.4, 1.2, 17.0), Vector3(c.x + s * 16.5, 0.6, tz), Color("#6f7a4c"))
	for x in [-8.0, 8.0]:
		var t := Vector3(c.x + x, 0, tz)
		_tank(b, t, 7.0, 9.0, TAN.lightened(0.08))
		_tank_stair(b, t, 7.0, 9.0)
	# Unloading rack: canopy on four posts over two truck lanes.
	var rk := c + Vector3(0, 0, -9.0)
	b._flat_rect("drive", rk.x - 9.0, rk.x + 9.0, rk.z - 4.0, rk.z + 4.0, 0.12)
	for x in [-7.5, 7.5]:
		for z in [-3.0, 3.0]:
			b._box("paint", Vector3(0.3, 5.4, 0.3), rk + Vector3(x, 2.7, z), STEEL)
	b._box("paint", Vector3(16.0, 0.4, 7.0), rk + Vector3(0, 5.6, 0), Color("#d8d6cf"))
	for z in [-1.2, 1.2]:
		b._box("paint", Vector3(1.0, 1.4, 0.6), rk + Vector3(0, 0.8, z), Color("#3d5f8a"))  # pump and meter


# ------------------------------------------------------------------ coal
# Benchmark: southern Indiana surface mines and their preparation plants
# (Bear Run in Sullivan County, Gibson County Coal), the plant at the pit.

## Coal preparation (wash) plant: a tall metal-clad plant with a stepped
## headhouse, a concrete clean-coal silo fed by an inclined gallery, and a
## round thickener tank where the wash water settles. Footprint 20 x 36,
## the plant at the back (+z).
static func prep_plant(b: CommercialBuilder, c: Vector3) -> void:
	_pad(b, c, 10.0, 18.0, Color("#6d6a62"))
	var pc := c + Vector3(0, 0, 10.0)
	_block_building(b, pc, 12.0, 15.0, 20.0, Color("#b9b4a6"))
	_block_building(b, pc + Vector3(-1.5, 20.6, 1.5), 7.0, 8.0, 6.0, Color("#a7aba9"))
	var si := c + Vector3(-5.0, 0, -8.0)
	b._cylinder("paint", si, 4.5, 24.0, CONCRETE, 18)
	b._box("paint", Vector3(5.0, 3.0, 5.0), si + Vector3(0, 25.5, 0), Color("#a7aba9"))
	_gallery(b, pc + Vector3(-3.0, 18.0, -7.5), si + Vector3(0, 26.0, 2.0))
	# Thickener: a low round tank of grey water with a bridge to its centre drive.
	var th := c + Vector3(4.5, 0, -12.5)
	b._cylinder("paint", th, 5.0, 2.4, CONCRETE, 20)
	b._flat_rect("gravel", th.x - 3.4, th.x + 3.4, th.z - 3.4, th.z + 3.4, 2.45, Color("#5d6466"))
	b._box("paint", Vector3(5.2, 0.4, 0.8), th + Vector3(-2.6, 2.8, 0), STEEL)
	b._box("paint", Vector3(1.2, 1.2, 1.2), th + Vector3(0, 3.2, 0), PIPE)


## An overland belt from the crusher out of the yard toward the customer:
## a covered conveyor on low bents (as at the long belts linking Indiana
## mines to their plants), rising from `a` up at the crusher to a transfer
## house at `z`.
static func overland_conveyor(b: CommercialBuilder, a: Vector3, z: Vector3) -> void:
	var low := a.lerp(z, 0.3)
	low.y = 2.2
	var end := Vector3(z.x, 2.2, z.z)
	_gallery(b, a, low)
	_gallery(b, low, end)
	b._box("metal", Vector3(3.2, 5.0, 3.2), Vector3(z.x, 2.8, z.z), Color("#b9b4a6"))
	b._box("paint", Vector3(3.6, 0.3, 3.6), Vector3(z.x, 5.4, z.z), Color("#8e9aa3"))


## Rail loadout: a tall concrete silo with a flood-loader tower over a
## loading track (unit trains pass under it at walking speed), fed by an
## inclined belt; a stretch of track with bumpers. Footprint 14 x 80.
static func rail_loadout(b: CommercialBuilder, c: Vector3) -> void:
	_track_z(b, c.x, c.z - 39.0, c.z + 39.0)
	var si := c + Vector3(0, 0, 22.0)
	for s in [-1.0, 1.0]:
		b._box("concrete", Vector3(2.4, 6.0, 9.0), si + Vector3(s * 3.2, 3.0, 0), CONCRETE)
	b._cylinder("paint", si + Vector3(0, 6.0, 0), 5.5, 26.0, CONCRETE, 18)
	b._box("paint", Vector3(6.0, 4.0, 6.0), si + Vector3(0, 34.0, 0), Color("#a7aba9"))
	b._box("paint", Vector3(2.0, 1.6, 2.4), si + Vector3(0, 5.2, -5.0), DARK)  # flood loader chute
	# The belt up from the reclaim hopper under the stockpile.
	_gallery(b, si + Vector3(4.0, 33.0, 0), c + Vector3(11.0, 1.2, 26.0))


# ------------------------------------------------------------------ forestry
# Benchmark: southern Indiana hardwood sawmills and their yards.

## Wet log deck: long decks of sawlogs kept under sprinklers so the logs
## don't check or stain before sawing, as hardwood mills do through summer.
## Footprint 14 x 40, decks along z. `b` is a ForestryBuilder.
static func wet_deck(b: ForestryBuilder, c: Vector3) -> void:
	b._flat_rect("gravel", c.x - 7.0, c.x + 7.0, c.z - 20.0, c.z + 20.0, 0.06, Color("#5e5648"))
	for x in [-3.2, 3.2]:
		b._log_deck(c + Vector3(x, 0, 0), 0.0, 34.0, 12, 0.3)
	var z := c.z - 16.0
	while z <= c.z + 16.0:
		b._box("paint", Vector3(0.1, 4.6, 0.1), Vector3(c.x, 2.3, z), STEEL)
		b._box("paint", Vector3(0.5, 0.2, 0.5), Vector3(c.x, 4.7, z), DARK)
		z += 8.0


## Lumber dry kilns: three package kilns (aluminium-clad boxes with big
## doors on the track side and fan housings along the roof) with kiln carts
## of stickered lumber, and the wood-waste boiler that heats them. Footprint
## 16 x 36.
static func dry_kilns(b: ForestryBuilder, c: Vector3) -> void:
	_pad(b, c, 8.0, 18.0, Color("#7d7462"))
	for i in 3:
		var k := c + Vector3(2.0, 0, -13.0 + i * 9.5)
		b._box("paint", Vector3(10.4, 0.3, 8.4), k + Vector3(0, 0.15, 0), CONCRETE)
		b._box("metal", Vector3(10.0, 6.4, 8.0), k + Vector3(0, 3.5, 0), Color("#c9cbc8"))
		b._box("paint", Vector3(0.12, 5.6, 7.0), k + Vector3(-5.06, 3.1, 0), Color("#a7aba9"))  # door
		for z in [-2.4, 0.0, 2.4]:
			b._box("paint", Vector3(8.0, 0.8, 1.2), k + Vector3(0, 7.1, z), Color("#9aa0a4"))
		# A kiln cart of stickered lumber waiting on the track out front.
		b._lumber(k + Vector3(-6.6, 0, 0), 2.2)
	var bh := c + Vector3(1.0, 0, 15.0)
	_metal_building(b, bh, 6.0, 5.0, 6.0, Color("#b9b4a6"))
	b._cylinder("paint", bh + Vector3(2.0, 0.3, 1.0), 0.5, 16.0, Color("#5c5c5e"), 8)


## Wood pellet mill: a rotary dryer drum on piers with its furnace, the
## hammer mill and pellet mill building, three pellet silos and a bagging
## warehouse with pallets out front, as at small Midwest pellet plants.
## Footprint 36 x 16.
static func pellet_mill(b: CommercialBuilder, c: Vector3) -> void:
	_pad(b, c, 18.0, 8.0, Color("#7d7462"))
	var dr := c + Vector3(-10.0, 0, -3.0)
	for x in [-5.0, 0.0, 5.0]:
		b._box("concrete", Vector3(1.2, 2.0, 3.0), dr + Vector3(x, 1.0, 0), CONCRETE)
	_drum(b, dr + Vector3(0, 3.6, 0), 1.8, 14.0, Color("#7a7d80"))
	b._box("metal", Vector3(3.5, 5.0, 4.0), dr + Vector3(-8.6, 2.5, 0), Color("#8a8f92"))  # furnace
	b._cylinder("paint", dr + Vector3(-8.6, 5.0, 0), 0.5, 9.0, Color("#5c5c5e"), 8)
	var pm := c + Vector3(3.0, 0, -2.0)
	_metal_building(b, pm, 9.0, 9.0, 12.0, Color("#d8d6cf"))
	for i in 3:
		var s := c + Vector3(10.0 + i * 3.0, 0, -4.5)
		b._cylinder("paint", s + Vector3(0, 2.0, 0), 1.3, 12.0, Color("#c3c7c8"), 12)
		_cone(b, s + Vector3(0, 14.0, 0), 1.35, 0.8, Color("#a9adab"), 12)
		for x in [-0.9, 0.9]:
			b._box("paint", Vector3(0.15, 2.0, 0.15), s + Vector3(x, 1.0, 0), STEEL)
	_strut(b, pm + Vector3(4.5, 11.0, -1.0), c + Vector3(16.0, 15.0, -4.5), 0.6, Color("#a7aba9"))
	var bw := c + Vector3(12.0, 0, 4.5)
	_metal_building(b, bw, 12.0, 6.0, 5.5, Color("#c9cbc8"))
	for i in 4:
		b._box("paint", Vector3(1.1, 1.3, 1.1), bw + Vector3(-4.5 + i * 1.5, 0.65, -4.0), Color("#8a6a3c"))


## Seedling cooler and planting crew: a white reefer trailer on its landing
## gear holding bare-root seedlings from the state nursery (Vallonia, IN),
## and pallets of seedling bundles and tree shelters. Footprint 8 x 18.
static func seedling_cooler(b: CommercialBuilder, c: Vector3) -> void:
	_pad(b, c, 4.0, 9.0, Color("#7d7462"))
	b._box("paint", Vector3(2.6, 3.4, 14.5), c + Vector3(0, 2.6, 0.5), WHITE)
	b._box("paint", Vector3(2.2, 1.4, 0.9), c + Vector3(0, 3.6, -7.2), Color("#c9cbc8"))  # reefer unit
	for z in [-5.0, 5.5]:
		b._box("paint", Vector3(2.4, 0.9, 1.2), c + Vector3(0, 0.45, z), Color("#262626"))
	for i in 3:
		b._box("paint", Vector3(1.1, 1.0, 1.1), c + Vector3(-2.6 + 0.0, 0.5, -3.0 + i * 2.6), Color("#7d6a4a"))


## Rows of tree shelters (tan tubes about 1.2 m tall) where a logged stand
## was replanted, as on Indiana hardwood plantings: in the opening around
## the landing, inside a square of half-size `h`.
static func planted_rows(b: CommercialBuilder, land: Vector2, h: float) -> void:
	var col := Color("#c8b88a")
	var z := land.y - 28.0
	while z <= land.y + 28.0:
		var x := land.x - 28.0
		while x <= land.x + 28.0:
			var d := Vector2(x, z).distance_to(land)
			if d > 17.0 and d < 28.0 and absf(x) < h - 3.0 and absf(z) < h - 3.0:
				b._box("paint", Vector3(0.14, 1.2, 0.14), Vector3(x, 0.6, z), col)
			x += 5.0
		z += 3.5


# ------------------------------------------------------------------ farm
# Benchmark: Indiana and Illinois grain farmsteads.

## A bigger grain bin than the first two: 8.4 m across, eaves at 8 m.
static func big_bin(b: CommercialBuilder, base: Vector3) -> void:
	b._box("paint", Vector3(9.0, 0.3, 9.0), base + Vector3(0, 0.15, 0), CONCRETE)
	b._cylinder("metal", base + Vector3(0, 0.3, 0), 4.2, 8.0, Color("#c3c7c8"), 20)
	_cone(b, base + Vector3(0, 8.3, 0), 4.3, 2.2, Color("#a9adab"), 20)
	b._box("paint", Vector3(0.8, 0.5, 0.8), base + Vector3(0, 10.5, 0), Color("#a9adab"))  # roof cap and fan


## Tower grain dryer and bucket elevator leg: a tall narrow dryer (as made by
## the big bin makers) beside a leg tower with spouts down to the bins.
static func dryer_leg(b: CommercialBuilder, dryer: Vector3, leg: Vector3, bins: Array) -> void:
	b._box("paint", Vector3(3.2, 0.3, 3.2), dryer + Vector3(0, 0.15, 0), CONCRETE)
	b._box("metal", Vector3(2.6, 13.0, 2.6), dryer + Vector3(0, 6.8, 0), Color("#d8d6cf"))
	b._box("paint", Vector3(2.9, 1.6, 2.9), dryer + Vector3(0, 2.0, 0), Color("#5a5e60"))  # burner and fan
	b._box("paint", Vector3(0.7, 22.0, 0.7), leg + Vector3(0, 11.0, 0), Color("#a7aba9"))
	b._box("paint", Vector3(1.6, 1.4, 1.6), leg + Vector3(0, 22.4, 0), Color("#a7aba9"))  # head
	for t in bins:
		_strut(b, leg + Vector3(0, 21.5, 0), t, 0.3, Color("#a7aba9"))
	_strut(b, leg + Vector3(0, 21.5, 0), dryer + Vector3(0, 13.3, 0), 0.3, Color("#a7aba9"))


## Precision ag: an RTK base station (a GPS antenna on a mast) and a folded
## 16-row planter with its row units, parked in the yard.
static func precision(b: CommercialBuilder, mast: Vector3, planter: Vector3, col: Color) -> void:
	b._box("paint", Vector3(0.15, 9.0, 0.15), mast + Vector3(0, 4.5, 0), STEEL)
	b._box("paint", Vector3(0.5, 0.25, 0.5), mast + Vector3(0, 9.1, 0), WHITE)
	b._box("paint", Vector3(0.5, 0.5, 0.4), mast + Vector3(0, 1.3, 0.2), Color("#c9cbc8"))
	b._box("paint", Vector3(9.5, 0.35, 0.35), planter + Vector3(0, 1.2, 0), col)  # toolbar
	for i in 8:
		var x := -4.2 + i * 1.2
		b._box("paint", Vector3(0.4, 0.9, 1.6), planter + Vector3(x, 0.7, 0.9), col.darkened(0.1))
		b._box("paint", Vector3(0.45, 0.5, 0.45), planter + Vector3(x, 1.6, 0.9), Color("#d6c27a"))  # seed hopper
	b._box("paint", Vector3(0.3, 0.3, 3.5), planter + Vector3(0, 1.0, -1.9), col)  # tongue


## A hopper-bottom grain trailer, unhitched on its landing gear: the farm
## hauls its grain to the co-op elevator itself.
static func grain_trailer(b: CommercialBuilder, c: Vector3) -> void:
	var col := Color("#c4c8ca")
	b._box("metal", Vector3(12.0, 1.8, 2.5), c + Vector3(0, 2.6, 0), col)
	for x in [-3.0, 0.0, 3.0]:
		_strut(b, c + Vector3(x - 1.2, 1.7, 0), c + Vector3(x, 0.8, 0), 1.0, col.darkened(0.1))
	b._box("paint", Vector3(12.2, 0.15, 2.6), c + Vector3(0, 3.55, 0), Color("#2e5a3a"))  # roll tarp
	for x in [4.2, 5.4]:
		b._box("paint", Vector3(1.0, 1.0, 2.4), c + Vector3(x, 0.5, 0), Color("#1e1e1e"))
	b._box("paint", Vector3(0.2, 1.6, 2.0), c + Vector3(-4.2, 0.8, 0), STEEL)


## Seed dealership: a dealer sign by the yard and stacks of returnable
## seed boxes (the 1.2 m bulk boxes dealers deliver to their neighbours).
static func seed_dealer(b: CommercialBuilder, sign: Vector3, boxes: Vector3) -> void:
	for x in [-1.1, 1.1]:
		b._box("paint", Vector3(0.12, 2.6, 0.12), sign + Vector3(x, 1.3, 0), STEEL)
	b._box("paint", Vector3(2.6, 1.2, 0.1), sign + Vector3(0, 2.4, 0), Color("#2e6b3a"))
	b._box("paint", Vector3(2.0, 0.3, 0.12), sign + Vector3(0, 2.3, -0.02), Color("#e8c43a"))
	for i in 3:
		for j in 2:
			b._box("paint", Vector3(1.15, 1.15, 1.15), boxes + Vector3(i * 1.3, 0.6 + j * 1.2, 0), Color("#3b6ea8" if (i + j) % 2 == 0 else "#2f5c90"))
