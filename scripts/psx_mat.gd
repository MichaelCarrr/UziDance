class_name PSXMat
extends RefCounted
## Converts imported glTF materials (matched by name) into PSX ShaderMaterials.

const OPAQUE := preload("res://shaders/psx_opaque.gdshader")
const CUTOUT := preload("res://shaders/psx_cutout_2s.gdshader")
const TRANSPARENT := preload("res://shaders/psx_transparent.gdshader")

## tex: texture name in assets/textures; color: albedo multiplier; shader: opaque/cutout/trans;
## lit/fog/snap/affine: per-material PSX knobs; emit: emission colour.
const DEFS := {
	# the Uzis
	"GunMetal": {"tex": "metal", "color": Color(0.55, 0.56, 0.62)},
	"GunDark": {"tex": "noise", "color": Color(0.12, 0.12, 0.15)},
	"Glove": {"tex": "noise", "color": Color(0.16, 0.16, 0.2)},
	"Sleeve": {"tex": "noise", "color": Color(0.7, 0.28, 0.62)},
	"Brass": {"tex": "noise", "color": Color(1.0, 0.8, 0.25)},
	# enemies
	"BotBody": {"tex": "rust"},
	"BotDark": {"tex": "plate", "color": Color(0.32, 0.32, 0.4)},
	"BotPanel": {"tex": "noise", "color": Color(0.25, 0.95, 0.9), "lit": 0.0, "emit": Color(0.0, 0.18, 0.18)},
	"EyeGlow": {"color": Color(1.0, 0.15, 0.1), "lit": 0.0, "emit": Color(0.5, 0.0, 0.0)},
	"VisorGlow": {"color": Color(1.0, 0.92, 0.25), "lit": 0.0, "emit": Color(0.4, 0.3, 0.0)},
	"GunnerBody": {"tex": "plate", "color": Color(0.45, 0.4, 0.95)},
	"BruteArmor": {"tex": "plate", "color": Color(0.62, 0.64, 0.7)},
	"BruteDark": {"tex": "plate", "color": Color(0.24, 0.24, 0.28)},
	"BossArmor": {"tex": "plate", "color": Color(0.95, 0.2, 0.28)},
	"DroneBody": {"tex": "plate", "color": Color(0.3, 0.95, 0.5)},
	"Rotor": {"tex": "noise", "color": Color(0.75, 0.75, 0.8)},
	# pickups
	"Medkit": {"tex": "noise", "color": Color(0.95, 0.95, 0.95), "lit": 0.5},
	"MedCross": {"color": Color(0.9, 0.08, 0.1), "lit": 0.0, "emit": Color(0.3, 0.0, 0.0)},
	"Orb": {"color": Color(1.0, 0.85, 0.2), "lit": 0.0, "emit": Color(0.3, 0.2, 0.0), "fog": 0.2},
	"Grenade": {"tex": "noise", "color": Color(0.32, 0.46, 0.26)},
	# arena
	"Floor": {"tex": "floor", "affine": 0.5},
	"StageTop": {"tex": "stage_top", "affine": 0.5},
	"Stage": {"tex": "concrete", "color": Color(0.5, 0.5, 0.7)},
	"Wall": {"tex": "wall"},
	"Hazard": {"tex": "hazard", "lit": 0.8},
	"Crate": {"tex": "crate"},
	"Barrier": {"tex": "barrier"},
	"Pillar": {"tex": "concrete", "color": Color(0.7, 0.68, 0.85)},
	"NeonPink": {"color": Color(1.0, 0.25, 0.75), "lit": 0.0, "fog": 0.4, "emit": Color(0.3, 0.0, 0.2)},
	"NeonCyan": {"color": Color(0.2, 0.95, 1.0), "lit": 0.0, "fog": 0.4, "emit": Color(0.0, 0.25, 0.3)},
	"Gate": {"color": Color(0.03, 0.01, 0.05), "lit": 0.0},
	"Sign": {"tex": "sign", "lit": 0.0, "fog": 0.3, "affine": 0.0},
	"Skyline": {"tex": "skyline", "shader": "cutout", "lit": 0.0, "fog": 0.55, "color": Color(0.9, 0.5, 1.0)},
	"Sky": {"tex": "sky_neon", "lit": 0.0, "fog": 0.0, "snap": 0.0, "affine": 0.0},
	"Clouds": {"tex": "clouds", "lit": 0.0, "fog": 0.35, "affine": 0.3},
}

static var _textures := {}


static func tex(name: String) -> Texture2D:
	if not _textures.has(name):
		_textures[name] = load("res://assets/textures/%s.png" % name)
	return _textures[name]


static func make(def: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	match def.get("shader", "opaque"):
		"cutout":
			m.shader = CUTOUT
		"trans":
			m.shader = TRANSPARENT
		_:
			m.shader = OPAQUE
	if def.has("tex"):
		m.set_shader_parameter("albedo_tex", tex(def["tex"]))
	m.set_shader_parameter("albedo", def.get("color", Color.WHITE))
	m.set_shader_parameter("lit", def.get("lit", 1.0))
	m.set_shader_parameter("fog_amount", def.get("fog", 1.0))
	m.set_shader_parameter("snap_amount", def.get("snap", 1.0))
	m.set_shader_parameter("affine_amount", def.get("affine", 1.0))
	if def.has("emit"):
		m.set_shader_parameter("emission", def["emit"])
	return m


## Replace every surface material under `root` with a PSX material. Returns {name: ShaderMaterial}.
## overrides: {material name: def} replaces the stock definition (e.g. recolour an enemy).
static func apply(root: Node, overrides: Dictionary = {}) -> Dictionary:
	var made := {}
	_apply_rec(root, made, overrides)
	return made


static func _apply_rec(n: Node, made: Dictionary, overrides: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(i)
				var key := src.resource_name if src != null else ""
				if not made.has(key):
					var def: Dictionary = overrides.get(key, DEFS.get(key, {}))
					if def.is_empty():
						push_warning("PSXMat: no definition for material '%s' on %s" % [key, mi.name])
						def = {"color": Color(1, 0, 1)}
					made[key] = make(def)
				mi.set_surface_override_material(i, made[key])
	for c in n.get_children():
		_apply_rec(c, made, overrides)


## Simple unshaded billboard/particle material.
static func sprite_material(texture_name: String, additive: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex(texture_name)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m
