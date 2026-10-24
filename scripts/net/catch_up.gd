class_name CatchUp
extends RefCounted
## "While you were away, your neighbors were at work." A town pauses while
## its player is away, but the neighbors keep playing. When the player comes
## back, their town lives the game time the neighbors played meanwhile
## (Region.away_report), up to a season, then a card says what happened.
##
## It is the town's own tick, run a few extra times per frame inside a time
## budget while the player is already playing (no longer loading), with the
## cars left parked where they are (they are the costly part and don't move
## money). Each game month on the way, trade settles with the neighbors as
## their towns stand now, just as the region's market does for towns that
## are online, so they keep buying what the town makes. Shared-service fees
## and regional projects follow the town's clock by themselves
## (RegionClient). The same rules and seeds as normal play, so nothing
## drifts.

## The most game time caught up: a season (three game months).
const MAX_TICKS := 3 * 24 * CitySim.TICKS_PER_HOUR
## Less than this (half a game month) isn't worth a fast-forward or a card.
const MIN_TICKS := 12 * CitySim.TICKS_PER_HOUR
## Main-thread time spent on catching up per frame, in ms. The browser
## (one thread, and slower) gets less, so it takes longer but never stutters.
const BUDGET_MS := 6.0
const WEB_BUDGET_MS := 3.0
## The most catch-up ticks in one frame, so a tiny town doesn't flash past.
const MAX_PER_FRAME := 24
const MONTH := 24 * CitySim.TICKS_PER_HOUR

var sim: CitySim
var region: Region
var my_city := ""
var report := {}
## Ticks to play in all, and still to play.
var total := 0
var left := 0
## The town before catching up (see _glance), for the card.
var before := {}
## Money from the neighbors (their purchases minus ours) over the catch-up.
var sold_to_neighbors := 0.0
var bought_from_neighbors := 0.0


## How many ticks a report asks for: the most game time any neighbor
## played, capped at a season; 0 when it's too little to bother.
static func ticks_for(r: Dictionary) -> int:
	var t := mini(int(r.get("ticks", 0)), MAX_TICKS)
	return t if t >= MIN_TICKS else 0


func _init(s: CitySim, r: Region, city: String, away: Dictionary) -> void:
	sim = s
	region = r
	my_city = city
	report = away
	total = ticks_for(away)
	left = total
	before = _glance()


func done() -> bool:
	return left <= 0


## 0 to 1.
func progress() -> float:
	return 1.0 if total <= 0 else 1.0 - float(left) / total


## Game months played so far, and in all.
func months_done() -> int:
	return ceili(float(total - left) / MONTH)


func months() -> int:
	return maxi(1, roundi(float(total) / MONTH))


## Plays as many catch-up ticks as fit in `budget_ms` (and MAX_PER_FRAME).
## Returns how many it played.
func step(budget_ms := BUDGET_MS, max_ticks := MAX_PER_FRAME) -> int:
	if left <= 0 or sim.held:
		return 0
	var until := Time.get_ticks_usec() + int(budget_ms * 1000.0)
	var n := 0
	var cars := sim.simulate_traffic
	sim.simulate_traffic = false
	while left > 0 and n < max_ticks and Time.get_ticks_usec() < until:
		sim.tick()
		left -= 1
		n += 1
		if sim.tick_count % MONTH == 0:
			_settle_month()
	sim.simulate_traffic = cars
	return n


## A month of trade with the neighbors as their towns stand now. Only this
## town's side counts: the neighbors' copies here are just drawings, and
## their own computers keep their own books.
func _settle_month() -> void:
	if region == null or not region.cities.has(my_city):
		return
	var sims := {my_city: sim}
	var links := region.trade_links()
	for other in links.get(my_city, {}):
		if region.cities.has(other) and not region.stale_ids().has(other):
			sims[other] = region.cities[other].sim
	Trade.settle(sims, links)
	for d in sim.trade.last_deals:
		var other: String = d.buyer if d.sold else d.seller
		if other == "outside":
			continue
		var money := float(d.amount) * float(d.price)
		if d.sold:
			sold_to_neighbors += money
		else:
			bought_from_neighbors += money


func _glance() -> Dictionary:
	var counts := [0, 0, 0, 0]
	for key in sim.buildings:
		var z := int(sim.buildings[key].get("zone", 0))
		if z >= 0 and z < counts.size():
			counts[z] += 1
	return {"pop": int(sim.stats.get("population", 0)), "built": counts[1] + counts[2] + counts[3],
		"money": float(sim.economy.money)}


## The card's lines, two to four short ones, most telling first: the
## neighbors who did the most, regional projects they moved along, what
## they bought from us, and how our own town changed.
func lines() -> Array:
	var out := []
	var towns: Array = report.get("towns", []).duplicate()
	towns.sort_custom(func(a, b): return _busy(a) > _busy(b))
	for t in towns:
		if out.size() >= 2:
			break
		var line := _town_line(t)
		if line != "":
			out.append(line)
	for p in report.get("projects", []):
		if out.size() >= 3:
			break
		out.append("Neighbors' pledges finished the %s's %s." % [p.name, str(p.stage).to_lower()])
	if sold_to_neighbors >= 1.0:
		out.append("Your neighbors bought %s of your goods." % _money(sold_to_neighbors))
	var now := _glance()
	var grew: int = now.pop - int(before.pop)
	var built: int = now.built - int(before.built)
	var mine := []
	if grew != 0:
		mine.append("%s%s people" % ["+" if grew > 0 else "", _thousands(grew)])
	if built > 0:
		mine.append("%d new building%s" % [built, "" if built == 1 else "s"])
	if not mine.is_empty():
		out.append("Your town: %s." % ", ".join(mine))
	return out.slice(0, 4)


static func _busy(t: Dictionary) -> int:
	if t.get("new", false):
		return 1_000_000
	return absi(int(t.get("pop", 0))) + 10 * (int(t.get("homes", 0)) + int(t.get("shops", 0)) + int(t.get("works", 0)))


static func _town_line(t: Dictionary) -> String:
	var who := str(t.get("player", ""))
	var town := str(t.get("name", "A neighbor"))
	if t.get("new", false):
		return "%s founded %s nearby." % [who if who != "" else "A new neighbor", town]
	var pop := int(t.get("pop", 0))
	var homes := int(t.get("homes", 0))
	var others := int(t.get("shops", 0)) + int(t.get("works", 0))
	var did := []
	if pop > 0:
		did.append("grew by %s people" % _thousands(pop))
	if homes > 0:
		did.append("built %d home%s" % [homes, "" if homes == 1 else "s"])
	if others > 0:
		did.append("opened %d new business%s" % [others, "" if others == 1 else "es"])
	if did.is_empty():
		return ""
	if did.size() > 2:
		did = [did[0], did[1]]
	return "%s %s." % [town, " and ".join(did)]


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func _money(v: float) -> String:
	if v >= 1_000_000.0:
		return "$%.1fM" % (v / 1_000_000.0)
	if v >= 10_000.0:
		return "$%dk" % roundi(v / 1000.0)
	return "$" + _thousands(roundi(v))
