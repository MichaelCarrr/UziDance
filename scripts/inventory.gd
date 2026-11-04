class_name Inventory
extends RefCounted
## The run's items and the stat block they produce.

signal changed

var counts := {}                  ## id -> stack count
var order: Array = []             ## ids in the order first picked up
var stats := {}


func _init() -> void:
	recompute()


func count(id: String) -> int:
	return int(counts.get(id, 0))


func total() -> int:
	var n := 0
	for id in counts:
		n += int(counts[id])
	return n


func add(id: String) -> void:
	if not counts.has(id):
		order.append(id)
	counts[id] = count(id) + 1
	recompute()
	changed.emit()


func recompute() -> void:
	var s := {
		"dmg": 1.0, "rate": 1.0, "spread": 1.0, "crit": 0.05, "crit_mul": 2.0, "speed": 1.0, "max_hp": 100.0,
		"air_jumps": 0, "dash_cd": 1.0, "dash_charges": 2, "pierce": 0, "burn": 0.0, "ricochet": 0, "tesla": 0,
		"explosive": 0.0, "lifesteal": 0.0, "gren_cd": 1.0, "gren_dmg": 1.0, "pellets": 0, "magnet": 3.0,
		"score": 1.0, "luck": 0, "revives": 0, "blossom": 0, "enemy_mul": 1.0, "bloodlust": 0.0, "head": 2.0,
		"medkit": 0.0, "pets": 0, "slow_dash": 0.0, "low_hp_dmg": 1.0, "heal_mul": 1.0, "gold": false,
		"cards": 3,
	}
	for id in counts:
		var n: int = counts[id]
		match id:
			"hollow_points":
				s["dmg"] *= 1.0 + 0.15 * n
			"trigger_happy":
				s["rate"] *= pow(1.12, n)
			"laser_sight":
				s["spread"] *= pow(0.8, n)
				s["crit"] += 0.05 * n
			"combat_boots":
				s["speed"] *= 1.0 + 0.09 * n
			"kevlar":
				s["max_hp"] += 25.0 * n
			"feather":
				s["air_jumps"] += n
			"adrenaline":
				s["dash_cd"] *= pow(0.75, n)
			"scavenger":
				s["medkit"] += 0.05 * n
			"magnet":
				s["magnet"] += 3.0 * n
			"grenade_belt":
				s["gren_cd"] *= pow(0.75, n)
				s["gren_dmg"] *= 1.0 + 0.3 * n
			"piercing":
				s["pierce"] += n
			"incendiary":
				s["burn"] += 6.0 * n
			"ricochet":
				s["ricochet"] += n
			"tesla":
				s["tesla"] += n + 1
			"explosive":
				s["explosive"] += 0.12 * n
			"vampire":
				s["lifesteal"] += 2.0 * n
			"bullet_hose":
				s["pellets"] += n
			"lucky_penny":
				s["cards"] += n
				s["luck"] += n
			"bloodlust":
				s["bloodlust"] += 0.25 + 0.1 * (n - 1)
			"third_eye":
				s["head"] += 0.5 * n
			"death_blossom":
				s["blossom"] = maxi(4, 12 - 3 * (n - 1))
			"golden_uzis":
				s["score"] *= pow(1.5, n)
				s["gold"] = true
			"sentry":
				s["pets"] += n
			"bullet_time":
				s["slow_dash"] += 1.2 + 0.6 * (n - 1)
			"heavy_barrel":
				s["crit"] += 0.10 * n
				s["crit_mul"] += 1.0 + 0.5 * (n - 1)
			"second_wind":
				s["revives"] += n
			"megaheart":
				s["max_hp"] += 50.0 * n
			"glass_cannon":
				s["dmg"] *= pow(2.0, n)
				s["max_hp"] *= pow(0.5, n)
			"overclock":
				s["rate"] *= pow(1.8, n)
				s["spread"] *= pow(2.0, n)
			"devils_deal":
				s["score"] *= pow(1.6, n)
				s["luck"] += n
				s["enemy_mul"] *= pow(1.4, n)
			"dead_mans_hand":
				s["low_hp_dmg"] *= pow(2.5, n)
				s["heal_mul"] *= pow(0.5, n)
	s["max_hp"] = maxf(20.0, floorf(s["max_hp"]))
	s["dash_charges"] = 2
	stats = s
