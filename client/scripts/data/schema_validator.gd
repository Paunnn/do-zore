extends RefCounted
## Small JSON Schema subset covering the checked-in game-data contracts.
var schemas: Dictionary = {}

func _init() -> void:
	schemas = JSON.parse_string(FileAccess.get_file_as_string("res://data/schemas.json"))

func valid(value: Variant, schema: Dictionary, file: String) -> bool:
	if schema.has("$ref"):
		var parts: PackedStringArray = str(schema["$ref"]).split("#")
		var target_file: String = parts[0].get_file() if not parts[0].is_empty() else file
		var target: Dictionary = schemas.get(target_file, {})
		if parts.size() > 1:
			for part in parts[1].split("/", false):
				target = target.get(part, {})
		return not target.is_empty() and valid(value, target, target_file)
	if schema.has("oneOf"):
		var matches: int = 0
		for child in schema.oneOf:
			if valid(value, child, file): matches += 1
		if matches != 1: return false
	if schema.has("anyOf"):
		var matched: bool = false
		for child in schema.anyOf:
			if valid(value, child, file): matched = true
		if not matched: return false
	if schema.has("const") and value != schema.const: return false
	if schema.has("enum") and value not in schema.enum: return false
	var kind: String = str(schema.get("type", ""))
	match kind:
		"object":
			if not value is Dictionary: return false
			if value.size() < schema.get("minProperties", 0) or value.size() > schema.get("maxProperties", INF): return false
			for required in schema.get("required", []):
				if not value.has(required): return false
			var properties: Dictionary = schema.get("properties", {})
			for key in value:
				if schema.has("propertyNames") and not valid(str(key), schema.propertyNames, file): return false
				if properties.has(key):
					if not valid(value[key], properties[key], file): return false
				elif schema.get("additionalProperties", true) is Dictionary:
					if not valid(value[key], schema.additionalProperties, file): return false
				elif schema.get("additionalProperties", true) == false: return false
		"array":
			if not value is Array: return false
			if value.size() < schema.get("minItems", 0) or value.size() > schema.get("maxItems", INF): return false
			var seen: Array = []
			for entry in value:
				if schema.get("uniqueItems", false) and entry in seen: return false
				seen.append(entry)
				if not valid(entry, schema.get("items", {}), file): return false
		"number", "integer":
			if not (value is float or value is int) or not is_finite(float(value)): return false
			if kind == "integer" and float(value) != floor(float(value)): return false
			if value < schema.get("minimum", -INF) or value > schema.get("maximum", INF): return false
			if value <= schema.get("exclusiveMinimum", -INF): return false
			if value >= schema.get("exclusiveMaximum", INF): return false
		"string":
			if not value is String: return false
			if value.length() < schema.get("minLength", 0) or value.length() > schema.get("maxLength", INF): return false
			if schema.has("pattern"):
				var regex: RegEx = RegEx.new()
				regex.compile(schema.pattern)
				if regex.search(value) == null: return false
		"boolean":
			if not value is bool: return false
	return true
