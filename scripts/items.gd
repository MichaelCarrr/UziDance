class_name Items
extends RefCounted
## Item database + card rolling. Rarity colours follow Risk of Rain 2: white common, green
## uncommon, red rare, blue cursed (strong, with a price).

const COLORS := {
	"common": Color(0.92, 0.92, 0.96),
	"uncommon": Color(0.35, 0.95, 0.42),
	"rare": Color(1.0, 0.3, 0.32),
	"cursed": Color(0.42, 0.62, 1.0),
}
const RARITY_NAMES := {"common": "COMMON", "uncommon": "UNCOMMON", "rare": "RARE", "cursed": "CURSED"}

## icon = index into assets/textures/items.png (8x8 cells, 8 per row; order in tools/gen_textures.py)
const DB := {
	# ---- common
	"hollow_points": {"name": "HOLLOW POINTS", "rarity": "common", "icon": 0,
		"desc": "+15% BULLET DAMAGE", "stack": "+15% PER STACK"},
	"trigger_happy": {"name": "TRIGGER HAPPY", "rarity": "common", "icon": 1,
		"desc": "+12% FIRE RATE", "stack": "x1.12 PER STACK"},
	"laser_sight": {"name": "LASER SIGHT", "rarity": "common", "icon": 2,
		"desc": "-20% SPREAD, +5% CRIT CHANCE", "stack": "STACKS"},
	"combat_boots": {"name": "COMBAT BOOTS", "rarity": "common", "icon": 3,
		"desc": "+9% MOVE SPEED", "stack": "+9% PER STACK"},
	"kevlar": {"name": "KEVLAR VEST", "rarity": "common", "icon": 17,
		"desc": "+25 MAX HP AND HEAL 25", "stack": "+25 PER STACK"},
	"feather": {"name": "PIGEON FEATHER", "rarity": "common", "icon": 5,
		"desc": "+1 AIR JUMP", "stack": "+1 JUMP PER STACK"},
	"adrenaline": {"name": "ADRENALINE", "rarity": "common", "icon": 26,
		"desc": "DASH RECHARGES 25% FASTER", "stack": "x0.75 PER STACK"},
	"scavenger": {"name": "SCAVENGER", "rarity": "common", "icon": 24,
		"desc": "+5% MEDKIT DROP CHANCE", "stack": "+5% PER STACK"},
	"magnet": {"name": "COIN MAGNET", "rarity": "common", "icon": 7,
		"desc": "PICKUPS FLY TO YOU FROM FAR AWAY", "stack": "+3M RANGE"},
	"grenade_belt": {"name": "GRENADE BELT", "rarity": "common", "icon": 14,
		"desc": "GRENADE COOLDOWN -25%, +30% DMG", "stack": "STACKS"},
	# ---- uncommon
	"piercing": {"name": "PIERCING ROUNDS", "rarity": "uncommon", "icon": 8,
		"desc": "BULLETS PASS THROUGH +1 ENEMY", "stack": "+1 PER STACK"},
	"incendiary": {"name": "INCENDIARY", "rarity": "uncommon", "icon": 9,
		"desc": "BULLETS SET ENEMIES ON FIRE", "stack": "+6 DPS PER STACK"},
	"ricochet": {"name": "RICOCHET", "rarity": "uncommon", "icon": 10,
		"desc": "BULLETS BOUNCE TO A NEARBY ENEMY", "stack": "+1 BOUNCE PER STACK"},
	"tesla": {"name": "TESLA COIL", "rarity": "uncommon", "icon": 11,
		"desc": "EVERY 5TH SHOT ZAPS 2 ENEMIES", "stack": "+1 TARGET PER STACK"},
	"explosive": {"name": "EXPLOSIVE TIPS", "rarity": "uncommon", "icon": 12,
		"desc": "12% OF BULLETS EXPLODE", "stack": "+12% PER STACK"},
	"vampire": {"name": "VAMPIRE FANGS", "rarity": "uncommon", "icon": 13,
		"desc": "KILLS HEAL 2 HP", "stack": "+2 PER STACK"},
	"bullet_hose": {"name": "BULLET HOSE", "rarity": "uncommon", "icon": 15,
		"desc": "EVERY SHOT FIRES +1 BULLET", "stack": "+1 BULLET PER STACK"},
	"lucky_penny": {"name": "LUCKY PENNY", "rarity": "uncommon", "icon": 6,
		"desc": "DRAW 1 MORE CARD, BETTER ODDS", "stack": "+1 CARD PER STACK"},
	"bloodlust": {"name": "BLOODLUST", "rarity": "uncommon", "icon": 16,
		"desc": "KILLS GIVE +25% SPEED AND FIRE RATE FOR 3S", "stack": "+10% PER STACK"},
	"third_eye": {"name": "THIRD EYE", "rarity": "uncommon", "icon": 27,
		"desc": "HEADSHOTS DO +50% DAMAGE", "stack": "+50% PER STACK"},
	# ---- rare
	"death_blossom": {"name": "DEATH BLOSSOM", "rarity": "rare", "icon": 19,
		"desc": "EVERY 12 KILLS A NOVA OF BULLETS ERUPTS", "stack": "-3 KILLS PER STACK"},
	"golden_uzis": {"name": "GOLDEN UZIS", "rarity": "rare", "icon": 20,
		"desc": "x1.5 SCORE, GOLDEN TRACERS", "stack": "x1.5 PER STACK"},
	"sentry": {"name": "SENTRY DRONE", "rarity": "rare", "icon": 30,
		"desc": "A DRONE ORBITS YOU AND SHOOTS ENEMIES", "stack": "+1 DRONE PER STACK"},
	"bullet_time": {"name": "BULLET TIME", "rarity": "rare", "icon": 31,
		"desc": "DASHING SLOWS THE WORLD FOR 1.2S", "stack": "+0.6S PER STACK"},
	"heavy_barrel": {"name": "HEAVY BARREL", "rarity": "rare", "icon": 22,
		"desc": "CRITS HIT FOR x3, +10% CRIT CHANCE", "stack": "+10% / +0.5x"},
	"second_wind": {"name": "SECOND WIND", "rarity": "rare", "icon": 29,
		"desc": "REVIVE ONCE AT HALF HP", "stack": "+1 REVIVE"},
	"megaheart": {"name": "MEGA HEART", "rarity": "rare", "icon": 4,
		"desc": "+50 MAX HP AND FULL HEAL", "stack": "+50 PER STACK"},
	# ---- cursed
	"glass_cannon": {"name": "GLASS CANNON", "rarity": "cursed", "icon": 21,
		"desc": "x2 DAMAGE BUT MAX HP IS HALVED", "stack": "x2 / x0.5 PER STACK"},
	"overclock": {"name": "OVERCLOCK", "rarity": "cursed", "icon": 28,
		"desc": "x1.8 FIRE RATE BUT x2 SPREAD", "stack": "STACKS"},
	"devils_deal": {"name": "DEVIL'S DEAL", "rarity": "cursed", "icon": 23,
		"desc": "x1.6 SCORE, +1 LUCK, BUT 40% MORE ENEMIES", "stack": "STACKS"},
	"dead_mans_hand": {"name": "DEAD MAN'S HAND", "rarity": "cursed", "icon": 25,
		"desc": "x2.5 DAMAGE UNDER 35% HP, HEALING HALVED", "stack": "STACKS"},
}

const ORDER := ["common", "uncommon", "rare", "cursed"]


static func ids_of(rarity: String) -> Array:
	var out: Array = []
	for id in DB.keys():
		if DB[id]["rarity"] == rarity:
			out.append(id)
	return out


## Roll `count` distinct cards. luck shifts odds toward better rarity; min_rarity (0..2) floors them.
static func roll_cards(count: int, luck: int, min_rarity: int = 0, rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var picked: Array = []
	var guard := 0
	while picked.size() < count and guard < 200:
		guard += 1
		var r := rng.randf()
		var cursed_p := 0.08
		var rare_p := 0.10 + 0.03 * luck
		var unc_p := 0.30 + 0.04 * luck
		var rarity := "common"
		if r < cursed_p:
			rarity = "cursed"
		elif r < cursed_p + rare_p:
			rarity = "rare"
		elif r < cursed_p + rare_p + unc_p:
			rarity = "uncommon"
		if min_rarity > 0 and rarity == "common":
			rarity = "uncommon"
		if min_rarity > 1 and rarity == "uncommon":
			rarity = "rare"
		var pool := ids_of(rarity)
		var id: String = pool[rng.randi() % pool.size()]
		if not picked.has(id):
			picked.append(id)
	return picked
