extends Node3D
## One low-poly character: guests, waiters, the bartender, the bouncer and the band.
##
## A character is assembled from a "look" (skin, hair, clothes, hat, accessories) into a few
## meshes — body, head, arms, legs and a held prop — that are cached per look and shared. Poses
## are procedural: the pivots swing, bend and bob from the current animation and time. The node's
## position is the character's feet; it walks along world-space paths and turns to face where
## it goes.
signal arrived

const Builder = preload("res://scripts/world3d/builder.gd")
const Kit = preload("res://scripts/world3d/kit3d.gd")
const WALK_SPEED = 2.4
const HIP = 0.52
## Characters are drawn a little larger than life so they read on a phone screen.
const SIZE = 1.3
## Height of a chair seat: a seated character's hips rest here whatever its size.
const SEAT_HEIGHT = 0.5
const SKIN = ["f6d3b3", "efc29c", "e0a77e", "c58a62", "8d5b3d"]
## Who plays in each band level, left to right on the stage.
const BAND_LINEUPS = {
	"solo_harmonikas": ["accordion"],
	"trio": ["guitar", "accordion", "bass"],
	"tamburaski_orkestar": ["tamburica", "violin", "accordion", "tamburica", "bass"],
	"pevacica": ["guitar", "tamburica", "mic", "accordion", "violin", "bass"],
}
const BONES = ["root", "body", "head", "arm_l", "arm_r", "leg_l", "leg_r"]
enum { ROOT, BODY, HEAD, ARM_L, ARM_R, LEG_L, LEG_R }

static var _cache: Dictionary = {}

var look: Dictionary = {}
var skeleton: Skeleton3D
var rest: Array = []
var body: Node3D
var prop: Node3D
var brows: MeshInstance3D
var instrument: Node3D
var current: String = "idle"
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
	var female: bool = variant % 2 == 1
	var look: Dictionary = {
		"kind": kind, "variant": variant, "female": female, "skin": SKIN[rng.randi() % SKIN.size()],
		"hair": ["2b1d14", "4a3020", "7a5230", "c9a26a", "1a1a1e", "8a3a22"][rng.randi() % 6],
		"hair_style": "long" if female else "short", "top": "f4f1ea", "top_style": "shirt", "bottom": "2b2f45",
		"shoes": "1d1d22", "hat": "", "beard": "", "extra": "", "accent": "c0322c", "build": 1.0, "instrument": "",
	}
	match kind:
		"penzioner":
			look.hair = ["c9c4ba", "e8e4dc", "9a948a"][rng.randi() % 3]
			look.top = ["7a6a52", "5a6a4a", "6e5a44", "4a5568"][rng.randi() % 4]
			look.top_style = "cardigan"
			look.bottom = ["4a4a52", "5a4a3a"][rng.randi() % 2]
			if female:
				look.hair_style = "bun"
				look.extra = "scarf"
				look.accent = ["8a2f3a", "3a5a8a", "6a4a7a"][rng.randi() % 3]
			else:
				look.hat = ["sajkaca", "flatcap", ""][rng.randi() % 3]
				look.beard = "mustache"
				look.hair_style = "bald" if rng.randf() < 0.5 else "short"
		"studenti":
			look.top = ["e85a4f", "3e8ed0", "f2b83a", "4fae6a", "9a5ad0", "f4f1ea"][rng.randi() % 6]
			look.top_style = "hoodie"
			look.bottom = ["3a5a8a", "2b2f45", "5a6a7a"][rng.randi() % 3]
			look.shoes = ["f4f1ea", "e85a4f", "2b2b30"][rng.randi() % 3]
			look.hat = "beanie" if rng.randf() < 0.3 else ""
			look.accent = ["2b2f45", "c0322c", "3e8ed0"][rng.randi() % 3]
			look.extra = "backpack" if rng.randf() < 0.4 else ""
			if female:
				look.hair_style = ["long", "ponytail", "bob"][rng.randi() % 3]
			else:
				look.hair_style = ["short", "messy"][rng.randi() % 2]
				look.beard = "stubble" if rng.randf() < 0.3 else ""
		"ozalosceni":
			look.top = "1d1d22"
			look.top_style = "dress" if female else "suit"
			look.bottom = "1d1d22"
			look.accent = "1d1d22"
			if female:
				look.extra = "veil"
				look.hair_style = "bun"
			else:
				look.beard = ["", "beard", "mustache"][rng.randi() % 3]
		"svatovi":
			if female:
				look.top = ["d9536a", "f2b83a", "4aa8c9", "b05ad0", "f4f1ea"][rng.randi() % 5]
				look.top_style = "dress"
				look.hair_style = ["bun", "long"][rng.randi() % 2]
				look.extra = "necklace"
			else:
				look.top = ["2b2f45", "4a4a52", "1d2433"][rng.randi() % 3]
				look.top_style = "suit"
				look.extra = "flower"
				look.accent = ["c0322c", "f2b83a"][rng.randi() % 2]
				look.beard = ["", "mustache"][rng.randi() % 2]
		"biznismen":
			look.top = ["1d2433", "2b2b33", "3a3a44"][rng.randi() % 3]
			look.top_style = "suit"
			look.accent = ["c0322c", "3e8ed0", "d9a531"][rng.randi() % 3]
			look.extra = "tie"
			look.hair_style = "slick" if not female else "bob"
			look.hat = "glasses" if rng.randf() < 0.4 else ""
		"waiter":
			look.top_style = "vest"
			look.top = "f4f1ea"
			look.accent = "1d1d22"
			look.extra = "bowtie"
			look.bottom = "1d1d22"
			look.hair_style = "slick" if not female else "ponytail"
		"bartender":
			look.top_style = "vest"
			look.top = "f4f1ea"
			look.accent = "8a1f22"
			look.extra = "bowtie"
			look.beard = "mustache"
			look.female = false
			look.hair_style = "short"
		"bouncer":
			look.female = false
			look.top = "1d1d22"
			look.top_style = "tshirt"
			look.bottom = "1d1d22"
			look.hair_style = "bald"
			look.hat = "glasses"
			look.build = 1.25
		_:
			if kind.begins_with("musician:"):
				look.instrument = kind.split(":")[1]
				look.top_style = "vest"
				look.top = "f4f1ea"
				look.accent = ["8a1f22", "1d2433", "2f5a35"][variant % 3]
				look.bottom = "1d1d22"
				look.female = look.instrument == "mic"
				if look.female:
					look.top_style = "dress"
					look.top = "c9294a"
					look.hair_style = "long"
					look.hair = "1a1a1e"
					look.extra = "necklace"
				else:
					look.hair_style = "short"
					look.beard = ["mustache", "", "beard"][variant % 3]
	return look

# ---------------------------------------------------------------------------------------------
# Meshes
# ---------------------------------------------------------------------------------------------

## Bone rest positions (relative to the parent bone) for a look's build.
static func rest_positions(look: Dictionary) -> Array:
	var build: float = float(look.get("build", 1.0))
	return [Vector3.ZERO, Vector3(0, HIP, 0), Vector3(0, 0.44, 0), Vector3(-0.2 * build, 0.38, 0), Vector3(0.2 * build, 0.38, 0),
		Vector3(-0.085, 0, 0), Vector3(0.085, 0, 0)]

## One skinned mesh per look: every part follows its bone, so a character is one draw call.
static func _mesh(look: Dictionary) -> ArrayMesh:
	var key: String = JSON.stringify(look)
	if _cache.has(key):
		return _cache[key]
	var skin: Color = Color(look.skin)
	var top: Color = Color(look.top)
	var accent: Color = Color(look.accent)
	var bottom: Color = Color(look.bottom)
	var build: float = float(look.build)
	var rests: Array = rest_positions(look)
	var b: Builder = Builder.new()
	var place: Callable = func(bone: int) -> void:
		var at: Vector3 = Vector3.ZERO
		var current: int = bone
		var parents: Array = [-1, ROOT, BODY, BODY, BODY, BODY, BODY]
		while current >= 0:
			at += rests[current]
			current = parents[current]
		b.bone = bone
		b.offset = Transform3D(Basis.IDENTITY, at)
	# Body: hips and torso above the hip.
	place.call(BODY)
	var dress: bool = look.top_style == "dress"
	if dress:
		b.cylinder(Vector3(0, -0.34, 0), 0.25, 0.42, top.darkened(0.08), "vc", 12, 0.66)
	else:
		b.box(Vector3(0, -0.05, 0), Vector3(0.3, 0.14, 0.2) * Vector3(build, 1, build), bottom)
	b.cylinder(Vector3(0, 0.0, 0), 0.165 * build, 0.42, top, "vc", 12, 1.12)
	match look.top_style:
		"suit":
			b.box(Vector3(0, 0.12, 0.13), Vector3(0.12, 0.3, 0.06), Color("f4f1ea"))
			b.box(Vector3(-0.09, 0.1, 0.15), Vector3(0.08, 0.32, 0.04), top.darkened(0.15))
			b.box(Vector3(0.09, 0.1, 0.15), Vector3(0.08, 0.32, 0.04), top.darkened(0.15))
		"vest":
			b.cylinder(Vector3(0, 0.02, 0), 0.172 * build, 0.34, accent, "vc", 12, 1.1)
			b.box(Vector3(0, 0.1, 0.16), Vector3(0.1, 0.3, 0.03), top)
		"cardigan":
			b.box(Vector3(0, 0.03, 0.16), Vector3(0.05, 0.36, 0.03), top.lightened(0.25))
			for y in [0.1, 0.2, 0.3]:
				b.sphere(Vector3(0.0, y, 0.18), 0.018, Color("d9c9a0"), "vc", Vector3.ONE, 6)
		"hoodie":
			b.cylinder(Vector3(0, 0.36, -0.06), 0.13, 0.1, top.darkened(0.12), "vc", 10)
			b.box(Vector3(0, 0.02, 0.15), Vector3(0.2, 0.1, 0.04), top.darkened(0.1))
	match look.extra:
		"tie":
			b.box(Vector3(0, 0.12, 0.17), Vector3(0.05, 0.26, 0.02), accent)
		"bowtie":
			b.box(Vector3(0, 0.38, 0.16), Vector3(0.11, 0.05, 0.03), accent if look.kind != "waiter" else Color("1d1d22"))
		"flower":
			b.sphere(Vector3(-0.1, 0.3, 0.16), 0.035, accent, "vc", Vector3.ONE, 6)
		"necklace":
			b.sphere(Vector3(0, 0.33, 0.16), 0.025, Color("f3d27a"), "vc", Vector3.ONE, 6)
		"backpack":
			b.box(Vector3(0, 0.05, -0.2), Vector3(0.24, 0.3, 0.12), accent)
		"scarf":
			b.cylinder(Vector3(0, 0.36, 0), 0.13, 0.07, accent, "vc", 10)
	b.cylinder(Vector3(0, 0.4, 0), 0.06, 0.08, skin, "vc", 8)
	# Head: face, hair and hat around the neck.
	place.call(HEAD)
	var head_c: Vector3 = Vector3(0, 0.2, 0)
	b.sphere(head_c, 0.2, skin, "vc", Vector3(1.0, 1.02, 0.98), 14)
	b.sphere(head_c + Vector3(-0.2, 0.0, 0), 0.04, skin.darkened(0.08), "vc", Vector3(0.6, 1, 1), 6)
	b.sphere(head_c + Vector3(0.2, 0.0, 0), 0.04, skin.darkened(0.08), "vc", Vector3(0.6, 1, 1), 6)
	for x in [-0.07, 0.07]:
		b.sphere(head_c + Vector3(x, 0.02, 0.175), 0.032, Color("1a1410"), "vc", Vector3(0.8, 1.2, 0.5), 8)
		b.sphere(head_c + Vector3(x + 0.01, 0.035, 0.19), 0.008, Color.WHITE, "vc", Vector3.ONE, 4)
	b.sphere(head_c + Vector3(0, -0.04, 0.2), 0.03, skin.darkened(0.1), "vc", Vector3(0.9, 0.8, 0.8), 6)
	b.box(Vector3(0, head_c.y - 0.115, 0.175), Vector3(0.07, 0.015, 0.02), Color("6a2a20"))
	var hair: Color = Color(look.hair)
	match look.hair_style:
		"short", "messy":
			b.sphere(head_c + Vector3(0, 0.085, -0.05), 0.205, hair, "vc", Vector3(1.04, 0.74, 1.0), 12)
			if look.hair_style == "messy":
				for k in range(5):
					b.sphere(head_c + Vector3(-0.12 + k * 0.06, 0.2, 0.05), 0.05, hair, "vc", Vector3.ONE, 6)
		"slick":
			b.sphere(head_c + Vector3(0, 0.09, -0.05), 0.205, hair, "vc", Vector3(1.04, 0.7, 1.0), 12)
		"long", "ponytail", "bob":
			b.sphere(head_c + Vector3(0, 0.08, -0.06), 0.215, hair, "vc", Vector3(1.05, 0.8, 1.0), 12)
			if look.hair_style == "long":
				b.box(head_c + Vector3(0, -0.28, -0.1), Vector3(0.38, 0.34, 0.16), hair)
			elif look.hair_style == "ponytail":
				b.sphere(head_c + Vector3(0, 0.05, -0.25), 0.08, hair, "vc", Vector3(0.8, 1.6, 0.8), 8)
			else:
				b.box(head_c + Vector3(0, -0.12, -0.06), Vector3(0.44, 0.18, 0.3), hair)
		"bun":
			b.sphere(head_c + Vector3(0, 0.085, -0.05), 0.208, hair, "vc", Vector3(1.04, 0.76, 1.0), 12)
			b.sphere(head_c + Vector3(0, 0.2, -0.12), 0.09, hair, "vc", Vector3.ONE, 8)
		"bald":
			b.sphere(head_c + Vector3(0, -0.02, -0.04), 0.205, hair, "vc", Vector3(1.04, 0.5, 1.0), 10)
	match look.beard:
		"mustache":
			b.sphere(head_c + Vector3(-0.04, -0.075, 0.185), 0.035, hair, "vc", Vector3(1.4, 0.7, 0.8), 6)
			b.sphere(head_c + Vector3(0.04, -0.075, 0.185), 0.035, hair, "vc", Vector3(1.4, 0.7, 0.8), 6)
		"beard":
			b.sphere(head_c + Vector3(0, -0.11, 0.08), 0.15, hair, "vc", Vector3(1.0, 0.75, 0.9), 10)
		"stubble":
			b.sphere(head_c + Vector3(0, -0.1, 0.07), 0.155, skin.darkened(0.25), "vc", Vector3(1.0, 0.7, 0.9), 10)
	match look.hat:
		"sajkaca":
			# The Serbian šajkača: a boat-shaped cap folded down the middle.
			b.box(head_c + Vector3(0, 0.17, -0.01), Vector3(0.36, 0.11, 0.42), Color("5a5a3e"))
			b.prism(head_c + Vector3(0, 0.225, -0.01), Vector3(0.36, 0.08, 0.42), Color("4a4a32"), "vc", PI / 2.0)
		"flatcap":
			b.cylinder(head_c + Vector3(0, 0.15, -0.01), 0.21, 0.09, Color("5a4a3a"), "vc", 12, 0.9)
			b.box(head_c + Vector3(0, 0.15, 0.18), Vector3(0.3, 0.03, 0.14), Color("4a3a2c"))
		"beanie":
			b.sphere(head_c + Vector3(0, 0.11, -0.04), 0.212, Color(look.accent), "vc", Vector3(1.05, 0.7, 1.02), 12)
		"glasses":
			b.box(head_c + Vector3(0, 0.025, 0.2), Vector3(0.26, 0.06, 0.02), Color("15151a"))
	if look.extra == "veil":
		b.sphere(head_c + Vector3(0, 0.04, -0.02), 0.225, Color("15151a"), "vc", Vector3(1.05, 1.0, 1.05), 12)
		b.box(head_c + Vector3(0, -0.2, -0.08), Vector3(0.4, 0.3, 0.2), Color("15151a"))
	# Arms hang down from the shoulders; hands are spheres.
	for bone in [ARM_L, ARM_R]:
		place.call(bone)
		var sleeve: Color = top if look.top_style != "tshirt" else skin
		b.cylinder(Vector3(0, -0.36, 0), 0.066 * build, 0.38, sleeve, "vc", 8, 1.12)
		if look.top_style == "tshirt":
			b.cylinder(Vector3(0, -0.14, 0), 0.075 * build, 0.16, top, "vc", 8)
		b.sphere(Vector3(0, -0.4, 0), 0.066, skin, "vc", Vector3.ONE, 8)
	for bone in [LEG_L, LEG_R]:
		place.call(bone)
		b.cylinder(Vector3(0, -0.46, 0), 0.082 * build, 0.46, bottom if not dress else skin, "vc", 8, 1.1)
		b.box(Vector3(0, -0.5, 0.04), Vector3(0.12, 0.08, 0.2), Color(look.shoes))
	var mesh: ArrayMesh = b.mesh()
	_cache[key] = mesh
	return mesh

static func _prop_mesh(kind: String) -> ArrayMesh:
	var key: String = "prop:" + kind
	if _cache.has(key):
		return _cache[key]
	var b: Builder = Builder.new()
	match kind:
		"glass":
			b.cylinder(Vector3(0, 0, 0), 0.045, 0.12, Color("dfeff0"), "vc_gloss", 8)
			b.cylinder(Vector3(0, 0.0, 0), 0.04, 0.08, Color("e8a33a"), "vc_gloss", 8)
		"tray":
			b.cylinder(Vector3(0, 0, 0), 0.24, 0.02, Color("c9ced6"), "vc_metal", 14)
			b.cylinder(Vector3(0.06, 0.02, 0.03), 0.04, 0.14, Color("dfeff0"), "vc_gloss", 8)
			b.cylinder(Vector3(-0.08, 0.02, -0.04), 0.035, 0.18, Color("3d8a4f"), "vc_gloss", 8)
		"cloth":
			b.box(Vector3(0, -0.02, 0), Vector3(0.16, 0.04, 0.12), Color("f4f1ea"))
		"accordion":
			# A black accordion with a pearl keyboard and a brass grille, bellows open between.
			b.box(Vector3(-0.17, -0.22, 0), Vector3(0.1, 0.38, 0.22), Color("1d1d22"), "vc_gloss")
			b.box(Vector3(0.17, -0.22, 0), Vector3(0.1, 0.38, 0.22), Color("1d1d22"), "vc_gloss")
			for k in range(6):
				b.box(Vector3(-0.1 + k * 0.04, -0.21, 0), Vector3(0.035, 0.36, 0.21), Color("c0322c") if k % 2 == 0 else Color("2b2b30"))
			b.box(Vector3(-0.225, -0.22, 0.02), Vector3(0.02, 0.34, 0.16), Color("f4f1ea"), "vc_gloss")
			for k in range(7):
				b.box(Vector3(-0.236, -0.36 + k * 0.045, 0.02), Vector3(0.008, 0.025, 0.15), Color("1d1d22"))
			b.box(Vector3(0.225, -0.2, 0.0), Vector3(0.012, 0.22, 0.14), Color("d9a531"), "vc_metal")
		"guitar", "tamburica", "bass":
			var scale: float = {"guitar": 1.0, "tamburica": 0.75, "bass": 1.25}[kind]
			var wood: Color = {"guitar": Color("c98a4a"), "tamburica": Color("8a4a22"), "bass": Color("3a2416")}[kind]
			b.sphere(Vector3(0, 0, 0), 0.17 * scale, wood, "vc_gloss", Vector3(1.0, 1.25, 0.35), 12)
			b.sphere(Vector3(0, 0, 0.055 * scale), 0.05 * scale, Color("1a1410"), "vc", Vector3(1, 1, 0.2), 8)
			b.box(Vector3(0, 0.15 * scale, 0), Vector3(0.05, 0.5 * scale, 0.04), Color("2b1d14"), "vc_gloss")
		"violin":
			b.sphere(Vector3(0, 0, 0), 0.09, Color("8a3a1a"), "vc_gloss", Vector3(1.0, 1.4, 0.4), 10)
			b.box(Vector3(0, 0.15, 0), Vector3(0.03, 0.2, 0.03), Color("1a1410"))
		"mic":
			b.cylinder(Vector3(0, -0.04, 0), 0.02, 0.14, Color("2b2b30"), "vc_metal", 6)
			b.sphere(Vector3(0, 0.12, 0), 0.04, Color("8a8f98"), "vc_metal", Vector3.ONE, 8)
		"bow":
			b.box(Vector3(0, 0, 0), Vector3(0.012, 0.5, 0.012), Color("2b1d14"))
	var mesh: ArrayMesh = b.mesh()
	_cache[key] = mesh
	return mesh

# ---------------------------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------------------------

func setup(new_look: Dictionary) -> void:
	look = new_look
	var build: float = float(look.build)
	scale = Vector3.ONE * SIZE * (1.0 + (build - 1.0) * 0.5)
	rest = rest_positions(look)
	skeleton = Skeleton3D.new()
	var parents: Array = [-1, ROOT, BODY, BODY, BODY, BODY, BODY]
	for i in range(BONES.size()):
		skeleton.add_bone(BONES[i])
		skeleton.set_bone_parent(i, parents[i])
		skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, rest[i]))
		skeleton.set_bone_pose_position(i, rest[i])
	add_child(skeleton)
	var skin_mesh: MeshInstance3D = MeshInstance3D.new()
	skin_mesh.mesh = _mesh(look)
	skeleton.add_child(skin_mesh)
	skin_mesh.skeleton = NodePath("..")
	body = _attachment("body")
	prop = Node3D.new()
	prop.position = Vector3(0, -0.44, 0.04)
	_attachment("arm_r").add_child(prop)
	if str(look.instrument) != "":
		instrument = Node3D.new()
		body.add_child(instrument)
		var kind: String = look.instrument
		match kind:
			"accordion": instrument.position = Vector3(0, 0.3, 0.3)
			"violin":
				instrument.position = Vector3(-0.12, 0.42, 0.12)
				instrument.rotation = Vector3(0.3, 0, 1.1)
			"mic": instrument.position = Vector3(0, 0.6, 0.35)
			_:
				instrument.position = Vector3(0.02, 0.2, 0.2)
				instrument.rotation = Vector3(0, 0, -0.9)
		_add_mesh(instrument, _prop_mesh(kind))
		if kind == "mic":
			# The singer stands at a microphone on a stand.
			var stand: MeshInstance3D = MeshInstance3D.new()
			var cylinder: CylinderMesh = CylinderMesh.new()
			cylinder.top_radius = 0.015
			cylinder.bottom_radius = 0.015
			cylinder.height = 1.1
			stand.mesh = cylinder
			stand.position = Vector3(0, 0.55, 0.36)
			stand.material_override = Kit.material("vc_metal")
			add_child(stand)
		if kind == "violin":
			var bow: Node3D = Node3D.new()
			prop.add_child(bow)
			bow.position = Vector3(0, 0.04, 0.0)
			bow.rotation = Vector3(0, 0, 1.2)
			_add_mesh(bow, _prop_mesh("bow"))
	brows = MeshInstance3D.new()
	var brow_mesh: BoxMesh = BoxMesh.new()
	brow_mesh.size = Vector3(0.24, 0.025, 0.02)
	brows.mesh = brow_mesh
	brows.position = Vector3(0, 0.28, 0.185)
	brows.material_override = Kit.material("vc")
	brows.visible = false
	_attachment("head").add_child(brows)
	phase = randf() * TAU
	play("idle")

func _attachment(bone_name: String) -> Node3D:
	var attach: BoneAttachment3D = BoneAttachment3D.new()
	attach.bone_name = bone_name
	skeleton.add_child(attach)
	return attach

func _add_mesh(parent: Node3D, mesh: Mesh) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	parent.add_child(node)

## Hold something in the right hand: "", "glass", "tray" or "cloth".
func hold(kind: String) -> void:
	if kind == holding:
		return
	holding = kind
	for child in prop.get_children():
		child.queue_free()
	if kind != "":
		_add_mesh(prop, _prop_mesh(kind))

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
	if brows != null:
		brows.visible = name == "angry"

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
	scale = Vector3.ONE * 0.2
	create_tween().tween_property(self, "scale", Vector3.ONE * (1.0 + (float(look.get("build", 1.0)) - 1.0) * 0.5), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func fade_and_free(_duration: float = 0.3) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
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

func _pose() -> void:
	var t: float = anim_time
	var swing: float = 0.0
	var bob: float = 0.0
	var lean: float = 0.0
	var arms: Vector2 = Vector2.ZERO
	var spread: float = 0.08
	var sit: bool = false
	var head_tilt: float = 0.0
	var head_turn: float = 0.0
	match current:
		"walk", "carry":
			swing = sin(t * 10.0) * 0.55
			bob = absf(sin(t * 10.0)) * 0.04
			arms = Vector2(-swing * 0.8, swing * 0.8)
		"idle", "carry_idle":
			bob = sin(t * 2.0 + phase) * 0.008
			head_turn = sin(t * 0.7 + phase) * 0.25
		"sit":
			sit = true
			head_turn = sin(t * 0.9 + phase) * 0.35
			arms = Vector2(-0.5, -0.5)
		"drink":
			sit = true
			arms = Vector2(-0.5, -1.4 - sin(t * 3.0) * 0.4)
			head_tilt = -0.25
		"happy":
			sit = true
			bob = absf(sin(t * 6.0 + phase)) * 0.03
			arms = Vector2(-0.6 - absf(sin(t * 6.0)) * 0.6, -0.6 - absf(sin(t * 6.0 + 1.5)) * 0.6)
			head_tilt = sin(t * 6.0) * 0.12
		"angry":
			sit = true
			arms = Vector2(-0.9, -0.9)
			spread = 0.35
			head_tilt = 0.12 + sin(t * 9.0) * 0.06
			head_turn = sin(t * 4.0) * 0.3
		"dance":
			bob = absf(sin(t * 7.0 + phase)) * 0.12
			swing = sin(t * 7.0 + phase) * 0.35
			arms = Vector2(-2.6 + sin(t * 7.0) * 0.4, -2.6 - sin(t * 7.0) * 0.4)
			spread = 0.45
			lean = sin(t * 3.5 + phase) * 0.15
			head_tilt = sin(t * 7.0) * 0.15
		"play":
			bob = absf(sin(t * 6.0 + phase)) * 0.025
			head_tilt = sin(t * 3.0) * 0.12
			arms = Vector2(-0.9 + sin(t * 8.0) * 0.25, -1.0 - sin(t * 8.0) * 0.25)
		"wipe":
			arms = Vector2(-0.3, -1.1)
			bob = sin(t * 2.0) * 0.005
	if current in ["carry", "carry_idle"]:
		arms.y = -1.45
	var legs: Vector2 = Vector2(swing, -swing)
	if sit:
		legs = Vector2(-1.45, -1.45)
		bob = SEAT_HEIGHT / scale.y - HIP
	var arm_l: Vector3 = Vector3(arms.x, 0, -spread)
	var arm_r: Vector3 = Vector3(arms.y, 0, spread)
	if instrument != null:
		var playing: bool = current == "play"
		match str(look.instrument):
			"accordion":
				instrument.scale = Vector3(1.0 + (sin(anim_time * 4.0) * 0.18 if playing else 0.0), 1, 1)
				arm_l = Vector3(-1.1, 0, -0.5)
				arm_r = Vector3(-1.1, 0, 0.5)
			"mic":
				arm_r = Vector3(-1.2 if playing else -0.3, 0, 0.1)
			"violin":
				arm_l = Vector3(-1.3, 0, -0.6)
				arm_r = Vector3(-1.0, sin(anim_time * 9.0) * 0.35 if playing else 0.0, 0.3)
			_:
				arm_l = Vector3(-1.0, 0, -0.7)
				arm_r = Vector3(-0.7 + (sin(anim_time * 14.0) * 0.25 if playing else 0.0), 0, 0.2)
	skeleton.set_bone_pose_position(BODY, rest[BODY] + Vector3(0, bob, 0))
	skeleton.set_bone_pose_rotation(BODY, Quaternion(Vector3(0, 0, 1), lean))
	skeleton.set_bone_pose_rotation(HEAD, Quaternion.from_euler(Vector3(head_tilt, head_turn, 0)))
	skeleton.set_bone_pose_rotation(ARM_L, Quaternion.from_euler(arm_l))
	skeleton.set_bone_pose_rotation(ARM_R, Quaternion.from_euler(arm_r))
	skeleton.set_bone_pose_rotation(LEG_L, Quaternion(Vector3(1, 0, 0), legs.x))
	skeleton.set_bone_pose_rotation(LEG_R, Quaternion(Vector3(1, 0, 0), legs.y))
