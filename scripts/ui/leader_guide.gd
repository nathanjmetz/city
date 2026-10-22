class_name LeaderGuide
extends VBoxContainer
## Your word to a hub's leader, at the bottom of its info panel (Brawn: the
## permit idea works both ways). Tell them to grow (buy up land around them,
## e.g. toward an international airport), use their own judgment, or hold
## off, and pre-approve permits near them so they needn't ask. They act on
## it over time with their own money and judgment. Shown for any hub that
## has signed up with Permits (sim.permits.locators has its kind).

const STANCE_TEXT := {
	"grow": ["Grow", "Buy up land around you and grow, as your budget allows"],
	"steady": ["Your call", "Run it the way you see fit"],
	"hold": ["Hold off", "No new land and no new requests for now"],
}

var sim: CitySim
var hub := ""
var hub_id := 0
var _stances := {}   # stance -> Button
var _grants := {}    # metres -> Button
var _said := UiStyle.label("", 11, UiStyle.MUTED)


## True if this kind of selection is a hub that takes guidance.
static func takes(s: CitySim, selection: Dictionary) -> bool:
	return not selection.is_empty() and s.permits.locators.has(str(selection.get("type", "")))


func setup(s: CitySim, kind: String, id: int) -> void:
	sim = s
	hub = kind
	hub_id = id
	_sync()


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	add_child(HSeparator.new())
	add_child(UiStyle.label("YOUR WORD TO THE LEADER", 10, UiStyle.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	for st in Permits.STANCES:
		var b := _toggle(STANCE_TEXT[st][0], STANCE_TEXT[st][1])
		b.pressed.connect(func(): _send(st, int(sim.permits.guidance(hub, hub_id).grant)))
		row.add_child(b)
		_stances[st] = b
	add_child(UiStyle.label("PRE-APPROVE PERMITS WITHIN", 10, UiStyle.MUTED))
	var grants := HBoxContainer.new()
	grants.add_theme_constant_override("separation", 4)
	add_child(grants)
	for m in Permits.GRANTS:
		var b := _toggle("None" if m == 0 else "%d m" % m,
			"They ask about everything" if m == 0 else "Requests within %d m of them go straight through" % m)
		b.pressed.connect(func(): _send(str(sim.permits.guidance(hub, hub_id).stance), m))
		grants.add_child(b)
		_grants[m] = b
	_said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_said.custom_minimum_size.x = 230
	add_child(_said)
	sim.permits.changed.connect(_sync)
	_sync()


func _send(stance: String, grant: int) -> void:
	sim.apply({"type": "guide", "hub": hub, "hub_id": hub_id, "stance": stance, "grant": grant})
	_sync()


func _sync() -> void:
	if sim == null or _stances.is_empty():
		return
	var g := sim.permits.guidance(hub, hub_id)
	for st in _stances:
		_stances[st].set_pressed_no_signal(st == g.stance)
	for m in _grants:
		_grants[m].set_pressed_no_signal(m == int(g.grant))
	_said.text = "" if int(g.set) < 0 else "You told them on day %d." % (int(g.set) / (24 * CitySim.TICKS_PER_HOUR) + 1)


func _toggle(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	return b
