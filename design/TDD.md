# NIGHTBEAM — Technical Design Document (v1)

Owner: tl-1 (GJ-3). Source of truth for rules and numbers: `GDD.md`. This document says *where* the
rules live and *how* the pieces talk. If this doc and the GDD disagree on a rule, the GDD wins; if they
disagree on a file/API, this doc wins (change it via a comment on the ticket, not silently).

## Engine & versions
- **Godot 4.6.1-stable** (standard build, not mono), **GDScript only**, typed everywhere.
  Binary: any Godot 4.6.x build (console build on Windows for headless runs)
  (also in `.studio/config.json` → `engines.godot`). The playbook's default path is wrong here.
- Plugins: `addons/playtest_bridge` (vendored copy of Playtest Lab's Godot bridge, MIT-style, ours to use;
  nobody edits it — refresh by re-copying from the skill). No other plugins, no imported assets.

## Target platforms & budgets
| Item | Value |
|---|---|
| Platform | Windows desktop (web export = stretch, M2+) |
| Base viewport | **960 × 540**, stretch mode `canvas_items`, aspect `keep` (letterbox) |
| Sim rate | **60 Hz fixed** (`physics/common/physics_ticks_per_second=60`), `DT = 1/60`, one `sim.step()` per physics tick |
| Render | whatever the monitor gives (vsync); `_draw()` only reads the latest observation |
| Frame budget | sim step ≤ 0.5 ms at 64 entities; `_draw` ≤ 4 ms; no per-frame allocations in the sim beyond the observation dict |
| Headless speed | BotRunner: ≥ 100 seeds × 3 skills × 180 s in < 60 s wall (≈ 3.2 M ticks; pure RefCounted, no scene tree) |
| Memory / build | < 100 MB RAM, < 60 MB exported build |
| Input | Keyboard primary (A/D, ←/→, Space, R, N, Esc). Mouse in M2, mapped to the same `turn` value |

## Architecture

### The one rule: sim/view split
```
             action Dictionary {"turn": float, "flare": bool}
PlayerInput ─────────────┐
NightbeamBots ───────────┼──► NightbeamSim.step(action)   (pure, seeded, RefCounted, 60 Hz)
PlaytestTarget ──────────┘              │
                                        ▼ get_observation() -> Dictionary  (read-only snapshot)
                     ┌──────────────────┼──────────────────────┐
                NightbeamView        HudView          NightbeamInvariants / BotRunner / PlaytestTarget
                (_draw, fx, audio)   (Control)        (checks, CSV, bridge)
```
- `NightbeamSim` (`Scripts/Sim/NightbeamSim.gd`, `class_name NightbeamSim extends RefCounted`) owns **all**
  gameplay state and rules. It owns its own `RandomNumberGenerator` seeded from the constructor seed.
  Forbidden inside `Scripts/Sim/`: Node/SceneTree calls, `Input`, `Time`/`OS` clocks, global `randf()/randi()`,
  `await`, signals, iterating a Dictionary whose key order could differ between runs.
- Everything outside `Scripts/Sim/` treats the sim as a black box: it calls `step(action)` and reads
  `get_observation()`. The view never writes sim members. Visual/audio randomness uses a **separate view RNG**.
- Tuning lives in `res://Data/Tuning/NightbeamTuning.tres` (`class_name NightbeamTuning extends Resource`).
  The sim receives the tuning object in its constructor; it never `load()`s anything itself.
- Events (save bell, foghorn, flare whoosh) come from `obs.events` — the list of things that happened in the
  **last** tick — so the view never has to diff entity lists. The view turns them into signals.

### Scene / module tree
```
Main.tscn  (root: Node "Main", script Scripts/Game/GameFlow.gd)           ← game flow, owns the sim instance
├── NightbeamView   (Node2D, Scripts/View/NightbeamView.gd)                ← bay, beam, ships, shades, fx (_draw)
└── Hud             (CanvasLayer)
    └── HudView     (Control, full-rect anchors, Scripts/View/HudView.gd)  ← pips, score, title/end cards
PlaytestHarness.tscn (root: Node "PlaytestHarness", script Scripts/Playtest/PlaytestTarget.gd)
                                                                           ← bots only; no view, no input
PersonaHarness.tscn (root: Node "PersonaHarness", script Scripts/Playtest/PersonaTarget.gd)
└── Main          (instance of Main.tscn)                                  ← AI persona sessions (GJ-10/GJ-14):
                                                                             real view + HUD, windowed
Autoload: PlaytestBridge = res://addons/playtest_bridge/playtest_bridge.gd (no-op unless --playtestPort)
```
No other autoloads. GameFlow is not an autoload: it is the Main scene root.

### Frame / tick flow (Main.tscn)
1. `GameFlow._physics_process(_delta)` (60 Hz): if the flow state is `NIGHT` and not paused →
   `sim.step(PlayerInput.read_action(obs, tuning))`, then `obs = sim.get_observation()`,
   then `view.show_observation(obs)` and `hud.show_observation(obs)`; emits signals for `obs.events`;
   if `sim.is_over()` → switch to `END`.
2. `NightbeamView._process(delta)`: advances view-only effects (shake, wake buffer, flare ring), `queue_redraw()`.
3. `NightbeamView._draw()`: draws only from the last observation + view-only fx state.

Flow states (GameFlow, B): `TITLE → NIGHT ⇄ PAUSED → END`; `R` = retry same seed, `N` = new night
(new seed from the view RNG), `Esc` = pause. Seed source: `--seed=N` user arg (`OS.get_cmdline_user_args()`),
else a random seed from GameFlow's own RNG (`randomize()` is allowed in GameFlow, never in the sim).

### Signals (declared in GameFlow, B)
`ship_saved(entity_id: int)`, `reef_hit(hull_left: int)`, `flare_fired(charges_left: int)`,
`run_ended(result: int)` (`NightbeamSim.State`). Audio (M2) listens to these.

### Save/load & settings
No save data in v1. Settings (M2): `reduce_shake: bool` in `user://settings.cfg` via `ConfigFile`, owned by B.

## Public API (code against this before A lands)

The stubs in the repo already have these exact signatures; A fills the bodies, nobody changes a
signature without a ticket comment tagging B and C.

### `Scripts/Sim/NightbeamTuning.gd` — `class_name NightbeamTuning extends Resource`
Every GDD tunable is an `@export` var named in **snake_case** (GDD `BEAM_TURN_SPEED` → `beam_turn_speed`),
typed `float` or `int`, with the GDD default. Full list: `dawn_time, hull_max, beam_turn_speed,
beam_half_width, beam_range, spawn_radius, reef_radius, ship_heading_jitter, ship_speed_start,
ship_speed_end, saved_speed, guide_time, guide_decay, spawn_interval_start, spawn_interval_end,
first_spawn_delay, min_spawn_separation, shade_start_time, shade_chance_end, shade_speed_dark,
shade_speed_lit, shade_lifetime, flare_start_charges, flare_max_charges, flare_saves_per_charge,
flare_cooldown, flare_guide, flare_radius, max_entities, score_per_save, score_per_hull, sim_hz`.
```gdscript
"""Fixed step length in seconds (1.0 / sim_hz)."""
func dt() -> float
"""Spawn interval at sim time t (GDD difficulty ramp)."""
func spawn_interval(t: float) -> float
"""Speed given to a ship spawned at sim time t."""
func ship_speed(t: float) -> float
"""Probability that a spawn at sim time t is a Shade (0 before shade_start_time)."""
func shade_chance(t: float) -> float
```
Load it with `preload("res://Data/Tuning/NightbeamTuning.tres") as NightbeamTuning`
(constant `NightbeamSim.DEFAULT_TUNING_PATH`).

### `Scripts/Sim/NightbeamSim.gd` — `class_name NightbeamSim extends RefCounted`
```gdscript
enum State { RUNNING, WON, LOST }
enum Kind { SHIP, SHADE }
const DEFAULT_TUNING_PATH: String = "res://Data/Tuning/NightbeamTuning.tres"
const ACTION_TURN: String = "turn"     # float in [-1, 1], clamped by the sim; missing = 0
const ACTION_FLARE: String = "flare"   # bool; missing = false

"""Creates a fresh night. All randomness comes from p_seed; p_tuning is read-only for the sim."""
func _init(p_seed: int, p_tuning: NightbeamTuning) -> void
"""Advances exactly one fixed tick (tuning.dt()) in the GDD tick order. No-op once is_over()."""
func step(action: Dictionary) -> void
"""Read-only snapshot of the current state (schema below). A new Dictionary every call; callers may keep it."""
func get_observation() -> Dictionary
"""Deterministic hash of the full sim state incl. RNG state. Same seed + same actions ⇒ same hash."""
func state_hash() -> int
"""True once the night is WON or LOST."""
func is_over() -> bool
"""Current State (RUNNING while the night is on)."""
func result() -> State
"""The seed this sim was created with."""
func get_seed() -> int
"""Ticks stepped so far (time == tick * dt)."""
func get_tick() -> int
"""Signed shortest angular difference a - b, in (-PI, PI]. Shared by sim, view (mouse), bots, invariants."""
static func angle_diff(a: float, b: float) -> float
"""Wraps an angle into [0, TAU)."""
static func wrap_angle(a: float) -> float
"""String name for a State: "running" | "won" | "lost" (used in observations and CSVs)."""
static func state_name(s: State) -> String
```

### Observation schema (`get_observation()`; JSON-safe, sent as-is over the bridge)
```
{
  "tick": int, "time": float, "beam_angle": float,          # radians [0, TAU)
  "hull": int, "saved": int, "score": int,
  "flare_charges": int, "flare_cd": float, "flares_used": int,
  "state": "running" | "won" | "lost",
  "spawns_skipped": int,                                    # spawns dropped by the lane rules (GJ-12), cumulative
  "entities": [ {"id": int, "kind": "ship" | "shade", "angle": float, "radius": float, "speed": float,
                 "guidance": float, "saved": bool, "lit": bool, "fading": bool, "age": float} ],   # ascending id
  "events": [ {"type": "spawn" | "saved" | "wreck" | "shade_fade" | "shade_flared" | "flare" | "won" | "lost",
               "id": int, "kind": "ship" | "shade" | "", "angle": float, "radius": float, "lit": bool} ]
                                                            # this tick only
}
```
`tick`, `flares_used`, `spawns_skipped` and `events` extend the GDD dict (needed by the CSV and the view).
Polar → screen: `center + Vector2.from_angle(angle) * radius`, center = viewport center (480, 270).
M2 "Readable Shades" (GJ-12), as built:
- `speed` = actual inward px/s this tick; a dark Shade stops at `shade_hold_radius` (speed 0 = *holding*).
- `fading` (Shades only): true during the last `shade_fade_time` of `shade_lifetime`; a fading Shade has
  `lit = false` and `speed = 0` for that tick.
- Event `kind` = the entity's kind for entity events, `""` for `flare` / `won` / `lost` (their `id` is -1).
  Event `lit` = that entity's lit flag on that tick (always true on a `wreck` with `kind` `shade`).
- Shade removals: `shade_fade` (lifetime over), `shade_flared` (hit by a flare), `wreck` with `kind` `shade`
  (a lit Shade reached the rocks). `dissolve` no longer exists.

### `Scripts/Sim/NightbeamInvariants.gd` — `class_name NightbeamInvariants extends RefCounted`
```gdscript
"""
Checks GDD invariants 1-4 (except the run-twice determinism check, which the test runner does) between
two consecutive observations. prev is {} on the first call. Returns [] when fine, else an Array of
{"id": String, "message": String, "severity": "P0".."P3"} (the Playtest Lab bridge format).
"""
static func check(prev: Dictionary, curr: Dictionary, tuning: NightbeamTuning) -> Array
```
Ids (GDD invariants 1-6): `beam-range`, `beam-speed`, `counters-monotonic`, `hull-range`, `flare-range`,
`entity-in-bay`, `guidance-range`, `entity-cap`, `terminal-final`, `run-length`, and since GJ-12
`shade-gap` (ship/Shade lanes too close, GDD 5), `shade-hold` (a dark Shade moved in past `shade_hold_radius`,
or a fading Shade moved), `fading-lit` (a fading Shade is lit), `shade-wreck-unlit` (a dark Shade hit the
rocks, GDD 6, P0). The bots target adds `bridge-frame-tick` and `unknown-policy` (see Playtest Lab plan).

### `Scripts/Sim/NightbeamBots.gd` — `class_name NightbeamBots extends RefCounted`
```gdscript
const SKILLS: PackedStringArray = ["idle", "greedy", "careful"]
"""Returns the action for skill on this observation. memo is per-run scratch space owned by the caller."""
static func act(skill: String, obs: Dictionary, tuning: NightbeamTuning, memo: Dictionary) -> Dictionary
```
Bots are pure functions of (obs, tuning, memo) — no RNG — so a (seed, skill) pair is fully deterministic.
They live in GDScript once and are reused by BotRunner **and** the lab (see Playtest plan), so there is no
second JS copy to keep in sync.

### `Scripts/Game/PlayerInput.gd` — `class_name PlayerInput extends RefCounted`
```gdscript
"""Maps the current keyboard state (and in M2 the mouse vs. beam_angle) to a sim action Dictionary."""
static func read_action(obs: Dictionary, tuning: NightbeamTuning) -> Dictionary
```

### `Scripts/View/NightbeamView.gd` / `Scripts/View/HudView.gd`
```gdscript
"""Stores the latest observation and requests a redraw. Never mutates the sim."""
func show_observation(obs: Dictionary) -> void
```

### `Scripts/Playtest/PlaytestTarget.gd` — bridge target (group `playtest_target`)
`reset_game(seed: int) -> void`, `apply_action(action: Dictionary) -> void`, `observe() -> Dictionary`,
`is_done() -> bool`, `metrics() -> Dictionary`, `is_ready() -> bool`, `check_invariants() -> Array`.

### `Scripts/Playtest/PersonaTarget.gd` + `PersonaPerception.gd` — persona target (GJ-10, GJ-14)
Same bridge methods (no `check_invariants`). Lives only in `PersonaHarness.tscn`; see "Persona mode" below.

## Playtest Lab plan (ticket C)
- **Target node:** `PlaytestHarness.tscn` root (`PlaytestTarget.gd`), added to group `playtest_target` in `_ready`.
  It owns its own `NightbeamSim` + tuning and has no view. The adapter launches that scene directly, so the
  Main scene (and its player input) never runs under the bridge:
  `godot --headless --fixed-fps 60 --path . res://Scenes/PlaytestHarness.tscn -- --playtestPort={PORT}`.
- **Stepping:** exactly **one `sim.step()` per `_physics_process`** of the target (60 Hz with `--fixed-fps 60`
  ⇒ 1 physics tick per frame). A bridge `step` with `n` frames = `n` sim ticks. `reset_game` builds a new sim.
- **Action dict:** raw `{"turn": float, "flare": bool}` (lab `idle`/`random` policies), **or**
  `{"policy": "greedy" | "careful" | "idle"}` — then the target calls `NightbeamBots.act(policy, obs, ...)` every
  tick itself (fast: one bridge round-trip per decision window, and bots are the single GDScript copy).
- **observe():** the sim observation minus `events` (keep payloads small).
- **metrics():** `time_survived, saved, hull, score, flares_used, won (0/1), lost (0/1)`.
- **check_invariants():** `NightbeamInvariants.check(prev_obs, obs, tuning)` on **every** tick (the target
  keeps `prev_obs` and collects violations until the bridge asks), plus `terminal-final` (`state_hash()` must
  not change after the end), `bridge-frame-tick` (physics ticks == frames == `sim.get_tick()`; verified in GJ-6:
  `--fixed-fps 60` gives exactly 1 tick per frame, no fallback needed) and `unknown-policy`.
- **Reset frame (as built, GJ-6):** the bridge unpauses one frame after `reset` to poll `is_ready()`; the target
  does not step until the first `apply_action`, so a reset never advances the sim.
- **Adapter** (`.playtest/adapter.mjs`): `meta {name:"NIGHTBEAM", dt:1/60, decisionEvery: 6, maxSeconds: 200}`,
  `bridge {command: <godot path>, args: [...above...]}`, `idleAction`, `randomAction`, policies `greedy`/`careful`
  returning `{policy: ...}`, `findings()` alarms from the GDD gradient table (careful ≥ 4× idle survival,
  ≥ 1.3× greedy; careful win rate 50-80 %). Then `lab.js bots --runs 30`, `lab.js baseline set`, commit
  `.playtest/baseline.json` → per-wave regression gate (`lab.js check`).

### Persona mode (GJ-10, M2 cues GJ-14)
- **Launch:** `lab.js host --port <p>` starts `adapter.personaBridge`: windowed Godot (no `--headless`),
  `--fixed-fps 60 --resolution 960x540 res://Scenes/PersonaHarness.tscn -- --playtestPort={PORT}`. Personas
  drive it only with `lab.js play <verb> --port <p> --persona <name>`; `meta.personaFrames` = 30 per turn.
- **reset_game(seed):** `Main.show_title(seed)`: sessions start on the title card (onboarding is tested).
- **apply_action:** through `Input.parse_input_event` (the human path): `turn` -1..1 = `turn_left/right`
  action strength held for the window; `flare: true` = one Space press; `key` `space|r|n|esc` = one press
  (released after one frame). `is_done()` is always false (sessions end with `play done` / `play quit`).
- **observe() is human-fidelity** (`PersonaPerception`): `screen` (title|night|paused|end); `text` (every visible
  HUD/card label exactly as drawn; pip rows as ●/○, "(dim)" while the flare cools, "(a lamp blinking
  purple|orange)" while a lost hull lamp flashes); `scene` (vague: beam as a clock hour; boats and Shades as
  one / a couple / a few / several, far out / midway in / close to the rocks; **beam-relative** cues for anything
  in or near the beam: "right where the beam points", "in the beam, slightly clockwise of where it points",
  "just past the beam's counter-clockwise edge", "a little clockwise of the beam" (clockwise = the way turn > 0
  sweeps); Shade looks: drifting in / bobbing in place with eyes on the beam / lit up red and rushing /
  shrinking grey under rising motes; the first-lunge slow motion while it plays); `since_last_look` (noticed
  events, no causes: a boat broke up on the rocks vs a purple splash, fade, white burst, flare ring, spawns,
  the lunge beat). No ids, speeds, guidance numbers, timers or counts beyond what the HUD prints. Sounds are
  not described.
- **"The Drowned" cues (GJ-19, mirrors GJ-18):** every boat/ghost group carries rough clock positions (needed to
  aim); pale rock with teeth and foam under the beam; boats' masthead lamp dim → brightening → bright with the
  ring, "blinked twice, heeled over and turned back out to sea" on a save; Shades described as see-through purple
  ghost ships with a torn sail and lantern eyes; a boat wreck adds "a thin purple wisp" (scene for 2 s); at dawn
  "ghost ships folding their sails and sinking" / "the boats' masthead lamps blink together" only when ghosts /
  boats were on screen; HUD LAMP windows as ■/□ with "(a window blinking purple|orange)".

## Folder layout (locked)
```
project.godot                    TL only
addons/playtest_bridge/          vendored, TL only (Godot requires lowercase "addons" — the one exception to PascalCase)
Scenes/        Main.tscn, PlaytestHarness.tscn
Scripts/Sim/   NightbeamSim.gd, NightbeamTuning.gd, NightbeamInvariants.gd, NightbeamBots.gd
Scripts/Game/  GameFlow.gd, PlayerInput.gd
Scripts/View/  NightbeamView.gd, HudView.gd  (M2: SynthAudio.gd)
Scripts/Playtest/ PlaytestTarget.gd
Data/Tuning/   NightbeamTuning.tres
Assets/{Art,Audio,Fonts}/        empty in v1 (procedural only)
Tests/         TestRunner.gd, BotRunner.gd, Results/ (CSV output, gitignored)
Builds/        export output (gitignored)
.playtest/     adapter.mjs, config, baseline.json (lab-owned runs/ subfolder)
```

## Ownership map (M1 — disjoint files, parallel-safe)
| Ticket | Owns (only these files) | Depends on | Short ACs |
|---|---|---|---|
| **A — Sim core** (programmer) | `Scripts/Sim/*` (Sim, Tuning, Invariants, Bots), `Data/Tuning/NightbeamTuning.tres`, `Tests/*` | GJ-3 | all GDD rules in tick order; invariants return [] over 100 seeds × 3 skills; determinism (run each seed twice, equal `state_hash`); `Tests/TestRunner.gd` exits 0; `Tests/BotRunner.gd --seeds=1-100` writes CSV (seed, skill, result, time_survived, saved, hull, flares_used) in < 60 s; gradient table posted |
| **B — View + flow** (programmer/artist) | `Scenes/Main.tscn`, `Scripts/Game/*`, `Scripts/View/*` | GJ-3 (codes against stub obs; integrates when A lands) | graybox bay/beam/ships/shades/guidance rings from `obs`; keys A/D/←/→/Space; title → night → end card; R retry same seed, N new night, Esc pause; `--seed=N`; hull/flare/score HUD; headless `Main.tscn --quit-after 600` has no errors |
| **C — Playtest bridge** (QA/programmer) | `Scenes/PlaytestHarness.tscn`, `Scripts/Playtest/*`, `.playtest/*` | **A** (needs real sim + bots + invariants) | target implements all 7 bridge methods; `lab.js bots --runs 30` runs idle/random/greedy/careful with 0 crashes/errors/invariant breaks; same seed replays identically; baseline set + `.playtest/baseline.json` committed; `lab.js check` passes on an unchanged build |
| TL (shared) | `project.godot`, `addons/`, `.studio/docs/TDD.md` | — | change on request via ticket comment |

Rules: a worker edits only its own files. Need a change in someone else's file (e.g. a new observation
field)? Comment on their ticket + post in #engineering; the API section above is updated by TL.

## Coding standards
Boss global CLAUDE.md applies (PascalCase files/folders/nodes/scenes, snake_case vars/funcs/signals,
SCREAMING_SNAKE constants and in-script enum values, typed everything, `@export`, signals over hard refs,
Resources in `res://Data/<Type>/`). Project deltas:
- Docstrings are `"""..."""` placed directly above the class / public function (verified to parse in 4.6.1).
- No magic numbers in the sim or view: sim numbers come from `NightbeamTuning`, view numbers are named
  `const`s at the top of the view script (palette colors included).
- Sim determinism: iterate entities as an Array sorted by `id`; never iterate a Dictionary for rules.
- `print` only in Tests/ and harness scripts; the game uses `push_warning`/`push_error` for real problems
  (any `ERROR:` line fails the boot check and the lab's error scan).

## Test & build
- Import: `"$GODOT" --headless --path . --import`
- Boot check: `"$GODOT" --headless --path . --quit` → grep `ERROR|SCRIPT ERROR|Parse Error` = none
  (GJ-3 log: `.studio/qa/GJ-3-boot.log`).
- Main scene smoke: `"$GODOT" --headless --path . res://Scenes/Main.tscn --quit-after 600`
- Unit/invariant/determinism tests: `"$GODOT" --headless --path . -s res://Tests/TestRunner.gd` (exit code = failures).
- Bot CSV: `"$GODOT" --headless --path . -s res://Tests/BotRunner.gd -- --seeds=1-100 --out=Tests/Results/bots.csv`
- Lab: `node <playtest-lab>/lab/lab.js --game . bots --runs 30`
- Export (M2): `export_presets.cfg` "Windows Desktop" → `Builds/Windows/Nightbeam.exe`; export templates are
  a download → needs `approval request --kind download` first.

## Risks & spikes
| Risk | Mitigation / spike | Decision deadline |
|---|---|---|
| Bridge frame ≠ sim tick (paused tree, physics accumulation) → non-deterministic lab runs | C verifies `--fixed-fps 60` gives 1 `_physics_process` per frame; fallback: step the sim in `_process` once per frame | during C |
| Headless BotRunner too slow for 100×3 nights | pure RefCounted sim, no scene tree, typed arrays; profile in A | during A |
| Stubs drift from real API | signatures frozen here; changes only via ticket comment + TDD edit | ongoing |
| Float drift across platforms | determinism only promised per platform/binary; hash rounds floats to 1e-4 | A |
