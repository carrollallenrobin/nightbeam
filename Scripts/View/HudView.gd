"""
Minimal HUD and flow cards, built from containers so it follows the 960x540 canvas_items stretch.
- Top-left: the LAMP as 5 window lights (one goes out per reef hit), flare charges as pips, ships saved.
- Top-centre: night clock (time left to dawn). Top-right: score.
- Centre card: title (name, the "Drowned" tagline and teaching line) / pause / end card (win or lose line,
  saved, lamp lights lost to wrecks vs the drowned, score, seed, R / N hints).
- A lost window light blinks (purple when a Shade took it, orange for a wreck) via flash_lost_hull().
All copy lives in NightbeamStrings (Framing.md option A). Reads the observation only; never mutates the sim.
Owner: view (GJ-5, GJ-13, GJ-18).
"""
class_name HudView extends Control

const COLOR_TEXT: Color = Color("#F7F1E1")
const COLOR_TEXT_DIM: Color = Color(0.97, 0.95, 0.88, 0.6)
const COLOR_LAMP_ON: Color = Color("#FFD98A")
const COLOR_LAMP_OFF: Color = Color("#1E2742")
const COLOR_PIP_OFF: Color = Color(1.0, 1.0, 1.0, 0.15)
const COLOR_FLARE_ON: Color = Color("#FFFFFF")
const COLOR_WON: Color = Color("#7BE0AD")
const COLOR_LOST: Color = Color("#FF4D6D")
const COLOR_TITLE: Color = Color("#FFD166")
const COLOR_CARD_BG: Color = Color(0.024, 0.047, 0.11, 0.88)
const COLOR_CARD_BORDER: Color = Color(1.0, 0.91, 0.66, 0.45)
const COLOR_TEACH: Color = Color("#FFE9A8")
const COLOR_FLASH_SHADE: Color = Color("#A97BFF")
const COLOR_FLASH_SHIP: Color = Color("#FF8A5C")

const MARGIN: int = 14
const ROW_SEPARATION: int = 6
const FONT_SMALL: int = 13
const FONT_HUD: int = 16
const FONT_CARD_BODY: int = 16
const FONT_CARD_TITLE: int = 40
const FONT_END_TITLE: int = 28
const FONT_TEACH: int = 20
const PIP_FLASH_TIME: float = 1.2
const CARD_PADDING: int = 24
const CARD_BORDER_WIDTH: int = 2
const CARD_CORNER_RADIUS: int = 8
const PIP_RADIUS: float = 6.0
const PIP_GAP: float = 5.0
const CAPTION_WIDTH: float = 44.0
const WINDOW_SIZE: Vector2 = Vector2(10.0, 14.0)
const WINDOW_GAP: float = 5.0

const STATE_WON: String = "won"


"""
Row of pips: round (flare charges) or lit windows (the LAMP). Draws `count` pips, the first `filled` lit;
a flashing pip blinks in flash_color (the light that just went out).
"""
class PipRow extends Control:
	enum Shape { ROUND, WINDOW }

	var count: int = 0
	var filled: int = 0
	var color_on: Color = Color.WHITE
	var color_off: Color = Color(1.0, 1.0, 1.0, 0.15)
	var radius: float = 6.0
	var gap: float = 5.0
	var shape: Shape = Shape.ROUND
	var window_size: Vector2 = Vector2(10.0, 14.0)
	var flash_index: int = -1
	var flash_color: Color = Color.WHITE
	var flash_left: float = 0.0
	var flash_hz: float = 6.0

	func _init(p_color_on: Color, p_color_off: Color, p_radius: float, p_gap: float) -> void:
		color_on = p_color_on
		color_off = p_color_off
		radius = p_radius
		gap = p_gap
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	"""Switches the row to lit-window pips of the given size (the keeper's LAMP)."""
	func use_windows(p_size: Vector2) -> void:
		shape = Shape.WINDOW
		window_size = p_size
		_resize()

	"""Sets how many pips exist and how many are lit; resizes and redraws only on change."""
	func set_pips(p_count: int, p_filled: int) -> void:
		if p_count == count and p_filled == filled:
			return
		count = p_count
		filled = p_filled
		_resize()
		queue_redraw()

	"""Blinks pip `index` in `color` for `duration` seconds (a just-lost lamp light)."""
	func flash(index: int, color: Color, duration: float) -> void:
		flash_index = index
		flash_color = color
		flash_left = duration
		queue_redraw()

	"""Advances the flash timer (called from HudView._process)."""
	func tick_flash(delta: float) -> void:
		if flash_left <= 0.0:
			return
		flash_left = maxf(flash_left - delta, 0.0)
		queue_redraw()

	func _resize() -> void:
		if shape == Shape.WINDOW:
			custom_minimum_size = Vector2(count * (window_size.x + gap), window_size.y + 2.0)
		else:
			custom_minimum_size = Vector2(count * (radius * 2.0 + gap), radius * 2.0 + 2.0)

	func _draw() -> void:
		for i: int in count:
			var color: Color = color_on if i < filled else color_off
			var flashing: bool = i == flash_index and flash_left > 0.0
			if flashing:
				color = flash_color if fmod(flash_left * flash_hz, 1.0) > 0.35 else color_off
			if shape == Shape.WINDOW:
				_draw_window(i, color, flashing, i < filled)
			else:
				var c: Vector2 = Vector2(radius + i * (radius * 2.0 + gap), size.y * 0.5)
				if flashing:
					draw_arc(c, radius + 2.5, 0.0, TAU, 20, Color(flash_color, 0.8), 1.5, true)
				draw_circle(c, radius, color)

	# A tall window with an arched top feel: glow when lit, a cross of glazing bars, a thin frame.
	func _draw_window(i: int, color: Color, flashing: bool, lit: bool) -> void:
		var top_left: Vector2 = Vector2(i * (window_size.x + gap), (size.y - window_size.y) * 0.5)
		var rect: Rect2 = Rect2(top_left, window_size)
		if lit and not flashing:
			draw_rect(rect.grow(2.0), Color(color, 0.25))
		if flashing:
			draw_rect(rect.grow(2.0), Color(flash_color, 0.8), false, 1.5)
		draw_rect(rect, color)
		var bar: Color = Color(0.08, 0.1, 0.18, 0.9)
		draw_line(Vector2(rect.get_center().x, rect.position.y), Vector2(rect.get_center().x, rect.end.y), bar, 1.0)
		draw_line(Vector2(rect.position.x, rect.position.y + rect.size.y * 0.45),
				Vector2(rect.end.x, rect.position.y + rect.size.y * 0.45), bar, 1.0)
		draw_rect(rect, Color(0.85, 0.8, 0.7, 0.5), false, 1.0)


var tuning: NightbeamTuning = null
var _obs: Dictionary = {}

var _top_bar: MarginContainer = null
var _hull_pips: PipRow = null
var _flare_pips: PipRow = null
var _saved_label: Label = null
var _clock_label: Label = null
var _score_label: Label = null
var _card: PanelContainer = null
var _card_title: Label = null
var _card_body: Label = null
var _card_sub: Label = null
var _card_teach: Label = null
var _card_hint: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_card()


func _process(delta: float) -> void:
	if _hull_pips != null:
		_hull_pips.tick_flash(delta)


"""Sets the tuning used for pip counts and the dawn clock. Called once by GameFlow."""
func configure(p_tuning: NightbeamTuning) -> void:
	tuning = p_tuning


"""Stores the latest observation and refreshes the HUD numbers. Never mutates the sim."""
func show_observation(obs: Dictionary) -> void:
	_obs = obs
	if tuning == null or _hull_pips == null:
		return
	_hull_pips.set_pips(tuning.hull_max, int(obs.get("hull", 0)))
	var cooling: bool = float(obs.get("flare_cd", 0.0)) > 0.0
	_flare_pips.color_on = Color(COLOR_FLARE_ON, 0.5) if cooling else COLOR_FLARE_ON
	_flare_pips.set_pips(tuning.flare_max_charges, int(obs.get("flare_charges", 0)))
	_flare_pips.queue_redraw()
	_saved_label.text = NightbeamStrings.HUD_SAVED % int(obs.get("saved", 0))
	_score_label.text = NightbeamStrings.HUD_SCORE % int(obs.get("score", 0))
	var left: float = maxf(tuning.dawn_time - float(obs.get("time", 0.0)), 0.0)
	_clock_label.text = NightbeamStrings.HUD_DAWN_IN % _format_clock(left)


"""Title card, three short lines (Framing.md): name, tagline, teaching line; then seed and controls."""
func show_title(night_seed: int) -> void:
	_top_bar.visible = false
	_show_card(NightbeamStrings.GAME_TITLE, COLOR_TITLE, FONT_CARD_TITLE, NightbeamStrings.TAGLINE, "",
			"%s\n\n%s\n%s" % [NightbeamStrings.TITLE_SEED % night_seed, NightbeamStrings.TITLE_START_HINT,
				NightbeamStrings.CONTROLS_HINT])
	_card_teach.text = NightbeamStrings.TEACHING_LINE
	_card_teach.visible = true


"""Blinks the lamp light that was just lost: purple for a Shade hit, orange for a ship wreck (GJ-11)."""
func flash_lost_hull(hull_left: int, by_shade: bool) -> void:
	if _hull_pips == null:
		return
	_hull_pips.flash(hull_left, COLOR_FLASH_SHADE if by_shade else COLOR_FLASH_SHIP, PIP_FLASH_TIME)


"""Hides every card and shows the HUD bar while a night is being played."""
func show_night() -> void:
	_hull_pips.flash_left = 0.0   # a blink from the previous night must not carry into a retry
	_top_bar.visible = true
	_card.visible = false


"""Shows or hides the pause card."""
func show_paused(paused: bool) -> void:
	if paused:
		_show_card(NightbeamStrings.PAUSE_TITLE, COLOR_TEXT, FONT_CARD_TITLE, NightbeamStrings.PAUSE_BODY, "",
				NightbeamStrings.PAUSE_HINT)
	else:
		_card.visible = false


"""
End card for a finished night: the win or lose line (Framing.md option A), ships saved, lamp lights lost
split into wrecks vs the drowned (from the run's wreck events, counted by GameFlow), score, seed, R / N.
"""
func show_end(obs: Dictionary, night_seed: int, lost_to_ships: int, lost_to_shades: int) -> void:
	var won: bool = String(obs.get("state", "")) == STATE_WON
	var body: String = "\n".join([
		NightbeamStrings.END_SAVED % int(obs.get("saved", 0)),
		NightbeamStrings.END_LIGHTS_LOST % [lost_to_ships, lost_to_shades],
		NightbeamStrings.END_SCORE % int(obs.get("score", 0)),
		"",
		NightbeamStrings.END_SEED % night_seed,
	])
	_show_card(NightbeamStrings.WIN_TITLE if won else NightbeamStrings.LOSE_TITLE,
			COLOR_WON if won else COLOR_LOST, FONT_END_TITLE,
			NightbeamStrings.WIN_SUBTITLE if won else "", body, NightbeamStrings.END_HINT)


# Card rows: title, sub line (tagline / win subtitle), accent teaching line (title card only), body, hint.
# Empty rows are hidden so the card stays compact.
func _show_card(title: String, title_color: Color, title_size: int, sub: String, body: String, hint: String) -> void:
	_card_title.text = title
	_card_title.add_theme_color_override("font_color", title_color)
	_card_title.add_theme_font_size_override("font_size", title_size)
	_card_sub.text = sub
	_card_sub.visible = not sub.is_empty()
	_card_body.text = body
	_card_body.visible = not body.is_empty()
	_card_hint.text = hint
	_card_teach.visible = false
	_card.visible = true


func _format_clock(seconds: float) -> String:
	var whole: int = ceili(seconds)
	return "%d:%02d" % [whole / 60, whole % 60]


# --- UI construction ----------------------------------------------------------

func _build_top_bar() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["margin_left", "margin_right", "margin_top"]:
		margin.add_theme_constant_override(side, MARGIN)
	add_child(margin)
	_top_bar = margin

	var bar: HBoxContainer = HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(bar)

	var left: VBoxContainer = VBoxContainer.new()
	left.add_theme_constant_override("separation", ROW_SEPARATION)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(left)
	_hull_pips = PipRow.new(COLOR_LAMP_ON, COLOR_LAMP_OFF, PIP_RADIUS, WINDOW_GAP)
	_hull_pips.use_windows(WINDOW_SIZE)
	left.add_child(_pip_line(NightbeamStrings.HUD_LAMP, _hull_pips))
	_flare_pips = PipRow.new(COLOR_FLARE_ON, COLOR_PIP_OFF, PIP_RADIUS * 0.75, PIP_GAP)
	left.add_child(_pip_line(NightbeamStrings.HUD_FLARE, _flare_pips))
	_saved_label = _make_label(FONT_HUD, COLOR_TEXT)
	left.add_child(_saved_label)

	_clock_label = _make_label(FONT_HUD, COLOR_TEXT)
	_clock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_clock_label)

	_score_label = _make_label(FONT_HUD, COLOR_TEXT)
	_score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_score_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_score_label)


func _pip_line(caption: String, pips: PipRow) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEPARATION)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label: Label = _make_label(FONT_SMALL, COLOR_TEXT_DIM)
	label.text = caption
	label.custom_minimum_size.x = CAPTION_WIDTH
	row.add_child(label)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pips)
	return row


func _build_card() -> void:
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_CARD_BG
	style.border_color = COLOR_CARD_BORDER
	style.set_border_width_all(CARD_BORDER_WIDTH)
	style.set_corner_radius_all(CARD_CORNER_RADIUS)
	style.set_content_margin_all(CARD_PADDING)
	_card.add_theme_stylebox_override("panel", style)
	center.add_child(_card)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", ROW_SEPARATION * 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(column)
	_card_title = _make_label(FONT_CARD_TITLE, COLOR_TITLE)
	_card_sub = _make_label(FONT_CARD_BODY, COLOR_TEXT)
	_card_teach = _make_label(FONT_TEACH, COLOR_TEACH)
	_card_body = _make_label(FONT_CARD_BODY, COLOR_TEXT)
	_card_hint = _make_label(FONT_SMALL, COLOR_TEXT_DIM)
	for label: Label in [_card_title, _card_sub, _card_teach, _card_body, _card_hint]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
	_card.visible = false


func _make_label(font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
