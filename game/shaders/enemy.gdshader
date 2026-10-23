shader_type canvas_item;
// Colourises the channel-packed enemy sheet (docs/SPEC.md §16.2):
//   R = diffuse of a white material, G = specular / rim, B = emissive mask (eyes), A = coverage.
//   base = gradient(t), t from content_top → content_bottom of the frame
//   col  = base*(0.18 + R) + G*mix(1, base, 0.35)*0.9 + B*eye_color
// plus: dithering against banding, eye halo, outline for black enemies, orange hit flash,
// materialize scan/fade. Black enemies limit the emission (and its halo) to eye_rect, so only the
// eyes glow (REFERENCE I: black Earth enemies readable through a subtle outline and the eyes).

uniform sampler2D gradient_tex : source_color, filter_linear, repeat_disable;
// Region of the current frame inside the sheet, in sheet UV: (u0, v0, du, dv).
uniform vec4 frame_uv = vec4(0.0, 0.0, 1.0, 1.0);
// content_top / content_bottom as fractions of the frame height.
uniform float content_top = 0.0;
uniform float content_bottom = 1.0;
uniform vec4 eye_color : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform float eye_glow = 0.55;
// Emissive area in local frame coordinates (x0, y0, x1, y1), 0..1; B outside it is ignored.
uniform vec4 eye_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float outline = 0.0;
uniform vec4 outline_color : source_color = vec4(0.42, 0.47, 0.62, 1.0);
uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 0.55, 0.1, 1.0);
uniform float materialize = 1.0;
uniform vec4 scan_color : source_color = vec4(0.55, 0.9, 1.0, 1.0);
uniform float seed = 0.0;

varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

// 1 inside eye_rect, 0 outside (sample UV → local frame coordinates, as in fragment()).
float eye_mask(vec2 uv) {
	vec2 l = (uv - frame_uv.xy) / frame_uv.zw;
	return step(eye_rect.x, l.x) * step(l.x, eye_rect.z) * step(eye_rect.y, l.y) * step(l.y, eye_rect.w);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec4 s = texture(TEXTURE, UV);
	vec2 local = (UV - frame_uv.xy) / frame_uv.zw;              // 0..1 inside the frame
	float t = clamp((local.y - content_top) / max(content_bottom - content_top, 1e-4), 0.0, 1.0);
	vec3 base = texture(gradient_tex, vec2(t, 0.5)).rgb;

	vec3 col = base * (0.18 + 1.0 * s.r) + s.g * mix(vec3(1.0), base, 0.35) * 0.9 + s.b * eye_mask(UV) * eye_color.rgb;
	float a = s.a;
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec2 lo = frame_uv.xy;
	vec2 hi = frame_uv.xy + frame_uv.zw;

	// Soft halo around emissive details (eyes): a small blur of B that may leave the silhouette.
	float halo = 0.0;
	if (eye_glow > 0.0) {
		for (int i = 0; i < 8; i++) {
			float ang = float(i) * 0.785398;
			vec2 o = vec2(cos(ang), sin(ang));
			vec2 u1 = clamp(UV + o * px * 3.0, lo, hi);
			vec2 u2 = clamp(UV + o * px * 6.5, lo, hi);
			halo += texture(TEXTURE, u1).b * eye_mask(u1) * 0.6 + texture(TEXTURE, u2).b * eye_mask(u2) * 0.4;
		}
		halo = clamp(halo / 8.0 * eye_glow, 0.0, 1.0);
	}

	// Outline for very dark (black) enemies: a cool rim just outside the silhouette.
	if (outline > 0.0) {
		float n = 0.0;
		for (int i = 0; i < 8; i++) {
			float ang = float(i) * 0.785398;
			vec2 o = vec2(cos(ang), sin(ang));
			n = max(n, texture(TEXTURE, clamp(UV + o * px * 2.5, lo, hi)).a);
		}
		float edge = clamp(n - a, 0.0, 1.0) * outline;
		// Also a faint inner rim on the silhouette border for extra readability.
		float inner = clamp(a - min(a, texture(TEXTURE, clamp(UV + vec2(0.0, -px.y * 2.0), lo, hi)).a), 0.0, 1.0);
		col += outline_color.rgb * inner * 0.35 * outline;
		col = mix(col, outline_color.rgb, edge / max(a + edge, 1e-3));
		a = max(a, edge * 0.85);
	}

	// Eye halo behaves like light: outside the body it becomes a soft coloured glow, inside it brightens.
	float out_a = max(a, halo * 0.75);
	col = (col * a + eye_color.rgb * halo * 0.75 * (1.0 - a)) / max(out_a, 1e-3) + eye_color.rgb * halo * 0.3 * a;
	a = out_a;

	// Orange hit flash (non-lethal hits on Earth enemies).
	col = mix(col, flash_color.rgb * (0.75 + 0.5 * s.r), clamp(flash, 0.0, 1.0) * 0.82 * step(0.01, s.a));

	// Materialize: a scan front sweeps top → bottom, with glowing scan lines and a noisy dissolve edge.
	if (materialize < 1.0) {
		float m = clamp(materialize, 0.0, 1.0);
		float front = m * 1.35 - 0.2;
		float n = hash12(floor(local * vec2(90.0, 56.0)) + seed + floor(TIME * 24.0));
		float d = front - local.y + (n - 0.5) * 0.12;
		float vis = smoothstep(0.0, 0.08, d);
		float edge_glow = exp(-abs(d) * 22.0) * s.a;
		float lines = 0.65 + 0.35 * sin(local.y * 220.0 - TIME * 30.0);
		float settle = smoothstep(0.55, 1.0, m);
		col = mix(mix(scan_color.rgb * 0.6, col, 0.55) * lines, col, settle);
		col += scan_color.rgb * edge_glow * 1.4;
		a = a * vis * mix(0.55, 1.0, settle) + edge_glow * 0.9 * (1.0 - settle * 0.6);
		a = clamp(a, 0.0, 1.0);
	}

	// Dither (±0.5 LSB) against gradient banding.
	col += (hash12(FRAGCOORD.xy + seed) - 0.5) / 255.0;
	COLOR = vec4(col, a) * v_modulate;
}
