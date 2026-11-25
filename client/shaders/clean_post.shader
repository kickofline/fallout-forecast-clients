shader_type canvas_item;
// Retro off: plain upscale plus the tracking glitch so lightning still reads.
uniform float glitch = 0.0;
float hash(float n) { return fract(sin(n) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	float t = TIME;
	float band = step(1.0 - glitch * 0.35, hash(floor(uv.y * 18.0) + floor(t * 12.0)));
	uv.x += band * (hash(floor(uv.y * 240.0) + floor(t * 20.0)) - 0.5) * 0.05 * glitch;
	vec3 col = texture(TEXTURE, uv).rgb;
	col += (hash(floor(uv.x * 320.0) * 13.1 + floor(uv.y * 240.0) * 71.7 + floor(t * 30.0)) - 0.5) * 0.2 * glitch;
	COLOR = vec4(col, 1.0);
}
