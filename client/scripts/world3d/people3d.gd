extends Node3D
## One character: guests, waiters, the bartender, the bouncer, the band and the people in the
## streets.
##
## The bodies are Kenney's "Mini Characters" (assets/people, CC0): rigged chibi models with a
## shared colour-palette texture. A "look" picks a model for the role and repaints the palette
## cells it uses for clothes and hair (body and head have separate palettes, so a suit colour
## never reaches the eyes), then adds our own hats, glasses and props on the bones, and merges
## it all into one mesh with one material (one draw call per character). Kenney's
## animations give the base motion (idle, walk, sit, wipe, holding); drinking, dancing, cheering,
## arguing and playing are layered on top by posing the arm, head and torso bones in code.
##
## The node's position is the character's feet; it walks along world-space paths and turns to
## face where it goes.
signal arrived

const Builder = preload("res://scripts/world3d/builder.gd")
const MODELS = "res://assets/people/"
const WALK_SPEED = 2.4
## Kenney's models are 0.72 units tall; drawn at this scale people stand about 1.45 m, larger
## than life so they read on a phone screen.
const SIZE = 2.0
## The height of a chair seat, and of the hips in Kenney's sitting pose (model units).
const SEAT_HEIGHT = 0.47
const SIT_HIP = 0.026
## Where the right hand is on the right arm bone (the arm points along -x).
const HAND = Vector3(-0.25, 0.0, 0.0)
## Who plays in each band level, left to right on the stage.
const BAND_LINEUPS = {
	"solo_harmonikas": ["accordion"],
	"trio": ["guitar", "accordion", "bass"],
	"tamburaski_orkestar": ["tamburica", "violin", "accordion", "tamburica", "bass"],
	"pevacica": ["guitar", "tamburica", "mic", "accordion", "violin", "bass"],
}
## The palette cells ([column, row] of 32 x 128 px in the 512 px colormap) each model paints its
## parts with, per mesh. Read from the models' UVs and bone weights.
const PARTS = {
	"female-a": {"body": {"top": [15, 2], "bottom": [11, 2], "shoes": [9, 3]}, "head": {}},
	"female-b": {"body": {"top": [5, 2], "bottom": [15, 2], "shoes": [1, 3]}, "head": {"hair": [11, 3], "band": [5, 2]}},
	"female-c": {"body": {"top": [11, 2], "skirt": [3, 3], "belt": [9, 2], "blouse": [9, 3]}, "head": {"hair": [3, 3], "band": [9, 2]}},
	"female-d": {"body": {"top": [3, 3], "shoes": [1, 3], "shirt": [9, 3]}, "head": {"hair": [11, 3], "jewel": [9, 3]}},
	"female-e": {"body": {"top": [9, 3], "gloves": [11, 2], "bottom": [1, 3], "shoes": [7, 3]}, "head": {}},
	"female-f": {"body": {"top": [5, 2], "sleeves": [1, 3], "bottom": [11, 2], "shoes": [15, 2]}, "head": {"hair": [13, 3], "frames": [15, 2]}},
	"male-a": {"body": {"top": [3, 2], "bottom": [11, 2], "shoes": [5, 2]}, "head": {}},
	"male-b": {"body": {"top": [9, 2], "bottom": [11, 2], "shoes": [11, 3]}, "head": {"hair": [11, 3]}},
	"male-c": {"body": {"top": [11, 2], "vest": [1, 3], "badge": [5, 2], "shoes": [3, 3]}, "head": {"cap": [11, 2], "badge": [5, 2]}},
	"male-d": {"body": {"top": [1, 3], "shirt": [9, 3], "tie": [9, 2]}, "head": {"hair": [11, 3]}},
	"male-e": {"body": {"top": [9, 3], "vest": [5, 2], "hands": [1, 3], "shoes": [3, 3]}, "head": {"hair": [13, 3]}},
	"male-f": {"body": {"top": [3, 2], "shorts": [1, 3], "belt": [3, 3]}, "head": {}},
}
const BRIGHT = ["e85a4f", "3e8ed0", "f2b83a", "4fae6a", "9a5ad0", "f4f1ea", "2fb5a8", "f28a3a"]
const DENIM = ["3a5a8a", "2b2f45", "5a6a7a", "6a4a3a", "4a4a52"]
const HAIR = ["2b1d14", "4a3020", "7a5230", "c9a26a", "1a1a1e", "8a3a22"]
const GREY_HAIR = ["d8d4cc", "c9c4ba", "e8e4dc", "9a948a"]

static var _scenes: Dictionary = {}
static var _bodies: Dictionary = {}
static var _meshes: Dictionary = {}
static var _palette: Image

var look: Dictionary = {}
var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var bones: Dictionary = {}
var hand: Node3D
var instrument: Node3D
var current: String = "idle"
var base: String = "idle"
var rate: float = 1.0
var anim_time: float = 0.0
var path: PackedVector3Array = PackedVector3Array()
var speed_scale: float = 1.0
var heading: float = 0.0
var target_heading: float = 0.0
var phase: float = 0.0
var holding: String = ""

# ---------------------------------------------------------------------------------------------
# Looks
# ---------------------------------------------------------------------------------------------

## A look for a guest type (or "waiter", "bartender", "bouncer", "musician:<instrument>").
static func make_look(kind: String, variant: int) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(kind) + variant * 7919
	var pick: Callable = func(options: Array) -> String: return options[rng.randi() % options.size()]
	var female: bool = variant % 2 == 1
	var look: Dictionary = {"kind": kind, "variant": variant, "female": female, "model": "male-d",
		"body": {}, "head": {}, "hat": "", "extra": "", "glasses": "", "instrument": "", "build": 1.0}
	match kind:
		"penzioner":
			if female:
				look.model = "female-c"
				look.body = {"top": pick.call(["3a4a6a", "6a2a3a", "5a6a4a", "4a3a5a", "6e5a44"]), "skirt": pick.call(["3a3a40", "4a3a2e", "2f3a4a"]), "belt": pick.call(["8a2f3a", "c0322c", "3a5a8a"])}
				look.head = {"band": pick.call(["2f3a5a", "6a2a3a", "3d5a3a", "5a3a5a"]), "hair": pick.call(GREY_HAIR)}
			elif variant % 4 == 0:
				look.model = "male-d"
				look.body = {"top": pick.call(["5a4a3a", "4a4a52", "3a3a40", "4a4030"]), "tie": pick.call(["8a1f22", "3a5a3a", "5a3a22"])}
				look.head = {"hair": pick.call(GREY_HAIR)}
				look.hat = pick.call(["sajkaca", "flatcap"])
			else:
				look.model = "male-b"
				look.body = {"top": pick.call(["6e5a44", "5a6a4a", "7a6a52", "4a5568", "8a6a4a"]), "bottom": pick.call(["4a4a52", "5a4a3a", "3a3a40"]), "shoes": "3a2a1e"}
				look.head = {"hair": pick.call(GREY_HAIR)}
				look.hat = "sajkaca" if rng.randf() < 0.6 else ""
		"studenti":
			look.model = pick.call(["female-a", "female-b", "female-f"] if female else ["male-a", "male-f", "male-a"])
			look.body = {"top": pick.call(BRIGHT), "bottom": pick.call(DENIM), "shoes": pick.call(["f4f1ea", "e85a4f", "2b2b30", "3e8ed0"]), "sleeves": pick.call(["2b2b30", "f4f1ea"]), "shorts": pick.call(DENIM)}
			look.head = {"hair": pick.call(HAIR), "band": pick.call(BRIGHT), "frames": "2b2b30"}
		"svatovi":
			if female:
				look.model = "female-d"
				look.body = {"top": pick.call(["d9536a", "f2b83a", "4aa8c9", "b05ad0", "f4f1ea", "e88aa8"]), "shoes": pick.call(["f4f1ea", "c0322c", "d9a531"])}
				look.head = {"hair": pick.call(HAIR), "jewel": "f3d27a"}
			else:
				look.model = "male-d"
				look.body = {"top": pick.call(["2b2f45", "1d2433", "3a3a44", "4a3a5a"]), "tie": pick.call(["c0322c", "f2b83a", "d9536a"])}
				look.head = {"hair": pick.call(HAIR)}
				look.extra = "flower"
		"biznismen":
			look.model = "female-d" if female else "male-d"
			look.body = {"top": pick.call(["2b2f45", "3a3f4a", "4a4f5a", "1d2433"]), "tie": pick.call(["c0322c", "3e8ed0", "d9a531"]), "shoes": "1d1d22"}
			look.head = {"hair": pick.call(HAIR), "jewel": "f3d27a"}
			look.glasses = "glasses" if rng.randf() < 0.4 else ""
		"ozalosceni":
			look.model = pick.call(["female-d", "female-c"]) if female else "male-d"
			look.body = {"top": "1d1d22", "tie": "1d1d22", "shoes": "1d1d22", "shirt": "2b2b30", "skirt": "1d1d22", "belt": "1d1d22", "blouse": "2b2b30"}
			look.head = {"hair": pick.call(["2b1d14", "1a1a1e", "4a3020", "9a948a"]), "band": "1d1d22", "jewel": "2b2b30"}
		"waiter":
			look.model = "female-e" if female else "male-e"
			look.body = {"top": "f4f1ea", "vest": "1d1d22", "hands": "dd9f78", "gloves": "dd9f78", "bottom": "1d1d22", "shoes": "1d1d22"}
			look.head = {"hair": pick.call(HAIR)}
			look.extra = "apron"
		"bartender":
			look.model = "male-b"
			look.body = {"top": "f4f1ea", "bottom": "1d1d22", "shoes": "1d1d22"}
			look.head = {"hair": "3a2416"}
			look.extra = "bowtie"
		"bouncer":
			look.model = "male-c"
			look.body = {"top": "1d1d22", "vest": "1d1d22", "badge": "3a3a40", "shoes": "1d1d22"}
			look.head = {"cap": "1d1d22", "badge": "3a3a40"}
			look.glasses = "sunglasses"
			look.build = 1.2
		_:
			if kind.begins_with("musician:"):
				look.instrument = kind.split(":")[1]
				look.female = look.instrument == "mic"
				if look.female:
					look.model = "female-d"
					look.body = {"top": "c9294a", "shoes": "1d1d22"}
					look.head = {"hair": "1a1a1e", "jewel": "f3d27a"}
				else:
					look.model = "male-b" if variant % 3 == 2 else "male-d"
					var colour: String = ["8a1f22", "1d2433", "2f5a35"][variant % 3]
					look.body = {"top": colour, "tie": "d9a531", "bottom": "1d1d22", "shoes": "1d1d22"}
					look.head = {"hair": pick.call(HAIR)}
					look.extra = "bowtie" if look.model == "male-b" else ""
	return look

## A model's palette for one of its meshes with cells repainted. The cells keep their shading:
## each pixel is the new colour times its brightness relative to the cell's average.
static func _repaint(model_name: String, mesh_name: String, colours: Dictionary) -> Image:
	if _palette == null:
		var texture: Texture2D = load(MODELS + "Textures/colormap.png")
		_palette = texture.get_image()
		if _palette.is_compressed():
			_palette.decompress()
		_palette.convert(Image.FORMAT_RGBA8)
	var parts: Dictionary = PARTS.get(model_name, {}).get(mesh_name, {})
	var image: Image = _palette.duplicate()
	for part in colours:
		if not parts.has(part):
			continue
		var cell: Array = parts[part]
		var rect: Rect2i = Rect2i(int(cell[0]) * 32, int(cell[1]) * 128, 32, 128)
		var mean: float = 0.0
		for y in range(rect.position.y, rect.end.y, 8):
			for x in range(rect.position.x, rect.end.x, 4):
				mean += image.get_pixel(x, y).get_luminance()
		mean /= (rect.size.y / 8.0) * (rect.size.x / 4.0)
		var colour: Color = Color(str(colours[part]))
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var shade: float = clampf(image.get_pixel(x, y).get_luminance() / maxf(0.05, mean), 0.75, 1.2)
				image.set_pixel(x, y, Color(colour.r * shade, colour.g * shade, colour.b * shade))
	return image

## The whole character as one skinned mesh with one material, so it costs a single draw call:
## Kenney's body and head meshes, their two repainted palettes side by side in one texture, and
## the hat, glasses and clothing extras built onto their bones (coloured per vertex over a white
## patch of the texture). Returns [mesh, skin], cached per look.
static func _body(look: Dictionary, skeleton: Skeleton3D, sources: Array) -> Array:
	var key: String = JSON.stringify([look.model, look.body, look.head, look.hat, look.glasses, look.extra], "", true)
	if _bodies.has(key):
		return _bodies[key]
	var atlas: Image = Image.create(1024, 512, false, Image.FORMAT_RGBA8)
	atlas.blit_rect(_repaint(str(look.model), "body", look.body), Rect2i(0, 0, 512, 512), Vector2i(0, 0))
	atlas.blit_rect(_repaint(str(look.model), "head", look.head), Rect2i(0, 0, 512, 512), Vector2i(512, 0))
	# The colormap leaves its top rows empty: a white patch there carries the vertex colours.
	atlas.fill_rect(Rect2i(128, 24, 64, 64), Color.WHITE)
	atlas.generate_mipmaps()
	var white: Vector2 = Vector2(160.0 / 1024.0, 56.0 / 512.0)
	# One skin over the whole skeleton; each source's bone indices are renumbered into it.
	var skin: Skin = Skin.new()
	var names: Array = []
	for i in range(skeleton.get_bone_count()):
		names.append(skeleton.get_bone_name(i))
		skin.add_named_bind(skeleton.get_bone_name(i), skeleton.get_bone_global_rest(i).affine_inverse())
	var out: Dictionary = {"verts": PackedVector3Array(), "normals": PackedVector3Array(), "uvs": PackedVector2Array(),
		"colors": PackedColorArray(), "bones": PackedInt32Array(), "weights": PackedFloat32Array(), "indices": PackedInt32Array()}
	for source in sources:
		var mesh_node: MeshInstance3D = source
		var head: bool = mesh_node.name.begins_with("head")
		var arrays: Array = mesh_node.mesh.surface_get_arrays(0)
		var remap: Array = []
		for i in range(mesh_node.skin.get_bind_count()):
			var bind_name: String = mesh_node.skin.get_bind_name(i)
			if bind_name.is_empty():
				bind_name = skeleton.get_bone_name(mesh_node.skin.get_bind_bone(i))
			remap.append(maxi(0, names.find(bind_name)))
			skin.set_bind_pose(remap[i], mesh_node.skin.get_bind_pose(i))
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		for i in range(bones.size()):
			bones[i] = remap[bones[i]] if bones[i] < remap.size() else 0
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for i in range(uvs.size()):
			uvs[i] = Vector2(uvs[i].x * 0.5 + (0.5 if head else 0.0), uvs[i].y)
		var colors: PackedColorArray = PackedColorArray()
		colors.resize(uvs.size())
		colors.fill(Color.WHITE)
		_append(out, arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL], uvs, colors, bones, arrays[Mesh.ARRAY_WEIGHTS], arrays[Mesh.ARRAY_INDEX])
	var extras: Builder = Builder.new()
	var place: Callable = func(bone: String, at: Vector3) -> void:
		var index: int = names.find(bone)
		extras.bone = index
		extras.offset = skeleton.get_bone_global_rest(index) * Transform3D(Basis.IDENTITY, at)
	if str(look.hat) != "":
		place.call("head", Vector3(0, 0.355, -0.03))
		_accessory(extras, look.hat)
	match str(look.extra):
		"flower":
			place.call("torso", Vector3(0.07, 0.15, 0.115))
			_accessory(extras, "flower")
		"bowtie":
			place.call("torso", Vector3(0, 0.175, 0.105))
			_accessory(extras, "bowtie")
		"apron":
			place.call("torso", Vector3(0, 0.0, 0.105))
			_accessory(extras, "apron")
	for id in extras.groups:
		var group: Dictionary = extras.groups[id]
		var flat: PackedVector2Array = PackedVector2Array()
		flat.resize(group.verts.size())
		flat.fill(white)
		_append(out, group.verts, group.normals, flat, group.colors, group.bones, group.weights, group.indices)
	if str(look.glasses) != "":
		var glasses: Mesh = _mesh(look.glasses)
		if glasses != null:
			var arrays: Array = glasses.surface_get_arrays(0)
			var index: int = names.find("head")
			var xf: Transform3D = skeleton.get_bone_global_rest(index) * Transform3D(Basis.IDENTITY, Vector3(0, 0.07, 0.06))
			var verts: PackedVector3Array = xf * PackedVector3Array(arrays[Mesh.ARRAY_VERTEX])
			var normals: PackedVector3Array = Transform3D(xf.basis, Vector3.ZERO) * PackedVector3Array(arrays[Mesh.ARRAY_NORMAL])
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			for i in range(uvs.size()):
				uvs[i] = Vector2(uvs[i].x * 0.5 + 0.5, uvs[i].y)
			var count: int = verts.size()
			var colors: PackedColorArray = PackedColorArray()
			colors.resize(count)
			colors.fill(Color.WHITE)
			var bones: PackedInt32Array = PackedInt32Array()
			bones.resize(count * 4)
			var weights: PackedFloat32Array = PackedFloat32Array()
			weights.resize(count * 4)
			for i in range(count):
				bones[i * 4] = index
				weights[i * 4] = 1.0
			_append(out, verts, normals, uvs, colors, bones, weights, arrays[Mesh.ARRAY_INDEX])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out.verts
	arrays[Mesh.ARRAY_NORMAL] = out.normals
	arrays[Mesh.ARRAY_TEX_UV] = out.uvs
	arrays[Mesh.ARRAY_COLOR] = out.colors
	arrays[Mesh.ARRAY_BONES] = out.bones
	arrays[Mesh.ARRAY_WEIGHTS] = out.weights
	arrays[Mesh.ARRAY_INDEX] = out.indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(atlas)
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.85
	material.rim_enabled = true
	material.rim = 0.35
	material.rim_tint = 0.6
	mesh.surface_set_material(0, material)
	_bodies[key] = [mesh, skin]
	return _bodies[key]

static func _append(out: Dictionary, verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray,
		bones: PackedInt32Array, weights: PackedFloat32Array, indices: PackedInt32Array) -> void:
	var base: int = out.verts.size()
	out.verts.append_array(verts)
	out.normals.append_array(normals)
	out.uvs.append_array(uvs)
	out.colors.append_array(colors)
	out.bones.append_array(bones)
	out.weights.append_array(weights)
	var shifted: PackedInt32Array = PackedInt32Array(indices)
	for i in range(shifted.size()):
		shifted[i] += base
	out.indices.append_array(shifted)

static func _scene(model_name: String) -> PackedScene:
	if not _scenes.has(model_name):
		var scene: PackedScene = load(MODELS + "character-" + model_name + ".glb")
		_scenes[model_name] = scene
		# Kenney's clips carry no loop flag; every clip we use loops.
		var probe: Node = scene.instantiate()
		for found in probe.find_children("*", "AnimationPlayer", true, false):
			for clip in found.get_animation_list():
				found.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		probe.free()
	return _scenes[model_name]

# ---------------------------------------------------------------------------------------------
# Props, hats and instruments (model units: the character is 0.72 tall)
# ---------------------------------------------------------------------------------------------

static func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	if kind in ["glasses", "sunglasses"]:
		var scene: Node = load(MODELS + "aid-" + kind + ".glb").instantiate()
		var found: Array = scene.find_children("*", "MeshInstance3D", true, false)
		_meshes[kind] = found[0].mesh if not found.is_empty() else null
		scene.free()
		return _meshes[kind]
	var b: Builder = Builder.new()
	_accessory(b, kind)
	_meshes[kind] = b.mesh()
	return _meshes[kind]

## Adds a prop, hat or instrument to a builder (at the builder's offset and bone).
static func _accessory(b: Builder, kind: String) -> void:
	match kind:
		"glass":
			b.cylinder(Vector3.ZERO, 0.028, 0.075, Color("dfeff0"), "vc_gloss", 8)
			b.cylinder(Vector3(0, 0.004, 0), 0.025, 0.05, Color("e8a33a"), "vc_gloss", 8)
		"tray":
			b.cylinder(Vector3.ZERO, 0.13, 0.012, Color("c9ced6"), "vc_metal", 14)
			b.cylinder(Vector3(0.035, 0.012, 0.02), 0.022, 0.075, Color("dfeff0"), "vc_gloss", 8)
			b.cylinder(Vector3(-0.045, 0.012, -0.02), 0.02, 0.1, Color("3d8a4f"), "vc_gloss", 8)
		"cloth":
			b.box(Vector3(0, -0.012, 0), Vector3(0.09, 0.025, 0.07), Color("f4f1ea"))
		"sajkaca":
			# The Serbian šajkača: a grey-green cap, boat-shaped and folded down the middle.
			var cloth: Color = Color("5e5d40")
			b.box(Vector3(0, 0.0, 0), Vector3(0.42, 0.07, 0.4), cloth)
			b.prism(Vector3(0, 0.07, 0), Vector3(0.42, 0.08, 0.38), cloth.darkened(0.12), "vc", PI / 2.0)
			b.box(Vector3(0, 0.03, 0.2), Vector3(0.28, 0.05, 0.02), cloth.darkened(0.25))
		"flatcap":
			b.cylinder(Vector3.ZERO, 0.23, 0.07, Color("5a4a3a"), "vc", 14, 0.88)
			b.box(Vector3(0, 0.0, 0.2), Vector3(0.3, 0.025, 0.12), Color("4a3a2c"))
		"flower":
			b.sphere(Vector3.ZERO, 0.022, Color("f4f1ea"), "vc", Vector3.ONE, 6)
			b.sphere(Vector3(0, 0, 0.012), 0.01, Color("f3d27a"), "vc", Vector3.ONE, 5)
		"bowtie":
			for x in [-0.02, 0.02]:
				b.sphere(Vector3(x, 0, 0), 0.018, Color("1d1d22"), "vc", Vector3(1.2, 0.8, 0.5), 6)
		"apron":
			b.box(Vector3(0, -0.15, 0), Vector3(0.21, 0.17, 0.012), Color("f4f1ea"))
		"accordion":
			# A black accordion with a pearl keyboard and a brass grille, red bellows open between.
			b.box(Vector3(-0.1, -0.11, 0), Vector3(0.06, 0.2, 0.12), Color("1d1d22"), "vc_gloss")
			b.box(Vector3(0.1, -0.11, 0), Vector3(0.06, 0.2, 0.12), Color("1d1d22"), "vc_gloss")
			for k in range(6):
				b.box(Vector3(-0.06 + k * 0.024, -0.105, 0), Vector3(0.02, 0.19, 0.115), Color("c0322c") if k % 2 == 0 else Color("2b2b30"))
			b.box(Vector3(-0.132, -0.11, 0.01), Vector3(0.012, 0.18, 0.09), Color("f4f1ea"), "vc_gloss")
			b.box(Vector3(0.132, -0.1, 0.0), Vector3(0.008, 0.12, 0.08), Color("d9a531"), "vc_metal")
		"guitar", "tamburica", "bass":
			var scale: float = {"guitar": 1.0, "tamburica": 0.75, "bass": 1.25}[kind]
			var wood: Color = {"guitar": Color("c98a4a"), "tamburica": Color("8a4a22"), "bass": Color("3a2416")}[kind]
			b.sphere(Vector3.ZERO, 0.1 * scale, wood, "vc_gloss", Vector3(1.0, 1.25, 0.35), 12)
			b.sphere(Vector3(0, 0, 0.032 * scale), 0.03 * scale, Color("1a1410"), "vc", Vector3(1, 1, 0.2), 8)
			b.box(Vector3(0, 0.09 * scale, 0), Vector3(0.03, 0.3 * scale, 0.024), Color("2b1d14"), "vc_gloss")
		"violin":
			b.sphere(Vector3.ZERO, 0.055, Color("8a3a1a"), "vc_gloss", Vector3(1.0, 1.4, 0.4), 10)
			b.box(Vector3(0, 0.09, 0), Vector3(0.018, 0.12, 0.018), Color("1a1410"))
		"bow":
			b.box(Vector3.ZERO, Vector3(0.007, 0.3, 0.007), Color("2b1d14"))
		"mic":
			b.cylinder(Vector3(0, 0, 0), 0.01, 0.47, Color("2b2b30"), "vc_metal", 6)
			b.cylinder(Vector3(0, 0, 0), 0.06, 0.01, Color("2b2b30"), "vc_metal", 10)
			b.sphere(Vector3(0, 0.49, 0), 0.025, Color("8a8f98"), "vc_metal", Vector3.ONE, 8)

# ---------------------------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------------------------

func setup(new_look: Dictionary) -> void:
	look = new_look
	scale = full_scale()
	model = _scene(str(look.model)).instantiate()
	model.scale = Vector3.ONE * SIZE
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	for i in range(skeleton.get_bone_count()):
		bones[skeleton.get_bone_name(i)] = i
	var sources: Array = skeleton.find_children("*", "MeshInstance3D", true, false)
	var built: Array = _body(look, skeleton, sources)
	for source in sources:
		source.free()
	var body: MeshInstance3D = MeshInstance3D.new()
	body.mesh = built[0]
	body.skin = built[1]
	skeleton.add_child(body)
	body.skeleton = NodePath("..")
	player = model.find_children("*", "AnimationPlayer", true, false)[0]
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var torso: Node3D = _attachment("torso")
	hand = Node3D.new()
	hand.position = HAND
	_attachment("arm-right").add_child(hand)
	if str(look.instrument) != "":
		var kind: String = look.instrument
		instrument = Node3D.new()
		match kind:
			"accordion":
				torso.add_child(instrument)
				instrument.position = Vector3(0, 0.2, 0.16)
			"violin":
				torso.add_child(instrument)
				instrument.position = Vector3(0.08, 0.27, 0.1)
				instrument.rotation = Vector3(0.3, 0, 1.2)
			"mic":
				model.add_child(instrument)
				instrument.position = Vector3(0, 0, 0.2)
			_:
				torso.add_child(instrument)
				instrument.position = Vector3(0.01, 0.1, 0.13)
				instrument.rotation = Vector3(0, 0, -0.9)
		_add_mesh(instrument, _mesh(kind), Vector3.ZERO)
		if kind == "violin":
			_add_mesh(hand, _mesh("bow"), Vector3.ZERO, Vector3(0, 0, 1.2))
	phase = randf() * TAU
	play("idle")

## The size a character is drawn at (the model inside carries the base scale); broader for a
## big build.
func full_scale() -> Vector3:
	return Vector3.ONE * (1.0 + (float(look.get("build", 1.0)) - 1.0) * 0.5)

func _attachment(bone_name: String) -> Node3D:
	var attach: BoneAttachment3D = BoneAttachment3D.new()
	attach.bone_name = bone_name
	skeleton.add_child(attach)
	return attach

func _add_mesh(parent: Node3D, mesh: Mesh, at: Vector3, turn: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.rotation = turn
	parent.add_child(node)
	return node

## Hold something in the right hand: "", "glass", "tray" or "cloth".
func hold(kind: String) -> void:
	if kind == holding:
		return
	holding = kind
	for child in hand.get_children():
		if child.get_meta("held", false):
			child.queue_free()
	if kind != "":
		var held: MeshInstance3D = _add_mesh(hand, _mesh(kind), Vector3(0, 0.02 if kind == "tray" else 0.0, 0))
		held.set_meta("held", true)

# ---------------------------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------------------------

## Animations: idle, walk, sit, drink, dance, angry, happy, carry, carry_idle, play, wipe.
func play(name: String, new_rate: float = 1.0, restart: bool = false) -> void:
	if name == current and not restart:
		rate = new_rate
		return
	current = name
	rate = new_rate
	anim_time = 0.0
	hold("tray" if name in ["carry", "carry_idle"] else ("glass" if name == "drink" else ("cloth" if name == "wipe" else "")))
	base = {"walk": "walk", "carry": "walk", "sit": "sit", "drink": "sit", "happy": "sit", "angry": "sit",
		"wipe": "interact-right", "play": "holding-both"}.get(name, "idle")

func face(direction: Vector3) -> void:
	if Vector2(direction.x, direction.z).length() < 0.01:
		return
	target_heading = atan2(direction.x, direction.z)

func face_now(direction: Vector3) -> void:
	face(direction)
	heading = target_heading
	rotation.y = heading

func walk(points: PackedVector3Array) -> void:
	path = points
	if path.is_empty():
		arrived.emit()

func is_walking() -> bool:
	return not path.is_empty()

func fade_in(_duration: float = 0.3) -> void:
	scale = full_scale() * 0.2
	create_tween().tween_property(self, "scale", full_scale(), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func fade_and_free(_duration: float = 0.3) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", full_scale() * 0.05, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

func _process(delta: float) -> void:
	if skeleton == null:
		return
	anim_time += delta * rate
	if not path.is_empty():
		var target: Vector3 = path[0]
		var offset: Vector3 = target - position
		offset.y = 0.0
		var step: float = WALK_SPEED * speed_scale * delta
		face(offset)
		if current not in ["walk", "carry"]:
			play("carry" if holding == "tray" else "walk")
		rate = 1.15 * speed_scale
		if offset.length() <= step:
			position = Vector3(target.x, position.y, target.z)
			path.remove_at(0)
			if path.is_empty():
				arrived.emit()
		else:
			position += offset.normalized() * step
	heading = lerp_angle(heading, target_heading, clampf(delta * 10.0, 0.0, 1.0))
	rotation.y = heading
	_pose()

func _turn(bone: String, rotation_euler: Vector3) -> void:
	if bones.has(bone):
		skeleton.set_bone_pose_rotation(bones[bone], Quaternion.from_euler(rotation_euler))

## An arm: `forward` swings it from the side to the front (radians), `down` lowers it from the
## horizontal (negative raises it). Kenney's arms point out sideways at rest.
func _arm(side: String, forward: float, down: float) -> void:
	if not bones.has("arm-" + side):
		return
	var sign: float = 1.0 if side == "right" else -1.0
	var q: Quaternion = Quaternion(Vector3.UP, forward * sign) * Quaternion(Vector3.BACK, -down * sign)
	skeleton.set_bone_pose_rotation(bones["arm-" + side], q)

func _pose() -> void:
	if player == null:
		return
	skeleton.reset_bone_poses()
	if player.has_animation(base):
		if player.current_animation != base:
			player.play(base)
		player.seek(fmod(anim_time, maxf(0.01, player.get_animation(base).length)), true)
	var t: float = anim_time
	var sitting: bool = base == "sit"
	model.position = Vector3(0, (SEAT_HEIGHT / SIZE - SIT_HIP) if sitting else 0.0, 0)
	match current:
		"carry", "carry_idle":
			_arm("right", 1.05, 0.15)
		"drink":
			var lift: float = maxf(0.0, sin(t * 2.4 + phase))
			_arm("right", 1.2, 0.2 - lift * 1.2)
			_turn("head", Vector3(-0.25 * lift, 0, 0))
		"happy":
			var wave: float = sin(t * 6.0 + phase)
			_arm("right", 0.4, -0.9 - 0.4 * wave)
			_arm("left", 0.4, -0.9 + 0.4 * wave)
			_turn("head", Vector3(0, 0, 0.15 * wave))
		"angry":
			_arm("right", 1.3, 0.35)
			_arm("left", 1.3, 0.35)
			_turn("head", Vector3(0.1, sin(t * 9.0) * 0.35, 0))
		"sit":
			_turn("head", Vector3(0, sin(t * 0.9 + phase) * 0.35, 0))
		"dance":
			var beat: float = sin(t * 7.0 + phase)
			_arm("right", 0.2, -1.1 - 0.5 * beat)
			_arm("left", 0.2, -1.1 + 0.5 * beat)
			_turn("torso", Vector3(0, beat * 0.3, 0))
			_turn("head", Vector3(0, 0, beat * 0.15))
			model.position.y = absf(sin(t * 7.0 + phase)) * 0.05
		"play":
			var strum: float = sin(t * 9.0 + phase)
			match str(look.instrument):
				"accordion":
					_arm("right", 1.2, 0.35)
					_arm("left", 1.2, 0.35)
					instrument.scale = Vector3(1.0 + strum * 0.15, 1, 1)
				"mic":
					_arm("right", 1.3, -0.6)
					_arm("left", 0.2, 0.7 + 0.2 * strum)
				"violin":
					_arm("left", 1.0, -0.3)
					_arm("right", 1.1, 0.3 * strum)
				_:
					_arm("left", 1.3, 0.1)
					_arm("right", 1.1, 0.45 + 0.25 * strum)
			_turn("head", Vector3(0, 0, sin(t * 3.0 + phase) * 0.12))
			model.position.y = absf(sin(t * 6.0 + phase)) * 0.012
