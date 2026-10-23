class_name Insights
extends RefCounted
## Turns play telemetry (see Telemetry) into a ranked list of fixes, each
## with the thread that owns it. The region server redoes it every half hour
## as report.md in its telemetry folder; tools/telemetry_report.gd runs it
## by hand.
##
## Ranking: a problem more players hit ranks higher than one player hitting
## it often; broken things (errors, failed joins) beat slow things, which
## beat hard-to-find things. Speed and simple multiplayer come first.

## Load budgets in seconds, by what the loading screen said; others get DEFAULT.
const LOAD_BUDGET := {"Connecting to the region": 5.0, "Opening your town": 10.0}
const LOAD_BUDGET_DEFAULT := 10.0
## The web page should reach its first frame in this many seconds.
const PAGE_BUDGET := 20.0
const FPS_FLOOR := 30.0
const HITCHES_PER_MINUTE := 2.0
## A thing is hard to find when it takes longer or more clicks than this.
const FIND_SECONDS := 6.0
const FIND_CLICKS := 3.0
const PERF_SAMPLE_SECONDS := 15.0

## Who fixes what, by where an error happened.
const OWNERS := [
	["scripts/net", "Multiplayer and game shell"], ["scripts/shell", "Multiplayer and game shell"],
	["scripts/traffic", "Traffic simulation"], ["scripts/vehicles", "Vehicles"],
	["scripts/terrain", "Terrain"], ["scripts/art", "Art style and asset library"],
	["scripts/buildings", "Art style and asset library"], ["scripts/power", "Power"],
	["scripts/banks", "Banks"], ["scripts/sim/balance", "Game balance"],
	["construction", "Construction"], ["scripts/perf", "Performance budget"],
	["scripts/telemetry", "Player telemetry"],
]
const UI_OWNER := "Build roadmap and loop"
const PERF_OWNER := "Performance budget"
const NET_OWNER := "Multiplayer and game shell"


## Every batch in the newest `days` day files of a telemetry folder.
static func read_dir(dir: String, days := 14) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	var files := Array(d.get_files()).filter(func(f): return f.ends_with(".jsonl"))
	files.sort()
	for f in files.slice(maxi(files.size() - days, 0)):
		for line in FileAccess.get_file_as_string(dir.path_join(f)).split("\n", false):
			var b = JSON.parse_string(line)
			if typeof(b) == TYPE_DICTIONARY:
				out.append(b)
	return out


static func owner_for(file: String) -> String:
	for o in OWNERS:
		if o[0] in file:
			return o[1]
	return UI_OWNER


## {"summary": {...}, "fixes": [{"score", "title", "detail", "owner", "kind", "players"}, ...]}
## with the fixes best first.
static func analyze(batches: Array) -> Dictionary:
	# Every event, tagged with who and which build.
	var ev := {}
	var players := {}
	var sessions := {}
	var builds := {}
	for b in batches:
		var who := str(b.get("from", b.get("player", "?")))
		players[who] = true
		sessions[str(b.get("session", ""))] = true
		builds[str(b.get("build", ""))] = true
		for e in b.get("events", []):
			if typeof(e) != TYPE_DICTIONARY:
				continue
			e["_who"] = who
			e["_build"] = str(b.get("build", ""))
			e["_session"] = str(b.get("session", ""))
			var k := str(e.get("k", ""))
			if not ev.has(k):
				ev[k] = []
			ev[k].append(e)
	var fixes := []
	_join_fixes(ev, fixes)
	_error_fixes(ev, fixes)
	_speed_fixes(ev, fixes)
	_finding_fixes(ev, fixes)
	_stuck_fixes(ev, fixes)
	fixes.sort_custom(func(a, b): return a.score > b.score)
	var hunts: Array = ev.get("hunt", []).filter(func(h): return h.end == "used")
	var by_build := {}
	for h in hunts:
		if not by_build.has(h._build):
			by_build[h._build] = []
		by_build[h._build].append(float(h.s))
	var find := {}
	for bld in by_build:
		find[bld] = snappedf(median(by_build[bld]), 0.1)
	return {"fixes": fixes, "summary": {"players": players.size(), "sessions": sessions.size(),
		"batches": batches.size(), "builds": builds.keys(), "find_seconds_by_build": find,
		"find_seconds": snappedf(median(hunts.map(func(h): return float(h.s))), 0.1),
		"fps": snappedf(median(ev.get("perf", []).filter(func(p): return p.get("scene") == "main").map(func(p): return float(p.fps))), 0.1),
		"top_features": _top_features(ev, 12)}}


static func _join_fixes(ev: Dictionary, fixes: Array) -> void:
	var fails := _group(ev.get("join_fail", []), "reason")
	for reason in fails:
		var g: Array = fails[reason]
		var who := _who(g)
		_fix(fixes, 100 + 10 * who, "Players couldn't join: \"%s\"" % reason,
			"%d failed joins from %d players." % [g.size(), who], NET_OWNER, "multiplayer", who)
	var drops: Array = ev.get("dropped", [])
	if drops.size() >= 2:
		_fix(fixes, 60 + 8 * _who(drops), "Players get dropped from the region",
			"%d drops from %d players." % [drops.size(), _who(drops)], NET_OWNER, "multiplayer", _who(drops))


static func _error_fixes(ev: Dictionary, fixes: Array) -> void:
	var counts := {}
	for e in ev.get("error_count", []):
		counts[e.sig] = int(counts.get(e.sig, 0)) + int(e.n) - 1
	var errs := _group(ev.get("error", []), "sig")
	for sig in errs:
		var g: Array = errs[sig]
		var first: Dictionary = g[0]
		var n: int = g.size() + int(counts.get(sig, 0))
		var who := _who(g)
		var base := 70.0 if first.type == "script" else (50.0 if first.type == "error" else 15.0)
		var where := "%s:%s" % [str(first.file).trim_prefix("res://"), int(first.line)]
		var detail := "%d times for %d players. In %s." % [n, who, where]
		if str(first.get("ctx", "")) != "":
			detail += " Last thing pressed: %s." % first.ctx
		if str(first.get("trace", "")) != "":
			detail += "\n\n```\n%s\n```" % str(first.trace).left(600)
		_fix(fixes, base + 8 * who + 3 * log(n + 1) / log(2), "%s: %s" % [first.type.capitalize(), first.msg],
			detail, owner_for(str(first.file)), "bug", who)


static func _speed_fixes(ev: Dictionary, fixes: Array) -> void:
	var loads := _group(ev.get("load", []), "what")
	for what in loads:
		var g: Array = loads[what]
		var med := median(g.map(func(l): return float(l.s)))
		var budget: float = LOAD_BUDGET.get(what, LOAD_BUDGET_DEFAULT)
		if med > budget:
			_fix(fixes, 60 + 10 * med / budget + 3 * _who(g), "Slow loading screen \"%s\": %.1f s" % [what, med],
				"Median %.1f s over %d loads (budget %.0f s, slowest %.1f s)." % [med, g.size(), budget,
				g.map(func(l): return float(l.s)).max()], PERF_OWNER, "speed", _who(g))
	var boots: Array = ev.get("boot", []).filter(func(b): return int(b.get("page_ms", 0)) > 0)
	if not boots.is_empty():
		var med := median(boots.map(func(b): return b.page_ms / 1000.0))
		if med > PAGE_BUDGET:
			_fix(fixes, 75 + 3 * _who(boots), "The web page takes %.0f s to start" % med,
				"From opening the link to the first frame, download included. Median of %d starts (budget %.0f s)." \
				% [boots.size(), PAGE_BUDGET], PERF_OWNER, "speed", _who(boots))
	var perf: Array = ev.get("perf", []).filter(func(p): return p.get("scene") == "main")
	if perf.is_empty():
		return
	var fps := median(perf.map(func(p): return float(p.fps)))
	var slow: Array = perf.filter(func(p): return float(p.fps) < FPS_FLOOR)
	if fps < FPS_FLOOR or slow.size() * 4 > perf.size():
		var pops: Array = slow.map(func(p): return float(p.get("pop", 0)))
		_fix(fixes, 70 + (FPS_FLOOR - minf(fps, FPS_FLOOR)) + 3 * _who(slow), "Low frame rate: median %.0f fps" % fps,
			"%d%% of samples under %.0f fps, from %d players; median town size when slow: %d people." \
			% [100 * slow.size() / perf.size(), FPS_FLOOR, _who(slow), int(median(pops))], PERF_OWNER, "speed", _who(slow))
	var hitches := 0
	for p in perf:
		hitches += int(p.get("hitches", 0))
	var per_min := hitches / (perf.size() * PERF_SAMPLE_SECONDS / 60.0)
	if per_min > HITCHES_PER_MINUTE:
		_fix(fixes, 55 + 2 * per_min, "Stutters: %.1f hitches a minute" % per_min,
			"Frames over 100 ms while playing (worst %d ms)." % perf.map(func(p): return int(p.get("worst_ms", 0))).max(),
			PERF_OWNER, "speed", _who(perf))


static func _finding_fixes(ev: Dictionary, fixes: Array) -> void:
	var hunts: Array = ev.get("hunt", [])
	var used := _group(hunts.filter(func(h): return h.end == "used"), "target")
	for target in used:
		var g: Array = used[target]
		var s := median(g.map(func(h): return float(h.s)))
		var clicks := median(g.map(func(h): return float(h.clicks)))
		if s <= FIND_SECONDS and clicks <= FIND_CLICKS:
			continue
		var travel := median(g.map(func(h): return float(h.travel)))
		_fix(fixes, 30 + 4 * _who(g) + minf(s, 30.0) + 2 * minf(clicks, 10.0), "Hard to find: %s" % target,
			"Median %.1f s, %d clicks and %.1f screens of mouse travel to get there (%d times). Usual path: %s." \
			% [s, int(clicks), travel, g.size(), _usual_path(g)], UI_OWNER, "finding", _who(g))
	var gave_up := _group(hunts.filter(func(h): return h.end == "escape" and h.path.size() >= 2),
		"path", true)
	for first in gave_up:
		var g: Array = gave_up[first]
		if g.size() < 2:
			continue
		_fix(fixes, 35 + 5 * _who(g) + g.size(), "Players open %s, look around, and back out" % first,
			"%d times; they tried %s before pressing Escape. Whatever they wanted isn't where they look." \
			% [g.size(), _usual_path(g)], UI_OWNER, "finding", _who(g))


static func _stuck_fixes(ev: Dictionary, fixes: Array) -> void:
	var rage := _group(ev.get("rage", []), "over")
	for over in rage:
		var g: Array = rage[over]
		var thing: String = "the map" if over == "" else over
		var ctx := _common(g, "ctx")
		_fix(fixes, 45 + 6 * _who(g) + 2 * g.size(), "Rage clicks on %s" % thing,
			"%d bursts of fast clicks in one spot%s: it doesn't respond the way players expect." \
			% [g.size(), (" while in " + ctx) if ctx != "" else ""], UI_OWNER, "stuck", _who(g))
	for e in _group(ev.get("esc_spam", []), "ctx").values():
		_fix(fixes, 40 + 5 * _who(e) + e.size(), "Hard to get out of %s" % _or_game(e[0].ctx),
			"Players hit Escape again and again (%d times)." % e.size(), UI_OWNER, "stuck", _who(e))
	for e in _group(ev.get("undo_streak", []), "ctx").values():
		_fix(fixes, 35 + 5 * _who(e) + e.size(), "Players keep undoing in %s" % _or_game(e[0].ctx),
			"%d undo streaks: the tool does something they didn't mean." % e.size(), UI_OWNER, "stuck", _who(e))
	for e in _group(ev.get("refused_streak", []), "cmd").values():
		_fix(fixes, 45 + 6 * _who(e) + e.size(), "The game keeps turning down \"%s\"" % e[0].cmd,
			"%d times in a row-ish (in %s). Show why before they click, not after." % [e.size(), _or_game(_common(e, "ctx"))],
			UI_OWNER, "stuck", _who(e))
	# From the feature-use summaries.
	var disabled := {}
	var dead := {}
	var cmds := {}
	for u in ev.get("use", []):
		_sum(disabled, u.get("disabled", {}), u._who)
		_sum(dead, u.get("dead", {}), u._who)
		for t in u.get("cmds", {}):
			if not cmds.has(t):
				cmds[t] = [0, 0]
			cmds[t][0] += int(u.cmds[t][0])
			cmds[t][1] += int(u.cmds[t][1])
	for label in disabled:
		if disabled[label].n >= 3:
			_fix(fixes, 30 + 5 * disabled[label].who.size() + disabled[label].n, "%s is greyed out but gets clicked" % label,
				"%d clicks on it while disabled. Say why it's off, or hide it." % disabled[label].n, UI_OWNER, "stuck",
				disabled[label].who.size())
	for label in dead:
		if dead[label].n >= 5:
			_fix(fixes, 20 + 4 * dead[label].who.size() + dead[label].n / 2.0, "Players click %s, which isn't a button" % label,
				"%d clicks. Make it do the obvious thing or look less clickable." % dead[label].n, UI_OWNER, "stuck",
				dead[label].who.size())
	for t in cmds:
		var total: int = cmds[t][0] + cmds[t][1]
		if total >= 5 and cmds[t][1] * 10 >= total * 3:
			_fix(fixes, 30 + 30.0 * cmds[t][1] / total, "\"%s\" fails %d%% of the time" % [t, 100 * cmds[t][1] / total],
				"%d of %d tries turned down." % [cmds[t][1], total], UI_OWNER, "stuck", 0)


static func _top_features(ev: Dictionary, n: int) -> Array:
	var count := {}
	for u in ev.get("use", []):
		for label in u.get("buttons", {}):
			count[label] = int(count.get(label, 0)) + int(u.buttons[label])
	var labels := count.keys()
	labels.sort_custom(func(a, b): return count[a] > count[b])
	return labels.slice(0, n).map(func(l): return [l, count[l]])


## Markdown for people: the fixes first, then the numbers to watch.
static func to_markdown(r: Dictionary) -> String:
	var s: Dictionary = r.summary
	var md := "# Neighbors play report\n\n"
	md += "%d players, %d sessions. Median time to find something: %s s. Median frame rate in town: %s fps.\n\n" \
		% [s.players, s.sessions, s.find_seconds, s.fps]
	md += "## Fix first\n\n"
	if r.fixes.is_empty():
		md += "Nothing stands out yet.\n"
	var i := 0
	for f in r.fixes.slice(0, 20):
		i += 1
		md += "%d. **%s** (%s, score %d)\n   %s\n" % [i, f.title, f.owner, int(f.score), str(f.detail).replace("\n", "\n   ")]
	if not s.find_seconds_by_build.is_empty():
		md += "\n## Time to find, by build\n\n"
		for b in s.find_seconds_by_build:
			md += "- %s: %s s\n" % [b, s.find_seconds_by_build[b]]
	if not s.top_features.is_empty():
		md += "\n## Most used\n\n"
		for t in s.top_features:
			md += "- %s: %d\n" % [t[0], t[1]]
	return md


static func median(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var a := xs.duplicate()
	a.sort()
	var m := a.size() / 2
	return float(a[m]) if a.size() % 2 == 1 else (float(a[m - 1]) + float(a[m])) / 2.0


static func _fix(fixes: Array, score: float, title: String, detail: String, owner: String, kind: String, players: int) -> void:
	fixes.append({"score": snappedf(score, 0.1), "title": title, "detail": detail, "owner": owner, "kind": kind,
		"players": players})


## Events grouped by a field (by its first entry, for a list like path).
static func _group(events: Array, field: String, first := false) -> Dictionary:
	var out := {}
	for e in events:
		var v = e.get(field, "")
		var key := str(v[0] if first and v is Array and not v.is_empty() else v)
		if not out.has(key):
			out[key] = []
		out[key].append(e)
	return out


static func _who(events: Array) -> int:
	var w := {}
	for e in events:
		w[e.get("_who", "?")] = true
	return w.size()


static func _common(events: Array, field: String) -> String:
	var g := _group(events, field)
	var best := ""
	for k in g:
		if best == "" or g[k].size() > g[best].size():
			best = k
	return best


static func _usual_path(hunts: Array) -> String:
	return _common(hunts.map(func(h): return {"p": " → ".join(PackedStringArray(h.path))}), "p")


static func _or_game(ctx: String) -> String:
	return ctx if ctx != "" else "the game"


static func _sum(into: Dictionary, counts: Dictionary, who: String) -> void:
	for label in counts:
		if not into.has(label):
			into[label] = {"n": 0, "who": {}}
		into[label].n += int(counts[label])
		into[label].who[who] = true
