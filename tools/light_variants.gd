extends "res://tools/look_shot.gd"
## One town, several lighting settings: loads once, then for each variant
## sets Environment / sun properties, waits and saves OUT_k.png. For tuning
## SkyLight against photos without reloading the game each time.
## LIGHT_VARIANTS is JSON: [{"name": "a", "env": {"tonemap_exposure": 1.1}, "sun": {"light_energy": 1.8}}, ...]
## Run: xvfb-run godot --rendering-driver vulkan -s tools/light_variants.gd -- out_prefix yaw pitch dist --quality=ultra

const WAIT := 14


func _process(delta: float) -> bool:
	var start := 60
	if _frames < start:
		var save := OS.get_environment("SHOT_FRAMES")
		OS.set_environment("SHOT_FRAMES", "100000")
		var r := super(delta)
		OS.set_environment("SHOT_FRAMES", save)
		return r
	_frames += 1
	var vs: Array = JSON.parse_string(OS.get_environment("LIGHT_VARIANTS"))
	var k := (_frames - start) / WAIT
	var step := (_frames - start) % WAIT
	if k >= vs.size():
		quit()
		return false
	var sky: SkyLight = _main.find_children("*", "SkyLight", true, false)[0]
	var v: Dictionary = vs[k]
	if step == 1:
		if not has_meta("base"):
			var base := {}
			for key in ["env", "sun", "sky"]:
				base[key] = {}
			set_meta("base", base)
		var base: Dictionary = get_meta("base")
		# Back to the base look, then this variant on top.
		for key in ["env", "sun", "sky"]:
			var obj: Object = sky.env if key == "env" else (sky.sun if key == "sun" else sky)
			for p in base[key]:
				obj.set(p, base[key][p])
			for p in v.get(key, {}):
				if not base[key].has(p):
					base[key][p] = obj.get(p)
				obj.set(p, v[key][p])
	if step == WAIT - 1:
		var out := OS.get_cmdline_user_args()[0] + "_" + str(v.get("name", k)) + ".png"
		root.get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
	return false
