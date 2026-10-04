// People: cartoon toon shading, a palette per person and a face drawn on the head.
// The mesh comes from tools/art/people/build_people.py: UV is an atlas of the cartoonised clothes and hair,
// UV2 the face plane (eyes at (0.31, 0.41) and (0.69, 0.41), mouth at (0.5, 0.79)), COLOR.r the palette
// slot, COLOR.g the face mask and COLOR.b set where a part keeps its own texture colours.
// The palette and the face are set per person on the person's own copy of the material (see
// scripts/world3d/people3d.gd); instance uniforms would run out of room on phones' browsers.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform float detail_amount = 0.32;
// How much the fabric and hair textures are smoothed (a coarser mip level): flat cartoon colour with
// the folds and seams, without the scanned noise.
uniform float smooth_bias = 2.0;
uniform vec3 shade_color : source_color = vec3(0.47, 0.36, 0.55);
uniform float band = 0.06;

// Palette: skin, hair, top, bottom, shoes, hat and eyes.
uniform vec4 col_skin : source_color = vec4(0.96, 0.76, 0.62, 1.0);
uniform vec4 col_hair : source_color = vec4(0.36, 0.24, 0.17, 1.0);
uniform vec4 col_top : source_color = vec4(0.25, 0.45, 0.7, 1.0);
uniform vec4 col_bottom : source_color = vec4(0.25, 0.25, 0.3, 1.0);
uniform vec4 col_shoes : source_color = vec4(0.25, 0.16, 0.12, 1.0);
uniform vec4 col_hat : source_color = vec4(0.4, 0.38, 0.36, 1.0);
uniform vec4 col_eye : source_color = vec4(0.36, 0.22, 0.12, 1.0);
// Face: eyes (open, squint, look x, look y), brows (lift, angry, worry, unused),
// mouth (smile, open, round, width), extra (blush, tears, happy closed eyes, wink).
uniform vec4 face_eyes = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 face_brows = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 face_mouth = vec4(0.2, 0.0, 0.0, 1.0);
uniform vec4 face_extra = vec4(0.25, 0.0, 0.0, 0.0);
// Face style: lashes (0 to 1), brow weight, lip colour, glasses (1 glasses, 2 sunglasses).
uniform vec4 face_style = vec4(0.0, 1.0, 0.0, 0.0);
// Age and whiskers: wrinkles (0 to 1), moustache (1 trim, 2 big brk), beard (0 to 1, stubble to
// full), bushy brows (0 to 1).
uniform vec4 face_age = vec4(0.0);

varying vec4 vcol;

const vec3 INK = vec3(0.16, 0.08, 0.06);

void vertex() {
	vcol = COLOR;
}

float aa_step(float px, float d) {
	return 1.0 - smoothstep(-px, px, d);
}

// An ink stroke of half-width w that never gets thinner than about a pixel and a half on screen.
float line(float px, float d, float w) {
	return aa_step(px, d - max(w, px * 0.75));
}

float sd_ellipse(vec2 p, vec2 r) {
	float k = length(p / r);
	return (k - 1.0) * min(r.x, r.y);
}

// Distance to a quadratic Bezier (Inigo Quilez).
float sd_bezier(vec2 pos, vec2 A, vec2 B, vec2 C) {
	vec2 a = B - A;
	vec2 b = A - 2.0 * B + C;
	vec2 c = a * 2.0;
	vec2 d = A - pos;
	float kk = 1.0 / max(dot(b, b), 1e-6);
	float kx = kk * dot(a, b);
	float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
	float kz = kk * dot(d, a);
	float res = 0.0;
	float p = ky - kx * kx;
	float p3 = p * p * p;
	float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
	float h = q * q + 4.0 * p3;
	if (h >= 0.0) {
		h = sqrt(h);
		vec2 x = (vec2(h, -h) - q) / 2.0;
		vec2 uv = sign(x) * pow(abs(x), vec2(1.0 / 3.0));
		float t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
		vec2 qq = d + (c + b * t) * t;
		res = dot(qq, qq);
	} else {
		float z = sqrt(-p);
		float v = acos(q / (p * z * 2.0)) / 3.0;
		float m = cos(v);
		float n = sin(v) * 1.732050808;
		vec3 t = clamp(vec3(m + m, -n - m, n - m) * z - kx, 0.0, 1.0);
		vec2 qx = d + (c + b * t.x) * t.x;
		float dx = dot(qx, qx);
		vec2 qy = d + (c + b * t.y) * t.y;
		float dy = dot(qy, qy);
		res = min(dx, dy);
	}
	return sqrt(res);
}

// One eye in its own frame (q centred on the eye, y down). side = -1 left, +1 right (viewer).
vec4 draw_eye(vec2 q, float side, vec3 base, float px) {
	vec3 col = base;
	float open = clamp(face_eyes.x - (side > 0.0 ? face_extra.w : 0.0), 0.0, 1.0);
	float squint = face_eyes.y;
	vec2 r = vec2(0.095, 0.122 * (1.0 - 0.12 * face_age.x));
	float happy = face_extra.z;
	if (open < 0.12 || happy > 0.5) {
		// Closed: a lash stroke. Happy closed eyes arc upwards (^ ^), sleepy ones droop.
		float bend = happy > 0.5 ? -0.05 : 0.025;
		float d = sd_bezier(q, vec2(-r.x * 0.95, 0.01), vec2(0.0, 0.01 + bend * 2.0), vec2(r.x * 0.95, 0.01));
		col = mix(col, INK, line(px, d, 0.011));
		return vec4(col, 1.0);
	}
	float lid = -r.y + (1.0 - open) * r.y * 1.7;        // upper lid height
	float low = r.y - squint * r.y * 0.9;               // lower lid rises when smiling or squinting
	float inside = sd_ellipse(q, r);
	float lid_d = lid - q.y + 0.004 * (q.x / r.x) * (q.x / r.x) * 3.0;
	float low_d = q.y - low;
	float vis = max(inside, max(lid_d, low_d));
	float m = aa_step(px, vis);
	vec3 eye = vec3(0.99, 0.97, 0.93);
	// Iris and pupil, following the look direction.
	vec2 look = face_eyes.zw * vec2(0.035, 0.03);
	float ir = 0.066;
	float di = length(q - look - vec2(0.0, 0.006)) - ir;
	vec3 iris = mix(col_eye.rgb * 1.25, col_eye.rgb * 0.55, smoothstep(-ir, 0.0, di + ir * 0.5));
	eye = mix(eye, iris, aa_step(px, di));
	eye = mix(eye, INK * 0.6, line(px, abs(di), 0.004));
	float dp = length(q - look - vec2(0.0, 0.006)) - 0.03;
	eye = mix(eye, vec3(0.05, 0.03, 0.03), aa_step(px, dp));
	float h1 = length(q - look - vec2(-0.02, -0.018)) - 0.013;
	float h2 = length(q - look - vec2(0.018, 0.024)) - 0.006;
	eye = mix(eye, vec3(1.0), aa_step(px, min(h1, h2)));
	// Soft shadow under the upper lid.
	eye *= mix(0.78, 1.0, smoothstep(0.0, 0.03, q.y - lid));
	col = mix(col, eye, m);
	// Ink: thin outline, thick lash line along the upper lid.
	col = mix(col, INK, line(px, abs(vis), 0.004) * smoothstep(0.02, -0.01, inside));
	float in_x = smoothstep(r.x * 1.12, r.x * 0.85, abs(q.x));
	col = mix(col, INK, line(px, abs(lid_d), 0.011) * in_x * step(inside, 0.012));
	// A little flick at the outer corner.
	float flick = sd_bezier(q, vec2(-r.x * 0.8, lid + 0.01), vec2(-r.x * 1.05, lid - 0.004),
			vec2(-r.x * 1.25, lid - 0.02));
	col = mix(col, INK, line(px, flick, 0.006) * step(0.3, open) * face_style.x);
	return vec4(col, 1.0);
}

vec3 draw_brow(vec2 q, float side, vec3 base, float px) {
	// q in brow frame: x outward from the nose (inner end at x=0).
	float lift = face_brows.x * 0.03;
	float angry = face_brows.y;
	float worry = face_brows.z;
	vec2 inner = vec2(0.0, 0.035 * angry - 0.04 * worry - lift);
	vec2 outer = vec2(0.13, -0.01 * angry + 0.01 * worry - lift * 0.8);
	vec2 mid = (inner + outer) * 0.5 + vec2(0.0, -0.028 + 0.02 * worry * 0.5);
	float d = sd_bezier(q, inner, mid, outer);
	// Thicker towards the inner end, like a brush stroke.
	float t = clamp(q.x / 0.13, 0.0, 1.0);
	float w = mix(0.022, 0.011, t) * face_style.y * (1.0 + face_age.w * 0.7);
	vec3 brow = mix(col_hair.rgb * mix(0.55, 0.8, face_age.w), INK, mix(0.35, 0.2, face_age.w));
	return mix(base, brow, line(px, d, w));
}

vec3 draw_mouth(vec2 q, vec3 base, float px) {
	vec3 col = base;
	float smile = face_mouth.x;
	float open = face_mouth.y;
	float round_ = face_mouth.z;
	float w = mix(0.15, 0.07, round_) * face_mouth.w;
	float x = clamp(q.x / w, -1.0, 1.0);
	float edge = smoothstep(1.0, 0.0, abs(q.x / w));
	float top = -smile * 0.045 * x * x - open * 0.012;
	float bottom = top + open * mix(0.14, 0.15, round_) * pow(max(1.0 - x * x, 0.0), mix(0.55, 0.5, round_)) + 0.0005;
	if (open > 0.04) {
		float din = max(max(top - q.y, q.y - bottom), abs(q.x) - w);
		// Round off the shape a bit with an ellipse when singing or surprised.
		vec2 oc = vec2(0.0, (top + bottom) * 0.5);
		float dell = sd_ellipse(q - oc, vec2(w * 0.85, max((bottom - top) * 0.55, 0.01)));
		din = mix(din, dell, round_);
		float inside = aa_step(px, din);
		vec3 m = vec3(0.36, 0.08, 0.08);
		// Tongue at the bottom, teeth along the top when smiling.
		float tongue = sd_ellipse(q - vec2(0.0, bottom - 0.004), vec2(w * 0.55, 0.035));
		m = mix(m, vec3(0.86, 0.42, 0.42), aa_step(px, tongue));
		float teeth = max(q.y - (top + 0.022 * clamp(smile + 0.3, 0.0, 1.0)), din);
		m = mix(m, vec3(1.0, 0.98, 0.94), aa_step(px, teeth) * (1.0 - round_));
		col = mix(col, m, inside);
		col = mix(col, INK, line(px, abs(din), 0.0045));
	} else {
		// Lipstick: a soft rose mouth under the line.
		float lips = sd_ellipse(q - vec2(0.0, 0.004), vec2(w * 0.72, 0.022));
		col = mix(col, vec3(0.86, 0.38, 0.42), aa_step(px, lips) * face_style.z * 0.85);
		float d = sd_bezier(q, vec2(-w, -smile * 0.045), vec2(0.0, smile * 0.045), vec2(w, -smile * 0.045));
		col = mix(col, INK, line(px, d, mix(0.0035, 0.0065, edge)));
	}
	// Smile dimples.
	if (smile > 0.35) {
		for (int i = 0; i < 2; i++) {
			float s = i == 0 ? -1.0 : 1.0;
			vec2 c = vec2(s * (w + 0.008), -smile * 0.045 + 0.004);
			float dd = sd_bezier(q, c + vec2(-s * 0.004, -0.012), c + vec2(s * 0.01, 0.0), c + vec2(-s * 0.004, 0.012));
			col = mix(col, INK, line(px, dd, 0.003) * smoothstep(0.35, 0.7, smile));
		}
	}
	return col;
}

// Wrinkles, beard and moustache, drawn over the mouth.
vec3 draw_age(vec2 p, vec3 base, float px) {
	vec3 col = base;
	float age = face_age.x;
	if (age > 0.01) {
		vec3 crease = mix(base, INK, 0.55);
		float d = 1e9;
		for (int i = 0; i < 2; i++) {
			float s = i == 0 ? -1.0 : 1.0;
			// Smile lines from the nose to past the mouth corners.
			vec2 a = vec2(0.5 + s * 0.085, 0.655);
			d = min(d, sd_bezier(p, a, vec2(0.5 + s * 0.165, 0.72), vec2(0.5 + s * 0.15, 0.83)));
			// Crow's feet at the outer corners of the eyes.
			vec2 c = vec2(0.5 + s * 0.31, 0.405);
			for (int k = 0; k < 3; k++) {
				float f = float(k - 1);
				vec2 dir = normalize(vec2(s, f * 0.55));
				d = min(d, sd_bezier(p, c + dir * 0.012, c + dir * 0.03, c + dir * 0.05));
			}
			// Soft bags under the eyes.
			vec2 e = vec2(0.5 + s * 0.19, 0.505);
			d = min(d, sd_bezier(p, e - vec2(0.06, 0.0), e + vec2(0.0, 0.022), e + vec2(0.06, 0.0)));
		}
		// Two lines across the forehead.
		d = min(d, sd_bezier(p, vec2(0.38, 0.165), vec2(0.5, 0.145), vec2(0.62, 0.165)));
		d = min(d, sd_bezier(p, vec2(0.41, 0.115), vec2(0.5, 0.098), vec2(0.59, 0.115)));
		col = mix(col, crease, line(px, d, 0.0032) * smoothstep(0.0, 0.5, age));
	}
	vec3 hair = col_hair.rgb * 0.85;
	if (face_age.z > 0.01) {
		// Beard: around the jaw and chin, leaving the lips clear.
		float jaw = sd_ellipse(p - vec2(0.5, 0.86), vec2(0.36, 0.2));
		float lips = sd_ellipse(p - vec2(0.5, 0.795), vec2(0.13, 0.05));
		float area = max(jaw, -lips);
		float amount = aa_step(px * 3.0, area) * smoothstep(0.6, 0.72, p.y);
		col = mix(col, mix(hair, INK, 0.2), amount * mix(0.35, 0.95, face_age.z));
		col = mix(col, INK, line(px, abs(area), 0.004) * step(0.6, face_age.z) * smoothstep(0.66, 0.74, p.y));
	}
	if (face_age.y > 0.5) {
		// Brk: a moustache under the nose, two rounded wings meeting at the middle; the big one
		// droops past the corners of the mouth.
		float big = step(1.5, face_age.y);
		float m = 1e9;
		for (int i = 0; i < 2; i++) {
			float s = i == 0 ? -1.0 : 1.0;
			vec2 q = p - vec2(0.5 + s * mix(0.06, 0.075, big), mix(0.722, 0.735, big));
			float angle = s * mix(0.28, 0.45, big);
			q = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * q;
			m = min(m, sd_ellipse(q, mix(vec2(0.075, 0.032), vec2(0.105, 0.046), big)));
		}
		col = mix(col, hair, aa_step(px, m));
		// A few strands for texture, then the ink outline.
		for (int k = 0; k < 4; k++) {
			float x = 0.5 + (float(k) - 1.5) * 0.045;
			float strand = sd_bezier(p, vec2(x, 0.705), vec2(x + (x - 0.5) * 0.15, 0.725), vec2(x + (x - 0.5) * 0.3, 0.745));
			col = mix(col, mix(hair, INK, 0.45), line(px, strand, 0.0025) * aa_step(px, m + 0.008));
		}
		col = mix(col, INK, line(px, abs(m), 0.0042));
	}
	return col;
}

vec3 draw_face(vec2 p, vec3 skin, float px) {
	vec3 col = skin;
	// Blush.
	for (int i = 0; i < 2; i++) {
		float s = i == 0 ? -1.0 : 1.0;
		float d = length((p - vec2(0.5 + s * 0.22, 0.6)) / vec2(0.075, 0.042));
		col = mix(col, vec3(0.98, 0.52, 0.46), (1.0 - smoothstep(0.4, 1.0, d)) * 0.55 * face_extra.x);
	}
	// Nose: a soft shadow and a short ink curve under the tip.
	float nd = sd_bezier(p, vec2(0.465, 0.645), vec2(0.5, 0.665), vec2(0.535, 0.645));
	col = mix(col, INK, line(px, nd, 0.004) * 0.75);
	col = draw_eye(p - vec2(0.31, 0.41), -1.0, col, px).rgb;
	col = draw_eye(vec2(-1.0, 1.0) * (p - vec2(0.69, 0.41)), 1.0, col, px).rgb;
	col = draw_brow(vec2(0.40 - p.x, p.y - 0.235), -1.0, col, px);
	col = draw_brow(vec2(p.x - 0.60, p.y - 0.235), 1.0, col, px);
	col = draw_mouth(p - vec2(0.5, 0.79), col, px);
	col = draw_age(p, col, px);
	// Glasses: round frames and a bridge; sunglasses fill the lenses.
	if (face_style.w > 0.5) {
		float sun = step(1.5, face_style.w);
		float lens = 1e9;
		for (int i = 0; i < 2; i++) {
			float s = i == 0 ? -1.0 : 1.0;
			lens = min(lens, sd_ellipse(p - vec2(0.5 + s * 0.19, 0.42), vec2(0.13, 0.11)));
		}
		col = mix(col, vec3(0.1, 0.11, 0.14), aa_step(px, lens) * sun * 0.94);
		float shine = sd_bezier(p, vec2(0.25, 0.37), vec2(0.27, 0.35), vec2(0.3, 0.345));
		col = mix(col, vec3(0.85, 0.9, 1.0), aa_step(px, shine - 0.006) * sun);
		col = mix(col, INK, line(px, abs(lens), 0.009));
		float bridge = sd_bezier(p, vec2(0.44, 0.40), vec2(0.5, 0.375), vec2(0.56, 0.40));
		col = mix(col, INK, line(px, bridge, 0.007));
	}
	// Tears.
	if (face_extra.y > 0.01) {
		for (int i = 0; i < 2; i++) {
			float s = i == 0 ? -1.0 : 1.0;
			vec2 c = vec2(0.5 + s * 0.2, 0.55 + 0.06 * face_extra.y);
			float d = sd_ellipse(p - c, vec2(0.018, 0.03));
			col = mix(col, vec3(0.6, 0.85, 1.0), aa_step(px, d) * step(0.2, face_extra.y));
		}
	}
	return col;
}

void fragment() {
	float region = vcol.r;
	vec3 pal = col_skin.rgb;
	if (region > 0.9) pal = col_hat.rgb;
	else if (region > 0.7) pal = col_shoes.rgb;
	else if (region > 0.5) pal = col_bottom.rgb;
	else if (region > 0.3) pal = col_top.rgb;
	else if (region > 0.1) pal = col_hair.rgb;
	vec4 t = texture(atlas, UV);
	// The colour from a smoother level; the cut-out edge of the hair from the sharp one.
	t.rgb = texture(atlas, UV, smooth_bias).rgb;
	float l = dot(t.rgb, vec3(0.299, 0.587, 0.114));
	// (Pale cloth, a white shirt or a wedding dress, shows its weave more: less of it there.)
	float detail = detail_amount * (1.0 - 0.7 * smoothstep(0.7, 0.95, max(pal.r, max(pal.g, pal.b))));
	vec3 albedo = pal * mix(1.0, clamp(l * 1.35, 0.55, 1.1), region < 0.1 ? 0.0 : detail);
	albedo = mix(albedo, t.rgb, vcol.b);
	float px = max(length(fwidth(UV2)) * 0.6, 0.0008);
	vec3 face = draw_face(UV2, albedo, px);
	albedo = mix(albedo, face, region < 0.1 ? vcol.g : 0.0);
	ALBEDO = albedo * 0.88;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-band, band, ndl - 0.05);
	// Faces stay readable: the drawn face is lit almost evenly.
	lit = mix(lit, 0.7 + 0.3 * lit, vcol.g * 0.85);
	vec3 tone = mix(shade_color * 0.55, vec3(0.82), lit);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0) * lit * 0.25;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (tone + rim) / PI;
}
