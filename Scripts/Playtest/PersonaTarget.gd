"""
Playtest Lab persona target (group "playtest_target") for PersonaHarness.tscn (GJ-10, M2 cues GJ-14, Drowned cues GJ-19). The scene instances the
real Main.tscn, so personas see and play exactly what a human does: title card first, then the night.
Input goes through Godot's input system (Input.parse_input_event), the same path as a keyboard/gamepad:
  {"turn": -1..1}      held for the whole bridge window (released when missing or 0)
  {"flare": true}      one press of Space (the flare key; also starts the night on the title card)
  {"key": "space"|"r"|"n"|"esc"}   one press of that key
observe() is human-fidelity (see PersonaPerception): no hidden state, no exact values beyond the HUD.
Sessions end through `play done` / `play quit`, so is_done() stays false.
"""
class_name PersonaTarget extends Node

const TARGET_GROUP: StringName = &"playtest_target"
const TUNING: NightbeamTuning = preload("res://Data/Tuning/NightbeamTuning.tres")
const ACTION_TURN_LEFT: StringName = &"turn_left"
const ACTION_TURN_RIGHT: StringName = &"turn_right"
const KEY_FIELD: String = "key"
## Named keys a persona may press once, mapped to the physical keys in project.godot's input map.
const KEYS: Dictionary = {"space": KEY_SPACE, "r": KEY_R, "n": KEY_N, "esc": KEY_ESCAPE, "escape": KEY_ESCAPE}
const SCREEN_NAMES: PackedStringArray = ["title", "night", "paused", "end"]
## Run after GameFlow's _physics_process so this tick's sim events are already there.
const PHYSICS_PRIORITY_AFTER_GAME: int = 10
## Seconds a wrecked boat's wisp is still on screen. StoryFx.WISP_LIFE is 4.5 s, but the wisp accelerates and
## leaves the 960x540 view after roughly half that (checked on GJ-19 screenshots), so perception stops at 2 s.
const WISP_VISIBLE_TIME: float = 2.0
## Guard against a runaway event list when a persona waits a very long time.
const MAX_EVENT_PHRASES: int = 12

@onready var _main: GameFlow = $Main
@onready var _hud: HudView = $Main/Hud/HudView

var _turn: float = 0.0
## Key events pressed at the start of the current window, released after one frame.
var _pending_release: Array[InputEventKey] = []
var _frames_since_press: int = 0
## Noticeable events since the last observe(): phrase -> times seen (insertion ordered).
var _event_counts: Dictionary = {}
var _last_sim: NightbeamSim = null
var _last_tick: int = -1
## Shade currently in the first-lunge slow motion (-1 = none); set from GameFlow.lunge_beat_started.
var _beat_id: int = -1
## Seconds a view-only effect stays on screen after its event: a wrecked boat's wisp, dawn ghosts sinking,
## dawn lamps blinking together.
var _wisp_left: float = 0.0
var _dawn_ghosts_left: float = 0.0
var _dawn_lamps_left: float = 0.0
var _input_note: String = ""


func _ready() -> void:
	add_to_group(TARGET_GROUP)
	process_physics_priority = PHYSICS_PRIORITY_AFTER_GAME
	_main.lunge_beat_started.connect(_on_lunge_beat_started)


func _physics_process(_delta: float) -> void:
	_collect_events()


func _process(delta: float) -> void:
	# View effects age in real time (NightbeamView/StoryFx use _process delta too).
	_wisp_left = maxf(_wisp_left - delta, 0.0)
	_dawn_ghosts_left = maxf(_dawn_ghosts_left - delta, 0.0)
	_dawn_lamps_left = maxf(_dawn_lamps_left - delta, 0.0)
	# One-shot presses were flushed at the start of this frame and read by this frame's physics tick.
	if _pending_release.is_empty():
		return
	_frames_since_press += 1
	if _frames_since_press >= 1:
		for ev: InputEventKey in _pending_release:
			_send_key(ev.physical_keycode, false)
		_pending_release.clear()


"""Fresh game on the title card (onboarding is part of the test) for night_seed; releases all held input."""
func reset_game(night_seed: int) -> void:
	_set_turn(0.0)
	for ev: InputEventKey in _pending_release:
		_send_key(ev.physical_keycode, false)
	_pending_release.clear()
	_main.show_title(night_seed)
	_event_counts = {}
	_beat_id = -1
	_wisp_left = 0.0
	_dawn_ghosts_left = 0.0
	_dawn_lamps_left = 0.0
	_last_sim = _main.sim
	_last_tick = _main.sim.get_tick()
	_input_note = ""


"""Applies a persona input for the coming window (see class docstring)."""
func apply_action(action: Dictionary) -> void:
	_input_note = ""
	_set_turn(clampf(float(action.get(NightbeamSim.ACTION_TURN, 0.0)), -1.0, 1.0))
	var presses: PackedStringArray = []
	if bool(action.get(NightbeamSim.ACTION_FLARE, false)):
		presses.append("space")
	if action.has(KEY_FIELD):
		var key: String = str(action[KEY_FIELD]).to_lower()
		if KEYS.has(key):
			presses.append(key)
		else:
			_input_note = "nothing happens: the game only uses A/D or arrow keys (turn), space, r, n, esc"
	for key: String in presses:
		var code: Key = KEYS[key]
		_send_key(code, true)
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = code
		_pending_release.append(ev)
	_frames_since_press = 0


"""What a human would see and could say right now (screen, text as drawn, vague scene, noticed events)."""
func observe() -> Dictionary:
	var screen: String = SCREEN_NAMES[_main.flow_state]
	var obs: Dictionary = _main.sim.get_observation()
	if not _main.is_slow_motion():
		_beat_id = -1
	var out: Dictionary = {
		"screen": screen,
		"text": PersonaPerception.hud_text(_hud),
		"scene": PersonaPerception.describe_scene(obs, TUNING, screen, _beat_id,
				{"wisp": _wisp_left > 0.0, "dawn_ghosts": _dawn_ghosts_left > 0.0, "dawn_lamps": _dawn_lamps_left > 0.0}),
	}
	var events: Array[String] = PersonaPerception.summarize_events(_event_counts)
	if not events.is_empty():
		out["since_last_look"] = events
	if not _input_note.is_empty():
		out["input"] = _input_note
	_event_counts = {}
	return out


"""Persona sessions never end on their own; the persona stops with `play done` / `play quit`."""
func is_done() -> bool:
	return false


"""Ready once Main has a sim."""
func is_ready() -> bool:
	return _main != null and _main.sim != null


"""Minimal: personas are judged on their notes, not on numbers."""
func metrics() -> Dictionary:
	return {"screen": _main.flow_state}


func _collect_events() -> void:
	var sim: NightbeamSim = _main.sim
	if sim == null:
		return
	if sim != _last_sim:
		_last_sim = sim
		_last_tick = -1
	var tick: int = sim.get_tick()
	if tick == _last_tick:
		return
	_last_tick = tick
	var obs: Dictionary = sim.get_observation()
	var events: Array = obs.get("events", [])
	var any_boats: bool = false
	for e: Dictionary in obs.get("entities", []):
		if String(e.get("kind", "")) == PersonaPerception.KIND_SHIP:
			any_boats = true
			break
	var won: bool = false
	var ghosts_sank: bool = false
	for event: Dictionary in events:
		match String(event.get("type", "")):
			"wreck":
				if String(event.get("kind", "")) != PersonaPerception.KIND_SHADE:
					_wisp_left = WISP_VISIBLE_TIME
			"won":
				won = true
			"shade_fade":
				ghosts_sank = true
	# At dawn the view sinks every ghost removed that tick and blinks the lamps of the boats still drawn.
	if won:
		if ghosts_sank:
			_dawn_ghosts_left = StoryFx.DAWN_SINK_TIME
		if any_boats:
			_dawn_lamps_left = StoryFx.DAWN_BLINK_TIME
	for phrase: String in PersonaPerception.tick_phrases(events, any_boats):
		_note_event(phrase)


func _note_event(phrase: String) -> void:
	if phrase.is_empty():
		return
	if not _event_counts.has(phrase) and _event_counts.size() >= MAX_EVENT_PHRASES:
		return
	_event_counts[phrase] = int(_event_counts.get(phrase, 0)) + 1


func _on_lunge_beat_started(entity_id: int) -> void:
	_beat_id = entity_id
	_note_event(PersonaPerception.lunge_beat_phrase())


func _set_turn(turn: float) -> void:
	if is_equal_approx(turn, _turn):
		return
	_turn = turn
	_send_action(ACTION_TURN_LEFT, maxf(-turn, 0.0))
	_send_action(ACTION_TURN_RIGHT, maxf(turn, 0.0))


func _send_action(action: StringName, strength: float) -> void:
	var ev: InputEventAction = InputEventAction.new()
	ev.action = action
	ev.pressed = strength > 0.0
	ev.strength = strength
	Input.parse_input_event(ev)


func _send_key(code: Key, pressed: bool) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
