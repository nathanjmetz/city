class_name TradeHaul
extends RefCounted
## Trading surplus with a friend's town by truck (Brawn's pick #20, after
## Anno's trade routes). What the town's farms, woods, quarry and oil wells
## ship out of town goes on the regional market each month (Trade.offer,
## from what really left last month). When a friend's town buys it, those
## loads drive out on the road toward that town (the deal's link) instead
## of to the nearest highway, and the production chain page shows them going
## to neighbor towns. A load still rides a real truck (Logistics); a deal
## with no road out is money only.
##
## The money: farms and companies already earn what they ship in their own
## books, so the town's budget doesn't take the price again. The buyer pays
## the market price as for any regional deal.
##
## Real reference: Indiana grain and aggregate move mostly by truck within
## about 50 miles, to the nearest elevator or plant that bids for it.

## Goods posted on the market from what left town. Goods another hub posts
## itself (warehouses' goods, the big factories' products and inputs) are
## left to it.
const GOODS := ["corn", "soybeans", "wheat", "logs", "ore", "crude oil"]

## Loads that left town since the last market (good -> loads).
var out_count := {}
## Goods this posts on the market (good -> true), so it never clears another
## hub's offer.
var posted := {}
## Loads sold to friends' towns still to go: good -> [[link node, loads]].
var owed := {}
## Loads sold to friends' towns at the last market and this one so far.
var last := 0
var _month := 0
var _hooked = null  # the Trade this listens to


## Each tick: listens for the month's deals, and once a game day (a month
## of books) posts what the town can spare.
func tick(sim) -> void:
	if _hooked != sim.trade:
		_hooked = sim.trade
		sim.trade.deal.connect(on_deal.bind(sim))
	var day := 24 * CitySim.TICKS_PER_HOUR
	if sim.tick_count % day != day - 1:
		return
	# Just before the month's market (Trade.settle runs on the day's turn).
	last = _month
	_month = 0
	for g in GOODS:
		if (sim.trade.offers.has(g) or sim.trade.wants.has(g)) and not posted.has(g):
			continue  # another hub's
		var o := float(out_count.get(g, 0))
		sim.trade.offer(g, o)
		if o > 0.0:
			posted[g] = true
		else:
			posted.erase(g)
	out_count.clear()


## Logistics: a load of `good` left town.
func counted(good: String) -> void:
	if good in GOODS:
		out_count[good] = int(out_count.get(good, 0)) + 1


## A deal settled on a good this posts: the town's budget gives the price
## back (its producers were paid in their own books), and loads a friend's
## town bought are owed on the road toward it.
func on_deal(d: Dictionary, sim) -> void:
	var g := str(d.get("good", ""))
	if not posted.has(g) or str(d.get("buyer", "")) == "outside" and str(d.get("seller", "")) == "outside":
		return
	if d.has("sold") and not bool(d.sold):
		return  # this town bought it (not from its own offer)
	var money := roundi(float(d.amount) * float(d.price))
	sim.economy.money -= money
	sim.trade.net -= money
	if str(d.get("buyer", "")) == "outside" or int(d.get("link", -1)) == -1:
		return
	var loads := roundi(float(d.amount))
	if loads <= 0:
		return
	if not owed.has(g):
		owed[g] = []
	owed[g].append([int(d.link), loads])
	_month += loads


## Where a load of `good` leaving from `from` goes: toward a friend's town
## that bought it, else the nearest highway (Logistics._edge).
func export_edge(sim, from: Vector3, good: String) -> Dictionary:
	var q: Array = owed.get(good, [])
	while not q.is_empty():
		var link := int(q[0][0])
		if not sim.network.nodes.has(link):
			q.pop_front()  # that road's gone: the rest was money only
			continue
		q[0][1] = int(q[0][1]) - 1
		if int(q[0][1]) <= 0:
			q.pop_front()
		return {"ref": "edge", "pos": Logistics._xz(sim.network.nodes[link]), "friend": true}
	owed.erase(good)
	return sim.logistics._edge(sim, from)


func to_dict() -> Dictionary:
	return {"out": out_count, "posted": posted.keys(), "owed": owed, "last": last, "month": _month}


func from_dict(d: Dictionary) -> void:
	out_count = {}
	for g in d.get("out", {}):
		out_count[str(g)] = int(d.out[g])
	posted = {}
	for g in d.get("posted", []):
		posted[str(g)] = true
	owed = {}
	for g in d.get("owed", {}):
		owed[str(g)] = Array(d.owed[g]).map(func(e): return [int(e[0]), int(e[1])])
	last = int(d.get("last", 0))
	_month = int(d.get("month", 0))
