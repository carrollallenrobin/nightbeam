"""
Static _draw() helpers for the two ship silhouettes (Framing.md option A "The Drowned"): the warm living
ship with its masthead lamp, and the see-through purple ghost ship with a torn sail. Pure drawing: callers
pass a CanvasItem and every pose value, so the helpers hold no state and never touch the sim.
Owner: view (GJ-18).
"""
class_name ShipShapes extends RefCounted

# --- Living ship ---
const SHIP_LENGTH: float = 16.0
const SHIP_BEAM: float = 7.0
const SAIL_SIZE: float = 8.0
## How much narrower the hull reads (top-down) at full heel while a saved ship turns away.
const HEEL_NARROWING: float = 0.45
const MAST_FORWARD: float = 1.5
const LAMP_RADIUS: float = 2.2
const LAMP_GLOW_RADIUS: float = 7.5
const COLOR_HULL: Color = Color("#F2A65A")
const COLOR_SAIL: Color = Color("#F7F1E1")
const COLOR_SAIL_SAVED: Color = Color("#FFFFFF")
const COLOR_LAMP: Color = Color("#FFE08A")
const COLOR_LAMP_DIM: Color = Color("#6B5A3A")

# --- Ghost ship: the living silhouette, scaled up and drawn see-through in purple ---
const GHOST_SCALE: float = 2.0
const GHOST_LENGTH: float = SHIP_LENGTH * GHOST_SCALE
const GHOST_FILL_ALPHA: float = 0.3
const GHOST_EDGE_WIDTH: float = 2.0
const GHOST_SAIL_ALPHA: float = 0.5
## Ragged hypotenuse of the torn sail: inset (0..1 toward the mast) per notch, from the bow tip outward.
const TORN_EDGE: PackedFloat32Array = [0.0, 0.3, 0.05, 0.4, 0.1, 0.35, 0.0]


"""
Living ship: hull + sail + masthead lamp. heading in radians; heel 0..1 narrows the hull and leans the
sail (the saved ship turning away); lamp 0..1 is the masthead lamp brightness.
"""
static func draw_living_ship(ci: CanvasItem, pos: Vector2, heading: float, heel: float, alpha: float,
		saved: bool, lamp: float) -> void:
	var fwd: Vector2 = Vector2.from_angle(heading)
	var side: Vector2 = fwd.orthogonal() * (1.0 - HEEL_NARROWING * heel)
	var hull: PackedVector2Array = PackedVector2Array([
		pos + fwd * SHIP_LENGTH * 0.5,
		pos + side * SHIP_BEAM * 0.5 - fwd * SHIP_LENGTH * 0.2,
		pos - fwd * SHIP_LENGTH * 0.5 + side * SHIP_BEAM * 0.35,
		pos - fwd * SHIP_LENGTH * 0.5 - side * SHIP_BEAM * 0.35,
		pos - side * SHIP_BEAM * 0.5 - fwd * SHIP_LENGTH * 0.2,
	])
	ci.draw_colored_polygon(hull, Color(COLOR_HULL, alpha))
	var sail_side: Vector2 = fwd.orthogonal() * (1.0 + heel * 0.3)
	var sail: PackedVector2Array = PackedVector2Array([
		pos + fwd * SAIL_SIZE * 0.6,
		pos - fwd * SAIL_SIZE * 0.4 + sail_side * SAIL_SIZE * 0.9,
		pos - fwd * SAIL_SIZE * 0.4,
	])
	ci.draw_colored_polygon(sail, Color(COLOR_SAIL_SAVED if saved else COLOR_SAIL, alpha))
	var mast: Vector2 = pos + fwd * MAST_FORWARD
	if lamp > 0.05:
		ci.draw_circle(mast, LAMP_GLOW_RADIUS * lamp, Color(COLOR_LAMP, 0.35 * lamp * alpha))
	ci.draw_circle(mast, LAMP_RADIUS, Color(COLOR_LAMP_DIM.lerp(COLOR_LAMP, lamp), alpha))


"""
Ghost ship (a Shade): the same hull and sail as a living ship, twice the size, see-through purple, with a
torn sail and a mast line. scale shrinks it (fade / dawn sink); sail_fold 0..1 furls the sail against the
mast; edge is the outline colour (red while lit).
"""
static func draw_ghost_ship(ci: CanvasItem, pos: Vector2, heading: float, scale: float, alpha: float,
		body: Color, edge: Color, sail_fold: float) -> void:
	var fwd: Vector2 = Vector2.from_angle(heading)
	var side: Vector2 = fwd.orthogonal()
	var length: float = GHOST_LENGTH * scale
	var beam: float = SHIP_BEAM * GHOST_SCALE * scale
	var hull: PackedVector2Array = PackedVector2Array([
		pos + fwd * length * 0.5,
		pos + side * beam * 0.5 - fwd * length * 0.2,
		pos - fwd * length * 0.5 + side * beam * 0.35,
		pos - fwd * length * 0.5 - side * beam * 0.35,
		pos - side * beam * 0.5 - fwd * length * 0.2,
	])
	ci.draw_colored_polygon(hull, Color(body, GHOST_FILL_ALPHA * alpha))
	var outline: PackedVector2Array = hull.duplicate()
	outline.append(hull[0])
	ci.draw_polyline(outline, Color(edge, alpha), GHOST_EDGE_WIDTH, true)
	var sail_size: float = SAIL_SIZE * GHOST_SCALE * scale
	var head: Vector2 = pos + fwd * sail_size * 0.6
	var foot: Vector2 = pos - fwd * sail_size * 0.4
	ci.draw_line(head, foot, Color(edge, 0.7 * alpha), 1.2, true)
	var reach: float = sail_size * 0.9 * (1.0 - sail_fold)
	if reach < 0.5:
		return
	# Torn sail: the living ship's triangle with a ragged outer edge (bow tip -> clew -> foot).
	var clew: Vector2 = foot + side * reach
	var sail: PackedVector2Array = PackedVector2Array()
	var notches: int = TORN_EDGE.size()
	for i: int in notches:
		var u: float = float(i) / float(notches - 1)
		var on_edge: Vector2 = head.lerp(clew, u)
		var toward_mast: Vector2 = head.lerp(foot, u)
		sail.append(on_edge.lerp(toward_mast, TORN_EDGE[i]))
	sail.append(foot)
	ci.draw_colored_polygon(sail, Color(body.lightened(0.3), GHOST_SAIL_ALPHA * alpha))
	var sail_edge: PackedVector2Array = sail.duplicate()
	sail_edge.append(sail[0])
	ci.draw_polyline(sail_edge, Color(edge, 0.7 * alpha), 1.0, true)
