// Shared PSX surface: vertex snapping (jitter), affine texture warping, per-vertex
// Gouraud lighting and per-vertex depth fog. Lighting is driven by global uniforms
// so the whole stadium can switch between sunset and night in one place.

global uniform vec3 psx_light_dir;
global uniform vec4 psx_light_color;
global uniform vec4 psx_ambient;
global uniform vec4 psx_fog_color;
global uniform vec2 psx_fog_range;
global uniform vec2 psx_snap;
global uniform float psx_affine;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable, hint_default_white;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float lit : hint_range(0.0, 1.0) = 1.0;
uniform float fog_amount : hint_range(0.0, 1.0) = 1.0;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.0;
uniform float snap_amount : hint_range(0.0, 1.0) = 1.0;
uniform float affine_amount : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_light;
varying float v_fog;
varying vec3 v_affine;

void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float ndl = max(dot(n, normalize(-psx_light_dir)), 0.0);
	vec3 light = psx_ambient.rgb + psx_light_color.rgb * ndl;
	v_light = mix(vec3(1.0), light, lit) * COLOR.rgb;

	vec4 view = VIEW_MATRIX * world;
	float dist = length(view.xyz);
	v_fog = clamp((dist - psx_fog_range.x) / max(0.001, psx_fog_range.y - psx_fog_range.x), 0.0, 1.0) * fog_amount;

	vec4 clip = PROJECTION_MATRIX * view;
	if (snap_amount > 0.0 && psx_snap.x > 0.0 && clip.w > 0.0) {
		vec2 grid = psx_snap * 0.5;
		vec2 ndc = clip.xy / clip.w;
		ndc = round(ndc * grid) / grid;
		clip.xy = mix(clip.xy, ndc * clip.w, snap_amount);
	}
	POSITION = clip;

	vec2 uv = UV * uv_scale + uv_offset;
	v_affine = vec3(uv * clip.w, clip.w);
}

// Varyings are passed in explicitly so this helper is safe to call from fragment().
vec4 psx_shade(vec2 base_uv, vec3 aff, vec3 light, float fog) {
	vec2 uv_affine = aff.xy / aff.z;
	vec2 uv = mix(base_uv * uv_scale + uv_offset, uv_affine, psx_affine * affine_amount);
	vec4 tex = texture(albedo_tex, uv);
	vec3 col = tex.rgb * albedo.rgb * light + emission.rgb;
	col = mix(col, flash_color.rgb, flash);
	col = mix(col, psx_fog_color.rgb, fog);
	return vec4(col, tex.a * albedo.a);
}
