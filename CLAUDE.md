# Claude Code Guide — Elek Games

## Project Location
- Repo root: `Elek-games/`
- Kart Racers: `kart-racers/` (Godot 4 project)

## How to Run
1. Open `kart-racers/project.godot` in Godot 4
2. Press Play (F5)

## Current State
- One kart on a figure-eight dirt road with gentle hills
- Focus: getting the kart **feel** right (steering, speed, acceleration, braking, drifting)
- Settings menu with sliders to tune all dynamics without code changes
- No laps, no NPCs, no weapons, no HUD beyond speedometer

## Code Conventions
- **Language:** GDScript only
- **Renderer:** Compatibility (GL Compatibility)
- **All tunable parameters** live in `Settings` autoload singleton — never hardcode dynamics
- **Controller support:** Xbox gamepad with analog triggers from day one
- **Scene structure:** `node_3d.tscn` → `main_setup.gd` builds everything procedurally

## Key Files
| File | Purpose |
|------|---------|
| `scripts/settings.gd` | Autoload singleton — all kart dynamics, save/load to disk |
| `scripts/player_kart.gd` | CharacterBody3D kart physics, reads Settings every frame |
| `scripts/main_setup.gd` | Builds world: sky, ground, road, hills, kart, HUD, menu |
| `scripts/menu_ui.gd` | Main menu + settings screen with sliders |
| `node_3d.tscn` | Root scene, points to main_setup.gd |

## Stone Stairs Build Order
1. **Kart feel** — steering, speed, drift, weight (NOW)
2. **Track with laps** — checkpoints, lap counter, timer
3. **NPCs** — AI racers with personality
4. **Items** — pickups, attacks, defense (every item has counterplay)
5. **Tracks** — multiple tracks with themes
6. **Battle mode** — arena combat
7. **Split screen** — local multiplayer

## Rules
- Never skip a stair. Each one must feel good before moving on.
- Test with both keyboard and gamepad.
- If a setting should be tunable, put it in `settings.gd`.
- Read `GROWTH.md` before adding any new feature, track, racer, or item.
