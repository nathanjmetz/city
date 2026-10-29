extends SceneTree
## Trading surplus with a friend's town (Brawn's pick #20): what left town
## last month goes on the market, a friend's town buys it, and those loads
## drive out on the road toward that town. The town's budget doesn't take
## the price twice (its producers were paid in their own books).
## Run: godot --headless -s tests/test_trade_haul.gd


func _init() -> void:
	var a := _town()
	var b := _town()
	var day := 24 * CitySim.TICKS_PER_HOUR
	for i in 5:
		a.trade_haul.counted("logs")
	a.trade_haul.counted("furniture")  # not a raw good it posts
	a.tick_count = day - 1
	a.trade_haul.tick(a)
	_check(is_equal_approx(float(a.trade.offers.get("logs", {}).get("amount", 0.0)), 5.0)
		and not a.trade.offers.has("furniture"), "last month's logs go on the market (%s)" % str(a.trade.offers))
	# Another hub's offer is left alone.
	b.trade.offer("corn", 7.0)
	b.trade_haul.counted("corn")
	b.tick_count = day - 1
	b.trade_haul.tick(b)
	_check(is_equal_approx(float(b.trade.offers.corn.amount), 7.0), "another hub's offer is left alone")
	b.trade.want("logs", 3.0)
	var link_a: int = a.region_links[0]
	var link_b: int = b.region_links[0]
	var money_a := a.economy.money
	Trade.settle({"a": a, "b": b}, {"a": {"b": link_a}, "b": {"a": link_b}})
	_check(is_equal_approx(b.trade.got("logs"), 3.0), "the friend's town bought 3 loads")
	_check(b.trade.last_deals.any(func(d): return d.good == "logs" and d.seller == "a" and is_equal_approx(float(d.price), Trade.base_price("logs"))),
		"and paid the market price for them")
	_check(a.economy.money == money_a, "the selling town's budget doesn't take the price again (%d)" % (a.economy.money - money_a))
	var to_friend := 0
	for i in 5:
		var e := a.trade_haul.export_edge(a, Vector3.ZERO, "logs")
		if e.get("friend", false):
			to_friend += 1
			_check(Vector2(e.pos[0], e.pos[1]).is_equal_approx(Vector2(a.network.nodes[link_a].x, a.network.nodes[link_a].z)),
				"a sold load heads for the road toward the friend") if to_friend == 1 else null
	_check(to_friend == 3, "three loads drive to the friend's town, the rest to the highway (%d)" % to_friend)
	_check(a.trade_haul.last == 0 and a.trade_haul._month == 3, "the month's loads with friends are counted")
	# The chain page shows them going to neighbor towns.
	var wid := a.industry.add_site("forest", Vector3(0, 0, 100), Vector3(0, 0, -1), [Vector3(0, 0, 60), Vector3(0, 0, 6)])
	a.logistics._arrive(a, {"from": {"ref": "site:%d" % wid, "pos": [0, 0]}, "to": {"ref": "edge", "pos": [0, 0], "friend": true},
		"purpose": "raw", "cargo": {"good": "logs", "amount": 1}, "kind": "site"})
	_check(a.chains.links().any(func(l): return l.to == "friend" and l.good == "logs"), "the chain page shows logs to neighbor towns")
	_check(int(a.trade_haul.out_count.get("logs", 0)) == 1, "and counts it for next month's market")
	var copy := TradeHaul.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(a.trade_haul.to_dict())))
	_check(copy.to_dict() == a.trade_haul.to_dict(), "it's saved")

	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _town() -> CitySim:
	var sim := CitySim.new()
	sim.simulate_traffic = false
	sim.economy.money = 10_000_000
	sim.apply({"type": "build_county_road", "a": [-500, 0], "b": [500, 0], "links": [0, 1]})
	return sim


var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
