"""
Shared headless helper for Tests/TestRunner.gd and Tests/BotRunner.gd: plays one whole night with a bot
skill, optionally checking NightbeamInvariants every tick, and returns a flat summary Dictionary.
"""
extends RefCounted

## Ticks allowed past dawn before the runner gives up (a run that long is itself a run-length failure).
const EXTRA_TICKS: int = 10
## How many violation messages to keep per night (the count is always exact).
const MAX_KEPT_VIOLATIONS: int = 5


"""
Runs seed x skill to the end. Returns {seed, skill, result, time_survived, saved, hull, score,
flares_used, ticks, hash, shade_wrecks, spawns, spawns_skipped, shade_spawns, shade_exits, shades_alive,
tally, violation_count, violations}.
"""
static func run_night(night_seed: int, skill: String, tuning: NightbeamTuning, check: bool) -> Dictionary:
	var sim: NightbeamSim = NightbeamSim.new(night_seed, tuning)
	var memo: Dictionary = {}
	var obs: Dictionary = sim.get_observation()
	var prev: Dictionary = {}
	var violations: Array = []
	var violation_count: int = 0
	var max_ticks: int = tuning.dawn_tick() + EXTRA_TICKS
	var tally: Dictionary = {}
	if check:
		violation_count += _collect(NightbeamInvariants.check(prev, obs, tuning), violations)
	while not sim.is_over() and sim.get_tick() < max_ticks:
		sim.step(NightbeamBots.act(skill, obs, tuning, memo))
		prev = obs
		obs = sim.get_observation()
		_tally_events(obs, tally)
		if check:
			violation_count += _collect(NightbeamInvariants.check(prev, obs, tuning), violations)
	if not sim.is_over():
		violation_count += _collect([NightbeamInvariants.violation("run-length", "night never ended", "P0")], violations)
	if check:
		# Terminal is final: one more step must change nothing.
		var end_hash: int = sim.state_hash()
		sim.step({NightbeamSim.ACTION_TURN: 1.0, NightbeamSim.ACTION_FLARE: true})
		var after: Dictionary = sim.get_observation()
		violation_count += _collect(NightbeamInvariants.check(obs, after, tuning), violations)
		if sim.state_hash() != end_hash:
			violation_count += _collect([NightbeamInvariants.violation("terminal-final", "state_hash changed after the end", "P0")], violations)
	return {
		"seed": night_seed, "skill": skill, "result": obs["state"], "time_survived": obs["time"],
		"saved": obs["saved"], "hull": obs["hull"], "score": obs["score"], "flares_used": obs["flares_used"],
		"ticks": obs["tick"], "hash": sim.state_hash(), "shade_wrecks": int(tally.get("wreck:shade", 0)),
		"spawns": int(tally.get("spawn:ship", 0)) + int(tally.get("spawn:shade", 0)),
		"spawns_skipped": obs["spawns_skipped"], "shade_spawns": int(tally.get("spawn:shade", 0)),
		"shade_exits": int(tally.get("shade_fade:shade", 0)) + int(tally.get("shade_flared:shade", 0))
			+ int(tally.get("wreck:shade", 0)),
		"shades_alive": _count_kind(obs, "shade"), "tally": tally, "violation_count": violation_count, "violations": violations,
	}


"""Parses "1-100" or "1,5,9" or "7" into an ascending list of seeds."""
static func parse_seeds(spec: String) -> Array[int]:
	var seeds: Array[int] = []
	for part: String in spec.split(",", false):
		if part.contains("-"):
			var bounds: PackedStringArray = part.split("-", false)
			for s: int in range(int(bounds[0]), int(bounds[1]) + 1):
				seeds.append(s)
		else:
			seeds.append(int(part))
	return seeds


"""Reads --key=value user args (after "--") into a Dictionary."""
static func parse_user_args() -> Dictionary:
	var args: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var kv: PackedStringArray = arg.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	return args


"""Counts this tick's events by "type:kind" (e.g. "wreck:shade", "spawn:ship", "flare:")."""
static func _tally_events(obs: Dictionary, tally: Dictionary) -> void:
	for ev: Dictionary in obs["events"]:
		var key: String = "%s:%s" % [ev["type"], ev.get("kind", "")]
		tally[key] = int(tally.get(key, 0)) + 1


static func _count_kind(obs: Dictionary, kind: String) -> int:
	var n: int = 0
	for e: Dictionary in obs["entities"]:
		if e["kind"] == kind:
			n += 1
	return n


static func _collect(found: Array, kept: Array) -> int:
	for v: Dictionary in found:
		if kept.size() < MAX_KEPT_VIOLATIONS:
			kept.append(v)
	return found.size()
