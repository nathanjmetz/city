class_name CitySim
extends RefCounted
## The whole city as plain data, stepped in fixed ticks.
##
## Every player action is a command Dictionary passed to apply(), and the
## simulation only changes inside apply() and tick(). Given the same commands
## in the same order, every copy ends up in the same state, so a headless
## server can run this exact class later and send commands to players.

signal buildings_changed
## County roads joined to town or bulldozed (county_joined, county_removed).
signal county_changed
signal lots_changed
## Buildings removed because a road now runs through their lot (for refunds).
signal parcels_lost(keys: Array)
signal zones_changed
## Population, jobs or demand changed (at most every MOVE_EVERY ticks).
signal stats_changed
## Farmland or a farm's fields changed.
signal farms_changed
## The future land use map changed (LandPlan).
signal plan_changed
## A resource company opened, closed, or added or dropped a pad.
signal industry_changed
## A campus opened, closed, or bought, built up or sold a block.
signal education_changed
## The phone company opened or closed, strung fiber, raised a tower or grew.
signal telecom_changed
## A bank opened, closed, bought a block or changed hands.
signal banks_changed
## A warehouse was built, grew, shrank or went away.
signal warehouses_changed
## A big local factory was built, grew, built something new or went away.
signal big_factories_changed
## A park or landmark was placed, filled in, grew, changed tier or went away.
signal parks_changed
## A water utility laid pipe, built a piece of its yard, or its troubles changed.
signal water_changed
## A power company opened, closed, grew, mothballed a unit or built an add-on.
signal power_changed
## A player command went through (sounds and other feedback listen to this).
signal command_applied(cmd: Dictionary)
## A player command was turned down (Telemetry counts these to find where
## players get stuck).
signal command_refused(cmd: Dictionary)
signal neighborhoods_changed

const TICKS_PER_SECOND := 10
## A new building can start every this many ticks.
const GROW_EVERY := Balance.GROW_EVERY
## People move in and stats update every this many ticks.
const MOVE_EVERY := Balance.MOVE_EVERY
## How each zone's buildings go up (see Construction).
const PROFILE_OF_ZONE := {ZoneMap.Zone.RESIDENTIAL: "house", ZoneMap.Zone.COMMERCIAL: "shop",
	ZoneMap.Zone.INDUSTRIAL: "factory"}
## Game minutes per tick: at normal speed a day takes 2.4 real minutes.
const MINUTES_PER_TICK := 1
## Tick 0 is 6:00 AM on Monday, January 4, 2027.
const START_UNIX := 1799042400
## Share of residents who work (US labour force is about half of everyone).
const WORKER_SHARE := Balance.WORKER_SHARE
const TICKS_PER_HOUR := 60 / MINUTES_PER_TICK

var network := RoadNetwork.new()
## The last builds, for Ctrl+Z (not saved).
var undo := UndoLog.new()
var zones := ZoneMap.new()
var traffic := TrafficSim.new(network)
## Everyone in town by name, and the names of places (owned by Traffic work).
var people := People.new()
var economy := Economy.new()
var services := Services.new()
var farms := Farms.new()
## Oil, mining and forestry companies (Brawn's model: a main building whose
## pads spread to where the resource is).
var industry := Industry.new()
## Warehouses that buffer loads between them (hubs that grow in place).
var warehouses := Warehouses.new()
## Big local factories: the ethanol plant, meatpacker, furniture maker and
## RV plant (one of each, hubs run by their owners).
var big := BigFactories.new()
## Power companies (Brawn's hub-with-a-leader model): a yard whose leader
## picks the plant and grows it. The regional grid stays the default.
var power := Power.new()
## The trucks that carry every load (grain, crude, ore, logs, goods).
var logistics := Logistics.new()
## Land saved for farming or an industry: no roads or zoning on it.
var reserves := Reserves.new()
## The town's future land use map: big soft areas the player outlines for
## homes, shops, jobs or farming. Builders look inside it first (LandPlan).
var land_plan := LandPlan.new()
## Bus depots and school buses, which run themselves (scripts/transit/).
var buses := BusNet.new()
## Cab companies, which run themselves too.
var taxis := TaxiCo.new()
var builders := Builders.new()
## Where this city sits in the shared region (its own coordinates start at
## 0): the land under it is read there. 0 in solo play.
var terrain_offset := Vector2.ZERO:
	set(v):
		terrain_offset = v
		services.terrain_offset = v
		power.offset = v
		# Farms, companies and parks read the land under the town, not at
		# the region's corner (they were, until 2026-10-24).
		Resources.follow(v)
		_lots_dirty = true
## High schools, colleges and universities, and the town's graduates.
var education := Education.new()
## The town's phone company: its office, cell towers and fiber.
var telecom := Telecom.new()
## Banks that lend to the farms, companies and builders (see Banks).
var banks := Banks.new()
## Requests from hub leaders for big moves (track through town, crossing
## your roads), answered from the bell up top. See Permits.
var permits := Permits.new()
## Rail depots, their leaders, track and trains (see Rail).
var rail := Rail.new()
## Wild trees and brush, and how far cleared land has grown back.
var vegetation := Vegetation.new()
## Landfills, recycling and cemeteries, and the garbage trucks' rounds.
var hubs := CivicHubs.new()
## Parks (hubs that fill in by themselves) and one-per-town landmarks.
var parks := Parks.new()
## The post office, its postmaster, and the carriers on their routes.
var mail := Mail.new()
## Services shared with neighbor towns under signed deals (Interlocal).
var interlocal := Interlocal.new()
## What the region's shared projects do in this town (Regional).
var regional := Regional.new()
## The people within commuting reach, which decides what developers build
## (Market).
var market := Market.new()
## The town's other neighborhoods, out on open land (Neighborhoods).
var neighborhoods := Neighborhoods.new()
## In a region, set by RegionClient: whose land these points (town
## coordinates) are on. Returns "" when this town may build there, or why
## not. Unset in a lone town.
var land_check: Callable
## In a region: why a new neighborhood can't start at a spot ("" if it can).
var site_check: Callable
## Who owns each business, its name and its family's brand (Families).
var families := Families.new()
var _zone_keys := {}  # zone_keys() cache
var _zone_sig := []
var streets := Streets.new()
## The town's broad Funding and Growth sliders for every area and hub (no
## tax fiddling: Brawn). Set on the Economy page or a hub's panel.
var policies := Policies.new()
## What kind of town this is, from where its jobs are (TownCulture).
var culture := TownCulture.new()
## Buildings going up, stage by stage, with their crews and deliveries.
var construction := Construction.new()
## Smoke, noise and dirty ground, each traced to the source that makes it.
var pollution := Pollution.new()
## Hospitals run by their administrators, ambulances, nursing homes, daycare.
var healthcare := Healthcare.new()
## The nickname the town earns (TownNickname), its old buildings and
## historic districts (Heritage), the roadside markers for its firsts
## (HistoricMarkers), what its leaders ask of the town (LeaderAsks), and the
## record its timelapse plays back (Timelapse).
var nicknames := TownNickname.new()
var heritage := Heritage.new()
var markers := HistoricMarkers.new()
var leaders := LeaderAsks.new()
## The town's place on the real ladder: Indiana charters and federal place types.
var charter := Charter.new()
var timelapse := Timelapse.new()
## How well every owner keeps their property up, from what the town gives
## it (PropertyCare), and developers' asks to build denser (Redevelopment).
var care := PropertyCare.new()
var redevelopment := Redevelopment.new()
## Home builders who ask to build subdivisions on farmland at the edge of
## town, each with a choice of sites (Subdivisions).
var subdivisions := Subdivisions.new()
## Streets wear out and come due for resurfacing (StreetAge).
var street_age := StreetAge.new()
## The city engineer: counts rush-hour traffic and proposes fixes (CityEngineer).
var engineer := CityEngineer.new()
## The town's numbers over time, for the top bar's charts (StatHistory).
var history := StatHistory.new()
## Buildings only grow and fill with power and water, as in Cities: Skylines.
## The game turns this on; tests about other things can leave it off.
var require_utilities := false
## The balance harness turns cars off to play years of a city in seconds
## (traffic doesn't touch the budget yet).
var simulate_traffic := true
var lots := {}       # lot key -> lot Dictionary (from LotPlanner)
## Surveys lots from the roads and zones; lots with buildings are saved
## parcels that stay put.
var planner := LotPlanner.new()
var buildings := {}  # lot key -> building Dictionary (see BuildingTypes)
var tick_count := 0
var city_seed := 1

## Latest totals, worked out from the buildings.
var stats := {"population": 0, "workers": 0, "jobs": 0, "employed": 0, "commuting": 0, "homes_free": 0}
## How much each zone wants to grow, 0 to 1, like the CS demand bars.
var demand := {ZoneMap.Zone.RESIDENTIAL: 0.6, ZoneMap.Zone.COMMERCIAL: 0.0, ZoneMap.Zone.INDUSTRIAL: 0.1}

## In a shared region, your commands go to the server instead and come back
## in a tick, so every player applies them at the same moment.
var send_command := Callable()

## Road ends that lead on to the rest of the region (there's no map edge):
## the county highway's far ends. Trade, imports and through traffic come
## and go here, and nowhere else. Node ids.
var region_links: Array = []
## Miles of county road this town has joined (CountyGrid keys), now its own
## roads; the rest are scenery.
var county_joined := {}
## Miles of scenery county road the player has bulldozed away.
var county_removed := {}
## Goods and services bought from and sold to neighbors and the outside.
var trade := Trade.new()
## True in a shared region, which settles trade for every city at once.
var in_region := false
## Homes-equivalent of power neighbor towns bought from this town's power
## companies last month (from Trade), which unlocks a line to a neighbor.
## Tests can set it directly.
var neighbor_power_short := 0.0
## What the neighbouring towns make and buy, kept up to date by the region
## server (see Agency._region). Not saved: it comes from the neighbours.
var region := {}

var _lots_dirty := true
## Towns with replan_lots lots plan a zoning edit's lots over the next
## REPLAN_TICKS ticks (a road's over REPLAN_ROAD_TICKS: it touches more),
## doing REPLAN_WARM units of the work a tick (see LotPlanner.warm), then
## finishing on the tick it's due (_replan_at).
## (Tests make a small town act big.)
var replan_lots := 1500
const REPLAN_TICKS := 15
const REPLAN_ROAD_TICKS := 50
const REPLAN_WARM := 32
var _replan_at := 0
## A zoning drag still going (its commands carry "hold"): the lots are cut
## once, when it ends ("zone_done") or HOLD_TICKS after its last street.
var _hold_until := 0
const HOLD_TICKS := 50
## What the last lots_changed changed: the keys of lots added, removed or
## reshaped. lots_delta_full is true when every lot should be treated as new
## (a load, or a full replan), though the keys are still listed.
var lots_delta := []
var lots_delta_full := true
## Only zoning or roads changed: built parcels need checking only where a
## road moved (the rest can't have changed), which keeps edits in a big
## town quick.
var _lots_light := false
## Boxes where something that keeps lots off the ground changed (see
## lots_changed_near), for the next refresh to check.
var _lots_near := []
## Roads changed since the world last made way for them (see RoadWins).
var _roads_moved := false
var _usable_cache := {}  # field cell -> bool, cleared when roads or lots change
## Whether each planned lot was blocked: key -> [the lot Dictionary, bool].
## A zoning-only replan changes nothing that blocks lots, so a lot the
## planner hands back unchanged keeps its answer.
var _blocked_by := {}
## Land checks for lots by position (the terrain never changes).
var _land_ok := {}
var _zone_check := []  # what _refresh last checked buildings against
var _zone_check_lots := {}


func _init() -> void:
	Resources.follow(terrain_offset)
	lots_changed.connect(func(): _lot_rev += 1)
	# The water utility's manager takes the player's word (Permits guidance).
	permits.locators["water"] = func(c: CitySim, id: int) -> Vector2:
		var b: Dictionary = c.services.buildings.get(id, {})
		return Vector2(b.pos.x, b.pos.z) if not b.is_empty() else Vector2.INF
	planner.wealth = wealth_at
	# Campus heads take the player's word (grow, your call, hold off).
	permits.locators["campus"] = func(_sim, id: int) -> Vector2:
		var c: Dictionary = education.campuses.get(id, {"pos": Vector3.ZERO})
		return Vector2(c.pos.x, c.pos.z)
	permits.locators["warehouse"] = func(_sim, id: int) -> Vector2:
		var w = warehouses.buildings.get(id)
		var c := Vector3.ZERO if w == null else Warehouses.center(w)
		return Vector2(c.x, c.z)
	# The phone company's manager files tower requests on the bell, and takes
	# the player's word the same way.
	permits.locators["telecom"] = func(_sim, id: int) -> Vector2:
		var c: Dictionary = telecom.companies.get(id, {"pos": Vector3.ZERO})
		return Vector2(c.pos.x, c.pos.z)
	permits.costers["telecom"] = func(_sim, req: Dictionary, _route: Array, _hits: Dictionary) -> int:
		return int(req.base)
	rail.attach(self)
	# Bank presidents take the player's word too.
	permits.locators["power"] = func(_sim, id: int) -> Vector2:
		var s: Dictionary = power.sites.get(id, {"pos": Vector3.ZERO})
		return Vector2(s.pos.x, s.pos.z)
	permits.locators["bank"] = func(_sim, id: int) -> Vector2:
		var b: Dictionary = banks.banks.get(id, {"pos": Vector3.ZERO})
		return Vector2(b.pos.x, b.pos.z)
	farms.reserves = reserves
	industry.reserves = reserves
	permits.locators["farm"] = func(_sim, id: int) -> Vector2:
		var f: Dictionary = farms.farms.get(id, {"pos": Vector3.ZERO})
		return Vector2(f.pos.x, f.pos.z)
	permits.locators["industry"] = func(_sim, id: int) -> Vector2:
		var s: Dictionary = industry.sites.get(id, {"pos": Vector3.ZERO})
		return Vector2(s.pos.x, s.pos.z)
	# New businesses get their names before any view draws them, so signs go
	# up with the building (connected ahead of the views).
	for sig in [buildings_changed, farms_changed, industry_changed]:
		sig.connect(func(): families.sync(self))
	buildings_changed.connect(func(): _zone_keys = {})
	permits.costers[Families.HUB] = func(_sim, req: Dictionary, _route, _hits) -> int:
		return int(req.base)
	permits.locators[Families.HUB] = func(_sim, id: int) -> Vector2:
		return families.locate(self, id)
	_wire_policies()
	# Streets are named before any view draws their signs.
	network.changed.connect(func(): streets.sync(self))
	# The county seat: county roads count from the courthouse once it stands.
	parks_changed.connect(func(): streets.seat(self))
	_hook_pollution()
	network.changed.connect(func():
		_lots_light = true
		_roads_moved = true
		rail.roads_changed())
	vegetation.watch(self)


## Applies one player command. Returns true if anything changed (online:
## true once it's sent).
func apply(cmd: Dictionary) -> bool:
	if held:
		_held_cmds.append(cmd)
		return true
	if send_command.is_valid():
		send_command.call(cmd)
		return true
	var ok := apply_now(cmd)
	if not ok:
		command_refused.emit(cmd)
	return ok


## Applies a command right away, even online (the region does this).
## The lot keys of every building in a zone, sorted (where people shop and
## work, where freight goes). Cached until the buildings change.
func zone_keys(zone: int) -> Array:
	var sig := [buildings.size(), lots.size()]
	if _zone_keys.is_empty() or _zone_sig != sig:
		_zone_sig = sig
		_zone_keys = {ZoneMap.Zone.RESIDENTIAL: [], ZoneMap.Zone.COMMERCIAL: [], ZoneMap.Zone.INDUSTRIAL: []}
		for key in buildings:
			if lots.has(key) and _zone_keys.has(buildings[key].zone):
				_zone_keys[buildings[key].zone].append(key)
		for z in _zone_keys:
			_zone_keys[z].sort()
	return _zone_keys.get(zone, [])


func apply_now(cmd: Dictionary) -> bool:
	if cmd.get("type", "") == "undo":
		return undo.undo(self)
	var snap: Variant = undo.before(self, cmd)
	var ok := _apply_cmd(cmd)
	if ok and snap != null:
		undo.after(self, snap)
	return ok


func _apply_cmd(cmd: Dictionary) -> bool:
	var ok := false
	match cmd.get("type", ""):
		"build_road":
			var c := [_v(cmd.start), _v(cmd.ctrl), _v(cmd.end)]
			# A raised road climbs over what it crosses (Overpass).
			var pieces := [c]
			if cmd.get("over", false):
				var plan := Overpass.plan(self, c, _road(cmd))
				pieces = plan.pieces
			# The server checks real road rules too, not just the player's screen.
			if pieces.size() == 1 and road_problem(c, _road(cmd)) == "":
				ok = _build_over(c, _road(cmd))
				if ok and cmd.get("join", false):
					_join_crossings([c])
			elif pieces.size() > 1 and pieces_problem(pieces, _road(cmd)) == "":
				network.begin_batch()
				for q in pieces:
					ok = network.build_road(q[0], q[1], q[2], _road(cmd)) or ok
				network.end_batch()
				if ok:
					economy.money -= shapes_cost(pieces, _road(cmd))
					if cmd.get("join", false):
						_join_crossings(pieces)
		"join_county":
			# A road drawn onto a county road (hub roads too).
			ok = _join_county(_v(cmd.at), int(cmd.get("way", 0)))
		"remove_county":
			# Bulldozing a mile of county road that isn't the town's.
			var key := str(cmd.key)
			ok = CountyGrid.valid_key(key) and not county_removed.has(key)
			if ok:
				county_removed[key] = true
				county_changed.emit()
		"build_grid", "build_grid_shape":
			# Old three-click grids are a rectangle; new ones any shape.
			var shape: Array = GridFill.rect(_v(cmd.a), _v(cmd.b), _v(cmd.c)) if cmd.type == "build_grid" \
				else cmd.points.map(_v)
			var join: bool = cmd.get("join", false)
			var painted := painted_near(shape) if join else []
			var lines := GridFill.plan(network, shape, float(cmd.block), _road(cmd), int(cmd.get("side", 0)),
				clampf(float(cmd.get("across", RoadShapes.GRID_ACROSS)), GridFill.ACROSS_MIN, GridFill.BLOCK_MAX),
				int(cmd.get("fit", GridFill.FIT_ROUND)), painted)
			if shape.size() == 2:
				lines = [[shape[0], shape[0].lerp(shape[1], 0.5), shape[1]]]
			if lines.is_empty() or not _can_afford(lines, _road(cmd)) or land_problem(lines) != "":
				return false
			# A county road or highway the grid meets along its side becomes
			# the town's between the grid's streets, so its blocks front it.
			var taken := GridFill.taken_over(lines, painted, shape)
			network.begin_batch()
			for l in lines:
				ok = network.build_road(l[0], l[1], l[2], _road(cmd)) or ok
			# Where the town already joined that road, its gravel is taken
			# over in place (upgraded), not doubled (Brawn 2026-10-24: a
			# street laid over the joined gravel left a turnaround bulb and
			# a broken edge street). Free, as the county hands it over.
			var money_before := economy.money
			for t in taken:
				var hwy: bool = t.type == RoadStyle.Type.STATE_HWY
				for l in t.curves:
					_build_over(l, RoadStyle.Type.STATE_HWY if hwy else _road(cmd))
			economy.money = money_before
			network.end_batch()
			if ok:
				economy.money -= shapes_cost(lines, _road(cmd))
				if join:
					var all := lines.duplicate()
					for t in taken:
						all.append_array(t.curves)
					_join_crossings(all)
		"build_roundabout":
			# The size row picks the lanes; older commands took them from the road type.
			var ring := RoadShapes.ring_for_lanes(int(cmd.lanes)) if cmd.has("lanes") else RoadStyle.ring_type(_road(cmd))
			var radius := RoadShapes.roundabout_radius(float(cmd.radius), ring)
			var arcs := RoadShapes.roundabout(_v(cmd.center), radius)
			if not _can_afford(arcs, ring) or land_problem(arcs) != "":
				return false
			ok = _build_roundabout(_v(cmd.center), radius, ring)
			if ok:
				economy.money -= shapes_cost(arcs, ring)
		"remove_roundabout":
			# The whole ring goes, and the streets that met it run on to its
			# centre and meet there in a plain intersection.
			if not network.segments.has(int(cmd.seg)) or not RoadStyle.is_ring(network.segments[int(cmd.seg)].type):
				return false
			var rs := ring_of(int(cmd.seg))
			var ring_nodes := []
			var mid := Vector3.ZERO
			for id in rs:
				for n in [network.segments[id].a, network.segments[id].b]:
					if not n in ring_nodes:
						ring_nodes.append(n)
						mid += network.nodes[n]
			mid /= maxf(ring_nodes.size(), 1.0)
			var legs := []  # [where the street met the ring, its type]
			for n in ring_nodes:
				for other in network.segments_at(n):
					if not other in rs:
						legs.append([network.nodes[n], int(network.segments[other].type)])
			network.begin_batch()
			for id in rs:
				network.remove_segment(id)
			for leg in legs:
				var a: Vector3 = leg[0]
				network.build_road(a, (a + mid) * 0.5, mid, int(leg[1]), true)
			network.end_batch()
			ok = true
		"resize_roundabout":
			# A roundabout rebuilt with one or two lanes round, on the same
			# centre and size, joined to the same streets (the upgrade tool).
			if not network.segments.has(int(cmd.seg)) or not RoadStyle.is_ring(network.segments[int(cmd.seg)].type):
				return false
			var rs := ring_of(int(cmd.seg))
			var ring := RoadShapes.ring_for_lanes(int(cmd.lanes))
			var nodes := []
			var mid := Vector3.ZERO
			for id in rs:
				for n in [network.segments[id].a, network.segments[id].b]:
					if not n in nodes:
						nodes.append(n)
						mid += network.nodes[n]
			mid /= maxf(nodes.size(), 1.0)
			var r := 0.0
			for n in nodes:
				r += Vector2(network.nodes[n].x - mid.x, network.nodes[n].z - mid.z).length()
			r /= maxf(nodes.size(), 1.0)
			var same_size := not cmd.has("radius")
			if not same_size:
				var want := RoadShapes.roundabout_radius(float(cmd.radius), ring)
				same_size = absf(want - r) < 0.5
				r = want
			var arcs := RoadShapes.roundabout(mid, r)
			if network.segments[int(cmd.seg)].type == ring and same_size or not _can_afford(arcs, ring):
				return false
			network.begin_batch()
			for id in rs:
				network.remove_segment(id)
			network.end_batch()
			ok = _build_roundabout(mid, r, ring)
			if ok:
				economy.money -= shapes_cost(arcs, ring)
		"upgrade_road":
			var cost := upgrade_cost(int(cmd.seg), _road(cmd))
			if network.segments.has(int(cmd.seg)) and (RoadStyle.is_ring(network.segments[int(cmd.seg)].type)
					or RoadStyle.is_ring(_road(cmd))):
				return false  # rings change only by rebuilding the roundabout
			if cost < 0 or cost > economy.money:
				return false
			ok = network.set_type(int(cmd.seg), _road(cmd))
			if ok:
				economy.money -= cost
		"found_neighborhood":
			var at := _v(cmd.pos)
			var spot := Vector2(at.x, at.z)
			if neighborhood_problem(spot) != "":
				return false
			var from := _nearest_road_xz(spot)
			economy.money -= neighborhoods.fee()
			var name := str(cmd.get("name", "")).strip_edges().left(40)
			if name == "":
				name = Neighborhoods.side_name(spot)
			neighborhoods.add(spot, name, tick_count)
			if from.distance_to(spot) >= RoadNetwork.MIN_LENGTH:
				_county_road(from, spot, [])
			neighborhoods_changed.emit()
			ok = true
		"place_service":
			var kind := int(cmd.kind)
			if not Services.KINDS.has(kind) or charter.locked(kind) != "":
				return false
			var pos := _v(cmd.pos)
			var dir := _v(cmd.dir).normalized()
			var cost: int = services.cost_of(kind)
			if cost > economy.money or services.site_problem(network, kind, pos, dir) != "" \
					or _on_warehouse(Services.corners(kind, pos, dir)) \
					or parks.overlaps(Services.corners(kind, pos, dir).map(func(q): return Vector2(q.x, q.z))) \
					or education.covers(pos) or banks.covers(pos) or telecom.covers(pos):
				return false
			var sid := services.add(kind, pos, dir, bool(cmd.get("angled", false)) and kind in Services.PARKING)
			if kind == Services.Kind.BUILDER_YARD:
				builders.on_placed(self, sid)  # the builder's own yard is ready at once
			else:
				construction.start("svc:%d" % sid, Services.profile_of(kind), tick_count, pos, dir, Services.SETBACK
					+ RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH)
			economy.money -= cost
			if kind == Services.Kind.BUS_DEPOT:
				buses.on_placed(self, sid)
			if kind == Services.Kind.TAXI_COMPANY:
				taxis.on_placed(self, sid)
			if kind == Services.Kind.TRAFFIC_CENTER:
				traffic.engineers = true  # counting from today; retiming once it opens
			if kind == Services.Kind.WATER_UTILITY:
				services.water.found(self, sid)
				water_changed.emit()
			_clear_zones_under(services.footprint(sid))
			_lots_dirty = true
			ok = true
		"paint_reserve", "paint_farmland":
			# Older clients sent paint_farmland {points, on}.
			var pts := []
			for p in cmd.points:
				pts.append(_v(p))
			var kind := str(cmd.get("kind", "farm" if bool(cmd.get("on", true)) else ""))
			ok = reserves.paint(pts, kind)
			if ok:
				_lots_dirty = true
				_usable_cache.clear()
				_clear_reserved_zones()
				zones_changed.emit()
				farms_changed.emit()
				farms_changed.emit()
		"paint_plan":
			var pts := []
			for p in cmd.points:
				pts.append(_v(p))
			ok = land_plan.paint(pts, str(cmd.get("kind", "")))
			if ok:
				plan_changed.emit()
		"place_farmhouse":
			var pos := _v(cmd.pos)
			var dir := _v(cmd.dir).normalized()
			if dir.length() < 0.5 or farmhouse_problem(pos, dir) != "" or Farms.FARMHOUSE_COST > economy.money:
				return false
			var fid := farms.add_farm(pos, dir, str(cmd.get("crop", "corn")), farm_drive(pos, dir))
			var lane: Array = farms.farms[fid].drive
			if lane.size() >= 2:
				# The farmhouse goes up first (FarmBuilder adds the barn as the
				# farm grows). Trucks pull over where the lane meets the road.
				construction.start("farm:%d" % fid, "house", tick_count, lane[-1],
					(lane[-1] - lane[-2]).normalized(), 0.0)
			economy.money -= Farms.FARMHOUSE_COST
			_lots_dirty = true
			farms_changed.emit()
			ok = true
		"place_industry":
			var kind := str(cmd.get("kind", ""))
			var pos := _v(cmd.pos)
			var dir := _v(cmd.dir).normalized()
			if not Industry.KINDS.has(kind) or dir.length() < 0.5 or industry_problem(kind, pos, dir) != "" \
					or int(Industry.KINDS[kind].cost) > economy.money:
				return false
			var drive := industry_drive(pos, dir)
			var iid := industry.add_site(kind, pos, dir, drive)
			# The main building goes up like any steel-frame plant; the crews
			# park where its road meets the street.
			var gate: Vector3 = drive[-1] if drive.size() >= 2 else pos
			var out: Vector3 = (drive[-1] - drive[-2]).normalized() if drive.size() >= 2 else dir
			construction.start("ind:%d" % iid, "factory", tick_count, gate - out * 2.0, out, 0.5)
			economy.money -= int(Industry.KINDS[kind].cost)
			_lots_dirty = true
			industry_changed.emit()
			ok = true
		"place_warehouse":
			var kind := str(cmd.get("kind", ""))
			var pos := _v(cmd.pos)
			var dir := _v(cmd.dir).normalized()
			if not Warehouses.KINDS.has(kind) or dir.length() < 0.5 or warehouse_problem(kind, pos, dir) != "" \
					or int(Balance.WAREHOUSE[kind].cost) > economy.money:
				return false
			var wid := warehouses.add(kind, pos, dir)
			construction.start("wh:%d" % wid, "warehouse", tick_count, pos, dir, Warehouses.SETBACK
				+ RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH)
			economy.money -= int(Balance.WAREHOUSE[kind].cost)
			_clear_zones_under(warehouses.footprint(wid))
			_lots_dirty = true
			warehouses_changed.emit()
			ok = true
		"place_big_factory":
			var kind := str(cmd.get("kind", ""))
			var pos := _v(cmd.pos)
			var dir := _v(cmd.dir).normalized()
			if not BigFactories.KINDS.has(kind) or dir.length() < 0.5 or big.site_problem(self, kind, pos, dir) != "" \
					or int(Balance.BIG_FACTORY[kind].cost) > economy.money:
				return false
			var bid := big.add(self, kind, pos, dir)
			economy.money -= int(Balance.BIG_FACTORY[kind].cost)
			_clear_zones_under(BigFactories.corners(big.sites[bid]))
			_lots_dirty = true
			big_factories_changed.emit()
			ok = true
		"remove_big_factory":
			ok = big.sites.has(int(cmd.id))
			big.sites.erase(int(cmd.id))
			_lots_dirty = true
			big_factories_changed.emit()
		"remove_warehouse":
			ok = warehouses.buildings.has(int(cmd.id))
			warehouses.buildings.erase(int(cmd.id))
			_lots_dirty = true
			warehouses_changed.emit()
		"place_power":
			var pos := _v(cmd.pos)
			var dir := _v(cmd.dir).normalized()
			if dir.length() < 0.5 or power_problem(pos, dir) != "" or Balance.POWER_YARD_COST > economy.money:
				return false
			power.add_site(pos, dir, industry_drive(pos, dir), town_education(), city_seed, game_day())
			economy.money -= Balance.POWER_YARD_COST
			_lots_dirty = true
			_decide_power()
			power_changed.emit()
			ok = true
		"remove_power":
			ok = power.sites.has(int(cmd.id))
			power.sites.erase(int(cmd.id))
			if power.sites.is_empty():
				trade.offer("power", 0.0)
			_lots_dirty = true
			power_changed.emit()
		"place_campus":
			var kind := str(cmd.get("kind", ""))
			var pos := _v(cmd.pos)
			var dir := _v(cmd.dir).normalized()
			if not Education.KINDS.has(kind) or dir.length() < 0.5 or Education.site_problem(self, kind, pos, dir) != "" \
					or int(Education.spec(kind).cost) > economy.money:
				return false
			education.add(self, kind, pos, dir, city_seed, tick_count)
			economy.money -= int(Education.spec(kind).cost)
			_clear_zones_under(Education.block_corners({"pos": pos, "dir": dir}, Vector2i.ZERO))
			_lots_dirty = true
			education_changed.emit()
			ok = true
		"place_bank":
			var kind := str(cmd.get("kind", ""))
			var pos := _v(cmd.pos)
			var dir := _v(cmd.dir).normalized()
			if not Banks.KINDS.has(kind) or dir.length() < 0.5 or Banks.site_problem(self, kind, pos, dir) != "" \
					or int(Banks.spec(kind).cost) > economy.money:
				return false
			banks.add(self, kind, pos, dir, city_seed, tick_count)
			economy.money -= int(Banks.spec(kind).cost)
			_clear_zones_under(Banks.block_corners({"pos": pos, "dir": dir}, Vector2i.ZERO))
			_lots_dirty = true
			banks_changed.emit()
			ok = true
		"remove_bank":
			ok = banks.banks.erase(int(cmd.id))
			_lots_dirty = true
			banks_changed.emit()
		"remove_bank_block":
			ok = banks.remove_at(_v(cmd.pos))
			_lots_dirty = true
			banks_changed.emit()
		"remove_campus":
			ok = education.campuses.erase(int(cmd.id))
			_lots_dirty = true
			education_changed.emit()
		"remove_campus_block":
			ok = education.remove_at(_v(cmd.pos))
			_lots_dirty = true
			education_changed.emit()
		"set_campus_funding":
			ok = education.campuses.has(int(cmd.id))
			if ok:
				# A campus's funding is its Funding slider on the Economy page.
				policies.set_step("campus:%d" % int(cmd.id), "funding",
					clampi(int(cmd.level), 0, Balance.EDUCATION_FUNDING_LEVELS.size() - 1))
				_sync_levers()
				update_stats()
		"place_telecom":
			var pos := _v(cmd.pos)
			var dir := _v(cmd.dir).normalized()
			if dir.length() < 0.5 or Telecom.site_problem(self, pos, dir) != "" or Balance.TELECOM_COST > economy.money:
				return false
			telecom.add(self, pos, dir, city_seed, tick_count)
			economy.money -= Balance.TELECOM_COST
			_clear_zones_under(Telecom.block_corners({"pos": pos, "dir": dir}, Vector2i.ZERO))
			_lots_dirty = true
			telecom_changed.emit()
			ok = true
		"remove_telecom":
			ok = telecom.companies.erase(int(cmd.id))
			telecom.mark_dirty()
			_lots_dirty = true
			telecom_changed.emit()
		"remove_telecom_at":
			ok = telecom.remove_at(_v(cmd.pos))
			_lots_dirty = true
			telecom_changed.emit()
		"set_telecom_funding":
			ok = telecom.companies.has(int(cmd.id))
			if ok:
				telecom.companies[int(cmd.id)].funding = clampi(int(cmd.level), 0, Balance.TELECOM_FUNDING_LEVELS.size() - 1)
				# The grant is the company's Funding slider on the Economy page.
				_adopt_levers("telecom:%d" % int(cmd.id))
				update_stats()
		"remove_industry":
			ok = industry.sites.has(int(cmd.id))
			industry.sites.erase(int(cmd.id))
			_lots_dirty = true
			industry_changed.emit()
		"remove_farm":
			ok = farms.farms.has(int(cmd.id))
			farms.farms.erase(int(cmd.id))
			_lots_dirty = true
			farms_changed.emit()
		"place_park":
			var kind := str(cmd.get("kind", ""))
			var pos := _v(cmd.pos)
			var dir := _v(cmd.dir).normalized()
			var size_class := int(cmd.get("size", 0))  # Balance.PARK_SIZES, parks only
			if not Parks.KINDS.has(kind) or dir.length() < 0.5 or Parks.cost_of(kind, size_class) > economy.money \
					or parks.site_problem(self, kind, pos, dir, size_class) != "":
				return false
			var pid := parks.add(self, kind, pos, dir, size_class)
			economy.money -= Parks.cost_of(kind, size_class)
			_clear_zones_under(parks.footprint(pid))
			_lots_dirty = true
			parks_changed.emit()
			ok = true
		"remove_park":
			ok = parks.sites.has(int(cmd.id))
			parks.sites.erase(int(cmd.id))
			_lots_dirty = true
			parks_changed.emit()
		"set_water_subsidy":
			# The player's one lever on the water utility: its monthly subsidy.
			ok = services.water.set_subsidy(int(cmd.id), int(cmd.amount))
			if ok:
				# An exact amount: the Economy page's slider shows the nearest step.
				_adopt_levers("water:%d" % int(cmd.id))
				update_stats()
			return ok
		"remove_service":
			ok = services.buildings.has(int(cmd.id))
			services.buildings.erase(int(cmd.id))
			if ok and traffic.engineers and not _signal_engineers():
				traffic.engineers_gone()  # the engineers leave with their center
			_lots_dirty = true
		"place_hub", "upgrade_hub", "remove_hub":
			ok = _hub_command(cmd)
		"move":
			# Move It: slide, turn or raise what the player placed (MoveIt).
			ok = MoveIt.apply(self, cmd)
		"fund_cleanup", "noise_wall", "quiet_zone":
			ok = pollution.command(self, cmd)
		"set_difficulty":
			# A city that hasn't started yet also gets that difficulty's start money.
			ok = economy.set_difficulty(str(cmd.difficulty), tick_count == 0 and network.segments.size() <= 2)
			if ok:
				update_stats()
			return ok
		"set_tax":
			if economy.set_tax(int(cmd.zone), float(cmd.rate)):
				update_stats()
			return true
		"build_county_road":
			ok = not _county_road(Vector2(cmd.a[0], cmd.a[1]), Vector2(cmd.b[0], cmd.b[1]), cmd.get("links", [])).has(-1)
		"remove_road":
			ok = network.segments.has(int(cmd.seg)) and not is_link_segment(int(cmd.seg))
			if ok:
				_note_county_removed(int(cmd.seg))
				network.remove_segment(int(cmd.seg))
		"paint_zone":
			zones.paint(_v(cmd.center), float(cmd.radius), int(cmd.zone))
			_clear_reserved_zones(_v(cmd.center), float(cmd.radius) + ZoneMap.CELL)
			_usable_cache.clear()
			_lots_light = true
			ok = true
		"set_bus_subsidy":
			ok = buses.apply(self, cmd)
			if ok:
				_adopt_levers("bus_depot:%d" % int(cmd.id))
		"zone_done":
			# The zoning drag ended: its lots are cut now.
			_hold_until = 0
			ok = true
		"zone_frontage":
			# Zones a whole block face: one side of a street from junction to
			# junction ("both" does the other side too, "single" only this
			# piece of street, not on round bends).
			if not network.segments.has(int(cmd.seg)):
				return false
			planner.update(network)
			var sides := [int(cmd.side)]
			if bool(cmd.get("both", false)):
				sides.append(-int(cmd.side))
			# "span": [from, to] metres along the street, just that stretch
			# (a drag over part of a block face).
			var span: Array = cmd.get("span", [])
			for side in sides:
				var parts := [[int(cmd.seg), side]] if bool(cmd.get("single", false)) or not span.is_empty() \
					else frontage_chain(int(cmd.seg), side)
				for part in parts:
					if span.size() == 2:
						_paint_frontage(part[0], part[1], int(cmd.zone), float(span[0]), float(span[1]))
					else:
						_paint_frontage(part[0], part[1], int(cmd.zone))
			_clear_reserved_zones()
			_usable_cache.clear()
			_lots_light = true
			ok = true
		"permit":
			ok = permits.answer(self, cmd)
		"place_rail_depot":
			var pos := _v(cmd.pos)
			var dir := _v(cmd.dir).normalized()
			var axis := _v(cmd.axis).normalized()
			if dir.length() < 0.5 or rail.site_problem(self, pos, dir, axis) != "" \
					or Balance.RAIL_DEPOT_COST > economy.money:
				return false
			rail.add_depot(self, pos, dir, axis)
			economy.money -= Balance.RAIL_DEPOT_COST
			_clear_zones_under(Rail.yard_corners(pos, dir, axis))
			_lots_dirty = true
			ok = true
		"remove_rail_depot":
			ok = rail.depots.has(int(cmd.id))
			if ok:
				rail.remove_depot(self, int(cmd.id))
				_lots_dirty = true
		"rail_subsidy":
			ok = rail.set_subsidy(int(cmd.id), int(cmd.monthly))
		"guide":
			# The player's word to a hub's leader (grow, hold off, pre-approve).
			ok = permits.guide(self, cmd)
			var key := "%s:%d" % [str(cmd.get("hub", "")), int(cmd.get("hub_id", 0))]
			if ok and hub_area(key) != "":
				# Growth is the same word: keep the hub's slider in step.
				var now := policies.step("growth", hub_area(key), key)
				var want := Policies.growth_for(str(cmd.get("stance", "steady")), now)
				if want != now:
					policies.set_step(key, "growth", want)
		"end_deal":
			# Notice to end a service deal with a neighbor town.
			ok = interlocal.end(self, str(cmd.get("id", "")))
		"policy":
			# A Funding or Growth slider for the town, an area or one hub.
			ok = _set_policy(str(cmd.get("scope", "")), str(cmd.get("slider", "")), int(cmd.get("step", -1)))
		"policy_reset":
			# Everything under the town or an area follows it again.
			ok = policies.reset_below(str(cmd.get("scope", "")), hub_area)
			if ok:
				_sync_stances()
				_sync_levers()
		"heritage":
			# Protect a historic district, or lift its protection.
			ok = heritage.set_protected(self, int(cmd.get("district", -1)), bool(cmd.get("protect", true)))
		"set_junction":
			# Traffic lights, stop signs or none at a junction (-1 = automatic).
			ok = traffic.set_rule(int(cmd.node), int(cmd.rule))
		"link_wave":
			# A green wave: light `to` timed behind light `from` at the limit.
			ok = traffic.link_wave(int(cmd.from), int(cmd.to), float(cmd.get("v", 15.6)))
		"set_actuated":
			# A smart light: sensors decide when each way gets its green.
			ok = traffic.set_actuated(int(cmd.node), bool(cmd.on))
		"set_offset":
			ok = traffic.set_offset(int(cmd.node), float(cmd.seconds))
		"set_green":
			# How long one direction's green lasts at a light (0 = automatic).
			ok = traffic.set_green(int(cmd.node), int(cmd.phase), float(cmd.seconds))
		"place_post_office", "remove_post_office", "post_office_funding":
			ok = mail.command(self, cmd)
			if ok and cmd.type != "post_office_funding":
				_lots_dirty = true
			elif ok:
				_adopt_levers("post_office:%d" % int(cmd.id))
		"clear":
			# Starting over keeps the way out: the county highways to the
			# neighbouring towns (trade comes and goes on them), rebuilt
			# after the wipe, with a crossroads to start the town from.
			var links_kept := _link_roads()
			undo = UndoLog.new()
			region_links.clear()
			trade = Trade.new()
			traffic.overrides.clear()
			traffic.from_dict({})
			people = People.new()
			network.clear()
			# The county has its roads back.
			county_joined.clear()
			county_removed.clear()
			county_changed.emit()
			zones.cells.clear()
			planner = LotPlanner.new()
			_ground_was = {}
			_lots_touched.clear()
			planner.wealth = wealth_at
			var diff := economy.difficulty
			economy = Economy.new()
			economy.set_difficulty(diff, true)
			services = Services.new()
			farms = Farms.new()
			industry = Industry.new()
			power = Power.new()
			power.offset = terrain_offset
			logistics = Logistics.new()
			construction = Construction.new()
			warehouses = Warehouses.new()
			big = BigFactories.new()
			big_factories_changed.emit()
			reserves = Reserves.new()
			land_plan = LandPlan.new()
			buses = BusNet.new()
			taxis = TaxiCo.new()
			builders = Builders.new()
			education = Education.new()
			telecom = Telecom.new()
			banks = Banks.new()
			banks_changed.emit()
			permits.from_dict({})
			rail = Rail.new()
			rail.attach(self)
			families.from_dict({})
			families.changed.emit()
			streets.from_dict(self, {})
			hubs = CivicHubs.new()
			parks = Parks.new()
			parks_changed.emit()
			mail = Mail.new()
			neighborhoods = Neighborhoods.new()
			neighborhoods_changed.emit()
			policies.from_dict({})
			culture.from_dict({})
			nicknames.from_dict({})
			heritage.from_dict({})
			markers.from_dict({})
			leaders.from_dict({})
			care.from_dict({})
			redevelopment.from_dict({})
			subdivisions.from_dict({})
			street_age.from_dict({})
			engineer.from_dict({})
			timelapse.from_dict(self, {})
			history.from_dict({})
			_lever_steps.clear()
			pollution = Pollution.new()
			_hook_pollution()
			healthcare = Healthcare.new()
			farms.reserves = reserves
			industry.reserves = reserves
			vegetation.reset()
			_wire_policies()
			farms_changed.emit()
			industry_changed.emit()
			warehouses_changed.emit()
			power_changed.emit()
			education_changed.emit()
			telecom_changed.emit()
			for road in links_kept:
				_county_road(road[0], road[1], road[2])
			_start_crossroads()
			ok = true
	if ok:
		if cmd.type in ["place_campus", "place_park", "place_bank", "place_hub", "place_service", "place_farmhouse",
				"place_industry", "place_post_office", "place_warehouse", "place_power", "place_telecom", "clear"]:
			# A new hub takes its area's sliders (and its leader the stance).
			_sync_levers()
			_sync_stances()
		var roads := _roads_moved
		if roads:
			_road_wins()
		if bool(cmd.get("hold", false)) and not _lots_dirty:
			# Mid-drag: the zones show now, the lots when the drag ends.
			_hold_until = tick_count + HOLD_TICKS
		elif not _lots_dirty and _lots_light and lots.size() >= replan_lots:
			# A big town: the road or zoning is in at once, and its lots
			# catch up over a few ticks, so no single tick does it all (the
			# same ticks on every copy).
			_replan_at = maxi(_replan_at, tick_count + (REPLAN_ROAD_TICKS if roads else REPLAN_TICKS))
		else:
			_replan_at = 0
			_refresh()
		zones_changed.emit()
		command_applied.emit(cmd)
	return ok


## Saves from before region links: trucks used to leave by the dead end
## farthest from the middle of town, so a county highway now runs on from
## there 2 km toward the region, and its far end is the town's way out.
func _guess_link() -> void:
	if network.nodes.is_empty():
		return
	var mid := Vector3.ZERO
	for n in network.nodes:
		mid += network.nodes[n]
	mid /= network.nodes.size()
	var best := -1
	var best_d := -1.0
	var ids := network.nodes.keys()
	ids.sort()
	for n in ids:
		if network.segments_at(n).size() == 1 and network.nodes[n].distance_to(mid) > best_d + 0.01:
			best_d = network.nodes[n].distance_to(mid)
			best = n
	if best == -1:
		return
	var seg: Dictionary = network.segments[network.segments_at(best)[0]]
	var end: Vector3 = network.nodes[best]
	var out: Vector3 = end - seg.ctrl
	out.y = 0.0
	if out.length() < 0.1:
		out = end - mid
	out = out.normalized() * 2000.0
	_county_road(Vector2(end.x, end.z), Vector2(end.x + out.x, end.z + out.z), [1])


## What a road not built yet would wipe out (Brawn 2026-10-24: a grid drawn
## over a park that had grown for years took it with no warning): every
## park, landmark, hub building and built lot its ground takes, as
## _road_wins would clear them. Fields and pads it only trims are left
## out. Each: {what, at, named} (named: `what` is the place's own name).
func road_losses(curves: Array, type: int) -> Array:
	var out := []
	if curves.is_empty():
		return out
	var corr := RoadWins.corridors_of(curves, type, RoadWins.BUILDING_SLACK)
	var box: Rect2 = corr[0].bounds
	for c in corr:
		box = box.merge(c.bounds)
	var hit := func(poly: PackedVector2Array) -> bool:
		return box.intersects(RoadWins._bounds(poly)) and RoadWins.hits(corr, poly)
	for id in parks.sites:
		var s: Dictionary = parks.sites[id]
		if hit.call(parks.footprint(id)):
			out.append({"what": str(s.get("name", Parks.KINDS[s.kind].name)), "at": s.pos, "named": true})
	for id in services.buildings:
		if hit.call(services.footprint(id)):
			out.append({"what": Services.KINDS[services.buildings[id].kind].name, "at": services.buildings[id].pos})
	for id in farms.farms:
		if hit.call(farms._yard(farms.farms[id])):
			out.append({"what": "Farmhouse", "at": farms.farms[id].pos})
	for id in industry.sites:
		if hit.call(industry._yard(industry.sites[id])):
			out.append({"what": Industry.KINDS[industry.sites[id].kind].name, "at": industry.sites[id].pos})
	for id in warehouses.buildings:
		var w: Dictionary = warehouses.buildings[id]
		if not Warehouses.is_store(w) and hit.call(warehouses.footprint(id)):
			out.append({"what": Warehouses.KINDS[w.kind].name, "at": w.pos})
	for id in power.sites:
		if hit.call(power.yard(power.sites[id])):
			out.append({"what": "Power plant", "at": power.sites[id].pos})
	for id in big.sites:
		if hit.call(BigFactories.corners(big.sites[id])):
			out.append({"what": "Factory", "at": big.sites[id].pos})
	for key in buildings:
		if lots.has(key) and hit.call(lots[key].corners):
			var b: Dictionary = buildings[key]
			var what := "Home" if int(b.zone) == ZoneMap.Zone.RESIDENTIAL else "Building"
			var mid := Vector2.ZERO
			for q in lots[key].corners:
				mid += q
			mid /= maxf(1.0, lots[key].corners.size())
			out.append({"what": what, "at": Vector3(mid.x, 0.0, mid.y)})
	return out


## The road wins (Brawn): whatever a new road runs through makes way for it.
## Buildings the player paid for are bulldozed and paid back, fields are
## trimmed to the road's edge, cut lanes find the nearest road again, and
## pads that are hit close (the company reopens them elsewhere).
func _road_wins() -> void:
	_roads_moved = false
	_usable_cache.clear()
	var corr := RoadWins.corridors(network, RoadWins.BUILDING_SLACK)
	var field_corr := RoadWins.corridors(network, RoadWins.VERGE)
	var ids := services.buildings.keys()
	ids.sort()
	for id in ids:
		if RoadWins.hits(corr, services.footprint(id)):
			economy.money += int(Services.KINDS[services.buildings[id].kind].cost)
			services.buildings.erase(id)
			_lots_dirty = true
	var lane_end := RoadStyle.right_of_way_half(RoadStyle.Type.BOULEVARD) + RoadWins.VERGE + 4.0
	ids = farms.farms.keys()
	ids.sort()
	farms.trim.clear()
	for id in ids:
		var f: Dictionary = farms.farms[id]
		if RoadWins.hits(corr, farms._yard(f)):
			economy.money += Farms.FARMHOUSE_COST
			farms.farms.erase(id)
			continue
		# County roads and highways the town hasn't built cross farm country
		# too: fields stop at their right of way like at any road's.
		var shape := []
		for c in f.cells:
			for q in Farms.cell_corners(f, c):
				shape.append(Vector3(q.x, 0.0, q.y))
		var roads := field_corr + RoadWins.painted(painted_near(shape), RoadWins.VERGE) if not shape.is_empty() else field_corr
		for c in f.cells.duplicate():
			var cell := Farms.cell_corners(f, c)
			if not RoadWins.hits(roads, cell):
				continue
			var left := RoadWins.clip(roads, cell)
			var kept := 0.0
			for piece in left:
				kept += RoadWins.area(piece)
			if kept < RoadWins.MIN_FIELD_SHARE * Farms.CELL * Farms.CELL:
				f.cells.erase(c)
			else:
				if not farms.trim.has(id):
					farms.trim[id] = {}
				farms.trim[id][c] = left
		if RoadWins.cuts(corr, f.drive, lane_end):
			var lane := farm_drive(f.pos, f.dir)
			if not lane.is_empty():
				f.drive = lane
	ids = industry.sites.keys()
	ids.sort()
	for id in ids:
		var s: Dictionary = industry.sites[id]
		if RoadWins.hits(corr, industry._yard(s)):
			economy.money += int(Industry.KINDS[s.kind].cost)
			industry.sites.erase(id)
			continue
		for c in s.pads.duplicate():
			if RoadWins.hits(corr, Industry.pad_corners(s, c)):
				s.pads.erase(c)
		if RoadWins.cuts(corr, s.drive, lane_end):
			var lane := industry_drive(s.pos, s.dir)
			if not lane.is_empty():
				s.drive = lane
	ids = warehouses.buildings.keys()
	ids.sort()
	for id in ids:
		if not Warehouses.is_store(warehouses.buildings[id]) and RoadWins.hits(corr, warehouses.footprint(id)):
			economy.money += int(Balance.WAREHOUSE[warehouses.buildings[id].kind].cost)
			warehouses.buildings.erase(id)
			_lots_dirty = true
	if big.road_wins(self, corr):
		_lots_dirty = true
		big_factories_changed.emit()
	if parks.road_wins(self, corr):
		_lots_dirty = true
		parks_changed.emit()
	ids = power.sites.keys()
	ids.sort()
	for id in ids:
		var s: Dictionary = power.sites[id]
		if RoadWins.hits(corr, power.yard(s)):
			economy.money += Balance.POWER_YARD_COST
			power.sites.erase(id)
			continue
		for c in s.cells.duplicate():
			if RoadWins.hits(corr, Power.cell_corners(s, c)):
				s.cells.erase(c)
		if RoadWins.cuts(corr, s.drive, lane_end):
			var lane := industry_drive(s.pos, s.dir)
			if not lane.is_empty():
				s.drive = lane
	# Lots are planned again only if a road took some of a hub's ground.
	if not education.campuses.is_empty():
		var was := hash(education.campuses)
		economy.money += education.make_way(corr)
		if hash(education.campuses) != was:
			_lots_dirty = true
	if not telecom.companies.is_empty():
		var was := hash(telecom.companies)
		economy.money += telecom.make_way(corr)
		if hash(telecom.companies) != was:
			_lots_dirty = true
		telecom_changed.emit()
	if not banks.banks.is_empty():
		var was := hash(banks.banks)
		economy.money += banks.make_way(corr)
		if hash(banks.banks) != was:
			_lots_dirty = true
	farms_changed.emit()
	industry_changed.emit()
	warehouses_changed.emit()
	education_changed.emit()
	power_changed.emit()
	banks_changed.emit()


func tick() -> void:
	var t0 := Perf.now()
	tick_count += 1
	var t := Perf.now()
	if _replan_at > tick_count or _hold_until > tick_count:
		planner.warm(network, zones, _parcel_lots, _lot_blocked, REPLAN_WARM)
		Perf.add("sim.lots.warm", t)
	_refresh()
	Perf.add("sim.lots", t)
	if tick_count % COUNTY_ENDS_EVERY == 7:
		_extend_county_ends()
	t = Perf.now()
	vegetation.update(self)
	Perf.add("sim.vegetation", t)
	t = Perf.now()
	if tick_count % MOVE_EVERY == 0:
		_move_in()
	Perf.add("sim.people", t)
	t = Perf.now()
	if tick_count % MOVE_EVERY == 0:
		# The homes' scan and the budget's buildings go a slice at a time; the
		# budget only pays out on the hour (slice 0).
		var slice := (tick_count / MOVE_EVERY) % Economy.SLICES
		update_stats(false, slice)
		economy.budget_step(self, slice)
	Perf.add("sim.stats", t)
	t = Perf.now()
	if tick_count % GROW_EVERY == 0 and _replan_at == 0:
		_grow_one()
		# A builder with a construction loan from a bank in town puts up one more.
		if not banks.banks.is_empty() and banks.builds_more(self):
			var key := _grow_one(1)
			if key != "":
				banks.financed(self, key)
	Perf.add("sim.growth", t)
	t = Perf.now()
	if tick_count % Balance.DEVELOP_EVERY == 0 and _replan_at == 0:
		_develop_one()
	if tick_count % TICKS_PER_HOUR == 50:
		_decline()
	if tick_count % Farms.DECIDE_EVERY == 0 and not farms.farms.is_empty():
		farms.tax_rate = economy.tax[ZoneMap.Zone.INDUSTRIAL]
		farms.price = Farms.price_on(tick_count / (24.0 * TICKS_PER_HOUR))
		farms.day = game_day()
		# Each January the farm leaders plan the year's crops (CropPlan).
		var crop_year := Seasons.year(tick_count)
		if crop_year != farms.year:
			farms.demand = CropPlan.demand(self)
			if not farms.slope_of.is_valid():
				farms.slope_of = func(p: Vector3) -> float:
					return Terrain.slope(p.x + terrain_offset.x, p.z + terrain_offset.y)
			farms.year = crop_year
		var ground := farms.ground_boxes()
		var farmed := farms.decide(field_usable)
		var others := false
		# Where the town has made the land worth far more to developers,
		# a farm family may ask to sell out.
		if _farm_sell_outs():
			farmed = true
			others = true
			_usable_cache.clear()
		# Hog, dairy and turkey barns and beef herds, picked by farm leaders.
		if Livestock.step(self):
			farmed = true
			others = true
			_usable_cache.clear()
		if others:
			_lots_dirty = true  # lots under new fields go away
		elif farmed:
			# Fields planted or given up: only lots by those farms can change.
			# The lots are planned again all the same, as after any change.
			lots_changed_near(_farm_boxes(ground, farms.ground_boxes()))
			_lots_light = true
		if farmed:
			farms_changed.emit()
	Perf.add("sim.farms", t)
	t = Perf.now()
	if tick_count % Industry.DECIDE_EVERY == Balance.ROUND_AT.industry and not industry.sites.is_empty():
		industry.tax_rate = economy.tax[ZoneMap.Zone.INDUSTRIAL]
		industry.day = tick_count / (24.0 * TICKS_PER_HOUR)
		industry.road_between = road_between
		if industry.decide(field_usable):
			_lots_dirty = true
			industry_changed.emit()
	Perf.add("sim.industry", t)
	t = Perf.now()
	if tick_count % Balance.EDUCATION_DECIDE_EVERY == 0 and not education.campuses.is_empty():
		if education.decide(self):
			_lots_dirty = true
			education_changed.emit()
	Perf.add("sim.education", t)
	t = Perf.now()
	if tick_count % Balance.TELECOM_DECIDE_EVERY == 0 and not telecom.companies.is_empty():
		if telecom.decide(self):
			_lots_dirty = true
			telecom_changed.emit()
	Perf.add("sim.telecom", t)
	t = Perf.now()
	# Farms and companies that want the land next door ask the banks for a loan.
	if tick_count % Balance.BANK_LEND_EVERY == 0 and not banks.banks.is_empty():
		_bank_changes(banks.lend(self))
	if tick_count % Balance.BANK_DECIDE_EVERY == 0 and not banks.banks.is_empty():
		_bank_changes(banks.decide(self))
	Perf.add("sim.banks", t)
	t = Perf.now()
	if tick_count % Balance.WAREHOUSE_DECIDE_EVERY == Balance.ROUND_AT.warehouses and not warehouses.buildings.is_empty():
		if warehouses.decide(self):
			_lots_dirty = true
			warehouses_changed.emit()
	Perf.add("sim.warehouses", t)
	t = Perf.now()
	permits.tick(self)
	Perf.add("sim.permits", t)
	t = Perf.now()
	# Events at the fairgrounds and the football field, and their visitors.
	if not parks.tourism.venues.is_empty():
		parks.tourism.tick(self)
	Perf.add("sim.tourism", t)
	t = Perf.now()
	if tick_count % Balance.PARK_DECIDE_EVERY == Balance.ROUND_AT.parks and not parks.sites.is_empty():
		var sizes := parks.sites.values().map(func(s): return s.size)
		if parks.decide(self):
			if parks.sites.values().map(func(s): return s.size) != sizes:
				# A park bought land: lots and zoning under it go away.
				for id in parks.sites:
					_clear_zones_under(parks.footprint(id))
				_lots_dirty = true
				zones_changed.emit()
			parks_changed.emit()
	Perf.add("sim.parks", t)
	t = Perf.now()
	if tick_count % Power.DECIDE_EVERY == Balance.ROUND_AT.power and not power.sites.is_empty():
		if _decide_power():
			power_changed.emit()
	Perf.add("sim.power", t)
	t = Perf.now()
	# Once a month every hub's leader looks at its development tree (Agency).
	if tick_count % (24 * TICKS_PER_HOUR) == 12 * TICKS_PER_HOUR:
		_develop_hubs()
		if not neighborhoods.sites.is_empty():
			var before := neighborhoods.sites.size()
			neighborhoods.check(self)
			if neighborhoods.sites.size() != before:
				neighborhoods_changed.emit()
	Perf.add("sim.hub_leaders", t)
	t = Perf.now()
	# The town's character drifts toward where its jobs are.
	if tick_count % (24 * TICKS_PER_HOUR) == 11 * TICKS_PER_HOUR:
		culture.update(self, tick_count / (24 * TICKS_PER_HOUR))
	# A developer looks for land an hour later, so no tick carries both.
	elif tick_count % (24 * TICKS_PER_HOUR) == 12 * TICKS_PER_HOUR:
		if culture.develop(self):
			_usable_cache.clear()
			_lots_dirty = true
			farms_changed.emit()
			zones_changed.emit()
	# ...and every family looks at what it owns, and whether to branch out.
	if tick_count % (24 * TICKS_PER_HOUR) == 13 * TICKS_PER_HOUR:
		families.month(self)
	Perf.add("sim.families", t)
	t = Perf.now()
	# The town's story, one part an hour so no tick carries it all: its
	# districts, charm, firsts, nickname and leaders' asks, and the
	# timelapse's record.
	var hour := tick_count % (24 * TICKS_PER_HOUR)
	if hour == 14 * TICKS_PER_HOUR:
		heritage.month(self)
	elif hour == 15 * TICKS_PER_HOUR:
		heritage.month_charm(self)
	elif hour == 16 * TICKS_PER_HOUR:
		markers.month(self)
	elif hour == 17 * TICKS_PER_HOUR:
		nicknames.month(self)
		leaders.month(self)
	elif hour == 18 * TICKS_PER_HOUR:
		charter.month(self)
		timelapse.month(self)
	if tick_count % TICKS_PER_HOUR == 0:
		history.hour(self)
	if tick_count % TICKS_PER_HOUR == 30:
		heritage.carry_out(self)
		leaders.carry_out(self)
		charter.carry_out(self)
		redevelopment.carry_out(self)
		if subdivisions.carry_out(self):
			farms_changed.emit()
		subdivisions.works(self)
	Perf.add("sim.heritage", t)
	t = Perf.now()
	# Every owner looks after their property, a slice of town an hour;
	# developers ask to build denser in the evening.
	if hour == 5:
		care.start_month(self)
	elif hour % 30 == 10:
		if care.slice(self, (hour / 30) % PropertyCare.SLICES):
			buildings_changed.emit()
	Perf.add("sim.care", t)
	if hour == 19 * TICKS_PER_HOUR + 50:
		t = Perf.now()
		redevelopment.month(self)
		Perf.add("sim.redevelop", t)
	elif hour == 20 * TICKS_PER_HOUR + 20:
		# Home builders: the next phase of a subdivision, or start scouting
		# for land for a new one...
		t = Perf.now()
		subdivisions.month(self)
		Perf.add("sim.subdivisions", t)
	elif hour == 20 * TICKS_PER_HOUR + 40:
		# Streets that have worn out are resurfaced, on the town's bill.
		t = Perf.now()
		economy.money -= street_age.month(self)
		Perf.add("sim.street_age", t)
	elif hour == 21 * TICKS_PER_HOUR + 10:
		# The city engineer brings the month's worst traffic problem.
		t = Perf.now()
		engineer.month(self)
		Perf.add("sim.engineer", t)
	if tick_count % TICKS_PER_HOUR == 20 and not subdivisions.scout.is_empty():
		# Home builders scout a few roads an hour.
		t = Perf.now()
		subdivisions.hour(self)
		Perf.add("sim.subdivisions", t)
	if hour % TICKS_PER_HOUR == 15 and hour / TICKS_PER_HOUR in Balance.ENGINEER_COUNT_HOURS:
		# The engineer's traffic counts, at rush hour.
		t = Perf.now()
		engineer.count(self)
		Perf.add("sim.engineer", t)
	if tick_count % TICKS_PER_HOUR == 35 and not engineer.pending.is_empty() and engineer.carry_out(self):
		_lots_dirty = true
	if tick_count % TrafficSim.RETUNE_EVERY == 45:
		# The traffic engineers (a Traffic Management Center, or a
		# university's transportation research center) retime the lights.
		var here := _signal_engineers()
		if here and not traffic.engineers:
			traffic.engineers = true
		elif not here and traffic.engineers:
			traffic.engineers_gone()
		if traffic.engineers and construction.is_done("svc:%d" % services.traffic_center(), tick_count):
			traffic.retune(tick_count)
	t = Perf.now()
	if tick_count % WaterUtility.DECIDE_EVERY == Balance.ROUND_AT.water and not services.water.utilities.is_empty():
		var res := services.water.decide(self, yard_usable)
		economy.money += int(res[1])
		if res[0]:
			_lots_dirty = true  # lots under new yard pieces go away
			water_changed.emit()
	Perf.add("sim.water", t)
	# Taxes come in and upkeep goes out every game hour, a day settling a month.
	if tick_count % TICKS_PER_HOUR == 0:
		economy.money += roundi(economy.monthly_net() / 24.0)
	# Before trade settles: last month's deals, and this month's asks.
	big.tick(self)
	if big.take_changed():
		_lots_dirty = true
		big_factories_changed.emit()
	# Before logistics, which clears Traffic's arrivals.
	t = Perf.now()
	hubs.tick(self)
	construction.tick(self)
	if simulate_traffic:
		power.crew_tick(self)
	Perf.add("sim.civic_hubs", t)
	if not in_region and tick_count % (24 * TICKS_PER_HOUR) == 0:
		t = Perf.now()
		Trade.settle({"me": self}, {})
		Perf.add("sim.trade", t)
	t = Perf.now()
	mail.tick(self)
	Perf.add("sim.mail", t)
	t = Perf.now()
	interlocal.tick(self)
	Perf.add("sim.interlocal", t)
	t = Perf.now()
	rail.tick(self)
	Perf.add("sim.rail", t)
	# After rail, so a loaded copy has its grade crossings back first.
	t = Perf.now()
	pollution.tick(self)
	Perf.add("sim.pollution", t)
	t = Perf.now()
	healthcare.tick(self)
	Perf.add("sim.healthcare", t)
	if not simulate_traffic:
		Perf.add("sim.tick", t0)
		return
	t = Perf.now()
	# Before logistics, which clears Traffic's arrival list.
	for id in buses.tick(self) + taxis.tick(self) + builders.tick(self):
		_clear_zones_under(services.footprint(id))
		_lots_dirty = true
	Perf.add("sim.buses", t)
	t = Perf.now()
	logistics.tick(self)
	Perf.add("sim.logistics", t)
	t = Perf.now()
	var prng := RandomNumberGenerator.new()
	prng.seed = hash([city_seed, tick_count, "people"])
	people.sync(self, traffic, prng)
	people.plan(self, traffic, prng)
	Perf.add("sim.people", t)
	t = Perf.now()
	education.trips(self)
	telecom.trips(self)
	Perf.add("sim.school_trips", t)
	t = Perf.now()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([city_seed, tick_count, "traffic"])
	traffic.step(self, rng)
	Perf.add("sim.traffic", t)
	Perf.count("vehicles", traffic.cars.size())
	Perf.add("sim.tick", t0)


## The town's heritage, firsts, nickname, leaders' asks and timelapse record
## all at once (tests and tools; the tick spreads them over the afternoon).
func town_month() -> void:
	heritage.month(self)
	heritage.month_charm(self)
	markers.month(self)
	nicknames.month(self)
	leaders.month(self)
	charter.month(self)
	timelapse.month(self)


## Game time as a Dictionary (year, month, day, weekday, hour, minute).
## A game day settles a month, so the month and year follow Seasons.
func clock() -> Dictionary:
	var t := Time.get_datetime_dict_from_unix_time(START_UNIX + tick_count * MINUTES_PER_TICK * 60)
	t.month = Seasons.month(tick_count)
	t.year = Seasons.year(tick_count)
	return t


## Recounts people and jobs, then works out demand the way Cities: Skylines
## does in spirit: homes are wanted while there are jobs, jobs while people
## need work, and shops while residents need somewhere to shop.
## `budget` false skips the month's budget (the tick only needs it hourly).
## `slice` (0 to Economy.SLICES - 1) refreshes only that share of the
## homes' service and park scan (the tick passes one each time); -1 does
## all of them, -2 none (a loaded town keeps the parts it saved).
func update_stats(budget := true, slice := -1) -> void:
	var pop := 0
	var home_cap := 0
	var shop_jobs := 0
	var factory_jobs := 0
	# Shops and factories still going up count toward demand (they're
	# coming) but nobody works there yet.
	var unfinished_jobs := 0
	var presold := 0  # buyers waiting on homes going up (see _move_in)
	var office_cap := 0  # BuildingTypes.office_jobs, in the same pass
	var all_ok := not require_utilities
	var served: Dictionary = services.served
	for key in buildings:
		var b: Dictionary = buildings[key]
		var zone := int(b.zone)
		if zone == ZoneMap.Zone.RESIDENTIAL:
			pop += b.occ
			home_cap += b.cap
			continue
		# (BuildingTypes.type_of: no zone defaults to an office.)
		if b.get("type", "") == "office":
			office_cap += int(b.cap)
		# Closed without power or water (_utilities_ok, read straight).
		var sv = served.get(key)
		var ok: bool = all_ok or (sv != null and sv.power and sv.water)
		match zone:
			ZoneMap.Zone.COMMERCIAL:
				# Flats above a shop count as homes.
				pop += int(b.get("focc", 0))
				home_cap += int(b.get("flats", 0))
				if ok:
					shop_jobs += b.cap
			ZoneMap.Zone.INDUSTRIAL:
				if ok:
					factory_jobs += b.cap
	# Only the buildings with a site still open can be going up, so those are
	# the ones asked about rather than every building in town.
	for ref in construction.sites:
		if not ref.begins_with("lot:"):
			continue
		var key: String = ref.substr(4)
		if not buildings.has(key) or construction.is_done(ref, tick_count):
			continue
		var b: Dictionary = buildings[key]
		if int(b.zone) == ZoneMap.Zone.RESIDENTIAL:
			presold += mini(b.cap, 2)
		elif _utilities_ok(key):
			unfinished_jobs += b.cap
	_update_services()
	parks.update_effects(self)
	var homes := _home_scan(slice)
	factory_jobs += farms.jobs() + industry.jobs() + warehouses.jobs() + power.jobs() + rail.jobs() + big.jobs()
	# Teachers, and office and tech jobs for the town's graduates (less the
	# ones already counted in office buildings, which house those jobs).
	shop_jobs += education.jobs() - mini(office_cap, education.office_jobs())
	# The gas station, diner and motel that opened for visitors.
	shop_jobs += Tourism.jobs(self)
	# The phone company's staff, and remote workers who bring their jobs.
	telecom.mark_dirty()
	telecom.refresh(self)
	# Tellers and loan officers.
	shop_jobs += banks.jobs()
	economy.reach_milestones(pop)
	var workers := int(pop * WORKER_SHARE)
	var jobs := shop_jobs + factory_jobs + telecom.jobs() + healthcare.jobs(self)
	# Demand plans ahead, as builders do: homes going up are people on the
	# way (their pre-sold buyers; the rest of a new home is still for sale),
	# and jobs at shops and factories going up are jobs on the way.
	var coming := pop + presold
	var coming_workers := int(coming * WORKER_SHARE)
	var free := home_cap - presold - pop
	var open_jobs := maxi(jobs - unfinished_jobs, 0)
	# Some of the town's people work in Marion or Gas City (Backdrop): jobs
	# for homes, not shops or factories here.
	var away := mini(roundi(coming_workers * Balance.BACKDROP_COMMUTE_SHARE * _commute_weight()),
		roundi(_commute_pool()))
	var employed := mini(workers, open_jobs)
	stats = {"population": pop, "workers": workers, "jobs": open_jobs,
		"employed": employed, "commuting": clampi(away, 0, workers - employed), "homes_free": free}
	demand[ZoneMap.Zone.RESIDENTIAL] = clampf(
		0.6 + 0.6 * float(jobs + away - coming_workers) / maxf(coming_workers, 40.0)
		- float(free) / maxf(home_cap, 30.0), 0.0, 1.0)
	demand[ZoneMap.Zone.COMMERCIAL] = clampf(
		0.05 + (coming * 0.12 - shop_jobs) / maxf(shop_jobs, 12.0), 0.0, 1.0)
	demand[ZoneMap.Zone.INDUSTRIAL] = clampf(
		0.1 + float(coming_workers - jobs) / maxf(coming_workers, 40.0)
		+ 0.4 * (shop_jobs * 0.8 - factory_jobs) / maxf(factory_jobs, 20.0), 0.0, 1.0)
	for z in demand:
		demand[z] = clampf(demand[z] + economy.demand_shift(z) + mail.demand_shift(z) + regional.demand_shift(z), 0.0, 1.0)
	# Visitors who come to walk the old districts, and the fall festival.
	demand[ZoneMap.Zone.COMMERCIAL] = clampf(demand[ZoneMap.Zone.COMMERCIAL] + heritage.tourism_demand()
		+ LeaderAsks.festival_demand(self), 0.0, 1.0)
	# A boil-water notice, or a steep water bill, puts people off moving in.
	demand[ZoneMap.Zone.RESIDENTIAL] = clampf(demand[ZoneMap.Zone.RESIDENTIAL]
		- Balance.WATER_BOIL_DEMAND * homes.boil - services.water.rate_penalty(self), 0.0, 1.0)
	# Good care keeps people in town and draws families.
	demand[ZoneMap.Zone.RESIDENTIAL] = clampf(demand[ZoneMap.Zone.RESIDENTIAL] + healthcare.demand_shift(self, homes.care), 0.0, 1.0)
	# Past village size, people want fire, police, a clinic and a school nearby.
	if pop > 300:
		demand[ZoneMap.Zone.RESIDENTIAL] = clampf(
			demand[ZoneMap.Zone.RESIDENTIAL] + 0.3 * (homes.cover - 0.5), 0.0, 1.0)
	# Parks and landmarks make a town nicer to live in.
	demand[ZoneMap.Zone.RESIDENTIAL] = clampf(demand[ZoneMap.Zone.RESIDENTIAL]
		+ Balance.AMENITY_DEMAND * homes.happy, 0.0, 1.0)
	# Good cell service and internet draw people, and fiber draws offices.
	if not telecom.companies.is_empty():
		demand[ZoneMap.Zone.RESIDENTIAL] = clampf(demand[ZoneMap.Zone.RESIDENTIAL]
			+ Balance.TELECOM_HOME_DEMAND * telecom.town_signal, 0.0, 1.0)
		demand[ZoneMap.Zone.COMMERCIAL] = clampf(demand[ZoneMap.Zone.COMMERCIAL] + telecom.office_demand(), 0.0, 1.0)
	if budget:
		economy.update_budget(self)
	stats_changed.emit()


## Jobs within commuting reach in the backdrop towns, and how near the
## nearest is (1 within Market's full reach): worked out once per place.
var _commute_at := Vector2.INF
var _commute := [0.0, 0.0]


func _commute_pool() -> float:
	_commute_check()
	return _commute[0]


func _commute_weight() -> float:
	_commute_check()
	return _commute[1]


func _commute_check() -> void:
	if _commute_at == terrain_offset:
		return
	_commute_at = terrain_offset
	var near := Backdrop.nearest(terrain_offset)
	var w := 0.0 if near.is_empty() else Market.weight(Backdrop.distance_to(terrain_offset))
	_commute = [Backdrop.commute_jobs(terrain_offset), w]


## The town's homes, as their own functions would each work them out:
## share under a boil notice (water.boil_share), care (healthcare.care),
## service coverage (service_coverage) and park happiness
## (parks.average_happiness). Kept as Economy.SLICES parts so the tick can
## redo one part at a time; the parts are saved, so a loaded copy matches.
var _home_parts := []


func _home_scan(slice := -1) -> Dictionary:
	if _home_parts.size() != Economy.SLICES or slice == -1:
		_home_parts = []
		for i in Economy.SLICES:
			_home_parts.append(_home_part(i))
	elif slice >= 0:
		_home_parts[slice] = _home_part(slice)
	var n := 0
	var boil := 0
	var care := 0.0
	var cover := 0.0
	var happy := 0.0
	for part in _home_parts:
		n += int(part.n)
		boil += int(part.boil)
		care += float(part.care)
		cover += float(part.cover)
		happy += float(part.happy)
	if n == 0:
		return {"boil": 0.0, "care": 0.0, "cover": 0.0, "happy": 0.0}
	return {"boil": float(boil) / n, "care": clampf(care / n + healthcare.region_care, 0.0, 1.0),
		"cover": cover / n, "happy": happy / n}


func _home_part(slice: int) -> Dictionary:
	var n := 0
	var boil := 0
	var care := 0.0
	var cover := 0.0
	var happy := 0.0
	# (The served rows, water utilities and park lifts read once.)
	var served: Dictionary = services.served
	var utilities: Dictionary = services.water.utilities
	var lot_happy: Dictionary = parks.lot_happy
	for key in ledger().home_slices[slice]:
		n += 1
		var s: Dictionary = served.get(key, {})
		# water.boils(s):
		var by: int = s.get("water_by", -1)
		if by != -1 and utilities.has(by) and utilities[by].boil:
			boil += 1
		care += Healthcare.care_of(s)
		if not s.is_empty():
			cover += Services.coverage_of(s)
		happy += float(lot_happy.get(key, 0.0))
	return {"n": n, "boil": boil, "care": care, "cover": cover, "happy": happy}


## The town's ledger: lists of the buildings that systems would otherwise
## sort or filter out of the whole town on every pass. Worked out again only
## when a building is added or removed (homes and shops keep their zone).
##   sorted: every building's key, sorted
##   refs: "lot:" + each of those keys, in the same order
##   slices: every building's key in each Economy slice, in building order
##   home_slices: the homes' keys in each Economy slice, in building order
##   by_zone: zone -> its buildings' keys, sorted
##   sig: a hash of the building keys, which changes when one comes or goes
var _ledger := {}
var _ledger_sig := 0


func ledger() -> Dictionary:
	var keys := buildings.keys()
	var sig := hash(keys)
	if sig == _ledger_sig and not _ledger.is_empty():
		return _ledger
	_ledger_sig = sig
	var slices := []
	var homes := []
	for i in Economy.SLICES:
		slices.append([])
		homes.append([])
	for key in keys:
		var i: int = key.hash() % Economy.SLICES
		slices[i].append(key)
		if int(buildings[key].zone) == ZoneMap.Zone.RESIDENTIAL:
			homes[i].append(key)
	var sorted := keys.duplicate()
	sorted.sort()
	var by_zone := {}
	var refs := []
	for key in sorted:
		var z := int(buildings[key].zone)
		if not by_zone.has(z):
			by_zone[z] = []
		by_zone[z].append(key)
		refs.append("lot:" + key)
	_ledger = {"sorted": sorted, "refs": refs, "slices": slices, "home_slices": homes, "by_zone": by_zone, "sig": sig}
	return _ledger


## New residents move into homes with room, faster when homes are in demand.
func _move_in() -> void:
	# Without power or water, people move away (one household at a time).
	if require_utilities:
		for key in buildings:
			var home: Dictionary = buildings[key]
			if home.zone == ZoneMap.Zone.RESIDENTIAL and home.occ > 0 and not _utilities_ok(key):
				home.occ -= 1
			elif int(home.get("focc", 0)) > 0 and not _utilities_ok(key):
				home.focc -= 1
	# A new home is built for a buyer: they move in when it's finished.
	# (The ledger's sorted keys: the same as sorting them here.)
	var sorted: Array = ledger().sorted
	for key in sorted:
		var nb: Dictionary = buildings[key]
		if nb.zone == ZoneMap.Zone.RESIDENTIAL and nb.occ == 0 and _utilities_ok(key) and care.livable(key):
			var since: int = tick_count - int(nb.built) - Construction.duration("house")
			if since >= 0 and since < MOVE_EVERY * 6:
				nb.occ = mini(nb.cap, 2)
	var arrivals := 1 + int(demand[ZoneMap.Zone.RESIDENTIAL] * 4.0)
	if demand[ZoneMap.Zone.RESIDENTIAL] <= 0.05:
		return
	for key in sorted:
		var b: Dictionary = buildings[key]
		# A full home or shop takes nobody (the rest below only matters
		# where there's room).
		if not (b.zone == ZoneMap.Zone.RESIDENTIAL and b.occ < b.cap) and int(b.get("focc", 0)) >= int(b.get("flats", 0)):
			continue
		if not care.livable(key):
			continue
		if b.zone == ZoneMap.Zone.RESIDENTIAL and b.occ < b.cap and _utilities_ok(key) \
				and construction.is_done("lot:" + key, tick_count):
			b.occ += 1
			arrivals -= 1
		elif int(b.get("focc", 0)) < int(b.get("flats", 0)) and _utilities_ok(key) \
				and construction.is_done("lot:" + key, tick_count):
			b.focc += 1
			arrivals -= 1
		if arrivals == 0:
			return


## Lots that are zoned but have nothing on them yet.
func empty_zoned_lots() -> Array:
	var out := []
	for key in lots:
		if not buildings.has(key) and zones.zone_at(lots[key].zone_pt) != ZoneMap.Zone.NONE \
				and _utilities_ok(key):
			out.append(key)
	out.sort()
	return out


## Why a farmhouse can't go here, or "" if it can: it needs farmland, clear
## ground and a road near enough for its lane.
func farmhouse_problem(pos: Vector3, dir: Vector3) -> String:
	var side := Vector3(-dir.z, 0.0, dir.x)
	var poly := PackedVector2Array()
	for sgn in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = pos + side * Farms.FARMHOUSE_SIZE.x * 0.5 * sgn.x + dir * Farms.FARMHOUSE_SIZE.y * 0.5 * sgn.y
		poly.append(Vector2(p.x, p.z))
	if not land_ok(pos, Farms.FARMHOUSE_SIZE.length() * 0.5):
		return "Can't build in the water or on a slope that steep."
	if not farms.reserved_ok(pos):
		return "That land is reserved for %s." % Reserves.KINDS[reserves.kind_at(pos)]
	if farm_drive(pos, dir).is_empty():
		return "Needs a road within %d m for its farm lane." % int(Farms.MAX_DRIVE)
	if Services.road_clash(network, poly):
		return "Too close to a road."
	for id in services.buildings:
		if not Geometry2D.intersect_polygons(poly, services.footprint(id)).is_empty():
			return "Overlaps a service building."
	for id in farms.farms:
		if farms.farms[id].pos.distance_to(pos) < Farms.FARMHOUSE_SIZE.length():
			return "Too close to another farm."
	for p in [pos] + Array(poly).map(func(q): return Vector3(q.x, 0.0, q.y)):
		if Capital.owner_of(self, p).begins_with("site:") or power.covers(p):
			return "That ground belongs to a company."
		if rail.covers(p):
			return "That ground belongs to the railroad."
		if education.covers(p):
			return "That ground is a campus."
		if telecom.covers(p):
			return "That ground belongs to the phone company."
		if banks.covers(p):
			return "That ground is a bank."
	if _on_warehouse(Array(poly).map(func(q): return Vector3(q.x, 0.0, q.y))):
		return "Overlaps a warehouse."
	if parks.overlaps(Array(poly)):
		return "That ground is a park."
	# Nobody sets up a farmstead where no field would pay.
	if farms.start_profit(pos, dir) <= 0.0:
		return "Soil here is too poor to farm: %d%% fertile." % roundi(Farms.fertility_at(pos - dir * Farms.CELL) * 100.0)
	return ""


## Why a company's main building can't go here, or "" if it can: it needs
## the resource underground, clear ground and a road near enough for its lane.
func industry_problem(kind: String, pos: Vector3, dir: Vector3) -> String:
	var spec: Dictionary = Industry.KINDS[kind]
	var side := Vector3(-dir.z, 0.0, dir.x)
	var poly := PackedVector2Array()
	for sgn in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = pos + side * Industry.HQ_SIZE.x * 0.5 * sgn.x + dir * Industry.HQ_SIZE.y * 0.5 * sgn.y
		poly.append(Vector2(p.x, p.z))
	if not land_ok(pos, Industry.HQ_SIZE.length() * 0.5):
		return "Can't build in the water or on a slope that steep."
	if not industry.reserved_ok(kind, pos):
		return "That land is reserved for %s." % Reserves.KINDS[reserves.kind_at(pos)]
	if industry_reach(kind, pos) < Industry.MIN_RICHNESS:
		return "No %s near here. Open the %s view and build where it shows." % [spec.cargo,
			{"oil": "Oil", "ore": "Ore", "forest": "Forest"}[kind]]
	if industry_drive(pos, dir).is_empty():
		return "Needs a road within %d m for its access road." % int(Industry.MAX_DRIVE)
	if Services.road_clash(network, poly):
		return "Too close to a road."
	for id in services.buildings:
		if not Geometry2D.intersect_polygons(poly, services.footprint(id)).is_empty():
			return "Overlaps a service building."
	for p in [pos] + Array(poly).map(func(q): return Vector3(q.x, 0.0, q.y)):
		var owner := Capital.owner_of(self, p)
		if owner.begins_with("farm:"):
			return "That ground is farmland."
		if owner.begins_with("site:") or power.covers(p):
			return "Too close to another company."
		if rail.covers(p):
			return "That ground belongs to the railroad."
		if education.covers(p):
			return "That ground is a campus."
		if telecom.covers(p):
			return "That ground belongs to the phone company."
		if banks.covers(p):
			return "That ground is a bank."
	if _on_warehouse(Array(poly).map(func(q): return Vector3(q.x, 0.0, q.y))):
		return "Overlaps a warehouse."
	if parks.overlaps(Array(poly)):
		return "That ground is a park."
	return ""


## Why a warehouse can't go here, or "" if it can: it needs clear ground
## beside a street for its truck court and building.
func warehouse_problem(kind: String, pos: Vector3, dir: Vector3) -> String:
	var w := {"kind": kind, "pos": pos, "dir": dir, "bays": 0}
	var poly := Warehouses.corners(w)
	for p in _grid_in(poly):
		if not land_ok(p):
			return "Can't build in the water or on a slope that steep."
	if reserves.kind_at(Warehouses.center(w)) != "":
		return "That land is reserved for %s." % Reserves.KINDS[reserves.kind_at(Warehouses.center(w))]
	if Services.road_clash(network, poly):
		return "Too close to a road. A %s needs %d × %d m." % [Warehouses.KINDS[kind].name.to_lower(),
			roundi(Warehouses.site_width(w)), roundi(Warehouses.site_depth(w))]
	for id in services.buildings:
		if not Geometry2D.intersect_polygons(poly, services.footprint(id)).is_empty():
			return "Overlaps a service building."
	for id in warehouses.buildings:
		if not Geometry2D.intersect_polygons(poly, warehouses.footprint(id)).is_empty():
			return "Overlaps another warehouse."
	for p in _grid_in(poly):
		var owner := Capital.owner_of(self, p)
		if owner.begins_with("farm:"):
			return "That ground is farmland."
		if owner.begins_with("site:"):
			return "That ground belongs to a company."
		if rail.covers(p):
			return "That ground belongs to the railroad."
		if hubs.covers(p):
			return "Overlaps a landfill, recycling center or cemetery."
		if power.covers(p):
			return "That ground belongs to a power company."
		if mail.covers(p):
			return "Overlaps the post office."
		if education.covers(p):
			return "That ground is a campus."
		if telecom.covers(p):
			return "That ground belongs to the phone company."
		if banks.covers(p):
			return "That ground is a bank."
	if big.overlaps(poly):
		return "Overlaps a big factory."
	if parks.overlaps(Array(poly)):
		return "That ground is a park."
	return ""


## True when new ground for warehouse `id` is free: no road, building,
## farm, company, other warehouse, reserve, or zoned or built lot on it.
func warehouse_ground_ok(poly: PackedVector2Array, id: int) -> bool:
	if Services.road_clash(network, poly):
		return false
	for p in _grid_in(poly):
		if not land_ok(p):
			return false  # water or a slope too steep to grade
	for sid in services.buildings:
		if not Geometry2D.intersect_polygons(poly, services.footprint(sid)).is_empty():
			return false
	for wid in warehouses.buildings:
		if wid != id and not Geometry2D.intersect_polygons(poly, warehouses.footprint(wid)).is_empty():
			return false
	for p in _grid_in(poly):
		if Capital.owner_of(self, p) != "" or reserves.kind_at(p) != "" \
				or hubs.covers(p) or education.covers(p) or mail.covers(p) or power.covers(p) or banks.covers(p) or rail.covers(p) or telecom.covers(p) or big.covers(p):
			return false
	for key in lots:
		if not buildings.has(key) and zones.zone_at(lots[key].zone_pt) == ZoneMap.Zone.NONE:
			continue  # an empty, unzoned roadside lot can be bought
		if not Geometry2D.intersect_polygons(poly, lots[key].corners).is_empty():
			return false
	return true


## True when any of these points (or the area between them) is on a warehouse.
func _on_warehouse(pts: Array) -> bool:
	var poly := PackedVector2Array()
	for p in pts:
		poly.append(Vector2(p.x, p.z))
	for id in warehouses.buildings:
		if not Geometry2D.intersect_polygons(poly, warehouses.footprint(id)).is_empty():
			return true
	return false


## Sample points over a polygon, about every 10 m (corners and middle too).
static func _grid_in(poly: PackedVector2Array) -> Array:
	var out := []
	var box := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		box = box.expand(q)
		out.append(Vector3(q.x, 0.0, q.y))
	var step := 10.0
	var y := box.position.y + step * 0.5
	while y < box.end.y:
		var x := box.position.x + step * 0.5
		while x < box.end.x:
			if Geometry2D.is_point_in_polygon(Vector2(x, y), poly):
				out.append(Vector3(x, 0.0, y))
			x += step
		y += step
	return out


## Why a power company's yard can't go here, or "" if it can: clear ground
## and a road near enough for its access road. Any ground will do; the
## leader picks the plant from what's around.
func power_problem(pos: Vector3, dir: Vector3) -> String:
	if not land_ok(pos, Power.HQ_SIZE.length() * 0.5):
		return "The yard needs dry, fairly level ground."
	var side := Vector3(-dir.z, 0.0, dir.x)
	var poly := PackedVector2Array()
	var pts := [pos]
	for sgn in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p: Vector3 = pos + side * Power.HQ_SIZE.x * 0.5 * sgn.x + dir * Power.HQ_SIZE.y * 0.5 * sgn.y
		poly.append(Vector2(p.x, p.z))
		pts.append(p)
	if reserves.kind_at(pos) != "":
		return "That land is reserved for %s." % Reserves.KINDS[reserves.kind_at(pos)]
	if industry_drive(pos, dir).is_empty():
		return "Needs a road within %d m for its access road." % int(Power.MAX_DRIVE)
	if Services.road_clash(network, poly):
		return "Too close to a road."
	for id in services.buildings:
		if not Geometry2D.intersect_polygons(poly, services.footprint(id)).is_empty():
			return "Overlaps a service building."
	for p in pts:
		var owner := Capital.owner_of(self, p)
		if owner.begins_with("farm:"):
			return "That ground is farmland."
		if owner.begins_with("site:") or power.covers(p):
			return "Too close to another company."
		if hubs.covers(p):
			return "Overlaps a landfill, recycling center or cemetery."
	if _on_warehouse(pts):
		return "Overlaps a warehouse."
	if parks.overlaps(Array(poly)):
		return "That ground is a park."
	return ""


## The town's schooling, 0 to 1, which shapes the leaders it can hire: a
## base for a small Midwest town, rising with the share of homes a school
## covers, or with the town's own college graduates.
func town_education() -> float:
	var homes := 0
	var schooled := 0
	for key in buildings:
		if buildings[key].zone == ZoneMap.Zone.RESIDENTIAL:
			homes += 1
			if services.served.has(key) and services.served[key].get(Services.Kind.SCHOOL, false):
				schooled += 1
	var schools := Balance.TOWN_EDUCATION_BASE + Balance.TOWN_EDUCATION_SCHOOLS * (0.0 if homes == 0 else float(schooled) / homes)
	# Local graduates from the town's own campuses (the education thread's
	# shared leader pool) lift it further.
	return maxf(schools, education.leader_education(int(stats.workers)))


func game_day() -> float:
	return tick_count / float(24 * TICKS_PER_HOUR)


## Power companies take a step (see Power.decide). The town's load is every
## building's draw; the rest goes out the county highway to the region.
func _decide_power() -> bool:
	power.tax_rate = economy.tax[ZoneMap.Zone.INDUSTRIAL]
	var load := 0.0
	for key in buildings:
		load += Services.LOAD[int(buildings[key].zone)]
	neighbor_power_short = 0.0
	for d in trade.last_deals:
		# Power is only ever offered, so a deal with a neighbor is a sale.
		if d.good == "power" and d.buyer != "outside" and d.seller != "outside":
			neighbor_power_short += float(d.amount) * 12.0 / Balance.POWER_MWH_PER_HOME
	var changed := power.decide(field_usable, load, not region_links.is_empty() or in_region, power_context())
	# Spare power goes to the region through Trade, in MWh a month.
	var spare := 0.0
	for id in power.sales:
		spare += float(power.sales[id].export) + float(power.sales[id].neighbor)
	trade.offer("power", spare * Balance.POWER_MWH_PER_HOME / 12.0, Balance.POWER_EXPORT_PRICE)
	if changed:
		_lots_dirty = true
	return changed


## What a power company's leader can see around it (see Power.decide).
## How much the power plants' smoke, noise and ash lower land value at a
## point (0 to about -0.3), as Pollution measures them.
func power_nuisance(p: Vector3) -> float:
	var smoke := 0.0
	var energy := 0.0
	var clean := 1.0
	for id in power.sites:
		var src: Dictionary = pollution.sources.get("power:%d" % id, {})
		if src.is_empty():
			continue
		var v := pollution.source_at(src, p)
		smoke += v.x
		energy += v.y
		clean *= 1.0 - v.z
	if smoke == 0.0 and energy == 0.0 and clean == 1.0:
		return 0.0
	return Pollution.penalty({"smoke": smoke, "noise": Pollution.db(energy), "ground": 1.0 - clean})


func power_context() -> Dictionary:
	var has_school := false
	for id in services.buildings:
		has_school = has_school or services.buildings[id].kind == Services.Kind.SCHOOL
	var ctx := {"day": game_day(), "education": town_education(), "school": has_school,
		"university": education.campuses.values().any(func(c): return c.kind == "university"), "neighbor_short": neighbor_power_short,
		"industry_near": func(p: Vector3) -> bool:
			for key in buildings:
				if buildings[key].zone == ZoneMap.Zone.INDUSTRIAL and lots.has(key) \
						and lots[key].pos.distance_to(p) < Balance.POWER_STEAM_REACH:
					return true
			return false}
	return ctx


## The best the resource gets within reach of a main building (its pads
## spread up to about 400 m out).
func industry_reach(kind: String, pos: Vector3) -> float:
	var best := 0.0
	for r in [0.0, 120.0, 240.0, 360.0]:
		for i in (1 if r == 0.0 else 12):
			var a := TAU * i / 12.0
			best = maxf(best, Resources.at(Industry.KINDS[kind].resource, pos + Vector3(cos(a), 0.0, sin(a)) * r))
	return best


## The access road from a main building to the nearest public road, or [].
func industry_drive(pos: Vector3, dir: Vector3) -> Array:
	var near := RoadIndex.segment_near(network, pos, Industry.MAX_DRIVE, 1.0)
	if near.is_empty():
		return []
	return Farms.make_drive(pos, dir, near.point)


## Places, upgrades or removes a landfill, recycling centre or cemetery.
func _hub_command(cmd: Dictionary) -> bool:
	if cmd.type == "place_hub":
		var kind := str(cmd.get("kind", ""))
		var pos := _v(cmd.pos)
		var dir := _v(cmd.dir).normalized()
		# Recycling starts as a drop-off yard; the bigger plants are upgrades.
		if not kind in CivicHubs.TOOL_KINDS.values() or dir.length() < 0.5:
			return false
		var cost := int(Balance.WASTE_SITES[kind].cost)
		if cost > economy.money or hubs.site_problem(self, kind, pos, dir) != "":
			return false
		var id := hubs.add(kind, pos, dir, tick_count)
		# Its scale house, booth or chapel goes up like any other building.
		construction.start("hub:%d" % id, "shop", tick_count, pos, dir, CivicHubs.SETBACK
			+ RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH)
		economy.money -= cost
		for c in hubs.hubs[id].cells:
			_clear_zones_under(CivicHubs.cell_poly(hubs.hubs[id], c))
	elif cmd.type == "upgrade_hub":
		var id := int(cmd.id)
		if not hubs.hubs.has(id):
			return false
		var cost := CivicHubs.upgrade_cost(hubs.hubs[id].kind)
		if cost <= 0 or cost > economy.money or not hubs.upgrade(id):
			return false
		economy.money -= cost
	else:
		if not hubs.remove(int(cmd.id)):
			return false
	_lots_dirty = true
	return true
## A hub grew onto (or gave back) this ground: zoning there goes, and the
## lots are re-cut around it (bought-out buildings go with their lots).
func land_taken(poly: PackedVector2Array) -> void:
	if not poly.is_empty():
		_clear_zones_under(poly)
	_lots_dirty = true
	zones_changed.emit()


## Lots are worked out again on the next refresh (new track took some).
func mark_lots_dirty() -> void:
	_lots_dirty = true
## Hands the sliders to everything that reads them.
func _wire_policies() -> void:
	farms.policies = policies
	industry.policies = policies
	farms.culture = culture
	industry.culture = culture
	services.policies = policies
	hubs.policies = policies
	parks.policies = policies
	power.policies = policies
	# Wind leases: turbines stand in farmers' fields, which pay the farm.
	power.on_farm = func(p: Vector3) -> bool: return farms.field_at(p) != -1
	power.pad_usable = pad_usable
	farms.lease_of = power.lease_in
	farms.rent_of = power.farm_rent
	# A farm whose block is full builds a road to the next (HubRoads), and
	# asks on the bell when that road would cross the player's things.
	farms.expand = _farm_road
	industry.expand = _industry_road
	industry.land_price_of = func(p: Vector3) -> float: return Capital.land_price(self, p)
	industry.pad_road = _pad_road
	# Land has one owner: hubs plant and build only on open land or their own.
	industry.land_free = func(pts: Array, who: String) -> bool: return Capital.land_free(self, pts, who)
	farms.land_free = industry.land_free
	# What farmland sells for, nearby development included (Capital).
	farms.land_price_of = func(p: Vector3) -> float: return Capital.land_price(self, p)


## Hubs with their own money lever (a campus's funding level, a post
## office's, the water utility's and a bus depot's subsidy) take it from
## their Funding slider. Each: its hub kind, Economy page area, the hubs,
## and the lever's value at each step (see Balance).
func _levers() -> Array:
	var depots := []
	for id in buses.depots:
		if services.buildings.has(id):
			depots.append(id)
	var bus := []
	for level in Balance.BUS_FUNDING_LEVELS:
		bus.append(int(level[1]))
	return [
		{"kind": "campus", "area": "schools", "hubs": education.campuses, "field": "funding", "values": [0, 1, 2, 3, 4]},
		{"kind": "post_office", "area": "mail", "hubs": mail.offices, "field": "funding", "values": Balance.POLICY_MAIL_FUNDING},
		{"kind": "water", "area": "water", "hubs": services.water.utilities, "field": "subsidy", "values": Balance.POLICY_WATER_SUBSIDY},
		{"kind": "telecom", "area": "telecom", "hubs": telecom.companies, "field": "funding", "values": [0, 1, 2, 3, 4]},
		{"kind": "bus_depot", "area": "transit", "hubs": services.buildings, "ids": depots, "field": "subsidy", "values": bus},
	]


## The step each lever hub was last set to, so a lever is only rewritten
## when its slider moves (an exact amount from an old save or a command
## stays put until then).
var _lever_steps := {}


## Writes every lever whose Funding step has moved since it was last set.
func _sync_levers() -> void:
	var seen := {}
	for lv in _levers():
		for id in lv.get("ids", lv.hubs.keys()):
			var key := "%s:%d" % [lv.kind, id]
			var now := policies.step("funding", lv.area, key)
			seen[key] = true
			if int(_lever_steps.get(key, -1)) != now:
				lv.hubs[id][lv.field] = lv.values[now]
				_lever_steps[key] = now
	for key in _lever_steps.keys():
		if not seen.has(key):
			_lever_steps.erase(key)


## A lever was set to an exact amount (a command, an old save): its slider
## takes the nearest step, and the amount stays as it is.
func _adopt_levers(only := "") -> void:
	for lv in _levers():
		for id in lv.get("ids", lv.hubs.keys()):
			var key := "%s:%d" % [lv.kind, id]
			if only != "" and key != only:
				continue
			var value := float(lv.hubs[id].get(lv.field, 0))
			var best := Policies.STANDARD
			for i in lv.values.size():
				if absf(float(lv.values[i]) - value) < absf(float(lv.values[best]) - value):
					best = i
			if best != policies.step("funding", lv.area, key):
				policies.set_step(key, "funding", best)
			_lever_steps[key] = best


## The Economy page area of a hub key ("farm:3", "service:5", "hub:1"...),
## or "" if there's no such hub.
func hub_area(key: String) -> String:
	var parts := key.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return ""
	var id := int(parts[1])
	match parts[0]:
		"farm":
			return "farms" if farms.farms.has(id) else ""
		"industry":
			return "resources" if industry.sites.has(id) else ""
		"service":
			# A bus depot and the water utility go by their own keys below.
			return Services.area_of(services.buildings[id].kind) \
				if services.buildings.has(id) and services.key_of(id) == key else ""
		"bus_depot":
			return "transit" if buses.depots.has(id) and services.buildings.has(id) else ""
		"water":
			return "water" if services.water.utilities.has(id) else ""
		"post_office":
			return "mail" if mail.offices.has(id) else ""
		"power":
			return "power" if power.sites.has(id) else ""
		"warehouse":
			return "warehouses" if warehouses.buildings.has(id) else ""
		"big":
			return "big" if big.sites.has(id) else ""
		"taxi":
			return "taxis" if taxis.companies.has(id) and services.buildings.has(id) else ""
		"builders":
			return "public" if builders.companies.has(id) and services.buildings.has(id) else ""
		"telecom":
			return "telecom" if telecom.companies.has(id) else ""
		"hub":
			return CivicHubs.area_of(hubs.hubs[id].kind) if hubs.hubs.has(id) else ""
		"park":
			return "parks" if parks.sites.has(id) else ""
		"campus":
			return "schools" if education.campuses.has(id) else ""
		"bank":
			return "banks" if banks.banks.has(id) else ""
		"hospital":
			return "health" if services.buildings.has(id) and services.buildings[id].kind == Services.Kind.HOSPITAL else ""
	return ""


func _set_policy(scope: String, slider: String, s: int) -> bool:
	if scope.begins_with("area:"):
		var area := scope.trim_prefix("area:")
		if Policies.AREAS.has(area) and not slider in Policies.AREAS[area].sliders:
			return false
	elif scope != "city":
		# A hub with a leader always takes Growth: it's your word to them.
		var area := hub_area(scope)
		if area == "" or not (slider in Policies.AREAS[area].sliders
				or slider == "growth" and permits.locators.has(scope.get_slice(":", 0))):
			return false
	if not policies.set_step(scope, slider, s):
		return false
	if slider == "growth":
		_sync_stances()
	_sync_levers()
	economy.update_budget(self)
	return true


## Leaders who signed up with Permits hear their hub's Growth as a stance.
func _sync_stances() -> void:
	for key in permits.guided.keys() + _leader_keys():
		var parts: PackedStringArray = str(key).split(":")
		# Hubs the Economy page doesn't list (rail...) keep their own stance.
		if parts.size() != 2 or hub_area(key) == "":
			continue
		var want := Policies.stance(policies.step("growth", hub_area(key), key))
		var g := permits.guidance(parts[0], int(parts[1]))
		if g.stance != want:
			permits.guide(self, {"hub": parts[0], "hub_id": int(parts[1]), "stance": want, "grant": int(g.grant)})


## Hub keys of every hub whose kind has a leader (signed up with Permits).
func _leader_keys() -> Array:
	var out := []
	for kind in ["farm", "industry", "service", "hub", "park", "campus", "bank", "bus_depot", "water",
			"post_office", "warehouse", "taxi", "telecom", "hospital", "big"]:
		if not permits.locators.has(kind):
			continue
		var ids: Array = {"farm": farms.farms, "industry": industry.sites, "service": services.buildings,
			"hub": hubs.hubs, "park": parks.sites, "campus": education.campuses, "bank": banks.banks,
			"bus_depot": buses.depots, "water": services.water.utilities, "post_office": mail.offices,
			"warehouse": warehouses.buildings, "taxi": taxis.companies, "telecom": telecom.companies, "builders": builders.companies,
			"hospital": healthcare.hubs, "big": big.sites}[kind].keys()
		for id in ids:
			out.append("%s:%d" % [kind, id])
	return out


## Zoning under a new building goes away, as in Cities: Skylines 2.
func _clear_zones_under(poly: PackedVector2Array) -> void:
	for c in zones.cells.keys():
		if Geometry2D.is_point_in_polygon(Vector2((c.x + 0.5) * ZoneMap.CELL, (c.y + 0.5) * ZoneMap.CELL), poly):
			zones.erase_cell(c)


## Zoning never stays on reserved land.
func _clear_reserved_zones(near := Vector3.INF, reach := 0.0) -> void:
	if reserves.outlines.is_empty():
		return
	for c in zones.cells.keys():
		if near != Vector3.INF and Vector2((c.x + 0.5) * ZoneMap.CELL - near.x, (c.y + 0.5) * ZoneMap.CELL - near.z).length() > reach:
			continue
		if reserves.kind_at(Vector3((c.x + 0.5) * ZoneMap.CELL, 0.0, (c.y + 0.5) * ZoneMap.CELL)) != "":
			zones.erase_cell(c)


## The gravel lane from a farmhouse to the nearest road, or [] if no road is
## near enough.
func farm_drive(pos: Vector3, dir: Vector3) -> Array:
	var near := RoadIndex.segment_near(network, pos, Farms.MAX_DRIVE, 1.0)
	if near.is_empty():
		return []
	return Farms.make_drive(pos, dir, near.point)


## True when a public road runs between a and b on the ground.
func road_between(a: Vector3, b: Vector3) -> bool:
	var a2 := Vector3(a.x, 0.0, a.z)
	var b2 := Vector3(b.x, 0.0, b.z)
	var n := maxi(2, ceili(a2.distance_to(b2) / 6.0))
	for i in range(1, n):
		var p := a2.lerp(b2, float(i) / n)
		if not RoadIndex.segment_near(network, p, 4.0).is_empty():
			return true
	return false


## Fields and lots changed outside a command (a farm leased fields away).
func clear_usable_cache() -> void:
	_usable_cache.clear()


## True when ground for a field is clear: no road, lot, service or farmyard.
func field_usable(mid: Vector3, corners: PackedVector2Array) -> bool:
	return _ground_free(mid, corners, false)


## Where a wind turbine's pad may go: the same free ground, or inside a
## farm's field, which the farmer leases out and keeps farming around.
func pad_usable(mid: Vector3, corners: PackedVector2Array) -> bool:
	return _ground_free(mid, corners, true)


## True if a county road (not bulldozed) runs under the outline `poly`
## (town coordinates), out to `half` metres each side of its section line:
## no lot is platted across one, joined or still only painted on the land,
## which would cut it in two (Brawn 2026-10-24).
func _county_under(poly: PackedVector2Array, half: float) -> bool:
	if poly.is_empty():
		return false
	var o := terrain_offset
	var lo := poly[0] + o
	var hi := lo
	for q in poly:
		lo = lo.min(q + o)
		hi = hi.max(q + o)
	var mid := (lo + hi) * 0.5
	var radius := (hi - lo).length() * 0.5
	if CountyGrid.distance(mid.x, mid.y) > radius + half:
		return false
	for mile in CountyGrid.miles_at(mid.x, mid.y, radius + half):
		if county_removed.has(mile.key):
			continue
		var a: Vector2 = mile.a
		var b: Vector2 = mile.b
		# Section lines run north-south or east-west: the outline's box
		# meets the strip along the mile.
		var hits := hi.x >= a.x - half and lo.x <= b.x + half and hi.y >= a.y - half and lo.y <= b.y + half
		if hits and CountyGrid.clears(clampf(mid.x, a.x, b.x), clampf(mid.y, a.y, b.y)):
			return true
	return false


func _ground_free(mid: Vector3, corners: PackedVector2Array, in_fields: bool) -> bool:
	var key := Vector3i(roundi(mid.x), roundi(mid.z), int(in_fields))
	if _usable_cache.has(key):
		return _usable_cache[key]
	var ok := RoadIndex.segment_near(network, mid, Farms.CELL * 0.6 + RoadStyle.right_of_way_half(RoadStyle.Type.AVENUE), 2.0).is_empty() \
		and not _on_painted_road(mid, Farms.CELL * 0.6 + RoadStyle.right_of_way_half(RoadStyle.Type.COUNTY))
	var pts := [mid]
	for c in corners:
		pts.append(mid.lerp(Vector3(c.x, 0.0, c.y), 0.8))
	if ok:
		for p in pts:
			if services.covers(p) or farms.covers(p) or industry.covers(p) or (not in_fields and farms.field_at(p) != -1) \
					or hubs.covers(p) or warehouses.covers(p) or parks.covers(p) or education.covers(p) \
					or mail.covers(p) or power.covers(p) or banks.covers(p) or rail.covers(p) or telecom.covers(p) or big.covers(p) \
					or not land_ok(p):
				ok = false
	if ok:
		var reach := Farms.CELL * 0.71 + 16.0
		for key2 in lots_near(Rect2(mid.x - reach, mid.z - reach, reach * 2.0, reach * 2.0)):
			# Fields can take empty roadside lots, but not zoned or built ones.
			if not buildings.has(key2) and zones.zone_at(lots[key2].zone_pt) == ZoneMap.Zone.NONE:
				continue
			if lots[key2].pos.distance_to(mid) < reach:
				ok = false
				break
	_usable_cache[key] = ok
	return ok


## True when a county road (a mile not bulldozed) or a state highway the
## town hasn't built runs within `reach` metres of p: fields, yards and
## pads keep off it as off any built road (Brawn, 2026-10-24).
func _on_painted_road(p: Vector3, reach: float) -> bool:
	var x := p.x + terrain_offset.x
	var z := p.z + terrain_offset.y
	if Highways.distance(x, z) < reach:
		return true
	if CountyGrid.distance(x, z) >= reach:
		return false
	for mile in CountyGrid.miles_at(x, z, reach):
		if not county_removed.has(mile.key):
			return true
	return false


## Whose land a point is: "farm:<id>" for a farm's yard, lane or fields,
## "site:<id>" for an industry company's (pads, the ground around them and
## its leases: Industry.claim_at), "hub" for any other hub or
## service, or "" for open land.
func land_owner(p: Vector3) -> String:
	var owner := Capital.owner_of(self, p)
	if owner != "":
		return owner
	if services.covers(p) or hubs.covers(p) or warehouses.covers(p) or parks.covers(p) or education.covers(p) \
			or mail.covers(p) or power.covers(p) or banks.covers(p) or rail.covers(p) or telecom.covers(p):
		return "hub"
	return ""


## Farm `id` has filled its block: it builds a gravel road along the survey
## line to the next block (Brawn: hubs grow to a real size, then build a
## road, which joins the town's network). It picks the next block with the
## most good free soil for the shortest road. Roads that would cross the
## player's roads, lots or buildings go to the bell first. True when
## anything changed.
func _farm_road(id: int) -> bool:
	var f: Dictionary = farms.farms[id]
	var name := families.name_of("farm:%d" % id)
	var leader := name if name != "" else "The farm"
	var pending: Dictionary = f.get("pending", {})
	if not pending.is_empty():
		var state := permits.state_of(int(pending.req))
		if state == Permits.State.APPROVED:
			var route := HubRoads.from_flat(self, permits.requests[int(pending.req)].route)
			permits.done(int(pending.req))
			f.pending = {}
			return _farm_open(id, Vector2i(int(pending.block[0]), int(pending.block[1])), route, leader)
		if state != Permits.State.OPEN:
			# Told no, shelved or withdrawn: try again later, maybe elsewhere.
			f.pending = {}
			f.road_wait = farms.day + Balance.FARM_ROAD_WAIT_DAYS
		return false
	var best := {}
	var best_score := -INF
	for pair in Farms.next_blocks(f):
		var soil := _block_soil(id, pair[1])
		if soil <= 0:
			continue
		for line in Farms.road_lines(f, pair[0], pair[1]):
			var far: Vector3 = line[0]
			var start := HubRoads.reach(self, far, line[1], Balance.FARM_ROAD_MAX)
			if start == Vector3.INF:
				continue
			var route := [start, far] if start.distance_to(far) > HubRoads.SNAP else [start]
			route.append_array(line[2])
			var end := HubRoads.on_road(self, route[-1])
			if route.size() >= 2 and end != Vector3.INF and end.distance_to(route[0]) > HubRoads.SNAP:
				route[-1] = end
			var plan := HubRoads.check(self, route, "farm:%d" % id)
			if not plan.ok or plan.length > Balance.FARM_ROAD_MAX:
				continue
			# Good soil it can farm, less the road it has to build (and a
			# road through the player's things is a last resort).
			var score: float = soil * 100.0 - plan.length - (2000.0 if plan.permit else 0.0)
			if score > best_score:
				best_score = score
				best = {"block": pair[1], "plan": plan}
	if best.is_empty():
		f.road_wait = farms.day + Balance.FARM_ROAD_WAIT_DAYS
		return false
	if not best.plan.permit:
		return _farm_open(id, best.block, best.plan.route, leader)
	var req := permits.file(self, {"hub": "farm", "hub_id": id, "leader": leader,
		"title": "A gravel road to farm the next 80 acres",
		"why": "%s has filled its 80 acres and wants the next block. The road would join the town's roads." \
			% leader,
		"route": HubRoads.flat(best.plan.route), "width": RoadStyle.right_of_way_half(HubRoads.TYPE) * 2.0,
		"per_m": int(Economy.BUILD_PER_M[HubRoads.TYPE]), "base": 0, "budget": 0})
	if req == -1:
		f.road_wait = farms.day + Balance.FARM_ROAD_WAIT_DAYS
		return false
	f.pending = {"req": req, "block": [best.block.x, best.block.y]}
	return false


## Once a year each farm family looks at what its land would bring: where
## the town has grown up around it and the land sells for at least
## CAPITAL_SELL_RATIO times farm value, it asks on the bell to sell to a
## developer (Brawn: a farmer priced out of growing may sell the family
## farm). Yes: the farm closes and its land is open for the town. No: the
## family farms on and won't ask again for a few years. True when a farm
## closed.
func _farm_sell_outs() -> bool:
	var changed := false
	var ids := farms.farms.keys()
	ids.sort()
	for id in ids:
		var f: Dictionary = farms.farms[id]
		var sale: Dictionary = f.get("sale", {})
		if not sale.is_empty():
			var state := permits.state_of(int(sale.req))
			if state == Permits.State.OPEN:
				# Developers stopped bidding (or never would have): the
				# family takes the farm off the market.
				if not Capital.sell_out(self, f.pos):
					permits.withdraw(int(sale.req))
					f.sale = {}
					f.sale_year = farms.year
					f.why = "No developer wants the land after all, so the family farms on."
					changed = true
				continue
			f.sale = {}
			if state == Permits.State.APPROVED:
				permits.done(int(sale.req))
				farms.farms.erase(id)
				changed = true
				continue
			f.sale_year = farms.year + Balance.CAPITAL_SELL_WAIT_YEARS
			f.why = "The family turned down the developers and farms on."
			continue
		if not f.barn or farms.year <= int(f.get("sale_year", 0)) or f.cells.is_empty():
			continue
		f.sale_year = farms.year
		if not Capital.sell_out(self, f.pos):
			continue
		var per_acre := Capital.land_price(self, f.pos)
		var acres := 0.0
		for k in f.get("own", Farms.start_fields()):
			acres += Farms.field_cells(f, k).size() * Farms.ACRES_PER_CELL
		var name := families.name_of("farm:%d" % id)
		var who := name if name != "" else "The farm"
		var ring := []
		for c in f.cells:
			ring.append_array(Farms.cell_corners(f, c))
		var hull := Geometry2D.convex_hull(PackedVector2Array(ring))
		var area := []
		for q in hull:
			area.append([q.x, q.y])
		var req := permits.file(self, {"hub": "farm", "hub_id": id, "leader": who, "ask": "sell_farm",
			"title": "%s wants to sell the family farm" % who,
			"why": "Developers offer about $%s an acre, %.1f times what it is worth as farmland, for its %d acres. With the town grown up around it, the family can't buy more land here." % [
				money_text(roundi(per_acre)), per_acre / Balance.CAPITAL_LAND_PER_ACRE, roundi(acres)],
			"area": area, "change": "Family farm sold",
			"yes": "The family sells. The farm closes and its land is open for the town to grow onto.",
			"no": "The family keeps farming and won't ask again for %d years." % Balance.CAPITAL_SELL_WAIT_YEARS})
		if req != -1:
			f.sale = {"req": req}
			f.why = "%s asked you about selling the farm (see the bell)." % who
	return changed


## Builds a farm's road and opens the block beyond it.
func _farm_open(id: int, block: Vector2i, route: Array, leader: String) -> bool:
	var f: Dictionary = farms.farms[id]
	if route.size() < 2 or HubRoads.build(self, route, "farm:%d" % id).is_empty():
		f.road_wait = farms.day + Balance.FARM_ROAD_WAIT_DAYS
		return false
	f.blocks.append(block)
	f.why = "%s filled its 80 acres, so it built a gravel road on the survey line to farm the next 80. It's a town road now." % leader
	_lots_dirty = true
	_usable_cache.clear()
	return true


## A new well pad or harvest unit needs a way in for its trucks: the
## company lays a gravel lease (or logging) road to it from the nearest
## road, most often the one it built to its last pad, so its roads branch
## out across its ground the way an operator lays them out. They are public
## roads: trucks and anyone else may use them, and in time they may become
## shortcuts the mayor has to deal with (Brawn, 2026-10-23). Paid from the
## company's cash. A quarry hauls inside its pit and needs none. True when
## the pad can be reached (road built or already there).
func _pad_road(id: int, cell: Vector2i, spare: float) -> bool:
	var s: Dictionary = industry.sites[id]
	if s.kind == "ore":
		return true
	var mid := Industry.pad_center(s, cell)
	if not RoadIndex.segment_near(network, mid, Industry.PAD * 0.9, 2.0).is_empty():
		return true  # already beside a road
	var home := Vector3(s.pos.x, 0.0, s.pos.z) - mid
	var right := Vector3(-s.dir.z, 0.0, s.dir.x)
	var ways := [s.dir, -s.dir, right, -right]
	if home.length() > 1.0:
		ways.push_front(home.normalized())
	var best := {}
	var best_len := INF
	for d in ways:
		var edge: Vector3 = mid + d * (Industry.PAD * 0.5)
		var start := HubRoads.reach(self, edge, d, Balance.INDUSTRY_PAD_ROAD_MAX)
		if start == Vector3.INF or start.distance_to(edge) <= HubRoads.SNAP:
			continue
		var plan := HubRoads.check(self, [start, edge], "site:%d" % id)
		# A road through the player's things goes to the bell, as the big
		# lease road does; a pad that needs one waits for another spot.
		if not plan.ok or plan.permit or plan.length >= best_len:
			continue
		best_len = plan.length
		best = plan
	if best.is_empty() or spare < float(best.cost):
		return false
	if HubRoads.build(self, best.route, "site:%d" % id).is_empty():
		return false
	s.cash = float(s.cash) - float(best.cost)
	_lots_dirty = true
	_usable_cache.clear()
	return true


## Oil or timber company `id` has worked out its lease: it leases the next
## tract and builds a gravel lease (or logging) road to it from the nearest
## public road, which then joins the town's network like a farm's road.
## Real reference: Illinois Basin lease roads off Pike County's gravel
## roads; logging roads into the next woods. Crossing the player's roads,
## lots or buildings goes to the bell first. True when anything changed.
func _industry_road(id: int) -> bool:
	var s: Dictionary = industry.sites[id]
	var leader := str(s.get("leader", {}).get("name", ""))
	if leader == "":
		leader = "The %s" % Industry.KINDS[s.kind].name.to_lower()
	var pending: Dictionary = s.get("pending", {})
	if not pending.is_empty():
		var state := permits.state_of(int(pending.req))
		if state == Permits.State.APPROVED:
			var route := HubRoads.from_flat(self, permits.requests[int(pending.req)].route)
			permits.done(int(pending.req))
			s.pending = {}
			return _industry_open(id, Vector2i(int(pending.cell[0]), int(pending.cell[1])), route, leader,
				float(pending.get("cost", 0.0)))
		if state != Permits.State.OPEN:
			s.pending = {}
			s.road_wait = industry.day + Balance.INDUSTRY_ROAD_WAIT_DAYS
		return false
	var cell := industry.next_lease(id, field_usable)
	if cell == Vector2i.MAX:
		s.road_wait = industry.day + Balance.INDUSTRY_ROAD_WAIT_DAYS
		return false
	var mid := Industry.pad_center(s, cell)
	var right := Vector3(-s.dir.z, 0.0, s.dir.x)
	var home := Vector3(s.pos.x, 0.0, s.pos.z) - mid
	# Toward the main building first, then square off to the nearest road.
	var ways := [home.normalized(), s.dir, -s.dir, right, -right] if home.length() > 1.0 else [s.dir, -s.dir, right, -right]
	var best := {}
	var best_score := -INF
	for d in ways:
		var start := HubRoads.reach(self, mid, d, Balance.INDUSTRY_ROAD_MAX)
		if start == Vector3.INF:
			continue
		var span := start.distance_to(mid)
		# It stops at the edge of the new tract's first pad, not on it.
		var end := mid + (start - mid) / maxf(span, 1.0) * Industry.PAD
		if start.distance_to(end) <= HubRoads.SNAP:
			continue
		var plan := HubRoads.check(self, [start, end], "site:%d" % id)
		if not plan.ok or plan.length > Balance.INDUSTRY_ROAD_MAX:
			continue
		var score: float = -plan.length - (2000.0 if plan.permit else 0.0)
		if score > best_score:
			best_score = score
			best = plan
	# The company pays for its road from what it has saved (Capital).
	if best.is_empty() or float(s.get("cash", 0.0)) < float(best.cost) + Balance.CAPITAL_RESERVE:
		s.road_wait = industry.day + Balance.INDUSTRY_ROAD_WAIT_DAYS
		return false
	if not best.permit:
		return _industry_open(id, cell, best.route, leader, float(best.cost))
	var what := "logging road" if s.kind == "forest" else "lease road"
	var req := permits.file(self, {"hub": "industry", "hub_id": id, "leader": leader,
		"title": "A gravel %s to new ground" % what,
		"why": "%s has worked out its lease and wants the next tract. The road would join the town's roads." \
			% leader,
		"route": HubRoads.flat(best.route), "width": RoadStyle.right_of_way_half(HubRoads.TYPE) * 2.0,
		"per_m": int(Economy.BUILD_PER_M[HubRoads.TYPE]), "base": 0, "budget": 0})
	if req == -1:
		s.road_wait = industry.day + Balance.INDUSTRY_ROAD_WAIT_DAYS
		return false
	s.pending = {"req": req, "cell": [cell.x, cell.y], "cost": float(best.cost)}
	return false


## Builds a company's lease road and takes on the tract beyond it.
func _industry_open(id: int, cell: Vector2i, route: Array, leader: String, cost: float) -> bool:
	var s: Dictionary = industry.sites[id]
	if route.size() < 2 or HubRoads.build(self, route, "site:%d" % id).is_empty():
		s.road_wait = industry.day + Balance.INDUSTRY_ROAD_WAIT_DAYS
		return false
	s.cash = float(s.get("cash", 0.0)) - cost
	if not s.has("leases"):
		s.leases = []
	s.leases.append(cell)
	var what := "a logging road into the next woods" if s.kind == "forest" else "a gravel lease road to the next tract"
	s.why = "%s worked out its lease, so it built %s. It's a town road now." % [leader, what]
	_lots_dirty = true
	_usable_cache.clear()
	return true


## How many cells of block b farm `id` could plant: free ground worth farming.
func _block_soil(id: int, b: Vector2i) -> int:
	var f: Dictionary = farms.farms[id]
	var n := 0
	var x0 := b.x * (Farms.BLOCK.x + 1) - Farms.BLOCK.x / 2
	var y0 := 0 if b.y == 0 else b.y * (Farms.BLOCK.y + 1)
	# Every other cell is enough to judge it.
	for i in range(0, Farms.BLOCK.x, 2):
		for j in range(0, Farms.BLOCK.y, 2):
			var c := Vector2i(x0 + i, y0 + j)
			var mid := Farms.cell_center(f, c)
			if farms.reserved_ok(mid) and farms.field_profit(f, c) + farms.support(id) > maxf(farms.buy_margin(id), 0.0) \
					and field_usable(mid, Farms.cell_corners(f, c)):
				n += 4
	return n


## Whether a water utility can put a piece of its yard on this square: no
## roads, other buildings, farms, industry, reserved land or built lots.
func yard_usable(corners: PackedVector2Array) -> bool:
	if Services.road_clash(network, corners):
		return false
	var mid := Vector3.ZERO
	for c in corners:
		mid += Vector3(c.x, 0.0, c.y) / corners.size()
	if not land_ok(mid, WaterUtility.CELL * 0.5):
		return false
	var pts := [mid]
	for c in corners:
		pts.append(mid.lerp(Vector3(c.x, 0.0, c.y), 0.9))
	for p in pts:
		if services.covers(p) or Capital.owner_of(self, p) != "" or reserves.kind_at(p) != "":
			return false
	for id in services.buildings:
		if not Geometry2D.intersect_polygons(corners, services.footprint(id)).is_empty():
			return false
	for key in buildings:
		if lots.has(key) and Geometry2D.is_point_in_polygon(Vector2(lots[key].pos.x, lots[key].pos.z), corners):
			return false
	return true


## Average share of fire, police, health and school cover across homes.
func service_coverage() -> float:
	var total := 0.0
	var n := 0
	for key in buildings:
		if buildings[key].zone == ZoneMap.Zone.RESIDENTIAL:
			total += services.coverage(key)
			n += 1
	return 0.0 if n == 0 else total / n


## What keeps the town from growing for want of power or water, in plain
## words (what's missing, why, and what to build), or "" if nothing does.
func utility_problem() -> String:
	return _utility_report()[1]


## The same, short enough for the top bar: "No power ($20,366 short)" or
## "74 lots: no power · 71: no water".
func utility_summary() -> String:
	return _utility_report()[0]


func _utility_report() -> Array:
	var zoned := []
	for key in lots:
		if zones.zone_at(lots[key].zone_pt) != ZoneMap.Zone.NONE:
			zoned.append(key)
	if zoned.is_empty():
		return ["", ""]
	for u in ["power", "water"]:
		var has_source := false
		for id in services.buildings:
			has_source = has_source or services.buildings[id].kind in Services.UTILITIES[u] \
				or (u == "water" and services.buildings[id].kind == Services.Kind.WATER_UTILITY)
		if not has_source:
			var starter: int = Services.Kind.POWER_FEED if u == "power" else Services.Kind.WELL
			var cost: int = Services.KINDS[starter].cost
			var full := "No %s: build a %s, under Utilities ($%s)" % [u, Services.KINDS[starter].name, money_text(cost)]
			var short := "No %s" % u
			if cost > economy.money:
				full += ". You need $%s more" % money_text(cost - economy.money)
				short += " ($%s short)" % money_text(cost - economy.money)
			return [short, full]
	# Count zoned lots each utility misses, and why.
	var missing := {"power": 0, "water": 0}
	var unlinked := {"power": 0, "water": 0}
	for key in zoned:
		var s: Dictionary = services.served.get(key, {})
		for u in missing:
			if not s.get(u, false):
				missing[u] += 1
				if not s.get(u + "_linked", false):
					unlinked[u] += 1
	var shorts := []
	var fulls := []
	for u in ["power", "water"]:
		if missing[u] == 0:
			continue
		shorts.append("%d lots: no %s" % [missing[u], u] if shorts.is_empty() else "%d: no %s" % [missing[u], u])
		var text := "%d zoned lots have no %s" % [missing[u], u]
		var going_up := utilities_going_up().filter(func(g): return g.utility == u)
		if not going_up.is_empty():
			text += ": the %s is still going in (%d%% done)" % [Services.KINDS[going_up[0].kind].name.to_lower(),
				roundi(float(going_up[0].state.total) * 100.0)]
		elif unlinked[u] > 0 and u == "water" and not services.water.utilities.is_empty():
			text += ": the water utility hasn't laid mains under their streets yet"
		elif unlinked[u] > 0:
			text += ": their streets aren't joined by road to a %s" % ("power line" if u == "power" else "water source")
		else:
			var use: Array = services.utility_use[u]
			text += ": %s is full (%s of %s homes), build a %s" % [u, money_text(use[0]), money_text(use[1]),
				"Substation" if u == "power" else "Water tower"]
		fulls.append(text)
	return [" · ".join(shorts), ". ".join(fulls)]


## Works out what every lot gets. A power line or well still going up
## supplies nothing until its crew is done, as a real one doesn't.
func _update_services() -> void:
	services.plants = power.sources()
	var off := {}
	for id in services.buildings:
		var kind: int = services.buildings[id].kind
		if (kind in Services.UTILITIES.power or kind in Services.UTILITIES.water) \
				and not construction.is_done("svc:%d" % id, tick_count):
			off[id] = true
	services.offline = off
	services.update(network, lots, buildings)


## Utilities still going up: [{id, kind, utility ("power"/"water"), state}],
## oldest first.
func utilities_going_up() -> Array:
	var out := []
	var ids := services.offline.keys()
	ids.sort()
	for id in ids:
		if not services.buildings.has(id):
			continue
		var kind: int = services.buildings[id].kind
		var st := construction.state("svc:%d" % id, tick_count)
		if not st.is_empty():
			out.append({"id": id, "kind": kind, "utility": Services.KINDS[kind].utility, "state": st})
	return out


## Buildings on zoned lots that lack power or water.
func unserved_count() -> int:
	var n := 0
	var served: Dictionary = services.served  # (services.has_utilities, read straight)
	for key in buildings:
		var s = served.get(key)
		if s == null or not (s.power and s.water):
			n += 1
	return n


func utilities_ok(key: String) -> bool:
	return _utilities_ok(key)


func _utilities_ok(key: String) -> bool:
	return not require_utilities or services.has_utilities(key)


func count_buildings(zone: int) -> int:
	var n := 0
	for key in buildings:
		if buildings[key].zone == zone:
			n += 1
	return n


## The street sides that make one block face with this one: the same side,
## followed through bends where only two roads meet, up to real junctions.
## Returns [[seg, side], ...].
func frontage_chain(seg: int, side: int) -> Array:
	var out := [[seg, side]]
	var seen := {seg: true}
	for from_b in [true, false]:
		var cur := seg
		var cur_side := side
		var at_b: bool = from_b
		while true:
			var node: int = network.segments[cur].b if at_b else network.segments[cur].a
			var here := network.segments_at(node)
			if here.size() != 2:
				break
			var nxt: int = here[0] if here[1] == cur else here[1]
			if seen.has(nxt) or not RoadStyle.TYPES[network.segments[nxt].type].lots:
				break
			seen[nxt] = true
			# Sides are left or right of a road's a-to-b direction, so they
			# swap when the next road runs the other way.
			var same_way: bool = (network.segments[nxt].a == node) == at_b
			cur_side = cur_side if same_way else -cur_side
			at_b = network.segments[nxt].a == node
			cur = nxt
			out.append([cur, cur_side])
	return out


## Paints a zone along one street side's frontage, where its lots read it.
## Zones both sides of new streets a builder laid (Subdivisions), the way
## the player zones a block face, and replans the lots.
func zone_new_streets(segs: Array, zone: int) -> void:
	planner.update(network)
	for seg in segs:
		if network.segments.has(seg):
			for side in [1, -1]:
				_paint_frontage(seg, side, zone)
	_clear_reserved_zones()
	_usable_cache.clear()
	_lots_dirty = true
	zones_changed.emit()


func _paint_frontage(seg: int, side: int, zone: int, from := -INF, to := INF) -> void:
	var s := planner.side_survey(network, seg, side)
	if s.is_empty():
		return
	# A strip from the sidewalk back about 17 m, so the zone stays when the
	# street is widened later (a Street to a Boulevard moves lots 8.5 m).
	for r in s.rays:
		if r[0] < from or r[0] > to:
			continue
		if r[3] >= 3.0:
			var p: Vector2 = (r[1] as Vector2) + (r[2] as Vector2) * LotPlanner.ZONE_PROBE
			zones.paint(Vector3(p.x, 0.0, p.y), 4.5, zone)
		if r[3] >= 18.0:
			var q: Vector2 = (r[1] as Vector2) + (r[2] as Vector2) * 12.0
			zones.paint(Vector3(q.x, 0.0, q.y), 5.5, zone)


## How well-off the neighbourhood at a point is, 0 to 1. Lot platting reads
## it (wealthier streets get wider lots). Neutral until land value and
## neighbourhood success are simulated.
func wealth_at(_p: Vector2) -> float:
	return 0.5


## Dirty ground seeps down the real land.
func _hook_pollution() -> void:
	pollution.height = func(p: Vector3) -> float:
		return Terrain.height(p.x + terrain_offset.x, p.z + terrain_offset.y)


## A lot's land value factor (1.0 = no change): the hubs nearby, trash left
## out, pollution, and an old building's charm.
func land_factor(key: String) -> float:
	return hubs.lot_factor(self, key) * pollution.lot_factor(self, key) * heritage.land(key) * care.land(key)


func _lot_blocked(lot: Dictionary) -> bool:
	if services.overlaps(lot.corners):
		return true
	for p in [lot.pos, lot.front, lot.zone_pt]:
		if services.covers(p) or Capital.owner_of(self, p) != "" \
				or reserves.kind_at(p) != "" or hubs.covers(p) or warehouses.covers(p) or parks.covers(p) or education.covers(p) \
				or mail.covers(p) or power.covers(p) or banks.covers(p) or rail.covers(p) or telecom.covers(p) or big.covers(p):
			return true
	# No lots in the water, on ground too steep to build on, or on a state
	# highway's right of way (the state's land, joined or not).
	var at: Vector3 = lot.pos
	if not _land_ok.has(at):
		if _land_ok.size() > 200_000:
			_land_ok.clear()
		_land_ok[at] = land_ok(at, LotPlanner.FRONTAGE * 0.5) \
			and Highways.distance(at.x + terrain_offset.x, at.z + terrain_offset.y) >= HIGHWAY_LOT_CLEAR
	# Nor across a county road's gravel (joined or still painted on the
	# land), which would cut it in two.
	return not _land_ok[at] or _county_under(lot.corners, CountyGrid.HALF_WIDTH)


## Why a street side's zoning gets no lots where it doesn't, in a few words
## for the zone tool ("" when nothing stops them): the first thing in the
## way of its lots that were planned but dropped.
func lots_blocked_why(seg: int, side: int) -> String:
	for key in _blocked_by:
		var e: Array = _blocked_by[key]
		var lot: Dictionary = e[0]
		if not e[1] or int(lot.seg) != seg or int(lot.side) != side:
			continue
		var why := _block_reason(lot)
		if why != "":
			return why
	return ""


func _block_reason(lot: Dictionary) -> String:
	if services.overlaps(lot.corners):
		return "a public building or parking lot stands here"
	for p in [lot.pos, lot.front, lot.zone_pt]:
		var owner := Capital.owner_of(self, p)
		if owner.begins_with("farm:"):
			return "a farm owns this land"
		if owner != "":
			return "a company's site owns this land"
		if reserves.kind_at(p) != "":
			return "it's inside a land use outline (%s)" % reserves.kind_at(p)
		if parks.covers(p):
			return "a park or trail is here"
		if services.covers(p) or hubs.covers(p) or warehouses.covers(p) or education.covers(p) or mail.covers(p) \
				or power.covers(p) or banks.covers(p) or rail.covers(p) or telecom.covers(p) or big.covers(p):
			return "a public building or site stands here"
	var at: Vector3 = lot.pos
	if not land_ok(at, LotPlanner.FRONTAGE * 0.5):
		return "the ground is too wet or steep to build on"
	if Highways.distance(at.x + terrain_offset.x, at.z + terrain_offset.y) < HIGHWAY_LOT_CLEAR:
		return "it's the state highway's right of way"
	if _county_under(lot.corners, CountyGrid.HALF_WIDTH):
		return "a county road runs through here (build a street on it, or bulldoze it)"
	return ""


## Notes which lots changed (for lots_changed listeners), when only these did.
func note_lots(keys: Array) -> void:
	lots_delta = keys
	lots_delta_full = false
	touched_lots(keys)


## Lots reshaped or moved in place (merged, split, carried along with their
## street): the next full lot check looks at them again wherever they are,
## as it would if it looked at every lot.
func touched_lots(keys: Array) -> void:
	for key in keys:
		_lots_touched[key] = true
		_lot_ix_stale[key] = true
	if not keys.is_empty():
		_lot_rev += 1  # lots_near files them again, wherever they are now


## Works out lots_delta: lots added, gone or changed since `was`. Unchanged
## lots are the same Dictionary (LotPlanner hands back a lot cut the same way
## as before as the same one), so this is a quick identity check.
func _lots_delta(was: Dictionary, full: bool) -> void:
	var keys := []
	for key in lots:
		if not is_same(was.get(key), lots[key]):
			keys.append(key)
	for key in was:
		if not lots.has(key):
			keys.append(key)
	keys.sort()
	lots_delta = keys
	lots_delta_full = full


## Something that keeps lots off the ground (a farm's fields, say) changed,
## but only inside these boxes (Rect2s): the next refresh checks the lots
## there again, built or not, and leaves the rest as they stand, rather
## than checking every lot in town (seconds in a big one). Saved, so a copy
## loaded before the refresh checks the same lots.
func lots_changed_near(boxes: Array) -> void:
	_lots_near.append_array(boxes)


## The boxes of farms whose ground changed between two Farms.ground_boxes.
static func _farm_boxes(before: Dictionary, after: Dictionary) -> Array:
	var out := []
	for id in before:
		if not after.has(id) or after[id][0] != before[id][0]:
			out.append(before[id][1])
	for id in after:
		if not before.has(id) or after[id][0] != before[id][0]:
			out.append(after[id][1])
	return out


## Boxes ready for _lot_near: [the box around them all, then the boxes].
static func _near_of(boxes: Array) -> Array:
	if boxes.is_empty():
		return []
	var all: Rect2 = boxes[0]
	for b in boxes:
		all = all.merge(b)
	return [all] + boxes


## Whether a lot reaches into any of these boxes (its outline and the
## points _lot_blocked looks at). `near` from _near_of (or plain boxes).
static func _lot_near(lot: Dictionary, near: Array) -> bool:
	if near.is_empty():
		return false
	var box := Rect2(Vector2(lot.pos.x, lot.pos.z), Vector2.ZERO)
	for q in lot.corners:
		box = box.expand(q)
	for p in [lot.front, lot.zone_pt]:
		box = box.expand(Vector2(p.x, p.z))
	if not (near[0] as Rect2).intersects(box, true):
		return false
	for i in range(1, near.size()):
		if (near[i] as Rect2).intersects(box, true):
			return true
	return near.size() == 1


## The keys of lots whose outline, middle, front or zone point could fall
## in `area` (the box around them all meets it), in no particular order: a search
## of one patch of town looks at the lots there, not every lot. Kept until
## the lots change (lots_changed).
func lots_near(area: Rect2) -> Array:
	var key := [lots.size(), _lot_rev]
	if not is_same(lots, _lot_cells_of) or key != _lot_cells_key:
		_lot_cells_of = lots
		_lot_cells_key = key
		_index_lots()
	var seen := {}
	for x in range(floori(area.position.x / LOT_CELL), floori(area.end.x / LOT_CELL) + 1):
		for y in range(floori(area.position.y / LOT_CELL), floori(area.end.y / LOT_CELL) + 1):
			for k in _lot_cells.get(Vector2i(x, y), []):
				if not seen.has(k) and (_lot_boxes[k] as Rect2).intersects(area, true):
					seen[k] = true
	return seen.keys()


## Brings lots_near's index up to date: lots gone, replaced or reshaped in
## place (note_lots, touched_lots) come out, and new ones go in, rather
## than every lot in town being filed again after each check.
func _index_lots() -> void:
	var gone := []
	for k in _lot_ix:
		if not lots.has(k) or not is_same(lots[k], _lot_ix[k]) or _lot_ix_stale.has(k):
			gone.append(k)
	_lot_ix_stale.clear()
	for k in gone:
		var box: Rect2 = _lot_boxes[k]
		for x in range(floori(box.position.x / LOT_CELL), floori(box.end.x / LOT_CELL) + 1):
			for y in range(floori(box.position.y / LOT_CELL), floori(box.end.y / LOT_CELL) + 1):
				var list: Array = _lot_cells.get(Vector2i(x, y), [])
				list.erase(k)
		_lot_boxes.erase(k)
		_lot_ix.erase(k)
	for k in lots:
		if _lot_ix.has(k):
			continue
		var lot: Dictionary = lots[k]
		var box := Rect2(Vector2(lot.pos.x, lot.pos.z), Vector2.ZERO)
		for q in lot.corners:
			box = box.expand(q)
		for p in [lot.front, lot.zone_pt]:
			box = box.expand(Vector2(p.x, p.z))
		_lot_boxes[k] = box
		_lot_ix[k] = lot
		for x in range(floori(box.position.x / LOT_CELL), floori(box.end.x / LOT_CELL) + 1):
			for y in range(floori(box.position.y / LOT_CELL), floori(box.end.y / LOT_CELL) + 1):
				var c := Vector2i(x, y)
				if not _lot_cells.has(c):
					_lot_cells[c] = []
				_lot_cells[c].append(k)


const LOT_CELL := 64.0
var _lot_ix := {}  # lot key -> the lot it was filed as (lots_near)
var _lot_ix_stale := {}  # lot keys reshaped in place since (note_lots, touched_lots)
var _lot_rev := 0  # goes up with every lots_changed
## What kept lots off the ground at the last full check (LotGround.items).
## Not saved: a loaded copy's first full check looks at every lot, which
## comes out the same.
var _ground_was := {}
var _lots_touched := {}  # lot key -> true (see touched_lots)
## Tools set this to check that lots away from what changed really are
## unchanged (_verify_ground), printing GROUND MISMATCH where not.
static var verify_ground := false
## How many GROUND MISMATCH lines were printed (for tests to fail on).
static var ground_mismatches := 0


func _verify_ground(near: Array) -> void:
	for key in lots:
		if not _lot_near(lots[key], near) and _lot_blocked(lots[key]):
			print("GROUND MISMATCH lot %s now blocked, away from what changed" % key)
			ground_mismatches += 1
	for key in _blocked_by:
		var e: Array = _blocked_by[key]
		if not _lot_near(e[0], near) and _lot_blocked(e[0]) != bool(e[1]):
			print("GROUND MISMATCH planned lot %s changed, away from what changed" % key)
			ground_mismatches += 1
var _lot_cells_of := {}
var _lot_cells_key := []
var _lot_cells := {}  # Vector2i -> [lot keys]
var _lot_boxes := {}  # lot key -> Rect2


## The lots buildings stand on, by key.
func _parcel_lots() -> Dictionary:
	var out := {}
	for key in buildings:
		if lots.has(key):
			out[key] = lots[key]
	return out


## Built parcels plus the ground of public sites (services, parking lots and
## parks) as fixed outlines: lots beside one stop at its edge, the way a lot
## backing onto a city parking lot is just shorter, instead of being lost.
## Keys have no ":" so they never pass for a lot.
func _with_sites(frozen: Dictionary) -> Dictionary:
	if services.buildings.is_empty() and parks.sites.is_empty():
		return frozen
	var out := frozen.duplicate()
	for id in services.buildings:
		out["svc-%d" % id] = {"corners": services.footprint(id)}
	for id in parks.sites:
		out["park-%d" % id] = {"corners": parks.footprint(id)}
	return out


func _refresh() -> void:
	if _hold_until > 0:
		if tick_count < _hold_until and not _lots_dirty:
			return
		_hold_until = 0
	if _replan_at > 0:
		# A big town's road or zoning edit: the lots catch up when it's due.
		if tick_count < _replan_at:
			return
		_replan_at = 0
	if _roads_moved:
		_road_wins()
	if _lots_dirty or _lots_light or not _lots_near.is_empty():
		var tr := Perf.now()
		var full := _lots_dirty
		# Where lots must be checked again though no road came near them.
		var near: Array = [] if full else _lots_near
		if full:
			# Only lots by what came, went or changed shape since the last
			# full check can have gained or lost something under them.
			var ground := LotGround.items(self)
			var changed = LotGround.diff(_ground_was, ground)
			_ground_was = ground
			if changed != null:
				full = false
				near = changed + _lots_near
				for key in _lots_touched:
					if lots.has(key):
						near.append(LotGround.lot_box(lots[key]))
				if verify_ground:
					_verify_ground(_near_of(near))
			_lots_touched.clear()
		near = _near_of(near)
		var was := lots
		_lots_dirty = false
		_lots_light = false
		_lots_near = []
		planner.update(network)
		if not full and _plan_same() and not _near_any_lot(near):
			# Nothing planning reads has changed since the lots were last
			# planned (roads, zoning, the parcels built on, public sites), and
			# whatever changed is away from every lot: planning again would
			# hand back these very lots. What else a check does is done.
			planner.revalidated()
			_usable_cache.clear()
			lots_delta = []
			lots_delta_full = false
			Perf.add("sim.lots.revalidate", tr)
			tr = Perf.now()
			_update_services()
			Perf.add("sim.lots.services", tr)
			_zone_check_lots = {}  # the buildings are checked against their zones, as after any check
		else:
			_plan_lots(was, full, near)
	# Buildings go away when their lot disappears or its zone changes, so
	# this only needs a look after zoning, lots or buildings change.
	_check_zones()


## The part of _refresh that plans the lots again (see there).
func _plan_lots(was: Dictionary, full: bool, near: Array) -> void:
		var tr := Perf.now()
		var plan_keys: int = ledger().sig
		# Lots with buildings are parcels: they stay as they are unless a road
		# now runs through them.
		var frozen := {}
		var lost := []
		var keys: Array = ledger().sorted  # the buildings' keys, sorted
		if not full and planner.changed_boxes.is_empty():
			# No road changed: every parcel stands as it is (unless whatever
			# changed near it is in its way now).
			for key in keys:
				if lots.has(key):
					if _lot_near(lots[key], near) and _lot_blocked(lots[key]):
						lost.append(key)
					else:
						frozen[key] = lots[key]
			keys = []
		for key in keys:
			if lots.has(key):
				var lot := planner.revalidate(network, lots[key])
				if not full and is_same(lot, lots[key]) and not _lot_near(lot, near):
					frozen[key] = lot  # no road came near it
				elif not lot.is_empty() and not _lot_blocked(lot):
					frozen[key] = lot
				else:
					lost.append(key)
		planner.revalidated()
		Perf.add("sim.lots.revalidate", tr)
		tr = Perf.now()
		lots = frozen.duplicate()
		if not lost.is_empty():
			parcels_lost.emit(lost)
		var blocked := {}
		for lot in planner.plan(network, zones, _with_sites(frozen)):
			# No lots under a service building.
			var had: Array = _blocked_by.get(lot.key, [])
			var no: bool = had[1] if not full and not had.is_empty() and is_same(had[0], lot) \
				and not _lot_near(lot, near) else _lot_blocked(lot)
			blocked[lot.key] = [lot, no]
			if not no:
				lots[lot.key] = lot
		_blocked_by = blocked
		_usable_cache.clear()
		_lots_delta(was, full)
		Perf.add("sim.lots.plan", tr)
		tr = Perf.now()
		_update_services()
		Perf.add("sim.lots.services", tr)
		lots_changed.emit()
		_planned = [plan_keys, _sites_sig(), _lot_rev]
		_planned_lots = lots


## What the lots were last planned from: [the buildings' key set
## (ledger().sig), the public sites (_sites_sig), _lot_rev], and the lots
## that came out.
var _planned := []
var _planned_lots := {}


## True when planning the lots now would read exactly what it read last
## time: no road, zoning or survey change waiting, the same buildings on the
## same lots, the same public sites. (LotPlanner.plan hands back the same
## lots for the same inputs.)
func _plan_same() -> bool:
	if _planned.is_empty() or not is_same(lots, _planned_lots) or _lot_rev != int(_planned[2]):
		return false
	if not planner.changed_boxes.is_empty() or not planner._pending.is_empty() or not zones.dirty.is_empty() \
			or not planner._dirty.is_empty() or planner._fresh or not planner._warm_list.is_empty():
		return false
	return int(_planned[0]) == ledger().sig and int(_planned[1]) == _sites_sig()


## The public sites planning treats as parcels (_with_sites), as one hash.
func _sites_sig() -> int:
	var sites := []
	for id in services.buildings:
		sites.append([id, services.footprint(id)])
	for id in parks.sites:
		sites.append([id, parks.footprint(id)])
	return hash(sites)


## Whether any lot, built or planned (kept off the ground or not), reaches
## into these boxes (from _near_of).
func _near_any_lot(near: Array) -> bool:
	if near.is_empty():
		return false
	for i in range(1, near.size()):
		for key in lots_near(near[i]):
			if _lot_near(lots[key], [near[i]]):
				return true
	for key in _blocked_by:
		if _lot_near(_blocked_by[key][0], near):
			return true
	return false


func _check_zones() -> void:
	var check := [zones.revision, lots.size(), buildings.size()]
	if check == _zone_check and is_same(lots, _zone_check_lots):
		return
	_zone_check = check
	_zone_check_lots = lots
	var removed := false
	for key in buildings.keys():
		if not lots.has(key) or zones.zone_at(lots[key].zone_pt) != buildings[key].zone:
			buildings.erase(key)
			removed = true
	if removed:
		buildings_changed.emit()


## Whether a built parcel reaches into this outline by more than a sliver
## (a back yard counts, not just the house): a service growing there has to
## buy it whole.
func parcel_under(key: String, poly: PackedVector2Array) -> bool:
	return lots.has(key) and Services.shared_area(lots[key].corners, poly) > 4.0


## True when the land at a point (and `radius` around it) is dry and gentle
## enough to build on.
func land_ok(p: Vector3, radius := 0.0) -> bool:
	return Terrain.buildable(p.x + terrain_offset.x, p.z + terrain_offset.y, radius)


## Why a road can't be built under real US road rules, or "" if it can.
func road_problem(c: Array, type: int) -> String:
	var flat := Vector2(c[2].x - c[0].x, c[2].z - c[0].z).length()
	if flat < RoadNetwork.MIN_LENGTH:
		return "Too short."
	var r := RoadNetwork.min_radius(c[0], c[1], c[2])
	if r < RoadStyle.MIN_CURVE_RADIUS:
		return "Bend too tight: %d m. Roads need at least %d m (42 ft) so trucks can turn (AASHTO)." \
			% [int(r), int(RoadStyle.MIN_CURVE_RADIUS)]
	var spec: Dictionary = RoadStyle.TYPES[type]
	var grade := absf(c[2].y - c[0].y) / flat
	if grade > spec.grade + 0.0001:
		return "Too steep: %d%% grade. A %s can climb at most %d%% (AASHTO)." \
			% [roundi(grade * 100.0), spec.name, roundi(spec.grade * 100.0)]
	var problem := network.crossing_problem(c[0], c[1], c[2])
	if problem == "":
		problem = land_problem([c])
	var saved := reserves.crosses(RoadNetwork.sample_curve(c[0], c[1], c[2], 24))
	if problem == "" and saved != "":
		problem = "That land is reserved for %s. Clear the reserve first." % Reserves.KINDS[saved]
	if problem == "" and Economy.road_cost(c, type) > economy.money:
		return "Not enough money: this road costs $%s." % money_text(Economy.road_cost(c, type))
	return problem


## Why a road built as these pieces (an overpass and its approaches) can't
## go in ("" if it can): each piece meets the road rules, and the town can
## pay for them all.
func pieces_problem(pieces: Array, type: int) -> String:
	if pieces.size() == 1:
		return road_problem(pieces[0], type)
	for q in pieces:
		var why := road_problem(q, type)
		if why != "" and not why.begins_with("Not enough money"):
			return why
	if shapes_cost(pieces, type) > economy.money:
		return "Not enough money: this road costs $%s." % money_text(shapes_cost(pieces, type))
	return ""


## Whose land these road pieces cross ("" when it's this town's or open
## land). Only in a region (land_check).
func land_problem(curves: Array) -> String:
	if not land_check.is_valid():
		return ""
	var pts := []
	for c in curves:
		for q in RoadNetwork.sample_curve(c[0], c[1], c[2], 8):
			pts.append(Vector2(q.x, q.z))
	return land_check.call(pts)


## Why a new neighborhood can't start here ("" if it can).
func neighborhood_problem(spot: Vector2) -> String:
	if neighborhoods.slots_free(int(stats.population)) <= 0:
		if neighborhoods.sites.size() >= Balance.NEIGHBORHOOD_MAX:
			return "A town can have %d neighborhoods." % Balance.NEIGHBORHOOD_MAX
		return "Grow to the next town stage to earn another neighborhood."
	if neighborhoods.fee() > economy.money:
		return "Not enough money: a new neighborhood costs $%s." % money_text(neighborhoods.fee())
	if network.nodes.is_empty():
		return "Build your first roads at home first."
	if site_check.is_valid():
		return site_check.call(spot)
	return ""


## The nearest road node to a spot, on the ground plane.
func _nearest_road_xz(to: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for n in network.nodes:
		var q: Vector3 = network.nodes[n]
		var d := Vector2(q.x, q.z).distance_squared_to(to)
		if d < best_d:
			best_d = d
			best = Vector2(q.x, q.z)
	return best


## The land this town has built on, as LAND_CELL squares (centres, town
## coordinates): its buildings, its town centre and its neighborhood sites.
## Neighbors use it to tell whose land is whose without the whole town.
func land_cells() -> PackedVector2Array:
	var cell := Balance.LAND_CELL
	var seen := {}
	var add := func(p: Vector2):
		seen[Vector2i(floori(p.x / cell), floori(p.y / cell))] = true
	add.call(Vector2.ZERO)
	for s in neighborhoods.sites:
		add.call(s.at)
	for key in buildings:
		if lots.has(key):
			var p: Vector3 = lots[key].pos
			add.call(Vector2(p.x, p.z))
	var out := PackedVector2Array()
	for k in seen:
		out.append((Vector2(k) + Vector2(0.5, 0.5)) * cell)
	return out


## What it costs to build these road pieces.
static func shapes_cost(curves: Array, type: int) -> int:
	var total := 0
	for c in curves:
		total += Economy.road_cost(c, type)
	return total


## What upgrading a road costs: the difference in build price, nothing to
## downgrade. -1 if there is no such road.
## Builds a road, but where it runs along a road already there (a county
## road it follows, a street drawn over again) it takes that road's place
## instead of being laid on top: that stretch becomes the new type, as an
## upgrade, and only the rest is new road. True if anything changed. With
## `retype` false the old roads keep their type (a county road joined
## along a street the player drew onto its line stays that street).
func _build_over(c: Array, type: int, retype := true) -> bool:
	var n := maxi(2, ceili(Vector2(c[2].x - c[0].x, c[2].z - c[0].z).length() / OVERLAY_STEP))
	var along := []  # per sample: the segment it runs along, or -1
	var any := false
	for i in n + 1:
		var t := float(i) / n
		var p := RoadNetwork.bezier(c[0], c[1], c[2], t)
		var hit := RoadIndex.segment_near(network, p, OVERLAY_NEAR, RoadNetwork.SAME_LEVEL)
		var seg := -1
		if not hit.is_empty():
			var sc := network.curve_of(hit.seg)
			var a := RoadNetwork.bezier_tangent(c[0], c[1], c[2], t)
			var b := RoadNetwork.bezier_tangent(sc[0], sc[1], sc[2], hit.t)
			if absf(Vector2(a.x, a.z).normalized().dot(Vector2(b.x, b.z).normalized())) > OVERLAY_PARALLEL:
				seg = hit.seg
				any = true
		along.append(seg)
	if not any:
		var built := network.build_road(c[0], c[1], c[2], type)
		if built:
			economy.money -= Economy.road_cost(c, type)
		return built
	# Runs of new road between the stretches along old ones. Each run ends
	# on the old road where it meets it, so the two join.
	var ok := false
	var runs := []
	var i := 0
	while i <= n:
		if along[i] != -1:
			i += 1
			continue
		var j := i
		while j < n and along[j + 1] == -1:
			j += 1
		runs.append([maxi(i - 1, 0), mini(j + 1, n)])
		i = j + 1
	network.begin_batch()
	for r in runs:
		var t0 := float(r[0]) / n
		var t1 := float(r[1]) / n
		var a := RoadNetwork.bezier(c[0], c[1], c[2], t0)
		var b := RoadNetwork.bezier(c[0], c[1], c[2], t1)
		for k in [0, 1]:
			var idx: int = r[k]
			if along[idx] != -1 and network.segments.has(along[idx]):
				var on := RoadIndex.segment_near(network, a if k == 0 else b, OVERLAY_NEAR * 2.0, RoadNetwork.SAME_LEVEL)
				if not on.is_empty():
					if k == 0:
						a = on.point
					else:
						b = on.point
		var sub := [a, RoadNetwork.sub_control(c[0], c[1], c[2], t0, t1), b]
		if network.build_road(sub[0], sub[1], sub[2], type):
			economy.money -= Economy.road_cost(sub, type)
			ok = true
	if not retype:
		network.end_batch()
		return ok
	# Where the new road starts or ends partway along an old one, the old
	# one is cut there, so only the stretch it covers changes.
	for k in [0, n]:
		if along[k] != -1:
			var end := RoadIndex.segment_near(network, c[0] if k == 0 else c[2], OVERLAY_NEAR, RoadNetwork.SAME_LEVEL)
			if not end.is_empty() and end.t > 0.02 and end.t < 0.98:
				network.split_segment(end.seg, end.t)
	network.end_batch()
	# The stretches along old roads: those roads take the new type.
	var seen := {}
	var line := RoadNetwork.sample_curve(c[0], c[1], c[2], n)
	for p in line:
		var hit := RoadIndex.segment_near(network, p, OVERLAY_NEAR, RoadNetwork.SAME_LEVEL)
		if hit.is_empty() or seen.has(hit.seg) or int(network.segments[hit.seg].type) == type:
			continue
		var sc := network.curve_of(hit.seg)
		var mid := RoadNetwork.bezier(sc[0], sc[1], sc[2], 0.5)
		# Only a road the new one runs along, not one it merely meets.
		if _off_line(line, mid) > OVERLAY_NEAR:
			continue
		seen[hit.seg] = true
		if RoadStyle.is_ring(int(network.segments[hit.seg].type)) or RoadStyle.is_ring(type):
			continue
		var cost := upgrade_cost(hit.seg, type)
		if cost >= 0 and cost <= economy.money and network.set_type(hit.seg, type):
			economy.money -= cost
			ok = true
	return ok


## How far a point is from a polyline, across the ground.
static func _off_line(line: PackedVector3Array, p: Vector3) -> float:
	var best := INF
	var q := Vector3(p.x, 0, p.z)
	for i in line.size() - 1:
		var a := Vector3(line[i].x, 0, line[i].z)
		var b := Vector3(line[i + 1].x, 0, line[i + 1].z)
		best = minf(best, Geometry3D.get_closest_point_to_segment(q, a, b).distance_to(q))
	return best


## A new road this near an old one, running parallel to it, runs along it
## rather than beside it (metres; the cosine of the angle between them).
const OVERLAY_NEAR := 2.5
const OVERLAY_PARALLEL := 0.97
const OVERLAY_STEP := 4.0


func upgrade_cost(seg: int, type: int) -> int:
	if not network.segments.has(seg):
		return -1
	var c := network.curve_of(seg)
	return maxi(0, Economy.road_cost(c, type) - Economy.road_cost(c, network.segments[seg].type))


func _can_afford(curves: Array, type: int) -> bool:
	return shapes_cost(curves, type) <= economy.money


## Dollars with thousands separators: 1234567 -> "1,234,567".
static func money_text(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Builds the ring, joining every road it crosses, then clears the roads
## left inside it.
## The ring pieces of the roundabout `seg` belongs to.
func ring_of(seg: int) -> Array:
	var out := [seg]
	var todo := [seg]
	while not todo.is_empty():
		var sg: Dictionary = network.segments[todo.pop_back()]
		for n in [sg.a, sg.b]:
			for other in network.segments_at(n):
				if not other in out and RoadStyle.is_ring(network.segments[other].type):
					out.append(other)
					todo.append(other)
	return out


func _build_roundabout(center: Vector3, radius: float, type: int) -> bool:
	network.begin_batch()
	var ok := false
	for arc in RoadShapes.roundabout(center, radius):
		ok = network.build_road(arc[0], arc[1], arc[2], type, true) or ok
	for id in network.segments.keys():
		var c := network.curve_of(id)
		var mid := RoadNetwork.bezier(c[0], c[1], c[2], 0.5)
		if mid.distance_to(center) < radius - 2.0:
			network.remove_segment(id)
	network.end_batch()
	return ok


## Starts one new building on an empty zoned lot, by demand. Returns its lot
## key, or "". `salt` gives a second, different pick in the same tick.
func _grow_one(salt := 0) -> String:
	var empty := empty_zoned_lots()
	if empty.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([city_seed, tick_count]) if salt == 0 else hash([city_seed, tick_count, salt])
	# Each zone gets a chance to build in proportion to its demand.
	var by_zone := {}
	for key in empty:
		var z := zones.zone_at(lots[key].zone_pt)
		if not by_zone.has(z):
			by_zone[z] = []
		by_zone[z].append(key)
	var zone_order := by_zone.keys()
	zone_order.sort()
	for z in zone_order:
		# Growth on the Economy page: Hold builds nothing new, Expand more.
		var pace := policies.pick(Balance.POLICY_BUILD_PACE, "growth", Economy.ZONE_AREA.get(z, "homes"))
		if rng.randf() >= demand[z] * pace:
			continue
		var list: Array = by_zone[z]
		var key: String = list[rng.randi() % list.size()]
		# Nobody wants to build next to a smoky old power plant.
		if z != ZoneMap.Zone.INDUSTRIAL and not power.sites.is_empty() \
				and rng.randf() < -power_nuisance(lots[key].pos) * Balance.POWER_SMOKE_GROWTH:
			continue
		var bseed := rng.randi()
		# The lot's owner picks what to build from what is around it.
		var choice := BuildingTypes.pick(self, key, z, rng)
		var b := {"zone": z, "seed": bseed, "built": tick_count, "changed": tick_count, "occ": 0}
		b = BuildingTypes.make(self, key, b, choice[0], 0)
		b.why = choice[1]
		buildings[key] = b
		if z == ZoneMap.Zone.INDUSTRIAL:
			buildings[key].chain = factory_chain(lots[key].pos)
		var lot: Dictionary = lots[key]
		construction.start("lot:" + key, PROFILE_OF_ZONE[z], tick_count, lot.front, -lot.normal, lot.to_curb)
		buildings_changed.emit()
		return key
	return ""


## What a bank's month or lending round changed.
func _bank_changes(c: Dictionary) -> void:
	if c.get("farms", false):
		_lots_dirty = true
		farms_changed.emit()
	if c.get("industry", false):
		_lots_dirty = true
		industry_changed.emit()
	if c.get("banks", false):
		_lots_dirty = true
		banks_changed.emit()


## A family opens a business on an empty zoned lot (Families, after the
## player approved its permit): a shop, or a factory making `chain`.
func found_business(key: String, zone: int, chain := "") -> bool:
	if buildings.has(key) or not lots.has(key):
		return false
	var bseed := hash([city_seed, key, tick_count, "family"])
	buildings[key] = {"zone": zone, "seed": bseed, "built": tick_count, "cap": capacity(zone, bseed), "occ": 0}
	if zone == ZoneMap.Zone.INDUSTRIAL:
		buildings[key].chain = chain if Balance.FACTORY_CHAINS.has(chain) else factory_chain(lots[key].pos)
	# It goes up like any other building, crew and all.
	var lot: Dictionary = lots[key]
	construction.start("lot:" + key, PROFILE_OF_ZONE[zone], tick_count, lot.front, -lot.normal, lot.to_curb)
	buildings_changed.emit()
	return true


## Ground beside a company's yard it may build an add-on on: buildable,
## unzoned, clear of roads, and nobody else's (Capital.land_free).
func _addon_free(p: Vector3, who: String) -> bool:
	return land_ok(p) and zones.zone_at(p) == ZoneMap.Zone.NONE \
		and RoadIndex.segment_near(network, p, 12.0).is_empty() and not big.covers(p) \
		and Capital.land_free(self, [p], who)


## Each farm and company leader takes their next step up their tree.
func _develop_hubs() -> void:
	var ids := farms.farms.keys()
	ids.sort()
	var farm_built := false
	for id in ids:
		var f: Dictionary = farms.farms[id]
		if not f.has("leader"):
			f.leader = Agency.leader(self, hash([city_seed, "farm", id]))
		if not Agency.develop(self, f, Agency.TREES.farm, f.pos, farms.yearly_profit(id)).is_empty():
			farm_built = true
	ids = industry.sites.keys()
	ids.sort()
	var site_built := false
	for id in ids:
		var s: Dictionary = industry.sites[id]
		if not s.has("leader"):
			s.leader = Agency.leader(self, hash([city_seed, "site", id]))
		var who := "site:%d" % id
		var free := func(p: Vector3) -> bool: return _addon_free(p, who)
		# Upgrades from before they took ground find theirs now.
		for had in s.get("built", []):
			if Industry.ADDONS.get(s.kind, {}).has(had) and not s.get("addons", {}).has(had):
				site_built = industry.place_addon(id, had, free) or site_built
		var node := Agency.develop(self, s, Agency.TREES[s.kind], s.pos, industry.yearly_profit(id))
		if node.is_empty():
			continue
		if industry.place_addon(id, node.id, free):
			site_built = true
			continue
		# No ground for it beside the yard: it isn't built after all.
		s.built.erase(node.id)
		if s.has("cap_day"):
			s.cash = float(s.cash) + float(node.cost)
		s.why = "%s wanted to build %s, but there's no free ground beside the yard." % [
			"Its owner", str(node.name).to_lower()]
	if farm_built:
		farms_changed.emit()
	if site_built:
		industry_changed.emit()
	ids = power.sites.keys()
	ids.sort()
	var power_built := false
	var ctx := power_context()
	for id in ids:
		if power.develop(self, id, ctx):
			power_built = true
		if power.farmland(self, id):
			power_built = true
	if power_built:
		_lots_dirty = true
		power_changed.emit()


## What a new factory here would make (a key of Balance.FACTORY_CHAINS):
## the chain with the most output nearby, counting closer supply more, or
## "general" when nothing local is near enough (Brawn: factories follow the
## town's industry).
func factory_chain(at: Vector3) -> String:
	var score := {"mill": 0.0, "sawmill": 0.0, "refinery": 0.0, "metal": 0.0}
	var reach := Balance.FACTORY_CHAIN_REACH
	for id in farms.farms:
		var f: Dictionary = farms.farms[id]
		var d: float = f.pos.distance_to(at)
		if d < reach:
			# A 1,000-bushel truck a month for about every 15 acres of corn.
			score.mill += f.cells.size() * Farms.ACRES_PER_CELL / 15.0 * (1.0 - d / reach)
	var by_kind := {"forest": "sawmill", "oil": "refinery", "ore": "metal"}
	for id in industry.sites:
		var s: Dictionary = industry.sites[id]
		var d: float = s.pos.distance_to(at)
		if d < reach:
			score[by_kind[s.kind]] += Balance.INDUSTRY[s.kind].loads * s.pads.size() * (1.0 - d / reach)
	var best := "general"
	var best_v := Balance.FACTORY_CHAIN_MIN
	for k in ["mill", "sawmill", "refinery", "metal"]:
		if score[k] > best_v:
			best_v = score[k]
			best = k
	return best


## Now and then a grown building moves up its growth path (a starter home
## adds a storey, a Main Street block goes up a floor), or turns into another
## type when the area calls for it. One building per check, chosen the same
## way on every copy of the city.
func _develop_one() -> void:
	var keys := []
	for key in buildings:
		if lots.has(key) and BuildingTypes.ready(self, key):
			keys.append(key)
	if keys.is_empty():
		return
	keys.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([city_seed, tick_count, "develop"])
	if rng.randf() >= Balance.DEVELOP_CHANCE:
		return
	# Try a few owners: not every one has somewhere to go.
	for i in mini(keys.size(), 6):
		var key: String = keys[rng.randi() % keys.size()]
		var opts := BuildingTypes.options(self, key)
		if opts.is_empty():
			# Room to go up but not on this lot: buy the lot next door.
			if BuildingTypes.assemble(self, key) != "":
				return
			continue
		var o: Array = opts[rng.randi() % opts.size()]
		# Up a level only with its needs mostly met (Nathan, 2026-10-25:
		# "the level goes up or down based on whether it has what it needs").
		# (Towns that don't track utilities, as in some tests, skip this:
		# their needs read as unpowered.)
		if require_utilities and o[0] == BuildingTypes.type_of(buildings[key]) \
				and int(o[1]) > int(buildings[key].get("level", 0)) \
				and int(Inspect.needs(self, key).met) < Balance.LEVEL_UP_MET:
			continue
		# Protected old buildings stay as they are; a charming one asks the
		# town before it comes down (Heritage).
		if not heritage.allow(self, key, o[0], o[1]):
			continue
		redevelop(key, o[0], o[1])
		return


## A grown building cut off from power or water for LEVEL_DOWN_AFTER drops
## a level (Nathan, 2026-10-25: "the level goes up or down based on whether
## it has what it needs"): the owner closes off the top floor, a shop shrinks
## back. `short` is when it was cut off; the clock starts again after each
## step down, and stops once it has power and water again.
func _decline() -> void:
	if not require_utilities:
		return
	var keys := buildings.keys()
	keys.sort()
	var changed := false
	for key in keys:
		var b: Dictionary = buildings[key]
		# A protected old building is kept as it is (Heritage): its owner
		# can't rebuild it, so it can't lose a level it couldn't win back.
		if int(b.get("level", 0)) <= 0 or not lots.has(key) or heritage.protected(key):
			b.erase("short")
			continue
		if services.has_utilities(key):
			b.erase("short")
		elif not b.has("short"):
			b.short = tick_count
		elif tick_count - int(b.short) >= Balance.LEVEL_DOWN_AFTER:
			var nb := BuildingTypes.make(self, key, b, BuildingTypes.type_of(b), int(b.level) - 1)
			nb.changed = tick_count
			nb.short = tick_count
			nb.why = "Lost a level: no %s for two days." % ("power" if not services.served.get(key, {}).get("power", false) else "water")
			buildings[key] = nb
			changed = true
	if changed:
		buildings_changed.emit()


## Whether the town has traffic engineers to time its lights: a Traffic
## Management Center, or a university's transportation research center.
func _signal_engineers() -> bool:
	return services.traffic_center() != -1 or education.has_built("traffic_lab")


## Rebuilds a building as another type or stage (the owner's call). Residents
## stay up to the new size. Build's agency can call this too.
func redevelop(key: String, type: String, level: int) -> void:
	if not buildings.has(key):
		return
	var b := BuildingTypes.make(self, key, buildings[key], type, level)
	b.changed = tick_count
	if type != BuildingTypes.type_of(buildings[key]):
		# Torn down and rebuilt as something else: its age starts again,
		# and it's new.
		b.fabric = tick_count
		care.forget(key)
	buildings[key] = b
	buildings_changed.emit()


## People a home holds, or jobs a shop or factory offers.
static func capacity(zone: int, bseed: int) -> int:
	var r := absi(bseed)
	match zone:
		ZoneMap.Zone.RESIDENTIAL: return 2 + r % 3
		ZoneMap.Zone.COMMERCIAL: return 6 + r % 9
		_: return 18 + r % 19


# --- Saving (also the future network format) --------------------------------

## True for the piece of county highway that runs off to the region: it
## can't be bulldozed, or the town would lose its way out.
func is_link_segment(seg_id: int) -> bool:
	var s: Dictionary = network.segments.get(seg_id, {})
	return not s.is_empty() and (s.a in region_links or s.b in region_links)


## The county highway a new city starts on (no map edge): a two-lane road
## from a to b (metres, city-local) in pieces of about 400 m, free of charge.
## The ends listed in link_ends (0 for a, 1 for b) lead on to the region.
## Returns the node ids at a and b. A command, so every copy builds it.
func build_county_road(a: Vector2, b: Vector2, link_ends: Array) -> Array:
	apply_now({"type": "build_county_road", "a": [a.x, a.y], "b": [b.x, b.y], "links": link_ends})
	return [network.find_node_near(Vector3(a.x, 0, a.y), 1.0), network.find_node_near(Vector3(b.x, 0, b.y), 1.0)]


## How near a road's end must come to a county road to join it, metres.
const COUNTY_JOIN := 6.0
## How often (ticks) county stubs are taken on along their line.
const COUNTY_ENDS_EVERY := 1440
## A joined county road is laid in pieces this long, metres, and looked
## along every COUNTY_STEP metres for the town's roads.
const COUNTY_PIECE := 200.0
const COUNTY_STEP := 8.0
## A road's dead end this near a county road is taken on to it, metres.
const COUNTY_REACH := 15.0
## A joined county road goes on through a street's zoned frontage this far
## to meet the street: about a lot's depth, metres.
const COUNTY_THROUGH := 64.0
## A joined state highway is taken on this far each way, metres (a mile).
const HIGHWAY_JOIN := 1608.0
## No lot's middle stands nearer a state highway than this, metres: its
## right of way (Highways.HALF_CLEAR) and half a lot's depth.
const HIGHWAY_LOT_CLEAR := Highways.HALF_CLEAR + 12.0


## Joins the mile of county road at `p` (if one runs there) to the town: it
## becomes a gravel road of the town's own, free, right where it runs, from
## `p` out both ways as far as the mile goes, the water or a bluff allows,
## the town's land reaches, or it meets one of the town's roads (and joins
## it there). A mile can be joined from more than one place. True if any
## road was laid.
func _join_county(p: Vector3, way := 0, key := "") -> bool:
	if absf(p.y) > 1.0:
		return false  # a bridge or tunnel end
	var o := terrain_offset
	var mile := CountyGrid.mile_at(p.x + o.x, p.z + o.y, COUNTY_JOIN) if key == "" \
		else CountyGrid.mile_of(key, p.x + o.x, p.z + o.y)
	if mile.is_empty() or county_removed.has(mile.key) \
			or Vector2(p.x + o.x, p.z + o.y).distance_to(mile.on) > COUNTY_REACH:
		return false
	var on: Vector2 = mile.on - o
	var here := Vector2(p.x, p.z)
	var pieces := []
	for e in 2:
		if (way < 0 and e == 1) or (way > 0 and e == 0):
			continue  # only out the way asked (away from the roads just built)
		var stop: Vector2 = CountyGrid.run(mile.on, mile.a if e == 0 else mile.b) - o
		var length := on.distance_to(stop)
		if length < RoadNetwork.MIN_LENGTH:
			continue
		var dir := (stop - on) / length
		pieces.append_array(_pieces_along(func(d): return on + dir * d, length))
	if pieces.is_empty():
		return false
	var before := network.segments.keys()
	var money := economy.money
	network.begin_batch()
	if here.distance_to(on) > 0.5:
		var m := (here + on) * 0.5
		network.build_road(p, Vector3(m.x, 0, m.y), Vector3(on.x, 0, on.y), RoadStyle.Type.GRAVEL)
	# Never laid along a road already there (a street drawn in at a
	# shallow angle onto the line), only up to it.
	for c in pieces:
		_build_over(c, RoadStyle.Type.GRAVEL, false)
	network.end_batch()
	economy.money = money  # the county hands it over
	county_joined[mile.key] = true
	county_changed.emit()
	streets.name_road(self, network.segments.keys().filter(func(id): return not id in before),
		streets.grid_name(mile.key))
	streets.sync(self)
	return true


## A county road the town joined, bulldozed: that mile is the player's to
## have gone, so it isn't joined again or taken on along its line.
func _note_county_removed(seg: int) -> void:
	var c := network.curve_of(seg)
	var o := terrain_offset
	var mid := RoadNetwork.bezier(c[0], c[1], c[2], 0.5)
	for mile in CountyGrid.miles_at(mid.x + o.x, mid.z + o.y, 2.0):
		var ns: bool = mile.key.begins_with("ns")
		var line: float = mile.a.x if ns else mile.a.y
		if absf((c[0].x + o.x if ns else c[0].z + o.y) - line) < 2.0 \
				and absf((c[2].x + o.x if ns else c[2].z + o.y) - line) < 2.0 and not county_removed.has(mile.key):
			county_removed[mile.key] = true
			county_changed.emit()


## Joined county road that stopped short and left a dead end on its line
## (at a farm lane, say, before lanes no longer stopped it: Brawn
## 2026-10-24, roads ending in round pads where the paint carried on) is
## taken on along the line, as far as the town may build. True if any was.
func _extend_county_ends() -> bool:
	var o := terrain_offset
	var any := false
	for n in network.nodes.keys():
		if not network.nodes.has(n):
			continue
		var segs := network.segments_at(n)
		if segs.size() != 1 or int(network.segments[segs[0]].type) != RoadStyle.Type.GRAVEL:
			continue
		var p: Vector3 = network.nodes[n]
		if absf(p.y) > 1.0:
			continue
		var c := network.curve_of(segs[0])
		var other: Vector3 = c[2] if c[0].distance_to(p) < c[2].distance_to(p) else c[0]
		for mile in CountyGrid.miles_at(p.x + o.x, p.z + o.y, 1.0):
			if county_removed.has(mile.key):
				continue
			var ns: bool = mile.key.begins_with("ns")
			var line: float = mile.a.x if ns else mile.a.y
			# Only a stub running along the line, out the way it points.
			if absf((other.x + o.x if ns else other.z + o.y) - line) > 2.0:
				continue
			var at: float = p.z + o.y if ns else p.x + o.x
			var from: float = other.z + o.y if ns else other.x + o.x
			var lo: float = mile.a.y if ns else mile.a.x
			var forward := at > from
			if at > lo + CountyGrid.SECTION - 2.0 or at < lo + 2.0:
				continue  # at the crossing: that mile was joined to its end
			if _join_county(p, 1 if forward else -1, mile.key):
				any = true
				break
	return any


## The pieces of road to lay along a line out from a join, `at`(metres
## along) giving each point (town coordinates), up to `length` metres: out
## to the first of the town's roads it meets (and onto it), and no further,
## so a road already on the line keeps its place. It stops short of zoned
## lots and farmyards, which are the town's, of the edge of the town's land
## and, with `dry`, of the water.
func _pieces_along(at: Callable, length: float, dry := false) -> Array:
	var o := terrain_offset
	var pieces := []
	var d := 0.0
	var met := false
	var blocked := false
	while d < length - 1.0 and not met and not blocked:
		var next := minf(d + COUNTY_PIECE, length)
		var s := d + COUNTY_STEP
		while s <= next:
			var q: Vector2 = at.call(s)
			var here := Vector3(q.x, 0, q.y)
			if not RoadIndex.segment_near(network, here, COUNTY_STEP * 0.6).is_empty():
				next = s
				met = true
				break
			var zoned := zones.zone_at(here) != ZoneMap.Zone.NONE
			# A farm lane coming out on the line doesn't stop it; a yard does.
			if zoned or farms.yard_at(here) or (dry and Terrain.water(q.x + o.x, q.y + o.y) >= 0.1):
				# A street's zoned frontage doesn't keep the road from the
				# street itself: it runs through to meet it, as a county road
				# meets a town's street (the lots are platted around it).
				var street := _street_ahead(at, s, minf(length, s + COUNTY_THROUGH), dry) if zoned else -1.0
				if street > 0.0:
					next = street
					met = true
					break
				next = s - COUNTY_STEP
				blocked = true
				break
			s += COUNTY_STEP
		if met and next <= COUNTY_STEP:
			break  # a road already runs along the line here
		var c := _piece(at, d, next)
		if land_problem([c]) != "":
			# Only as far as the town may build (its land, in a region).
			while next - d > COUNTY_STEP and land_problem([c]) != "":
				next -= COUNTY_STEP
				c = _piece(at, d, next)
			if land_problem([c]) != "":
				break
			met = false
			blocked = true
		if c[0].distance_to(c[2]) < RoadNetwork.MIN_LENGTH:
			break
		if met:
			# Right onto the road it meets, so the two join there.
			var hit := RoadIndex.segment_near(network, c[2], COUNTY_STEP)
			if not hit.is_empty():
				c[2] = Vector3(hit.point.x, 0, hit.point.z)
				c[1] = (c[0] + c[2]) * 0.5
		pieces.append(c)
		d = next
	return pieces


## How far along `at` the first of the town's roads lies between `from`
## and `to` metres, over land a road may cross (zoned or not, but no farmyard
## or water), or -1.
func _street_ahead(at: Callable, from: float, to: float, dry: bool) -> float:
	var o := terrain_offset
	var s := from + COUNTY_STEP
	while s <= to:
		var q: Vector2 = at.call(s)
		var here := Vector3(q.x, 0, q.y)
		if not RoadIndex.segment_near(network, here, COUNTY_STEP * 0.6).is_empty():
			return s
		if farms.yard_at(here) or (dry and Terrain.water(q.x + o.x, q.y + o.y) >= 0.1):
			return -1.0
		s += COUNTY_STEP
	return -1.0


## A piece of road from `a` to `b` metres along `at`, bowed through the
## line's middle.
static func _piece(at: Callable, a: float, b: float) -> Array:
	var pa: Vector2 = at.call(a)
	var pb: Vector2 = at.call(b)
	var k: Vector2 = at.call((a + b) * 0.5) * 2.0 - (pa + pb) * 0.5
	return [Vector3(pa.x, 0, pa.y), Vector3(k.x, 0, k.y), Vector3(pb.x, 0, pb.y)]


## Joins the state highway at `p` (route, if given, else the nearest within
## COUNTY_REACH) to the town, the way a county road joins: a STATE_HWY road
## of its own, free, laid where the highway runs, from `p` out HIGHWAY_JOIN
## metres each way (or only `way`: -1 back toward the route's start, +1 on),
## stopping at the town's roads (joining them), the water, zoned lots and
## the edge of its land. True if any road was laid.
func _join_highway(p: Vector3, way := 0, route := -1) -> bool:
	if absf(p.y) > 1.0:
		return false  # a bridge or tunnel end
	var o := terrain_offset
	var hit := Highways.near(p.x + o.x, p.z + o.y, COUNTY_REACH, route)
	if hit.is_empty():
		return false
	var r: int = hit.route
	var from: float = hit.along
	var on: Vector2 = hit.on - o
	var here := Vector2(p.x, p.z)
	var pieces := []
	for e in [-1, 1]:
		if way != 0 and way != e:
			continue
		var at := func(d): return Highways.point(r, from + e * d) - o
		var length := absf(clampf(from + e * HIGHWAY_JOIN, 0.0, Highways.length(r)) - from)
		if length >= RoadNetwork.MIN_LENGTH:
			pieces.append_array(_pieces_along(at, length, true))
	if pieces.is_empty():
		return false
	var before := network.segments.keys()
	var money := economy.money
	network.begin_batch()
	if here.distance_to(on) > 0.5:
		var m := (here + on) * 0.5
		network.build_road(p, Vector3(m.x, 0, m.y), Vector3(on.x, 0, on.y), RoadStyle.Type.STATE_HWY)
	for c in pieces:
		network.build_road(c[0], c[1], c[2], RoadStyle.Type.STATE_HWY)
	network.end_batch()
	economy.money = money  # the state hands it over
	streets.name_road(self, network.segments.keys().filter(func(id): return not id in before),
		Highways.all()[r].name)
	streets.sync(self)
	return true


## County roads (miles not bulldozed) and state highways near a shape, as
## lines a grid plan meets: {"pts" (town coordinates), "type"}.
func painted_near(shape: Array) -> Array:
	var box := Rect2(Vector2(shape[0].x, shape[0].z), Vector2.ZERO)
	for p in shape:
		box = box.expand(Vector2(p.x, p.z))
	box = box.grow(200.0)
	var o := terrain_offset
	var sec := CountyGrid.SECTION
	var out := []
	var lo := ((box.position + o) / sec).floor()
	var hi := ((box.end + o) / sec).floor()
	for k in range(int(lo.x), int(hi.x) + 2):  # north-south lines
		for seg in range(int(lo.y), int(hi.y) + 1):
			if CountyGrid.has_mile(k, seg) and not county_removed.has("ns:%d:%d" % [k, seg]):
				out.append({"pts": PackedVector2Array([Vector2(k * sec, seg * sec) - o, Vector2(k * sec, (seg + 1) * sec) - o]),
					"type": RoadStyle.Type.COUNTY})
	for k in range(int(lo.y), int(hi.y) + 2):  # east-west lines
		for seg in range(int(lo.x), int(hi.x) + 1):
			if CountyGrid.has_mile(k + (1 << 20), seg) and not county_removed.has("ew:%d:%d" % [k, seg]):
				out.append({"pts": PackedVector2Array([Vector2(seg * sec, k * sec) - o, Vector2((seg + 1) * sec, k * sec) - o]),
					"type": RoadStyle.Type.COUNTY})
	var routes := Highways.all()
	for r in routes.size():
		var pts: PackedVector2Array = routes[r].pts
		var run := PackedVector2Array()
		for i in pts.size():
			var q: Vector2 = pts[i] - o
			var inside := box.has_point(q) or (i > 0 and box.intersects(Rect2(pts[i - 1] - o, Vector2.ZERO).expand(q)))
			if inside:
				if run.is_empty() and i > 0:
					run.append(pts[i - 1] - o)
				run.append(q)
			elif not run.is_empty():
				run.append(q)
				out.append({"pts": run, "type": RoadStyle.Type.STATE_HWY, "route": r})
				run = PackedVector2Array()
		if run.size() >= 2:
			out.append({"pts": run, "type": RoadStyle.Type.STATE_HWY, "route": r})
	return out


## Where roads just built (curves) cross or end on a county road out in the
## country, the town takes over that mile, out from the outermost places
## they touch it, so the county road runs on from them where it was.
func _join_crossings(curves: Array) -> void:
	var o := terrain_offset
	var touch := {}  # mile key -> [lowest along, its point, highest, its point]
	for c in curves:
		var pts := RoadNetwork.sample_curve(c[0], c[1], c[2], maxi(2, ceili(c[0].distance_to(c[2]) / 4.0)))
		for i in pts.size():
			var a: Vector3 = pts[i]
			if absf(a.y) > 1.0:
				continue
			for mile in CountyGrid.miles_at(a.x + o.x, a.z + o.y, COUNTY_STEP):
				if county_removed.has(mile.key):
					continue
				var ns: bool = mile.key.begins_with("ns")
				var line: float = mile.a.x - o.x if ns else mile.a.y - o.y
				var off := (a.x if ns else a.z) - line
				var q := a
				if absf(off) > 0.05:
					# Only where the road reaches the line, at the very spot.
					if i + 1 >= pts.size():
						continue
					var b: Vector3 = pts[i + 1]
					var off_b := (b.x if ns else b.z) - line
					if signf(off) == signf(off_b) and absf(off_b) > 0.05:
						continue
					q = a.lerp(b, off / (off - off_b))
				var along := q.z if ns else q.x
				var lo: float = (mile.a.y if ns else mile.a.x) - (o.y if ns else o.x)
				if along < lo - 0.5 or along > lo + CountyGrid.SECTION + 0.5:
					continue  # on the line, but the next mile's stretch
				_touch(touch, mile.key, along, q)
		# Where it crosses a state highway.
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			if absf(a.y) > 1.0 or absf(b.y) > 1.0:
				continue
			var hw := Highways.crossing(Vector2(a.x + o.x, a.z + o.y), Vector2(b.x + o.x, b.z + o.y))
			if not hw.is_empty():
				var on: Vector2 = hw.on - o
				_touch(touch, "hw:%d" % hw.route, hw.along, Vector3(on.x, 0, on.y))
		# A road ending just short of a county road or highway is taken on to it.
		for end in [c[0], c[2]]:
			if absf(end.y) > 1.0 or network.segments_at(network.find_node_near(end, 0.5)).size() != 1:
				continue
			var hw := Highways.near(end.x + o.x, end.z + o.y, COUNTY_REACH)
			if not hw.is_empty() and not touch.has("hw:%d" % hw.route):
				var on: Vector2 = hw.on - o
				_touch(touch, "hw:%d" % hw.route, hw.along, end if end.distance_to(Vector3(on.x, 0, on.y)) > 0.5 \
					else Vector3(on.x, 0, on.y))
				continue
			var near := CountyGrid.mile_at(end.x + o.x, end.z + o.y, COUNTY_REACH)
			if near.is_empty() or county_removed.has(near.key) or touch.has(near.key):
				continue
			if _join_county(end, 0, near.key):
				continue
	for key in touch:
		var t: Array = touch[key]
		if key.begins_with("hw:"):
			var r := int(key.substr(3))
			if t[2] - t[0] < 20.0:
				_join_highway(t[1], 0, r)
			else:
				_join_highway(t[1], -1, r)
				_join_highway(t[3], 1, r)
			continue
		if t[2] - t[0] < 20.0:
			_join_county(t[1], 0, key)
		else:
			_join_county(t[1], -1, key)
			_join_county(t[3], 1, key)


static func _touch(touch: Dictionary, key: String, along: float, q: Vector3) -> void:
	if not touch.has(key):
		touch[key] = [along, q, along, q]
	var t: Array = touch[key]
	if along < t[0]:
		t[0] = along
		t[1] = q
	if along > t[2]:
		t[2] = along
		t[3] = q


func _county_road(a: Vector2, b: Vector2, link_ends: Array) -> Array:
	var money := economy.money
	var n := maxi(1, ceili(a.distance_to(b) / 400.0))
	var pts := []
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		pts.append(Vector3(p.x, 0.0, p.y))
	var before := network.segments.keys()
	streets.hold = true
	network.begin_batch()
	for i in n:
		network.build_road(pts[i], (pts[i] + pts[i + 1]) * 0.5, pts[i + 1], RoadStyle.Type.STREET)
	network.end_batch()
	streets.hold = false
	# A road out of town is named for the town it leads to.
	var made := network.segments.keys().filter(func(id): return not id in before)
	streets.name_road(self, made, streets.town_road(hash([city_seed, a, b])))
	street_age.note_old(self, made)
	streets.sync(self)
	economy.money = money
	var ends := [network.find_node_near(pts[0], 1.0), network.find_node_near(pts[-1], 1.0)]
	for i in link_ends:
		if ends[int(i)] != -1 and not ends[int(i)] in region_links:
			region_links.append(ends[int(i)])
	return ends


## The roads out to the region, as straight county highways to rebuild:
## [[a, b, link_ends], ...]. Each runs from one region link along the road,
## straight on through any junctions, to the other link or the road's end.
func _link_roads() -> Array:
	var out := []
	var done := {}
	var links := region_links.duplicate()
	links.sort()
	for start in links:
		if done.has(start) or not network.nodes.has(start):
			continue
		done[start] = true
		var at: int = start
		var came := -1
		var heading := Vector3.ZERO
		var steps := 0
		while steps < 200:
			steps += 1
			var next := -1
			var best := -1.0
			for seg in network.segments_at(at):
				if seg == came:
					continue
				var sd: Dictionary = network.segments[seg]
				var other: int = sd.b if sd.a == at else sd.a
				var dir: Vector3 = network.nodes[other] - network.nodes[at]
				dir.y = 0.0
				dir = dir.normalized()
				# The first step takes the only road; then straight on (within 25°).
				var straight := 1.0 if heading == Vector3.ZERO else dir.dot(heading)
				if straight > best and (heading == Vector3.ZERO or straight > 0.9):
					best = straight
					next = seg
			if next == -1:
				break
			var nd: Dictionary = network.segments[next]
			var to: int = nd.b if nd.a == at else nd.a
			heading = network.nodes[to] - network.nodes[at]
			heading.y = 0.0
			heading = heading.normalized()
			came = next
			at = to
			if at in region_links:
				break
		var a: Vector3 = network.nodes[start]
		var b: Vector3 = network.nodes[at]
		var ends := [0]
		if at in region_links and at != start:
			done[at] = true
			ends.append(1)
		if a.distance_to(b) >= RoadNetwork.MIN_LENGTH:
			out.append([Vector2(a.x, a.z), Vector2(b.x, b.z), ends])
	return out


## A fresh start gets a crossroads on its county highway, nearest the
## town's middle: a street across it, 300 m each way, to grow from.
func _start_crossroads() -> void:
	var near := RoadIndex.segment_near(network, Vector3.ZERO, 5000.0)
	if near.is_empty():
		return
	var at: Vector3 = near.point
	var hub := network.find_node_near(at, 60.0)
	if hub != -1 and network.segments_at(hub).size() >= 3:
		return
	var sd: Dictionary = network.segments[int(near.seg)]
	var along: Vector3 = network.nodes[sd.b] - network.nodes[sd.a]
	along.y = 0.0
	var across := Vector3(-along.z, 0.0, along.x).normalized() * 300.0
	var a := at - across
	var b := at + across
	if not land_ok(a) or not land_ok(b) or not land_ok(at):
		return
	var money := economy.money
	network.build_road(a, at, b, RoadStyle.Type.STREET)
	economy.money = money


func _parcels_to_save() -> Dictionary:
	var out := {}
	var keys := buildings.keys()
	keys.sort()
	var cache := {}
	for key in keys:
		if lots.has(key):
			# A lot that hasn't changed (the same contents) keeps its saved
			# form, so saving a big town stays quick.
			var lot: Dictionary = lots[key]
			var h := lot.hash()
			var was: Array = _parcel_cache.get(key, [])
			var saved: Dictionary = was[1] if not was.is_empty() and was[0] == h else LotPlanner.lot_to_save(lot)
			cache[key] = [h, saved]
			out[key] = saved
	_parcel_cache = cache
	return out


## The empty lots and the planner's state, so a loaded copy has exactly the
## town's lots without planning it all again (see LotPlanner.cuts_to_save).
func _plan_to_save() -> Dictionary:
	var out := planner.cuts_to_save(zones)
	# The empty lots are the saved cuts' lots, less any blocked ones (just
	# their keys are saved), unless the town hasn't caught up with them.
	var cut := {}
	for lot in planner.cut_lots(network, buildings):
		cut[lot.key] = lot
	var keys := lots.keys()
	keys.sort()
	var same := true
	for key in keys:
		if not buildings.has(key) and cut.get(key, {}) != lots[key]:
			same = false
			break
	if same:
		var skip := []
		for key in cut:
			if not lots.has(key):
				skip.append(key)
		skip.sort()
		out.skip = skip
	else:
		var empty := []
		for key in keys:
			if not buildings.has(key):
				empty.append(LotPlanner.lot_to_save(lots[key]))
		out.empty = empty
	out.flags = [_lots_dirty, _lots_light, _roads_moved]
	if not _lots_near.is_empty():
		out.near = _lots_near.map(func(b: Rect2): return [b.position.x, b.position.y, b.size.x, b.size.y])
	out.replan_at = _replan_at
	out.hold_until = _hold_until
	return out


var _parcel_cache := {}  # lot key -> [hash of the lot, its saved form] (see _parcels_to_save)
var _zones_saved := [-1, {}]  # [ZoneMap.revision, its saved form]


## The zoning as saved, made again only when it changed (a big town's
## zoning takes a fifth of a second to write out).
func _zones_to_save() -> Dictionary:
	if int(_zones_saved[0]) != zones.revision:
		_zones_saved = [zones.revision, zones.to_dict()]
	return _zones_saved[1]


## What a postcard leaves out (see to_dict).
const POSTCARD_SKIP := ["plan", "zones", "families", "timelapse", "history", "traffic", "buses", "taxis", "people"]


## The town as saved data. A postcard is what a neighbor's computer needs
## to draw it and trade with it: everything but who lives where, the cars
## and buses, and the planner's working state, which are most of a grown
## town's size and saving time (see from_dict).
func to_dict(postcard := false) -> Dictionary:
	vegetation.update(self)  # land cleared since the last tick counts
	var d := {}
	for step in save_steps(postcard):
		d[step[0]] = step[1].call()
	if postcard:
		d.postcard = true
	return d


## Holds the town still while a TownSnapshot saves it: no ticks (the game
## checks `held`), and player commands wait their turn.
var held := false
var _held_cmds := []


func hold() -> void:
	held = true


func release() -> void:
	held = false
	var cmds := _held_cmds
	_held_cmds = []
	for cmd in cmds:
		apply(cmd)


## to_dict as steps, [key, Callable], so a big town can be saved a few at
## a time over several frames while it holds still (see hold and
## TownSnapshot). The heavy ones (people, plans, cars) come last and only
## in a full copy.
func save_steps(postcard := false) -> Array:
	var steps := [
		["version", func(): return 2],
		["links", func(): return region_links],
		["county", func(): return county_joined.keys()],
		["county_removed", func(): return county_removed.keys()],
		["trade", func(): return trade.to_dict()],
		["tick", func(): return tick_count],
		["seed", func(): return city_seed],
		["roads", func(): return network.to_dict()],
		["buildings", func(): return buildings],
		["parcels", func(): return _parcels_to_save()],
		["economy", func(): return economy.to_dict()],
		["home_parts", func(): return _home_parts],
		["services", func(): return services.to_dict()],
		["farms", func(): return farms.to_dict()],
		["industry", func(): return industry.to_dict()],
		["power", func(): return power.to_dict()],
		["education", func(): return education.to_dict()],
		["telecom", func(): return telecom.to_dict()],
		["banks", func(): return banks.to_dict()],
		["logistics", func(): return logistics.to_dict()],
		["construction", func(): return construction.to_dict()],
		["warehouses", func(): return warehouses.to_dict()],
		["big_factories", func(): return big.to_dict()],
		["reserves", func(): return reserves.to_dict()],
		["land_plan", func(): return land_plan.to_dict()],
		["rail", func(): return rail.to_dict()],
		["permits", func(): return permits.to_dict()],
		["hubs", func(): return hubs.to_dict()],
		["parks", func(): return parks.to_dict()],
		["neighborhoods", func(): return neighborhoods.to_dict()],
		["mail", func(): return mail.to_dict()],
		["interlocal", func(): return interlocal.to_dict()],
		["regional", func(): return regional.to_dict()],
		["market", func(): return market.to_dict()],
		["streets", func(): return streets.to_dict()],
		["policies", func(): return policies.to_dict()],
		["culture", func(): return culture.to_dict()],
		["pollution", func(): return pollution.to_dict()],
		["healthcare", func(): return healthcare.to_dict()],
		["nicknames", func(): return nicknames.to_dict()],
		["heritage", func(): return heritage.to_dict()],
		["markers", func(): return markers.to_dict()],
		["leaders", func(): return leaders.to_dict()],
		["charter", func(): return charter.to_dict()],
		["care", func(): return care.to_dict()],
		["redevelopment", func(): return redevelopment.to_dict()],
		["subdivisions", func(): return subdivisions.to_dict()],
		["street_age", func(): return street_age.to_dict()],
		["engineer", func(): return engineer.to_dict()],
		["junctions", func(): return traffic.rules_to_dict()],
		["greens", func(): return traffic.greens_to_dict()],
		["offsets", func(): return traffic.offsets_to_dict()],
		["actuated", func(): return traffic.actuated_to_dict()],
		["signal_engineers", func(): return traffic.engineers_to_dict()],
		["vegetation", func(): return vegetation.to_dict()],
	]
	if not postcard:
		steps.append_array([
			["zones", func(): return _zones_to_save()],
			["plan", func(): return _plan_to_save()],
			["families", func(): return families.to_dict()],
			["timelapse", func(): return timelapse.to_dict()],
			["history", func(): return history.to_dict()],
			["traffic", func(): return traffic.to_dict()],
			["buses", func(): return buses.to_dict()],
			["taxis", func(): return taxis.to_dict()],
			["builders", func(): return builders.to_dict()],
			["people", func(): return people.to_dict()],
		])
	return steps


func from_dict(d: Dictionary) -> void:
	_ground_was = {}  # the next full lot check looks at every lot
	_lots_touched.clear()
	vegetation.from_dict(d.get("vegetation", {}))
	# Streets get their saved names below: don't name every road afresh as
	# the network comes in (a quarter of a second in a big town).
	var held := streets.hold
	streets.hold = true
	planner = LotPlanner.new()
	planner.wealth = wealth_at
	if d.has("roads"):
		network.from_dict(d.roads)
		zones.from_dict(d.get("zones", {}))
		region_links.clear()
		if d.has("links"):
			for n in d.links:
				region_links.append(int(n))
		else:
			_guess_link()
		county_joined.clear()
		for k in d.get("county", []):
			county_joined[str(k)] = true
		county_removed.clear()
		for k in d.get("county_removed", []):
			county_removed[str(k)] = true
		county_changed.emit()
		trade.from_dict(d.get("trade", {}))
	else:
		# Version 1 saves were just roads, with houses on every lot.
		network.from_dict(d)
		planner.update(network)
		for id in network.segments:
			for side in [-1, 1]:
				_paint_frontage(id, side, ZoneMap.Zone.RESIDENTIAL)
	_upgrade_old_rings()
	economy.from_dict(d.get("economy", {}))
	_home_parts = []
	for part in d.get("home_parts", []):
		_home_parts.append({"n": int(part.n), "boil": int(part.boil), "care": float(part.care),
			"cover": float(part.cover), "happy": float(part.happy)})
	families.from_dict(d.get("families", {}))
	streets.hold = held
	streets.from_dict(self, d.get("streets", {}))
	services.from_dict(d.get("services", {}))
	farms.from_dict(d.get("farms", {}))
	industry.from_dict(d.get("industry", {}))
	power.from_dict(d.get("power", {}))
	education.from_dict(d.get("education", {}))
	telecom.from_dict(d.get("telecom", {}))
	banks.from_dict(d.get("banks", {}))
	logistics.from_dict(d.get("logistics", {}))
	construction.from_dict(d.get("construction", {}))
	warehouses.from_dict(d.get("warehouses", {}))
	big.from_dict(d.get("big_factories", {}))
	reserves.from_list(d.get("reserves", []))
	land_plan.from_list(d.get("land_plan", []))
	plan_changed.emit()
	rail.from_dict(d.get("rail", {}))
	permits.from_dict(d.get("permits", {}))
	hubs.from_dict(d.get("hubs", {}))
	parks.from_dict(d.get("parks", {}))
	neighborhoods.from_dict(d.get("neighborhoods", {}))
	mail.from_dict(d.get("mail", {}))
	interlocal.from_dict(d.get("interlocal", {}))
	regional.from_dict(d.get("regional", {}))
	market.from_dict(d.get("market", {}))
	services.contracts = interlocal.coverage()
	policies.from_dict(d.get("policies", {}))
	culture.from_dict(d.get("culture", {}))
	pollution.from_dict(d.get("pollution", {}))
	healthcare.from_dict(d.get("healthcare", {}))
	nicknames.from_dict(d.get("nicknames", {}))
	heritage.from_dict(d.get("heritage", {}))
	markers.from_dict(d.get("markers", {}))
	leaders.from_dict(d.get("leaders", {}))
	charter.from_dict(d.get("charter", {}))
	care.from_dict(d.get("care", {}))
	redevelopment.from_dict(d.get("redevelopment", {}))
	subdivisions.from_dict(d.get("subdivisions", {}))
	street_age.from_dict(d.get("street_age", {}))
	engineer.from_dict(d.get("engineer", {}))
	for legacy in farms.legacy_outlines:
		reserves.paint(legacy[0], legacy[1])
	for id in farms.farms:
		var f: Dictionary = farms.farms[id]
		if f.drive.is_empty():
			f.drive = farm_drive(f.pos, f.dir)
	traffic.rules_from_dict(d.get("junctions", {}))
	traffic.greens_from_dict(d.get("greens", {}))
	traffic.offsets_from_dict(d.get("offsets", {}))
	traffic.actuated_from_dict(d.get("actuated", {}))
	traffic.engineers_from_dict(d.get("signal_engineers", {}))
	traffic.from_dict(d.get("traffic", {}))
	people.from_dict(d.get("people", {}))
	tick_count = int(d.get("tick", 0))
	city_seed = int(d.get("seed", 1))
	var postcard := bool(d.get("postcard", false))
	# Parcels: the lots buildings stand on. (A neighbor's postcard has no
	# planner state: it is drawn, never planned, here.)
	if not postcard:
		planner.update(network)
	lots.clear()
	var parcels: Dictionary = d.get("parcels", {})
	for key in parcels:
		lots[key] = LotPlanner.lot_from_save(parcels[key])
	if not d.has("parcels"):
		# Saves from before natural lots: their buildings keep the old lots.
		for lot in LotPlanner.legacy_plan(network):
			lot.sig = planner.sig_of(lot.seg)
			lots[lot.key] = lot
	buildings.clear()
	for key in d.get("buildings", {}):
		var b: Dictionary = d.buildings[key]
		var z := int(b.zone)
		var cap := int(b.get("cap", capacity(z, int(b.seed))))
		# Older saves had no residents yet: assume the homes were full. Their
		# buildings are the plain type for the zone, first stage.
		buildings[key] = {"zone": z, "seed": int(b.seed), "built": int(b.built), "cap": cap,
			"occ": int(b.get("occ", cap if z == ZoneMap.Zone.RESIDENTIAL else 0)),
			"type": BuildingTypes.type_of(b), "level": int(b.get("level", 0)),
			"units": int(b.get("units", 1)), "flats": int(b.get("flats", 0)), "focc": int(b.get("focc", 0)),
			"changed": int(b.get("changed", b.built)), "why": str(b.get("why", ""))}
		if b.has("fabric"):
			buildings[key].fabric = int(b.fabric)
		if b.has("short"):
			buildings[key].short = int(b.short)
		if z == ZoneMap.Zone.INDUSTRIAL and b.has("chain"):
			buildings[key].chain = str(b.chain)
	if postcard:
		# Drawn, not run: no service coverage to work out.
		_usable_cache.clear()
		lots_delta = lots.keys()
		lots_delta_full = true
		lots_changed.emit()
	elif d.has("plan") and d.has("parcels"):
		# The town's own lots and planning state, as saved: no need to plan
		# the whole town again, and a copy re-plans just when the town does.
		planner.restore(network, zones, d.plan)
		if d.plan.has("skip"):
			var skip := {}
			for key in d.plan.skip:
				skip[key] = true
			for lot in planner.cut_lots(network, buildings):
				if not skip.has(lot.key):
					lots[lot.key] = lot
		for e in d.plan.get("empty", []):
			var lot := LotPlanner.lot_from_save(e)
			lots[lot.key] = lot
		var flags: Array = d.plan.get("flags", [false, false, false])
		# Fields trimmed by roads aren't saved: work them out again (unless
		# a new road is still waiting to make way, as the town's is).
		if not bool(flags[2]):
			_road_wins()
		_lots_dirty = bool(flags[0])
		_lots_light = bool(flags[1])
		_lots_near = d.plan.get("near", []).map(func(b): return Rect2(float(b[0]), float(b[1]), float(b[2]), float(b[3])))
		_roads_moved = bool(flags[2])
		_replan_at = int(d.plan.get("replan_at", 0))
		_hold_until = int(d.plan.get("hold_until", 0))
		_usable_cache.clear()
		lots_delta = lots.keys()
		lots_delta_full = true
		_update_services()
		lots_changed.emit()
	else:
		_road_wins()
		_lots_dirty = true
		_refresh()
	# Factories from before industry chains take up the local one.
	for key in buildings:
		if buildings[key].zone == ZoneMap.Zone.INDUSTRIAL and not buildings[key].has("chain"):
			buildings[key].chain = factory_chain(lots[key].pos) if lots.has(key) else "general"
	pollution.after_load(self)
	heritage.ensure(self)
	timelapse.from_dict(self, d.get("timelapse", {}))
	history.from_dict(d.get("history", {}))
	if postcard:
		# Just its size: a neighbor's jobs and services are worked out on
		# its own computer.
		var pop := 0
		for key in buildings:
			pop += int(buildings[key].occ) if int(buildings[key].zone) == ZoneMap.Zone.RESIDENTIAL \
				else int(buildings[key].focc)
		stats.population = pop
	else:
		update_stats(true, -2)
	buses = BusNet.new()
	buses.from_dict(self, d.get("buses", {}))
	taxis = TaxiCo.new()
	taxis.from_dict(self, d.get("taxis", {}))
	builders = Builders.new()
	builders.from_dict(self, d.get("builders", {}))
	# Levers keep the exact amounts they were saved with (old saves had their
	# own buttons); each slider shows the nearest step.
	_lever_steps.clear()
	_adopt_levers()
	# A word to a leader saved before its hub was on the Economy page.
	for key in permits.guided:
		var area := hub_area(key)
		if area != "":
			var now := policies.step("growth", area, key)
			var want := Policies.growth_for(str(permits.guided[key].stance), now)
			if want != now:
				policies.set_step(key, "growth", want)
	buildings_changed.emit()


## Saves from before real roundabouts drew rings as two-way roads of the
## chosen type. Turn those into one-way counter-clockwise rings.
func _upgrade_old_rings() -> void:
	var groups := {}  # rounded centre -> [seg ids]
	for id in network.segments:
		var s: Dictionary = network.segments[id]
		if RoadStyle.is_ring(s.type) or RoadStyle.TYPES[s.type].oneway:
			continue
		var c := network.curve_of(id)
		var circle := RoadShapes.arc_circle(c)
		# 14-45 m: the only ring radii the old roundabout tool could build.
		if circle.is_empty() or circle[1] < 13.0 or circle[1] > 46.0:
			continue
		var key := Vector2i(roundi(circle[0].x / 2.0), roundi(circle[0].z / 2.0))
		if not groups.has(key):
			groups[key] = []
		groups[key].append([id, circle[0]])
	for key in groups:
		if groups[key].size() < 6:
			continue
		for entry in groups[key]:
			var id: int = entry[0]
			var s: Dictionary = network.segments[id]
			var c := network.curve_of(id)
			# Counter-clockwise seen from above: the centre is on the driver's left.
			var fwd: Vector3 = c[2] - c[0]
			var to_centre: Vector3 = entry[1] - c[0]
			if fwd.cross(to_centre).y < 0.0:
				var a: int = s.a
				s.a = s.b
				s.b = a
			s.type = RoadStyle.ring_type(s.type)
			s.oneway = true


## The road type a command asks for (Street if it doesn't say).
static func _road(cmd: Dictionary) -> int:
	return clampi(int(cmd.get("road", 0)), 0, RoadStyle.TYPES.size() - 1)


## A point from a command: [x, z] or [x, z, height].
static func _v(a) -> Vector3:
	if a is Vector3:
		return a
	return Vector3(float(a[0]), float(a[2]) if a.size() > 2 else 0.0, float(a[1]))
