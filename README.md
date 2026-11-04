# UZI RUSH - Endless Mode

A first-person PSX arena shooter built from the core of *Sky Slugger*: the same low-poly,
vertex-jitter, affine-texture, dithered 15-bit look and the same roguelike item-card drafting -
but the bat is gone and you **dual-wield two Uzis**.

**Play it in the browser:** https://michaelcarrr.github.io/uzi-rush/

## How it plays

- Survive **endless waves** of robots in a neon rooftop arena. Every wave is bigger and tougher.
- After every wave you **draft 1 of 3 item cards**. Items stack and combine into builds.
- Every **5th wave is a TITAN boss** (volley, summons and a floor shockwave you have to jump).
- Kills chain into a **combo multiplier**; headshots and crits hit harder; drops include medkits
  and rare power-ups (RAMPAGE, BULLET TIME, MIDAS x3).
- Records (high score, best wave, best combo) are saved in the browser.

### Controls

| Input | Action |
|---|---|
| WASD | move |
| Mouse | aim (click to lock the pointer; arrow keys also look) |
| Left click | fire both Uzis (alternating, full auto) |
| Right click | focus: tighter spread, slower movement |
| Space | jump (crates are jumpable, extra air jumps from items) |
| Shift | dash (brief invincibility, 2 charges) |
| Q / G | grenade |
| Esc | pause |

Gamepad works too (sticks, triggers, A / B / X / Start).

### Enemies

| Enemy | Behaviour |
|---|---|
| SCRAPPER | rusty melee zombie-bot, swarms you |
| SENTRY | arm cannon, keeps its distance and strafes, telegraphs each shot |
| BRUTE | armoured charger - winds up red, then rams |
| HOVERBOT | flying burst-shooter |
| TITAN (boss) | orb volley, shockwave slam, summons scrappers |

### Items (30)

Four rarities in Risk of Rain 2 colours - **white common, green uncommon, red rare, blue cursed**
(strong, with a price). Highlights: PIERCING ROUNDS, INCENDIARY, RICOCHET, TESLA COIL, EXPLOSIVE TIPS,
BULLET HOSE (+1 bullet per shot), SENTRY DRONE (orbiting auto-turret), DEATH BLOSSOM (bullet nova every
N kills), BULLET TIME (dash slows the world), SECOND WIND (revive), and the cursed GLASS CANNON,
OVERCLOCK, DEVIL'S DEAL and DEAD MAN'S HAND. See `scripts/items.gd` and `scripts/inventory.gd`.

## Tech

- **Godot 4.7** (GL Compatibility renderer), exported to the web (no threads, no special headers).
- 3D renders into a 427x240 SubViewport and is upscaled through a Bayer-dither / 15-bit post shader.
  The Uzis render in a second transparent viewport so they never clip into walls.
- All models are modelled in **Blender** by script: `tools/blender_models.py`
  (`blender -b --factory-startup --python tools/blender_models.py`). It also writes
  `levels/arena.json`, the collision boxes and enemy gates, so the model and the game agree.
- Textures (`tools/gen_textures.py`) and audio (`tools/gen_audio.py`) are generated procedurally.
- Collision, hitscan and AI are plain maths (no physics engine): see `scripts/world.gd`,
  `scripts/player.gd`, `scripts/enemy.gd`.

### Build / run

```bash
# run
godot --path .
# regenerate assets
python tools/gen_textures.py && python tools/gen_audio.py
blender -b --factory-startup --python tools/blender_models.py
# web export (needs the Godot 4.7 web export templates)
godot --headless --path . --export-release "Web" build/web/index.html
python -m http.server 8070 --directory build/web
```

Debug URLs on the web build: `?autoplay` (a bot plays), `?gallery` (frozen enemy line-up), `?results`.
Headless smoke test: `godot --headless --path . --fixed-fps 60 --quit-after 30000 -- --autoplay`.
