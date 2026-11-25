shader_type canvas_item;
// ui/damage.gdshader: edge-weighted full-screen tint.
uniform float strength = 0.0;
uniform vec3 tint = vec3(1.0, 0.08, 0.16);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge = smoothstep(0.22, 0.95, max(abs(p.x), abs(p.y)));
	COLOR = vec4(tint, strength * (0.12 + edge * 0.8));
}
