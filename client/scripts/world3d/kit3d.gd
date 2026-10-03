extends RefCounted
## Low-poly 3D kit: shared materials, unit primitives and lights (see builder.gd for merging).
##
## Everything in the city and the venues is made of boxes, cylinders, spheres, prisms and quads
## coloured per vertex. A Builder collects them per material and per spatial chunk and commits
## one ArrayMesh for each, which keeps draw calls low on phones and keeps every chunk under the
## Compatibility renderer's per-object light limit.
##
## Material keys:
##   "vc"            matte, vertex-coloured
##   "vc_gloss"      glossy (varnished wood, bottles, cars)
##   "vc_metal"      brass and steel
##   "glow:RRGGBB:E" emissive colour E times (lamps, lit windows)
##   "tex:NAME:S"    world-mapped tiling texture NAME scaled by S, tinted by vertex colour (with
##                   NAME_normal and NAME_rough relief and shine maps when they exist)
##   "uv:NAME"       texture mapped by the quad's own UVs (rugs, paintings, signs)
##   "add:NAME"      unshaded additive (light pools, glows)
##   "blend:NAME"    unshaded alpha blend (contact shadows)
##   "water"         animated river surface
const TEX = "res://assets/textures/"
const WORLD_SHADER = preload("res://shaders/world.gdshader")

static var _materials: Dictionary = {}
static var _units: Dictionary = {}

## A texture by name: drawn ones are PNG, painted-over scans JPG.
static func texture(name: String) -> Texture2D:
	for extension in [".png", ".jpg"]:
		var path: String = TEX + name + extension
		if ResourceLoader.exists(path):
			return load(path)
	return null

static func material(key: String) -> Material:
	if _materials.has(key):
		return _materials[key]
	var parts: PackedStringArray = key.split(":")
	var result: Material
	match parts[0]:
		"water":
			result = _water()
		"glowvc":
			result = _glow()
		"add", "blend":
			var unshaded: StandardMaterial3D = StandardMaterial3D.new()
			unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			unshaded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			unshaded.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if parts[0] == "add" else BaseMaterial3D.BLEND_MODE_MIX
			unshaded.albedo_texture = texture(parts[1])
			unshaded.vertex_color_use_as_albedo = true
			unshaded.vertex_color_is_srgb = true
			unshaded.no_depth_test = false
			unshaded.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			unshaded.render_priority = 1
			result = unshaded
		"glow":
			var standard: StandardMaterial3D = StandardMaterial3D.new()
			standard.albedo_color = Color(parts[1]).darkened(0.3)
			standard.emission_enabled = true
			standard.emission = Color(parts[1])
			standard.emission_energy_multiplier = float(parts[2]) if parts.size() > 2 else 1.5
			result = standard
		_:
			# Everything else is painted and toon-lit (shaders/world.gdshader).
			var toon: ShaderMaterial = ShaderMaterial.new()
			toon.shader = WORLD_SHADER
			match parts[0]:
				"vc_gloss":
					toon.set_shader_parameter("gloss", 0.8)
				"vc_metal":
					toon.set_shader_parameter("gloss", 0.6)
					toon.set_shader_parameter("metal", 1.0)
				"tex":
					toon.set_shader_parameter("mode", 1)
					toon.set_shader_parameter("albedo_tex", texture(parts[1]))
					toon.set_shader_parameter("tex_scale", float(parts[2]) if parts.size() > 2 else 0.5)
				"uv":
					toon.set_shader_parameter("mode", 2)
					toon.set_shader_parameter("albedo_tex", texture(parts[1]))
			result = toon
	_materials[key] = result
	return result

## Every lamp, lit window and candle shares this material: the vertex colour carries the hue and
## its alpha the brightness, so all of them merge into one mesh per chunk.
static func _glow() -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_back;
void fragment() {
	vec3 colour = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = colour * COLOR.a * 5.0;
}
"""
	var glow: ShaderMaterial = ShaderMaterial.new()
	glow.shader = shader
	return glow

static func _water() -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec4 deep : source_color = vec4(0.05, 0.11, 0.22, 1.0);
uniform vec4 shallow : source_color = vec4(0.13, 0.26, 0.42, 1.0);
uniform vec4 sparkle : source_color = vec4(1.0, 0.86, 0.55, 1.0);
varying vec3 world;
void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(world.x * 0.7 + TIME * 1.2) * 0.03 + cos(world.z * 0.6 + TIME * 0.9) * 0.03;
}
void fragment() {
	// A calm surface: a slow swell in the colour and thin moving ripples catching the lights.
	float swell = sin(world.x * 0.33 + TIME * 0.4) * sin(world.z * 0.29 - TIME * 0.3);
	float ripple = sin((world.x + world.z) * 2.6 + TIME * 1.5 + sin(world.x * 0.8 - world.z * 0.6) * 1.6);
	ALBEDO = mix(deep.rgb, shallow.rgb, 0.5 + 0.14 * swell);
	ROUGHNESS = 0.2;
	SPECULAR = 0.6;
	float patch = sin(world.x * 0.21 + TIME * 0.25) * sin(world.z * 0.17 - TIME * 0.2);
	EMISSION = sparkle.rgb * smoothstep(0.99, 1.0, ripple) * smoothstep(0.25, 0.8, patch) * 0.3;
}
"""
	var water: ShaderMaterial = ShaderMaterial.new()
	water.shader = shader
	return water

## Unit primitives (size 1, base at origin for boxes/cylinders) cached as mesh arrays.
static func unit(kind: String, segments: int = 12, taper: float = 1.0) -> Array:
	var key: String = "%s:%d:%.3f" % [kind, segments, taper]
	if _units.has(key):
		return _units[key]
	var mesh: PrimitiveMesh
	var lift: float = 0.5
	match kind:
		"box":
			mesh = BoxMesh.new()
		"cylinder":
			var cylinder: CylinderMesh = CylinderMesh.new()
			cylinder.radial_segments = segments
			cylinder.rings = 1
			cylinder.height = 1.0
			cylinder.bottom_radius = 1.0
			cylinder.top_radius = taper
			mesh = cylinder
		"sphere":
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radial_segments = segments
			sphere.rings = maxi(4, segments / 2)
			sphere.radius = 1.0
			sphere.height = 2.0
			mesh = sphere
			lift = 0.0
		"prism":
			var prism: PrismMesh = PrismMesh.new()
			prism.left_to_right = taper
			mesh = prism
		"quad":
			var plane: PlaneMesh = PlaneMesh.new()
			plane.size = Vector2.ONE
			mesh = plane
			lift = 0.0
		"grid":
			var water_plane: PlaneMesh = PlaneMesh.new()
			water_plane.size = Vector2.ONE
			water_plane.subdivide_width = segments
			water_plane.subdivide_depth = segments
			mesh = water_plane
			lift = 0.0
	var arrays: Array = mesh.get_mesh_arrays()
	if lift != 0.0:
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		arrays[Mesh.ARRAY_VERTEX] = Transform3D(Basis.IDENTITY, Vector3(0, lift, 0)) * verts
	_units[key] = arrays
	return arrays

static func omni(parent: Node3D, position: Vector3, color: Color, energy: float, reach: float, shadows: bool = false) -> OmniLight3D:
	var light: OmniLight3D = OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.4
	light.shadow_enabled = shadows
	parent.add_child(light)
	return light
