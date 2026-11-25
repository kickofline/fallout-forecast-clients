shader_type canvas_item;
// Background sky for the run viewport (Environment BG_CANVAS). Same gradient
// as Godot 3's ProceduralSky (horizon->top with ease(sky_curve), ground
// horizon->bottom with ease(ground_curve), sun disc with an eased halo), but
// evaluated per pixel at the low 3D resolution. ProceduralSky regenerates a
// 1024px texture plus radiance on the CPU whenever a colour changes, which
// stalled the head unit for ~1 s every few seconds as the storm ramped.

uniform vec4 sky_top : hint_color = vec4(0.11, 0.086, 0.22, 1.0);
uniform vec4 sky_horizon : hint_color = vec4(0.85, 0.345, 0.42, 1.0);
uniform vec4 ground_horizon : hint_color = vec4(0.42, 0.227, 0.333, 1.0);
uniform vec4 ground_bottom : hint_color = vec4(0.102, 0.078, 0.149, 1.0);
uniform vec4 sun_color : hint_color = vec4(1.0, 0.66, 0.52, 1.0);
uniform float sky_curve = 0.12;
uniform float ground_curve = 0.02;
uniform float energy = 1.0;
uniform vec3 sun_dir = vec3(0.0, 0.208, -0.978);
uniform float sun_angle_min = 1.0;
uniform float sun_angle_max = 8.0;
// Camera: world basis columns and tan(vfov/2), aspect.
uniform vec3 cam_x = vec3(1.0, 0.0, 0.0);
uniform vec3 cam_y = vec3(0.0, 1.0, 0.0);
uniform vec3 cam_z = vec3(0.0, 0.0, 1.0);
uniform float tan_half_fov = 0.767;
uniform float aspect = 1.777;

// Godot's ease() for positive curves (all ProceduralSky defaults are > 0).
float ease_pos(float x, float c) {
	x = clamp(x, 0.0, 1.0);
	if (c < 1.0) {
		return 1.0 - pow(1.0 - x, 1.0 / c);
	}
	return pow(x, c);
}

void fragment() {
	vec2 ndc = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	vec3 d = normalize(cam_x * (ndc.x * tan_half_fov * aspect) + cam_y * (ndc.y * tan_half_fov) - cam_z);
	float v_angle = acos(clamp(d.y, -1.0, 1.0));
	vec3 col;
	if (d.y < 0.0) {
		float c = (v_angle - 1.5707963) / 1.5707963;
		col = mix(ground_horizon.rgb, ground_bottom.rgb, ease_pos(c, ground_curve));
	} else {
		float c = v_angle / 1.5707963;
		col = mix(sky_horizon.rgb, sky_top.rgb, ease_pos(1.0 - c, sky_curve));
		float sun_angle = degrees(acos(clamp(dot(sun_dir, d), -1.0, 1.0)));
		if (sun_angle < sun_angle_min) {
			col = sun_color.rgb;
		} else if (sun_angle < sun_angle_max) {
			float c2 = ease_pos((sun_angle - sun_angle_min) / (sun_angle_max - sun_angle_min), 0.05);
			col = mix(sun_color.rgb, col, c2);
		}
	}
	COLOR = vec4(col * energy, 1.0);
}
