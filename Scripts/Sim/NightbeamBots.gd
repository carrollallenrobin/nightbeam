"""
Scripted NIGHTBEAM bot skills (GDD "Bot skills"): idle, greedy, careful. Fading Shades (GJ-11) are ignored,
since they can never be lit. Pure functions of
(observation, tuning, memo) with no RNG, so a (seed, skill) pair is fully deterministic.
Reused by Tests/BotRunner.gd and by the Playtest Lab target ({"policy": "<skill>"} actions).
Owner: ticket A (sim core, GJ-4).
"""
class_name NightbeamBots extends RefCounted

const SKILLS: PackedStringArray = ["idle", "greedy", "careful"]
const SKILL_IDLE: String = "idle"
const SKILL_GREEDY: String = "greedy"
const SKILL_CAREFUL: String = "careful"
## Careful flares when this many unsaved ships are closer than CAREFUL_FLARE_ETA seconds to the reef.
const CAREFUL_FLARE_SHIPS: int = 3
const CAREFUL_FLARE_ETA: float = 2.5
## Extra angle (radians) around the cone where careful still counts a Shade as "in the light".
const CAREFUL_SHADE_MARGIN: float = 0.05
## Seconds of light a Shade must still be able to absorb after careful finishes filling a ship.
const CAREFUL_SHADE_SAFETY: float = 1.0
## Guards divisions by a zero speed.
const MIN_SPEED: float = 0.001


"""Returns the sim action for skill on this observation. memo is per-run scratch space owned by the caller."""
static func act(skill: String, obs: Dictionary, tuning: NightbeamTuning, memo: Dictionary) -> Dictionary:
	match skill:
		SKILL_GREEDY:
			return _greedy(obs, tuning)
		SKILL_CAREFUL:
			return _careful(obs, tuning, memo)
		_:
			return idle_action()


"""The idle baseline action: no turn, no flare."""
static func idle_action() -> Dictionary:
	return {NightbeamSim.ACTION_TURN: 0.0, NightbeamSim.ACTION_FLARE: false}


"""Seconds until this entity reaches the reef at its current speed."""
static func time_to_reef(e: Dictionary, tuning: NightbeamTuning) -> float:
	return (float(e["radius"]) - tuning.reef_radius) / maxf(float(e["speed"]), MIN_SPEED)


"""Turn value that moves the beam toward target_angle along the shortest way, capped at full speed."""
static func turn_toward(beam_angle: float, target_angle: float, tuning: NightbeamTuning) -> float:
	var diff: float = NightbeamSim.angle_diff(target_angle, beam_angle)
	return clampf(diff / (tuning.beam_turn_speed * tuning.dt()), -1.0, 1.0)


# --- greedy ------------------------------------------------------------------------------------

static func _greedy(obs: Dictionary, tuning: NightbeamTuning) -> Dictionary:
	var beam: float = obs["beam_angle"]
	var target: Dictionary = _closest_ship(obs["entities"], beam)
	var turn: float = 0.0 if target.is_empty() else turn_toward(beam, target["angle"], tuning)
	var flare: bool = _flare_ready(obs) and not target.is_empty()
	return {NightbeamSim.ACTION_TURN: turn, NightbeamSim.ACTION_FLARE: flare}


static func _closest_ship(entities: Array, beam: float) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = INF
	for e: Dictionary in entities:
		if e["kind"] != "ship" or e["saved"]:
			continue
		var dist: float = absf(NightbeamSim.angle_diff(e["angle"], beam))
		if dist < best_dist:
			best_dist = dist
			best = e
	return best


# --- careful -----------------------------------------------------------------------------------

static func _careful(obs: Dictionary, tuning: NightbeamTuning, _memo: Dictionary) -> Dictionary:
	var beam: float = obs["beam_angle"]
	var entities: Array = obs["entities"]
	var target: Dictionary = _most_urgent_reachable_ship(entities, beam, tuning)
	if target.is_empty():
		target = _closest_safe_ship(entities, beam, tuning)
	var turn: float = 0.0
	if not target.is_empty():
		turn = _safe_turn(entities, beam, target["angle"], tuning)
	else:
		turn = _escape_turn(entities, beam, tuning)
	return {NightbeamSim.ACTION_TURN: turn, NightbeamSim.ACTION_FLARE: _careful_wants_flare(obs, tuning)}


"""Unsaved ship with the lowest time-to-reef that the beam can still reach and fill before it wrecks."""
static func _most_urgent_reachable_ship(entities: Array, beam: float, tuning: NightbeamTuning) -> Dictionary:
	var best: Dictionary = {}
	var best_eta: float = INF
	for e: Dictionary in entities:
		if e["kind"] != "ship" or e["saved"]:
			continue
		var eta: float = time_to_reef(e, tuning)
		var gap: float = maxf(absf(NightbeamSim.angle_diff(e["angle"], beam)) - tuning.beam_half_width, 0.0)
		var turn_time: float = gap / tuning.beam_turn_speed
		var fill_time: float = tuning.guide_time * (1.0 - float(e["guidance"]))
		if turn_time + fill_time > eta:
			continue
		if _shade_would_wreck(entities, float(e["angle"]), fill_time, tuning):
			continue
		if eta < best_eta:
			best_eta = eta
			best = e
	return best


"""Fallback when no ship can be filled in time: the angularly closest ship that is safe to light (flares may still save it)."""
static func _closest_safe_ship(entities: Array, beam: float, tuning: NightbeamTuning) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = INF
	for e: Dictionary in entities:
		if e["kind"] != "ship" or e["saved"]:
			continue
		var dist: float = absf(NightbeamSim.angle_diff(e["angle"], beam))
		if dist < best_dist and not _shade_would_wreck(entities, float(e["angle"]), tuning.guide_time, tuning):
			best_dist = dist
			best = e
	return best


"""With nothing worth lighting: steer away from the nearest Shade in the cone, else hold still."""
static func _escape_turn(entities: Array, beam: float, tuning: NightbeamTuning) -> float:
	var nearest: float = INF
	var turn: float = 0.0
	for e: Dictionary in entities:
		if e["kind"] != "shade" or e.get("fading", false) or float(e["radius"]) > tuning.beam_range:
			continue
		var diff: float = NightbeamSim.angle_diff(float(e["angle"]), beam)
		if absf(diff) <= tuning.beam_half_width + CAREFUL_SHADE_MARGIN and absf(diff) < nearest:
			nearest = absf(diff)
			turn = -1.0 if diff >= 0.0 else 1.0
	return turn


"""
True if holding the beam on angle for hold_time would push a nearby Shade (in the cone) onto the reef,
with CAREFUL_SHADE_SAFETY seconds to spare. Far-out Shades can take a short burst of light.
"""
static func _shade_would_wreck(entities: Array, angle: float, hold_time: float, tuning: NightbeamTuning) -> bool:
	var max_offset: float = tuning.beam_half_width + CAREFUL_SHADE_MARGIN
	for e: Dictionary in entities:
		if e["kind"] != "shade" or e.get("fading", false) or float(e["radius"]) > tuning.beam_range:
			continue
		if absf(NightbeamSim.angle_diff(float(e["angle"]), angle)) > max_offset:
			continue
		var light_budget: float = (float(e["radius"]) - tuning.reef_radius) / maxf(tuning.shade_speed_lit, MIN_SPEED)
		if light_budget < hold_time + CAREFUL_SHADE_SAFETY:
			return true
	return false


"""Turns toward target along the way whose sweep lights no Shade; the shorter way if both (or neither) do."""
static func _safe_turn(entities: Array, beam: float, target_angle: float, tuning: NightbeamTuning) -> float:
	var diff: float = NightbeamSim.angle_diff(target_angle, beam)
	var dist: float = absf(diff)
	if dist <= tuning.beam_half_width:
		return turn_toward(beam, target_angle, tuning)
	var short_dir: float = signf(diff)
	var short_blocked: bool = _sweep_hits_shade(entities, beam, short_dir, dist, tuning)
	if short_blocked and not _sweep_hits_shade(entities, beam, -short_dir, TAU - dist, tuning):
		return -short_dir
	return turn_toward(beam, target_angle, tuning)


"""True if sweeping the beam span radians in direction dir (+1/-1) would light a Shade that is too close to take it."""
static func _sweep_hits_shade(entities: Array, beam: float, dir: float, span: float, tuning: NightbeamTuning) -> bool:
	for e: Dictionary in entities:
		if e["kind"] != "shade" or e.get("fading", false) or float(e["radius"]) > tuning.beam_range:
			continue
		# Angle of the shade ahead of the beam, measured in the sweep direction.
		var offset: float = NightbeamSim.wrap_angle((float(e["angle"]) - beam) * dir)
		if offset > span + tuning.beam_half_width:
			continue
		# A quick pass lights a shade for about one cone width of turning; far-out shades can take that.
		var pass_time: float = 2.0 * tuning.beam_half_width / tuning.beam_turn_speed
		var light_budget: float = (float(e["radius"]) - tuning.reef_radius) / maxf(tuning.shade_speed_lit, MIN_SPEED)
		if light_budget < pass_time + CAREFUL_SHADE_SAFETY:
			return true
	return false


static func _careful_wants_flare(obs: Dictionary, tuning: NightbeamTuning) -> bool:
	if not _flare_ready(obs):
		return false
	var urgent: int = 0
	for e: Dictionary in obs["entities"]:
		if e["kind"] == "ship":
			if not e["saved"] and time_to_reef(e, tuning) < CAREFUL_FLARE_ETA:
				urgent += 1
		elif e["lit"] and float(e["radius"]) <= tuning.flare_radius:
			return true
	return urgent >= CAREFUL_FLARE_SHIPS


static func _flare_ready(obs: Dictionary) -> bool:
	return int(obs["flare_charges"]) > 0 and float(obs["flare_cd"]) <= 0.0
