"""
Root of Main.tscn: owns the NightbeamSim instance, steps it at 60 Hz from player input, hands each
observation to the view and HUD, and runs the TITLE -> NIGHT <-> PAUSED -> END flow (TDD "Frame / tick flow").
Gameplay rules live only in the sim; this script decides *when* the sim steps, never *what* happens.
It also runs the GJ-11 first-lunge beat: the first time in an app session that a Shade is lit, the sim is
stepped at 0.3x for 0.6 s of real time (fewer step() calls; the ticks themselves are unchanged).
Owner: view + flow (GJ-5, GJ-13).

User args (after `--`): `--seed=N` fixes the night seed; `--autostart` skips the title card (smoke runs).
"""
class_name GameFlow extends Node

signal ship_saved(entity_id: int)
signal reef_hit(hull_left: int)
signal flare_fired(charges_left: int)
signal run_ended(result: int)
signal lunge_beat_started(entity_id: int)

enum FlowState { TITLE, NIGHT, PAUSED, END }

const TUNING: NightbeamTuning = preload("res://Data/Tuning/NightbeamTuning.tres")
const SEED_ARG_PREFIX: String = "--seed="
const AUTOSTART_ARG: String = "--autostart"
const ACTION_PAUSE: StringName = &"pause"
const ACTION_RETRY: StringName = &"retry"
const ACTION_NEW_NIGHT: StringName = &"new_night"
const ACTION_START: StringName = &"flare"
const EVENT_SAVED: String = "saved"
const EVENT_WRECK: String = "wreck"
const EVENT_FLARE: String = "flare"
const KIND_SHADE: String = "shade"
## Seeds stay in a positive 31-bit range so they are easy to read and type on the title/end cards.
const MAX_SEED: int = 0x7FFFFFFF
## First-lunge beat (GDD 6 "Teaching (GJ-11)").
const LUNGE_BEAT_TIME: float = 0.6
const LUNGE_TIME_SCALE: float = 0.3

## True once the first-lunge beat has played in this app session (static: survives retries/new nights).
static var lunge_beat_done: bool = false

var flow_state: FlowState = FlowState.TITLE
var sim: NightbeamSim = null
var night_seed: int = 0
## Optional action source (obs: Dictionary) -> Dictionary, used by tests/harnesses instead of the keyboard.
var action_provider: Callable = Callable()
## Hull lost this night, split by what hit the rock (end card, GJ-11).
var hull_lost_to_ships: int = 0
var hull_lost_to_shades: int = 0
var _last_obs: Dictionary = {}
var _prev_obs: Dictionary = {}
## The key that starts a night (Space) is also the flare key: ignore flare until it is released once,
## so starting a night never burns the first charge.
var _flare_armed: bool = false
var _flow_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _slowmo_left: float = 0.0
var _step_budget: float = 0.0

@onready var _view: NightbeamView = $NightbeamView
@onready var _hud: HudView = $Hud/HudView
@onready var _audio: SynthAudio = $SynthAudio


func _ready() -> void:
	_flow_rng.randomize()
	_view.configure(TUNING)
	_hud.configure(TUNING)
	_view.fx_played.connect(_on_view_fx_played)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	night_seed = _read_seed_arg(args)
	if args.has(AUTOSTART_ARG):
		start_night(night_seed)
	else:
		show_title(night_seed)


func _physics_process(delta: float) -> void:
	if flow_state != FlowState.NIGHT or sim == null:
		return
	if not _consume_step(delta):
		return
	sim.step(_read_action())
	_publish_observation()
	_count_and_emit_events(_last_obs)
	_check_first_lunge()
	if sim.is_over():
		_enter_end()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_PAUSE):
		_toggle_pause()
	elif event.is_action_pressed(ACTION_RETRY):
		if flow_state != FlowState.TITLE:
			start_night(night_seed)
	elif event.is_action_pressed(ACTION_NEW_NIGHT):
		if flow_state == FlowState.TITLE:
			show_title(_random_seed())
		else:
			start_night(_random_seed())
	elif event.is_action_pressed(ACTION_START):
		if flow_state == FlowState.TITLE:
			start_night(night_seed)
	else:
		return
	get_viewport().set_input_as_handled()


"""Shows the title card over an idle bay for the given seed. The sim is created but not stepped."""
func show_title(p_seed: int) -> void:
	_create_sim(p_seed)
	flow_state = FlowState.TITLE
	_hud.show_title(night_seed)


"""Starts (or restarts) a night with the given seed and shows its first observation."""
func start_night(p_seed: int) -> void:
	_create_sim(p_seed)
	_flare_armed = false
	flow_state = FlowState.NIGHT
	_hud.show_night()


"""True while the first-lunge slow motion is running."""
func is_slow_motion() -> bool:
	return _slowmo_left > 0.0


func _create_sim(p_seed: int) -> void:
	night_seed = p_seed
	sim = NightbeamSim.new(night_seed, TUNING)
	hull_lost_to_ships = 0
	hull_lost_to_shades = 0
	_slowmo_left = 0.0
	_step_budget = 0.0
	_view.reset_effects()
	_last_obs = {}
	_publish_observation()


func _enter_end() -> void:
	flow_state = FlowState.END
	_slowmo_left = 0.0
	_hud.show_end(_last_obs, night_seed, hull_lost_to_ships, hull_lost_to_shades)
	run_ended.emit(sim.result())


func _toggle_pause() -> void:
	if flow_state == FlowState.NIGHT:
		flow_state = FlowState.PAUSED
		_hud.show_paused(true)
	elif flow_state == FlowState.PAUSED:
		flow_state = FlowState.NIGHT
		_hud.show_paused(false)


# One sim step per physics tick, except during the first-lunge beat: then a step only every
# 1 / LUNGE_TIME_SCALE ticks. Only the step *rate* changes, so the sequence of ticks is identical.
func _consume_step(delta: float) -> bool:
	if _slowmo_left <= 0.0:
		return true
	_slowmo_left -= delta
	_step_budget += LUNGE_TIME_SCALE
	if _step_budget < 1.0:
		return false
	_step_budget -= 1.0
	return true


func _read_action() -> Dictionary:
	if action_provider.is_valid():
		return action_provider.call(_last_obs)
	return _read_player_action()


func _read_player_action() -> Dictionary:
	var action: Dictionary = PlayerInput.read_action(_last_obs, TUNING)
	var flare_held: bool = bool(action.get(NightbeamSim.ACTION_FLARE, false))
	if not _flare_armed:
		_flare_armed = not flare_held
		action[NightbeamSim.ACTION_FLARE] = false
	return action


func _publish_observation() -> void:
	_prev_obs = _last_obs
	_last_obs = sim.get_observation()
	_view.show_observation(_last_obs)
	_hud.show_observation(_last_obs)


# The first time in the app session that any Shade is lit, slow the sim down and stage the lunge.
func _check_first_lunge() -> void:
	if lunge_beat_done:
		return
	for entity: Dictionary in _last_obs.get("entities", []):
		if String(entity.get("kind", "")) == KIND_SHADE and bool(entity.get("lit", false)):
			lunge_beat_done = true
			_slowmo_left = LUNGE_BEAT_TIME
			_step_budget = 0.0
			var id: int = int(entity.get("id", -1))
			_view.start_lunge_beat(id, LUNGE_BEAT_TIME)
			lunge_beat_started.emit(id)
			return


# Turns this tick's sim events into GameFlow signals and tallies hull loss by cause for the end card.
func _count_and_emit_events(obs: Dictionary) -> void:
	for event: Dictionary in obs.get("events", []):
		match String(event.get("type", "")):
			EVENT_SAVED:
				ship_saved.emit(int(event.get("id", -1)))
			EVENT_WRECK:
				if NightbeamView.event_kind(event, _prev_obs) == KIND_SHADE:
					hull_lost_to_shades += 1
				else:
					hull_lost_to_ships += 1
				reef_hit.emit(int(obs.get("hull", 0)))
			EVENT_FLARE:
				flare_fired.emit(int(obs.get("flare_charges", 0)))


# View FX -> sound + HUD pip flash. Keeps audio and HUD decoupled from the view.
func _on_view_fx_played(fx_id: StringName, _event: Dictionary) -> void:
	match fx_id:
		NightbeamView.FX_SHADE_FADE_START:
			_audio.play(SynthAudio.FX_SIGH)
		NightbeamView.FX_SHADE_FLARED:
			_audio.play(SynthAudio.FX_POP)
		NightbeamView.FX_SHADE_SPLASH:
			_audio.play(SynthAudio.FX_GULP)
			_hud.flash_lost_hull(int(_last_obs.get("hull", 0)), true)
		NightbeamView.FX_SHIP_WRECK:
			_audio.play(SynthAudio.FX_FOGHORN)
			_hud.flash_lost_hull(int(_last_obs.get("hull", 0)), false)


# Seed from `-- --seed=N`; otherwise a random night. Randomness here is flow-side only, never in the sim.
func _read_seed_arg(args: PackedStringArray) -> int:
	for arg: String in args:
		if arg.begins_with(SEED_ARG_PREFIX):
			var value: String = arg.trim_prefix(SEED_ARG_PREFIX)
			if value.is_valid_int():
				return int(value)
			push_warning("Ignoring invalid seed argument: %s" % arg)
	return _random_seed()


func _random_seed() -> int:
	return _flow_rng.randi_range(1, MAX_SEED)
