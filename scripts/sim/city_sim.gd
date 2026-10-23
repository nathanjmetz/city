class_name CitySim
extends RefCounted
## The whole city as plain data, stepped in fixed ticks.
##
## Every player action is a command Dictionary passed to apply(), and the
## simulation only changes inside apply() and tick(). Given the same commands
## in the same order, every copy ends up in the same state, so a headless
## server can run this exact class later and send commands to players.

signal buildings_changed
signal lots_changed
## Buildings removed because a road now runs through their lot (for refunds).
signal parcels_lost(keys: Array)
signal zones_changed
## Population, jobs or demand changed (at most every MOVE_EVERY ticks).
signal stats_changed
## Farmland or a farm's fields changed.
signal farms_changed
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
var zones := ZoneMap.new()
var traffic := TrafficSim.new(network)
var economy := Economy.new()
var services := Services.new()
var farms := Farms.new()
## Oil, mining and forestry companies (Brawn's model: a main building whose
## pads spread to where the resource is).
var industry := Industry.new()
## Warehouses that buffer loads between them (hubs that grow in place).
var warehouses := Warehouses.new()
## Power companies (Brawn's hub-with-a-leader model): a yard whose leader
## picks the plant and grows it. The regional grid stays the default.
var power := Power.new()
## The trucks that carry every load (grain, crude, ore, logs, goods).
var logistics := Logistics.new()
## Land saved for farming or an industry: no roads or zoning on it.
var reserves := Reserves.new()
## Bus depots and school buses, which run themselves (scripts/transit/).
var buses := BusNet.new()
## Cab companies, which run themselves too.
var taxis := TaxiCo.new()
## Where this city sits in the shared region (its own coordinates start at
## 0): the land under it is read there. 0 in solo play.
var terrain_offset := Vector2.ZERO:
	set(v):
		terrain_offset = v
		services.terrain_offset = v
		power.offset = v
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
## Who owns each business, its name and its family's brand (Families).
var families := Families.new()
var streets := Streets.new()
## The town's broad Funding and Growth sliders for every area and hub (no
## tax fiddling: Brawn). Set on the Economy page or a hub's panel.
var policies := Policies.new()
## Buildings going up, stage by stage, with their crews and deliveries.
var construction := Construction.new()
## Smoke, noise and dirty ground, each traced to the source that makes it.
var pollution := Pollution.new()
## Hospitals run by their administrators, ambulances, nursing homes, daycare.
var healthcare := Healthcare.new()
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
var stats := {"population": 0, "workers": 0, "jobs": 0, "employed": 0, "homes_free": 0}
## How much each zone wants to grow, 0 to 1, like the CS demand bars.
var demand := {ZoneMap.Zone.RESIDENTIAL: 0.6, ZoneMap.Zone.COMMERCIAL: 0.0, ZoneMap.Zone.INDUSTRIAL: 0.1}

## In a shared region, your commands go to the server instead and come back
## in a tick, so every player applies them at the same moment.
var send_command := Callable()

## Road ends that lead on to the rest of the region (there's no map edge):
## the county highway's far ends. Trade, imports and through traffic come
## and go here, and nowhere else. Node ids.
var region_links: Array = []
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
## Only zoning or roads changed: built parcels need checking only where a
## road moved (the rest can't have changed), which keeps edits in a big
## town quick.
var _lots_light := false
## Roads changed since the world last made way for them (see RoadWins).
var _roads_moved := false
var _usable_cache := {}  # field cell -> bool, cleared when roads or lots change
var _zone_check := []  # what _refresh last checked buildings against
var _zone_check_lots := {}


func _init() -> void:
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
	permits.locators["bank"] = func(_sim, id: int) -> Vector2:
		var b: Dictionary = banks.banks.get(id, {"pos": Vector3.ZERO})
		return Vector2(b.pos.x, b.pos.z)
	farms.reserves = reserves
	industry.reserves = reserves
	# New businesses get their names before any view draws them, so signs go
	# up with the building (connected ahead of the views).
	for sig in [buildings_changed, farms_changed, industry_changed]:
		sig.connect(func(): families.sync(self))
	permits.costers[Families.HUB] = func(_sim, req: Dictionary, _route, _hits) -> int:
		return int(req.base)
	permits.locators[Families.HUB] = func(_sim, id: int) -> Vector2:
		return families.locate(self, id)
	_wire_policies()
	# Streets are named before any view draws their signs.
	network.changed.connect(func(): streets.sync(self))
	_hook_pollution()
	network.changed.connect(func():
		_lots_light = true
		_roads_moved = true
		rail.roads_changed())
	vegetation.watch(self)


## Applies one player command. Returns true if anything changed (online:
## true once it's sent).
func apply(cmd: Dictionary) -> bool:
	if send_command.is_valid():
		send_command.call(cmd)
		return true
	var ok := apply_now(cmd)
	if not ok:
		command_refused.emit(cmd)
	return ok


## Applies a command right away, even online (the region does this).
func apply_now(cmd: Dictionary) -> bool:
	var ok := false
	match cmd.get("type", ""):
		"build_road":
			var c := [_v(cmd.start), _v(cmd.ctrl), _v(cmd.end)]
			# The server checks real road rules too, not just the player's screen.
			if road_problem(c, _road(cmd)) == "":
				ok = network.build_road(c[0], c[1], c[2], _road(cmd))
				if ok:
					economy.money -= Economy.road_cost(c, _road(cmd))
		"build_grid", "build_grid_shape":
			# Old three-click grids are a rectangle; new ones any shape.
			var shape: Array = GridFill.rect(_v(cmd.a), _v(cmd.b), _v(cmd.c)) if cmd.type == "build_grid" \
				else cmd.points.map(_v)
			var lines := GridFill.plan(network, shape, float(cmd.block), _road(cmd), int(cmd.get("side", 0)),
				clampf(float(cmd.get("across", RoadShapes.GRID_ACROSS)), GridFill.ACROSS_MIN, GridFill.BLOCK_MAX))
			if shape.size() == 2:
				lines = [[shape[0], shape[0].lerp(shape[1], 0.5), shape[1]]]
			if lines.is_empty() or not _can_afford(lines, _road(cmd)):
				return false
			network.begin_batch()
			for l in lines:
				ok = network.build_road(l[0], l[1], l[2], _road(cmd)) or ok
			network.end_batch()
			if ok:
				economy.money -= shapes_cost(lines, _road(cmd))
		"build_roundabout":
			var ring := RoadStyle.ring_type(_road(cmd))
			var radius := RoadShapes.roundabout_radius(float(cmd.radius), _road(cmd))
			var arcs := RoadShapes.roundabout(_v(cmd.center), radius)
			if not _can_afford(arcs, ring):
				return false
			ok = _build_roundabout(_v(cmd.center), radius, ring)
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
		"place_service":
			var kind := int(cmd.kind)
			if not Services.KINDS.has(kind):
				return false
			var pos := _v(cmd.pos)
			var dir := _v(cmd.dir).normalized()
			var cost: int = Services.KINDS[kind].cost
			if cost > economy.money or services.site_problem(network, kind, pos, dir) != "" \
					or _on_warehouse(Services.corners(kind, pos, dir)) \
					or parks.overlaps(Services.corners(kind, pos, dir).map(func(q): return Vector2(q.x, q.z))) \
					or education.covers(pos) or banks.covers(pos) or telecom.covers(pos):
				return false
			var sid := services.add(kind, pos, dir)
			construction.start("svc:%d" % sid, "civic", tick_count, pos, dir, Services.SETBACK
				+ RoadStyle.CURB_WIDTH + RoadStyle.PARKWAY_WIDTH + RoadStyle.SIDEWALK_WIDTH)
			economy.money -= cost
			if kind == Services.Kind.BUS_DEPOT:
				buses.on_placed(self, sid)
			if kind == Services.Kind.TAXI_COMPANY:
				taxis.on_placed(self, sid)
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
			industry.add_site(kind, pos, dir, industry_drive(pos, dir))
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
			if not Parks.KINDS.has(kind) or dir.length() < 0.5 or Parks.cost_of(kind) > economy.money \
					or parks.site_problem(self, kind, pos, dir) != "":
				return false
			var pid := parks.add(self, kind, pos, dir)
			economy.money -= Parks.cost_of(kind)
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
			_lots_dirty = true
		"place_hub", "upgrade_hub", "remove_hub":
			ok = _hub_command(cmd)
		"move":
			# Move It: slide, turn or raise what the player placed (MoveIt).
			ok = MoveIt.apply(self, cmd)
		"fund_cleanup", "noise_wall":
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
			for side in sides:
				var parts := [[int(cmd.seg), side]] if bool(cmd.get("single", false)) \
					else frontage_chain(int(cmd.seg), side)
				for part in parts:
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
		"policy":
			# A Funding or Growth slider for the town, an area or one hub.
			ok = _set_policy(str(cmd.get("scope", "")), str(cmd.get("slider", "")), int(cmd.get("step", -1)))
		"policy_reset":
			# Everything under the town or an area follows it again.
			ok = policies.reset_below(str(cmd.get("scope", "")), hub_area)
			if ok:
				_sync_stances()
				_sync_levers()
		"set_junction":
			# Traffic lights, stop signs or none at a junction (-1 = automatic).
			ok = traffic.set_rule(int(cmd.node), int(cmd.rule))
		"place_post_office", "remove_post_office", "post_office_funding":
			ok = mail.command(self, cmd)
			if ok and cmd.type != "post_office_funding":
				_lots_dirty = true
			elif ok:
				_adopt_levers("post_office:%d" % int(cmd.id))
		"clear":
			region_links.clear()
			trade = Trade.new()
			traffic.overrides.clear()
			traffic.from_dict({})
			network.clear()
			zones.cells.clear()
			planner = LotPlanner.new()
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
			reserves = Reserves.new()
			buses = BusNet.new()
			taxis = TaxiCo.new()
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
			policies.from_dict({})
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
			ok = true
	if ok:
		if cmd.type in ["place_campus", "place_park", "place_bank", "place_hub", "place_service", "place_farmhouse",
				"place_industry", "place_post_office", "place_warehouse", "place_power", "place_telecom", "clear"]:
			# A new hub takes its area's sliders (and its leader the stance).
			_sync_levers()
			_sync_stances()
		if _roads_moved:
			_road_wins()
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
		for c in f.cells.duplicate():
			var cell := Farms.cell_corners(f, c)
			if not RoadWins.hits(field_corr, cell):
				continue
			var left := RoadWins.clip(field_corr, cell)
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
	if not education.campuses.is_empty():
		economy.money += education.make_way(corr)
		_lots_dirty = true
	if not telecom.companies.is_empty():
		economy.money += telecom.make_way(corr)
		_lots_dirty = true
		telecom_changed.emit()
	if not banks.banks.is_empty():
		economy.money += banks.make_way(corr)
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
	_refresh()
	Perf.add("sim.lots", t)
	t = Perf.now()
	vegetation.update(self)
	Perf.add("sim.vegetation", t)
	t = Perf.now()
	if tick_count % MOVE_EVERY == 0:
		_move_in()
		# The budget only pays out on the hour, so it's worked out then.
		update_stats(tick_count % TICKS_PER_HOUR == 0)
	Perf.add("sim.people", t)
	t = Perf.now()
	if tick_count % GROW_EVERY == 0:
		_grow_one()
		# A builder with a construction loan from a bank in town puts up one more.
		if not banks.banks.is_empty() and banks.builds_more(self):
			var key := _grow_one(1)
			if key != "":
				banks.financed(self, key)
	Perf.add("sim.growth", t)
	t = Perf.now()
	if tick_count % Balance.DEVELOP_EVERY == 0:
		_develop_one()
	if tick_count % Farms.DECIDE_EVERY == 0 and not farms.farms.is_empty():
		farms.tax_rate = economy.tax[ZoneMap.Zone.INDUSTRIAL]
		farms.price = Farms.price_on(tick_count / (24.0 * TICKS_PER_HOUR))
		if farms.decide(field_usable):
			_lots_dirty = true  # lots under new fields go away
			farms_changed.emit()
	Perf.add("sim.farms", t)
	t = Perf.now()
	if tick_count % Industry.DECIDE_EVERY == 0 and not industry.sites.is_empty():
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
	if tick_count % Balance.WAREHOUSE_DECIDE_EVERY == 0 and not warehouses.buildings.is_empty():
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
	if tick_count % Balance.PARK_DECIDE_EVERY == 0 and not parks.sites.is_empty():
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
	if tick_count % Power.DECIDE_EVERY == 0 and not power.sites.is_empty():
		if _decide_power():
			power_changed.emit()
	Perf.add("sim.power", t)
	t = Perf.now()
	# Once a month every hub's leader looks at its development tree (Agency).
	if tick_count % (24 * TICKS_PER_HOUR) == 12 * TICKS_PER_HOUR:
		_develop_hubs()
	Perf.add("sim.hub_leaders", t)
	t = Perf.now()
	# ...and every family looks at what it owns, and whether to branch out.
	if tick_count % (24 * TICKS_PER_HOUR) == 13 * TICKS_PER_HOUR:
		families.month(self)
	Perf.add("sim.families", t)
	t = Perf.now()
	if tick_count % WaterUtility.DECIDE_EVERY == 0 and not services.water.utilities.is_empty():
		var res := services.water.decide(self, yard_usable)
		economy.money += int(res[1])
		if res[0]:
			_lots_dirty = true  # lots under new yard pieces go away
			water_changed.emit()
	Perf.add("sim.water", t)
	# Taxes come in and upkeep goes out every game hour, a day settling a month.
	if tick_count % TICKS_PER_HOUR == 0:
		economy.money += roundi(economy.monthly_net() / 24.0)
	# Before logistics, which clears Traffic's arrivals.
	t = Perf.now()
	hubs.tick(self)
	construction.tick(self)
	Perf.add("sim.civic_hubs", t)
	pollution.tick(self)
	if not in_region and tick_count % (24 * TICKS_PER_HOUR) == 0:
		t = Perf.now()
		Trade.settle({"me": self}, {})
		Perf.add("sim.trade", t)
	t = Perf.now()
	mail.tick(self)
	Perf.add("sim.mail", t)
	t = Perf.now()
	rail.tick(self)
	Perf.add("sim.rail", t)
	t = Perf.now()
	healthcare.tick(self)
	Perf.add("sim.healthcare", t)
	if not simulate_traffic:
		Perf.add("sim.tick", t0)
		return
	t = Perf.now()
	# Before logistics, which clears Traffic's arrival list.
	for id in buses.tick(self) + taxis.tick(self):
		_clear_zones_under(services.footprint(id))
		_lots_dirty = true
	Perf.add("sim.buses", t)
	t = Perf.now()
	logistics.tick(self)
	Perf.add("sim.logistics", t)
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
func update_stats(budget := true) -> void:
	var pop := 0
	var home_cap := 0
	var shop_jobs := 0
	var factory_jobs := 0
	# Shops and factories still going up count toward demand (they're
	# coming) but nobody works there yet.
	var unfinished_jobs := 0
	var presold := 0  # buyers waiting on homes going up (see _move_in)
	for key in buildings:
		var b: Dictionary = buildings[key]
		if int(b.zone) != ZoneMap.Zone.RESIDENTIAL and _utilities_ok(key) \
				and not construction.is_done("lot:" + key, tick_count):
			unfinished_jobs += b.cap
		match int(b.zone):
			ZoneMap.Zone.RESIDENTIAL:
				pop += b.occ
				home_cap += b.cap
				if not construction.is_done("lot:" + key, tick_count):
					presold += mini(b.cap, 2)
			ZoneMap.Zone.COMMERCIAL:
				# Flats above a shop count as homes.
				pop += int(b.get("focc", 0))
				home_cap += int(b.get("flats", 0))
				if _utilities_ok(key):  # closed without power or water
					shop_jobs += b.cap
			ZoneMap.Zone.INDUSTRIAL:
				if _utilities_ok(key):
					factory_jobs += b.cap
	services.plants = power.sources()
	services.update(network, lots, buildings)
	parks.update_effects(self)
	factory_jobs += farms.jobs() + industry.jobs() + warehouses.jobs() + power.jobs() + rail.jobs()
	# Teachers, and office and tech jobs for the town's graduates (less the
	# ones already counted in office buildings, which house those jobs).
	shop_jobs += education.jobs() - mini(BuildingTypes.office_jobs(self), education.office_jobs())
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
	stats = {"population": pop, "workers": workers, "jobs": open_jobs,
		"employed": mini(workers, open_jobs), "homes_free": free}
	demand[ZoneMap.Zone.RESIDENTIAL] = clampf(
		0.6 + 0.6 * float(jobs - coming_workers) / maxf(coming_workers, 40.0)
		- float(free) / maxf(home_cap, 30.0), 0.0, 1.0)
	demand[ZoneMap.Zone.COMMERCIAL] = clampf(
		0.05 + (coming * 0.12 - shop_jobs) / maxf(shop_jobs, 12.0), 0.0, 1.0)
	demand[ZoneMap.Zone.INDUSTRIAL] = clampf(
		0.1 + float(coming_workers - jobs) / maxf(coming_workers, 40.0)
		+ 0.4 * (shop_jobs * 0.8 - factory_jobs) / maxf(factory_jobs, 20.0), 0.0, 1.0)
	for z in demand:
		demand[z] = clampf(demand[z] + economy.demand_shift(z) + mail.demand_shift(z), 0.0, 1.0)
	# A boil-water notice, or a steep water bill, puts people off moving in.
	demand[ZoneMap.Zone.RESIDENTIAL] = clampf(demand[ZoneMap.Zone.RESIDENTIAL]
		- Balance.WATER_BOIL_DEMAND * services.water.boil_share(self) - services.water.rate_penalty(self), 0.0, 1.0)
	# Good care keeps people in town and draws families.
	demand[ZoneMap.Zone.RESIDENTIAL] = clampf(demand[ZoneMap.Zone.RESIDENTIAL] + healthcare.demand_shift(self), 0.0, 1.0)
	# Past village size, people want fire, police, a clinic and a school nearby.
	if pop > 300:
		demand[ZoneMap.Zone.RESIDENTIAL] = clampf(
			demand[ZoneMap.Zone.RESIDENTIAL] + 0.3 * (service_coverage() - 0.5), 0.0, 1.0)
	# Parks and landmarks make a town nicer to live in.
	demand[ZoneMap.Zone.RESIDENTIAL] = clampf(demand[ZoneMap.Zone.RESIDENTIAL]
		+ Balance.AMENITY_DEMAND * parks.average_happiness(self), 0.0, 1.0)
	# Good cell service and internet draw people, and fiber draws offices.
	if not telecom.companies.is_empty():
		demand[ZoneMap.Zone.RESIDENTIAL] = clampf(demand[ZoneMap.Zone.RESIDENTIAL]
			+ Balance.TELECOM_HOME_DEMAND * telecom.town_signal, 0.0, 1.0)
		demand[ZoneMap.Zone.COMMERCIAL] = clampf(demand[ZoneMap.Zone.COMMERCIAL] + telecom.office_demand(), 0.0, 1.0)
	if budget:
		economy.update_budget(self)
	stats_changed.emit()


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
	var keys0 := buildings.keys()
	keys0.sort()
	for key in keys0:
		var nb: Dictionary = buildings[key]
		if nb.zone == ZoneMap.Zone.RESIDENTIAL and nb.occ == 0 and _utilities_ok(key):
			var since: int = tick_count - int(nb.built) - Construction.duration("house")
			if since >= 0 and since < MOVE_EVERY * 6:
				nb.occ = mini(nb.cap, 2)
	var arrivals := 1 + int(demand[ZoneMap.Zone.RESIDENTIAL] * 4.0)
	if demand[ZoneMap.Zone.RESIDENTIAL] <= 0.05:
		return
	var keys := buildings.keys()
	keys.sort()
	for key in keys:
		var b: Dictionary = buildings[key]
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
		if industry.covers(p) or power.covers(p):
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
		if farms.covers(p) or farms.field_at(p) != -1:
			return "That ground is farmland."
		if industry.covers(p) or power.covers(p):
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
		if farms.covers(p) or farms.field_at(p) != -1:
			return "That ground is farmland."
		if industry.covers(p):
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
		if farms.covers(p) or farms.field_at(p) != -1 or industry.covers(p) or reserves.kind_at(p) != "" \
				or hubs.covers(p) or education.covers(p) or mail.covers(p) or power.covers(p) or banks.covers(p) or rail.covers(p) or telecom.covers(p):
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
		if farms.covers(p) or farms.field_at(p) != -1:
			return "That ground is farmland."
		if industry.covers(p) or power.covers(p):
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
	var near := network.find_segment_near(pos, Industry.MAX_DRIVE, 1.0)
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
	services.policies = policies
	hubs.policies = policies
	parks.policies = policies
	power.policies = policies


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
		"taxi":
			return "taxis" if taxis.companies.has(id) and services.buildings.has(id) else ""
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
			"post_office", "warehouse", "taxi", "telecom", "hospital"]:
		if not permits.locators.has(kind):
			continue
		var ids: Array = {"farm": farms.farms, "industry": industry.sites, "service": services.buildings,
			"hub": hubs.hubs, "park": parks.sites, "campus": education.campuses, "bank": banks.banks,
			"bus_depot": buses.depots, "water": services.water.utilities, "post_office": mail.offices,
			"warehouse": warehouses.buildings, "taxi": taxis.companies, "telecom": telecom.companies,
			"hospital": healthcare.hubs}[kind].keys()
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
	var near := network.find_segment_near(pos, Farms.MAX_DRIVE, 1.0)
	if near.is_empty():
		return []
	return Farms.make_drive(pos, dir, near.point)


## True when ground for a field is clear: no road, lot, service or farmyard.
## True when a public road runs between a and b on the ground.
func road_between(a: Vector3, b: Vector3) -> bool:
	var a2 := Vector3(a.x, 0.0, a.z)
	var b2 := Vector3(b.x, 0.0, b.z)
	var n := maxi(2, ceili(a2.distance_to(b2) / 6.0))
	for i in range(1, n):
		var p := a2.lerp(b2, float(i) / n)
		if not network.find_segment_near(Vector3(p.x, Terrain.ground_y(p.x, p.z), p.z), 4.0, 3.0).is_empty():
			return true
	return false


func field_usable(mid: Vector3, corners: PackedVector2Array) -> bool:
	var key := Vector2i(roundi(mid.x), roundi(mid.z))
	if _usable_cache.has(key):
		return _usable_cache[key]
	var ok := network.find_segment_near(mid, Farms.CELL * 0.6 + RoadStyle.right_of_way_half(RoadStyle.Type.AVENUE), 2.0).is_empty()
	var pts := [mid]
	for c in corners:
		pts.append(mid.lerp(Vector3(c.x, 0.0, c.y), 0.8))
	if ok:
		for p in pts:
			if services.covers(p) or farms.covers(p) or industry.covers(p) or farms.field_at(p) != -1 \
					or hubs.covers(p) or warehouses.covers(p) or parks.covers(p) or education.covers(p) \
					or mail.covers(p) or power.covers(p) or banks.covers(p) or rail.covers(p) or telecom.covers(p) \
					or not land_ok(p):
				ok = false
	if ok:
		for key2 in lots:
			# Fields can take empty roadside lots, but not zoned or built ones.
			if not buildings.has(key2) and zones.zone_at(lots[key2].zone_pt) == ZoneMap.Zone.NONE:
				continue
			if lots[key2].pos.distance_to(mid) < Farms.CELL * 0.71 + 16.0:
				ok = false
				break
	_usable_cache[key] = ok
	return ok


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
		if services.covers(p) or farms.covers(p) or farms.field_at(p) != -1 or industry.covers(p) or reserves.kind_at(p) != "":
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
			var full := "No %s: build a %s in Services ($%s)" % [u, Services.KINDS[starter].name, money_text(cost)]
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
		if unlinked[u] > 0 and u == "water" and not services.water.utilities.is_empty():
			text += ": the water utility hasn't laid mains under their streets yet"
		elif unlinked[u] > 0:
			text += ": their streets aren't joined by road to a %s" % ("power line" if u == "power" else "water source")
		else:
			var use: Array = services.utility_use[u]
			text += ": %s is full (%s of %s homes), build a %s" % [u, money_text(use[0]), money_text(use[1]),
				"Substation" if u == "power" else "Water tower"]
		fulls.append(text)
	return [" · ".join(shorts), ". ".join(fulls)]


## Buildings on zoned lots that lack power or water.
func unserved_count() -> int:
	var n := 0
	for key in buildings:
		if not services.has_utilities(key):
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
func _paint_frontage(seg: int, side: int, zone: int) -> void:
	var s := planner.side_survey(network, seg, side)
	if s.is_empty():
		return
	# A strip from the sidewalk back about 17 m, so the zone stays when the
	# street is widened later (a Street to a Boulevard moves lots 8.5 m).
	for r in s.rays:
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
## out, and pollution.
func land_factor(key: String) -> float:
	return hubs.lot_factor(self, key) * pollution.lot_factor(self, key)


func _lot_blocked(lot: Dictionary) -> bool:
	for p in [lot.pos, lot.front, lot.zone_pt]:
		if services.covers(p) or farms.covers(p) or farms.field_at(p) != -1 or industry.covers(p) \
				or reserves.kind_at(p) != "" or hubs.covers(p) or warehouses.covers(p) or parks.covers(p) or education.covers(p) \
				or mail.covers(p) or power.covers(p) or banks.covers(p) or rail.covers(p) or telecom.covers(p):
			return true
	# No lots in the water or on ground too steep to build on.
	return not land_ok(lot.pos, LotPlanner.FRONTAGE * 0.5)


func _refresh() -> void:
	if _lots_dirty or _lots_light:
		var full := _lots_dirty
		_lots_dirty = false
		_lots_light = false
		planner.update(network)
		# Lots with buildings are parcels: they stay as they are unless a road
		# now runs through them.
		var frozen := {}
		var lost := []
		var keys := buildings.keys()
		keys.sort()
		for key in keys:
			if lots.has(key):
				var lot := planner.revalidate(network, lots[key])
				if not full and is_same(lot, lots[key]):
					frozen[key] = lot  # no road came near it
				elif not lot.is_empty() and not _lot_blocked(lot):
					frozen[key] = lot
				else:
					lost.append(key)
		lots = frozen.duplicate()
		if not lost.is_empty():
			parcels_lost.emit(lost)
		for lot in planner.plan(network, zones, frozen):
			# No lots under a service building.
			if not _lot_blocked(lot):
				lots[lot.key] = lot
		_usable_cache.clear()
		services.plants = power.sources()
		services.update(network, lots, buildings)
		lots_changed.emit()
	# Buildings go away when their lot disappears or its zone changes, so
	# this only needs a look after zoning, lots or buildings change.
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
	var saved := reserves.crosses(RoadNetwork.sample_curve(c[0], c[1], c[2], 24))
	if problem == "" and saved != "":
		problem = "That land is reserved for %s. Clear the reserve first." % Reserves.KINDS[saved]
	if problem == "" and Economy.road_cost(c, type) > economy.money:
		return "Not enough money: this road costs $%s." % money_text(Economy.road_cost(c, type))
	return problem


## What it costs to build these road pieces.
static func shapes_cost(curves: Array, type: int) -> int:
	var total := 0
	for c in curves:
		total += Economy.road_cost(c, type)
	return total


## What upgrading a road costs: the difference in build price, nothing to
## downgrade. -1 if there is no such road.
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
				and rng.randf() < -power.land_value_effect(lots[key].pos) * Balance.POWER_SMOKE_GROWTH:
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
		if not Agency.develop(self, s, Agency.TREES[s.kind], s.pos, industry.yearly_profit(id)).is_empty():
			site_built = true
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
			continue
		var o: Array = opts[rng.randi() % opts.size()]
		redevelop(key, o[0], o[1])
		return


## Rebuilds a building as another type or stage (the owner's call). Residents
## stay up to the new size. Build's agency can call this too.
func redevelop(key: String, type: String, level: int) -> void:
	if not buildings.has(key):
		return
	var b := BuildingTypes.make(self, key, buildings[key], type, level)
	b.changed = tick_count
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
	streets.name_road(self, network.segments.keys().filter(func(id): return not id in before),
		streets.town_road(hash([city_seed, a, b])))
	streets.sync(self)
	economy.money = money
	var ends := [network.find_node_near(pts[0], 1.0), network.find_node_near(pts[-1], 1.0)]
	for i in link_ends:
		if ends[int(i)] != -1 and not ends[int(i)] in region_links:
			region_links.append(ends[int(i)])
	return ends


func _parcels_to_save() -> Dictionary:
	var out := {}
	var keys := buildings.keys()
	keys.sort()
	for key in keys:
		if lots.has(key):
			out[key] = LotPlanner.lot_to_save(lots[key])
	return out


func to_dict() -> Dictionary:
	vegetation.update(self)  # land cleared since the last tick counts
	return {
		"version": 2,
		"links": region_links,
		"trade": trade.to_dict(),
		"tick": tick_count,
		"seed": city_seed,
		"roads": network.to_dict(),
		"zones": zones.to_dict(),
		"buildings": buildings,
		"parcels": _parcels_to_save(),
		"economy": economy.to_dict(),
		"services": services.to_dict(),
		"farms": farms.to_dict(),
		"industry": industry.to_dict(),
		"power": power.to_dict(),
		"education": education.to_dict(),
		"telecom": telecom.to_dict(),
		"banks": banks.to_dict(),
		"logistics": logistics.to_dict(),
		"construction": construction.to_dict(),
		"warehouses": warehouses.to_dict(),
		"reserves": reserves.to_dict(),
		"rail": rail.to_dict(),
		"permits": permits.to_dict(),
		"hubs": hubs.to_dict(),
		"parks": parks.to_dict(),
		"mail": mail.to_dict(),
		"families": families.to_dict(),
		"streets": streets.to_dict(),
		"policies": policies.to_dict(),
		"pollution": pollution.to_dict(),
		"healthcare": healthcare.to_dict(),
		"junctions": traffic.rules_to_dict(),
		"traffic": traffic.to_dict(),
		"buses": buses.to_dict(),
		"taxis": taxis.to_dict(),
		"vegetation": vegetation.to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	vegetation.from_dict(d.get("vegetation", {}))
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
	families.from_dict(d.get("families", {}))
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
	reserves.from_list(d.get("reserves", []))
	rail.from_dict(d.get("rail", {}))
	permits.from_dict(d.get("permits", {}))
	hubs.from_dict(d.get("hubs", {}))
	parks.from_dict(d.get("parks", {}))
	mail.from_dict(d.get("mail", {}))
	policies.from_dict(d.get("policies", {}))
	pollution.from_dict(d.get("pollution", {}))
	healthcare.from_dict(d.get("healthcare", {}))
	for legacy in farms.legacy_outlines:
		reserves.paint(legacy[0], legacy[1])
	for id in farms.farms:
		var f: Dictionary = farms.farms[id]
		if f.drive.is_empty():
			f.drive = farm_drive(f.pos, f.dir)
	traffic.rules_from_dict(d.get("junctions", {}))
	traffic.from_dict(d.get("traffic", {}))
	tick_count = int(d.get("tick", 0))
	city_seed = int(d.get("seed", 1))
	# Parcels: the lots buildings stand on.
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
		if z == ZoneMap.Zone.INDUSTRIAL and b.has("chain"):
			buildings[key].chain = str(b.chain)
	_road_wins()
	_lots_dirty = true
	_refresh()
	# Factories from before industry chains take up the local one.
	for key in buildings:
		if buildings[key].zone == ZoneMap.Zone.INDUSTRIAL and not buildings[key].has("chain"):
			buildings[key].chain = factory_chain(lots[key].pos) if lots.has(key) else "general"
	pollution.after_load(self)
	update_stats()
	buses = BusNet.new()
	buses.from_dict(self, d.get("buses", {}))
	taxis = TaxiCo.new()
	taxis.from_dict(self, d.get("taxis", {}))
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
		if circle.is_empty() or circle[1] < RoadShapes.ROUNDABOUT_MIN - 1.0 or circle[1] > RoadShapes.ROUNDABOUT_MAX + 1.0:
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
