"""
View-only story cues for Framing.md ("the ship sees the reef" + option A "The Drowned"), kept out of
NightbeamView so the main view stays about entities. Holds its own timers and view RNG; the view feeds it
sim events and asks it for poses/brightness and to draw. Never touches the sim.
- Reef cue: under the beam the reef shows white breaker foam and jagged rock teeth.
- Ship answer: the masthead lamp brightens with guidance, blinks twice on save, then the ship heels and
  turns outward in a short arc instead of snapping.
- Wreck: foam flashes on the rock where the ship hit, and a thin purple wisp rises and drifts off-screen.
- Dawn: every remaining ghost folds its sail and sinks; living ships blink their lamps together.
Owner: view (GJ-18).
"""
class_name StoryFx extends RefCounted

# --- Reef cue ---
const REEF_TOOTH_COUNT: int = 44
const REEF_TOOTH_JITTER: float = 0.05
const REEF_TOOTH_HALF_WIDTH: float = 0.06
const REEF_TOOTH_MIN: float = 6.0
const REEF_TOOTH_MAX: float = 15.0
const REEF_FOAM_OFFSET: float = 13.0
const REEF_FOAM_POINTS: int = 18
const REEF_FOAM_WAVE: float = 1.4
const REEF_FOAM_WAVE_FREQ: float = 38.0
const REEF_FOAM_SPEED: float = 3.0
const REEF_LIT_INNER: float = 10.0
const REEF_LIT_OUTER: float = 8.0
const REEF_LIT_ALPHA: float = 0.35
const COLOR_ROCK_LIT: Color = Color("#A9AEC0")
const COLOR_ROCK_EDGE: Color = Color("#23283A")
const COLOR_FOAM: Color = Color("#F4F8FF")

# --- Ship answer ---
const LAMP_IDLE: float = 0.2
const ANSWER_BLINKS: int = 2
const ANSWER_BLINK_PERIOD: float = 0.25
const ANSWER_BLINK_ON: float = 0.12
const ANSWER_LAMP_OFF: float = 0.08
const TURN_DELAY: float = 0.25
const TURN_TIME: float = 0.6
const ANSWER_KEEP_TIME: float = 1.5

# --- Wreck: foam flash + wisp ---
const FOAM_HIT_TIME: float = 0.6
const FOAM_HIT_HALF_ARC: float = 0.3
const FOAM_HIT_WIDTH: float = 3.0
const WISP_LIFE: float = 4.5
const WISP_SPEED: float = 70.0
const WISP_RISE: float = 30.0
const WISP_ACCEL: float = 0.35
const WISP_SWAY: float = 18.0
const WISP_SWAY_HZ: float = 0.8
const WISP_SAMPLE_TIME: float = 0.06
const WISP_TRAIL_POINTS: int = 16
const WISP_HEAD_RADIUS: float = 3.0
const COLOR_WISP: Color = Color("#B79CFF")

# --- Dawn ---
const DAWN_SINK_TIME: float = 1.8
const DAWN_SINK_DEPTH: float = 12.0
const DAWN_SINK_MIN_SCALE: float = 0.3
const DAWN_BLINK_TIME: float = 1.5
const DAWN_BLINK_HZ: float = 2.0
const COLOR_GHOST: Color = Color("#8A5CF6")

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _answers: Dictionary = {}          # ship id -> {"t": float, "from": float (heading at save)}
var _foam_hits: Array[Dictionary] = []  # {"angle", "left"}
var _wisps: Array[Dictionary] = []      # {"pos", "vel", "t", "trail", "sample", "phase"} (bay-relative)
var _sinking: Array[Dictionary] = []    # {"pos", "heading", "t"} (bay-relative)
var _dawn_blink_left: float = 0.0
var _time: float = 0.0


func _init() -> void:
	_rng.randomize()


"""Clears every cue (new night / title)."""
func reset() -> void:
	_answers.clear()
	_foam_hits.clear()
	_wisps.clear()
	_sinking.clear()
	_dawn_blink_left = 0.0


"""Advances all cue timers by real time (called from the view's _process)."""
func tick(delta: float) -> void:
	_time += delta
	_dawn_blink_left = maxf(_dawn_blink_left - delta, 0.0)
	for id: int in _answers.keys():
		var answer: Dictionary = _answers[id]
		answer["t"] = float(answer["t"]) + delta
	for i: int in range(_foam_hits.size() - 1, -1, -1):
		_foam_hits[i]["left"] = float(_foam_hits[i]["left"]) - delta
		if float(_foam_hits[i]["left"]) <= 0.0:
			_foam_hits.remove_at(i)
	for i: int in range(_sinking.size() - 1, -1, -1):
		_sinking[i]["t"] = float(_sinking[i]["t"]) + delta
		if float(_sinking[i]["t"]) >= DAWN_SINK_TIME:
			_sinking.remove_at(i)
	for i: int in range(_wisps.size() - 1, -1, -1):
		if not _tick_wisp(_wisps[i], delta):
			_wisps.remove_at(i)


"""Drops answer state for ships that left the bay (ids not in live)."""
func prune(live: Dictionary) -> void:
	for id: int in _answers.keys():
		if not live.has(id) or float(_answers[id]["t"]) > TURN_DELAY + TURN_TIME + ANSWER_KEEP_TIME:
			_answers.erase(id)


# --- Event hooks (called by the view) -----------------------------------------------

"""A ship was saved: start its lamp answer and turn-away from the heading it had when it was lit."""
func on_ship_saved(id: int, heading: float) -> void:
	_answers[id] = {"t": 0.0, "from": heading}


"""A living ship hit the rock: foam flash at the hit angle and a purple wisp rising from the debris."""
func on_ship_wreck(angle: float, pos: Vector2) -> void:
	_foam_hits.append({"angle": angle, "left": FOAM_HIT_TIME})
	var out: Vector2 = Vector2.from_angle(angle)
	_wisps.append({"pos": pos, "vel": out * WISP_SPEED + Vector2(0.0, -WISP_RISE), "t": 0.0,
		"trail": PackedVector2Array([pos]), "sample": 0.0, "phase": _rng.randf() * TAU, "base": pos})


"""A Shade laid down at dawn: its ghost folds the sail and sinks (drawn after it left the sim)."""
func on_dawn_sink(pos: Vector2, heading: float) -> void:
	_sinking.append({"pos": pos, "heading": heading, "t": 0.0})


"""Dawn came: every living ship blinks its lamp in unison."""
func on_dawn() -> void:
	_dawn_blink_left = DAWN_BLINK_TIME


# --- Queries --------------------------------------------------------------------------

"""Masthead lamp brightness 0..1: dawn unison blink > save answer (2 blinks) > saved (on) > guidance."""
func ship_lamp(id: int, saved: bool, guidance: float) -> float:
	if _dawn_blink_left > 0.0:
		return 1.0 if fmod((DAWN_BLINK_TIME - _dawn_blink_left) * DAWN_BLINK_HZ, 1.0) < 0.5 else ANSWER_LAMP_OFF
	if _answers.has(id):
		var t: float = float(_answers[id]["t"])
		if t < ANSWER_BLINK_PERIOD * ANSWER_BLINKS:
			return 1.0 if fmod(t, ANSWER_BLINK_PERIOD) < ANSWER_BLINK_ON else ANSWER_LAMP_OFF
		return 1.0
	if saved:
		return 1.0
	return LAMP_IDLE + (1.0 - LAMP_IDLE) * clampf(guidance, 0.0, 1.0)


"""
Drawn pose of a ship as Vector2(heading, heel). A just-saved ship holds its old heading while it answers,
then turns to `outward` over TURN_TIME with a heel that peaks mid-turn; others use default_heading.
"""
func ship_pose(id: int, default_heading: float, outward: float) -> Vector2:
	if not _answers.has(id):
		return Vector2(default_heading, 0.0)
	var t: float = float(_answers[id]["t"])
	var from: float = float(_answers[id]["from"])
	if t < TURN_DELAY:
		return Vector2(from, 0.0)
	var u: float = clampf((t - TURN_DELAY) / TURN_TIME, 0.0, 1.0)
	var heading: float = from + NightbeamSim.angle_diff(outward, from) * smoothstep(0.0, 1.0, u)
	return Vector2(heading, sin(PI * u))


# --- Drawing ----------------------------------------------------------------------------

"""Foam and rock teeth where the beam crosses the reef ring; brightest at the beam's centre line."""
func draw_reef_cue(ci: CanvasItem, center: Vector2, beam_angle: float, half_width: float, reef_radius: float) -> void:
	# The lit stretch of rock itself turns pale, so the reef reads as a hard edge only where the light is.
	var wedge: PackedVector2Array = PackedVector2Array()
	for i: int in REEF_FOAM_POINTS + 1:
		var a: float = beam_angle - half_width + 2.0 * half_width * float(i) / float(REEF_FOAM_POINTS)
		wedge.append(center + Vector2.from_angle(a) * (reef_radius + REEF_LIT_OUTER))
	for i: int in range(REEF_FOAM_POINTS, -1, -1):
		var a: float = beam_angle - half_width + 2.0 * half_width * float(i) / float(REEF_FOAM_POINTS)
		wedge.append(center + Vector2.from_angle(a) * (reef_radius - REEF_LIT_INNER))
	ci.draw_colored_polygon(wedge, Color(COLOR_ROCK_LIT, REEF_LIT_ALPHA))
	for i: int in REEF_TOOTH_COUNT:
		var a: float = TAU * float(i) / float(REEF_TOOTH_COUNT) + sin(float(i) * 12.9898) * REEF_TOOTH_JITTER
		var d: float = absf(NightbeamSim.angle_diff(a, beam_angle))
		if d > half_width:
			continue
		var k: float = 1.0 - pow(d / half_width, 2.0)
		var h: float = lerpf(REEF_TOOTH_MIN, REEF_TOOTH_MAX, 0.5 + 0.5 * sin(float(i) * 78.233))
		var tooth: PackedVector2Array = PackedVector2Array([
			center + Vector2.from_angle(a - REEF_TOOTH_HALF_WIDTH) * (reef_radius - 2.0),
			center + Vector2.from_angle(a + REEF_TOOTH_HALF_WIDTH * 0.3) * (reef_radius + h),
			center + Vector2.from_angle(a + REEF_TOOTH_HALF_WIDTH) * (reef_radius - 2.0),
		])
		ci.draw_colored_polygon(tooth, Color(COLOR_ROCK_LIT, k))
		tooth.append(tooth[0])
		ci.draw_polyline(tooth, Color(COLOR_ROCK_EDGE, 0.8 * k), 1.0, true)
	_draw_foam_arc(ci, center, beam_angle, half_width, reef_radius + REEF_FOAM_OFFSET, 2.5, 0.95)
	_draw_foam_arc(ci, center, beam_angle, half_width * 0.8, reef_radius + REEF_FOAM_OFFSET + 6.0, 1.2, 0.4)


"""Foam flashes, wisps and sinking ghosts (drawn with the other fx, bay-relative to center)."""
func draw_effects(ci: CanvasItem, center: Vector2, reef_radius: float) -> void:
	for hit: Dictionary in _foam_hits:
		var k: float = float(hit["left"]) / FOAM_HIT_TIME
		var a: float = float(hit["angle"])
		ci.draw_arc(center, reef_radius + REEF_FOAM_OFFSET * 0.7, a - FOAM_HIT_HALF_ARC, a + FOAM_HIT_HALF_ARC,
				REEF_FOAM_POINTS, Color(COLOR_FOAM, k), FOAM_HIT_WIDTH * (0.5 + k), true)
	for ghost: Dictionary in _sinking:
		var u: float = float(ghost["t"]) / DAWN_SINK_TIME
		var pos: Vector2 = center + (ghost["pos"] as Vector2) + Vector2(0.0, DAWN_SINK_DEPTH * u)
		var edge: Color = COLOR_GHOST.lightened(0.35)
		ShipShapes.draw_ghost_ship(ci, pos, float(ghost["heading"]), lerpf(1.0, DAWN_SINK_MIN_SCALE, u),
				1.0 - u, COLOR_GHOST, edge, clampf(u * 2.0, 0.0, 1.0))
	for wisp: Dictionary in _wisps:
		_draw_wisp(ci, center, wisp)


func _draw_foam_arc(ci: CanvasItem, center: Vector2, beam_angle: float, half_width: float, radius: float,
		width: float, alpha: float) -> void:
	var previous: Vector2 = Vector2.ZERO
	for i: int in REEF_FOAM_POINTS + 1:
		var u: float = float(i) / float(REEF_FOAM_POINTS)
		var a: float = beam_angle - half_width + 2.0 * half_width * u
		var r: float = radius + sin(a * REEF_FOAM_WAVE_FREQ + _time * REEF_FOAM_SPEED) * REEF_FOAM_WAVE
		var point: Vector2 = center + Vector2.from_angle(a) * r
		if i > 0:
			var k: float = 1.0 - pow(absf(u * 2.0 - 1.0), 2.0)
			ci.draw_line(previous, point, Color(COLOR_FOAM, alpha * k), width, true)
		previous = point


func _tick_wisp(wisp: Dictionary, delta: float) -> bool:
	var t: float = float(wisp["t"]) + delta
	wisp["t"] = t
	if t >= WISP_LIFE:
		return false
	var vel: Vector2 = (wisp["vel"] as Vector2) * (1.0 + WISP_ACCEL * delta)
	wisp["vel"] = vel
	wisp["base"] = (wisp["base"] as Vector2) + vel * delta
	var side: Vector2 = vel.normalized().orthogonal()
	wisp["pos"] = (wisp["base"] as Vector2) + side * sin(t * TAU * WISP_SWAY_HZ + float(wisp["phase"])) * WISP_SWAY * minf(t, 1.0)
	wisp["sample"] = float(wisp["sample"]) + delta
	if float(wisp["sample"]) >= WISP_SAMPLE_TIME:
		wisp["sample"] = 0.0
		var trail: PackedVector2Array = wisp["trail"]
		trail.append(wisp["pos"])
		if trail.size() > WISP_TRAIL_POINTS:
			trail.remove_at(0)
		wisp["trail"] = trail
	return true


func _draw_wisp(ci: CanvasItem, center: Vector2, wisp: Dictionary) -> void:
	var fade: float = 1.0 - float(wisp["t"]) / WISP_LIFE
	var trail: PackedVector2Array = wisp["trail"]
	var n: int = trail.size()
	for i: int in range(1, n):
		var k: float = float(i) / float(n)
		ci.draw_line(center + trail[i - 1], center + trail[i], Color(COLOR_WISP, 0.7 * k * fade), 0.5 + 2.5 * k, true)
	var head: Vector2 = center + (wisp["pos"] as Vector2)
	ci.draw_circle(head, WISP_HEAD_RADIUS * 2.2, Color(COLOR_WISP, 0.25 * fade))
	ci.draw_circle(head, WISP_HEAD_RADIUS, Color(COLOR_WISP, 0.9 * fade))
