# Decision Log — GodotJam01

Append-only. Newest at bottom. Do not re-litigate without Boss approval.

- 2026-09-26T01:13 **gd-1**: GJ-1: concept NIGHTBEAM (lighthouse beam triage, light attracts Shades); procedural _draw art in a navy/amber/purple palette, calm-tense lonely tone; synth audio only

- 2026-09-26T01:16 **producer**: GDD v1 approved: NIGHTBEAM. Night 180 s, 1 starting flare, keys primary (mouse in M2), name NIGHTBEAM

- 2026-09-26T01:22 **tl-1**: GJ-3 tech: Godot 4.6.1 GDScript only (typed), GL Compatibility renderer; viewport 960x540 stretch canvas_items/keep; sim fixed 60 Hz (physics_ticks_per_second=60), one NightbeamSim.step per physics tick, pure seeded RefCounted sim, view reads get_observation() only

- 2026-09-26T01:22 **tl-1**: GJ-3 layout: Scenes/ Scripts/{Sim,Game,View,Playtest}/ Data/Tuning/NightbeamTuning.tres Assets/{Art,Audio,Fonts}/ Tests/ Builds/ addons/playtest_bridge (autoload PlaytestBridge, inactive w/o --playtestPort); lab runs Scenes/PlaytestHarness.tscn, bots live once in GDScript (NightbeamBots) and the lab sends {policy:skill}; sim API frozen in TDD.md

- 2026-09-26T02:15 **gd-1**: GJ-7 skill gradient: front-load Shades instead of relaxing the gradient. Tuned .tres: spawn_interval_start 2.7, shade_start_time -90 (offset ramp: 17% Shades at t=0 -> 50% at dawn), shade_chance_end 0.5, shade_speed_lit 260, shade_lifetime 10.5. Only target changed: greedy dawn rate 5-25% -> 0-10% (ignoring Shades, the core rule, should rarely reach dawn; 5-25% wins + <=130 s mean needs a bimodal outcome the ramp can't produce). Result (seeds 1-100): greedy 127.9 s/2%/42.6 saved, careful 175.8 s/69%/58.7, careful/greedy 1.37x; holdout 101-200 same 1.37x.

- 2026-09-26T02:25 **gd-1**: GJ-7 follow-up (GJ-8 gate): the 5 undeclared rows are accepted as intended, tuning unchanged. careful.flares_used doubling (2.9->6.1) is wanted: the flare becomes the answer to front-loaded Shades. random.saved/score -0.3/-3 is a Shade-in-opening side effect. greedy.hull follows greedy.won. careful.won 0.77 is inside GDD 50-80%. Gate rules now in .playtest/config.json check: directions + abs floors + GDD bands as min/max; greedy gets no better-direction.

- 2026-09-26T02:26 **qa-1**: Lab baseline = R3 after GJ-7 rebalance (intended moves per GJ-7 intent table: greedy time/won/saved/score/hull/flares DOWN, lost UP; careful saved/score DOWN, won UP/lost DOWN, flares UP; random saved/score DOWN noise-scale; idle flat; config.check encodes GDD bands)

- 2026-09-26T04:57 **gd-1**: GJ-11 Readable Shades: (1) Shade lane rule: SHADE_GAP 0.60 rad (> beam width 0.52) between every Shade and every unsaved ship's path arc, enforced at spawn by 0.35 rad nudges (else skip, ~0.1%), so holding the beam on a ship can never light a Shade; the skill left is routing sweeps. (2) Unlit Shades hold at 120 px (eyes on the beam) and fade visibly over 0.75 s; only a lit Shade can reach the rock, with its own splash/gulp FX. (3) Teaching: Shade-free first 7 s, a Lone Shade at ~7 s, crowd from 15 s (shade_chance_start 0.2 -> 0.5, folds GJ-9), one-time 0.3x slow-mo on the first lunge per session, title line 'Light saves ships, and it calls the Shades.' (4) Gradient targets unchanged; gd-1 retunes after GJ-12. Tickets GJ-12 (sim, gp-1), GJ-13 (view, ui-1).

- 2026-09-26T05:32 **producer**: Boss approved M2 design: Shade lanes (0.60 rad from ship paths), unlit Shades stop at 120 px and fade visibly, only lit Shades hit the rock (own effect, split end-card), 7 s ships-only opening + solo Shade, slow-mo first lunge once per session, title line 'Light saves ships, and it calls the Shades.', gradient targets unchanged

- 2026-09-26T06:08 **gd-1**: GJ-12 retune (gd-1): targets kept, all met. .tres: shade_start_time -90->15, shade_speed_dark 12->20, shade_speed_lit 260->500, shade_lifetime 10.5->13, spawn_interval_end 1.1->0.6, flare_saves_per_charge 6->7 (hull stays 5). Design consequence: a sweep across a Shade holding near the rock costs a hull; a far Shade survives one pass. The forgiving variant (every Shade survives one pass) gave greedy 37% wins / 1.08x, i.e. no skill. Seeds 1-100: greedy 118.2 s/1%/43.0, careful 174.9 s/69%/73.4, 1.48x (holdout 1.54x). Unlit Shades now reach hold 100% and are seen holding ~5.8 s (was 0%).

- 2026-09-26T06:17 **qa-1**: Lab baseline = R9 after M2 (GJ-12 sim + gd-1 retune). Intended moves per the GJ-12 description: careful saved/score UP (improved), careful flares_used UP 6.1->8.0, careful lost FLAT-UP 0.23->0.30 (won 0.77->0.70, inside the 0.45-0.85 band), greedy/idle/random flat. R9 matches gd-1's BotRunner seeds 1-30 predictions.

- 2026-09-26T15:31 **producer**: M2 accepted by Boss: Shade rule learnable in night 1, fade length OK

- 2026-09-26T21:26 **producer**: Boss picked framing A 'The Drowned': Shades are ghost ships of the reef's wrecks back for the old lamp's last night; the living see the rocks, the dead see only the light. Title/end copy per Framing.md option A; HULL label becomes LAMP

- 2026-09-26T22:03 **producer**: M3 accepted by Boss after playtest: 'game seems better'
