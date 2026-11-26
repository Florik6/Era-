# ERA: Восхождение — Architecture

Godot 4.7, GDScript, Mobile renderer (falls back to GL Compatibility). All 3D models, VFX and UI are
generated procedurally at runtime from primitives (no third-party art). Audio is synthesized offline by
`tools/gen_audio.py` (original, committed WAV/OGG).

## Autoloads (project.godot)
| Name | File | Role |
|---|---|---|
| `Events` | scripts/core/events.gd | Global signal bus (damage, kills, quests, chronicle, UI open/close, banners…) |
| `Settings` | scripts/core/settings.gd | Graphics profile (Low/Med/High/Auto), fog density + toggle, audio, controls. `Settings.profile()` |
| `Chronicle` | scripts/history/chronicle.gd | **Unified event journal**. `Chronicle.record(type, actors, data)` → event `{id,type,t,era,pos,place,actors,names,result,conseq,text}` emitted via `Events.chronicle` |
| `Profile` | scripts/core/profile.gd | Meta progress: `Profile.char` (CharData), eras, milestones, achievements, legacy flags, fallen legends, Last Witness |
| `SaveSys` | scripts/save/save_system.gd | Atomic JSON saves with `.bak`, versioned migration. `save_game()`, `load_profile()`, `load_world_state(era)` |
| `Audio` | scripts/audio/audio_manager.gd | `play_sfx(name, pos=null)`, `play_music(track)`, `play_sting`, `set_ambient(name,on)` |
| `Game` | scripts/core/game.gd | Mode, `player`, `world`, time (`game_time`, `hour()`, `is_night()`), `grid` (SpatialGrid), hostility rules `is_enemy/can_damage`, `start(mode, opts)`, `goto_menu()`, `push_ui/pop_ui` (pauses tree), Android lifecycle (autosave on pause/close, back button) |

## Data (static classes)
- `DBEras` (scripts/data/db_eras.gd): `ERAS[5]` (palette, props, enemies, factions, bosses, trial requirements, milestones), `FACTIONS{fid}` (name, era, color, enemies, successor, ranks, units, vendor).
- `DBActors`: `ENEMIES{}`, `BOSSES{}` (phases + ability library), `ARCHETYPES{}` (10 personalities), names/backstories.
- `DBSkills`: `CLASSES`, `TREES{cat}` (weapon mastery trees), `SCHOOLS{school}` (20 spells), `HYBRIDS`.
- `ItemDB` (scripts/items/item_db.gd): `BASES` (~90 items over 5 eras), rarity tables, mods, legendary abilities, mythic mechanics, curses + release methods, uniques, factory `create/create_unique/random_for_era`, `describe(item)` (BBCode card).

Item instances are Dictionaries: `{uid, base, rarity, lvl, upg, qty, stats{}, mods{}, ability, mythic, curse{id,bound,hidden,release,active}, living{stage,xp,path}, history[], name}`.

## Characters
- `CharData` (RefCounted): level/xp, gold, independent `mastery[cat] {lvl,xp,pts,nodes}`, `schools[s] {lvl,xp}`, skill `slots[cat]`, `inv: Inventory`, kills, fame. Same class for player and humanoid NPCs.
- `Inventory`: bag (40) + equip slots (`main off head body hands feet ring amulet module`), stacking, two-handed rules, bound curses (`equip_item`, `unequip`, `release_curse(method)`).
- `Actor` (CharacterBody3D, scripts/actors/actor.gd): vitals, statuses, attack state machine (melee combos, bows, firearms w/ magazine+reload, staff bolts), block/parry/dodge (i-frames), `use_slot(i)`, `use_ability(id)`, `take_damage(info)`, death. Subclasses: `Player`, `NPC` (bots/villagers/soldiers), `Monster`, `Boss`.
- Rigs: `HumanoidRig` (procedural articulated humanoid + gear visuals + procedural animation), `CreatureRig` (wolf, drone, spider, wraith, blob, mimic). `WeaponModels.build(model, item)`.

## Combat
`Combat` (static): `weapon_info`, `deal(att, tgt, info)` (mastery, crit, backstab, stealth, armor, resist, wet+lightning…), `melee(att, range, arc, info)` (arc + vertical + **line of sight**), `aoe(...)` (LOS from center), `fire_weapon`, `on_kill` (xp, mastery, living weapon). `Projectile` (swept ray vs world, sphere vs actors), `Zone` (fire wall, blizzard, time-slow, traps, rifts), `Spells.cast`, `Skills.use`, `LivingWeapon`, `VFX` facade → `VFXManager`.

Physics layers: 1 world/static, 2 actors, 3 (value 4) destructibles. Actors collide with 1|4, not with each other.

## World (game.tscn → scripts/world/world.gd, accessible as `Game.world`)
Members (fixed names):
```
terrain     ChunkStreamer   scripts/world/chunk_streamer.gd
gen         WorldGen        scripts/world/world_gen.gd   (seeded layout + height/biome functions)
day_night   DayNight        scripts/world/day_night.gd
weather     Weather         scripts/world/weather.gd     (is_raining(), current, set_weather())
env, sun    WorldEnvironment / DirectionalLight3D
fx_root     Node3D for projectiles/zones
vfx         VFXManager
orbs        OrbSystem       (XP orbs, MultiMesh)
spawner     Spawner         (spawn_enemy, spawn_bot, spawn_villager, spawn_boss…)
loot        Loot            (drops, chests)
factions    FactionSystem   quests QuestSystem   legends LegendSystem
sim         WorldSim (background simulation)  director WorldDirector (events)
ui          UIManager (CanvasLayer)  hud HUD  touch TouchControls  cam GameCamera
zones       Array of Zone
```
World API used by every subsystem: `ground_height(p)`, `is_water(p)`, `water_level`, `place_name(p)`, `clamp_to_world(actor)`,
`timeslow_at(p, src)`, `freeze_water(p, r)`, `spawn_ice_wall(p, dir, life)`, `camera_shake(a)`, `enter_dimension(kind, opts)`,
`leave_dimension()`, `sync_to_state()`, `on_back_pressed()`.

### WorldGen layout (Dictionaries)
- Settlement: `{id, name, pos:Vector2, type: village|town|city|fort|castle|port, radius, buildings:[{id,pos:Vector2,size:Vector2,rot,kind}], owner:fid, population, guards, security, resources}`
- POI: `{id, type, pos:Vector2, name, data:{}}` — types: `camp lair trial rift cp dungeon altar mirror ruins forge lab workshop terminal fortress relic_site monument witness tourney shrine`
- `ChunkStreamer` emits `chunk_loaded(key: Vector2i, node: Node3D, pois: Array, settlements: Array)` / `chunk_unloaded(key)`; gameplay logic nodes for POIs are attached by world.gd.

### Persistent world state
`Game.world_state` (saved to `user://world_era<N>.json`): `chunks{key: {destroyed:[ids], opened:[ids]}}`, `settlements{id: {...}}`, `points{id: {...}}`, `factions{}`, `records{}` (NPC records / legends), `quests{}`, `director{}`, `fortress{}`, `time`.

## UI
`UIManager.open(name, args := {})` / `close_top()` — screens: `inventory skills factions journal map legends chronicle settings pause dialog trade craft death eras`.
Generic screens: `dialog` args `{title, text, portrait_color, options:[{text, cb: Callable, disabled}]}`; `trade` args `{title, items:Array, sell:bool, price_mult}`;
`craft` args `{title, recipes:[{name, desc, cost:{base_id:n}, gold, cb:Callable}]}`.
Opening a screen calls `Game.push_ui(name)` (pauses the tree, resets touch input); closing calls `Game.pop_ui(name)`.
`UITheme.make()` builds the shared Theme (PT Sans body, Philosopher titles, Ruslan Display logo).

## Living Legends / NPC records
Record: `{id, name, title, archetype, faction, level, renown, kills, boss_kills, rare_items, survivals, alive, legend, commander, leader,
backstory, memories:[{t, text}], rel:{respect, fear, rivalry, gratitude, grudge}, holdings:[], era_history:[], equip:{}, data:{CharData dict},
pos:[x,z], female, look:{}, followers:[], heir_of, cause_of_death, events:[chronicle ids]}`.
Biographies are built only from Chronicle events that reference the record id, so they never contain invented facts.

## Implementation notes (0.9.0)
- Fog: `Settings.fog_value()` caps the user-scaled density at 0.012; `Weather` multiplies it by `Weather.FOG_SCALE` (0.35) and
  writes `fog_mode` only when it changes (Godot 4.7 resets `fog_density` to 1.0 whenever `fog_mode` is assigned).
- World state keys: `points` holds only faction control points (`{owner, type, name}`); per-POI gameplay state (camps cleared,
  rifts closed, mirror used, terminals hacked) lives in `poi_state`.
- `ChunkStreamer.build_poi_decor` is disabled by world.gd; `Poi` builds the visuals/logic, the streamer still adds camp
  palisades/crates/chest, lair destructible pillars and ruin chests.
- Player input can be overridden with `Player.scripted_move` (tests, cutscenes).
- Bot "avoid stronger enemy" rule applies only to `role == "bot"` (contenders); bandits/monsters keep fighting.

## 0.10.0 additions

- **Boot**: `scenes/boot.gd` (loading screen, threaded menu load, error/safe-mode buttons) + `scripts/core/boot_guard.gd`
  (`user://boot_state.cfg` stage marker → automatic safe graphics after a failed start, `user://boot.log`).
  Two export presets: "Android" (Mobile/Vulkan) and "Android GL" (`--rendering-method gl_compatibility`).
- **Spatial grid**: static interactables register with `Game.grid.insert_deferred(node, cat)` (their final position at end
  of frame). Never call `insert(self, global_position, …)` from `_ready()`.
- **Curses**: `scripts/items/curses.gd` (`Curses`) — severity/kind, `rituals_for(item, player, station)`, `pay()` only
  after success, `apply(item, effect, name)`. UI `scripts/ui/screens/altar.gd`; in-world sequence
  `scripts/world/altar_ritual.gd` (`world.active_ritual` locks gear).
- **Rifts**: `poi.gd` rift label/access/walk-through, `world.portal_block_until`, `enter_dimension(kind, {return_pos})`;
  `dimension.gd` stages (guards → `RiftAnchor` ×3 → echo boss with meta `rift_echo`), retreat `DimensionExit`.
- **Optional world subsystems** (`world.sys(name)`, attached from `world.gd`): `road_encounters` (25 templates),
  `discovery`, `tracking`, `living_pois`, `traces`, `cinematic` (CanvasLayer), `music` (`MusicDirector`).
  Each has `setup(world)` and keeps its state in `Game.world_state` (saved per era).
- **Touch controls**: fixed stick, `Settings.ui_layout` (element → {x, y fractions of the safe area, s}), `ui_opacity`,
  `joy_sensitivity`, `joy_deadzone`; editor `scripts/ui/screens/layout_editor.gd`.
- **Settlements**: `world.activity_points(sid)` (streamer layout points or fallback) → villager `job` meta → BotBrain
  `work` goal; `factions.change_settlement_owner` recolours banners.

## 0.11.0 additions (Visual Ascension)

- `Resonance` (`scripts/combat/resonance.gd`, optional subsystem "resonance"): imprint list fed by
  `Spells._effect`, `Projectile._end`, `Zone.create` and mid-air projectile meetings
  (`Projectile._check_meet`, swept segments); `_add` → threshold/cool-down/limit checks → `_react`
  (reaction zones steam/node/vortex/instability, `params.no_res` so they never re-feed) →
  `_check_catastrophe` → `WorldDirector.resonance_catastrophe` (event "resonance": anomaly zone,
  `BotBrain.flee_from` / `BotBrain.investigate`, chronicle `resonance_catastrophe`, temporary rift POI).
- `WorldDirector.start_black_storm(center, opts)` / `_tick_black_storm`: event "black_storm", covens
  spawned through `Spawner.spawn_bot` and registered in `WorldSim.active`.
- `Clash` (`scripts/combat/clash.gd`): called from `Actor._on_impact` (melee) and `Skills._act`
  (heavy skills); `Clash.boss_perfect_parry` from `Actor._parry` when the parried info has `heavy`.
- `Combat.deal` now sets `info.src`; `vulnerable` status multiplies damage ×1.4.
- `VFXManager` light pool (`_pool_light`, `pool_active`, `pool_peak`); decals `wet`, `rune`, `electric`.
- Shader globals `weather_wet`, `weather_snow` (project.godot `[shader_globals]`), driven by
  `Weather._update_surfaces`; used by the terrain and road shaders.
- `DayNight.apply_era_grade`, `HistoricalEchoes` (`scripts/world/echoes.gd`, subsystem "echoes"),
  `GearFX` (`scripts/vfx/gear_fx.gd`, from `HumanoidRig.set_gear`), `ResonanceFX`.
- `Settings`: `Quality.MAX` (appended after AUTO), `VIS_KEYS` (separate visual settings, section "vis").
- `SmokeTest` (`scripts/core/smoke_test.gd`): `--smoke-test` command-line self check.
- iOS: preset 2 in `export_presets.cfg`, `tools/export_ios.sh`, `tools/verify_ipa.sh`,
  `.github/workflows/ios.yml`.

## Tests
`tools/check.sh` (compile all), `tests/logic_test.tscn` (67 checks), `tests/world_logic_test.tscn` (122 checks),
`tests/game_smoke.tscn`, `tests/modes_smoke.tscn`, `tests/world_test.tscn`, `tests/ui_test.tscn` (screenshots; run with
`VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json xvfb-run -a godot --path . --rendering-method mobile --rendering-driver vulkan <scene>`).
