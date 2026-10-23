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
## Of that, the download and the engine start (web/shell.html timings).
const DOWNLOAD_BUDGET := 15.0
const START_BUDGET := 5.0
## A sim tick should take at most this long, on average (PerfBudget).
const TICK_BUDGET_MS := 25.0
const FPS_FLOOR := 30.0
const HITCHES_PER_MINUTE := 2.0
const LOW_FREE_MB := 400
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
	["scripts/telemetry", "Player telemetry"], ["scripts/audio", "Sound and music"],
]
const SOUND_OWNER := "Sound and music"
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
	_sound_fixes(ev, fixes)
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
		var seen := {}
		for e in g:
			seen[e._build] = true
		var detail := "%d times for %d players. In %s. Seen in builds %s." % [n, who, where, ", ".join(PackedStringArray(seen.keys()))]
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
	var dl: Array = boots.filter(func(b): return int(b.get("download_ms", 0)) > 0)
	if not dl.is_empty():
		var med := median(dl.map(func(b): return b.download_ms / 1000.0))
		var mb := median(dl.map(func(b): return float(b.get("bytes", 0)) / 1048576.0))
		if med > DOWNLOAD_BUDGET:
			_fix(fixes, 72 + 3 * _who(dl), "The download takes %.0f s" % med,
				"%.0f MB at a median %.0f KB/s over %d starts (budget %.0f s). Make the download smaller or cache it." \
				% [mb, mb * 1024.0 / maxf(med, 0.1), dl.size(), DOWNLOAD_BUDGET], PERF_OWNER, "speed", _who(dl))
	var st: Array = boots.filter(func(b): return int(b.get("start_ms", 0)) > 0)
	if not st.is_empty():
		var med := median(st.map(func(b): return b.start_ms / 1000.0))
		if med > START_BUDGET:
			_fix(fixes, 65 + 3 * _who(st), "The engine takes %.1f s to start after the download" % med,
				"Median of %d starts (budget %.0f s)." % [st.size(), START_BUDGET], PERF_OWNER, "speed", _who(st))
	var perf: Array = ev.get("perf", []).filter(func(p): return p.get("scene") == "main")
	if perf.is_empty():
		return
	var ticks: Array = perf.filter(func(p): return p.has("tick_ms"))
	if not ticks.is_empty():
		var med := median(ticks.map(func(p): return float(p.tick_ms)))
		if med > TICK_BUDGET_MS:
			_fix(fixes, 60 + med / TICK_BUDGET_MS * 5 + 3 * _who(ticks), "Sim ticks take %.0f ms" % med,
				"Median over %d samples (budget %.0f ms, worst %.0f ms). Costliest: %s." % [ticks.size(), TICK_BUDGET_MS,
				ticks.map(func(p): return float(p.get("tick_max_ms", 0))).max(), _costliest(ticks)], PERF_OWNER, "speed", _who(ticks))
	var fps := median(perf.map(func(p): return float(p.fps)))
	var slow: Array = perf.filter(func(p): return float(p.fps) < FPS_FLOOR)
	if fps < FPS_FLOOR or slow.size() * 4 > perf.size():
		var pops: Array = slow.map(func(p): return float(p.get("pop", 0)))
		_fix(fixes, 70 + (FPS_FLOOR - minf(fps, FPS_FLOOR)) + 3 * _who(slow), "Low frame rate: median %.0f fps" % fps,
			"%d%% of samples under %.0f fps, from %d players; median town size when slow: %d people. Costliest systems then: %s." \
			% [100 * slow.size() / perf.size(), FPS_FLOOR, _who(slow), int(median(pops)), _costliest(slow)], PERF_OWNER, "speed", _who(slow))
	var hitches := 0
	for p in perf:
		hitches += int(p.get("hitches", 0))
	var per_min := hitches / (perf.size() * PERF_SAMPLE_SECONDS / 60.0)
	if per_min > HITCHES_PER_MINUTE:
		_fix(fixes, 55 + 2 * per_min, "Stutters: %.1f hitches a minute" % per_min,
			"Frames over 100 ms while playing (worst %d ms)." % perf.map(func(p): return int(p.get("worst_ms", 0))).max(),
			PERF_OWNER, "speed", _who(perf))
	# Whole-second freezes: the game looks hung to the player.
	var stalls: Array = ev.get("stall", [])
	if not stalls.is_empty():
		var longest: Dictionary = stalls[0]
		for one in stalls:
			if int(one.ms) > int(longest.ms):
				longest = one
		_fix(fixes, 90 + 3 * _who(stalls) + mini(stalls.size(), 10), "Freezes: %d frames over a second (longest %.1f s)" \
			% [stalls.size(), int(longest.ms) / 1000.0],
			"Longest in %s while using %s. Slowest timed stages then: %s. %d of %d came with shader compiles." \
			% [longest.get("scene", "?"), longest.get("ctx", "") if longest.get("ctx", "") != "" else "nothing", str(longest.get("stages", {})),
				stalls.filter(func(x): return int(x.get("pipelines", 0)) > 0).size(), stalls.size()],
			PERF_OWNER, "speed", _who(stalls))
	# Desktop only: memory left on the machine. Near zero means macOS starts
	# swapping, which looks like a freeze to the player.
	var tight: Array = ev.get("perf", []).filter(func(p): return int(p.get("free_mb", 0)) > 0 and int(p.free_mb) < LOW_FREE_MB)
	if not tight.is_empty():
		var low: int = tight.map(func(p): return int(p.free_mb)).min()
		_fix(fixes, 65 + 3 * _who(tight), "Machine nearly out of memory: %d MB free" % low,
			"%d samples under %d MB free (graphics memory up to %d MB). Lower the default tier or texture sizes on small machines." \
			% [tight.size(), LOW_FREE_MB, tight.map(func(p): return int(p.get("vram_mb", 0))).max()], PERF_OWNER, "speed", _who(tight))


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
			% [g.size(), (" while in " + ctx) if ctx != "" else ""], UI_OWNER, "stuck", _who(g), g)
	for e in _group(ev.get("esc_spam", []), "ctx").values():
		_fix(fixes, 40 + 5 * _who(e) + e.size(), "Hard to get out of %s" % _or_game(e[0].ctx),
			"Players hit Escape again and again (%d times)." % e.size(), UI_OWNER, "stuck", _who(e), e)
	for e in _group(ev.get("undo_streak", []), "ctx").values():
		_fix(fixes, 35 + 5 * _who(e) + e.size(), "Players keep undoing in %s" % _or_game(e[0].ctx),
			"%d undo streaks: the tool does something they didn't mean." % e.size(), UI_OWNER, "stuck", _who(e), e)
	for e in _group(ev.get("refused_streak", []), "cmd").values():
		_fix(fixes, 45 + 6 * _who(e) + e.size(), "The game keeps turning down \"%s\"" % e[0].cmd,
			"%d times in a row-ish (in %s). Show why before they click, not after." % [e.size(), _or_game(_common(e, "ctx"))],
			UI_OWNER, "stuck", _who(e), e)
	for e in _group(ev.get("redo_loop", []), "cmd").values():
		_fix(fixes, 45 + 6 * _who(e) + 2 * e.size(), "Players build \"%s\" and tear it down again" % e[0].cmd,
			"%d times they built, removed and rebuilt within a minute or two (in %s): the preview doesn't match what gets built, or it's hard to aim." \
			% [e.size(), _or_game(_common(e, "ctx"))], UI_OWNER, "stuck", _who(e), e)
	for e in _group(ev.get("cancel_loop", []), "ctx").values():
		_fix(fixes, 40 + 6 * _who(e) + 2 * e.size(), "Players pick %s and back out without using it" % _or_game(e[0].ctx),
			"%d times they opened it, tried, and pressed Escape with nothing built." % e.size(), UI_OWNER, "stuck", _who(e), e)
	for e in _group(ev.get("no_progress", []), "ctx").values():
		_fix(fixes, 45 + 6 * _who(e) + 2 * e.size(), "Lots of clicking with %s and nothing gets built" % _or_game(e[0].ctx),
			"%d times: %d+ clicks on the map with the tool in hand and no result." % [e.size(), TelemetryTracker.NO_PROGRESS_CLICKS],
			UI_OWNER, "stuck", _who(e), e)
	for e in _group(ev.get("scroll_dead", []), "kind").values():
		_fix(fixes, 70 + 8 * _who(e) + e.size(), "Scrolling (%s) doesn't zoom" % e[0].kind,
			"%d times players scrolled again and again and the camera stayed put. Their mouse or trackpad sends %s events." \
			% [e.size(), e[0].kind], UI_OWNER, "stuck", _who(e), e)
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


## The sim systems that most often top the samples' top_sim lists.
static func _costliest(samples: Array) -> String:
	var n := {}
	for p in samples:
		for key in p.get("top_sim", {}):
			n[key] = float(n.get(key, 0.0)) + float(p.top_sim[key])
	var keys := n.keys()
	keys.sort_custom(func(a, b): return n[a] > n[b])
	return ", ".join(PackedStringArray(keys.slice(0, 3).map(func(k): return "%s %.1f ms" % [k, n[k] / samples.size()]))) \
		if not keys.is_empty() else "not measured"


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
		if f.has("replay"):
			md += "\n   What %s did:\n\n   ```\n   %s\n   ```\n" % [f.replay.who, "\n   ".join(replay_lines(f.replay, 25))]
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


## events: the moments behind it; the first with a replay goes along.
## Sounds players flagged as bad (pause menu > Audio, or N). The latest flag
## from each player counts, so taking a flag back clears it.
static func _sound_fixes(ev: Dictionary, fixes: Array) -> void:
	var last := {}   # "sound|who" -> event
	for e in ev.get("sound_flag", []):
		last["%s|%s" % [e.sound, e._who]] = e
	var bad := {}    # sound -> events still flagged
	for e in last.values():
		if bool(e.get("on", true)):
			if not bad.has(e.sound):
				bad[e.sound] = []
			bad[e.sound].append(e)
	for sound in bad:
		var g: Array = bad[sound]
		var who := _who(g)
		var just := g.filter(func(e): return e.get("how", "") == "just_heard").size()
		_fix(fixes, 55 + 10 * who, "Bad sound: \"%s\" (assets/audio/%s.ogg)" % [str(g[0].get("label", sound)), sound],
			"Flagged by %d players%s. Muted for them; replace it with a better real recording or remove it." \
			% [who, " (%d right after hearing it)" % just if just > 0 else ""], SOUND_OWNER, "sound", who)


static func _fix(fixes: Array, score: float, title: String, detail: String, owner: String, kind: String, players: int,
		events := []) -> void:
	var f := {"score": snappedf(score, 0.1), "title": title, "detail": detail, "owner": owner, "kind": kind,
		"players": players}
	for e in events:
		if e.has("replay") and not e.replay.is_empty():
			f["replay"] = {"who": e.get("_who", ""), "t": e.t, "a": e.replay}
			break
	fixes.append(f)


## A replay as readable lines, seconds before the moment it was flagged.
static func replay_lines(rep: Dictionary, most := 30) -> PackedStringArray:
	var out := PackedStringArray()
	var acts: Array = rep.a
	for a in acts.slice(maxi(acts.size() - most, 0)):
		out.append("%6.1fs  %s" % [float(a[0]) - float(rep.t), action_text(a)])
	return out


static func action_text(a: Array) -> String:
	match str(a[1]):
		"b": return "pressed %s" % a[2]
		"c": return "clicked the map" + (" at %d, %d" % [a[4], a[5]] if a.size() >= 6 else "")
		"d": return "dragged" + (" %d, %d to %d, %d" % [a[2], a[3], a[4], a[5]] if a.size() >= 6 else "")
		"k": return "key %s" % a[2]
		"x": return "%s %s%s" % [a[2], "done" if a[3] else "TURNED DOWN", (" (%s)" % a[4]) if a.size() > 4 and str(a[4]) != "" else ""]
		"h": return "hint: \"%s\"" % a[2]
		"s": return "%s x%d (camera %s m to %s m%s)" % [a[2], a[3], a[5], a[6], ", didn't move" if is_equal_approx(float(a[5]), float(a[6])) else ""]
	return str(a)


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
