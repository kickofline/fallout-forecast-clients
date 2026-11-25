extends ColorRect
## BroadcastUI.backdrop(): night-gradient with a pink horizon glow, faint
## scanlines and a perspective-ish grid in the lower third.

const CODE = """shader_type canvas_item;
uniform float t = 0.0;
void fragment() {
	vec2 uv = UV;
	vec3 base = mix(vec3(.025,.055,.09), vec3(.07,.16,.20), 1.0-uv.y);
	float horizon = exp(-abs(uv.y-.64)*16.0);
	base += vec3(.18,.045,.09)*horizon;
	float lines = step(.97,fract(uv.y*180.0))*.025;
	float grid = step(.985,fract(uv.x*24.0)) + step(.98,fract(uv.y*32.0 + t*0.05));
	base += vec3(.06,.16,.17)*grid*smoothstep(.55,1.0,uv.y);
	COLOR = vec4(base-lines,1.0);
}"""

var _mat = ShaderMaterial.new()
var _t = 0.0


func _ready() -> void:
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader = Shader.new()
	shader.code = CODE
	_mat.shader = shader
	material = _mat


func _process(delta: float) -> void:
	if visible:
		_t += delta
		_mat.set_shader_param("t", _t)
