"""
GDD invariants 1-6 checked between two consecutive observations. Used by Tests/TestRunner.gd,
Tests/BotRunner.gd and the Playtest Lab target. The run-twice determinism check lives in TestRunner.
Owner: ticket A (sim core, GJ-4).
"""
class_name NightbeamInvariants extends RefCounted

const SEVERITY_DEFAULT: String = "P1"
const SEVERITY_CRITICAL: String = "P0"
## Float slack for comparisons (GDD invariant 1 uses +1e-6).
const EPSILON: float = 0.000001
## Top-level fields that must not change once the night has ended.
const TERMINAL_FIELDS: PackedStringArray = [
	"tick", "time", "beam_angle", "hull", "saved", "score", "flare_charges", "flare_cd", "flares_used", "state",
]


"""
Returns [] when every invariant holds, else an Array of {"id", "message", "severity"} Dictionaries
(Playtest Lab bridge format). prev is {} on the first call after a reset.
Ids: beam-range, beam-speed, counters-monotonic, hull-range, flare-range, entity-in-bay,
guidance-range, entity-cap, terminal-final, run-length, shade-gap (5), shade-hold, fading-lit,
shade-wreck-unlit (6).
"""
static func check(prev: Dictionary, curr: Dictionary, tuning: NightbeamTuning) -> Array:
	var out: Array = []
	_check_ranges(curr, tuning, out)
	_check_entities(curr, tuning, out)
	_check_shade_lanes(curr, tuning, out)
	_check_shade_wrecks(curr, out)
	if not prev.is_empty():
		_check_transition(prev, curr, tuning, out)
		_check_shade_moves(prev, curr, tuning, out)
	return out


"""Builds one violation entry in the bridge format."""
static func violation(id: String, message: String, severity: String = SEVERITY_DEFAULT) -> Dictionary:
	return {"id": id, "message": message, "severity": severity}


static func _check_ranges(curr: Dictionary, tuning: NightbeamTuning, out: Array) -> void:
	var beam: float = curr["beam_angle"]
	if not (beam >= 0.0 and beam < TAU):
		out.append(violation("beam-range", "beam_angle %f outside [0, TAU)" % beam))
	var hull: int = curr["hull"]
	if hull < 0 or hull > tuning.hull_max:
		out.append(violation("hull-range", "hull %d outside [0, %d]" % [hull, tuning.hull_max]))
	var charges: int = curr["flare_charges"]
	if charges < 0 or charges > tuning.flare_max_charges:
		out.append(violation("flare-range", "flare_charges %d outside [0, %d]" % [charges, tuning.flare_max_charges]))
	var time: float = curr["time"]
	if time > tuning.dawn_time + tuning.dt() + EPSILON:
		out.append(violation("run-length", "time %f past dawn_time + dt" % time, SEVERITY_CRITICAL))


static func _check_entities(curr: Dictionary, tuning: NightbeamTuning, out: Array) -> void:
	var entities: Array = curr["entities"]
	if entities.size() > tuning.max_entities:
		out.append(violation("entity-cap", "%d live entities > %d" % [entities.size(), tuning.max_entities]))
	var despawn_radius: float = tuning.despawn_radius()
	for e: Dictionary in entities:
		var radius: float = e["radius"]
		if not (radius > tuning.reef_radius and radius <= despawn_radius + EPSILON):
			out.append(violation("entity-in-bay", "entity %d radius %f outside (%f, %f]"
				% [e["id"], radius, tuning.reef_radius, despawn_radius]))
		var guidance: float = e["guidance"]
		if not (guidance >= 0.0 and guidance <= 1.0):
			out.append(violation("guidance-range", "entity %d guidance %f outside [0, 1]" % [e["id"], guidance]))


static func _check_transition(prev: Dictionary, curr: Dictionary, tuning: NightbeamTuning, out: Array) -> void:
	var max_turn: float = tuning.beam_turn_speed * tuning.dt() + EPSILON
	var moved: float = absf(NightbeamSim.angle_diff(curr["beam_angle"], prev["beam_angle"]))
	if moved > max_turn:
		out.append(violation("beam-speed", "beam moved %f > %f in one tick" % [moved, max_turn]))
	if curr["saved"] < prev["saved"] or curr["score"] < prev["score"] or curr["hull"] > prev["hull"]:
		out.append(violation("counters-monotonic", "saved %d->%d, score %d->%d, hull %d->%d" % [
			prev["saved"], curr["saved"], prev["score"], curr["score"], prev["hull"], curr["hull"]]))
	var running: String = NightbeamSim.state_name(NightbeamSim.State.RUNNING)
	if prev["state"] != running:
		for field: String in TERMINAL_FIELDS:
			if curr[field] != prev[field]:
				out.append(violation("terminal-final", "%s changed after the end: %s -> %s"
					% [field, str(prev[field]), str(curr[field])], SEVERITY_CRITICAL))
		if curr["entities"] != prev["entities"]:
			out.append(violation("terminal-final", "entities changed after the end", SEVERITY_CRITICAL))
	elif curr["state"] == running and curr["time"] >= tuning.dawn_time + tuning.dt() - EPSILON:
		out.append(violation("run-length", "still running at time %f" % curr["time"], SEVERITY_CRITICAL))


"""Invariant 5: every unsaved ship is >= shade_gap from every non-fading Shade; fading Shades are never lit."""
static func _check_shade_lanes(curr: Dictionary, tuning: NightbeamTuning, out: Array) -> void:
	var ships: Array = []
	var shades: Array = []
	for e: Dictionary in curr["entities"]:
		if e["kind"] == "ship":
			if not e["saved"]:
				ships.append(e)
		elif e.get("fading", false):
			if e["lit"]:
				out.append(violation("fading-lit", "fading shade %d is lit" % e["id"]))
		else:
			shades.append(e)
	var min_gap: float = tuning.shade_gap - EPSILON
	for ship: Dictionary in ships:
		for shade: Dictionary in shades:
			var gap: float = absf(NightbeamSim.angle_diff(ship["angle"], shade["angle"]))
			if gap < min_gap:
				out.append(violation("shade-gap", "ship %d and shade %d only %f rad apart (< %f)"
					% [ship["id"], shade["id"], gap, tuning.shade_gap]))


"""Invariant 6: every wreck of a Shade happened on a tick it was lit."""
static func _check_shade_wrecks(curr: Dictionary, out: Array) -> void:
	for ev: Dictionary in curr.get("events", []):
		if ev["type"] == NightbeamSim.EVENT_WRECK and ev.get("kind", "") == "shade" and not ev.get("lit", false):
			out.append(violation("shade-wreck-unlit", "shade %d hit the reef while dark" % ev["id"], SEVERITY_CRITICAL))


"""Invariant 6: a dark Shade never moves inward past shade_hold_radius, a fading Shade never moves."""
static func _check_shade_moves(prev: Dictionary, curr: Dictionary, tuning: NightbeamTuning, out: Array) -> void:
	var before: Dictionary = {}
	for e: Dictionary in prev["entities"]:
		if e["kind"] == "shade":
			before[e["id"]] = e["radius"]
	for e: Dictionary in curr["entities"]:
		if e["kind"] != "shade" or not before.has(e["id"]) or e["lit"]:
			continue
		var old_radius: float = before[e["id"]]
		var radius: float = e["radius"]
		if e.get("fading", false) and absf(radius - old_radius) > EPSILON:
			out.append(violation("shade-hold", "fading shade %d moved %f -> %f" % [e["id"], old_radius, radius]))
		elif radius < old_radius - EPSILON and radius < tuning.shade_hold_radius - EPSILON:
			out.append(violation("shade-hold", "dark shade %d moved inward past the hold radius: %f -> %f"
				% [e["id"], old_radius, radius], SEVERITY_CRITICAL))
