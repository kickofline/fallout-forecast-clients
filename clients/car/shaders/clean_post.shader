shader_type canvas_item;
// Retro off: plain upscale plus the tracking glitch so lightning still reads.
uniform float glitch = 0.0;
// Damage / acid edge tints (ui/damage.gdshader), applied here at the 3D
// resolution instead of as two full-screen HUD rects.
uniform float hurt = 0.0;
uniform vec3 hurt_tint = vec3(1.0, 0.08, 0.16);
uniform float acid = 0.0;
uniform vec3 acid_tint = vec3(0.65, 1.0, 0.08);

vec3 edge_tints(vec3 col, vec2 uv) {
	vec2 p = uv * 2.0 - 1.0;
	float edge = smoothstep(0.22, 0.95, max(abs(p.x), abs(p.y)));
	col = mix(col, hurt_tint, clamp(hurt * (0.12 + edge * 0.8), 0.0, 1.0));
	return mix(col, acid_tint, clamp(acid * (0.12 + edge * 0.8), 0.0, 1.0));
}
float hash(float n) { return fract(sin(n) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	float t = TIME;
	float band = step(1.0 - glitch * 0.35, hash(floor(uv.y * 18.0) + floor(t * 12.0)));
	uv.x += band * (hash(floor(uv.y * 240.0) + floor(t * 20.0)) - 0.5) * 0.05 * glitch;
	vec3 col = texture(TEXTURE, uv).rgb;
	col += (hash(floor(uv.x * 320.0) * 13.1 + floor(uv.y * 240.0) * 71.7 + floor(t * 30.0)) - 0.5) * 0.2 * glitch;
	COLOR = vec4(edge_tints(col, UV), 1.0);
}
