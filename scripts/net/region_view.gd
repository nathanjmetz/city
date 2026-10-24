class_name RegionView
extends Node3D
## Shows the shared region around your city: every neighbor's city, live,
## with a name tag over it, the city lines between cities, and where each
## player online is pointing.
##
## Your city sits at the world's centre and the neighbors are placed around
## it at their spots on the shared map, so your tools work unchanged.

## How often your pointer position is sent, per second.
const CURSOR_RATE := 5.0

## A county highway drawn on toward another town stops this far from its
## centre (metres) if it hasn't already met that town's land.
const TOWN_CLEAR := 1500.0

var client: RegionClient
var cam: CityCamera
var road_tool: RoadTool
## The land (neighbors' roads are graded into it too) and your own town's
## county highways out to the horizon, set before this joins the tree.
var terrain: TerrainView
var exits: ExitRoads

var _cities := {}   # city id -> {"root": Node3D, "tag": Label3D}
var _cursors := {}  # player id -> Node3D
var _send_time := 0.0
var _last_sent := Vector2.INF


func setup(c: RegionClient, camera: CityCamera, rt: RoadTool) -> void:
	client = c
	cam = camera
	road_tool = rt


func _ready() -> void:
	for id in client.region.cities:
		_add_city(id)
	client.city_added.connect(func(id: String):
		_add_city(id)
		# A new town may stand where a county highway was drawn on before.
		for other in _cities:
			if _cities[other].exits != null:
				_cities[other].exits.refresh()
		if exits != null:
			exits.refresh())
	if exits != null:
		exits.stop = _stop_for(client.my_city)
		exits.refresh()
	var lines := CityLines.new()
	lines.setup(client, func(p: Vector2): return _to_world(p))
	add_child(lines)
	client.cursor_moved.connect(_move_cursor)
	client.players_changed.connect(_drop_gone_cursors)


func _process(delta: float) -> void:
	for id in _cities:
		var c: Dictionary = client.region.cities[id]
		var tag: Label3D = _cities[id].tag
		var online := _is_online(c.owner)
		tag.text = "%s\n%s  ·  %s people%s" % [c.name, c.player,
			CitySim.money_text(c.sim.stats.population), "" if online else "  ·  away"]
		tag.modulate.a = 1.0 if online else 0.6
	_send_time += delta
	if _send_time >= 1.0 / CURSOR_RATE:
		_send_time = 0.0
		var hit = cam.mouse_ground_point()
		if hit != null:
			var p := _to_region(hit)
			if p.distance_to(_last_sent) > 0.5:
				_last_sent = p
				client.send_cursor(p)


## Region coordinates to this world (your city at the centre), and back.
func _to_world(p: Vector2) -> Vector3:
	var o: Vector2 = client.region.cities[client.my_city].origin
	return Vector3(p.x - o.x, 0.0, p.y - o.y)


func _to_region(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z) + client.region.cities[client.my_city].origin


## The centre of a city in this world.
func city_position(id: String) -> Vector3:
	return _to_world(client.region.cities[id].origin) if client.region.cities.has(id) else Vector3.ZERO


func _add_city(id: String) -> void:
	if _cities.has(id):
		return
	var c: Dictionary = client.region.cities[id]
	var root := Node3D.new()
	root.position = _to_world(c.origin)
	add_child(root)
	var their_exits: ExitRoads = null
	if id != client.my_city:
		var roads := RoadView.new()
		# Their whole town lands at once: its streets drawn a few a frame.
		roads.sliced = true
		root.add_child(roads)
		roads.setup(c.sim.network, c.sim)
		var at := Vector2(root.position.x, root.position.z)
		if terrain != null:
			# Their roads sit on graded, mowed land, like yours: graded before
			# their lots and drives are laid on it.
			terrain.add_network("city " + id, c.sim.network, at)
		var buildings := BuildingView.new()
		# Their whole town lands at once: drawn a few buildings a frame.
		buildings.sliced = true
		root.add_child(buildings)
		buildings.setup(c.sim)
		if terrain != null:
			terrain.graded.connect(func(box: Rect2) -> void:
				if is_instance_valid(buildings):
					buildings.regraded(Rect2(box.position - at, box.size)))
		var cars := TrafficView.new()
		# Their cars as their computer last sent them.
		cars.setup(c.sim.traffic, func(): return 0.0)
		root.add_child(cars)
		if terrain != null:
			their_exits = ExitRoads.new()
			root.add_child(their_exits)
			their_exits.setup(c.sim, terrain, "exits " + id, _stop_for(id))
	# Name tags over the neighbors' cities (not your own).
	var tag := _label(client.region.color_of(id, client.my_city), 34)
	tag.position = Vector3(0, 70, 0)
	tag.visible = id != client.my_city
	root.add_child(tag)
	_cities[id] = {"root": root, "tag": tag, "exits": their_exits}


## Where a town's county highways must stop on their way to the horizon:
## at a link shared with a neighbor (their road carries on from there), and
## short of any other town. Takes points in that town's own coordinates.
func _stop_for(id: String) -> Callable:
	return func(p: Vector2) -> bool:
		var region := client.region
		if not region.cities.has(id):
			return false
		for j in region.joins:
			for side in [["a", "a_at"], ["b", "b_at"]]:
				if j.get(side[0]) == id and Vector2(j[side[1]][0], j[side[1]][1]).distance_to(p) < 30.0:
					return true
		var r: Vector2 = p + region.cities[id].origin
		var cell := Vector2i((r / Balance.LAND_CELL).floor())
		for other in region.cities:
			if other == id:
				continue
			if r.distance_to(region.cities[other].origin) < TOWN_CLEAR:
				return true
			if region.land.has(other) and region.land[other].has(cell):
				return true
		return false


func _move_cursor(player_id: String, p: Vector2) -> void:
	if not _cursors.has(player_id):
		var color := Brand.INK
		for id in client.region.cities:
			if client.region.cities[id].owner == player_id:
				color = client.region.color_of(id, client.my_city)
		var node := Node3D.new()
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = 3.0
		mesh.outer_radius = 4.2
		ring.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = mat
		node.add_child(ring)
		var tag := _label(color, 28)
		tag.text = client.name_of(player_id)
		tag.position = Vector3(0, 8, 0)
		node.add_child(tag)
		add_child(node)
		_cursors[player_id] = node
	var target := Terrain.lift(_to_world(p)) + Vector3(0, 0.6, 0)
	var node: Node3D = _cursors[player_id]
	var tw := create_tween()
	tw.tween_property(node, "position", target, 1.0 / CURSOR_RATE)


func _drop_gone_cursors() -> void:
	for id in _cursors.keys():
		if not _is_online(id):
			_cursors[id].queue_free()
			_cursors.erase(id)


func _is_online(player_id: String) -> bool:
	for p in client.players:
		if p.id == player_id:
			return true
	return false


static func _label(color: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.font = Brand.sign()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0006
	l.font_size = size
	l.outline_size = 10
	l.modulate = color
	l.outline_modulate = Color(Brand.BRAND_INK, 0.85)
	l.no_depth_test = true
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
