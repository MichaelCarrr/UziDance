shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, specular_disabled, shadows_disabled;

#include "res://shaders/psx_common.gdshaderinc"

void fragment() {
	vec4 c = psx_shade(UV, v_affine, v_light, v_fog);
	if (c.a < max(alpha_cut, 0.5)) {
		discard;
	}
	ALBEDO = c.rgb;
}
