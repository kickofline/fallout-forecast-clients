shader_type spatial;
// GLES2 port of retro/ps1.gdshader: per-vertex lighting, vertices snapped to
// a coarse clip-space grid (PS1 wobble), nearest-filtered texture, wetness.
render_mode vertex_lighting, diffuse_lambert, specular_blinn;

uniform vec4 albedo : hint_color = vec4(1.0);
uniform sampler2D albedo_texture : hint_albedo;
uniform bool use_texture = false;
uniform bool use_vertex_color = false;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform float snap = 120.0;
uniform float wetness = 0.0;
uniform float dry_roughness = 1.0;

void vertex() {
	UV = UV * uv_scale.xy + uv_offset.xy;
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (snap > 0.0) {
		vec2 grid = vec2(snap * VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, snap);
		clip.xy = floor(clip.xy / clip.w * grid + 0.5) / grid * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	vec4 c = albedo;
	if (use_vertex_color) {
		c *= COLOR;
	}
	if (use_texture) {
		c *= texture(albedo_texture, UV);
	}
	ALBEDO = c.rgb * (1.0 - 0.42 * wetness);
	ROUGHNESS = mix(dry_roughness, 0.25, wetness);
	SPECULAR = 0.48 * wetness;
}
