"""
All player-facing copy in one place (Framing.md option A "The Drowned", picked by Boss in GJ-17).
The HUD and cards read these constants; change wording here, not in the UI code. Owner: view (GJ-18).
"""
class_name NightbeamStrings extends RefCounted

# --- Title card (Framing.md: at most 3 short lines) ---
const GAME_TITLE: String = "NIGHTBEAM"
const TAGLINE: String = "The old lamp's last night. The reef remembers."
const TEACHING_LINE: String = "Light shows ships the rocks, and calls the drowned."
const TITLE_SEED: String = "SEED %d"
const TITLE_START_HINT: String = "Space to light    N new seed"
const CONTROLS_HINT: String = "A / D or ← / → turn the beam    Space flare    Esc pause"

# --- End cards ---
const WIN_TITLE: String = "Dawn. The drowned go back to sleep."
const WIN_SUBTITLE: String = "The new lamp can have the morning."
const LOSE_TITLE: String = "The lamp goes out. The reef keeps them all."
const END_SAVED: String = "Ships saved  %d"
## Lamp lights lost, split by cause: living ships wrecked vs the drowned (Shades) reaching the rock.
const END_LIGHTS_LOST: String = "Lamp lights lost: %d to wrecks · %d to the drowned"
const END_SCORE: String = "Score  %d"
const END_SEED: String = "SEED %d"
const END_HINT: String = "[R] retry same seed    [N] new night"

# --- Pause card ---
const PAUSE_TITLE: String = "PAUSED"
const PAUSE_BODY: String = "The sea waits."
const PAUSE_HINT: String = "Esc resume    R retry same seed    N new night"

# --- HUD ---
const HUD_LAMP: String = "LAMP"
const HUD_FLARE: String = "FLARE"
const HUD_SAVED: String = "SAVED %d"
const HUD_SCORE: String = "SCORE %d"
const HUD_DAWN_IN: String = "DAWN IN %s"
