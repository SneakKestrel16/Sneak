extends RefCounted
## Loads the models made in Blender (tools/blender, exported to assets/models)
## and dresses them in generated textures: noise run through a colour ramp,
## plus a matching bump map. Also the shared material helpers the house uses.
##
## Models are purely visual: each one fits inside its kind's collision box
## (KINDS in game.gd), centred on the origin, with its front facing +Z.

const BRASS := Color(0.78, 0.6, 0.25)
## Metallic level for gold and brass. Full metal needs reflections the dark house
## does not have (no sky, no probes) and renders near-black, as the first showcase showed.
const METAL := 0.45

const MODELS := "res://assets/models/"
## How a material name prefix (Blender's name up to the first "_") is dressed:
## grain, contrast and noise frequency for `textured`. Roughness and metal come
## from the material itself; "glow", "glass", "plain" and "canvas" are special.
const PRESETS := {
	"wood": [Vector2(1, 6), 0.4, 0.05],
	"lacquer": [Vector2(1, 4), 0.3, 0.03],
	"metal": [Vector2.ONE, 0.2, 0.02],
	"glaze": [Vector2(2, 1), 0.3, 0.03],
	"fabric": [Vector2.ONE, 0.25, 0.3],
	"leather": [Vector2.ONE, 0.3, 0.12],
	"stone": [Vector2.ONE, 0.3, 0.08],
	"marble": [Vector2(1, 3), 0.25, 0.03],
	"paper": [Vector2(8, 1), 0.08, 0.1],
	"flesh": [Vector2(2, 3), 0.45, 0.07],
	"bone": [Vector2.ONE, 0.3, 0.05],
	"plastic": [Vector2.ONE, 0.08, 0.05],
}

static var _materials := {}  ## Cache: every vase shares one ceramic material, and so on.


## The model for a loot kind, by its name in KINDS ("grandfather clock" is
## loot/grandfather_clock.glb). Surfaces made to vary (vase glaze, book cover,
## vial liquid...) take color. Textures repeat at about the item's own size.
static func loot(kind: String, size: Vector3, color: Color) -> Node3D:
	var tile := clampf(maxf(size.x, maxf(size.y, size.z)) * 0.8, 0.15, 1.0)
	return model("loot/" + kind.replace(" ", "_"), tile, color)


## A material whose colour varies with noise around base. grain stretches the
## texture (e.g. Vector2(1, 8) for wood running vertically). With tile > 0 the
## texture is projected in world space and repeats every tile metres, so a
## floor looks the same in a small room as in a hall. Shared by key.
static func textured(
	base: Color,
	grain := Vector2.ONE,
	contrast := 0.3,
	roughness := 0.8,
	metallic := 0.0,
	frequency := 0.02,
	tile := 0.0,
	world := true,
) -> StandardMaterial3D:
	var key := [base, grain, contrast, roughness, metallic, frequency, tile, world]
	if _materials.has(key):
		return _materials[key]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, base.darkened(contrast))
	ramp.set_color(1, base.lightened(contrast * 0.5))
	var albedo := NoiseTexture2D.new()
	albedo.noise = noise
	albedo.color_ramp = ramp
	albedo.seamless = true
	var bump := NoiseTexture2D.new()
	bump.noise = noise
	bump.seamless = true
	bump.as_normal_map = true
	bump.bump_strength = 4.0

	var material := StandardMaterial3D.new()
	material.albedo_texture = albedo
	material.normal_enabled = true
	material.normal_texture = bump
	material.normal_scale = 0.4
	material.roughness = roughness
	material.metallic = metallic
	material.uv1_scale = Vector3(grain.x, grain.y, 1.0)
	if tile > 0.0 and world:
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_scale = Vector3(grain.x, 1.0, grain.y) / tile
	elif tile > 0.0:  # Projected in the model's own space, so it moves with it.
		material.uv1_triplanar = true
		material.uv1_scale = Vector3(grain.y, grain.x, grain.y) / tile
	_materials[key] = material
	return material


## A model from assets/models (e.g. "monsters/stalker"), dressed by `dress`.
## Origin and facing are as tools/blender made them: front toward +Z.
static func model(path: String, tile := 0.5, tint := Color.TRANSPARENT) -> Node3D:
	var scene := load(MODELS + path + ".glb") as PackedScene
	var root := scene.instantiate() as Node3D
	dress(root, tile, tint)
	return root


## Replaces every imported surface material under node by a generated one,
## chosen by the material's name (see PRESETS) and keeping its colour,
## roughness and metal. Textures repeat every tile metres in the model's own
## space, so they need no UVs. Surfaces named "tint_..." take tint instead of
## their own colour, when tint is not transparent.
static func dress(node: Node, tile := 0.5, tint := Color.TRANSPARENT) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		for i in instance.mesh.get_surface_count():
			var source := instance.mesh.surface_get_material(i) as BaseMaterial3D
			if source:
				instance.set_surface_override_material(i, _dressed(source, tile, tint))


static func _dressed(source: BaseMaterial3D, tile: float, tint: Color) -> Material:
	var words := source.resource_name.split("_")
	var color := source.albedo_color
	if words[0] == "tint" and words.size() > 1:
		words.remove_at(0)
		if tint.a > 0.0:
			color = tint
	var preset := words[0]
	match preset:
		"glow":
			return _glow(color, 2.5)
		"glass":
			return _glass(color)
		"canvas":
			return _canvas()
		"gem":
			return _gem(color)
		"plain":
			var key := ["plain", color, source.roughness]
			if not _materials.has(key):
				var flat := StandardMaterial3D.new()
				flat.albedo_color = color
				flat.roughness = source.roughness
				_materials[key] = flat
			return _materials[key]
	var look: Array = PRESETS.get(preset, [Vector2.ONE, 0.25, 0.05])
	var metallic := minf(source.metallic, METAL)
	return textured(color, look[0], look[1], source.roughness, metallic, look[2], tile, false)


## Adds a mesh instance under parent and returns it.
static func part(
	parent: Node3D, mesh: Mesh, material: Material, at: Vector3, turn := Vector3.ZERO
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.rotation = turn
	parent.add_child(instance)
	return instance


static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var key := ["glow", color, energy]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	_materials[key] = material
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


## A cut stone that glows faintly, so it catches the eye in a dark drawer.
static func _gem(color: Color) -> StandardMaterial3D:
	var key := ["gem", color]
	if not _materials.has(key):
		var stone := StandardMaterial3D.new()
		stone.albedo_color = color
		stone.roughness = 0.05
		stone.metallic = 0.3
		stone.emission_enabled = true
		stone.emission = color
		stone.emission_energy_multiplier = 0.6
		_materials[key] = stone
	return _materials[key]


## An abstract painting: cellular noise through a ramp of oil colours.
static func _canvas() -> StandardMaterial3D:
	if not _materials.has("canvas"):
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.frequency = 0.012
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.55, 0.8, 1.0])
		ramp.colors = PackedColorArray(
			[
				Color(0.1, 0.15, 0.3),
				Color(0.2, 0.45, 0.4),
				Color(0.85, 0.7, 0.35),
				Color(0.7, 0.25, 0.2),
				Color(0.95, 0.9, 0.8),
			]
		)
		var texture := NoiseTexture2D.new()
		texture.noise = noise
		texture.color_ramp = ramp
		var canvas := StandardMaterial3D.new()
		canvas.albedo_texture = texture
		canvas.roughness = 0.9
		canvas.uv1_triplanar = true  # Blender models carry no UVs.
		canvas.uv1_scale = Vector3.ONE * 1.2
		_materials["canvas"] = canvas
	return _materials["canvas"]


## Clear, glossy glass tinted by color.
static func _glass(color: Color) -> StandardMaterial3D:
	var key := ["glass", color]
	if not _materials.has(key):
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(color, 0.25)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.roughness = 0.05
		glass.metallic_specular = 0.8
		_materials[key] = glass
	return _materials[key]
