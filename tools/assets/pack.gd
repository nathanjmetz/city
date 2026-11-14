extends SceneTree
## Packs each asset of the free asset library (AssetLib) into its own small
## .pck for the desktop apps. The game's own update pack leaves the art out,
## and an app downloads an asset's pack once, and again only when that asset
## changes (GameUpdater, tools/assets/release.py, .github/workflows/desktop.yml).
## Run (after fetch.py and an import):
##   godot --headless -s tools/assets/pack.gd -- OUT_DIR <macos|windows> [id ...]
## Writes OUT_DIR/<id>.pck; fails when an asset's import is missing.
## Windows packs keep only the S3TC copies of textures (what its GPUs read);
## Mac packs keep S3TC and ETC2/ASTC, like the Mac app (universal) itself.

var _platform := "macos"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	_platform = args[1] if args.size() > 1 else "macos"
	var ids := args.slice(2)
	DirAccess.make_dir_recursive_absolute(out)
	var failed := false
	for kind in AssetLib.KINDS:
		for id in AssetLib.index()[kind]:
			if not ids.is_empty() and not id in ids:
				continue
			var i: Dictionary = AssetLib.index()[kind][id]
			var files := {}
			var bad := []
			if kind == "hdris":
				_add_imported(str(i.path), files, bad)
			else:
				_walk(str(i.get("dir", str(i.get("path", "")).get_base_dir())), files, bad)
			if not bad.is_empty() or files.is_empty():
				push_error("%s not imported: %s" % [id, ", ".join(bad)])
				failed = true
				continue
			var pk := PCKPacker.new()
			pk.pck_start(out.path_join(id + ".pck"))
			var keys := files.keys()
			keys.sort()
			for k in keys:
				pk.add_file(k, files[k])
			pk.flush()
			print("packed %s (%d files)" % [id, keys.size()])
	quit(1 if failed else 0)


func _walk(dir: String, files: Dictionary, bad: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".import"):
			_add_imported(dir.path_join(f.trim_suffix(".import")), files, bad)
	for d in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(d), files, bad)


## An imported file ships as its .import (where the game finds it) plus the
## converted copies under .godot/imported, as Godot's own export does.
func _add_imported(src: String, files: Dictionary, bad: Array) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(src + ".import") != OK:
		bad.append(src)
		return
	files[src + ".import"] = ProjectSettings.globalize_path(src + ".import")
	for dest in cfg.get_value("deps", "dest_files", []):
		if _platform == "windows" and (dest.ends_with(".etc2.ctex") or dest.ends_with(".astc.ctex")):
			continue
		if not FileAccess.file_exists(dest):
			bad.append(dest)
			continue
		files[dest] = ProjectSettings.globalize_path(dest)
