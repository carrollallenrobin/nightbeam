# NIGHTBEAM — Game Design Document (v1, jam tier)

See `Pitch.md` for hook and pillars. All numbers below are the defaults for
`res://Data/Tuning/NightbeamTuning.tres` (class `NightbeamTuning extends Resource`).

## 1. Overview
- **Elevator pitch:** Rotate a lighthouse beam through one 3-minute night to guide ships past
  your reef, and keep the beam off the Shades, because light draws them in.
- **Genre / platform / session:** one-screen 2D arcade, Godot 4.6 desktop (and web export if
  time allows). 1 run = 2-4 min (win at 180 s; strong losing runs last 60-170 s).
- **Player fantasy:** the lone keeper deciding who gets the light.
- **Pillars:** (1) One beam, one decision. (2) Readable in one glance. (3) Same seed, same night.
  See Pitch.md for what each rules out.

## 2. Core loop
- **Moment-to-moment (1-3 s):** find the ship closest to wrecking, turn the beam to it without
  sweeping over a Shade, hold until its ring fills, move on. Fire a flare when too many ships
  close in at once.
- **Session (3 min):** the night gets harder (more spawns, faster ships, more Shades). Survive to
  dawn and score saved ships.
- **Meta:** none in v1. The seed shows on the end screen and "Retry same seed" / "New night"
  buttons are there. A best score per seed is a stretch goal.

## 3. Mechanics (testable rules)
Coordinates are polar around the lighthouse at screen center. Angles are in radians in
[0, TAU). The sim steps at a fixed `DT = 1/60`.

| Mechanic | Rule (numbers) | Input | Feedback |
|---|---|---|---|
| Beam turn | `beam_angle += turn * BEAM_TURN_SPEED * DT`, wrapped to [0,TAU). `turn` clamped to [-1,1]. | A/D or Left/Right; mouse: turn = clamp(angle_diff(cursor, beam) / (BEAM_TURN_SPEED*DT), -1, 1) | beam cone rotates; low creak loop when turning |
| Lit test | An entity is lit if `abs(angle_diff(entity.angle, beam_angle)) <= BEAM_HALF_WIDTH` and `entity.radius <= BEAM_RANGE`. Lit status is computed once per tick, before movement. | — | lit ships get a bright outline, lit shades get a red outline and speed lines |
| Ship spawn | At `SPAWN_RADIUS` and a random angle, with a random fixed `drift` in `[-SHIP_HEADING_JITTER, +SHIP_HEADING_JITTER]`. Kind is Shade with probability `shade_chance(t)`, otherwise Ship (plus the Lone Shade, see ramp). The angle then goes through the anti-cluster rule and the **Shade lane rule** (next row). | — | small wake fade-in at the edge |
| Shade lane rule (GJ-11) | **Guarantee: any beam angle that lights an unsaved ship does not light a (non-fading) Shade.** Since the lit test is `abs(angle_diff) <= BEAM_HALF_WIDTH`, that needs an angular gap `> 2*BEAM_HALF_WIDTH = 0.52 rad`; we use `SHADE_GAP = 0.60 rad` (34°, 0.08 rad margin for the drawn size). Ships spiral, so a ship's **path arc** is used: from its current angle to its reef angle `a_end = a_spawn + tan(drift) * ln(SPAWN_RADIUS / REEF_RADIUS)` (≤ 0.42 rad at max drift). Shades keep a fixed angle. At spawn: a new Shade must be ≥ `SHADE_GAP` from every unsaved ship's remaining path arc; a new Ship's whole path arc must be ≥ `SHADE_GAP` from every non-fading Shade. If the angle fails, try `angle + k*SPAWN_RETRY_STEP` for k = 1..17 (0.35 rad steps, one full turn); the first legal angle wins; if none, the spawn is skipped (the clock still advances, the RNG draws are unchanged). Holds for the whole approach because Shades never change angle and ships stay on their arc. Monte Carlo (.studio/qa/GJ-11-lanes.log): ~0.1% skips, ~30% of spawns nudged. | — | none needed: lanes are simply never shared |
| Ship approach | Each tick an unsaved Ship moves at `ship_speed(t)` (speed fixed at spawn) along the inward radial rotated by `drift`. The heading is recomputed every tick, which gives a spiral path. In polar form: `radius -= speed*cos(drift)*DT`, `angle += speed*sin(drift)*DT/radius`. The radius is strictly decreasing, so every unsaved ship reaches the reef. A straight-line heading would miss the reef (250·sin 0.25 ≈ 62 px > 48), so it is not allowed. | — | wake trail |
| Guidance | While lit: `guidance += DT / GUIDE_TIME`. While dark: `guidance -= GUIDE_DECAY * DT`, floored at 0. At `guidance >= 1` the ship becomes SAVED. | — | ring around the hull fills clockwise; bell chime (pitch rises with combo) on save |
| Saved ship | Heading snaps to radial outward and speed becomes `SAVED_SPEED`. It despawns at `radius > SPAWN_RADIUS + 10`. `saved += 1` when it becomes saved, not when it despawns. | — | ring turns green, sail turns white |
| Wreck | A Ship or Shade with `radius <= REEF_RADIUS` is removed and `hull -= 1`. The event carries `kind`. Only a **lit** Shade can get here (hold rule). | — | Ship: foghorn, wood debris, shake 6 px / 0.25 s, rock flash. **Shade (GJ-11):** purple splash ring on the rock, low 'gulp' thud, the lost hull pip flashes purple — visibly different from a ship wreck |
| Shade drift | Moves radially inward (angle fixed): `SHADE_SPEED_LIT` while lit. While dark it moves at `SHADE_SPEED_DARK` only while `radius > SHADE_HOLD_RADIUS`, then **holds** (stops) there; a Shade already pulled below the hold radius by light stays where it is while dark. So an unlit Shade can never reach the reef, by rule. | — | purple wavering blob with 2 eyes; eyes turn to face the beam; holding Shades bob ±3 px (view only); a low hum rises with the number of lit shades |
| Shade fade (GJ-11) | For the last `SHADE_FADE_TIME` s of `SHADE_LIFETIME` a Shade is `fading`: it cannot be lit and does not move. At `age >= SHADE_LIFETIME` it is removed with a `shade_fade` event. Flare removal emits `shade_flared`. Every Shade leaves through exactly one of `shade_fade`, `shade_flared`, `wreck(kind=shade)`. | — | fade: over 0.75 s the Shade desaturates, shrinks and releases 6-8 purple motes that drift up, with a soft falling 'sigh'. Flared: white burst + pop. Never a silent vanish |
| Flare | On `flare == true` with `flare_charges > 0` and `flare_cd <= 0`: charges -1, `flare_cd = FLARE_COOLDOWN`. Every unsaved Ship gets `+FLARE_GUIDE` guidance, and every Shade with `radius <= FLARE_RADIUS` dissolves (`shade_flared`; holding Shades at `SHADE_HOLD_RADIUS` are always inside it). | Space / left click | white 360° ring expands over 0.4 s; whoosh |
| Flare recharge | `+1` charge every `FLARE_SAVES_PER_CHARGE` saves, capped at `FLARE_MAX_CHARGES`. Starts at `FLARE_START_CHARGES`. | — | flare pips on the lighthouse |
| Win | `time >= DAWN_TIME` while `hull > 0` → state WON (checked after wrecks in the same tick, so a wreck on the final tick can still lose). | — | sky reaches dawn, all shades dissolve, horn chord |
| Lose | `hull <= 0` → state LOST. | — | beam goes out, long foghorn |
| Score | `score = saved * SCORE_PER_SAVE`; on WON add `hull * SCORE_PER_HULL`. | — | end card |

**Difficulty ramp.** `p = clamp(time / DAWN_TIME, 0, 1)`:
- `spawn_interval(t) = lerp(SPAWN_INTERVAL_START, SPAWN_INTERVAL_END, p)`. The next spawn is
  scheduled at `last_spawn + spawn_interval`, with no jitter. Randomness comes from angle and kind.
- `ship_speed(t) = lerp(SHIP_SPEED_START, SHIP_SPEED_END, p)`.
- `shade_chance(t) = 0` while `t < SHADE_START_TIME`, then
  `lerp(SHADE_CHANCE_START, SHADE_CHANCE_END, (t - SHADE_START_TIME) / (DAWN_TIME - SHADE_START_TIME))`
  (GJ-11, folds in GJ-9). This replaces the GJ-7 trick of a negative `SHADE_START_TIME` (-90), which
  front-loaded Shades (17% at t=0) but let a Shade be the very first spawn.
- **The Lone Shade (GJ-11 teaching beat):** the first spawn scheduled at `t >= LONE_SHADE_TIME`
  (7 s) is always a Shade (the kind roll is still drawn, then overridden), and no other Shade can
  spawn before `SHADE_START_TIME` (15 s). So every night opens with ~2 ships alone, then one Shade
  by itself among ~3 ships, and the crowd starts at 15 s. It follows the lane rule like any Shade.
  Onboarding comes from the rule, not from text: the Lone Shade drifts in, holds near the rock with
  its eyes on the beam, and the first time the player lights any Shade in a session the lunge is
  played in slow motion (UI section).
- **Front-loading (keeps the GJ-7 gradient intent):** `SHADE_CHANCE_START` 0.2 at 15 s → 0.5 at dawn
  gives almost the same Shade density after 15 s as the GJ-7 offset line (0.22 → 0.5).
- Anti-cluster: when a new spawn lands within `MIN_SPAWN_SEPARATION` rad of the previous spawn,
  add PI/2 to its angle. This keeps the rule deterministic and avoids unreadable stacks.

**Tick order (fixed, required for determinism):** 1) read action → 2) flare → 3) turn beam →
4) compute lit flags → 5) move entities in ascending `id` order → 6) guidance/saves → 7) wrecks,
shade lifetimes, despawns → 8) spawns → 9) `time += DT`, win/lose check.

### Architecture (separates state from rendering)
- `Scripts/Sim/NightbeamSim.gd` (`class_name NightbeamSim extends RefCounted`) is pure logic. It
  has `func _init(seed: int, tuning: NightbeamTuning)`, `func step(action: Dictionary) -> void`,
  `func get_observation() -> Dictionary`, `func state_hash() -> int`, and `is_over()` / `result()`.
  It owns its own `RandomNumberGenerator` with `rng.seed = seed`. It makes no Node calls, no
  `Time`/`OS` time calls, and uses no global `randf()`.
- `Scenes/Main.tscn` + `Scripts/View/NightbeamView.gd` (Node2D): calls `sim.step()` in
  `_physics_process` (physics_ticks_per_second = 60) and draws from the observation in `_draw()`.
  Render-only effects (shake, particles, audio) use a separate view RNG and never feed back.
- Signals come from the view layer, after comparing observations: `ship_saved`, `reef_hit`,
  `flare_fired`, `run_ended(result)`.
- **Bot action dict:** `{"turn": float -1..1, "flare": bool}`. A missing key means 0/false.
- **Observation dict:** `{time, beam_angle, hull, saved, score, flare_charges, flare_cd, state,
  entities: [{id, kind:"ship"|"shade", angle, radius, speed, guidance, saved, lit, age, fading}]}`.
  Events carry `kind` (GJ-11); Shade removals are `shade_fade`, `shade_flared` or `wreck`.
- Headless harness: `Tests/BotRunner.gd` (SceneTree script). It runs N seeds × bot skills with
  no rendering and writes a CSV (seed, skill, result, time_survived, saved, hull, flares_used).

### Invariants (assert every tick in debug and in the bot harness)
1. **Beam discipline:** `0 <= beam_angle < TAU`, and each tick the beam moves at most
   `BEAM_TURN_SPEED * DT` (+1e-6).
2. **Monotonic counters:** `saved` and `score` never decrease, `hull` never increases, and
   `0 <= hull <= HULL_MAX`. `flare_charges` stays in [0, FLARE_MAX_CHARGES].
3. **Entities stay in the bay:** every live entity has `REEF_RADIUS < radius <= SPAWN_RADIUS + 10`,
   `0 <= guidance <= 1`, and the live count is `<= MAX_ENTITIES`.
4. **Terminal is final and determinism holds:** once `state != RUNNING`, `step()` changes nothing,
   and a run ends by `time <= DAWN_TIME + DT`. The same seed and action sequence always gives the
   same `state_hash()` (check it by running each seed twice).
5. **Shade lanes (GJ-11):** every tick, every unsaved ship and every non-fading Shade have
   `abs(angle_diff) >= SHADE_GAP - 1e-6`. So no tick ever has a lit unsaved ship and a lit
   non-fading Shade at the same time.
6. **Unlit Shades are harmless (GJ-11):** a Shade that was dark on the tick it crossed
   `SHADE_HOLD_RADIUS` never moves inward while dark; every `wreck(kind=shade)` was lit on that tick.
   A fading Shade is never lit.

## 4. Progression & economy
The only resources are hull (5, a sink with no source), flare charges (source: saves, sink:
flares) and score. There is no between-run economy.

### Tunables (all go into NightbeamTuning.tres)
| Name | Default | Unit | Notes |
|---|---|---|---|
| DAWN_TIME | 180.0 | s | run length on a win |
| HULL_MAX | 5 | hits | reef hits before losing |
| BEAM_TURN_SPEED | 2.6 | rad/s | about 150°/s, half circle in 1.2 s |
| BEAM_HALF_WIDTH | 0.26 | rad | 30° cone total |
| BEAM_RANGE | 260.0 | px | reaches the spawn ring |
| SPAWN_RADIUS | 250.0 | px | bay radius; the arena is a 960×540 viewport |
| REEF_RADIUS | 48.0 | px | wreck line |
| SHIP_HEADING_JITTER | 0.25 | rad | makes ships slide sideways a little |
| SHIP_SPEED_START | 22.0 | px/s | about 9 s to the reef |
| SHIP_SPEED_END | 40.0 | px/s | about 5 s to the reef |
| SAVED_SPEED | 55.0 | px/s | outbound |
| GUIDE_TIME | 1.0 | s | continuous light needed to save |
| GUIDE_DECAY | 0.3 | /s | guidance lost while dark |
| SPAWN_INTERVAL_START | 3.0 | s | **tuned .tres: 2.7** (GJ-7): more early traffic, so a Shade-blind player meets Shades in the first minute |
| SPAWN_INTERVAL_END | 1.1 | s | **tuned .tres: 0.6** (GJ-12): lanes made the late night fair, so it can be denser; this is what keeps careful at 50-80% wins |
| FIRST_SPAWN_DELAY | 1.5 | s | |
| MIN_SPAWN_SEPARATION | 0.35 | rad | anti-cluster rule |
| SHADE_START_TIME | 20.0 | s | shades are off before this (except the Lone Shade). **tuned .tres: 15.0** (GJ-12; replaces the GJ-7 -90 offset) |
| SHADE_CHANCE_START | 0.2 | prob | GJ-11 (GJ-9): chance at SHADE_START_TIME; replaces the negative start offset |
| SHADE_CHANCE_END | 0.35 | prob | at dawn. **tuned .tres: 0.5** |
| SHADE_GAP | 0.60 | rad | GJ-11 lane rule; must stay > 2·BEAM_HALF_WIDTH (0.52). Hard floor 0.53 |
| SPAWN_RETRY_STEP | 0.35 | rad | GJ-11 lane rule nudge step, up to 17 tries |
| LONE_SHADE_TIME | 7.0 | s | GJ-11: first spawn at/after this is the Lone Shade; must be < SHADE_START_TIME |
| SHADE_HOLD_RADIUS | 120.0 | px | GJ-11: dark Shades stop here (72 px outside the reef, inside FLARE_RADIUS 140). With the GJ-12 tuning a sweep across a holding Shade (≥ 0.2 s at 500 px/s = 100 px) reaches the rock: **near Shades are walls, don't cross them** |
| SHADE_FADE_TIME | 0.75 | s | GJ-11: last part of the lifetime, not liteable, drawn as the fade |
| SHADE_SPEED_DARK | 12.0 | px/s | **tuned .tres: 20** (GJ-12): 130 px to the hold radius in 6.5 s, then seen holding ~5.8 s before the fade (probe: 100% of never-lit Shades hold; at 12 px/s it was 0%) |
| SHADE_SPEED_LIT | 70.0 | px/s | about 2.9 s of total light from spawn to reef. **tuned .tres: 500** (GJ-12): a far Shade survives one sweep across (-100 px, then it holds), a near one does not. Lanes removed the old deaths; the skill is now routing the beam around Shades |
| SHADE_LIFETIME | 14.0 | s | dissolves after this. **tuned .tres: 13.0** (GJ-12): fade starts at 12.25 s, so the hold is visible |
| FLARE_START_CHARGES | 1 | | |
| FLARE_MAX_CHARGES | 2 | | |
| FLARE_SAVES_PER_CHARGE | 6 | saves | **tuned .tres: 7** (GJ-12): the denser night gives ~30% more saves, so this keeps the flare economy about where it was |
| FLARE_COOLDOWN | 2.0 | s | also debounces a held key |
| FLARE_GUIDE | 0.6 | guidance | added to every unsaved ship |
| FLARE_RADIUS | 140.0 | px | shades inside it dissolve |
| MAX_ENTITIES | 64 | | safety cap: skip the spawn when full |
| SCORE_PER_SAVE | 10 | pts | |
| SCORE_PER_HULL | 25 | pts | dawn bonus |
| SIM_HZ | 60 | Hz | fixed step, DT = 1/SIM_HZ |

### Bot skills and target skill gradient (30+ seeds each, seeds 1..100)
- **idle:** `{"turn":0,"flare":false}` every tick. Baseline.
- **greedy:** targets the unsaved ship with the smallest angular distance to the beam and ignores
  Shades. It flares as soon as a charge is ready and at least 1 ship is on screen.
- **careful:** targets the unsaved ship with the lowest time-to-reef `(radius-REEF_RADIUS)/speed`,
  skipping ships it can't reach and fill in time (`turn_time + GUIDE_TIME*(1-guidance) > eta`).
  It picks the turn direction whose sweep doesn't cross a Shade (or the shorter one if both do).
  It flares when 3 or more unsaved ships have `eta < 2.5 s`, or when a lit Shade is inside
  `FLARE_RADIUS`.

| Metric | idle | greedy | careful |
|---|---|---|---|
| Mean time survived | 20-35 s | 70-130 s | ≥ 150 s |
| Dawn (win) rate | 0% | 0-10% (GJ-7, was 5-25%) | 50-80% |
| Mean ships saved | 0 | 25-45 | 55+ |

A good gradient means careful survives ≥ 4× longer than idle and ≥ 1.3× longer than greedy, and
careful wins in 50-80% of runs (not 100%, or the late night is too soft). Tuning order if we
miss: SPAWN_INTERVAL_END, then SHADE_CHANCE_END, then GUIDE_TIME. Record before/after tables on
the balance ticket.

**GJ-7 decision (gradient):** greedy ignores Shades, the core rule of the game, so it should rarely
see dawn. Its target dawn rate is now 0-10% (was 5-25%). With 5 hull and a rising ramp, "5-25%
wins" and "70-130 s mean" together need a bimodal outcome the game does not produce (tried ~40
configs in GJ-4, ~45 in GJ-7). The other targets stay as they were. Tuned result, 100 seeds (1..100):
idle 24.9 s / 0% / 0.8 saved, greedy 127.9 s / 2% / 42.6, careful 175.8 s / 69% / 58.7;
careful/greedy 1.37x, careful/idle 7.1x. On holdout seeds 101..200: greedy 126.6 s / 0%, careful 173.4 s / 54%,
1.37x. Log: `.studio/qa/GJ-7-gradient.log`.

### GJ-11 Readable Shades (decisions)
Boss: Shades overlap the ships he should light, and dark Shades drift in and vanish before he sees
them. Playtest R7: no persona learned "light draws Shades" in two nights.
1. **Lanes, not luck:** the Shade lane rule (SHADE_GAP 0.60 rad > beam width 0.52) means holding the
   beam on a ship can never light a Shade. The skill left is *routing*: pick the turn direction
   and don't sweep across a Shade, most of all one holding near the rock.
2. **Unlit Shades hold, then fade visibly:** dark Shades stop at 120 px, eyes on the beam, and fade
   out over 0.75 s with motes and a sigh. Only light can bring a Shade to the rock, and that hit
   looks and sounds different from a ship wreck.
3. **Teach by staging:** Shade-free first 7 s, then a Lone Shade, crowd from 15 s; a one-time slow-mo
   on the first lunge; one title line. GJ-9 (`shade_chance_start`) is folded into the sim ticket.
4. **Gradient targets unchanged** (careful/greedy ≥ 1.3x, greedy 70-130 s and 0-10% wins, careful
   50-80% wins). Lanes remove greedy's "hold on a ship next to a Shade" deaths, so greedy will get
   better before the retune; the retune levers are SHADE_SPEED_LIT (cost of a sweep-across),
   SHADE_HOLD_RADIUS and SHADE_CHANCE_*. If ≥ 1.3x cannot be met, gd-1 posts a new decide entry with
   new targets before the regression gate.
5. **GJ-12 retune (gd-1):** tested whether a far-or-near Shade could survive one sweep across
   (lit 350, hold 130): greedy then wins 37% (c/g 1.08x), so the forgiving version has no skill
   gradient. The tuning that ships: a sweep across a *holding* Shade costs a hull, a *far* Shade
   survives one pass. Result, seeds 1-100: idle 24.4 s | greedy 118.2 s / 1% / 43.0 saved |
   careful 174.9 s / 69% / 73.4 saved; careful/greedy 1.48x (holdout 101-200: 1.54x). Log:
   `.studio/qa/GJ-12-retune.log`.

## 5. Content (v1)
- Entity kinds: `ship`, `shade`. One bay layout. Seeds come from the menu (random) or `--seed=N`.
- No levels. The ramp is the content.

## 6. UI / UX
- **Flow:** Title (name, "Space to light", the teaching line, seed field) → Night (gameplay) → End
  card (WON/LOST, saved, score, seed, **hull lost: N to ships · M to Shades** (GJ-11), [R] retry same
  seed, [N] new night). Esc pauses.
- **Teaching (GJ-11), no text walls:**
  - Title-card line, one only: **"Light saves ships, and it calls the Shades."**
  - Lone Shade opening (ramp section): one Shade, alone, at ~7 s.
  - **First lunge beat:** the first time in an app session that any Shade becomes lit, the game
    layer runs the sim at 0.3x speed for 0.6 s real time (fewer `step()` calls per second; the sim
    and its determinism are untouched), the Shade's eyes snap open wide, a red ring pulses on it and
    a dotted line is drawn from it to the rock. Once per session, never again after that.
  - A lit Shade that hits the rock uses the Shade wreck feedback (mechanics table), so the cause
    of the lost hull is visible.
- **HUD (minimal):** hull shown as 5 lamp pips at the top-left, flare charges as pips on the tower,
  score at the top-right. Night progress is shown by the sky (edge vignette navy → rose → gold) and
  a thin arc around the bay.
- **Controls:** A/D or ←/→ turn, Space flare, R retry. Mouse: the beam follows the cursor at
  capped speed and left click fires a flare. The mouse is turned into the same `turn` value, so
  bots and humans get the same control authority.
- Accessibility: shades are purple with **eyes and a wavy outline** (shape, not only color); the
  guidance ring is thick (3 px); there is a reduce-shake toggle.

## 7. Art & audio direction (procedural only, no external assets)
- **Palette:** sea `#0B1630`, deep `#060C1C`, reef rock `#3A3F4F`, beam `#FFE9A8` at 35% alpha
  with an additive edge, ship hull `#F2A65A`, sail `#F7F1E1`, guidance ring `#FFD166` → saved
  `#7BE0AD`, shade `#8A5CF6` / lit shade outline `#FF4D6D`, dawn `#F7B7A3` → `#FFD9A0`.
- **Drawing:** everything is `_draw()` primitives (polygons, arcs, circles). The beam is a polygon
  cone with a 2-layer alpha falloff. An optional small CanvasItem shader can add water shimmer
  (stretch). The wake is a fading polyline of the last 12 positions (view-side buffer).
- **Audio:** `AudioStreamGenerator` + `AudioStreamGeneratorPlayback.push_frame`, 22050 Hz mono:
  - surf ambience: brown noise, low-passed, volume swell 0.1 Hz
  - save bell: sine 880 Hz + 1320 Hz, 0.6 s exp decay, +1 semitone per save in a 3 s combo
  - wreck foghorn: 110 Hz + 165 Hz sine, 5 Hz vibrato, 0.8 s
  - shade hum: 55 Hz saw, lowpassed, gain = 0.15 × lit_shade_count
  - shade fade 'sigh' (GJ-11): pink noise, bandpass falling 900 → 300 Hz, 0.5 s, quiet
  - shade reef hit 'gulp' (GJ-11): 70 Hz sine drop to 45 Hz, 0.35 s, plus a short noise splash; never the foghorn
  - flare whoosh: noise burst with a falling bandpass, 0.4 s; dawn: major-chord swell
  - Audio randomness uses its own RNG and never touches the sim.

## 8. Narrative
One line on the title card: "The keeper's last night before the new lamp arrives." The only other
title text is the teaching line (UI section, GJ-11).

## 9. Scope per milestone (1 jam day, 2-3 workers)
| Milestone | In | Out |
|---|---|---|
| M1 Playable (≈5 h) | NightbeamSim + Tuning resource, invariants asserted, BotRunner with idle/greedy/careful + CSV, graybox view (circles/lines), keyboard input, win/lose, retry | audio, mouse, polish |
| M2 Polish (≈3 h) | full `_draw` art, beam falloff, rings, shades with eyes, sky dawn, synth audio, title/end cards, mouse input, tuning pass from bot data | shader shimmer, per-seed best scores, web export (stretch) |

Suggested split: **Worker A (programmer):** sim, tuning, tests, bot harness. **Worker B
(artist/audio + programmer):** view, `_draw`, audio synth, UI. **QA:** harness run of 100 seeds
× 3 skills plus a manual playtest. Worker B can start against a stub observation dict right away.

## 10. Open questions
1. Is a 180 s night right? We could shorten it to 150 s for faster jam-judge sessions.
2. Should flares be earned only (start at 0) for more tension, or stay at 1 to teach the button?
3. Should mouse control be the primary scheme? It feels natural, but keys match the bot interface
   more directly.
4. Is the name "NIGHTBEAM" OK, or does Boss want to name it?
