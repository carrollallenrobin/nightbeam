"""
All NIGHTBEAM gameplay numbers (GDD section 4, "Tunables"). The sim reads them, never writes them.
Defaults match the GDD; the tuned values live in res://Data/Tuning/NightbeamTuning.tres.
Owner: ticket A (sim core, GJ-4). Ramp functions implement the GDD difficulty ramp.
"""
class_name NightbeamTuning extends Resource

@export_group("Night")
@export var dawn_time: float = 180.0
@export var hull_max: int = 5
@export var sim_hz: int = 60

@export_group("Beam")
@export var beam_turn_speed: float = 2.6
@export var beam_half_width: float = 0.26
@export var beam_range: float = 260.0

@export_group("Bay")
@export var spawn_radius: float = 250.0
@export var reef_radius: float = 48.0
@export var max_entities: int = 64
## Saved ships despawn past spawn_radius + despawn_margin (GDD "Saved ship": +10 px).
@export var despawn_margin: float = 10.0

@export_group("Ships")
@export var ship_heading_jitter: float = 0.25
@export var ship_speed_start: float = 22.0
@export var ship_speed_end: float = 40.0
@export var saved_speed: float = 55.0
@export var guide_time: float = 1.0
@export var guide_decay: float = 0.3

@export_group("Spawning")
@export var spawn_interval_start: float = 3.0
@export var spawn_interval_end: float = 1.1
@export var first_spawn_delay: float = 1.5
@export var min_spawn_separation: float = 0.35

@export_group("Shades")
## No Shades before this time, except the Lone Shade (GJ-11).
@export var shade_start_time: float = 20.0
## Shade chance at shade_start_time; lerps to shade_chance_end at dawn (GJ-11, folds in GJ-9).
@export var shade_chance_start: float = 0.2
@export var shade_chance_end: float = 0.35
@export var shade_speed_dark: float = 12.0
@export var shade_speed_lit: float = 70.0
@export var shade_lifetime: float = 14.0
## Dark Shades stop moving inward here, so only light can bring a Shade to the reef (GJ-11).
@export var shade_hold_radius: float = 120.0
## Last part of shade_lifetime in which a Shade is fading: never lit, never moving (GJ-11).
@export var shade_fade_time: float = 0.75
## The first spawn at or after this time is always a Shade: the Lone Shade (GJ-11).
@export var lone_shade_time: float = 7.0

@export_group("Shade lanes")
## Minimum angle between any unsaved ship's path arc and any non-fading Shade. Keep > 2 * beam_half_width.
@export var shade_gap: float = 0.60
## A spawn that breaks the lane rule is nudged by this step, up to one full turn, else skipped.
@export var spawn_retry_step: float = 0.35

@export_group("Flare")
@export var flare_start_charges: int = 1
@export var flare_max_charges: int = 2
@export var flare_saves_per_charge: int = 6
@export var flare_cooldown: float = 2.0
@export var flare_guide: float = 0.6
@export var flare_radius: float = 140.0

@export_group("Score")
@export var score_per_save: int = 10
@export var score_per_hull: int = 25


"""Fixed step length in seconds (1.0 / sim_hz)."""
func dt() -> float:
	return 1.0 / float(sim_hz)


"""Night progress p = clamp(t / dawn_time, 0, 1) used by every ramp."""
func night_progress(t: float) -> float:
	return clampf(t / dawn_time, 0.0, 1.0)


"""Spawn interval at sim time t (GDD difficulty ramp)."""
func spawn_interval(t: float) -> float:
	return lerpf(spawn_interval_start, spawn_interval_end, night_progress(t))


"""Speed given to a ship spawned at sim time t."""
func ship_speed(t: float) -> float:
	return lerpf(ship_speed_start, ship_speed_end, night_progress(t))


"""Probability that a spawn at sim time t is a Shade (0 before shade_start_time)."""
func shade_chance(t: float) -> float:
	if t < shade_start_time:
		return 0.0
	var span: float = maxf(dawn_time - shade_start_time, 0.000001)
	return lerpf(shade_chance_start, shade_chance_end, clampf((t - shade_start_time) / span, 0.0, 1.0))


"""Radius past which an outbound saved ship despawns (spawn_radius + despawn_margin)."""
func despawn_radius() -> float:
	return spawn_radius + despawn_margin


"""Number of ticks in a full night (dawn_time * sim_hz, rounded up), so win checks avoid float drift."""
func dawn_tick() -> int:
	return int(ceil(dawn_time * float(sim_hz) - 0.000001))


"""How many nudged angles a spawn tries after the first (k = 1..n): one full turn of spawn_retry_step."""
func spawn_retry_count() -> int:
	if spawn_retry_step <= 0.0:
		return 0
	return int(ceil(TAU / spawn_retry_step - 0.000001)) - 1


"""Angle a ship with this drift turns through on its spiral from spawn_radius to reef_radius."""
func ship_path_sweep(drift: float) -> float:
	return tan(drift) * log(spawn_radius / reef_radius)


"""Age at which a Shade starts fading (shade_lifetime - shade_fade_time)."""
func shade_fade_age() -> float:
	return shade_lifetime - shade_fade_time
