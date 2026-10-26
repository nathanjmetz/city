extends SceneTree
## A contact sheet of the game's icons at their real sizes (16, 20 and
## 28 px) on the two panel colours they sit on: the bottom bar's panel and
## the raised tool card. Run it with a window, not --headless:
##   Godot --resolution 1600x1000 -s tools/icon_sheet.gd -- out.png [services|bar|all]
## "services" is the building icons in the drawers, "bar" the top bar,
## category bar and stat icons; "all" (the default) is both.

const SERVICES := ["power_line", "substation", "power_co", "well", "water_tower", "water_utility",
	"landfill", "recycling", "phone_co", "builder_yard",
	"daycare", "elementary", "high_school", "college", "university",
	"clinic", "hospital", "nursing_home", "cemetery",
	"fire_station", "police_station", "post_office", "bank_co", "farm_credit",
	"bus_depot", "taxi_company", "rail_depot",
	"parking_small", "parking_large", "parking_downtown", "park_and_ride", "parking_garage",
	"farm_corn", "farm_soy", "oil_co", "mine_co", "forestry_co", "warehouse_co",
	"ethanol", "meatpacker", "furniture", "rv_plant"]
const BAR := ["roads", "zones", "industry", "power", "police", "school", "health", "bus", "parks",
	"bulldoze", "move", "budget", "homes", "shops", "people", "jobs", "car", "money", "views",
	"locate", "town", "seasons", "daynight", "help", "search", "permits", "advice", "warning",
	"fire", "water", "taxi", "parking", "park", "traffic", "courthouse", "football", "fairgrounds",
	"elevator", "water_landmark", "trailhead"]

var _f := 0
var _grid: GridContainer


func _initialize() -> void:
	var which: String = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else "all"
	var kinds: Array = SERVICES if which == "services" else (BAR if which == "bar" else SERVICES + BAR)
	var bg := ColorRect.new()
	bg.color = Brand.SURFACE
	bg.size = Vector2(1600, 1000)
	root.add_child(bg)
	var grid := GridContainer.new()
	_grid = grid
	grid.columns = 4
	grid.position = Vector2(10, 10)
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	bg.add_child(grid)
	for k in kinds:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		for panel in [Brand.SURFACE_PANEL, Brand.SURFACE_RAISED]:
			var tile := PanelContainer.new()
			var box := StyleBoxFlat.new()
			box.bg_color = Color(panel, 1.0)
			box.set_content_margin_all(4)
			tile.add_theme_stylebox_override("panel", box)
			var inner := HBoxContainer.new()
			inner.add_theme_constant_override("separation", 6)
			tile.add_child(inner)
			for px in [16, 20, 28]:
				var ic := Icon.new(k, px)
				ic.color = Brand.INK
				ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				inner.add_child(ic)
			row.add_child(tile)
		var l := Label.new()
		l.text = "  " + k
		l.custom_minimum_size.x = 130
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Brand.INK_MUTED)
		row.add_child(l)
		grid.add_child(row)


func _process(_d: float) -> bool:
	_f += 1
	if _f == 10:
		var out: String = OS.get_cmdline_user_args()[0]
		var img := root.get_texture().get_image()
		img.save_png(out)
		# The same pixels blown up 3x (no smoothing), half the sheet at a
		# time, to judge each icon's real pixels.
		var used := 60 + _grid.size.y
		for half in 2:
			var part := img.get_region(Rect2i(half * 655, 0, 655, mini(int(used), img.get_height())))
			part.resize(part.get_width() * 3, part.get_height() * 3, Image.INTERPOLATE_NEAREST)
			part.save_png(out.get_basename() + "_x3_%d.png" % half)
		quit()
	return false
