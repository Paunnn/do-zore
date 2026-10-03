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
const HIP = 0.42
## Characters are drawn a little larger than life so they read on a phone screen.
const SIZE = 1.3
## Height of a chair seat: a seated character's hips rest here whatever its size.
const SEAT_HEIGHT = 0.5
const SKIN = ["f2c7a2", "e8b48b", "d99b72", "b97a52", "8a5638"]
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
		"top_cell": "cotton", "bottom_cell": "wool",
	}
	match kind:
		"penzioner":
			look.hair = ["c9c4ba", "e8e4dc", "9a948a"][rng.randi() % 3]
			look.top = ["7a6a52", "5a6a4a", "6e5a44", "4a5568"][rng.randi() % 4]
			look.top_style = "cardigan"
			look.top_cell = "knit"
			look.bottom = ["4a4a52", "5a4a3a"][rng.randi() % 2]
			if female:
				look.hair_style = "bun"
				look.extra = "marama"
				look.accent = ["8a2f3a", "3a5a8a", "6a4a7a"][rng.randi() % 3]
			else:
				look.hat = ["sajkaca", "flatcap", ""][rng.randi() % 3]
				look.beard = "mustache"
				look.hair_style = "bald" if rng.randf() < 0.5 else "short"
		"studenti":
			look.top = ["e85a4f", "3e8ed0", "f2b83a", "4fae6a", "9a5ad0", "f4f1ea"][rng.randi() % 6]
			look.top_style = "hoodie"
			look.top_cell = "fleece"
			look.bottom_cell = "denim"
			look.bottom = ["3a5a8a", "2b2f45", "5a6a7a"][rng.randi() % 3]
			look.shoes = ["f4f1ea", "e85a4f", "2b2b30"][rng.randi() % 3]
			look.hat = "beanie" if rng.randf() < 0.3 else ""
			look.accent = ["2b2f45", "c0322c", "3e8ed0"][rng.randi() % 3]
			look.extra = "backpack" if rng.randf() < 0.4 else ""
			if variant % 3 == 2:
				look.top_style = "shirt"
				look.top_cell = "stripes" if female else "plaid"
			if female:
				look.hair_style = ["long", "ponytail", "bob"][rng.randi() % 3]
			else:
				look.hair_style = ["short", "messy"][rng.randi() % 2]
				look.beard = "stubble" if rng.randf() < 0.3 else ""
		"ozalosceni":
			look.top = "1d1d22"
			look.top_style = "dress" if female else "suit"
			look.top_cell = "satin" if female else "wool"
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
				look.top_cell = "satin"
				look.hair_style = ["bun", "long"][rng.randi() % 2]
				look.extra = "necklace"
			else:
				look.top = ["2b2f45", "4a4a52", "1d2433"][rng.randi() % 3]
				look.top_style = "suit"
				look.top_cell = "wool"
				look.extra = "flower"
				look.accent = ["c0322c", "f2b83a"][rng.randi() % 2]
				look.beard = ["", "mustache"][rng.randi() % 2]
		"biznismen":
			look.top = ["1d2433", "2b2b33", "3a3a44"][rng.randi() % 3]
			look.top_style = "suit"
			look.top_cell = "pinstripe" if variant % 2 == 0 else "wool"
			look.accent = ["c0322c", "3e8ed0", "d9a531"][rng.randi() % 3]
			look.extra = "tie"
			look.hair_style = "slick" if not female else "bob"
			look.hat = "glasses" if rng.randf() < 0.4 else ""
		"waiter":
			look.top_style = "vest"
			look.top = "f4f1ea"
			look.accent = "1d1d22"
			look.extra = "apron"
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
					look.top_cell = "satin"
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
	return [Vector3.ZERO, Vector3(0, HIP, 0), Vector3(0, 0.4, 0), Vector3(-0.235 * build, 0.33, 0), Vector3(0.235 * build, 0.33, 0),
		Vector3(-0.095, 0, 0), Vector3(0.095, 0, 0)]

## The fabric, hair and skin cells of the people atlas (tools/art/build_textures.py), row by row.
const CELLS = ["skin", "cotton", "knit", "denim", "wool", "pinstripe", "hair", "leather",
	"fleece", "satin", "linen", "floral", "plaid", "stripes", "felt", "lace"]

## Where a fabric sits in the atlas, inset a little so mipmaps do not bleed between cells.
static func cell(name: String) -> Rect2:
	var index: int = maxi(0, CELLS.find(name))
	var pad: float = 6.0 / 1024.0
	return Rect2(Vector2(index % 4, index / 4) * 0.25 + Vector2(pad, pad), Vector2(0.25 - 2.0 * pad, 0.25 - 2.0 * pad))

## The face's centre on the head bone and its radius (chibi: the head is about 40 % of the height).
const HEAD_CENTRE = Vector3(0, 0.25, 0)
const HEAD_R = 0.27

## One skinned mesh per look: every part follows its bone and every part uses the one matte
## vertex-colour material, so a character is a single draw call.
static func _mesh(look: Dictionary) -> ArrayMesh:
	var key: String = JSON.stringify(look)
	if _cache.has(key):
		return _cache[key]
	var skin: Color = Color(look.skin)
	var top: Color = Color(look.top)
	var accent: Color = Color(look.accent)
	var bottom: Color = Color(look.bottom)
	var hair: Color = Color(look.hair)
	var build: float = float(look.build)
	var rests: Array = rest_positions(look)
	var b: Builder = Builder.new()
	b.force_key = "people"
	var place: Callable = func(bone: int) -> void:
		var at: Vector3 = Vector3.ZERO
		var current: int = bone
		var parents: Array = [-1, ROOT, BODY, BODY, BODY, BODY, BODY]
		while current >= 0:
			at += rests[current]
			current = parents[current]
		b.bone = bone
		b.offset = Transform3D(Basis.IDENTITY, at)
	var white: Color = Color("f6f3ec")
	var dress: bool = look.top_style == "dress"
	# Body: a rounded bean of a torso over the hips.
	place.call(BODY)
	if dress:
		b.cell = cell(look.top_cell)
		b.cylinder(Vector3(0, -0.3, 0), 0.27, 0.42, top.darkened(0.06), "vc", 16, 0.55)
	else:
		b.cell = cell(look.bottom_cell)
		b.sphere(Vector3(0, 0.03, 0), 0.19, bottom, "vc", Vector3(1.05 * build, 0.72, 0.9), 8)
	var torso: Color = accent if look.top_style == "vest" else top
	b.cell = cell("wool" if look.top_style == "vest" else look.top_cell)
	b.sphere(Vector3(0, 0.2, 0), 0.2, torso, "vc", Vector3(1.0 * build, 1.18, 0.86), 10)
	b.cell = cell("skin")
	b.cylinder(Vector3(0, 0.37, 0), 0.075, 0.07, skin, "vc", 8)
	b.cell = cell("cotton")
	var chest: float = 0.172
	match look.top_style:
		"shirt":
			for y in [0.12, 0.22, 0.31]:
				b.sphere(Vector3(0, y, chest + 0.005), 0.016, top.darkened(0.3), "vc", Vector3.ONE, 6)
			_collar(b, top.lightened(0.15), chest)
		"suit":
			b.box(Vector3(0, 0.2, chest - 0.01), Vector3(0.1, 0.19, 0.02), white)
			for side in [-1.0, 1.0]:
				b.box_xf(Transform3D(Basis(Vector3.FORWARD, side * 0.32), Vector3(side * 0.06, 0.22, chest - 0.005)), Vector3(0.05, 0.2, 0.025), top.darkened(0.22))
			b.sphere(Vector3(0, 0.1, chest + 0.01), 0.016, top.darkened(0.4), "vc", Vector3.ONE, 6)
			_collar(b, white, chest)
		"vest":
			b.box(Vector3(0, 0.2, chest - 0.008), Vector3(0.09, 0.2, 0.02), top)
			for y in [0.08, 0.16]:
				b.sphere(Vector3(0.03, y, chest + 0.008), 0.015, Color("d9a531"), "vc", Vector3.ONE, 6)
			_collar(b, top, chest)
		"cardigan":
			b.box(Vector3(0, 0.0, chest - 0.005), Vector3(0.05, 0.4, 0.025), top.lightened(0.25))
			for y in [0.1, 0.19, 0.28]:
				b.sphere(Vector3(0.0, y, chest + 0.012), 0.018, Color("d9c9a0"), "vc", Vector3.ONE, 6)
			b.box(Vector3(0.1, 0.05, chest - 0.02), Vector3(0.09, 0.07, 0.03), top.darkened(0.12))
		"hoodie":
			b.sphere(Vector3(0, 0.36, -0.12), 0.13, top.darkened(0.14), "vc", Vector3(1.3, 0.6, 0.8), 8)
			b.box(Vector3(0, 0.03, chest - 0.02), Vector3(0.22, 0.1, 0.04), top.darkened(0.1))
			for x in [-0.04, 0.04]:
				b.cylinder(Vector3(x, 0.2, chest + 0.005), 0.007, 0.14, white, "vc", 4)
		"tshirt":
			b.box(Vector3(0, 0.33, chest - 0.02), Vector3(0.14, 0.04, 0.03), top.darkened(0.2))
	match look.extra:
		"tie":
			b.box(Vector3(0, 0.33, chest + 0.008), Vector3(0.05, 0.035, 0.02), accent.darkened(0.15))
			b.box_xf(Transform3D(Basis.IDENTITY, Vector3(0, 0.1, chest + 0.01)), Vector3(0.045, 0.23, 0.015), accent)
		"bowtie", "apron":
			for x in [-0.035, 0.035]:
				b.sphere(Vector3(x, 0.355, chest + 0.01), 0.032, Color("1d1d22") if look.kind in ["waiter", "bartender"] or look.instrument != "" else accent, "vc", Vector3(1.2, 0.8, 0.5), 6)
			if look.extra == "apron":
				# The konobar's long white apron, tied at the waist.
				b.cell = cell("linen")
				b.cylinder(Vector3(0, 0.05, 0), 0.205, 0.04, white, "vc", 10)
				b.box(Vector3(0, -0.33, 0.13), Vector3(0.34, 0.4, 0.03), white)
		"flower":
			b.sphere(Vector3(-0.1, 0.3, chest + 0.01), 0.035, accent, "vc", Vector3.ONE, 6)
			b.sphere(Vector3(-0.1, 0.3, chest + 0.03), 0.015, Color("f3d27a"), "vc", Vector3.ONE, 5)
		"necklace":
			for k in range(7):
				var a: float = -0.9 + k * 0.3
				b.sphere(Vector3(sin(a) * 0.09, 0.33 - cos(a) * 0.05 + 0.05, chest + 0.01 - absf(sin(a)) * 0.02), 0.014, Color("f3d27a"), "vc", Vector3.ONE, 5)
		"backpack":
			b.box(Vector3(0, 0.06, -0.2), Vector3(0.26, 0.3, 0.12), accent)
			b.box(Vector3(0, 0.22, -0.27), Vector3(0.18, 0.08, 0.03), accent.darkened(0.15))
			for x in [-0.08, 0.08]:
				b.box(Vector3(x, 0.08, 0.0), Vector3(0.03, 0.3, 0.37), accent.darkened(0.25))
		"scarf":
			b.cylinder(Vector3(0, 0.33, 0), 0.12, 0.07, accent, "vc", 8)
	# Head: a big round face with eyes, brows, cheeks and a smile; hair, beards and hats over it.
	place.call(HEAD)
	b.cell = cell("skin")
	var hc: Vector3 = HEAD_CENTRE
	var r: float = HEAD_R
	b.sphere(hc, r, skin, "vc", Vector3(1.0, 0.96, 0.95), 12)
	for side in [-1.0, 1.0]:
		b.sphere(hc + Vector3(side * 0.255, -0.01, -0.01), 0.05, skin.darkened(0.06), "vc", Vector3(0.5, 1.0, 0.8), 6)
		var eye: Vector3 = hc + Vector3(side * 0.095, 0.0, 0.228)
		b.sphere(eye, 0.042, Color("231812"), "vc", Vector3(0.85, 1.25, 0.5), 6)
		b.sphere(eye + Vector3(0.014, 0.022, 0.016), 0.013, Color.WHITE, "vc", Vector3.ONE, 5)
		b.box_xf(Transform3D(Basis(Vector3.FORWARD, side * -0.12), eye + Vector3(0, 0.075, 0.0)), Vector3(0.075, 0.018, 0.02), hair.darkened(0.15) if look.hair_style != "bald" else skin.darkened(0.35))
		b.sphere(hc + Vector3(side * 0.155, -0.075, 0.19), 0.042, skin.lerp(Color("ff8a7a"), 0.45), "vc", Vector3(1.15, 0.7, 0.35), 6)
	b.sphere(hc + Vector3(0, -0.04, 0.255), 0.024, skin.darkened(0.07), "vc", Vector3.ONE, 6)
	var lips: Color = Color("b8434a") if look.female else Color("7a3428")
	b.box(hc + Vector3(0, -0.11, 0.222), Vector3(0.075, 0.018, 0.02), lips)
	for side in [-1.0, 1.0]:
		b.box_xf(Transform3D(Basis(Vector3.FORWARD, side * 0.5), hc + Vector3(side * 0.043, -0.1, 0.221)), Vector3(0.022, 0.014, 0.018), lips)
	b.cell = cell("hair")
	var cap: Callable = func(lift: float, stretch: Vector3) -> void:
		b.sphere(hc + Vector3(0, lift, -0.07), r + 0.035, hair, "vc", stretch, 10)
	# A fringe: one smooth band over the forehead, swept to one side for some styles.
	var bangs: Callable = func(count: int, low: float) -> void:
		var sweep: float = 0.03 * (count % 2)
		b.sphere(hc + Vector3(sweep, low + 0.17, 0.13), 0.2, hair, "vc", Vector3(1.22, 0.42, 0.62), 8)
	match look.hair_style:
		"short":
			cap.call(0.06, Vector3(1.03, 0.92, 1.0))
			bangs.call(3, 0.0)
		"messy":
			cap.call(0.06, Vector3(1.03, 0.92, 1.0))
			bangs.call(3, -0.01)
			for k in range(6):
				var a: float = k * TAU / 6.0
				b.sphere(hc + Vector3(cos(a) * 0.12, 0.27, sin(a) * 0.12 - 0.04), 0.07, hair, "vc", Vector3(0.8, 1.2, 0.8), 6)
		"slick":
			cap.call(0.07, Vector3(1.03, 0.88, 1.0))
			b.sphere(hc + Vector3(0.06, 0.2, 0.12), 0.11, hair, "vc", Vector3(1.4, 0.45, 0.9), 6)
		"long", "ponytail", "bob":
			cap.call(0.06, Vector3(1.04, 0.94, 1.0))
			bangs.call(4, 0.0)
			if look.hair_style == "long":
				b.sphere(hc + Vector3(0, -0.14, -0.1), 0.26, hair, "vc", Vector3(1.05, 1.25, 0.72), 8)
				for side in [-1.0, 1.0]:
					b.sphere(hc + Vector3(side * 0.22, -0.13, 0.05), 0.085, hair, "vc", Vector3(0.75, 1.9, 0.85), 6)
			elif look.hair_style == "ponytail":
				b.sphere(hc + Vector3(0, 0.12, -0.27), 0.04, accent, "vc", Vector3.ONE, 6)
				b.sphere(hc + Vector3(0, -0.03, -0.32), 0.1, hair, "vc", Vector3(0.8, 1.7, 0.8), 6)
			else:
				for side in [-1.0, 1.0]:
					b.sphere(hc + Vector3(side * 0.215, -0.07, 0.02), 0.11, hair, "vc", Vector3(0.72, 1.3, 1.1), 6)
				b.sphere(hc + Vector3(0, -0.07, -0.11), 0.24, hair, "vc", Vector3(1.08, 0.85, 0.8), 8)
		"bun":
			cap.call(0.06, Vector3(1.03, 0.9, 1.0))
			bangs.call(2, 0.01)
			b.sphere(hc + Vector3(0, 0.27, -0.12), 0.11, hair, "vc", Vector3.ONE, 8)
		"bald":
			b.sphere(hc + Vector3(0, -0.02, -0.08), r + 0.03, hair, "vc", Vector3(1.03, 0.55, 1.0), 8)
	match look.beard:
		"mustache":
			for side in [-1.0, 1.0]:
				b.sphere(hc + Vector3(side * 0.045, -0.075, 0.245), 0.038, hair, "vc", Vector3(1.4, 0.65, 0.7), 6)
		"beard":
			b.sphere(hc + Vector3(0, -0.15, 0.08), 0.2, hair, "vc", Vector3(1.0, 0.68, 0.85), 8)
			b.sphere(hc + Vector3(0, -0.075, 0.24), 0.04, hair, "vc", Vector3(1.6, 0.6, 0.7), 6)
		"stubble":
			b.sphere(hc + Vector3(0, -0.12, 0.06), 0.215, skin.darkened(0.2), "vc", Vector3(1.0, 0.62, 0.9), 8)
	b.cell = cell("felt")
	match look.hat:
		"sajkaca":
			# The Serbian šajkača: a grey-green cap, boat-shaped and folded down the middle.
			var cloth: Color = Color("5e5d40")
			b.box(hc + Vector3(0, 0.15, -0.02), Vector3(0.44, 0.1, 0.52), cloth)
			b.prism(hc + Vector3(0, 0.25, -0.02), Vector3(0.44, 0.1, 0.5), cloth.darkened(0.12), "vc", PI / 2.0)
			b.box(hc + Vector3(0, 0.19, 0.24), Vector3(0.3, 0.06, 0.03), cloth.darkened(0.2))
		"flatcap":
			b.cylinder(hc + Vector3(0, 0.17, -0.02), r + 0.01, 0.1, Color("5a4a3a"), "vc", 14, 0.85)
			b.box(hc + Vector3(0, 0.18, 0.22), Vector3(0.32, 0.03, 0.14), Color("4a3a2c"))
		"beanie":
			b.cell = cell("knit")
			b.sphere(hc + Vector3(0, 0.1, -0.04), r + 0.035, accent, "vc", Vector3(1.04, 0.78, 1.02), 10)
			b.cylinder(hc + Vector3(0, 0.08, -0.03), r + 0.03, 0.07, accent.darkened(0.15), "vc", 10)
			b.sphere(hc + Vector3(0, 0.33, -0.04), 0.06, white, "vc", Vector3.ONE, 6)
		"glasses":
			var shades: bool = look.kind == "bouncer"
			for side in [-1.0, 1.0]:
				var lens: Transform3D = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), hc + Vector3(side * 0.095, 0.0, 0.24))
				b.cylinder_xf(lens, 0.06, 0.012, Color("15151a"), "vc", 8)
				if not shades:
					b.cylinder_xf(lens * Transform3D(Basis.IDENTITY, Vector3(0, 0.008, 0)), 0.047, 0.01, Color("b9cddb"), "vc", 8)
			b.box(hc + Vector3(0, 0.0, 0.25), Vector3(0.08, 0.015, 0.012), Color("15151a"))
	match look.extra:
		"veil":
			b.cell = cell("lace")
			b.sphere(hc + Vector3(0, 0.05, -0.09), r + 0.035, Color("15151a"), "vc", Vector3(1.04, 0.96, 1.0), 10)
			b.box(hc + Vector3(0, -0.36, -0.13), Vector3(0.44, 0.38, 0.16), Color("15151a"))
		"marama":
			# Grandma's headscarf, knotted under the chin, in a folk print.
			b.cell = cell("floral")
			b.sphere(hc + Vector3(0, 0.05, -0.09), r + 0.035, accent, "vc", Vector3(1.05, 0.98, 1.0), 10)
			b.sphere(hc + Vector3(0, -0.25, 0.14), 0.05, accent.darkened(0.12), "vc", Vector3(1.2, 0.8, 0.8), 6)
			for k in range(5):
				b.sphere(hc + Vector3(-0.16 + k * 0.08, 0.2, 0.17), 0.02, Color("f3e8cf"), "vc", Vector3.ONE, 5)
	# Arms hang down from the shoulders; round hands.
	for bone in [ARM_L, ARM_R]:
		place.call(bone)
		var sleeve: Color = top if look.top_style != "tshirt" else skin
		b.cell = cell(look.top_cell if look.top_style != "tshirt" else "skin")
		b.sphere(Vector3(0, -0.01, 0), 0.075 * build, top, "vc", Vector3.ONE, 6)
		b.cylinder(Vector3(0, -0.27, 0), 0.062 * build, 0.27, sleeve, "vc", 8, 1.18)
		if look.top_style == "tshirt":
			b.cell = cell("cotton")
			b.cylinder(Vector3(0, -0.11, 0), 0.075 * build, 0.11, top, "vc", 6)
		b.cylinder(Vector3(0, -0.27, 0), 0.066 * build, 0.035, sleeve.darkened(0.12), "vc", 6)
		b.cell = cell("skin")
		b.sphere(Vector3(0, -0.31, 0), 0.068, skin, "vc", Vector3.ONE, 6)
	# Short legs with round shoes.
	for bone in [LEG_L, LEG_R]:
		place.call(bone)
		b.cell = cell(look.bottom_cell if not dress else "skin")
		b.cylinder(Vector3(0, -0.36, 0), 0.08 * build, 0.36, bottom if not dress else skin, "vc", 8, 1.12)
		b.cell = cell("leather")
		b.sphere(Vector3(0, -0.375, 0.045), 0.085, Color(look.shoes), "vc", Vector3(1.0, 0.58, 1.5), 6)
	var mesh: ArrayMesh = b.mesh()
	_cache[key] = mesh
	return mesh

## A shirt collar: two points either side of the neck.
static func _collar(b: Builder, colour: Color, chest: float) -> void:
	for side in [-1.0, 1.0]:
		b.box_xf(Transform3D(Basis(Vector3.FORWARD, side * 0.6), Vector3(side * 0.045, 0.33, chest - 0.01)), Vector3(0.06, 0.07, 0.02), colour)

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
	scale = full_scale()
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
	prop.position = Vector3(0, -0.33, 0.05)
	_attachment("arm_r").add_child(prop)
	if str(look.instrument) != "":
		instrument = Node3D.new()
		body.add_child(instrument)
		var kind: String = look.instrument
		match kind:
			"accordion": instrument.position = Vector3(0, 0.22, 0.27)
			"violin":
				instrument.position = Vector3(-0.15, 0.34, 0.14)
				instrument.rotation = Vector3(0.3, 0, 1.1)
			"mic": instrument.position = Vector3(0, 0.55, 0.37)
			_:
				instrument.position = Vector3(0.02, 0.14, 0.24)
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
	brow_mesh.size = Vector3(0.22, 0.03, 0.02)
	brows.mesh = brow_mesh
	brows.position = HEAD_CENTRE + Vector3(0, 0.08, 0.235)
	brows.material_override = Kit.material("vc")
	brows.visible = false
	_attachment("head").add_child(brows)
	phase = randf() * TAU
	play("idle")

## The size a character is drawn at: larger than life, and broader for a big build.
func full_scale() -> Vector3:
	return Vector3.ONE * SIZE * (1.0 + (float(look.get("build", 1.0)) - 1.0) * 0.5)

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
	create_tween().tween_property(self, "scale", full_scale(), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
