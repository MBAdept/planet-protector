shader_type canvas_item;
// TWIN hologram (docs/SPEC.md §19.5): the ship sprite as a monochrome image in the power-up colour with fine scanlines
// and reduced opacity, so the twin reads as a ghost of every ship type (its own blue / green / orange accents vanish).
// PlayerView puts it on the twin's node; the additive glow / sheen children keep their own materials.

uniform vec4 tint : source_color = vec4(0.72, 0.5, 1.0, 1.0);
uniform float opacity = 0.55;

void fragment() {
	float l = dot(COLOR.rgb, vec3(0.3, 0.59, 0.11));
	float scan = 0.6 + 0.4 * step(1.5, mod(FRAGCOORD.y, 3.0));
	COLOR = vec4(tint.rgb * (0.25 + 0.8 * l) * scan, COLOR.a * opacity);
}
