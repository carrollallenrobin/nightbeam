"""
Playtest Lab bridge target (group "playtest_target") for PlaytestHarness.tscn. Owns its own NightbeamSim,
steps it exactly once per _physics_process, and accepts raw actions {"turn", "flare"} or
{"policy": "<skill>"} (engine-side NightbeamBots, asked every tick). See TDD "Playtest Lab plan".
Owner: ticket C (GJ-6).

Frame/tick contract: the bridge unpauses the tree for n frames per "step"; with --fixed-fps 60 and
physics_ticks_per_second=60 each frame runs exactly one _physics_process, so n frames == n sim ticks.
The target verifies this itself (invariant "bridge-frame-tick") instead of trusting it.
"""
class_name PlaytestTarget extends Node

const TARGET_GROUP: StringName = &"playtest_target"
const TUNING: NightbeamTuning = preload("res://Data/Tuning/NightbeamTuning.tres")
## Action key that selects an engine-side bot skill instead of a raw action.
const ACTION_POLICY: String = "policy"
const INVARIANT_FRAME_TICK: String = "bridge-frame-tick"
const INVARIANT_TERMINAL: String = "terminal-final"
const INVARIANT_UNKNOWN_POLICY: String = "unknown-policy"
const SEVERITY_BRIDGE: String = "P1"
const SEVERITY_TERMINAL: String = "P0"
## Stop collecting violations past this many per window (one broken rule already stops the lab run).
const MAX_VIOLATIONS: int = 20

var _sim: NightbeamSim = null
## Raw action in effect, used when _policy is empty.
var _action: Dictionary = {}
## Engine-side bot skill in effect ("" = use _action).
var _policy: String = ""
## Per-run scratch space for NightbeamBots, cleared on reset.
var _memo: Dictionary = {}
## Latest observation (events included), refreshed every tick; the previous one for transition checks.
var _obs: Dictionary = {}
var _prev_obs: Dictionary = {}
## False from reset until the first apply_action: the bridge's reset reply frame must not advance the sim.
var _armed: bool = false
## Frames (_process) and physics ticks (_physics_process) seen while armed; must stay equal.
var _frames: int = 0
var _ticks: int = 0
## state_hash() captured on the first tick the night was over (valid once _has_final_hash).
var _final_hash: int = 0
var _has_final_hash: bool = false
## Violations found since the last check_invariants() call.
var _violations: Array = []


func _ready() -> void:
	add_to_group(TARGET_GROUP)
	reset_game(1)


func _physics_process(_delta: float) -> void:
	if not _armed or _sim == null:
		return
	_ticks += 1
	# step() is a no-op once the night is over; calling it anyway lets terminal-final prove that.
	_sim.step(_current_action())
	_prev_obs = _obs
	_obs = _sim.get_observation()
	_check_tick()


func _process(_delta: float) -> void:
	if _armed:
		_frames += 1


"""Starts a fresh night; all randomness comes from night_seed. The sim does not advance until apply_action."""
func reset_game(night_seed: int) -> void:
	_sim = NightbeamSim.new(night_seed, TUNING)
	_action = NightbeamBots.idle_action()
	_policy = ""
	_memo = {}
	_obs = _sim.get_observation()
	_prev_obs = {}
	_armed = false
	_frames = 0
	_ticks = 0
	_final_hash = 0
	_has_final_hash = false
	_violations = NightbeamInvariants.check({}, _obs, TUNING)


"""
Sets the action for the following ticks: a raw sim action {"turn": float, "flare": bool}, or
{"policy": "idle" | "greedy" | "careful"} to let NightbeamBots decide on every tick.
"""
func apply_action(action: Dictionary) -> void:
	_armed = true
	if action.has(ACTION_POLICY):
		_policy = str(action[ACTION_POLICY])
		if not NightbeamBots.SKILLS.has(_policy):
			_add_violation(INVARIANT_UNKNOWN_POLICY, "unknown bot policy '%s'" % _policy, SEVERITY_BRIDGE)
		return
	_policy = ""
	_action = {
		NightbeamSim.ACTION_TURN: float(action.get(NightbeamSim.ACTION_TURN, 0.0)),
		NightbeamSim.ACTION_FLARE: bool(action.get(NightbeamSim.ACTION_FLARE, false)),
	}


"""What a player could know: the sim observation without per-tick events."""
func observe() -> Dictionary:
	var obs: Dictionary = _obs.duplicate()
	obs.erase("events")
	return obs


"""True once the night is won or lost."""
func is_done() -> bool:
	return _sim.is_over()


"""Ready as soon as a sim exists: the harness has no loading."""
func is_ready() -> bool:
	return _sim != null


"""
Violations found on every tick since the last call ([] when fine), in the bridge format
{"id", "message", "severity"}: NightbeamInvariants per tick, terminal-final via state_hash, and
bridge-frame-tick (frames stepped != sim ticks). Clears the list.
"""
func check_invariants() -> Array:
	var out: Array = _violations
	_violations = []
	return out


"""Flat numbers aggregated by the lab (TDD metrics list)."""
func metrics() -> Dictionary:
	var result: NightbeamSim.State = _sim.result()
	return {
		"time_survived": float(_obs["time"]),
		"saved": int(_obs["saved"]),
		"hull": int(_obs["hull"]),
		"score": int(_obs["score"]),
		"flares_used": int(_obs["flares_used"]),
		"won": 1 if result == NightbeamSim.State.WON else 0,
		"lost": 1 if result == NightbeamSim.State.LOST else 0,
	}


func _current_action() -> Dictionary:
	if _policy.is_empty():
		return _action
	return NightbeamBots.act(_policy, _obs, TUNING, _memo)


func _check_tick() -> void:
	for v: Dictionary in NightbeamInvariants.check(_prev_obs, _obs, TUNING):
		_add_violation(v["id"], v["message"], v["severity"])
	# _process for this frame has not run yet, so ticks lead frames by exactly one here.
	if _ticks != _frames + 1:
		_add_violation(INVARIANT_FRAME_TICK, "physics tick %d in frame %d (expected one tick per frame)" % [_ticks, _frames + 1], SEVERITY_BRIDGE)
	if not _sim.is_over() and _sim.get_tick() != _ticks:
		_add_violation(INVARIANT_FRAME_TICK, "sim tick %d != physics ticks %d" % [_sim.get_tick(), _ticks], SEVERITY_BRIDGE)
	if _sim.is_over():
		var h: int = _sim.state_hash()
		if not _has_final_hash:
			_final_hash = h
			_has_final_hash = true
		elif h != _final_hash:
			_add_violation(INVARIANT_TERMINAL, "state_hash changed after the end (%d -> %d)" % [_final_hash, h], SEVERITY_TERMINAL)


func _add_violation(id: String, message: String, severity: String) -> void:
	if _violations.size() < MAX_VIOLATIONS:
		_violations.append({"id": id, "message": message, "severity": severity})
