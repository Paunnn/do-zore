extends RefCounted
## Collects coloured primitives and commits them as merged meshes, one per material and chunk.
const Kit = preload("res://scripts/world3d/kit3d.gd")

var chunk: float = 0.0
var groups: Dictionary = {}
## For skinned meshes: the bone every new primitive follows (-1 for none) and a transform
## applied before placing it (the bone's rest position).
var bone: int = -1
var offset: Transform3D = Transform3D.IDENTITY
## When set, every new primitive's UVs are squeezed into this rectangle of a texture atlas
## (the characters' fabrics, hair and skin all live in one texture).
var cell: Rect2 = Rect2()
## When set, every new primitive uses this material whatever key it asks for (glows excepted),
## so a whole character merges into one surface.
var force_key: String = ""

func _init(chunk_size: float = 0.0) -> void:
	chunk = chunk_size

func _group(key: String, at: Vector3) -> Dictionary:
	var id: String = key
	if chunk > 0.0 and not key.begins_with("add") and not key.begins_with("blend"):
		id += "@%d,%d" % [floori(at.x / chunk), floori(at.z / chunk)]
	if not groups.has(id):
		groups[id] = {"key": key, "verts": PackedVector3Array(), "normals": PackedVector3Array(), "uvs": PackedVector2Array(),
			"colors": PackedColorArray(), "indices": PackedInt32Array(), "bones": PackedInt32Array(), "weights": PackedFloat32Array()}
	return groups[id]

func add(arrays: Array, placed: Transform3D, color: Color, key: String) -> void:
	var xf: Transform3D = offset * placed
	if force_key != "" and not key.begins_with("glow"):
		key = force_key
	if key.begins_with("glow:"):
		# Fold the emissive colour and strength into the vertex colour of the shared glow material.
		var parts: PackedStringArray = key.split(":")
		var hue: Color = Color(parts[1])
		color = Color(hue.r, hue.g, hue.b, clampf((float(parts[2]) if parts.size() > 2 else 1.5) / 5.0, 0.0, 1.0))
		key = "glowvc"
	var group: Dictionary = _group(key, xf.origin)
	var base: int = group.verts.size()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	group.verts.append_array(xf * verts)
	group.normals.append_array(Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO) * normals)
	var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
	if uvs != null and cell.size != Vector2.ZERO:
		var mapped: PackedVector2Array = PackedVector2Array()
		mapped.resize(uvs.size())
		for i in range(uvs.size()):
			mapped[i] = cell.position + uvs[i].clamp(Vector2.ZERO, Vector2.ONE) * cell.size
		group.uvs.append_array(mapped)
	elif uvs != null:
		group.uvs.append_array(uvs)
	else:
		var empty: PackedVector2Array = PackedVector2Array()
		empty.resize(verts.size())
		group.uvs.append_array(empty)
	var colors: PackedColorArray = PackedColorArray()
	colors.resize(verts.size())
	colors.fill(color)
	group.colors.append_array(colors)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var shifted: PackedInt32Array = PackedInt32Array()
	shifted.resize(indices.size())
	for i in range(indices.size()):
		shifted[i] = indices[i] + base
	group.indices.append_array(shifted)
	if bone >= 0:
		var bones: PackedInt32Array = PackedInt32Array()
		bones.resize(verts.size() * 4)
		var weights: PackedFloat32Array = PackedFloat32Array()
		weights.resize(verts.size() * 4)
		for i in range(verts.size()):
			bones[i * 4] = bone
			weights[i * 4] = 1.0
		group.bones.append_array(bones)
		group.weights.append_array(weights)

## Axis-aligned (optionally turned about Y) box standing on `at`.
func box(at: Vector3, size: Vector3, color: Color, key: String = "vc", turn: float = 0.0) -> void:
	var basis: Basis = Basis(Vector3.UP, turn) * Basis.from_scale(size)
	add(Kit.unit("box"), Transform3D(basis, at), color, key)

func box_xf(xf: Transform3D, size: Vector3, color: Color, key: String = "vc") -> void:
	add(Kit.unit("box"), xf * Transform3D(Basis.from_scale(size), Vector3.ZERO), color, key)

func cylinder(at: Vector3, radius: float, height: float, color: Color, key: String = "vc", segments: int = 12, taper: float = 1.0) -> void:
	add(Kit.unit("cylinder", segments, taper), Transform3D(Basis.from_scale(Vector3(radius, height, radius)), at), color, key)

func cylinder_xf(xf: Transform3D, radius: float, height: float, color: Color, key: String = "vc", segments: int = 12, taper: float = 1.0) -> void:
	add(Kit.unit("cylinder", segments, taper), xf * Transform3D(Basis.from_scale(Vector3(radius, height, radius)), Vector3.ZERO), color, key)

func sphere(center: Vector3, radius: float, color: Color, key: String = "vc", stretch: Vector3 = Vector3.ONE, segments: int = 12) -> void:
	add(Kit.unit("sphere", segments), Transform3D(Basis.from_scale(stretch * radius), center), color, key)

func sphere_xf(xf: Transform3D, radius: float, color: Color, key: String = "vc", stretch: Vector3 = Vector3.ONE, segments: int = 12) -> void:
	add(Kit.unit("sphere", segments), xf * Transform3D(Basis.from_scale(stretch * radius), Vector3.ZERO), color, key)

## Gable roof: a prism standing on `at`, ridge along X unless turned.
func prism(at: Vector3, size: Vector3, color: Color, key: String = "vc", turn: float = 0.0) -> void:
	var basis: Basis = Basis(Vector3.UP, turn) * Basis.from_scale(size)
	add(Kit.unit("prism", 12, 0.5), Transform3D(basis, at), color, key)

## Horizontal quad centred at `at`; `size` in X and Z.
func quad(at: Vector3, size: Vector2, color: Color, key: String, turn: float = 0.0) -> void:
	var basis: Basis = Basis(Vector3.UP, turn) * Basis.from_scale(Vector3(size.x, 1, size.y))
	add(Kit.unit("quad"), Transform3D(basis, at), color, key)

## Upright quad facing +Z (rotate with `turn`), e.g. a painting on a wall.
func panel(at: Vector3, size: Vector2, color: Color, key: String, turn: float = 0.0) -> void:
	var basis: Basis = Basis(Vector3.UP, turn) * Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(size.x, 1, size.y))
	add(Kit.unit("quad"), Transform3D(basis, at), color, key)

func commit(parent: Node3D, shadows: bool = true) -> Array:
	var made: Array = []
	for id in groups:
		var group: Dictionary = groups[id]
		if group.verts.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = group.verts
		arrays[Mesh.ARRAY_NORMAL] = group.normals
		arrays[Mesh.ARRAY_TEX_UV] = group.uvs
		arrays[Mesh.ARRAY_COLOR] = group.colors
		arrays[Mesh.ARRAY_INDEX] = group.indices
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var node: MeshInstance3D = MeshInstance3D.new()
		node.mesh = mesh
		var key: String = group.key
		node.material_override = Kit.material(key)
		var soft: bool = key.begins_with("add") or key.begins_with("blend") or key.begins_with("glow") or key == "water"
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows and not soft else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
		made.append(node)
	groups.clear()
	return made

## The collected primitives as one mesh with a surface per material, for sharing between nodes.
func mesh() -> ArrayMesh:
	var result: ArrayMesh = ArrayMesh.new()
	for id in groups:
		var group: Dictionary = groups[id]
		if group.verts.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = group.verts
		arrays[Mesh.ARRAY_NORMAL] = group.normals
		arrays[Mesh.ARRAY_TEX_UV] = group.uvs
		arrays[Mesh.ARRAY_COLOR] = group.colors
		arrays[Mesh.ARRAY_INDEX] = group.indices
		if not group.bones.is_empty():
			arrays[Mesh.ARRAY_BONES] = group.bones
			arrays[Mesh.ARRAY_WEIGHTS] = group.weights
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(result.get_surface_count() - 1, Kit.material(group.key))
	groups.clear()
	return result
