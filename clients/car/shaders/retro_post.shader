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
	COLOR = vec4(edge_tints(col, UV), 1.0);
}
