"""
Draws the bay, beam, ships and Shades with _draw() primitives from the latest observation only.
View-only effects (shake, wakes, flare ring, rock flash, particles, the first-lunge beat) use their own
RNG and state and never feed back into the sim. Geometry (bay, reef, beam cone, flare radius) comes from
the same NightbeamTuning the sim uses, so what you see is exactly what the rules test.
Every Shade removal event gets its own visible FX (GJ-11 "never a silent vanish"); each FX is announced
through `fx_played` so audio and the HUD can react. Story cues (Framing.md option A "The Drowned":
reef under the beam, ship lamp answer, wreck wisp, dawn) live in StoryFx; ship silhouettes in ShipShapes.
Owner: view (GJ-5, GJ-13, GJ-18).
"""
class_name NightbeamView extends Node2D

"""Emitted once per FX the view plays. fx_id is one of the FX_* constants; event is the sim event (or {})."""
signal fx_played(fx_id: StringName, event: Dictionary)

# --- FX ids: one per removal type, plus the fade onset (sigh) ---
const FX_SHIP_WRECK: StringName = &"ship_wreck"
const FX_SHADE_SPLASH: StringName = &"shade_splash"
const FX_SHADE_FADE: StringName = &"shade_fade_motes"
const FX_SHADE_FADE_START: StringName = &"shade_fade_start"
const FX_SHADE_FLARED: StringName = &"shade_flare_burst"

# --- Sim event / kind names (TDD observation schema + GJ-11) ---
const EVENT_WRECK: String = "wreck"
const EVENT_FLARE: String = "flare"
const EVENT_SAVED: String = "saved"
const EVENT_SHADE_FADE: String = "shade_fade"
const EVENT_SHADE_FLARED: String = "shade_flared"
const EVENT_WON: String = "won"
const EVENT_LEGACY_DISSOLVE: String = "dissolve"   # pre-GJ-12 sims; mapped to fade/flared
const KIND_SHIP: String = "ship"
const KIND_SHADE: String = "shade"
const STATE_LOST: String = "lost"

# --- Palette (GDD section 7) ---
const COLOR_SEA: Color = Color("#0B1630")
const COLOR_DEEP: Color = Color("#060C1C")
const COLOR_REEF: Color = Color("#3A3F4F")
const COLOR_REEF_FLASH: Color = Color("#E8E4F0")
const COLOR_BEAM: Color = Color("#FFE9A8")
const COLOR_HULL: Color = Color("#F2A65A")
const COLOR_DEBRIS: Color = Color("#A8743F")
const COLOR_SAIL_SAVED: Color = Color("#FFFFFF")
const COLOR_RING: Color = Color("#FFD166")
const COLOR_RING_SAVED: Color = Color("#7BE0AD")
const COLOR_RING_TRACK: Color = Color(1.0, 1.0, 1.0, 0.12)
const COLOR_SHADE: Color = Color("#8A5CF6")
const COLOR_SHADE_LIT: Color = Color("#FF4D6D")
const COLOR_SHADE_FADED: Color = Color("#6E6A80")
const COLOR_MOTE: Color = Color("#B79CFF")
const COLOR_EYE: Color = Color("#F7F1E1")
const COLOR_PUPIL: Color = Color("#140B2E")
const COLOR_LANTERN_GLOW: Color = Color("#D9C6FF")
const COLOR_DAWN_ROSE: Color = Color("#F7B7A3")
const COLOR_DAWN_GOLD: Color = Color("#FFD9A0")
const COLOR_SKY_NIGHT: Color = Color("#101E44")
const COLOR_TOWER: Color = Color("#D9D3C3")
const COLOR_TOWER_EDGE: Color = Color("#1B2238")
const COLOR_FLARE_PIP_ON: Color = Color("#FFFFFF")
const COLOR_FLARE_PIP_OFF: Color = Color(1.0, 1.0, 1.0, 0.18)
const COLOR_WAKE: Color = Color(0.85, 0.92, 1.0, 0.35)

# --- Beam ---
const BEAM_ALPHA: float = 0.35
const BEAM_OUTER_ALPHA_SCALE: float = 0.45
const BEAM_INNER_WIDTH_SCALE: float = 0.55
const BEAM_EDGE_ALPHA: float = 0.6
const BEAM_EDGE_WIDTH: float = 1.5
const BEAM_ARC_POINTS: int = 12

# --- Bay / sky ---
const BAY_EDGE_MARGIN: float = 10.0
const VIGNETTE_STEPS: int = 32
const VIGNETTE_OUTER_RADIUS: float = 560.0
const VIGNETTE_MAX_ALPHA: float = 0.9
const DAWN_ROSE_AT: float = 0.75
const PROGRESS_ARC_GAP: float = 8.0
const PROGRESS_ARC_WIDTH: float = 2.0
const PROGRESS_ARC_POINTS: int = 96
const REEF_ROCK_COUNT: int = 7
const REEF_ROCK_SCALE: float = 0.22
const REEF_FLASH_TIME: float = 0.3

# --- Lighthouse ---
const TOWER_RADIUS: float = 13.0
const TOWER_EDGE_WIDTH: float = 2.0
const LAMP_RADIUS: float = 5.0
const FLARE_PIP_RADIUS: float = 3.5
const FLARE_PIP_ORBIT: float = 22.0

# --- Ships (silhouettes in ShipShapes) ---
const RING_RADIUS: float = 13.0
const RING_WIDTH: float = 3.0
const RING_POINTS: int = 32
const LIT_OUTLINE_RADIUS: float = 17.5
const LIT_OUTLINE_WIDTH: float = 1.5
const SPAWN_FADE_TIME: float = 0.5

# --- Shades (ghost ships, Framing.md option A) ---
## Footprint radius used for fx placement around a Shade.
const SHADE_RADIUS: float = 13.0
## The wavy "spirit" body inside the ghost hull (keeps the wavy-outline shape cue).
const SHADE_BODY_RADIUS: float = 7.0
const SHADE_LANTERN_GLOW_SCALE: float = 2.2
const SHADE_LANTERN_GLOW_ALPHA: float = 0.4
const SHADE_WAVE_AMP: float = 2.2
const SHADE_WAVE_LOBES: int = 6
const SHADE_WAVE_SPEED: float = 4.0
const SHADE_POINTS: int = 28
const SHADE_OUTLINE_WIDTH: float = 2.0
## x = sideways from the centre, y = forward toward the reef.
const SHADE_EYE_OFFSET: Vector2 = Vector2(4.6, 2.6)
const SHADE_EYE_RADIUS: float = 3.1
const SHADE_EYE_RADIUS_WIDE: float = 4.6
const SHADE_PUPIL_RADIUS: float = 1.6
const SHADE_PUPIL_RADIUS_WIDE: float = 1.1
const SHADE_PUPIL_TRAVEL: float = 1.4
const SHADE_BOB_AMPLITUDE: float = 3.0
const SHADE_BOB_SPEED: float = 2.4
const SHADE_HOLD_SPEED_EPS: float = 0.01
const SHADE_FADE_MIN_SCALE: float = 0.35
## Soft glow so a dark Shade on the dark sea is noticed at a glance (Boss: "I don't see what this is").
const SHADE_HALO_SCALE: float = 1.9
const SHADE_HALO_ALPHA: float = 0.16
const SPEED_LINE_COUNT: int = 3
const SPEED_LINE_LENGTH: float = 9.0
const SPEED_LINE_SPREAD: float = 4.0
## Fallbacks while the tuning resource predates GJ-12 (GDD tunables table).
const DEFAULT_SHADE_FADE_TIME: float = 0.75
const DEFAULT_SHADE_HOLD_RADIUS: float = 120.0

# --- Wakes / fx ---
const WAKE_LENGTH: int = 12
const WAKE_SAMPLE_TICKS: int = 6
const WAKE_WIDTH: float = 2.0
const SHAKE_AMPLITUDE: float = 6.0
const SHAKE_TIME: float = 0.25
const FLARE_RING_TIME: float = 0.4
const FLARE_RING_WIDTH: float = 3.0
const SAVE_POP_TIME: float = 0.35
const SAVE_POP_RADIUS: float = 20.0
const MOTE_COUNT_MIN: int = 6
const MOTE_COUNT_MAX: int = 8
const MOTE_LIFE: float = 1.5
const MOTE_RISE_SPEED: float = 30.0
const MOTE_RADIUS: float = 2.7
const DEBRIS_COUNT: int = 7
const DEBRIS_LIFE: float = 0.7
const DEBRIS_SPEED: float = 60.0
const DEBRIS_SIZE: float = 2.5
const SPLASH_TIME: float = 0.6
const SPLASH_RADIUS: float = 34.0
const SPLASH_DROPS: int = 9
const SPLASH_DROP_SPEED: float = 70.0
const BURST_TIME: float = 0.35
const BURST_RADIUS: float = 22.0
const BURST_RAYS: int = 8
const PARTICLE_DRAG: float = 2.5

# --- First-lunge beat (GJ-11 teaching) ---
const BEAT_PULSE_HZ: float = 5.0
const BEAT_RING_RADIUS: float = 24.0
const BEAT_RING_WIDTH: float = 3.0
const BEAT_DASH_LENGTH: float = 6.0
const BEAT_DASH_GAP: float = 5.0
const BEAT_LINE_WIDTH: float = 2.0

var tuning: NightbeamTuning = null
var _obs: Dictionary = {}
var _prev_obs: Dictionary = {}
var _view_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _wakes: Dictionary = {}           # entity id -> PackedVector2Array (bay-relative, oldest first)
var _fade_started: Dictionary = {}    # shade id -> true once its fade FX (motes + sigh) played
var _shake_left: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO
var _reef_flash_left: float = 0.0
var _reef_flash_color: Color = COLOR_REEF_FLASH
var _flare_ring_left: float = 0.0
var _rings: Array[Dictionary] = []      # {pos, r0, r1, life, left, color, width} (bay-relative)
var _particles: Array[Dictionary] = []  # {pos, vel, life, left, color, size, drag}
var _beat_id: int = -1
var _beat_left: float = 0.0
var _anim_time: float = 0.0
var _story: StoryFx = StoryFx.new()


func _ready() -> void:
	_view_rng.randomize()


func _process(delta: float) -> void:
	_anim_time += delta
	_shake_left = maxf(_shake_left - delta, 0.0)
	_reef_flash_left = maxf(_reef_flash_left - delta, 0.0)
	_flare_ring_left = maxf(_flare_ring_left - delta, 0.0)
	_beat_left = maxf(_beat_left - delta, 0.0)
	_shake_offset = Vector2.ZERO
	if _shake_left > 0.0:
		var strength: float = SHAKE_AMPLITUDE * (_shake_left / SHAKE_TIME)
		_shake_offset = Vector2(_view_rng.randf_range(-1.0, 1.0), _view_rng.randf_range(-1.0, 1.0)) * strength
	_age_effects(delta)
	_story.tick(delta)
	queue_redraw()


"""Sets the tuning used for bay geometry (must be the one the sim runs on). Called once by GameFlow."""
func configure(p_tuning: NightbeamTuning) -> void:
	tuning = p_tuning


"""Clears all view-only effects (wakes, shake, flashes, particles). Called when a new night or title starts."""
func reset_effects() -> void:
	_obs = {}
	_prev_obs = {}
	_wakes.clear()
	_fade_started.clear()
	_rings.clear()
	_particles.clear()
	_shake_left = 0.0
	_reef_flash_left = 0.0
	_flare_ring_left = 0.0
	_beat_id = -1
	_beat_left = 0.0
	_story.reset()


"""Stores the latest observation and requests a redraw. Never mutates the sim."""
func show_observation(obs: Dictionary) -> void:
	_prev_obs = _obs
	_obs = obs
	_update_wakes()
	_start_fades()
	_consume_events()
	_prune_fades()
	queue_redraw()


"""Starts the first-lunge beat visuals on a Shade: red ring pulse, wide eyes, dotted line to the rock."""
func start_lunge_beat(entity_id: int, duration: float) -> void:
	_beat_id = entity_id
	_beat_left = duration


"""
Kind ("ship" | "shade") of the entity an event refers to. Uses the event's own "kind" (GJ-12 sims);
older sims don't send it, so fall back to the entity with that id in the previous observation.
"""
static func event_kind(event: Dictionary, prev_obs: Dictionary) -> String:
	var kind: String = String(event.get("kind", ""))
	if kind != "":
		return kind
	var id: int = int(event.get("id", -1))
	for entity: Dictionary in prev_obs.get("entities", []):
		if int(entity.get("id", -2)) == id:
			return String(entity.get("kind", KIND_SHIP))
	return KIND_SHIP


func _draw() -> void:
	if tuning == null:
		return
	var center: Vector2 = get_viewport_rect().size * 0.5
	var progress: float = _night_progress()
	_draw_sky(center, progress)
	draw_set_transform(_shake_offset)
	_draw_bay(center, progress)
	_draw_wakes(center)
	if String(_obs.get("state", "")) != STATE_LOST:
		_draw_beam(center)
		_story.draw_reef_cue(self, center, float(_obs.get("beam_angle", 0.0)), tuning.beam_half_width,
				tuning.reef_radius)
	for entity: Dictionary in _obs.get("entities", []):
		if String(entity.get("kind", "")) == KIND_SHADE:
			_draw_shade(center, entity)
		else:
			_draw_ship(center, entity)
	_draw_fx(center)
	_draw_lighthouse(center)
	draw_set_transform(Vector2.ZERO)


# --- Observation bookkeeping -------------------------------------------------

func _night_progress() -> float:
	return clampf(float(_obs.get("time", 0.0)) / tuning.dawn_time, 0.0, 1.0)


func _polar(center: Vector2, angle: float, radius: float) -> Vector2:
	return center + Vector2.from_angle(angle) * radius


func _bay_pos(angle: float, radius: float) -> Vector2:
	return Vector2.from_angle(angle) * radius


func _shade_fade_time() -> float:
	var value: Variant = tuning.get("shade_fade_time")
	return float(value) if value != null else DEFAULT_SHADE_FADE_TIME


func _shade_hold_radius() -> float:
	var value: Variant = tuning.get("shade_hold_radius")
	return float(value) if value != null else DEFAULT_SHADE_HOLD_RADIUS


func _is_fading(entity: Dictionary) -> bool:
	if entity.has("fading"):
		return bool(entity["fading"])
	return float(entity.get("age", 0.0)) >= tuning.shade_lifetime - _shade_fade_time()


# 0 at the start of the fade, 1 at removal (the sim removes at age >= shade_lifetime).
func _fade_progress(entity: Dictionary) -> float:
	var start: float = tuning.shade_lifetime - _shade_fade_time()
	return clampf((float(entity.get("age", 0.0)) - start) / _shade_fade_time(), 0.0, 1.0)


func _is_holding(entity: Dictionary) -> bool:
	return not bool(entity.get("lit", false)) and not _is_fading(entity) \
		and (float(entity.get("speed", 1.0)) <= SHADE_HOLD_SPEED_EPS
			or float(entity.get("radius", 0.0)) <= _shade_hold_radius() + SHADE_HOLD_SPEED_EPS)


# Wakes sample every WAKE_SAMPLE_TICKS ticks so 12 points cover ~1.2 s of travel; stale ids are dropped.
func _update_wakes() -> void:
	var live: Dictionary = {}
	var sample: bool = int(_obs.get("tick", 0)) % WAKE_SAMPLE_TICKS == 0
	for entity: Dictionary in _obs.get("entities", []):
		var id: int = int(entity.get("id", -1))
		live[id] = true
		if String(entity.get("kind", "")) == KIND_SHADE:
			continue   # Shades hover; a wake would read as a boat
		if not sample and _wakes.has(id):
			continue
		var trail: PackedVector2Array = _wakes.get(id, PackedVector2Array())
		trail.append(_bay_pos(float(entity.get("angle", 0.0)), float(entity.get("radius", 0.0))))
		if trail.size() > WAKE_LENGTH:
			trail.remove_at(0)
		_wakes[id] = trail
	for id: int in _wakes.keys():
		if not live.has(id):
			_wakes.erase(id)
	_story.prune(live)


# Runs after the events so a shade_fade removal still sees that its fade FX already played.
func _prune_fades() -> void:
	var live: Dictionary = {}
	for entity: Dictionary in _obs.get("entities", []):
		live[int(entity.get("id", -1))] = true
	for id: int in _fade_started.keys():
		if not live.has(id):
			_fade_started.erase(id)


# The fade FX (motes + sigh) starts when a Shade becomes `fading`, so it plays over the whole fade.
func _start_fades() -> void:
	for entity: Dictionary in _obs.get("entities", []):
		if String(entity.get("kind", "")) != KIND_SHADE or not _is_fading(entity):
			continue
		var id: int = int(entity.get("id", -1))
		if _fade_started.has(id):
			continue
		_fade_started[id] = true
		_spawn_motes(_bay_pos(float(entity.get("angle", 0.0)), float(entity.get("radius", 0.0))))
		fx_played.emit(FX_SHADE_FADE_START, {})


func _consume_events() -> void:
	var events: Array = _obs.get("events", [])
	var flare_this_tick: bool = false
	var dawn_this_tick: bool = false
	for event: Dictionary in events:
		match String(event.get("type", "")):
			EVENT_FLARE:
				flare_this_tick = true
			EVENT_WON:
				dawn_this_tick = true
	for event: Dictionary in events:
		var type: String = String(event.get("type", ""))
		if type == EVENT_LEGACY_DISSOLVE:
			type = EVENT_SHADE_FLARED if flare_this_tick else EVENT_SHADE_FADE
		var pos: Vector2 = _bay_pos(float(event.get("angle", 0.0)), float(event.get("radius", 0.0)))
		match type:
			EVENT_WRECK:
				if event_kind(event, _prev_obs) == KIND_SHADE:
					_play_shade_splash(pos, event)
				else:
					_play_ship_wreck(pos, event)
			EVENT_SHADE_FADE:
				_play_shade_fade(pos, event)
				if dawn_this_tick:
					_story.on_dawn_sink(pos, float(event.get("angle", 0.0)) + PI)
			EVENT_SHADE_FLARED:
				_play_shade_burst(pos, event)
			EVENT_FLARE:
				_flare_ring_left = FLARE_RING_TIME
			EVENT_SAVED:
				_add_ring(pos, RING_RADIUS, RING_RADIUS + SAVE_POP_RADIUS, SAVE_POP_TIME, COLOR_RING_SAVED, RING_WIDTH)
				_story.on_ship_saved(int(event.get("id", -1)), _heading_of(int(event.get("id", -1)),
						float(event.get("angle", 0.0)) + PI))
			EVENT_WON:
				_story.on_dawn()


# --- FX builders ---------------------------------------------------------------

func _play_ship_wreck(pos: Vector2, event: Dictionary) -> void:
	_shake_left = SHAKE_TIME
	_reef_flash_left = REEF_FLASH_TIME
	_reef_flash_color = COLOR_REEF_FLASH
	for i: int in DEBRIS_COUNT:
		var dir: Vector2 = Vector2.from_angle(_view_rng.randf() * TAU)
		_add_particle(pos, dir * _view_rng.randf_range(0.4, 1.0) * DEBRIS_SPEED, DEBRIS_LIFE,
				COLOR_DEBRIS if i % 2 == 0 else COLOR_HULL, DEBRIS_SIZE)
	# The Drowned: the lost ship's ghost rises from the debris (view only, nothing spawns in the sim).
	_story.on_ship_wreck(float(event.get("angle", 0.0)), pos)
	fx_played.emit(FX_SHIP_WRECK, event)


# A lit Shade reaching the rock: purple splash ring + droplets, purple rock flash, no shake (not the foghorn).
func _play_shade_splash(pos: Vector2, event: Dictionary) -> void:
	_reef_flash_left = REEF_FLASH_TIME
	_reef_flash_color = COLOR_SHADE
	_add_ring(pos, SHADE_RADIUS * 0.5, SPLASH_RADIUS, SPLASH_TIME, COLOR_SHADE, FLARE_RING_WIDTH)
	_add_ring(pos, 0.0, SPLASH_RADIUS * 0.6, SPLASH_TIME * 0.7, COLOR_MOTE, 2.0)
	for i: int in SPLASH_DROPS:
		var dir: Vector2 = Vector2.from_angle(TAU * float(i) / float(SPLASH_DROPS) + _view_rng.randf() * 0.3)
		_add_particle(pos, dir * SPLASH_DROP_SPEED, SPLASH_TIME, COLOR_MOTE, MOTE_RADIUS)
	fx_played.emit(FX_SHADE_SPLASH, event)


# If the fade onset was never observed (e.g. a very short fade), play the motes + sigh now.
func _play_shade_fade(pos: Vector2, event: Dictionary) -> void:
	var id: int = int(event.get("id", -1))
	if not _fade_started.has(id):
		_fade_started[id] = true
		_spawn_motes(pos)
		fx_played.emit(FX_SHADE_FADE_START, {})
	_add_ring(pos, SHADE_RADIUS * SHADE_FADE_MIN_SCALE, SHADE_RADIUS, MOTE_LIFE * 0.4, COLOR_SHADE_FADED, 1.0)
	fx_played.emit(FX_SHADE_FADE, event)


func _play_shade_burst(pos: Vector2, event: Dictionary) -> void:
	_add_ring(pos, SHADE_RADIUS, SHADE_RADIUS + BURST_RADIUS, BURST_TIME, COLOR_SAIL_SAVED, FLARE_RING_WIDTH)
	for i: int in BURST_RAYS:
		var dir: Vector2 = Vector2.from_angle(TAU * float(i) / float(BURST_RAYS))
		_add_particle(pos + dir * SHADE_RADIUS, dir * BURST_RADIUS / BURST_TIME, BURST_TIME, COLOR_SAIL_SAVED, 2.0)
	fx_played.emit(FX_SHADE_FLARED, event)


func _spawn_motes(pos: Vector2) -> void:
	var count: int = _view_rng.randi_range(MOTE_COUNT_MIN, MOTE_COUNT_MAX)
	for i: int in count:
		var start: Vector2 = pos + Vector2(_view_rng.randf_range(-SHADE_RADIUS, SHADE_RADIUS), _view_rng.randf_range(-4.0, 4.0))
		var vel: Vector2 = Vector2(_view_rng.randf_range(-6.0, 6.0), -MOTE_RISE_SPEED * _view_rng.randf_range(0.7, 1.3))
		var particle: Dictionary = _add_particle(start, vel, MOTE_LIFE * _view_rng.randf_range(0.8, 1.2), COLOR_MOTE, MOTE_RADIUS)
		particle["drag"] = 0.0


func _add_ring(pos: Vector2, r0: float, r1: float, life: float, color: Color, width: float) -> void:
	_rings.append({"pos": pos, "r0": r0, "r1": r1, "life": life, "left": life, "color": color, "width": width})


func _add_particle(pos: Vector2, vel: Vector2, life: float, color: Color, size: float) -> Dictionary:
	var particle: Dictionary = {"pos": pos, "vel": vel, "life": life, "left": life, "color": color,
		"size": size, "drag": PARTICLE_DRAG}
	_particles.append(particle)
	return particle


func _age_effects(delta: float) -> void:
	for i: int in range(_rings.size() - 1, -1, -1):
		_rings[i]["left"] = float(_rings[i]["left"]) - delta
		if float(_rings[i]["left"]) <= 0.0:
			_rings.remove_at(i)
	for i: int in range(_particles.size() - 1, -1, -1):
		var p: Dictionary = _particles[i]
		p["left"] = float(p["left"]) - delta
		if float(p["left"]) <= 0.0:
			_particles.remove_at(i)
			continue
		var vel: Vector2 = p["vel"]
		vel *= maxf(0.0, 1.0 - float(p["drag"]) * delta)
		p["vel"] = vel
		p["pos"] = (p["pos"] as Vector2) + vel * delta


# --- Background --------------------------------------------------------------

func _sky_color(progress: float) -> Color:
	if progress < DAWN_ROSE_AT:
		return COLOR_SKY_NIGHT.lerp(COLOR_DAWN_ROSE, progress / DAWN_ROSE_AT * 0.35)
	var t: float = (progress - DAWN_ROSE_AT) / (1.0 - DAWN_ROSE_AT)
	return COLOR_SKY_NIGHT.lerp(COLOR_DAWN_ROSE, 0.35).lerp(COLOR_DAWN_GOLD, t)


# Edge vignette: the sky colour fills the screen, then darker rings stack toward the bay so the
# night-progress colour only shows at the edges (GDD UI: navy -> rose -> gold).
func _draw_sky(center: Vector2, progress: float) -> void:
	draw_rect(get_viewport_rect(), _sky_color(progress))
	var bay_radius: float = tuning.spawn_radius + BAY_EDGE_MARGIN
	for i: int in VIGNETTE_STEPS:
		var t: float = float(i + 1) / float(VIGNETTE_STEPS)
		var radius: float = lerpf(VIGNETTE_OUTER_RADIUS, bay_radius, t)
		draw_circle(center, radius, Color(COLOR_DEEP, VIGNETTE_MAX_ALPHA / float(VIGNETTE_STEPS) * 2.0))


func _draw_bay(center: Vector2, progress: float) -> void:
	var bay_radius: float = tuning.spawn_radius + BAY_EDGE_MARGIN
	draw_circle(center, bay_radius, COLOR_SEA)
	var arc_radius: float = bay_radius + PROGRESS_ARC_GAP
	draw_arc(center, arc_radius, 0.0, TAU, PROGRESS_ARC_POINTS, COLOR_RING_TRACK, PROGRESS_ARC_WIDTH, true)
	if progress > 0.0:
		draw_arc(center, arc_radius, -PI * 0.5, -PI * 0.5 + TAU * progress, PROGRESS_ARC_POINTS,
				_sky_color(progress).lerp(COLOR_DAWN_GOLD, 0.5), PROGRESS_ARC_WIDTH, true)
	var reef_color: Color = COLOR_REEF.lerp(_reef_flash_color, _reef_flash_left / REEF_FLASH_TIME)
	draw_circle(center, tuning.reef_radius, reef_color)
	for i: int in REEF_ROCK_COUNT:
		var angle: float = TAU * float(i) / float(REEF_ROCK_COUNT)
		draw_circle(_polar(center, angle, tuning.reef_radius), tuning.reef_radius * REEF_ROCK_SCALE, reef_color)


func _draw_wakes(center: Vector2) -> void:
	for id: int in _wakes:
		var trail: PackedVector2Array = _wakes[id]
		for i: int in range(1, trail.size()):
			var alpha: float = float(i) / float(trail.size())
			draw_line(center + trail[i - 1], center + trail[i], Color(COLOR_WAKE, COLOR_WAKE.a * alpha), WAKE_WIDTH)


# --- Beam & lighthouse -------------------------------------------------------

func _draw_beam(center: Vector2) -> void:
	var angle: float = float(_obs.get("beam_angle", 0.0))
	var half: float = tuning.beam_half_width
	_draw_cone(center, angle, half, tuning.beam_range, Color(COLOR_BEAM, BEAM_ALPHA * BEAM_OUTER_ALPHA_SCALE))
	_draw_cone(center, angle, half * BEAM_INNER_WIDTH_SCALE, tuning.beam_range,
			Color(COLOR_BEAM, BEAM_ALPHA * BEAM_OUTER_ALPHA_SCALE))
	var edge: Color = Color(COLOR_BEAM, BEAM_EDGE_ALPHA)
	draw_line(center, _polar(center, angle - half, tuning.beam_range), edge, BEAM_EDGE_WIDTH, true)
	draw_line(center, _polar(center, angle + half, tuning.beam_range), edge, BEAM_EDGE_WIDTH, true)


func _draw_cone(center: Vector2, angle: float, half: float, length: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array([center])
	for i: int in BEAM_ARC_POINTS + 1:
		var a: float = angle - half + 2.0 * half * float(i) / float(BEAM_ARC_POINTS)
		points.append(_polar(center, a, length))
	draw_colored_polygon(points, color)


func _draw_lighthouse(center: Vector2) -> void:
	draw_circle(center, TOWER_RADIUS + TOWER_EDGE_WIDTH, COLOR_TOWER_EDGE)
	draw_circle(center, TOWER_RADIUS, COLOR_TOWER)
	var lamp: Color = COLOR_BEAM if String(_obs.get("state", "")) != STATE_LOST else COLOR_REEF
	draw_circle(center, LAMP_RADIUS, lamp)
	# Flare pips orbit the tower (GDD: "flare pips on the lighthouse"); filled = charge ready.
	var charges: int = int(_obs.get("flare_charges", 0))
	var cooling: bool = float(_obs.get("flare_cd", 0.0)) > 0.0
	for i: int in tuning.flare_max_charges:
		var a: float = -PI * 0.5 + PI * (float(i) - float(tuning.flare_max_charges - 1) * 0.5) * 0.35
		var on: bool = i < charges
		var color: Color = COLOR_FLARE_PIP_ON if on and not cooling else COLOR_FLARE_PIP_OFF
		if on and cooling:
			color = Color(COLOR_FLARE_PIP_ON, 0.5)
		draw_circle(_polar(center, a, FLARE_PIP_ORBIT), FLARE_PIP_RADIUS, color)


# --- Entities ----------------------------------------------------------------

func _spawn_alpha(entity: Dictionary) -> float:
	return clampf(float(entity.get("age", 0.0)) / SPAWN_FADE_TIME, 0.0, 1.0)


# Heading comes from the wake (last two samples) so the spiral drift shows; falls back to radial.
func _heading(entity: Dictionary) -> float:
	var radial: float = float(entity.get("angle", 0.0))
	return _heading_of(int(entity.get("id", -1)), radial if bool(entity.get("saved", false)) else radial + PI)


func _heading_of(id: int, fallback: float) -> float:
	var trail: PackedVector2Array = _wakes.get(id, PackedVector2Array())
	var n: int = trail.size()
	if n >= 2 and trail[n - 1].distance_squared_to(trail[n - 2]) > 0.01:
		return (trail[n - 1] - trail[n - 2]).angle()
	return fallback


func _draw_ship(center: Vector2, entity: Dictionary) -> void:
	var pos: Vector2 = _polar(center, float(entity.get("angle", 0.0)), float(entity.get("radius", 0.0)))
	var alpha: float = _spawn_alpha(entity)
	var saved: bool = bool(entity.get("saved", false))
	var guidance: float = clampf(float(entity.get("guidance", 0.0)), 0.0, 1.0)
	if bool(entity.get("lit", false)) and not saved:
		draw_arc(pos, LIT_OUTLINE_RADIUS, 0.0, TAU, RING_POINTS, Color(COLOR_BEAM, 0.9 * alpha), LIT_OUTLINE_WIDTH, true)
	# Guidance ring fills clockwise from 12 o'clock; full green once saved.
	draw_arc(pos, RING_RADIUS, 0.0, TAU, RING_POINTS, Color(COLOR_RING_TRACK, COLOR_RING_TRACK.a * alpha), RING_WIDTH, true)
	if saved:
		draw_arc(pos, RING_RADIUS, 0.0, TAU, RING_POINTS, Color(COLOR_RING_SAVED, alpha), RING_WIDTH, true)
	elif guidance > 0.0:
		draw_arc(pos, RING_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * guidance, RING_POINTS,
				Color(COLOR_RING, alpha), RING_WIDTH, true)
	# Shared cue "the ship sees the reef": the masthead lamp brightens with guidance, answers with two
	# blinks on save, then the ship heels over and turns outward (StoryFx).
	var id: int = int(entity.get("id", -1))
	var pose: Vector2 = _story.ship_pose(id, _heading(entity), float(entity.get("angle", 0.0)))
	ShipShapes.draw_living_ship(self, pos, pose.x, pose.y, alpha, saved, _story.ship_lamp(id, saved, guidance))


# Shade states (GJ-11): drifting / holding (bobs, eyes on the beam) / lit (red outline, speed lines) /
# fading (desaturates + shrinks while motes rise). The first-lunge beat adds a pulse, wide eyes and a
# dotted line to the rock.
func _draw_shade(center: Vector2, entity: Dictionary) -> void:
	var id: int = int(entity.get("id", 0))
	var angle: float = float(entity.get("angle", 0.0))
	var pos: Vector2 = _polar(center, angle, float(entity.get("radius", 0.0)))
	var lit: bool = bool(entity.get("lit", false))
	var fading: bool = _is_fading(entity)
	var fade: float = _fade_progress(entity) if fading else 0.0
	var in_beat: bool = id == _beat_id and _beat_left > 0.0
	if _is_holding(entity):
		pos.y += sin(_anim_time * SHADE_BOB_SPEED + float(id) * 1.7) * SHADE_BOB_AMPLITUDE
	var alpha: float = _spawn_alpha(entity) * (1.0 - 0.7 * fade)
	var scale: float = lerpf(1.0, SHADE_FADE_MIN_SCALE, fade)
	var body_color: Color = COLOR_SHADE.lerp(COLOR_SHADE_FADED, fade)
	if in_beat:
		_draw_beat_line(center, pos, angle)
	draw_circle(pos, SHADE_RADIUS * SHADE_HALO_SCALE * scale, Color(body_color, SHADE_HALO_ALPHA * alpha))
	# The Drowned: a see-through ghost hull with a torn sail, bow toward the lamp; the sail furls as it
	# is laid to rest (fade). Red outline while lit, like the M2 cue.
	var edge: Color = COLOR_SHADE_LIT if lit else body_color.lightened(0.35)
	# Wavy spirit body under the hull keeps the shape cue (GDD accessibility: not only colour).
	var phase: float = _anim_time * SHADE_WAVE_SPEED + float(id)
	var outline: PackedVector2Array = PackedVector2Array()
	for i: int in SHADE_POINTS:
		var t: float = TAU * float(i) / float(SHADE_POINTS)
		var r: float = (SHADE_BODY_RADIUS + sin(t * SHADE_WAVE_LOBES + phase) * SHADE_WAVE_AMP) * scale
		outline.append(pos + Vector2.from_angle(t) * r)
	draw_colored_polygon(outline, Color(body_color, 0.45 * alpha))
	outline.append(outline[0])
	draw_polyline(outline, Color(edge, 0.8 * alpha), SHADE_OUTLINE_WIDTH * 0.75, true)
	ShipShapes.draw_ghost_ship(self, pos, angle + PI, scale, alpha, body_color, edge, fade)
	if lit:
		var outward: Vector2 = Vector2.from_angle(angle)
		var side: Vector2 = outward.orthogonal()
		for i: int in SPEED_LINE_COUNT:
			var lateral: Vector2 = side * SPEED_LINE_SPREAD * (float(i) - float(SPEED_LINE_COUNT - 1) * 0.5)
			var start: Vector2 = pos + outward * (ShipShapes.GHOST_LENGTH * 0.5 * scale + 2.0) + lateral
			draw_line(start, start + outward * SPEED_LINE_LENGTH, Color(COLOR_SHADE_LIT, 0.8 * alpha), 1.5, true)
	if in_beat:
		var pulse: float = 0.5 + 0.5 * sin(_anim_time * TAU * BEAT_PULSE_HZ)
		draw_arc(pos, BEAT_RING_RADIUS + pulse * 4.0, 0.0, TAU, RING_POINTS,
				Color(COLOR_SHADE_LIT, 0.5 + 0.5 * pulse), BEAT_RING_WIDTH, true)
	_draw_shade_eyes(center, pos, angle, scale, alpha, in_beat)


# Eyes are the ghost's two masthead lanterns (option A); pupils look at the nearest part of the beam
# (GJ-11 "eyes on the beam").
func _draw_shade_eyes(center: Vector2, pos: Vector2, angle: float, scale: float, alpha: float, wide: bool) -> void:
	var fwd: Vector2 = Vector2.from_angle(angle + PI)
	var right: Vector2 = fwd.orthogonal()
	var beam_point: Vector2 = _polar(center, float(_obs.get("beam_angle", 0.0)), pos.distance_to(center))
	var look: Vector2 = (beam_point - pos).normalized() if beam_point.distance_squared_to(pos) > 1.0 else fwd
	var eye_radius: float = (SHADE_EYE_RADIUS_WIDE if wide else SHADE_EYE_RADIUS) * scale
	var pupil_radius: float = (SHADE_PUPIL_RADIUS_WIDE if wide else SHADE_PUPIL_RADIUS) * scale
	for s: float in [-1.0, 1.0]:
		var eye: Vector2 = pos + (right * SHADE_EYE_OFFSET.x * s + fwd * SHADE_EYE_OFFSET.y) * scale
		draw_circle(eye, eye_radius * SHADE_LANTERN_GLOW_SCALE, Color(COLOR_LANTERN_GLOW, SHADE_LANTERN_GLOW_ALPHA * alpha))
		draw_circle(eye, eye_radius, Color(COLOR_EYE, alpha))
		draw_circle(eye + look * SHADE_PUPIL_TRAVEL * scale, pupil_radius, Color(COLOR_PUPIL, alpha))


func _draw_beat_line(center: Vector2, pos: Vector2, angle: float) -> void:
	var target: Vector2 = _polar(center, angle, tuning.reef_radius)
	var length: float = pos.distance_to(target)
	var dir: Vector2 = (target - pos).normalized()
	var d: float = SHADE_RADIUS
	while d < length:
		var end: float = minf(d + BEAT_DASH_LENGTH, length)
		draw_line(pos + dir * d, pos + dir * end, COLOR_SHADE_LIT, BEAT_LINE_WIDTH, true)
		d += BEAT_DASH_LENGTH + BEAT_DASH_GAP


func _draw_fx(center: Vector2) -> void:
	if _flare_ring_left > 0.0:
		var t: float = 1.0 - _flare_ring_left / FLARE_RING_TIME
		draw_arc(center, tuning.flare_radius * t, 0.0, TAU, PROGRESS_ARC_POINTS,
				Color(COLOR_SAIL_SAVED, 1.0 - t), FLARE_RING_WIDTH, true)
	for ring: Dictionary in _rings:
		var t: float = 1.0 - float(ring["left"]) / float(ring["life"])
		var color: Color = ring["color"]
		draw_arc(center + (ring["pos"] as Vector2), lerpf(float(ring["r0"]), float(ring["r1"]), t), 0.0, TAU,
				RING_POINTS, Color(color, 1.0 - t), float(ring["width"]) * (1.0 - t) + 0.5, true)
	for p: Dictionary in _particles:
		var life_t: float = float(p["left"]) / float(p["life"])
		var color: Color = p["color"]
		draw_circle(center + (p["pos"] as Vector2), float(p["size"]) * (0.5 + 0.5 * life_t), Color(color, life_t))
	_story.draw_effects(self, center, tuning.reef_radius)
