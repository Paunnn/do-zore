// Ink outline for people: the back faces pushed out by a constant width in pixels.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec4 line_color : source_color = vec4(0.16, 0.08, 0.06, 1.0);
uniform float width_px = 1.3;
// The hull sits this far behind the surface, so the inside of a garment seen through an opening (the
// person is drawn two-sided) shows its cloth, not ink; outlines still show along the silhouette.
uniform float depth_push = 0.012;

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view.z -= depth_push;
	vec4 clip = PROJECTION_MATRIX * view;
	vec2 dir = (PROJECTION_MATRIX * vec4(normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), 0.0)).xy;
	float len = length(dir);
	if (len > 0.0001) {
		dir /= len;
	}
	clip.xy += dir * width_px * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}

void fragment() {
	if (texture(atlas, UV).a < 0.5) {
		discard;
	}
	ALBEDO = line_color.rgb;
}
