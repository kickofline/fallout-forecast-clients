shader_type canvas_item;
// GLES2 port of retro/retro_screen.gdshader. Applied to the TextureRect that
// shows the low-res 3D viewport, so it never needs a SCREEN_TEXTURE copy:
// colour bleed, ordered dither + 15-bit quantize, scanlines, vignette, VHS
// tape jitter and the tracking glitch (lightning / downed).

uniform vec2 res = vec2(426.0, 240.0);
uniform float levels = 32.0;
uniform float dither_strength = 1.0;
uniform float bleed_pixels = 0.75;
uniform float scanline_strength = 0.18;
uniform float vignette_strength = 0.35;
uniform float glitch = 0.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }

float b2(vec2 p) { return mod(2.0 * p.x + 3.0 * p.y, 4.0); }

float bayer4(vec2 p) {
	vec2 q = mod(p, 4.0);
	return (4.0 * b2(mod(q, 2.0)) + b2(floor(q * 0.5))) / 16.0 - 0.5;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	float row = floor(uv.y * res.y);
	float band = step(1.0 - glitch * 0.35, hash(floor(uv.y * 18.0) + floor(t * 12.0)));
	float wobble = sin(uv.y * 40.0 + t * 30.0) * 0.004 * glitch;
	uv.x += band * (hash(row + floor(t * 20.0)) - 0.5) * 0.06 * glitch + wobble;
	uv.x += (hash(row * 0.37 + floor(t * 60.0)) - 0.5) * 0.0015;
	vec2 cell = floor(uv * res);
	vec2 puv = (cell + 0.5) / res;
	vec2 px = vec2(bleed_pixels / res.x, 0.0);
	vec3 col;
	col.r = texture(TEXTURE, puv + px).r;
	col.g = texture(TEXTURE, puv).g;
	col.b = texture(TEXTURE, puv - px).b;
	col += bayer4(cell) * dither_strength / levels;
	col = floor(col * levels + 0.5) / levels;
	col *= 1.0 - scanline_strength * step(0.5, fract(UV.y * res.y * 0.5));
	vec2 v = UV - 0.5;
	col *= 1.0 - vignette_strength * dot(v, v) * 2.0;
	float bar = smoothstep(0.0, 0.02, abs(fract(UV.y + t * 0.15) - 0.5) - 0.48);
	col = mix(col, vec3(0.9), (1.0 - bar) * 0.25 * glitch);
	col += (hash(cell.x * 13.1 + cell.y * 71.7 + floor(t * 30.0)) - 0.5) * 0.25 * glitch;
	COLOR = vec4(col, 1.0);
}
