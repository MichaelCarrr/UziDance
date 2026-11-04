shader_type canvas_item;

// Final PSX pass over the low-res 3D frame: ordered 4x4 Bayer dithering and
// 15-bit colour (32 levels per channel), plus a soft CRT vignette.

uniform vec2 src_size = vec2(427.0, 240.0);
uniform float color_levels = 32.0;
uniform float dither_amount : hint_range(0.0, 2.0) = 1.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.35;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);

const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	ivec2 p = ivec2(floor(UV * src_size));
	int idx = (p.x % 4) + (p.y % 4) * 4;
	float b = BAYER[idx] / 16.0 - 0.5;
	vec3 col = c.rgb + b * dither_amount / color_levels;
	col = floor(col * (color_levels - 1.0) + 0.5) / (color_levels - 1.0);
	vec2 d = UV - 0.5;
	col *= 1.0 - dot(d, d) * vignette;
	col = mix(col, flash_color.rgb, flash);
	COLOR = vec4(clamp(col, 0.0, 1.0), c.a);
}
