shader_type spatial;
// Triplanar variant of ps1.shader for world-space tiled ground/walls (the
// game's 64x64 nearest-filtered textures). No vertex snap on these (the
// original skips snapping triplanar surfaces too).
render_mode vertex_lighting, diffuse_lambert, specular_blinn;

uniform vec4 albedo : hint_color = vec4(1.0);
uniform sampler2D albedo_texture : hint_albedo;
uniform vec3 uv_scale = vec3(1.0);
uniform float wetness = 0.0;
uniform float dry_roughness = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = pow(abs(world_normal), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = world_pos * uv_scale;
	vec4 c = albedo * (texture(albedo_texture, p.zy) * w.x + texture(albedo_texture, p.xz) * w.y + texture(albedo_texture, p.xy) * w.z);
	ALBEDO = c.rgb * (1.0 - 0.42 * wetness);
	ROUGHNESS = mix(dry_roughness, 0.25, wetness);
	SPECULAR = 0.48 * wetness;
}
