class_name ProductionView
extends VBoxContainer
## The production chain page inside the Economy page (Brawn's pick #15,
## after Anno's production overview): each chain the town has, with every
## link the last year's trucks drove, from where a good is grown, cut or dug
## to where it was made into something and where it went. Only what really
## happened (ProductionChains): no tips, no warnings.

var sim: CitySim
var _rows := VBoxContainer.new()
var _empty := UiStyle.label("No loads yet. Once farms, woods, a quarry or factories ship, each chain shows here.",
	12, UiStyle.MUTED)
var _sig := []


func setup(s: CitySim) -> void:
	sim = s


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	add_child(UiStyle.label("Truckloads over the last year, from where each good starts to where it went.",
		11, UiStyle.MUTED))
	get_child(0).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_empty)
	_rows.add_theme_constant_override("separation", 4)
	add_child(_rows)


## Draws the chains again if anything changed.
func refresh() -> void:
	if sim == null:
		return
	var chains := sim.chains.chains()
	if chains == _sig:
		return
	_sig = chains
	for c in _rows.get_children():
		c.queue_free()
	_empty.visible = chains.is_empty()
	for chain in chains:
		_rows.add_child(UiStyle.label(str(chain.name).to_upper(), 10, UiStyle.MUTED))
		for l in chain.links:
			_rows.add_child(_link_row(l))
		_rows.add_child(HSeparator.new())


## One link: [from icon] From → [to icon] To, the good and its loads.
func _link_row(l: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var a: Dictionary = ProductionChains.NODES.get(l.from, {"name": l.from, "icon": "industry"})
	var b: Dictionary = ProductionChains.NODES.get(l.to, {"name": l.to, "icon": "industry"})
	row.add_child(Icon.new(a.icon, 16))
	row.add_child(UiStyle.label(a.name, 12))
	row.add_child(UiStyle.label("→", 12, UiStyle.MUTED))
	row.add_child(Icon.new(b.icon, 16))
	var to := UiStyle.label(b.name, 12)
	to.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	to.clip_text = true
	row.add_child(to)
	var n := int(l.loads)
	var what := UiStyle.label("%s, %d load%s" % [l.good, n, "" if n == 1 else "s"], 11, UiStyle.MUTED)
	what.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(what)
	return row
