extends SceneTree
## Dumps the old FastNoiseLite textures for tools/bake_noise.py: each one as
## Godot made it seamless (ref_, for its histogram) and plain at twice the
## size (raw_, for its true spectrum). Run: godot --headless -s tools/noise_refs.gd
const COMBOS := [[512, 0.012, 4, 11], [256, 0.09, 2, 23], [256, 0.02, 3, 41], [256, 0.05, 3, 53], [512, 0.012, 4, 41], [256, 0.09, 2, 57], [512, 0.012, 4, 71], [256, 0.09, 2, 83]]
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/noise_refs")
	for c in COMBOS:
		# Built here, not by Ground.noise, which now loads the baked ones.
		var fn := FastNoiseLite.new()
		fn.seed = c[3]
		fn.frequency = c[1]
		fn.fractal_octaves = c[2]
		var t := NoiseTexture2D.new()
		t.noise = fn
		t.seamless = true
		t.width = c[0]
		t.height = c[0]
		await t.changed
		t.get_image().save_png("/tmp/noise_refs/ref_%d_%s_%d_%d.png" % [c[0], str(c[1]), c[2], c[3]])
		# The same noise without the seamless blend, for its true spectrum.
		var n := FastNoiseLite.new()
		n.seed = c[3]
		n.frequency = c[1]
		n.fractal_octaves = c[2]
		n.get_image(c[0] * 2, c[0] * 2, false, false, true).save_png("/tmp/noise_refs/raw_%d_%s_%d_%d.png" % [c[0], str(c[1]), c[2], c[3]])
	quit()
