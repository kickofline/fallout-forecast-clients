shader_type spatial;
render_mode vertex_lighting, diffuse_lambert, specular_blinn;

// UV.x picks the rigid transform. UV.y selects retro-lit, unlit, or lit
// special effects. Opaque effects carry emission in UV2 and COLOR.a, while
// translucent effects keep their real alpha in COLOR.a.
// The loader expands the single transform below to the rig's part count.
uniform mat4 part_0;
uniform bool animated = true;
uniform float snap = 120.0;
uniform float wetness = 0.0;

mat4 part_pose(float part) {
	return part_0;
}

void vertex() {
	if (animated) {
		mat4 pose = part_pose(UV.x);
		VERTEX = (pose * vec4(VERTEX, 1.0)).xyz;
		NORMAL = (pose * vec4(NORMAL, 0.0)).xyz;
	}

	// Only the original opaque, lit surfaces used the PS1 material.
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (snap > 0.0 && UV.y < 0.5) {
		vec2 grid = vec2(snap * VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, snap);
		clip.xy = floor(clip.xy / clip.w * grid + 0.5) / grid * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	if (UV.y < 0.5) {
		float retro_wet = snap > 0.0 ? wetness : 0.0;
		ALBEDO *= 1.0 - 0.42 * retro_wet;
		ROUGHNESS = mix(1.0, 0.25, retro_wet);
		SPECULAR = snap > 0.0 ? 0.48 * retro_wet : 0.5;
	} else if (UV.y < 1.5) {
		// Carry the unlit color through an otherwise vertex-lit surface.
		ALBEDO = vec3(0.0);
		EMISSION = COLOR.rgb;
	} else {
		EMISSION = vec3(UV2, COLOR.a) * 4.0;
	}
	// ALPHA is assigned only in the translucent shader variant.
}
