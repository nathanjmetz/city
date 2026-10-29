extends SceneTree
## Run: godot --headless -s tests/test_words.gd
##
## Text built from names reads as plain English (Words): "a" or "an" by the
## next word's sound, plurals that don't add "es" to a plural, and names that
## keep their capitals mid-sentence. The critic's text dump (2026-10-27) found
## "You have no county fairgroundses yet.", "You have no rv plants yet.",
## "Click a road to make it a Avenue.", "to where the logs is", "Crude Oil
## within reach" and a taxi company "with two buses". This checks the rules,
## every building and road name, and then the real texts: every card's
## tooltip, the hint and the "You have ..." line for every tool, and the
## upgrade hint for every road type.

var _failed := false
var _main: Node


func _initialize() -> void:
	_rules()
	_names()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_run.call_deferred()


func _rules() -> void:
	for pair in [["avenue", "an avenue"], ["Avenue", "an Avenue"], ["street", "a street"], ["one-way street", "a one-way street"],
			["university", "a university"], ["utility", "a utility"], ["hour", "an hour"], ["RV plant", "an RV plant"],
			["ATM vestibule", "an ATM vestibule"], ["US highway", "a US highway"], ["8-lane road", "an 8-lane road"],
			["11-acre lot", "an 11-acre lot"], ["110-acre lot", "a 110-acre lot"], ["unincorporated town", "an unincorporated town"],
			["oil company", "an oil company"], ["elementary school", "an elementary school"], ["European car", "a European car"],
			["S-curve", "an S-curve"], ["T-junction", "a T-junction"], ["U-turn", "a U-turn"]]:
		_check(Words.a(pair[0]) == pair[1], "a/an: %s (%s)" % [pair[1], Words.a(pair[0])])
	_check(Words.a_first("avenue") == "An avenue", "a sentence starts \"An avenue\"")
	for pair in [["county fairgrounds", "county fairgrounds"], ["RV plant", "RV plants"], ["bus", "buses"],
			["community library", "community libraries"], ["church", "churches"], ["highway", "highways"],
			["Avenue with bike lanes", "Avenues with bike lanes"], ["Avenue, center turn lane", "Avenues, center turn lane"],
			["Drive-up teller lanes", "Drive-up teller lanes"], ["campus", "campuses"], ["well pad", "well pads"],
			["logging stand", "logging stands"], ["pit", "pits"], ["box", "boxes"], ["person", "people"], ["shelf", "shelves"]]:
		_check(Words.plural(pair[0]) == pair[1], "plural: %s (%s)" % [pair[1], Words.plural(pair[0])])
	_check(Words.count(1, "well pad") == "1 well pad" and Words.count(3, "well pad") == "3 well pads", "counts: 1 well pad, 3 well pads")
	for pair in [["Water tower", "water tower"], ["RV plant", "RV plant"], ["Farm Credit office", "Farm Credit office"],
			["ATM vestibule", "ATM vestibule"], ["Avenue", "avenue"], ["Main street", "main street"]]:
		_check(Words.mid(pair[0]) == pair[1], "mid-sentence: %s (%s)" % [pair[1], Words.mid(pair[0])])
	_check(Words.first_up("crude oil") == "Crude oil", "only the first letter goes up: Crude oil")
	_check(_slips("Click a road to make it a Avenue.").size() == 1 and _slips("Click a road to make it an avenue.").is_empty()
		and _slips("an RV plant, a one-way street, an hour, a university").is_empty(), "the checker below catches a/an slips")


## Every building and road name: its plural, its article and its capitals.
func _names() -> void:
	var names := ["Post office", "Rail depot", "Power company", "Phone company", "Farmhouse", "Factory"]
	for table in [Services.KINDS, CivicHubs.KINDS, Industry.KINDS, Education.KINDS, Banks.KINDS, Warehouses.KINDS,
			BigFactories.KINDS, Parks.KINDS, Power.PLANTS, WaterUtility.NAMES]:
		for k in table:
			if table[k] is Dictionary and table[k].has("name"):
				names.append(str(table[k].name))
	for t in RoadStyle.TYPES:
		names.append(str(t.name))
	_check(names.size() > 80, "found the building and road names (%d)" % names.size())
	var bad := []
	for n in names:
		var one := Words.mid(n)
		var many := Words.plural(one)
		var head := _head(one)
		var last := head.get_slice(" ", head.get_slice_count(" ") - 1).to_lower()
		# A plural adds to the head noun once: never "fairgroundses", never
		# the same word back unless it was already plural.
		if many.contains("groundses") or many.contains("eses") and not last.ends_with("s"):
			bad.append("double plural: %s -> %s" % [n, many])
		if many == one and not (last.ends_with("s") or last in Words.SAME):
			bad.append("no plural: %s" % n)
		# Initials keep their capitals; everything else is lower case
		# mid-sentence unless it's a proper name (two capitals in a row).
		for w in n.split(" "):
			if w.length() >= 2 and w == w.to_upper() and w != w.to_lower() and not (one.contains(w) and many.contains(w)):
				bad.append("lost capitals: %s -> %s / %s" % [n, one, many])
		if one.substr(0, 1) != one.substr(0, 1).to_lower() and not _proper(n):
			bad.append("capital mid-sentence: %s" % one)
		# "an" before a vowel sound, by the first word.
		var first := one.get_slice(" ", 0).to_lower()
		var said_vowel := "aeiou".contains(first.substr(0, 1)) and not first.begins_with("one") and not first.begins_with("uni") \
			and not first.begins_with("uti") and not first.begins_with("use")
		if one.get_slice(" ", 0) == one.get_slice(" ", 0).to_upper() and one.get_slice(" ", 0).length() >= 2:
			said_vowel = "AEFHILMNORSX".contains(one.substr(0, 1))
		if Words.a(one).begins_with("an ") != said_vowel:
			bad.append("article: %s" % Words.a(one))
	for b in bad:
		print("  ", b)
	_check(bad.is_empty(), "every building and road name has a right plural, article and capitals (%d wrong)" % bad.size())


func _run() -> void:
	while _main.loading:
		await process_frame
	var hud: Hud
	var hints: PlacementHints
	for c in _main.get_children():
		if c is Hud:
			hud = c
		if c is PlacementHints:
			hints = c
	_check(hud != null and hints != null, "found the HUD and the placement hints")
	if hud == null or hints == null:
		_end()
		return
	var slips := []
	var lines := 0
	var taxi_ok := true
	for entry in hud._all_cards:
		var b: Button = entry[0]
		if entry[1] == "views":
			continue
		hud.close_all()
		hud.press_card(b)
		await process_frame
		hints._update_marks()
		for text in [b.tooltip_text, hud._hint_text, hints._marks_line]:
			for s in _slips(text):
				slips.append("%s: %s  [%s]" % [Hud.card_title(b), s, text])
		if hints._marks_line != "":
			lines += 1
		if hud.service_tool.kind == Services.Kind.TAXI_COMPANY:
			taxi_ok = taxi_ok and not (b.tooltip_text + hud._hint_text).contains("bus") and hud._hint_text.contains("cabs")
	hud.close_all()
	_check(lines > 30, "the building tools say what's already built (%d)" % lines)
	_check(taxi_ok, "the taxi company comes with cabs, not buses, in its card and its hint")
	# Every road type's upgrade hint.
	var rt: RoadTool = hud.road_tool
	var said := []
	rt.hint_changed.connect(func(t: String): said.append(t))
	rt.set_mode(RoadTool.Mode.UPGRADE)
	for t in RoadStyle.TYPES.size():
		rt.road_type = t
		rt._update_hint()
		var text: String = said[-1] if not said.is_empty() else ""
		for s in _slips(text):
			slips.append("road %s: %s  [%s]" % [RoadStyle.TYPES[t].name, s, text])
	rt.set_mode(RoadTool.Mode.NONE)
	_check(said.any(func(t: String): return t.contains("make it an avenue")), "\"Click a road to make it an avenue.\"")
	# The industry tools: where the logs are, and the resource in plain case.
	var forest := ""
	for entry in hud._all_cards:
		if Hud.card_title(entry[0]) == "Forestry":
			hud.press_card(entry[0])
			await process_frame
			forest = hud._hint_text
	hud.close_all()
	_check(forest.contains("to where the logs are") and forest.contains("logging stands"), "forestry: its logging stands spread to where the logs are")
	for s in slips:
		print("  ", s)
	_check(slips.is_empty(), "no wrong a/an, plural or capitals in any card, hint or \"You have\" line (%d)" % slips.size())
	_end()


## What's wrong in `text`: "a" before a vowel sound, "an" before a
## consonant, a doubled plural, initials in lower case, or Title Case from
## Godot's capitalize() on a resource.
func _slips(text: String) -> Array:
	var out := []
	var re := RegEx.create_from_string("\\b([Aa]n?) ([A-Za-z0-9][\\w'-]*)")
	for m in re.search_all(text):
		var an := m.get_string(1).to_lower() == "an"
		if an != Words.wants_an(m.get_string(2)):
			out.append(m.get_string())
	for bad in ["groundses", " rv ", " atm ", "Crude Oil", "Oil Within", "logs is"]:
		if text.contains(bad):
			out.append(bad)
	return out


## The part of a name before ", " or " with " (what gets pluralized).
func _head(name: String) -> String:
	var cut := name.length()
	for e in Words.HEAD_ENDS:
		var i := name.find(e)
		if i > 0 and i < cut:
			cut = i
	return name.substr(0, cut)


## A proper name keeps its capitals ("Farm Credit office").
func _proper(name: String) -> bool:
	var w := name.split(" ")
	return w.size() > 1 and w[1] != "" and w[1].substr(0, 1) != w[1].substr(0, 1).to_lower() \
		or (w[0].length() >= 2 and w[0] == w[0].to_upper())


func _end() -> void:
	print("ALL TESTS PASSED" if not _failed else "TESTS FAILED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	_failed = _failed or not ok
