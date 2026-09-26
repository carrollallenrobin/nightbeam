"""
Pure, seeded NIGHTBEAM simulation. Stepped at a fixed rate (tuning.sim_hz, 60 Hz) by whoever owns it
(GameFlow, BotRunner, PlaytestTarget). Owns ALL gameplay state and rules; see GDD section 3 for the rules
and the required tick order, and TDD "Public API" for the frozen signatures and observation schema.

Forbidden here: Node/SceneTree calls, Input, Time/OS clocks, global randf()/randi(), await, signals.
Owner: ticket A (sim core, GJ-4).
"""
class_name NightbeamSim extends RefCounted

enum State { RUNNING, WON, LOST }
enum Kind { SHIP, SHADE }

const DEFAULT_TUNING_PATH: String = "res://Data/Tuning/NightbeamTuning.tres"
const ACTION_TURN: String = "turn"
const ACTION_FLARE: String = "flare"
const KIND_NAMES: PackedStringArray = ["ship", "shade"]
const STATE_NAMES: PackedStringArray = ["running", "won", "lost"]

const EVENT_SPAWN: String = "spawn"
const EVENT_SAVED: String = "saved"
const EVENT_WRECK: String = "wreck"
const EVENT_SHADE_FADE: String = "shade_fade"
const EVENT_SHADE_FLARED: String = "shade_flared"
const EVENT_FLARE: String = "flare"
const EVENT_WON: String = "won"
const EVENT_LOST: String = "lost"
## Floats are rounded to this many steps per unit before hashing (TDD risk table: 1e-4).
const HASH_SCALE: float = 10000.0
## Slack for threshold tests on accumulated floats (60 x 1/60 can land a hair under 1.0).
const THRESHOLD_EPS: float = 0.000000001

var _tuning: NightbeamTuning = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _seed: int = 0
var _tick: int = 0
var _state: State = State.RUNNING
var _beam_angle: float = 0.0
var _hull: int = 0
var _saved: int = 0
var _score: int = 0
var _flare_charges: int = 0
var _flare_cd: float = 0.0
var _flares_used: int = 0
var _next_id: int = 0
var _next_spawn_time: float = 0.0
var _last_spawn_angle: float = 0.0
var _has_spawned: bool = false
## True until the Lone Shade (first spawn at t >= lone_shade_time) has actually spawned.
var _lone_shade_pending: bool = true
## Spawns dropped because no nudged angle satisfied the Shade lane rule.
var _spawns_skipped: int = 0
## Live entities, ascending id. Each: {id, kind: Kind, angle, radius, speed, drift, path_end, guidance, saved,
## lit, fading, age}. path_end = reef angle of the spawn spiral (lane rule; equals angle for Shades).
var _entities: Array[Dictionary] = []
## Events produced by the last step() (see TDD observation schema).
var _events: Array[Dictionary] = []


"""Creates a fresh night. All randomness comes from p_seed; p_tuning is read-only for the sim."""
func _init(p_seed: int, p_tuning: NightbeamTuning) -> void:
	_seed = p_seed
	_tuning = p_tuning
	_rng.seed = p_seed
	_hull = p_tuning.hull_max
	_flare_charges = p_tuning.flare_start_charges
	_next_spawn_time = p_tuning.first_spawn_delay


"""Advances exactly one fixed tick (tuning.dt()) in the GDD tick order. No-op once is_over()."""
func step(action: Dictionary) -> void:
	_events.clear()
	if is_over():
		return
	var dt: float = _tuning.dt()
	var time: float = _tick * dt
	# 1) read action (missing keys = 0 / false; NaN turn = 0)
	var turn: float = float(action.get(ACTION_TURN, 0.0))
	if is_nan(turn):
		turn = 0.0
	turn = clampf(turn, -1.0, 1.0)
	var want_flare: bool = bool(action.get(ACTION_FLARE, false))
	# 2) flare
	_flare_cd = maxf(_flare_cd - dt, 0.0)
	if want_flare and _flare_charges > 0 and _flare_cd <= 0.0:
		_fire_flare()
	# 3) turn beam
	_beam_angle = wrap_angle(_beam_angle + turn * _tuning.beam_turn_speed * dt)
	# 4) fading + lit flags, once per tick, before movement
	_update_lit_flags()
	# 5) movement in ascending id order
	_move_entities(dt)
	# 6) guidance and saves
	_update_guidance(dt)
	# 7) wrecks, shade lifetimes, despawns
	_resolve_removals()
	# 8) spawns
	_update_spawns(time)
	# 9) time, lose/win (lose first: a wreck on the final tick still loses)
	_tick += 1
	if _hull <= 0:
		_state = State.LOST
		_push_global_event(EVENT_LOST)
	elif _tick >= _tuning.dawn_tick():
		_state = State.WON
		_score += _hull * _tuning.score_per_hull
		_dissolve_shades_at_dawn()
		_push_global_event(EVENT_WON)


"""Read-only snapshot of the current state (TDD schema). A new Dictionary every call; callers may keep it."""
func get_observation() -> Dictionary:
	var entity_list: Array[Dictionary] = []
	for e: Dictionary in _entities:
		entity_list.append({
			"id": e["id"], "kind": KIND_NAMES[e["kind"]], "angle": e["angle"], "radius": e["radius"],
			"speed": e["speed"], "guidance": e["guidance"], "saved": e["saved"], "lit": e["lit"], "age": e["age"],
			"fading": e["fading"],
		})
	return {
		"tick": _tick,
		"time": _tick * _tuning.dt(),
		"beam_angle": _beam_angle,
		"hull": _hull,
		"saved": _saved,
		"score": _score,
		"flare_charges": _flare_charges,
		"flare_cd": _flare_cd,
		"flares_used": _flares_used,
		"spawns_skipped": _spawns_skipped,
		"state": state_name(_state),
		"entities": entity_list,
		"events": _events.duplicate(true),
	}


"""Deterministic hash of the full sim state incl. RNG state. Same seed + same actions => same hash."""
func state_hash() -> int:
	var parts: Array = [
		_seed, _tick, _state, _rng.state, _hull, _saved, _score, _flare_charges, _flares_used,
		_next_id, _has_spawned, _lone_shade_pending, _spawns_skipped, _q(_beam_angle), _q(_flare_cd), _q(_next_spawn_time), _q(_last_spawn_angle),
	]
	for e: Dictionary in _entities:
		parts.append_array([
			e["id"], e["kind"], e["saved"], e["lit"], e["fading"], _q(e["angle"]), _q(e["radius"]), _q(e["speed"]),
			_q(e["drift"]), _q(e["path_end"]), _q(e["guidance"]), _q(e["age"]),
		])
	return hash(parts)


"""True once the night is WON or LOST."""
func is_over() -> bool:
	return _state != State.RUNNING


"""Current State (RUNNING while the night is on)."""
func result() -> State:
	return _state


"""The seed this sim was created with."""
func get_seed() -> int:
	return _seed


"""Ticks stepped so far (time == tick * dt)."""
func get_tick() -> int:
	return _tick


"""Signed shortest angular difference a - b, in (-PI, PI]."""
static func angle_diff(a: float, b: float) -> float:
	var d: float = fposmod(a - b, TAU)
	return d - TAU if d > PI else d


"""Wraps an angle into [0, TAU)."""
static func wrap_angle(a: float) -> float:
	var w: float = fposmod(a, TAU)
	# fposmod can return TAU itself for tiny negative inputs due to rounding.
	return 0.0 if w >= TAU else w


"""
Shortest angle from x to the arc that runs from a0 to a1 the short way (0 if x is on the arc).
Used by the Shade lane rule.
"""
static func angle_to_arc(x: float, a0: float, a1: float) -> float:
	var span: float = angle_diff(a1, a0)
	var t: float = angle_diff(x, a0)
	if (span >= 0.0 and t >= 0.0 and t <= span) or (span < 0.0 and t <= 0.0 and t >= span):
		return 0.0
	return minf(absf(t), absf(angle_diff(x, a1)))


"""String name for a State: "running" | "won" | "lost" (used in observations and CSVs)."""
static func state_name(s: State) -> String:
	return STATE_NAMES[s]


# --- tick phases -------------------------------------------------------------------------------

func _fire_flare() -> void:
	_flare_charges -= 1
	_flares_used += 1
	_flare_cd = _tuning.flare_cooldown
	_push_global_event(EVENT_FLARE, _tuning.flare_radius)
	var kept: Array[Dictionary] = []
	for e: Dictionary in _entities:
		if e["kind"] == Kind.SHADE:
			if e["radius"] <= _tuning.flare_radius:
				_push_entity_event(EVENT_SHADE_FLARED, e)
				continue
		elif not e["saved"]:
			# Left unclamped on purpose: step 6 saves any ship at >= 1 before dark decay can undo the flare.
			e["guidance"] = e["guidance"] + _tuning.flare_guide
		kept.append(e)
	_entities = kept


func _update_lit_flags() -> void:
	var fade_age: float = _tuning.shade_fade_age()
	for e: Dictionary in _entities:
		# Fading is fixed here for the whole tick, so a Shade is never both fading and lit in one observation.
		e["fading"] = e["kind"] == Kind.SHADE and e["age"] >= fade_age - THRESHOLD_EPS
		e["lit"] = not e["fading"] and e["radius"] <= _tuning.beam_range \
			and absf(angle_diff(e["angle"], _beam_angle)) <= _tuning.beam_half_width


func _move_entities(dt: float) -> void:
	for e: Dictionary in _entities:
		e["age"] = e["age"] + dt
		if e["kind"] == Kind.SHADE:
			_move_shade(e, dt)
		elif e["saved"]:
			e["radius"] = e["radius"] + _tuning.saved_speed * dt
		else:
			# Spiral approach: heading re-aimed every tick, so radius strictly decreases (GDD "Ship approach").
			var old_radius: float = e["radius"]
			var speed: float = e["speed"]
			var drift: float = e["drift"]
			e["radius"] = old_radius - speed * cos(drift) * dt
			e["angle"] = wrap_angle(e["angle"] + speed * sin(drift) * dt / old_radius)


"""Shade drift (GJ-11): lit -> lunge inward; dark -> drift only down to the hold radius; fading -> still."""
func _move_shade(e: Dictionary, dt: float) -> void:
	var old_radius: float = e["radius"]
	var new_radius: float = old_radius
	if e["fading"]:
		new_radius = old_radius
	elif e["lit"]:
		new_radius = old_radius - _tuning.shade_speed_lit * dt
	elif old_radius > _tuning.shade_hold_radius:
		new_radius = maxf(old_radius - _tuning.shade_speed_dark * dt, _tuning.shade_hold_radius)
	e["radius"] = new_radius
	# Observed speed is the actual inward speed this tick (0 while holding or fading).
	e["speed"] = (old_radius - new_radius) / dt


func _update_guidance(dt: float) -> void:
	for e: Dictionary in _entities:
		if e["kind"] != Kind.SHIP or e["saved"] or e["radius"] <= _tuning.reef_radius:
			continue
		var guidance: float = e["guidance"]
		if guidance < 1.0 - THRESHOLD_EPS:
			if e["lit"]:
				guidance += dt / _tuning.guide_time
			else:
				guidance = maxf(guidance - _tuning.guide_decay * dt, 0.0)
		if guidance >= 1.0 - THRESHOLD_EPS:
			guidance = 1.0
			_save_ship(e)
		e["guidance"] = guidance


func _save_ship(e: Dictionary) -> void:
	e["saved"] = true
	e["speed"] = _tuning.saved_speed
	_saved += 1
	_score += _tuning.score_per_save
	if _tuning.flare_saves_per_charge > 0 and _saved % _tuning.flare_saves_per_charge == 0:
		_flare_charges = mini(_flare_charges + 1, _tuning.flare_max_charges)
	_push_entity_event(EVENT_SAVED, e)


func _resolve_removals() -> void:
	var kept: Array[Dictionary] = []
	var despawn_radius: float = _tuning.despawn_radius()
	for e: Dictionary in _entities:
		if e["radius"] <= _tuning.reef_radius:
			_hull = maxi(_hull - 1, 0)
			_push_entity_event(EVENT_WRECK, e)
			continue
		if e["kind"] == Kind.SHADE and e["age"] >= _tuning.shade_lifetime - THRESHOLD_EPS:
			_push_entity_event(EVENT_SHADE_FADE, e)
			continue
		if e["saved"] and e["radius"] > despawn_radius:
			continue
		kept.append(e)
	_entities = kept


"""GDD Win: all Shades dissolve at dawn. Each leaves with a normal shade_fade event (GJ-15)."""
func _dissolve_shades_at_dawn() -> void:
	var kept: Array[Dictionary] = []
	for e: Dictionary in _entities:
		if e["kind"] == Kind.SHADE:
			_push_entity_event(EVENT_SHADE_FADE, e)
		else:
			kept.append(e)
	_entities = kept


func _update_spawns(time: float) -> void:
	if time + THRESHOLD_EPS < _next_spawn_time:
		return
	# Schedule first, with no jitter: a skipped spawn (cap or lanes) still advances the clock.
	_next_spawn_time += _tuning.spawn_interval(time)
	# Always draw the same RNG values in the same order, so the stream never depends on skips or the Lone Shade.
	var angle: float = _rng.randf() * TAU
	var drift: float = _rng.randf_range(-_tuning.ship_heading_jitter, _tuning.ship_heading_jitter)
	var kind_roll: float = _rng.randf()
	if _entities.size() >= _tuning.max_entities:
		return
	var kind: Kind = Kind.SHADE if kind_roll < _tuning.shade_chance(time) else Kind.SHIP
	var lone_due: bool = _lone_shade_pending and time + THRESHOLD_EPS >= _tuning.lone_shade_time
	if lone_due:
		kind = Kind.SHADE
	if _has_spawned and absf(angle_diff(angle, _last_spawn_angle)) < _tuning.min_spawn_separation:
		angle = wrap_angle(angle + PI * 0.5)
	if kind == Kind.SHADE:
		drift = 0.0
	var sweep: float = _tuning.ship_path_sweep(drift)
	var lane_angle: float = _find_lane_angle(kind, angle, sweep)
	if is_nan(lane_angle):
		# A skipped Lone Shade stays pending, so the next spawn tries it again.
		_spawns_skipped += 1
		return
	if lone_due:
		_lone_shade_pending = false
	var speed: float = _tuning.shade_speed_dark if kind == Kind.SHADE else _tuning.ship_speed(time)
	var e: Dictionary = {
		"id": _next_id, "kind": kind, "angle": lane_angle, "radius": _tuning.spawn_radius, "speed": speed,
		"drift": drift, "path_end": wrap_angle(lane_angle + sweep), "guidance": 0.0, "saved": false,
		"lit": false, "fading": false, "age": 0.0,
	}
	_next_id += 1
	_last_spawn_angle = lane_angle
	_has_spawned = true
	_entities.append(e)
	_push_entity_event(EVENT_SPAWN, e)


"""
Shade lane rule (GJ-11): the first of angle + k * spawn_retry_step (k = 0..n, one full turn) that keeps
shade_gap between every unsaved ship's remaining path arc and every non-fading Shade. NAN if none works.
"""
func _find_lane_angle(kind: Kind, angle: float, sweep: float) -> float:
	for k: int in _tuning.spawn_retry_count() + 1:
		var candidate: float = wrap_angle(angle + k * _tuning.spawn_retry_step)
		if _lane_is_clear(kind, candidate, sweep):
			return candidate
	return NAN


func _lane_is_clear(kind: Kind, candidate: float, sweep: float) -> bool:
	var gap: float = _tuning.shade_gap
	for e: Dictionary in _entities:
		if kind == Kind.SHADE:
			# Remaining arc: ships only move from their current angle towards path_end.
			if e["kind"] == Kind.SHIP and not e["saved"] \
					and angle_to_arc(candidate, e["angle"], e["path_end"]) < gap:
				return false
		elif e["kind"] == Kind.SHADE and not e["fading"] \
				and angle_to_arc(e["angle"], candidate, candidate + sweep) < gap:
			return false
	return true


func _push_entity_event(type: String, e: Dictionary) -> void:
	_events.append({"type": type, "id": e["id"], "kind": KIND_NAMES[e["kind"]], "angle": e["angle"],
		"radius": e["radius"], "lit": e["lit"]})


func _push_global_event(type: String, radius: float = 0.0) -> void:
	_events.append({"type": type, "id": -1, "kind": "", "angle": _beam_angle, "radius": radius, "lit": false})


func _q(value: float) -> int:
	return int(roundf(value * HASH_SCALE))
