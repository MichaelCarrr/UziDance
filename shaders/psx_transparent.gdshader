shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, specular_disabled, shadows_disabled;

#include "res://shaders/psx_common.gdshaderinc"

void fragment() {
	vec4 c = psx_shade(UV, v_affine, v_light, v_fog);
	ALBEDO = c.rgb;
	ALPHA = c.a * COLOR.a;
}
