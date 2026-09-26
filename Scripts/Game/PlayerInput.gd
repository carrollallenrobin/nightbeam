"""
Turns the player's input into the same action Dictionary the bots send to NightbeamSim.step(),
so humans and bots have identical control authority. Keys in M1; mouse (beam follows cursor) in M2.
Owner: ticket B (view + flow).
"""
class_name PlayerInput extends RefCounted

const ACTION_TURN_LEFT: StringName = &"turn_left"
const ACTION_TURN_RIGHT: StringName = &"turn_right"
const ACTION_FLARE: StringName = &"flare"


"""Maps the current keyboard state (and in M2 the mouse vs. obs.beam_angle) to a sim action Dictionary."""
static func read_action(_obs: Dictionary, _tuning: NightbeamTuning) -> Dictionary:
	var turn: float = Input.get_axis(ACTION_TURN_LEFT, ACTION_TURN_RIGHT)
	return {NightbeamSim.ACTION_TURN: turn, NightbeamSim.ACTION_FLARE: Input.is_action_pressed(ACTION_FLARE)}
