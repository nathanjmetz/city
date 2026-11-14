extends SceneTree
## Run: godot --headless -s tests/test_asset_lib.gd
## The free asset library (AssetLib, tools/assets/): every listed asset is
## CC0 or CC-BY 4.0 and credited, and the library hands out working models,
## kit parts, surfaces and skies when its files are fetched (they aren't in
## git: python3 tools/assets/fetch.py). Without the files every call must
## return null so callers fall back to their code-built versions.

const ALLOWED := ["CC0-1.0", "CC-BY-4.0"]

var _failed := false


func _initialize() -> void:
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://tools/assets/catalog.json"))
	_check(typeof(catalog) == TYPE_DICTIONARY, "catalog.json parses")
	var credits := FileAccess.get_file_as_string("res://art/assets/CREDITS.md")
	var idx := AssetLib.index()
	for kind in AssetLib.KINDS:
		for id in catalog.get(kind, {}):
			_check(idx[kind].has(id), "%s is in index.json (run tools/assets/fetch.py)" % id)
		for id in idx[kind]:
			var i: Dictionary = idx[kind][id]
			_check(str(i.get("licence", "")) in ALLOWED, "%s is free for any use (%s)" % [id, i.get("licence", "")])
			_check(credits.contains("`%s`" % id), "%s is credited in CREDITS.md" % id)
			_check(str(i.get("real", "")) != "", "%s names the real thing it matches" % id)
			_check(str(i.get("loop", "")) != "", "%s has an owning loop" % id)
	if AssetLib.has("fire_hydrant"):
		var whole := AssetLib.mesh("fire_hydrant")
		var clean := AssetLib.mesh("fire_hydrant", ["fire_hydrant*"], ["*aged"])
		_check(whole != null and clean != null, "hydrant meshes load")
		if whole and clean:
			_check(clean.get_aabb().size.x < whole.get_aabb().size.x * 0.7, "picking the clean hydrant leaves the worn one out")
			_check(absf(clean.get_aabb().position.y) < 0.02, "a picked part stands on the ground")
			_check(clean.get_aabb().size.y > 0.6 and clean.get_aabb().size.y < 1.0, "the hydrant is a real 0.6-1.0 m tall")
		_check(AssetLib.mesh("fire_hydrant") == whole, "meshes are shared, not rebuilt")
		var n := AssetLib.instance("fire_hydrant")
		_check(n != null, "a model instances")
		if n:
			n.free()
	else:
		print("asset files not fetched: checking the fallbacks only")
		_check(AssetLib.mesh("fire_hydrant") == null and AssetLib.instance("fire_hydrant") == null,
			"a missing model gives null")
	if AssetLib.has("red_brick"):
		var m := AssetLib.material("red_brick")
		_check(m != null and m.albedo_texture != null and m.normal_texture != null and m.orm_texture != null,
			"a surface has colour, normal and AO/rough/metal maps")
		if m:
			_check(m.uv1_scale.x > 0.1 and m.uv1_scale.x < 2.0, "bricks tile at their real size")
	_check(AssetLib.material("not_an_asset") == null and AssetLib.mesh("not_an_asset") == null, "unknown ids give null")
	if AssetLib.has("kloofendal_overcast_puresky"):
		_check(AssetLib.sky("kloofendal_overcast_puresky") != null, "a sky loads")
	print("FAILED" if _failed else "PASSED")
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)
