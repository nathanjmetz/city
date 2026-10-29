class_name LawnMap
extends Node
## Paints every built lot's own lawn (LawnLook) into the textures the
## ground shader reads (TerrainView: lawn_pages, lawn_a, lawn_b), so each
## yard is its own green: deep, tired, weedy, striped, worn or shaded.
## Desktop only (the browser keeps one even lawn, at no cost).
##
## The town is cut into 256 m tiles (the tree field's chunks), each a
## 128 x 128 texel picture (2 m a texel) in two texture arrays, with a small
## page table saying which layer holds which tile; tiles with no lots get
## no layer. A lot's lawn is repainted only when the lot, its building or its
## upkeep tier changes, a tile or two a frame, and the yard trees' shade
## once a game year as they grow. About 170 KB of video memory a tile
## (with mipmaps): the big test town (1.7 km across) needs about 50.

## Tiles across the page table, centred on the town's middle: 16 km.
const PAGES := 64
## The most tiles a town can paint (one byte a page): 16 km2 of yards.
const MAX_LAYERS := 255
## Milliseconds a frame for scanning lots and painting tiles.
const BUDGET_MS := 1.5
## Lots looked over per budget check while scanning.
const SCAN_STEP := 64

var sim: CitySim
var _pages := Image.create(PAGES, PAGES, false, Image.FORMAT_R8)
var _pages_tex: ImageTexture
var _arr_a: Texture2DArray
var _arr_b: Texture2DArray
var _cap := 0
## Vector2i tile -> [layer, Image a, Image b] (images with mipmaps)
var _tiles := {}
var _blank := []  # [Image a, Image b]: an empty layer
## lot key -> [lot, look, tiles, marks, tier, zone]
var _lots := {}
## Vector2i tile -> {lot key: true}
var _tile_lots := {}
## Tiles to repaint.
var _dirty := {}
## A scan of the lots under way: [keys, next index, seen keys], or empty.
var _scan := []
var _rescan := true
## The lots were re-platted: every lot's shape is looked at again.
var _replat := false
var _tree_version := -1
var _tree_year := -1
var _tree_records := {}  # Vector2i tile -> the tree field's record array it was painted with
var _first := true


## The towns whose lawns a lawn map paints (BuildingView then leaves out
## the builders' flat weed patches): CitySim -> its map.
static var _painting := {}


static func paints(s: CitySim) -> bool:
	return s != null and _painting.has(s) and is_instance_valid(_painting[s])


## Whether this machine draws per-lot lawns: the desktop app (Forward+),
## where the ground shader has DESKTOP_DETAIL.
static func wanted() -> bool:
	return PhotoGround.drawable()


func setup(s: CitySim) -> void:
	sim = s
	_painting[s] = self
	_pages.fill(Color(0, 0, 0))
	_pages_tex = ImageTexture.create_from_image(_pages)
	_blank = [_tile_image(LawnLook.NEUTRAL_A), _tile_image(LawnLook.NEUTRAL_B)]
	for img in _blank:
		img.generate_mipmaps()
	sim.buildings_changed.connect(_mark)
	sim.lots_changed.connect(func(): _replat = true; _mark())
	var mat := TerrainView.ground_material()
	mat.set_shader_parameter("lawn_pages", _pages_tex)


func _exit_tree() -> void:
	if sim != null and _painting.get(sim) == self:
		_painting.erase(sim)


func _mark() -> void:
	_rescan = true


## True once every lot's lawn is painted (the loading screen waits).
func is_drawn() -> bool:
	return not _first and not _rescan and _scan.is_empty() and _dirty.is_empty()


func _process(_delta: float) -> void:
	if sim == null:
		return
	var start := Time.get_ticks_usec()
	var budget := LoadGate.ms(BUDGET_MS) * 1000.0
	if _first:
		budget = INF  # the town's lawns come in whole with the rest
	if _scan.is_empty() and _rescan:
		_rescan = false
		var keys := sim.buildings.keys()
		keys.sort()
		_scan = [keys, 0, {}]
	while not _scan.is_empty() and Time.get_ticks_usec() - start < budget:
		_scan_some()
	if _scan.is_empty():
		_check_trees()
	var painted := false
	# Room for every tile about to be painted at once, not doubled tile by tile.
	var need := _tiles.size()
	for c in _dirty:
		need += 0 if _tiles.has(c) else 1
	if need > _cap and _cap < MAX_LAYERS:
		_grow(need)
	while not _dirty.is_empty() and Time.get_ticks_usec() - start < budget:
		var keys := _dirty.keys()
		keys.sort()
		_dirty.erase(keys[0])
		_paint(keys[0])
		painted = true
	if painted:
		_pages_tex.update(_pages)
	if _scan.is_empty() and not _rescan:
		_first = false


## Looks over the next few lots: a new, changed or re-tiered lot marks its
## tiles to repaint; at the end, lots gone since the last scan do too.
func _scan_some() -> void:
	var keys: Array = _scan[0]
	var i: int = _scan[1]
	var seen: Dictionary = _scan[2]
	var stop := mini(i + SCAN_STEP, keys.size())
	for k in range(i, stop):
		var key: String = keys[k]
		var lot = sim.lots.get(key)
		if lot == null:
			continue
		seen[key] = true
		var tier := sim.care.tier_of(key)
		var zone := int(sim.buildings[key].get("zone", ZoneMap.Zone.RESIDENTIAL))
		var had: Array = _lots.get(key, [])
		if not had.is_empty() and is_same(had[0], lot) and had[4] == tier and had[5] == zone and not _replat:
			continue
		if not had.is_empty() and not _replat_changed(had[0], lot) and had[4] == tier and had[5] == zone:
			had[0] = lot
			continue
		_set_lot(key, lot, tier, zone)
	_scan[1] = stop
	if stop >= keys.size():
		for key in _lots.keys():
			if not seen.has(key):
				_drop_lot(key)
		_scan = []
		_replat = false


## Whether a lot's shape moved (a re-plat can hand back an equal copy).
static func _replat_changed(a: Dictionary, b: Dictionary) -> bool:
	return a.get("corners") != b.get("corners") or a.get("front") != b.get("front") or a.get("normal") != b.get("normal")


func _set_lot(key: String, lot: Dictionary, tier: int, zone: int) -> void:
	_drop_lot(key)
	var look := LawnLook.of(sim.city_seed, key, tier, zone == ZoneMap.Zone.RESIDENTIAL)
	var marks := LawnLook.wear_marks(lot, look)
	var tiles := _tiles_of(lot)
	_lots[key] = [lot, look, tiles, marks, tier, zone]
	for c in tiles:
		if not _tile_lots.has(c):
			_tile_lots[c] = {}
		_tile_lots[c][key] = true
		_dirty[c] = true


func _drop_lot(key: String) -> void:
	if not _lots.has(key):
		return
	for c in _lots[key][2]:
		if _tile_lots.has(c):
			_tile_lots[c].erase(key)
		_dirty[c] = true
	_lots.erase(key)


## The tiles a lot's shape touches (a texel's width of margin).
static func _tiles_of(lot: Dictionary) -> Array:
	var poly: PackedVector2Array = lot.get("corners", PackedVector2Array())
	if poly.is_empty():
		return []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in poly:
		lo = lo.min(q)
		hi = hi.max(q)
	var m := LawnLook.TEXEL
	var out := []
	for x in range(floori((lo.x - m) / LawnLook.TILE), floori((hi.x + m) / LawnLook.TILE) + 1):
		for z in range(floori((lo.y - m) / LawnLook.TILE), floori((hi.y + m) / LawnLook.TILE) + 1):
			var c := Vector2i(x, z)
			if absi(c.x) < PAGES / 2 and absi(c.y) < PAGES / 2:
				out.append(c)
	return out


## The yard trees' shade: repainted where a tree field's chunk changed, and
## everywhere once a game year as the trees grow.
func _check_trees() -> void:
	var year := TreeField.now_tick / maxi(TreeField.REGROW_TICKS * 12, 1)
	if TreeField.version == _tree_version and year == _tree_year:
		return
	var all := year != _tree_year
	_tree_version = TreeField.version
	_tree_year = year
	for c in _tiles:
		var recs := _tree_arrays(c)
		var was: Array = _tree_records.get(c, [])
		var same := recs.size() == was.size()
		for i in recs.size():
			same = same and is_same(recs[i], was[i])
		if not same or (all and not recs.is_empty()):
			_dirty[c] = true


## The town's own tree fields (not the wild woods, not a neighbor's town).
static func _fields() -> Array:
	var out := []
	for f in TreeField.fields:
		if is_instance_valid(f) and f.is_inside_tree() and not f.fades \
				and f.global_transform.origin.length() < 1.0:
			out.append(f)
	return out


func _tree_arrays(c: Vector2i) -> Array:
	var out := []
	for f in _fields():
		out.append(f.chunk_trees(c))
	return out


func _paint(c: Vector2i) -> void:
	var lots: Dictionary = _tile_lots.get(c, {})
	if lots.is_empty():
		_free_tile(c)
		return
	var origin := Vector2(c) * LawnLook.TILE
	var a := _tile_image(LawnLook.NEUTRAL_A)
	var b := _tile_image(LawnLook.NEUTRAL_B)
	var keys := lots.keys()
	keys.sort()
	for key in keys:
		LawnLook.fill(a, b, origin, _lots[key][0], _lots[key][1])
	var bytes := a.get_data()
	for key in keys:
		LawnLook.add_wear(bytes, origin, _lots[key][3])
	a.set_data(LawnLook.TILE_PX, LawnLook.TILE_PX, false, Image.FORMAT_RGBA8, bytes)
	bytes = b.get_data()
	var recs := []
	for f in _fields():
		var trees: Array = f.chunk_trees(c)
		recs.append(trees)
		for i in trees.size():
			var t: Array = f.chunk_record(c, i)
			if t.is_empty() or not t[5]:
				continue
			var xf: Transform3D = t[0]
			var r: float = TreeField.SPREAD.get(t[1], 5.0) * xf.basis.get_scale().y
			# Saplings shade too little to thin the grass; a grown maple's
			# crown, 10 to 15 m across, does.
			var k := clampf((r - 2.5) / 4.0, 0.0, 0.85)
			if k > 0.0:
				LawnLook.add_shade(bytes, origin, Vector2(xf.origin.x, xf.origin.z), r * 0.9, k)
	_tree_records[c] = recs
	b.set_data(LawnLook.TILE_PX, LawnLook.TILE_PX, false, Image.FORMAT_RGBA8, bytes)
	a.generate_mipmaps()
	b.generate_mipmaps()
	var layer: int = _tiles[c][0] if _tiles.has(c) else _free_layer()
	if layer < 0:
		return  # the town outgrew the arrays: these yards keep the even lawn
	_tiles[c] = [layer, a, b]
	if layer >= _cap:
		_grow(layer + 1)
	else:
		_arr_a.update_layer(a, layer)
		_arr_b.update_layer(b, layer)
	_pages.set_pixel(c.x + PAGES / 2, c.y + PAGES / 2, Color8(layer + 1, 0, 0))


func _free_tile(c: Vector2i) -> void:
	if not _tiles.has(c):
		return
	var layer: int = _tiles[c][0]
	_tiles.erase(c)
	_tree_records.erase(c)
	_pages.set_pixel(c.x + PAGES / 2, c.y + PAGES / 2, Color(0, 0, 0))
	if layer < _cap:
		_arr_a.update_layer(_blank[0], layer)
		_arr_b.update_layer(_blank[1], layer)


func _free_layer() -> int:
	var used := {}
	for c in _tiles:
		used[_tiles[c][0]] = true
	for i in MAX_LAYERS:
		if not used.has(i):
			return i
	return -1


## Makes the arrays room for at least `need` layers (doubling), with every
## painted tile copied in.
func _grow(need: int) -> void:
	var cap := maxi(_cap, 16)
	while cap < need:
		cap *= 2
	cap = mini(cap, MAX_LAYERS)
	var la := []
	var lb := []
	for i in cap:
		la.append(_blank[0])
		lb.append(_blank[1])
	for c in _tiles:
		la[_tiles[c][0]] = _tiles[c][1]
		lb[_tiles[c][0]] = _tiles[c][2]
	_arr_a = Texture2DArray.new()
	_arr_a.create_from_images(la)
	_arr_b = Texture2DArray.new()
	_arr_b.create_from_images(lb)
	_cap = cap
	var mat := TerrainView.ground_material()
	mat.set_shader_parameter("lawn_a", _arr_a)
	mat.set_shader_parameter("lawn_b", _arr_b)
	mat.set_shader_parameter("lawn_on", 1.0)


static func _tile_image(fill: Color) -> Image:
	var img := Image.create(LawnLook.TILE_PX, LawnLook.TILE_PX, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	return img


## Tiles painted (for tests and the perf log).
func tile_count() -> int:
	return _tiles.size()


## A painted texel's two colours at x/z (tests): [a, b], or [] off the map.
func texel(p: Vector2) -> Array:
	var c := Vector2i(floori(p.x / LawnLook.TILE), floori(p.y / LawnLook.TILE))
	if not _tiles.has(c):
		return []
	var q := (p - Vector2(c) * LawnLook.TILE) / LawnLook.TEXEL
	var i := clampi(int(q.x), 0, LawnLook.TILE_PX - 1)
	var j := clampi(int(q.y), 0, LawnLook.TILE_PX - 1)
	return [(_tiles[c][1] as Image).get_pixel(i, j), (_tiles[c][2] as Image).get_pixel(i, j)]
