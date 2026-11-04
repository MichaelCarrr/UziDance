shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, specular_disabled, shadows_disabled;

#include "res://shaders/psx_common.gdshaderinc"

void fragment() {
	vec4 c = psx_shade(UV, v_affine, v_light, v_fog);
	if (c.a < alpha_cut) {
		discard;
	}
	ALBEDO = c.rgb;
}
