extends RefCounted
## Builds the look of each loot kind out of primitive meshes with generated
## textures (noise run through a colour ramp, plus a matching bump map), and
## the shared material helpers the monster uses too.
##
## Models are purely visual: each one fits inside its kind's collision box
## (KINDS in game.gd), centred on the origin, with its front facing +Z.

const BLACK := Color(0.03, 0.03, 0.03)
const BRASS := Color(0.78, 0.6, 0.25)
const GOLD := Color(0.85, 0.66, 0.2)
## Metallic level for gold and brass. Full metal needs reflections the dark house
## does not have (no sky, no probes) and renders near-black, as the first showcase showed.
const METAL := 0.45

static var _materials := {}  ## Cache: every vase shares one ceramic material, and so on.


## The model for a loot kind, by its name in KINDS.
static func loot(kind: String, size: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	match kind:
		"vase":
			_vase(root, size, color)
		"painting":
			_painting(root, size)
		"crate":
			_crate(root, size, color)
		"grandfather clock":
			_clock(root, size, color)
		"piano":
			_piano(root, size)
		"gem":
			_gem(root, size, color)
		"necklace":
			_necklace(root, size, color)
		"book":
			_book(root, size, color)
		"vial":
			_vial(root, size, color)
		_:
			part(root, _box(size), textured(color), Vector3.ZERO)
	return root


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
) -> StandardMaterial3D:
	var key := [base, grain, contrast, roughness, metallic, frequency, tile]
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
	if tile > 0.0:
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_scale = Vector3(grain.x, 1.0, grain.y) / tile
	_materials[key] = material
	return material


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


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	return mesh


static func _sphere(radius: float, height: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	return mesh


static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


## Glazed ceramic: round belly, narrow neck, flared lip, gold band.
static func _vase(root: Node3D, size: Vector3, color: Color) -> void:
	var glaze := textured(color, Vector2(2, 1), 0.35, 0.12, 0.0, 0.03)
	var gold := textured(GOLD, Vector2.ONE, 0.2, 0.25, METAL)
	var r := size.x / 2.0
	var bottom := -size.y / 2.0
	part(root, _cylinder(r * 0.6, r * 0.5, 0.04), glaze, Vector3(0, bottom + 0.02, 0))
	part(root, _sphere(r, size.y * 0.6), glaze, Vector3(0, bottom + size.y * 0.32, 0))
	part(root, _cylinder(r * 0.94, r * 0.94, 0.03), gold, Vector3(0, bottom + size.y * 0.36, 0))
	part(root, _cylinder(r * 0.32, r * 0.45, size.y * 0.3), glaze, Vector3(0, size.y * 0.27, 0))
	part(root, _cylinder(r * 0.48, r * 0.32, 0.05), glaze, Vector3(0, size.y / 2.0 - 0.025, 0))


## Gilded frame around an abstract canvas.
static func _painting(root: Node3D, size: Vector3) -> void:
	var frame := textured(GOLD, Vector2(1, 6), 0.35, 0.3, METAL, 0.04)
	var border := 0.08
	for y: float in [-1.0, 1.0]:
		var bar := Vector3(size.x, border, size.z)
		part(root, _box(bar), frame, Vector3(0, y * (size.y - border) / 2.0, 0))
	for x: float in [-1.0, 1.0]:
		var bar := Vector3(border, size.y - border * 2.0, size.z)
		part(root, _box(bar), frame, Vector3(x * (size.x - border) / 2.0, 0, 0))

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
		_materials["canvas"] = canvas
	var inner := Vector3(size.x - border * 2.0, size.y - border * 2.0, size.z * 0.5)
	part(root, _box(inner), _materials["canvas"], Vector3.ZERO)


## Pale planks held by darker edge beams.
static func _crate(root: Node3D, size: Vector3, color: Color) -> void:
	var planks := textured(color.lightened(0.15), Vector2(1, 6), 0.35, 0.9, 0.0, 0.05)
	var beams := textured(color.darkened(0.35), Vector2(1, 6), 0.35, 0.9, 0.0, 0.05)
	part(root, _box(size * 0.94), planks, Vector3.ZERO)
	var t := 0.07
	for axis in 3:
		for a: float in [-1.0, 1.0]:
			for b: float in [-1.0, 1.0]:
				var beam := Vector3(t, t, t)
				beam[axis] = size[axis]
				var at := Vector3.ZERO
				at[(axis + 1) % 3] = a * (size[(axis + 1) % 3] - t) / 2.0
				at[(axis + 2) % 3] = b * (size[(axis + 2) % 3] - t) / 2.0
				part(root, _box(beam), beams, at)
	# Diagonal brace across the front.
	var diagonal := Vector2(size.x, size.y).length() * 0.85
	var brace := Vector3(diagonal, t, t * 0.6)
	var turn := Vector3(0, 0, atan2(size.y, size.x))
	part(root, _box(brace), beams, Vector3(0, 0, size.z / 2.0), turn)


## Tall wooden case, hood with a dial, glass door with a brass pendulum.
static func _clock(root: Node3D, size: Vector3, color: Color) -> void:
	var wood := textured(color, Vector2(1, 8), 0.4, 0.45, 0.0, 0.04)
	var brass := textured(BRASS, Vector2.ONE, 0.2, 0.3, METAL)
	var bottom := -size.y / 2.0
	var hood_height := size.y * 0.28
	var trunk_height := size.y - hood_height
	part(root, _box(Vector3(size.x, 0.12, size.z)), wood, Vector3(0, bottom + 0.06, 0))
	var trunk := Vector3(size.x * 0.82, trunk_height, size.z * 0.85)
	part(root, _box(trunk), wood, Vector3(0, bottom + trunk_height / 2.0, 0))
	var hood_y := size.y / 2.0 - hood_height / 2.0
	part(root, _box(Vector3(size.x, hood_height, size.z)), wood, Vector3(0, hood_y, 0))

	var front := size.z / 2.0
	var face_material := textured(Color(0.93, 0.9, 0.8), Vector2.ONE, 0.12, 0.6)
	var dial := _cylinder(size.x * 0.36, size.x * 0.36, 0.02)
	part(root, dial, face_material, Vector3(0, hood_y, front + 0.005), Vector3(PI / 2.0, 0, 0))
	var bezel := _cylinder(size.x * 0.4, size.x * 0.4, 0.015)
	part(root, bezel, brass, Vector3(0, hood_y, front - 0.003), Vector3(PI / 2.0, 0, 0))
	var hand_material := textured(BLACK, Vector2.ONE, 0.1, 0.4)
	part(
		root,
		_box(Vector3(0.015, 0.13, 0.01)),
		hand_material,
		Vector3(0, hood_y + 0.05, front + 0.02)
	)
	var minute := _box(Vector3(0.012, 0.16, 0.01))
	part(
		root,
		minute,
		hand_material,
		Vector3(0.05, hood_y + 0.02, front + 0.025),
		Vector3(0, 0, -1.1)
	)

	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.6, 0.7, 0.75, 0.25)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	var window_y := bottom + trunk_height * 0.55
	var window := Vector3(size.x * 0.5, trunk_height * 0.55, 0.01)
	var trunk_front := trunk.z / 2.0
	var back_panel := textured(color.darkened(0.5), Vector2(1, 8), 0.3, 0.6, 0.0, 0.04)
	part(root, _box(window), back_panel, Vector3(0, window_y, trunk_front + 0.002))
	part(root, _box(window), glass, Vector3(0, window_y, trunk_front + 0.03))
	var rod := _box(Vector3(0.012, trunk_height * 0.4, 0.008))
	part(root, rod, brass, Vector3(0, window_y + trunk_height * 0.08, trunk_front + 0.012))
	var bob := _cylinder(0.06, 0.06, 0.012)
	var bob_at := Vector3(0, window_y - trunk_height * 0.13, trunk_front + 0.014)
	part(root, bob, brass, bob_at, Vector3(PI / 2.0, 0, 0))


## Lacquered upright piano with a keyboard, lid and legs.
static func _piano(root: Node3D, size: Vector3) -> void:
	var lacquer := textured(Color(0.07, 0.05, 0.05), Vector2(1, 4), 0.5, 0.08, 0.0, 0.03)
	var ivory := textured(Color(0.95, 0.92, 0.84), Vector2(8, 1), 0.1, 0.35)
	var ebony := textured(BLACK, Vector2.ONE, 0.1, 0.3)
	var brass := textured(BRASS, Vector2.ONE, 0.2, 0.3, METAL)
	var bottom := -size.y / 2.0
	var depth := size.z * 0.6
	var back := -size.z / 2.0 + depth / 2.0
	var case_height := size.y - 0.15
	part(
		root,
		_box(Vector3(size.x, case_height, depth)),
		lacquer,
		Vector3(0, bottom + 0.15 + case_height / 2.0, back)
	)
	part(
		root,
		_box(Vector3(size.x + 0.04, 0.04, depth + 0.04)),
		lacquer,
		Vector3(0, size.y / 2.0 - 0.02, back)
	)

	var key_y := bottom + size.y * 0.6
	var shelf_depth := size.z - depth
	var shelf_z := size.z / 2.0 - shelf_depth / 2.0
	part(root, _box(Vector3(size.x, 0.06, shelf_depth)), lacquer, Vector3(0, key_y - 0.05, shelf_z))
	var keys := Vector3(size.x * 0.88, 0.025, shelf_depth * 0.85)
	part(root, _box(keys), ivory, Vector3(0, key_y - 0.008, shelf_z))
	var black_count := 22
	for i in black_count:
		if i % 7 == 2 or i % 7 == 6:
			continue  # The gaps between E-F and B-C.
		var x := -keys.x / 2.0 + (i + 0.75) * keys.x / black_count
		var black_key := Vector3(0.022, 0.03, keys.z * 0.55)
		part(root, _box(black_key), ebony, Vector3(x, key_y + 0.012, shelf_z - keys.z * 0.2))

	for x: float in [-1.0, 1.0]:
		var leg := Vector3(0.08, size.y * 0.6 - 0.05, 0.08)
		var leg_at := Vector3(x * (size.x / 2.0 - 0.1), bottom + leg.y / 2.0, size.z / 2.0 - 0.06)
		part(root, _box(leg), lacquer, leg_at)
	for x: float in [-0.12, 0.12]:
		var pedal := Vector3(0.05, 0.015, 0.12)
		part(root, _box(pedal), brass, Vector3(x, bottom + 0.05, depth - size.z / 2.0 + 0.06))


## A cut stone: a four-sided double pyramid that glows faintly, so it catches
## the eye in a dark drawer.
static func _gem(root: Node3D, size: Vector3, color: Color) -> MeshInstance3D:
	var stone := SphereMesh.new()
	stone.radius = size.x / 2.0
	stone.height = size.y
	stone.radial_segments = 4
	stone.rings = 1
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.05
	material.metallic = 0.3
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.6
	return part(root, stone, material, Vector3.ZERO)


## A chain lying in a loop with a red stone hanging at the front.
static func _necklace(root: Node3D, size: Vector3, color: Color) -> void:
	var metal := textured(color, Vector2.ONE, 0.2, 0.25, METAL)
	var chain := TorusMesh.new()
	chain.outer_radius = size.x / 2.0
	chain.inner_radius = size.x / 2.0 - 0.012
	part(root, chain, metal, Vector3(0, -size.y / 2.0 + 0.008, 0))
	var pendant := _gem(root, Vector3.ONE * 0.04, Color(0.7, 0.05, 0.15))
	pendant.position = Vector3(0, -size.y / 2.0 + 0.02, size.z / 2.0)


## A hardback: coloured boards round a block of pale pages.
static func _book(root: Node3D, size: Vector3, color: Color) -> void:
	var cover := textured(color, Vector2.ONE, 0.25, 0.7, 0.0, 0.08)
	var pages := textured(Color(0.9, 0.86, 0.75), Vector2(8, 1), 0.08, 0.9)
	var board := Vector3(size.x, 0.006, size.z)
	for y: float in [-1.0, 1.0]:
		part(root, _box(board), cover, Vector3(0, y * (size.y - board.y) / 2.0, 0))
	part(root, _box(Vector3(0.008, size.y, size.z)), cover, Vector3(-size.x / 2.0 + 0.004, 0, 0))
	var block := Vector3(size.x - 0.012, size.y - 0.012, size.z - 0.008)
	part(root, _box(block), pages, Vector3(0.002, 0, 0))


## A stoppered glass tube of glowing liquid.
static func _vial(root: Node3D, size: Vector3, color: Color) -> void:
	var r := size.x / 2.0
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.8, 0.9, 1.0, 0.25)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	var body_height := size.y * 0.8
	var body_y := -size.y / 2.0 + body_height / 2.0
	part(root, _cylinder(r, r, body_height), glass, Vector3(0, body_y, 0))
	var liquid := _glow(color, 1.5)
	var fill := body_height * 0.65
	part(
		root,
		_cylinder(r * 0.8, r * 0.8, fill),
		liquid,
		Vector3(0, -size.y / 2.0 + fill / 2.0 + 0.004, 0)
	)
	var cork := textured(Color(0.6, 0.45, 0.28), Vector2.ONE, 0.3, 0.9)
	var cork_height := size.y - body_height
	part(
		root,
		_cylinder(r * 0.75, r * 0.85, cork_height),
		cork,
		Vector3(0, size.y / 2.0 - cork_height / 2.0, 0)
	)
