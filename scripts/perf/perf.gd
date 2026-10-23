class_name Perf
extends RefCounted
## Measures how long each system takes, so we can tell what the game spends
## its time on and keep every system inside its budget (see PerfBudget).
##
## Cheap enough to leave on everywhere: two clock reads and a dictionary
## update per measured block. Use it like this:
##
##     var t := Perf.now()
##     ... the work ...
##     Perf.add("traffic", t)
##
## Keys are the names in PerfBudget. The hidden overlay (F3, see PerfOverlay)
## and the benchmark (tools/perf_run.gd) read the numbers back.

## Per key: {avg (smoothed ms), peak (recent worst ms, fades), n (samples
## since reset), sum (ms since reset), max (worst ms since reset)}.
static var stats := {}
## Counters set by systems each frame or tick: cars, trees, buildings...
static var counts := {}


static func now() -> int:
	return Time.get_ticks_usec()


## Records the time since `since` (from Perf.now()) under `key`.
static func add(key: String, since: int) -> void:
	record(key, (Time.get_ticks_usec() - since) / 1000.0)


## Records `ms` milliseconds under `key`.
static func record(key: String, ms: float) -> void:
	var s: Dictionary = stats.get(key, {})
	if s.is_empty():
		s = {"avg": ms, "peak": ms, "n": 0, "sum": 0.0, "max": 0.0}
		stats[key] = s
	s.avg = lerpf(s.avg, ms, 0.05)
	# The recent peak fades by half in about five seconds of ticks or frames.
	s.peak = maxf(ms, s.peak * 0.998)
	s.n += 1
	s.sum += ms
	s.max = maxf(s.max, ms)


static func count(key: String, value: int) -> void:
	counts[key] = value


## Mean ms per sample since the last reset.
static func mean(key: String) -> float:
	var s: Dictionary = stats.get(key, {})
	return 0.0 if s.is_empty() or s.n == 0 else s.sum / s.n


static func reset() -> void:
	stats.clear()
	counts.clear()
