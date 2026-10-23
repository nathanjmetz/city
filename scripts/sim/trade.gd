class_name Trade
extends RefCounted
## A city's trade with its neighbors and the outside world: goods and
## services bought and sold every month (one game day).
##
## Hubs say what they can spare and what they need; the region matches them.
## Neighbors joined by county road trade first, at a fair price. Whatever
## no neighbor covers comes from (or goes to) the outside world, at a worse
## price, so a good neighbor is worth having. Solo cities trade only with
## the outside. Like Anno's trade routes and CS2's outside connections.
##
## For hub threads:
##   sim.trade.offer("power", 40.0)     # can spare 40 units a month
##   sim.trade.want("garbage", 12.0)    # needs 12 units taken away a month
##   sim.trade.got("garbage")           # how much was covered last month
##   sim.trade.sold("power")            # how much was sold last month
##   sim.trade.deal.connect(...)        # each deal, for trucks and trains
## Offers and wants stay until changed (amount 0 removes them). Set them from
## sim code only (never from the UI), so every copy of the region agrees.
## Goods are any name; prices come from Balance.TRADE_PRICE.

## One deal settled: {"good", "amount", "price" (per unit), "seller", "buyer"
## (city ids, or "outside"), "link" (this city's region link node for the
## trip, -1 if none)}.
signal deal(d: Dictionary)

## good -> {"amount": per month, "price": per unit}
var offers := {}
var wants := {}
## Last month's results: good -> amount.
var bought := {}
var sold_last := {}
## Last month's money from trade (sales minus purchases).
var net := 0
## The deals settled last month, for the budget panel and vehicles.
var last_deals := []


## Can spare `amount` a month. price < 0 uses the region price.
func offer(good: String, amount: float, price := -1.0) -> void:
	_put(offers, good, amount, price)


## Needs `amount` a month. price < 0 uses the region price.
func want(good: String, amount: float, price := -1.0) -> void:
	_put(wants, good, amount, price)


func got(good: String) -> float:
	return bought.get(good, 0.0)


func sold(good: String) -> float:
	return sold_last.get(good, 0.0)


func _put(table: Dictionary, good: String, amount: float, price: float) -> void:
	if amount <= 0.0:
		table.erase(good)
	else:
		table[good] = {"amount": amount, "price": price if price >= 0.0 else base_price(good)}


static func base_price(good: String) -> float:
	return float(Balance.TRADE_PRICE.get(good, Balance.TRADE_PRICE_DEFAULT))


## Settles a month of trade between cities. `cities` maps id -> CitySim;
## `links` maps id -> {neighbor id: this city's link node} (who is joined
## to whom by road). Every copy of the region calls this on the same tick
## with the same cities, so the deals come out the same everywhere.
static func settle(cities: Dictionary, links: Dictionary) -> void:
	var ids := cities.keys()
	ids.sort()
	var left := {}  # id -> good -> amount still for sale
	for id in ids:
		var t: Trade = cities[id].trade
		t.bought = {}
		t.sold_last = {}
		t.net = 0
		t.last_deals = []
		left[id] = {}
		for g in t.offers:
			left[id][g] = float(t.offers[g].amount)
	for id in ids:
		var t: Trade = cities[id].trade
		var goods := t.wants.keys()
		goods.sort()
		for g in goods:
			var need := float(t.wants[g].amount)
			var cap := float(t.wants[g].price)
			# Joined neighbors first, cheapest first.
			var sellers := []
			var near: Dictionary = links.get(id, {})
			for other in near:
				if cities.has(other) and left[other].get(g, 0.0) > 0.0 \
						and float(cities[other].trade.offers[g].price) <= cap:
					sellers.append(other)
			sellers.sort_custom(func(a, b):
				var pa := float(cities[a].trade.offers[g].price)
				var pb := float(cities[b].trade.offers[g].price)
				return pa < pb or (pa == pb and a < b))
			for s in sellers:
				if need <= 0.0:
					break
				var amount: float = minf(need, left[s][g])
				left[s][g] -= amount
				need -= amount
				var price := float(cities[s].trade.offers[g].price)
				_book(cities, s, id, g, amount, price, links)
			if need > 0.0:
				_book(cities, "outside", id, g, need, base_price(g) * Balance.TRADE_IMPORT_MARKUP, links)
	# What no neighbor bought goes out to the wider world, for less.
	for id in ids:
		var goods: Array = left[id].keys()
		goods.sort()
		for g in goods:
			if left[id][g] > 0.0:
				_book(cities, id, "outside", g, left[id][g], base_price(g) * Balance.TRADE_EXPORT_SHARE, links)


static func _book(cities: Dictionary, seller: String, buyer: String, good: String, amount: float,
		price: float, links: Dictionary) -> void:
	var money := roundi(amount * price)
	for side in [[seller, buyer, 1], [buyer, seller, -1]]:
		var id: String = side[0]
		if id == "outside":
			continue
		var sim: CitySim = cities[id]
		var t: Trade = sim.trade
		var other: String = side[1]
		var link: int = links.get(id, {}).get(other, sim.region_links[0] if not sim.region_links.is_empty() else -1)
		var d := {"good": good, "amount": amount, "price": price, "seller": seller, "buyer": buyer, "link": link,
			"sold": side[2] > 0}
		sim.economy.money += money * side[2]
		t.net += money * side[2]
		if side[2] > 0:
			t.sold_last[good] = t.sold_last.get(good, 0.0) + amount
		else:
			t.bought[good] = t.bought.get(good, 0.0) + amount
		t.last_deals.append(d)
		t.deal.emit(d)


## Takes a month's deals settled by the region's server for this city:
## the money moves and the deal signals fire here, on the player's own
## computer, which runs the town.
func receive(sim: CitySim, deals: Array) -> void:
	bought = {}
	sold_last = {}
	net = 0
	last_deals = []
	for d in deals:
		var amount := float(d.amount)
		var money := roundi(amount * float(d.price))
		var selling := bool(d.get("sold", false))
		if selling:
			sold_last[d.good] = sold_last.get(d.good, 0.0) + amount
			net += money
		else:
			bought[d.good] = bought.get(d.good, 0.0) + amount
			net -= money
		var copy: Dictionary = d.duplicate()
		copy.erase("sold")
		last_deals.append(copy)
		deal.emit(copy)
	sim.economy.money += net


func to_dict() -> Dictionary:
	return {"offers": offers, "wants": wants, "bought": bought, "sold": sold_last, "net": net}


func from_dict(d: Dictionary) -> void:
	offers = {}
	wants = {}
	for pair in [[offers, d.get("offers", {})], [wants, d.get("wants", {})]]:
		for g in pair[1]:
			pair[0][str(g)] = {"amount": float(pair[1][g].amount), "price": float(pair[1][g].price)}
	bought = {}
	sold_last = {}
	for g in d.get("bought", {}):
		bought[str(g)] = float(d.bought[g])
	for g in d.get("sold", {}):
		sold_last[str(g)] = float(d.sold[g])
	net = int(d.get("net", 0))
