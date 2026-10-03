// The city and the venues in the cartoon style: flat painted colour (vertex colour, times a painted
// texture mapped in world space or by UV), toon light in two soft tones with a cool shadow, and a
// small hard highlight on glossy things. See scripts/world3d/kit3d.gd.
shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// 0: vertex colour only, 1: texture mapped in world space (three planes), 2: texture by UV.
uniform int mode = 0;
uniform float tex_scale = 0.5;
uniform float gloss = 0.0;
// The broad soft sheen (none on cloth).
uniform float sheen = 0.12;
uniform float metal = 0.0;
uniform vec3 shade_color : source_color = vec3(0.46, 0.4, 0.58);
uniform float band = 0.12;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec3 base = to_linear(COLOR.rgb);
	vec3 tex = vec3(1.0);
	if (mode == 1) {
		vec3 blend = pow(abs(world_normal), vec3(8.0));
		blend /= max(blend.x + blend.y + blend.z, 0.0001);
		vec3 p = world_pos * tex_scale;
		tex = texture(albedo_tex, p.zy).rgb * blend.x + texture(albedo_tex, p.xz).rgb * blend.y
				+ texture(albedo_tex, p.xy).rgb * blend.z;
	} else if (mode == 2) {
		tex = texture(albedo_tex, UV).rgb;
	}
	ALBEDO = base * tex * mix(1.0, 0.75, metal);
	// The sky still shows in the surfaces (flat roofs and floors catch the dusk light).
	ROUGHNESS = mix(0.85, 0.4, max(gloss, metal));
	METALLIC = metal * 0.6;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-band, band, ndl);
	vec3 tone = mix(shade_color * 0.5, vec3(1.0), lit);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * tone / PI;
	vec3 h = normalize(LIGHT + VIEW);
	float nh = dot(NORMAL, h);
	// A broad soft sheen where the light glances back at the camera (moonlit roofs, lamplit
	// floors), and a small hard highlight on glossy things.
	float shine = smoothstep(0.8, 0.97, nh) * sheen + smoothstep(0.93, 0.96, nh) * gloss;
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * shine * lit;
}
