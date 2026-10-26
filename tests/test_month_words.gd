extends SceneTree
## Run: godot --headless -s tests/test_month_words.gd
##
## A month is a day (docs/spec-month-is-a-day.md, Nathan 2026-10-26: "Money and
## timers count in days, for example '$12k a day' and 'ends in 3 days'").
## The town's budget settles once a sim day, so any text the player reads that
## still says "a month", "monthly" or "/mo" for that period is a leftover.
## This scans every quoted string in scripts/ that reads like a sentence (it
## has a space) and fails on one that mentions a month and is not a real
## calendar use. Names with no space ("month", "monthly", "price_per_month",
## "months+") are save keys and code, not text, so they pass.

## Exact substrings of legitimate calendar uses, each with its reason.
const ALLOWED := [
	"by Indiana's odds for the month",  # weather odds follow the calendar month
	"the last five months",  # stats span tooltip: five calendar months
	"5 months",  # stats span chip: five calendar months
	"Month by month",  # date chart title: bars are calendar months
	"years, %d months",  # town age is counted on the calendar
	"A month passes in",  # date card: a calendar month takes about an hour
	"Each bar is the end of a month",  # date chart note: calendar months
	"1st of next month",  # charter: takes effect on the calendar's 1st
	"1st of the next month",  # charter: same, other wording
	"The town votes next month",  # charter flavor line about the calendar
]
## Whole files that are not shown to players (a developer's timing table).
const SKIP_FILES := ["res://scripts/perf/perf_budget.gd"]

var _failed := false


func _init() -> void:
	# The scanner itself: it must catch leftovers and ignore code and comments.
	_check(_hits('x = "Costs $%s a month"').size() == 1, "scanner flags 'a month'")
	_check(_hits('x = "Net +$5K/mo"').size() == 1, "scanner flags '/mo'")
	_check(_hits('x = "monthly subsidy of the town"').size() == 1, "scanner flags 'monthly'")
	_check(_hits('x = {"price_per_month": 3, "months+": 1.0}').is_empty(), "scanner ignores keys with no space")
	_check(_hits('x = 1  # Costs a month "in a comment"').is_empty(), "scanner ignores comments")
	_check(_hits('x = "In May, the next moment"').is_empty(), "scanner ignores 'moment'")
	_check(_hits('x = """a shader\nper month"""').is_empty(), "scanner skips triple-quoted blocks")
	var files := _gd_files("res://scripts")
	_check(files.size() > 200, "found the scripts (%d files)" % files.size())
	var bad := 0
	for f in files:
		if f in SKIP_FILES:
			continue
		for h in _hits(FileAccess.get_file_as_string(f)):
			bad += 1
			print("FAIL leftover month word in %s: \"%s\"" % [f, h])
	_check(bad == 0, "no leftover 'month' words in text the player reads")
	print("FAILED" if _failed else "ALL PASSED")
	quit(1 if _failed else 0)


## Every quoted string in `src` (outside comments and triple-quoted blocks)
## that has a space, mentions a month, and is not allowed.
func _hits(src: String) -> Array:
	var out := []
	for s in _strings(src):
		if not s.contains(" "):
			continue
		var low: String = s.to_lower()
		if not (low.contains("month") or _has_mo(low)):
			continue
		var ok := false
		for a in ALLOWED:
			if s.contains(a):
				ok = true
				break
		if not ok:
			out.append(s)
	return out


## "/mo" as a word ("$5K/mo"), not "/moment".
func _has_mo(low: String) -> bool:
	var i := low.find("/mo")
	while i != -1:
		var after := low[i + 3] if i + 3 < low.length() else " "
		if not (after >= "a" and after <= "z"):
			return true
		i = low.find("/mo", i + 3)
	return false


## The contents of each single-line quoted string in GDScript source.
func _strings(src: String) -> Array:
	var out := []
	var i := 0
	var n := src.length()
	while i < n:
		var c := src[i]
		if c == "#":
			while i < n and src[i] != "\n":
				i += 1
		elif c == '"' or c == "'":
			if src.substr(i, 3) == c.repeat(3):
				var end := src.find(c.repeat(3), i + 3)
				i = n if end == -1 else end + 3
				continue
			var j := i + 1
			var s := ""
			while j < n and src[j] != c and src[j] != "\n":
				if src[j] == "\\" and j + 1 < n:
					s += src[j + 1]
					j += 2
				else:
					s += src[j]
					j += 1
			out.append(s)
			i = j
		i += 1
	return out


func _gd_files(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for name in d.get_files():
		if name.ends_with(".gd"):
			out.append(dir.path_join(name))
	for sub in d.get_directories():
		out.append_array(_gd_files(dir.path_join(sub)))
	return out


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("FAIL " + what)
		_failed = true
	else:
		print("PASS " + what)
