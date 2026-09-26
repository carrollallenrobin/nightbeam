"""
Headless test entry: unit checks of the GDD rules, invariants over many seeds x bot skills, and the
run-twice determinism check (equal state_hash). Exit code = number of failures.
Run: godot --headless --path . -s res://Tests/TestRunner.gd
Optional: -- --seeds=1-100 (seeds for the invariant + determinism sweep and the GJ-11 shade sweeps)
"""
extends SceneTree

const NightRunner: GDScript = preload("res://Tests/NightRunner.gd")
const TUNING_PATH: String = "res://Data/Tuning/NightbeamTuning.tres"
const DEFAULT_SWEEP_SEEDS: String = "1-100"
const EPS: float = 0.00001
const FAR_FUTURE: float = 100000.0
## GJ-11 values gd-1 sets in the .tres retune; used where a test needs the GJ-11 opening / hold behaviour.
const GJ11_SHADE_START_TIME: float = 15.0
const GJ11_SHADE_SPEED_DARK: float = 20.0
## GJ-12 AC: the lane rule may skip at most this share of scheduled spawns.
const MAX_SKIPPED_PCT: float = 1.0
## Keeps the lane-geometry beam a hair inside the cone edge (the lit test is <= and floats round both ways).
const EDGE_FACTOR: float = 0.9999
## The beam-off sweep checks invariants on every Nth tick to stay fast (the bot sweep checks every tick).
const INVARIANT_SAMPLE_TICKS: int = 1

var _failures: int = 0
var _checks: int = 0
var _tuning: NightbeamTuning = null
var _sweep_spec: String = DEFAULT_SWEEP_SEEDS


func _init() -> void:
	_tuning = load(TUNING_PATH) as NightbeamTuning
	_expect(_tuning != null, "tuning resource loads")
	if _tuning == null:
		quit(1)
		return
	var args: Dictionary = NightRunner.parse_user_args()
	_sweep_spec = args.get("seeds", DEFAULT_SWEEP_SEEDS)
	_test_tuning_defaults()
	_test_ramps()
	_test_angles()
	_test_api_smoke()
	_test_beam_turn()
	_test_guidance_and_save()
	_test_guidance_decay()
	_test_wreck_and_lose()
	_test_flare()
	_test_shade_rules()
	_test_shade_hold_and_fade()
	_test_lane_geometry()
	_test_lane_rule_on_spawn()
	_test_spiral_and_saved_despawn()
	_test_spawns()
	_test_lone_shade_opening()
	_test_dark_shades_never_wreck()
	_test_win_at_dawn()
	_test_invariant_checker_catches_bad_state()
	_test_bots_are_pure()
	_test_sweep(NightRunner.parse_seeds(_sweep_spec))
	print("TestRunner: %d checks, %d failure(s)" % [_checks, _failures])
	quit(_failures)


# --- unit tests --------------------------------------------------------------------------------

func _test_tuning_defaults() -> void:
	# Script defaults must equal the GDD table; the .tres may hold tuned values on top.
	var gdd: Dictionary = {
		"dawn_time": 180.0, "hull_max": 5, "beam_turn_speed": 2.6, "beam_half_width": 0.26, "beam_range": 260.0,
		"spawn_radius": 250.0, "reef_radius": 48.0, "ship_heading_jitter": 0.25, "ship_speed_start": 22.0,
		"ship_speed_end": 40.0, "saved_speed": 55.0, "guide_time": 1.0, "guide_decay": 0.3,
		"spawn_interval_start": 3.0, "spawn_interval_end": 1.1, "first_spawn_delay": 1.5,
		"min_spawn_separation": 0.35, "shade_start_time": 20.0, "shade_chance_end": 0.35, "shade_speed_dark": 12.0,
		"shade_speed_lit": 70.0, "shade_lifetime": 14.0, "flare_start_charges": 1, "flare_max_charges": 2,
		"flare_saves_per_charge": 6, "flare_cooldown": 2.0, "flare_guide": 0.6, "flare_radius": 140.0,
		"max_entities": 64, "score_per_save": 10, "score_per_hull": 25, "sim_hz": 60,
		"shade_chance_start": 0.2, "shade_gap": 0.60, "spawn_retry_step": 0.35, "lone_shade_time": 7.0,
		"shade_hold_radius": 120.0, "shade_fade_time": 0.75,
	}
	var defaults: NightbeamTuning = NightbeamTuning.new()
	for key: String in gdd:
		_expect(is_equal_approx(float(defaults.get(key)), float(gdd[key])), "GDD default %s = %s" % [key, str(gdd[key])])
		_expect(_tuning.get(key) != null, "tuning .tres has %s" % key)
	_expect(is_equal_approx(defaults.dt(), 1.0 / 60.0), "dt = 1/60")
	_expect(defaults.dawn_tick() == 10800, "dawn_tick = 10800")
	_expect(defaults.spawn_retry_count() == 17, "lane rule retries k = 1..17 (one full turn)")
	_expect(_tuning.shade_gap > 2.0 * _tuning.beam_half_width, "shade_gap > beam width (lane guarantee)")
	_expect(_tuning.shade_hold_radius > _tuning.reef_radius and _tuning.shade_hold_radius <= _tuning.flare_radius,
		"hold radius is outside the reef and inside the flare")


func _test_ramps() -> void:
	var t: NightbeamTuning = NightbeamTuning.new()
	_near(t.spawn_interval(0.0), 3.0, "spawn_interval(0)")
	_near(t.spawn_interval(90.0), 2.05, "spawn_interval(90)")
	_near(t.spawn_interval(500.0), 1.1, "spawn_interval clamps past dawn")
	_near(t.ship_speed(0.0), 22.0, "ship_speed(0)")
	_near(t.ship_speed(180.0), 40.0, "ship_speed(180)")
	_near(t.shade_chance(19.9), 0.0, "shade_chance before start")
	_near(t.shade_chance(20.0), 0.2, "shade_chance at start = shade_chance_start")
	_near(t.shade_chance(100.0), lerpf(0.2, 0.35, 80.0 / 160.0), "shade_chance(100)")
	_near(t.shade_chance(180.0), 0.35, "shade_chance at dawn")


func _test_angles() -> void:
	_near(NightbeamSim.angle_diff(0.1, TAU - 0.1), 0.2, "angle_diff wraps forward")
	_near(NightbeamSim.angle_diff(TAU - 0.1, 0.1), -0.2, "angle_diff wraps backward")
	_near(NightbeamSim.angle_diff(PI, 0.0), PI, "angle_diff(PI, 0) = PI")
	_near(NightbeamSim.wrap_angle(-0.5), TAU - 0.5, "wrap negative")
	_near(NightbeamSim.wrap_angle(TAU), 0.0, "wrap TAU -> 0")
	_expect(NightbeamSim.wrap_angle(-1e-18) < TAU, "wrap tiny negative stays < TAU")


func _test_api_smoke() -> void:
	var sim: NightbeamSim = NightbeamSim.new(1, _tuning)
	sim.step({})
	var obs: Dictionary = sim.get_observation()
	_expect(obs.has_all(["tick", "time", "beam_angle", "hull", "saved", "score", "flare_charges", "flare_cd",
		"flares_used", "state", "entities", "events"]), "observation schema keys")
	_expect(obs["tick"] == 1 and obs["state"] == "running" and obs["hull"] == _tuning.hull_max, "first tick state")
	_near(obs["beam_angle"], 0.0, "missing action keys mean no turn")
	_expect(JSON.parse_string(JSON.stringify(obs)) != null, "observation is JSON-safe")
	_expect(sim.get_seed() == 1 and sim.get_tick() == 1, "get_seed / get_tick")


func _test_beam_turn() -> void:
	var sim: NightbeamSim = _empty_sim()
	sim.step({"turn": 1.0})
	_near(sim.get_observation()["beam_angle"], _tuning.beam_turn_speed * _tuning.dt(), "full right turn")
	sim.step({"turn": 7.0})
	_near(sim.get_observation()["beam_angle"], 2.0 * _tuning.beam_turn_speed * _tuning.dt(), "turn clamped to 1")
	sim = _empty_sim()
	sim.step({"turn": -1.0})
	_near(sim.get_observation()["beam_angle"], TAU - _tuning.beam_turn_speed * _tuning.dt(), "left turn wraps")
	sim.step({"turn": NAN})
	_near(sim.get_observation()["beam_angle"], TAU - _tuning.beam_turn_speed * _tuning.dt(), "NaN turn = 0")


func _test_guidance_and_save() -> void:
	var sim: NightbeamSim = _empty_sim()
	sim._entities.append(_ship(0, 0.0, 200.0, 1.0))
	var ticks: int = 0
	while sim.get_observation()["saved"] == 0 and ticks < 200:
		sim.step({})
		ticks += 1
	var obs: Dictionary = sim.get_observation()
	_expect(ticks == int(round(_tuning.guide_time * _tuning.sim_hz)), "lit ship saved after guide_time (%d ticks)" % ticks)
	_expect(obs["score"] == _tuning.score_per_save, "score += score_per_save on save")
	_expect(_has_event(obs, "saved", 0), "saved event")
	var e: Dictionary = obs["entities"][0]
	_expect(e["saved"] and is_equal_approx(e["speed"], _tuning.saved_speed), "saved ship speed = saved_speed")
	var r0: float = e["radius"]
	sim.step({})
	_expect(sim.get_observation()["entities"][0]["radius"] > r0, "saved ship heads outward")


func _test_guidance_decay() -> void:
	var sim: NightbeamSim = _empty_sim()
	var ship: Dictionary = _ship(0, PI, 200.0, 1.0)
	ship["guidance"] = 0.5
	sim._entities.append(ship)
	sim.step({})
	_near(sim.get_observation()["entities"][0]["guidance"], 0.5 - _tuning.guide_decay * _tuning.dt(), "dark decay")
	ship["guidance"] = 0.001
	sim.step({})
	_near(sim.get_observation()["entities"][0]["guidance"], 0.0, "decay floors at 0")
	var far: NightbeamSim = _empty_sim()
	far._entities.append(_ship(0, 0.0, _tuning.beam_range + 5.0, 0.0))
	far.step({})
	_expect(not far.get_observation()["entities"][0]["lit"], "out of beam_range is not lit")


func _test_wreck_and_lose() -> void:
	var sim: NightbeamSim = _empty_sim()
	sim._entities.append(_ship(0, PI, _tuning.reef_radius + 0.1, 30.0))
	sim.step({})
	var obs: Dictionary = sim.get_observation()
	_expect(obs["hull"] == _tuning.hull_max - 1 and obs["entities"].is_empty(), "wreck removes ship, hull -1")
	_expect(_has_event(obs, "wreck", 0) and _event(obs, "wreck", 0)["kind"] == "ship", "wreck event with kind ship")
	sim._hull = 1
	sim._entities.append(_ship(1, PI, _tuning.reef_radius + 0.1, 30.0))
	sim.step({})
	obs = sim.get_observation()
	_expect(obs["state"] == "lost" and sim.is_over() and sim.result() == NightbeamSim.State.LOST, "hull 0 -> LOST")
	_expect(_has_event(obs, "lost", -1), "lost event")
	var h: int = sim.state_hash()
	sim.step({"turn": 1.0, "flare": true})
	_expect(sim.state_hash() == h and sim.get_observation()["events"].is_empty(), "step after end is a no-op")


func _test_flare() -> void:
	var sim: NightbeamSim = _empty_sim()
	sim._entities.append(_ship(0, PI, 200.0, 1.0))
	sim._entities.append(_shade(1, 1.0, _tuning.flare_radius - 1.0))
	sim._entities.append(_shade(2, 2.0, _tuning.flare_radius + 20.0))
	sim.step({"flare": true})
	var obs: Dictionary = sim.get_observation()
	_expect(obs["flare_charges"] == _tuning.flare_start_charges - 1 and obs["flares_used"] == 1, "flare spends a charge")
	_near(obs["flare_cd"], _tuning.flare_cooldown, "flare sets cooldown")
	_expect(obs["entities"].size() == 2 and obs["entities"][1]["id"] == 2, "shade inside flare_radius is flared")
	_expect(_has_event(obs, "flare", -1) and _has_event(obs, "shade_flared", 1), "flare + shade_flared events")
	_expect(_event(obs, "shade_flared", 1).get("kind", "") == "shade", "shade_flared carries kind")
	_near(obs["entities"][0]["guidance"], _tuning.flare_guide - _tuning.guide_decay * _tuning.dt(), "flare adds guidance")
	sim._flare_charges = 1
	sim.step({"flare": true})
	_expect(sim.get_observation()["flares_used"] == 1, "flare blocked by cooldown")
	# A flare that pushes guidance to >= 1 saves the ship that tick, even in the dark.
	var s2: NightbeamSim = _empty_sim()
	var ship: Dictionary = _ship(0, PI, 200.0, 1.0)
	ship["guidance"] = 1.0 - _tuning.flare_guide + 0.001
	s2._entities.append(ship)
	s2.step({"flare": true})
	_expect(s2.get_observation()["saved"] == 1, "flare can complete a save")
	# Recharge: +1 every flare_saves_per_charge saves, capped.
	var s3: NightbeamSim = _empty_sim()
	s3._flare_charges = 0
	for i: int in _tuning.flare_saves_per_charge:
		var lit_ship: Dictionary = _ship(i, 0.0, 200.0, 0.0)
		lit_ship["guidance"] = 0.99
		s3._entities.append(lit_ship)
	s3.step({})
	_expect(s3.get_observation()["flare_charges"] == 1, "flare recharges after flare_saves_per_charge saves")


func _test_shade_rules() -> void:
	var sim: NightbeamSim = _empty_sim()
	sim._entities.append(_shade(0, 0.0, 200.0))
	sim._entities.append(_shade(1, PI, 200.0))
	sim.step({})
	var obs: Dictionary = sim.get_observation()
	_near(obs["entities"][0]["radius"], 200.0 - _tuning.shade_speed_lit * _tuning.dt(), "lit shade speed")
	_near(obs["entities"][1]["radius"], 200.0 - _tuning.shade_speed_dark * _tuning.dt(), "dark shade speed")
	_expect(obs["entities"][0]["lit"] and not obs["entities"][1]["lit"], "shade lit flags")
	var old: Dictionary = _shade(2, PI, 200.0)
	old["age"] = _tuning.shade_lifetime - 0.5 * _tuning.dt()
	sim._entities.append(old)
	sim.step({})
	obs = sim.get_observation()
	_expect(obs["entities"].size() == 2 and _has_event(obs, "shade_fade", 2), "shade fades out at shade_lifetime")
	_expect(obs["hull"] == _tuning.hull_max, "shade_fade costs no hull")


func _test_shade_hold_and_fade() -> void:
	var sim: NightbeamSim = _empty_sim()
	var dt: float = _tuning.dt()
	sim._entities.append(_shade(0, PI, _tuning.shade_hold_radius + 0.5 * _tuning.shade_speed_dark * dt))
	sim._entities.append(_shade(1, PI + 1.0, _tuning.shade_hold_radius - 30.0))
	sim._entities.append(_shade(2, 0.0, _tuning.shade_hold_radius - 30.0))
	sim.step({})
	var obs: Dictionary = sim.get_observation()
	_near(obs["entities"][0]["radius"], _tuning.shade_hold_radius, "dark shade stops exactly at the hold radius")
	sim.step({})
	obs = sim.get_observation()
	_near(obs["entities"][0]["radius"], _tuning.shade_hold_radius, "dark shade holds")
	_near(obs["entities"][0]["speed"], 0.0, "holding shade reports speed 0")
	_near(obs["entities"][1]["radius"], _tuning.shade_hold_radius - 30.0, "dark shade below hold (pulled by light) stays")
	_expect(obs["entities"][2]["lit"] and obs["entities"][2]["radius"] < _tuning.shade_hold_radius - 30.0,
		"lit shade still lunges inside the hold radius")
	# Fading: never lit, never moves, flagged in the observation, then shade_fade.
	var s2: NightbeamSim = _empty_sim()
	var fading: Dictionary = _shade(0, 0.0, 200.0)
	fading["age"] = _tuning.shade_fade_age()
	s2._entities.append(fading)
	s2.step({})
	obs = s2.get_observation()
	var e: Dictionary = obs["entities"][0]
	_expect(e["fading"] and not e["lit"], "fading shade under the beam is not lit")
	_near(e["radius"], 200.0, "fading shade does not move")
	var fade_ticks: int = 1
	while not s2.get_observation()["entities"].is_empty() and fade_ticks < 1000:
		s2.step({})
		fade_ticks += 1
	_expect(absf(fade_ticks * dt - _tuning.shade_fade_time) <= dt + EPS,
		"fade lasts shade_fade_time (%d ticks)" % fade_ticks)
	_expect(_has_event(s2.get_observation(), "shade_fade", 0), "fade ends with shade_fade")
	var young: NightbeamSim = _empty_sim()
	young._entities.append(_shade(0, PI, 200.0))
	young.step({})
	_expect(not young.get_observation()["entities"][0]["fading"], "young shade is not fading")


func _test_lane_geometry() -> void:
	# AC1 unit test: with a Shade shade_gap from a ship, no beam within beam_half_width of the ship lights it.
	var steps: int = 40
	var ok: bool = true
	for side: float in [-1.0, 1.0]:
		for i: int in steps + 1:
			var sim: NightbeamSim = _empty_sim()
			var ship_angle: float = 1.0
			sim._entities.append(_ship(0, ship_angle, 200.0, 0.0))
			sim._entities.append(_shade(1, ship_angle + side * _tuning.shade_gap, 200.0))
			sim._beam_angle = NightbeamSim.wrap_angle(ship_angle + lerpf(-1.0, 1.0, float(i) / steps) * _tuning.beam_half_width * EDGE_FACTOR)
			sim.step({})
			var obs: Dictionary = sim.get_observation()
			ok = ok and obs["entities"][0]["lit"] and not obs["entities"][1]["lit"]
	_expect(ok, "beam anywhere within beam_half_width of a ship never lights a Shade shade_gap away")
	_near(NightbeamSim.angle_to_arc(0.5, 0.0, 1.0), 0.0, "angle_to_arc: on the arc")
	_near(NightbeamSim.angle_to_arc(1.3, 0.0, 1.0), 0.3, "angle_to_arc: past the end")
	_near(NightbeamSim.angle_to_arc(TAU - 0.2, 0.0, 1.0), 0.2, "angle_to_arc: before the start, wrapped")
	_near(NightbeamSim.angle_to_arc(-0.5, 0.0, -1.0), 0.0, "angle_to_arc: negative arc")
	_near(_tuning.ship_path_sweep(0.25), tan(0.25) * log(_tuning.spawn_radius / _tuning.reef_radius), "path sweep formula")


func _test_lane_rule_on_spawn() -> void:
	# A ship's whole remaining arc blocks a Shade; the spawn is nudged by spawn_retry_step.
	var t: NightbeamTuning = _tuning.duplicate() as NightbeamTuning
	t.first_spawn_delay = FAR_FUTURE
	var sim: NightbeamSim = NightbeamSim.new(1, t)
	var ship: Dictionary = _ship(0, 1.0, 200.0, 0.0)
	ship["path_end"] = 1.3
	sim._entities.append(ship)
	_expect(not sim._lane_is_clear(NightbeamSim.Kind.SHADE, 1.3 + t.shade_gap - 0.01, 0.0), "shade too close to a ship's path end is refused")
	_expect(sim._lane_is_clear(NightbeamSim.Kind.SHADE, 1.3 + t.shade_gap + 0.01, 0.0), "shade just outside the gap is allowed")
	var nudged: float = sim._find_lane_angle(NightbeamSim.Kind.SHADE, 1.2, 0.0)
	_expect(not is_nan(nudged) and NightbeamSim.angle_to_arc(nudged, 1.0, 1.3) >= t.shade_gap,
		"blocked shade spawn is nudged to a legal lane")
	var steps_taken: float = NightbeamSim.wrap_angle(nudged - 1.2) / t.spawn_retry_step
	_near(steps_taken, roundf(steps_taken), "nudges are whole spawn_retry_steps")
	# A ship's arc (not only its spawn point) must clear existing Shades.
	var s2: NightbeamSim = NightbeamSim.new(1, t)
	s2._entities.append(_shade(0, 2.0, 200.0))
	_expect(not s2._lane_is_clear(NightbeamSim.Kind.SHIP, 2.0 - t.shade_gap - 0.3, 0.4), "ship arc sweeping towards a shade is refused")
	_expect(s2._lane_is_clear(NightbeamSim.Kind.SHIP, 2.0 - t.shade_gap - 0.3, -0.4), "ship arc sweeping away is allowed")
	var faded: Dictionary = _shade(1, 4.0, 200.0)
	faded["fading"] = true
	s2._entities.append(faded)
	_expect(s2._lane_is_clear(NightbeamSim.Kind.SHIP, 4.0, 0.0), "fading shades do not block lanes")
	# No legal angle anywhere -> skipped, counted, RNG untouched by the skip.
	var s3: NightbeamSim = NightbeamSim.new(9, t)
	for i: int in 12:
		var blocker: Dictionary = _ship(i, i * TAU / 12.0, 200.0, 0.0)
		s3._entities.append(blocker)
	s3._next_spawn_time = 0.0
	s3._lone_shade_pending = false
	var free: NightbeamSim = NightbeamSim.new(9, t)
	free._next_spawn_time = 0.0
	free._lone_shade_pending = false
	var t_shade: NightbeamTuning = t.duplicate() as NightbeamTuning
	t_shade.shade_start_time = -1.0
	t_shade.shade_chance_start = 1.0
	t_shade.shade_chance_end = 1.0
	s3._tuning = t_shade
	free._tuning = t_shade
	s3.step({})
	free.step({})
	_expect(s3.get_observation()["spawns_skipped"] == 1 and s3.get_observation()["entities"].size() == 12,
		"shade with no legal lane is skipped and counted")
	_expect(s3._rng.state == free._rng.state, "a skipped spawn draws the same RNG values")


func _test_lone_shade_opening() -> void:
	# AC4 over the sweep seeds: first spawn is a Ship, exactly one Shade before shade_start_time.
	var t: NightbeamTuning = _tuning.duplicate() as NightbeamTuning
	if t.shade_start_time <= t.lone_shade_time:
		# The .tres still has the GJ-7 negative start (gd-1 retunes to 15 s after GJ-12); test the GJ-11 opening.
		t.shade_start_time = GJ11_SHADE_START_TIME
	var bad_first: int = 0
	var bad_count: int = 0
	var bad_lone_time: int = 0
	var seeds: Array[int] = NightRunner.parse_seeds(_sweep_spec)
	for s: int in seeds:
		var sim: NightbeamSim = NightbeamSim.new(s, t)
		var memo: Dictionary = {}
		var first_kind: String = ""
		var shades_early: int = 0
		var lone_at: float = -1.0
		while not sim.is_over() and sim.get_tick() * t.dt() < t.shade_start_time:
			sim.step(NightbeamBots.act("careful", sim.get_observation(), t, memo))
			var obs: Dictionary = sim.get_observation()
			for ev: Dictionary in obs["events"]:
				if ev["type"] != "spawn":
					continue
				if first_kind == "":
					first_kind = ev["kind"]
				if ev["kind"] == "shade" and (obs["tick"] - 1) * t.dt() < t.shade_start_time:
					shades_early += 1
					lone_at = (obs["tick"] - 1) * t.dt()
		if first_kind != "ship":
			bad_first += 1
		if shades_early != 1:
			bad_count += 1
		elif lone_at + EPS < t.lone_shade_time:
			bad_lone_time += 1
	_expect(bad_first == 0, "first spawn is a Ship on all %d seeds (%d bad)" % [seeds.size(), bad_first])
	_expect(bad_count == 0, "exactly 1 Shade before shade_start_time on all %d seeds (%d bad)" % [seeds.size(), bad_count])
	_expect(bad_lone_time == 0, "the Lone Shade spawns at or after lone_shade_time (%d bad)" % bad_lone_time)


func _test_dark_shades_never_wreck() -> void:
	# AC2: a beam that never lights anything (range 0) -> Shades only drift, hold and fade: 0 Shade wrecks.
	# Long hull so every night runs to dawn; the GJ-11 dark speed (20) makes Shades reach the hold radius.
	var t: NightbeamTuning = _tuning.duplicate() as NightbeamTuning
	t.beam_range = 0.0
	t.hull_max = 100000
	t.shade_speed_dark = GJ11_SHADE_SPEED_DARK
	var shade_wrecks: int = 0
	var shade_spawns: int = 0
	var held: int = 0
	var violations: int = 0
	var seeds: Array[int] = NightRunner.parse_seeds(_sweep_spec)
	for s: int in seeds:
		var sim: NightbeamSim = NightbeamSim.new(s, t)
		var prev: Dictionary = {}
		while not sim.is_over():
			sim.step({})
			var obs: Dictionary = sim.get_observation()
			for ev: Dictionary in obs["events"]:
				if ev["kind"] == "shade":
					if ev["type"] == "wreck":
						shade_wrecks += 1
					elif ev["type"] == "spawn":
						shade_spawns += 1
					elif ev["type"] == "shade_fade" and is_equal_approx(ev["radius"], t.shade_hold_radius):
						held += 1
			if obs["tick"] % INVARIANT_SAMPLE_TICKS == 0 or sim.is_over():
				violations += NightbeamInvariants.check(prev, obs, t).size()
			prev = obs
	_expect(shade_spawns > 0 and shade_wrecks == 0,
		"unlit shades never reach the reef: %d shade spawns, %d shade wrecks over %d seeds" % [shade_spawns, shade_wrecks, seeds.size()])
	_expect(held > 0, "some dark shades fade while holding at shade_hold_radius (%d)" % held)
	_expect(violations == 0, "invariants hold with the beam off (%d)" % violations)


func _test_spiral_and_saved_despawn() -> void:
	var sim: NightbeamSim = _empty_sim()
	var ship: Dictionary = _ship(0, PI, _tuning.spawn_radius, _tuning.ship_speed_end)
	ship["drift"] = _tuning.ship_heading_jitter
	sim._entities.append(ship)
	var prev_r: float = _tuning.spawn_radius
	var decreasing: bool = true
	while not sim.get_observation()["entities"].is_empty():
		sim.step({"turn": 0.0})
		var ents: Array = sim.get_observation()["entities"]
		if not ents.is_empty():
			decreasing = decreasing and ents[0]["radius"] < prev_r
			prev_r = ents[0]["radius"]
	_expect(decreasing, "spiral radius strictly decreases")
	_expect(sim.get_observation()["hull"] == _tuning.hull_max - 1, "max-drift ship still reaches the reef")
	var s2: NightbeamSim = _empty_sim()
	var saved: Dictionary = _ship(0, PI, _tuning.despawn_radius() - 0.1, _tuning.saved_speed)
	saved["saved"] = true
	saved["guidance"] = 1.0
	s2._entities.append(saved)
	s2.step({})
	_expect(s2.get_observation()["entities"].is_empty() and s2.get_observation()["saved"] == 0,
		"saved ship despawns past spawn_radius + margin without recounting")


func _test_spawns() -> void:
	# Ships only (no Shades, no Lone Shade), so no lane nudge can move a spawn: isolates the anti-cluster rule.
	var ships_only: NightbeamTuning = _tuning.duplicate() as NightbeamTuning
	ships_only.shade_start_time = FAR_FUTURE
	ships_only.lone_shade_time = FAR_FUTURE
	var sim: NightbeamSim = NightbeamSim.new(42, ships_only)
	var first_tick: int = -1
	var prev_angle: float = NAN
	var ok_sep: bool = true
	var spawn_ticks: Array[int] = []
	for i: int in 3600:
		sim.step({})
		var obs: Dictionary = sim.get_observation()
		for ev: Dictionary in obs["events"]:
			if ev["type"] != "spawn":
				continue
			spawn_ticks.append(obs["tick"] - 1)
			if first_tick < 0:
				first_tick = obs["tick"] - 1
			if not is_nan(prev_angle):
				ok_sep = ok_sep and absf(NightbeamSim.angle_diff(ev["angle"], prev_angle)) >= _tuning.min_spawn_separation
			prev_angle = ev["angle"]
			_near(ev["radius"], _tuning.spawn_radius, "spawn at spawn_radius")
		if sim.is_over():
			break
	_expect(first_tick == int(round(_tuning.first_spawn_delay * _tuning.sim_hz)), "first spawn at first_spawn_delay (tick %d)" % first_tick)
	_expect(ok_sep, "anti-cluster keeps consecutive spawns >= min_spawn_separation apart")
	if spawn_ticks.size() >= 2:
		var gap_s: float = (spawn_ticks[1] - spawn_ticks[0]) * _tuning.dt()
		_expect(absf(gap_s - _tuning.spawn_interval(spawn_ticks[0] * _tuning.dt())) <= _tuning.dt() + EPS, "spawn interval follows the ramp")


func _test_win_at_dawn() -> void:
	var calm: NightbeamTuning = _tuning.duplicate() as NightbeamTuning
	calm.first_spawn_delay = FAR_FUTURE
	var sim: NightbeamSim = NightbeamSim.new(3, calm)
	while not sim.is_over():
		sim.step({"turn": 0.3})
	var obs: Dictionary = sim.get_observation()
	_expect(obs["state"] == "won" and obs["tick"] == calm.dawn_tick(), "WON exactly at dawn_tick")
	_near(obs["time"], calm.dawn_time, "time == dawn_time at the win")
	_expect(obs["score"] == calm.hull_max * calm.score_per_hull, "dawn bonus = hull * score_per_hull")
	_expect(_has_event(obs, "won", -1), "won event")
	# GJ-15: every Shade still out at dawn leaves with shade_fade on the winning tick; ships stay.
	var dawn: NightbeamSim = NightbeamSim.new(3, calm)
	while dawn.get_tick() < calm.dawn_tick() - 1:
		dawn.step({})
	dawn._entities.append(_shade(900, PI, 200.0))
	dawn._entities.append(_ship(901, PI + 1.5, 200.0, 0.0))
	dawn._entities.append(_shade(902, 0.5 * PI, calm.shade_hold_radius))
	dawn.step({})
	var dawn_obs: Dictionary = dawn.get_observation()
	var kinds_left: Array = []
	for e: Dictionary in dawn_obs["entities"]:
		kinds_left.append(e["kind"])
	_expect(dawn_obs["state"] == "won" and kinds_left == ["ship"], "no Shades left at dawn, ships stay")
	_expect(_has_event(dawn_obs, "shade_fade", 900) and _has_event(dawn_obs, "shade_fade", 902)
		and _event(dawn_obs, "shade_fade", 900)["kind"] == "shade", "dawn Shades leave with shade_fade")
	# A wreck on the final tick still loses.
	var s2: NightbeamSim = NightbeamSim.new(3, calm)
	while s2.get_tick() < calm.dawn_tick() - 1:
		s2.step({})
	s2._hull = 1
	s2._entities.append(_ship(999, PI, calm.reef_radius + 0.1, 30.0))
	s2.step({})
	_expect(s2.get_observation()["state"] == "lost", "wreck on the final tick loses")


func _test_invariant_checker_catches_bad_state() -> void:
	var sim: NightbeamSim = NightbeamSim.new(5, _tuning)
	var good: Dictionary = sim.get_observation()
	_expect(NightbeamInvariants.check({}, good, _tuning).is_empty(), "fresh observation passes")
	var bad: Dictionary = good.duplicate(true)
	bad["beam_angle"] = 1.0
	bad["hull"] = _tuning.hull_max + 1
	bad["flare_charges"] = -1
	bad["saved"] = -1
	bad["entities"] = [{"id": 0, "kind": "ship", "angle": 0.0, "radius": 10.0, "speed": 1.0, "guidance": 2.0,
		"saved": false, "lit": false, "age": 0.0}]
	var ids: Array = []
	for v: Dictionary in NightbeamInvariants.check(good, bad, _tuning):
		ids.append(v["id"])
	for want: String in ["beam-speed", "hull-range", "flare-range", "counters-monotonic", "entity-in-bay", "guidance-range"]:
		_expect(want in ids, "checker reports %s" % want)
	var ended: Dictionary = good.duplicate(true)
	ended["state"] = "won"
	var moved: Dictionary = ended.duplicate(true)
	moved["tick"] = 5
	_expect(_ids(NightbeamInvariants.check(ended, moved, _tuning)).has("terminal-final"), "checker reports terminal-final")
	var lane: Dictionary = good.duplicate(true)
	lane["entities"] = [
		{"id": 0, "kind": "ship", "angle": 1.0, "radius": 200.0, "speed": 1.0, "guidance": 0.0, "saved": false, "lit": false, "age": 0.0, "fading": false},
		{"id": 1, "kind": "shade", "angle": 1.3, "radius": 200.0, "speed": 0.0, "guidance": 0.0, "saved": false, "lit": false, "age": 0.0, "fading": false},
		{"id": 2, "kind": "shade", "angle": 4.0, "radius": 200.0, "speed": 0.0, "guidance": 0.0, "saved": false, "lit": true, "age": 9.0, "fading": true},
	]
	var lane_ids: Array = _ids(NightbeamInvariants.check({}, lane, _tuning))
	_expect(lane_ids.has("shade-gap") and lane_ids.has("fading-lit"), "checker reports shade-gap and fading-lit")
	var before: Dictionary = good.duplicate(true)
	before["entities"] = [{"id": 5, "kind": "shade", "angle": 2.0, "radius": _tuning.shade_hold_radius + 1.0, "speed": 0.0,
		"guidance": 0.0, "saved": false, "lit": false, "age": 1.0, "fading": false}]
	var after: Dictionary = before.duplicate(true)
	after["tick"] = before["tick"] + 1
	after["entities"][0]["radius"] = _tuning.shade_hold_radius - 1.0
	after["events"] = [{"type": "wreck", "id": 6, "kind": "shade", "angle": 0.0, "radius": 40.0, "lit": false}]
	var hold_ids: Array = _ids(NightbeamInvariants.check(before, after, _tuning))
	_expect(hold_ids.has("shade-hold") and hold_ids.has("shade-wreck-unlit"), "checker reports shade-hold and shade-wreck-unlit")


func _test_bots_are_pure() -> void:
	var sim: NightbeamSim = NightbeamSim.new(11, _tuning)
	for i: int in 1200:
		sim.step(NightbeamBots.act("greedy", sim.get_observation(), _tuning, {}))
	var obs: Dictionary = sim.get_observation()
	for skill: String in NightbeamBots.SKILLS:
		var a: Dictionary = NightbeamBots.act(skill, obs, _tuning, {})
		var b: Dictionary = NightbeamBots.act(skill, obs, _tuning, {})
		_expect(a == b, "bot %s is a pure function of obs" % skill)
		_expect(absf(float(a["turn"])) <= 1.0, "bot %s turn in [-1, 1]" % skill)
	_expect(NightbeamBots.act("idle", obs, _tuning, {}) == NightbeamBots.idle_action(), "idle bot is idle")


# --- sweep: invariants + determinism -----------------------------------------------------------

func _test_sweep(seeds: Array[int]) -> void:
	var runs: int = 0
	var violations: int = 0
	var mismatches: int = 0
	var hashes: Dictionary = {}
	var unbalanced: int = 0
	var spawns: int = 0
	var skipped: int = 0
	for skill: String in NightbeamBots.SKILLS:
		for s: int in seeds:
			var first: Dictionary = NightRunner.run_night(s, skill, _tuning, true)
			var second: Dictionary = NightRunner.run_night(s, skill, _tuning, false)
			runs += 1
			violations += int(first["violation_count"])
			for v: Dictionary in first["violations"]:
				printerr("INVARIANT seed=%d skill=%s %s: %s" % [s, skill, v["id"], v["message"]])
			if first["hash"] != second["hash"] or first["ticks"] != second["ticks"]:
				mismatches += 1
				printerr("DETERMINISM seed=%d skill=%s hash %d vs %d" % [s, skill, first["hash"], second["hash"]])
			hashes[first["hash"]] = true
			spawns += int(first["spawns"])
			skipped += int(first["spawns_skipped"])
			if int(first["shade_spawns"]) != int(first["shade_exits"]) + int(first["shades_alive"]):
				unbalanced += 1
				printerr("SHADE EXITS seed=%d skill=%s: %d spawned, %d left, %d alive" % [s, skill,
					first["shade_spawns"], first["shade_exits"], first["shades_alive"]])
	_expect(violations == 0, "invariants hold over %d seeds x %d skills (%d violations)" % [seeds.size(), NightbeamBots.SKILLS.size(), violations])
	_expect(mismatches == 0, "same seed twice gives the same state_hash (%d runs, %d mismatches)" % [runs, mismatches])
	_expect(hashes.size() * 2 > runs, "different seeds give different nights (%d distinct hashes)" % hashes.size())
	_expect(unbalanced == 0, "every Shade leaves via exactly one of shade_fade / shade_flared / wreck (%d unbalanced runs)" % unbalanced)
	var skipped_pct: float = 100.0 * skipped / maxi(spawns + skipped, 1)
	_expect(skipped_pct <= MAX_SKIPPED_PCT, "lane rule skips <= %.1f%% of spawns (%d of %d = %.3f%%)" % [MAX_SKIPPED_PCT,
		skipped, spawns + skipped, skipped_pct])
	print("sweep: %d runs, %d invariant violations, %d determinism mismatches, spawns_skipped %d of %d (%.3f%%)"
		% [runs, violations, mismatches, skipped, spawns + skipped, skipped_pct])


# --- helpers -----------------------------------------------------------------------------------

func _empty_sim() -> NightbeamSim:
	var calm: NightbeamTuning = _tuning.duplicate() as NightbeamTuning
	calm.first_spawn_delay = FAR_FUTURE
	return NightbeamSim.new(1, calm)


func _ship(id: int, angle: float, radius: float, speed: float) -> Dictionary:
	return {"id": id, "kind": NightbeamSim.Kind.SHIP, "angle": angle, "radius": radius, "speed": speed,
		"drift": 0.0, "path_end": angle, "guidance": 0.0, "saved": false, "lit": false, "fading": false, "age": 0.0}


func _shade(id: int, angle: float, radius: float) -> Dictionary:
	return {"id": id, "kind": NightbeamSim.Kind.SHADE, "angle": angle, "radius": radius,
		"speed": _tuning.shade_speed_dark, "drift": 0.0, "path_end": angle, "guidance": 0.0, "saved": false,
		"lit": false, "fading": false, "age": 0.0}


func _event(obs: Dictionary, type: String, id: int) -> Dictionary:
	for ev: Dictionary in obs["events"]:
		if ev["type"] == type and ev["id"] == id:
			return ev
	return {}


func _has_event(obs: Dictionary, type: String, id: int) -> bool:
	for ev: Dictionary in obs["events"]:
		if ev["type"] == type and ev["id"] == id:
			return true
	return false


func _ids(violations: Array) -> Array:
	var out: Array = []
	for v: Dictionary in violations:
		out.append(v["id"])
	return out


func _near(actual: float, expected: float, label: String) -> void:
	_expect(absf(actual - expected) <= EPS, "%s (got %f, want %f)" % [label, actual, expected])


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + label)
