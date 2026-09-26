"""
Human-fidelity perception for Playtest Lab personas (GJ-10; M2 cues GJ-14; "The Drowned" cues GJ-19).
Turns what Main.tscn draws into words a player could say: HUD/card text exactly as drawn, a deliberately vague
scene description and noticeable events without their causes. Never exposes hidden sim values (guidance numbers,
speeds, ids, timers, exact counts beyond what the HUD prints).
Directions: clock hours for the bay at large, plus beam-relative cues ("just past the beam's clockwise edge")
for anything near the beam, because the beam (~30 deg) is as wide as one clock hour and a player aims by eye.
Clockwise is the way the beam sweeps from 12 toward 3 on screen.
Cues mirrored from NightbeamView / StoryFx / ShipShapes / HudView (GJ-13, GJ-18):
- reef under the beam turns pale with jagged teeth and white foam; elsewhere it is a dark grey blob;
- living boats carry a masthead lamp that brightens as their ring fills; on a save the lamp blinks twice and
  the boat heels over and turns back out to sea;
- Shades are see-through purple ghost ships with a torn sail and two lantern eyes: they glow, bob in place with
  eyes on the beam while waiting, go red with streaks when lit, shrink grey and furl the sail under rising
  motes when fading, burst in white on a flare, splash purple on the rocks;
- a wrecked boat leaves debris, a foam flash and a thin purple wisp that drifts away;
- the first lit ghost of a session plays a slow-motion lunge; at dawn the ghosts fold their sails and sink
  while the living boats blink their lamps together;
- the HUD LAMP row is drawn as windows (■ lit, □ dark); a lost window blinks purple (drowned) or orange (wreck).
Sounds are not described (personas cannot hear). Pure static helpers; never mutates anything.
Owner: GJ-10 / GJ-14 / GJ-19.
"""
class_name PersonaPerception extends RefCounted

const KIND_SHIP: String = "ship"
const KIND_SHADE: String = "shade"
const STATE_LOST: String = "lost"
const SCREEN_TITLE: String = "title"
const SCREEN_NIGHT: String = "night"
const EVENT_WON: String = "won"
const EVENT_SHADE_FADE: String = "shade_fade"
## Radius bands as a fraction of the reef..spawn span: below NEAR = "close to the rocks", above FAR = "far out".
const BAND_NEAR: float = 0.3
const BAND_FAR: float = 0.7
## Ring fill thresholds for words ("starting to fill" / "about half full" / "nearly full").
const RING_HALF: float = 0.35
const RING_NEARLY: float = 0.7
## Most individual things a glance can take in; the rest are only summarised.
const MAX_DETAILS: int = 3
## Beam-relative bands (radians). Inside the cone: "right where it points" below CENTER_FRACTION of the half width.
const BEAM_CENTER_FRACTION: float = 0.35
## Outside the cone: gap from the cone edge for "just past the edge" / "a little to the side".
const BEAM_JUST_PAST: float = 0.12
const BEAM_A_LITTLE: float = 0.45
## Night progress where the edge sky visibly shifts (matches NightbeamView's DAWN_ROSE_AT).
const SKY_PINK_AT: float = 0.35
const SKY_GOLD_AT: float = 0.75
const PIP_ON: String = "●"
const PIP_OFF: String = "○"
const WINDOW_ON: String = "■"
const WINDOW_OFF: String = "□"
const DIM_ALPHA: float = 0.99
const BOATS_LABEL: String = "Boats (small orange hulls, pale sails, a lamp at the masthead)"
const GHOSTS_LABEL: String = "Ghost ships (see-through purple, twice a boat's size, torn sail, two lantern eyes, soft glow)"


"""Vague amount word a person would use at a glance: one, a couple of, a few, several."""
static func amount(n: int) -> String:
	if n <= 0:
		return "no"
	if n == 1:
		return "one"
	if n == 2:
		return "a couple of"
	if n <= 4:
		return "a few"
	return "several"


# amount() without the trailing "of", for "a couple far out".
static func _glance(n: int) -> String:
	return amount(n).trim_suffix(" of")


"""Screen direction of a polar angle (0 = right, y down) as the nearest clock hour, 1..12."""
static func clock(angle: float) -> int:
	var hour: int = int(round(NightbeamSim.wrap_angle(angle + PI * 0.5) / TAU * 12.0)) % 12
	return 12 if hour == 0 else hour


"""
Where angle sits relative to the beam, in words, or "" if it is not near the beam.
Positive angle_diff = clockwise on screen (the way turn > 0 sweeps the beam).
"""
static func beam_relation(angle: float, beam: float, half_width: float) -> String:
	var diff: float = NightbeamSim.angle_diff(angle, beam)
	var side: String = "clockwise" if diff > 0.0 else "counter-clockwise"
	var off: float = absf(diff)
	if off <= half_width:
		if off < half_width * BEAM_CENTER_FRACTION:
			return "right where the beam points"
		return "in the beam, slightly %s of where it points" % side
	var gap: float = off - half_width
	if gap < BEAM_JUST_PAST:
		return "just past the beam's %s edge" % side
	if gap < BEAM_A_LITTLE:
		return "a little %s of the beam" % side
	return ""


"""Every visible HUD/card string, in draw order, exactly as drawn. Pip rows follow their caption as ●/○ or ■/□."""
static func hud_text(hud: Control) -> Array[String]:
	var out: Array[String] = []
	_collect_text(hud, out)
	return out


static func _collect_text(node: Node, out: Array[String]) -> void:
	for child: Node in node.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		if child is Label:
			for line: String in (child as Label).text.split("\n", false):
				if not line.strip_edges().is_empty():
					out.append(line.strip_edges())
		elif child is HudView.PipRow:
			var row: String = _pip_text(child)
			if out.is_empty():
				out.append(row)
			else:
				out[out.size() - 1] = "%s %s" % [out[out.size() - 1], row]
		_collect_text(child, out)


static func _pip_text(pips: HudView.PipRow) -> String:
	var windows: bool = pips.shape == HudView.PipRow.Shape.WINDOW
	var on: String = WINDOW_ON if windows else PIP_ON
	var off: String = WINDOW_OFF if windows else PIP_OFF
	var row: String = on.repeat(pips.filled) + off.repeat(maxi(pips.count - pips.filled, 0))
	if pips.color_on.a < DIM_ALPHA:
		row += " (dim)"
	if pips.flash_left > 0.0 and pips.flash_index >= 0:
		var color: String = ""
		if pips.flash_color.is_equal_approx(HudView.COLOR_FLASH_SHADE):
			color = " purple"
		elif pips.flash_color.is_equal_approx(HudView.COLOR_FLASH_SHIP):
			color = " orange"
		row += " (a %s blinking%s)" % ["window" if windows else "lamp", color]
	return row


"""
Short, vague description of the bay as a player would see it this moment. screen is "title" | "night" |
"paused" | "end"; on the pause/end card the bay is only glimpsed behind it. beat_id is the ghost in the
first-lunge slow motion (-1 when none). fx carries view-only effects still on screen: "wisp" (a wrecked boat's
wisp drifting away), "dawn_ghosts" (ghosts folding sails and sinking), "dawn_lamps" (boats blinking together).
"""
static func describe_scene(obs: Dictionary, tuning: NightbeamTuning, screen: String, beat_id: int = -1,
		fx: Dictionary = {}) -> String:
	if screen == SCREEN_TITLE:
		return "Behind the card: a dark round bay, a lighthouse in the middle on a grey blob of rock, its yellow beam resting."
	var parts: PackedStringArray = []
	if screen != SCREEN_NIGHT:
		parts.append("Partly hidden behind the card:")
	var beam_on: bool = String(obs.get("state", "")) != STATE_LOST
	var beam: float = float(obs.get("beam_angle", 0.0))
	if beam_on:
		parts.append("The yellow beam points toward about %d o'clock; where it crosses the rock around the lighthouse the rock shows pale, with jagged teeth and white foam, the rest stays a dark grey blob." % clock(beam))
	else:
		parts.append("The lighthouse is dark; no beam; the rock is a dark grey blob.")
	var ships: Array = []
	var saved_ships: int = 0
	var shades: Array = []
	for e: Dictionary in obs.get("entities", []):
		if String(e.get("kind", "")) == KIND_SHADE:
			shades.append(e)
		elif bool(e.get("saved", false)):
			saved_ships += 1
		else:
			ships.append(e)
	parts.append(_ship_line(ships, tuning))
	parts.append(_shade_line(shades, tuning))
	if beam_on:
		parts.append(_near_beam_line(ships, shades, beam, tuning))
	if beat_id >= 0:
		parts.append("Everything has slowed down: a red ring pulses around a ghost ship, its lantern eyes wide, and a red dotted line runs from it to the rocks.")
	var fading_rings: int = 0
	for e: Dictionary in ships:
		if not bool(e.get("lit", false)) and float(e.get("guidance", 0.0)) > 0.0:
			fading_rings += 1
	if fading_rings > 0:
		parts.append("Outside the beam, %s %s a part-filled yellow ring." % [amount(fading_rings), "boat has" if fading_rings == 1 else "boats have"])
	if saved_ships > 0:
		parts.append("%s %s with a green ring, white sail and lit masthead lamp heading back out to sea." % [amount(saved_ships).capitalize(), "boat" if saved_ships == 1 else "boats"])
	if bool(fx.get("wisp", false)):
		parts.append("A thin purple wisp is drifting away from the rocks.")
	if bool(fx.get("dawn_ghosts", false)):
		parts.append("Ghost ships are folding their sails and sinking in purple motes.")
	if bool(fx.get("dawn_lamps", false)):
		parts.append("The boats' masthead lamps blink together.")
	parts.append(_sky_line(float(obs.get("time", 0.0)) / tuning.dawn_time))
	return " ".join(parts)


static func _ship_line(ships: Array, tuning: NightbeamTuning) -> String:
	if ships.is_empty():
		return "%s: none." % BOATS_LABEL
	return "%s: %s." % [BOATS_LABEL, _band_summary(ships, tuning)]


# Ghosts by what they look like: drifting in, waiting (bob, eyes on the beam), lit (in the near-beam line), fading.
static func _shade_line(shades: Array, tuning: NightbeamTuning) -> String:
	if shades.is_empty():
		return "%s: none." % GHOSTS_LABEL
	var drifting: Array = []
	var waiting: Array = []
	var lit: int = 0
	var fading: int = 0
	for e: Dictionary in shades:
		if bool(e.get("fading", false)):
			fading += 1
		elif bool(e.get("lit", false)):
			lit += 1
		elif is_holding(e, tuning):
			waiting.append(e)
		else:
			drifting.append(e)
	var bits: PackedStringArray = []
	if not drifting.is_empty():
		bits.append("drifting in: %s" % _band_summary(drifting, tuning))
	if not waiting.is_empty():
		bits.append("%s bobbing in place at mid-distance around %s o'clock, lantern eyes following the beam" % [_glance(waiting.size()), ", ".join(_hours(waiting))])
	if lit > 0:
		bits.append("%s lit up red" % _glance(lit))
	if fading > 0:
		bits.append("%s shrinking, turning grey and furling %s sail while purple motes rise" % [_glance(fading), "its" if fading == 1 else "their"])
	return "%s: %s." % [GHOSTS_LABEL, "; ".join(bits)]


"""True if a Shade looks like it is waiting (dark, not fading, not moving in): the view's 'holding' look."""
static func is_holding(e: Dictionary, tuning: NightbeamTuning) -> bool:
	if bool(e.get("lit", false)) or bool(e.get("fading", false)):
		return false
	return float(e.get("speed", 1.0)) <= NightbeamView.SHADE_HOLD_SPEED_EPS \
		or float(e.get("radius", 0.0)) <= tuning.shade_hold_radius + NightbeamView.SHADE_HOLD_SPEED_EPS


# Anything in or near the beam, closest to its centre first, described relative to the beam.
static func _near_beam_line(ships: Array, shades: Array, beam: float, tuning: NightbeamTuning) -> String:
	var near: Array = []
	for e: Dictionary in ships + shades:
		if bool(e.get("fading", false)):
			continue
		var rel: String = beam_relation(float(e.get("angle", 0.0)), beam, tuning.beam_half_width)
		if not rel.is_empty():
			near.append({"e": e, "rel": rel, "off": absf(NightbeamSim.angle_diff(float(e.get("angle", 0.0)), beam))})
	if near.is_empty():
		return "Nothing is in or near the beam."
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["off"] < b["off"])
	var bits: PackedStringArray = []
	for item: Dictionary in near.slice(0, MAX_DETAILS):
		bits.append("%s, %s" % [_near_thing(item["e"], tuning), item["rel"]])
	if near.size() > MAX_DETAILS:
		bits.append("and more")
	return "In or near the beam: %s." % "; ".join(bits)


static func _near_thing(e: Dictionary, tuning: NightbeamTuning) -> String:
	var where: String = _band_word(float(e.get("radius", 0.0)), tuning)
	if String(e.get("kind", "")) == KIND_SHADE:
		if bool(e.get("lit", false)):
			return "a ghost ship %s with a red outline and streaks, rushing toward the lighthouse" % where
		if is_holding(e, tuning):
			return "a ghost ship bobbing in place %s, lantern eyes on the beam" % where
		return "a ghost ship drifting in %s" % where
	if bool(e.get("lit", false)):
		var fill: float = float(e.get("guidance", 0.0))
		return "a boat %s outlined in yellow, %s, %s" % [where, _ring_words(fill), _lamp_words(fill)]
	return "a boat %s" % where


static func _band_summary(group: Array, tuning: NightbeamTuning) -> String:
	# Every band gets rough clock positions: a player sees where things are and needs that to aim.
	var bands: Array = [[], [], []]
	for e: Dictionary in group:
		bands[_band(float(e.get("radius", 0.0)), tuning)].append(e)
	var bits: PackedStringArray = []
	for band: int in [2, 1, 0]:
		var members: Array = bands[band]
		if not members.is_empty():
			bits.append("%s %s (around %s o'clock)" % [_glance(members.size()), _band_name(band), ", ".join(_hours(members))])
	return ", ".join(bits)


static func _hours(group: Array) -> PackedStringArray:
	var hours: PackedStringArray = []
	for e: Dictionary in group.slice(0, MAX_DETAILS):
		var h: String = str(clock(float(e.get("angle", 0.0))))
		if not hours.has(h):
			hours.append(h)
	return hours


static func _ring_words(fill: float) -> String:
	if fill <= 0.0:
		return "no ring yet"
	if fill < RING_HALF:
		return "a yellow ring around it starting to fill"
	if fill < RING_NEARLY:
		return "its yellow ring about half full"
	return "its yellow ring nearly full"


# The masthead lamp brightens with the ring (StoryFx.ship_lamp): dim, brighter, bright.
static func _lamp_words(fill: float) -> String:
	if fill < RING_HALF:
		return "its masthead lamp dim"
	if fill < RING_NEARLY:
		return "its masthead lamp brightening"
	return "its masthead lamp bright"


static func _sky_line(progress: float) -> String:
	if progress < SKY_PINK_AT:
		return "The sky at the screen edges is deep navy."
	if progress < SKY_GOLD_AT:
		return "The sky at the screen edges has a faint pink tint."
	return "The sky at the screen edges is turning gold."


# 0 = close to the rocks, 1 = midway, 2 = far out.
static func _band(radius: float, tuning: NightbeamTuning) -> int:
	var t: float = (radius - tuning.reef_radius) / maxf(tuning.spawn_radius - tuning.reef_radius, 1.0)
	if t < BAND_NEAR:
		return 0
	if t < BAND_FAR:
		return 1
	return 2


static func _band_word(radius: float, tuning: NightbeamTuning) -> String:
	return _band_name(_band(radius, tuning))


static func _band_name(band: int) -> String:
	match band:
		0:
			return "close to the rocks"
		1:
			return "midway in"
	return "far out"


"""
What a player would notice for one tick's sim events (no causes, no ids). Needs the whole tick because at
dawn the same shade_fade event looks different (ghosts fold their sails and sink). any_boats = living boats
were on screen that tick (only then can a player see their lamps blink together at dawn).
"""
static func tick_phrases(events: Array, any_boats: bool = true) -> Array[String]:
	var dawn: bool = false
	for event: Dictionary in events:
		if String(event.get("type", "")) == EVENT_WON:
			dawn = true
	var out: Array[String] = []
	for event: Dictionary in events:
		var phrase: String = event_phrase(event, dawn)
		if not phrase.is_empty():
			out.append(phrase)
	if dawn and any_boats:
		out.append("the boats' masthead lamps blinked together")
	return out


"""What a player would notice for one sim event, or "" if nothing visible. dawn = the night was just won."""
static func event_phrase(event: Dictionary, dawn: bool = false) -> String:
	var at: int = clock(float(event.get("angle", 0.0)))
	var kind: String = String(event.get("kind", ""))
	match String(event.get("type", "")):
		"saved":
			return "a boat's ring turned green, its masthead lamp blinked twice, and it heeled over and turned back out to sea"
		"wreck":
			if kind == KIND_SHADE:
				return "a ghost ship splashed purple onto the rocks at about %d o'clock; the whole rock flashed purple" % at
			return "a boat broke up on the rocks at about %d o'clock: debris, a white foam flash, the screen shook, then a thin purple wisp rose from it" % at
		"shade_fade":
			if dawn:
				return "a ghost ship folded its sail and sank in purple motes"
			return "a ghost ship shrank, went grey, furled its sail and vanished as purple motes rose from it"
		"shade_flared":
			return "a ghost ship burst apart in a white ring with rays"
		"flare":
			return "a white ring burst out from the lighthouse"
		"spawn":
			return "a ghost ship appeared at the edge of the bay" if kind == KIND_SHADE else "a boat appeared at the edge of the bay"
		"won":
			return "the sky turned gold"
		"lost":
			return "the lighthouse lamp went out"
	return ""


"""The first-lunge slow motion as a player would describe it afterwards."""
static func lunge_beat_phrase() -> String:
	return "time slowed for a moment: a red ring pulsed around a ghost ship in the beam, its lantern eyes went wide, and a red dotted line pointed from it to the rocks"


"""Joins accumulated event phrases with vague repeat counts ("... (a few times)")."""
static func summarize_events(counts: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for phrase: String in counts:
		var n: int = int(counts[phrase])
		if n == 1:
			out.append(phrase)
		else:
			out.append("%s (%s times)" % [phrase, _glance(n)])
	return out
