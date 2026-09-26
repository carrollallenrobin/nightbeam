# NIGHTBEAM: Framing Options (GJ-17)

**Problem (Boss playtest):** the mechanics read (light a Shade and it lunges; the fade is fine), but
the fiction doesn't. Nothing on screen says who the keeper is, why a lit ship leaves, what a Shade
is, or why Shades are here tonight.

**Fixed for every option:** mechanics, numbers, lanes, entity count and tick order stay as GJ-11/GJ-12
approved. Every change below is copy or `_draw()`/synth view work. No sim changes and no external
assets. Title text stays at 3 short lines at most.

---

## Shared cue (use with any option): "the ship sees the reef"
A real lighthouse doesn't pull ships in. It shows them the rocks so they turn away. Today a lit ship
just fills a ring and reverses. Three view-only beats make the warning visible:
1. **Rocks show under the beam.** Where the beam crosses the reef ring (r = 48), draw a short arc
   of white breaker foam and 3-4 jagged rock teeth. In the dark the reef is only the grey blob.
   Lighting it shows it's dangerous.
2. **The ship answers.** While a ship's guidance fills, a small lamp at its masthead brightens.
   On save it blinks twice (a "seen you" reply), the hull heels over and turns outward in a short
   arc instead of snapping, and the green ring shows.
3. **A wreck looks like a wreck.** This is already in: foghorn, debris, and the foam flashes on the
   rock where the ship hit.

---

## Option A: "The Drowned" (folk ghost story)
**Premise.** For a hundred years this reef sank ships in the dark, until your lamp was built.
Tonight the old lamp burns for the last time, and everything the reef ever took has come back to
see it once more.

**Shades.** Ghost ships of this reef's own wrecks. They look like their living cousins drawn in
purple, with torn sails, a hull outline you can see through, and two lanterns for eyes.

**Why the light saves ships and calls Shades (one reason).** The light says *"here is the rock."*
The living see the rock and turn. The drowned can't see rocks any more. They only see the light
they were looking for when they sank, so they sail straight for it.

**Tone.** Quiet and a little sad, like a sea shanty. Not horror. The Shades aren't evil, just lost.

**Title card**
> NIGHTBEAM
> The old lamp's last night. The reef remembers.
> Light shows ships the rocks, and calls the drowned.

**End cards**
- Win: **"Dawn. The drowned go back to sleep."** (sub: "The new lamp can have the morning.")
- Lose: **"The lamp goes out. The reef keeps them all."**

**Visual cues**
1. **Shades are ships.** Draw each Shade as a faint purple hull and ragged sail around the existing
   wavy blob, with its two eyes as masthead lanterns. Players read "ghost ship" at a glance, next to
   the warm living ships.
2. **Wrecks leave ghosts (view only).** When a ship wrecks, a thin purple wisp rises from the debris
   and drifts off-screen. This doesn't spawn anything in the sim. It links "ship lost" to "Shade"
   without any text.
3. **Resting, not vanishing.** The existing dark fade (desaturate, motes rising, sigh) now reads as
   a ghost laid to rest. Leaving a Shade in the dark is kind to it.
4. **Dawn lays them all down.** At dawn every Shade's sail folds and it sinks, and the living ships
   on screen blink their lamps together.

**HUD copy (optional string change).** HULL → **LAMP**, drawn as 5 window lights. A wreck or a
Shade reaching the rock puts one out. That fits the existing "THE LAMP GOES OUT" loss card.

---

## Option B: "Lampfish" (creature feature)
**Premise.** On the one moonless night each year, the lampfish rise from the trench beyond the reef
to feed. They eat light, and your lamp is the brightest thing on the sea.

**Shades.** Deep-sea eaters about the size of a rowboat: a round purple body, two big eyes and a
wide jaw. Think anglerfish that hunt light instead of hunting with it.

**Why the light saves ships and calls Shades (one reason).** Light is a signal. Ships read it as
"rocks here" and steer clear. Lampfish read it as "food here" and lunge up the beam to the lamp.
In the dark they have nothing to chase, so they idle and sink back down.

**Tone.** Eerie and a little cozy, like a nature documentary at night. Tense but never gory.

**Title card**
> NIGHTBEAM
> No moon tonight. The lampfish are rising.
> Light shows ships the rocks, and feeds the lampfish.

**End cards**
- Win: **"Dawn. The lampfish sink, full of nothing."**
- Lose: **"The lampfish ate the light."**

**Visual cues**
1. **Jaws, not a blob.** The existing blob gets a jaw line. Holding in the dark, it's shut. When
   lit, it gapes and the eyes lock on the lamp, so the lunge reads as "it's hungry."
2. **Bitten lamp.** A Shade hit makes one lamp pip on the tower dim with a bite-shaped notch, and
   the tower light flickers once. It reads as eaten, not crashed.
3. **Sinking, not fading.** The dark fade goes downward: the Shade shrinks, darkens and gives off
   bubbles (the existing motes, drawn as rings) as it drops back into the trench.
4. **Dim bait lights far out.** Faint purple specks flicker at the bay edge just before a Shade
   spawns. The deep is full of them, which answers "why here, why tonight."

**HUD copy (optional).** HULL → **LAMP**. Weakness: a ship wreck costing a lamp pip is only
loosely explained ("the keeper's watch failed").

---

## Option C: "Wreckers" (grounded coastal thriller)
**Premise.** You keep the light on a coast of wreckers, people who lure ships onto the rocks and
loot what washes up. Tomorrow a new lamp and the coastguard arrive, so tonight is their last
chance, and they're out on the water with their lanterns shuttered.

**Shades.** The wreckers' black rowboats. "Shades" is what keepers call them: shuttered lanterns,
dark hulls, two faces showing pale over the gunwale.

**Why the light saves ships and calls Shades (one reason).** Light makes things *seen.* A lit ship
sees the reef and turns. A lit wrecker has been seen, so it rows flat out at the tower to smash
the lamp before anyone can name it. Left dark, a wrecker waits a while, gives up and slips away.

**Tone.** Grounded, tense and historical, like a smuggling story. Human villains, no supernatural.

**Title card**
> NIGHTBEAM
> Last night before the coastguard comes. The wreckers know.
> Light shows ships the rocks, and shows you to the wreckers.

**End cards**
- Win: **"Dawn. Sails of the coastguard on the horizon."**
- Lose: **"The lamp is smashed. The wreckers' lanterns open."**

**Visual cues**
1. **Rowboats with faces.** A long dark hull with two pale faces (the existing eyes) and oar
   strokes. Lit, the oars speed up and the faces turn to the lamp.
2. **False lights.** Unlit Shades have a tiny shuttered lantern that blinks now and then, trying to
   lure ships. This shows who they are and why ships need your beam.
3. **Slipping away.** The dark fade becomes the boat backing off into the dark. A flare becomes
   "caught in the open, they scatter."

**Weakness.** It needs the most art change (blob → boat), and a flare that dissolves people is odd.
The wreckers only fit the name "Shades" as slang.

---

## Recommendation: **A, "The Drowned"**
- **Best single reason.** "The living see the rock, the dead only see the light" explains both halves
  of the core rule with one idea: it's the same beam, read by two kinds of ships. B and C need a
  second idea (food, being seen).
- **Answers every one of Boss's questions on screen:** keeper (last night of the old lamp), why
  ships leave (shared cue: they see the rocks and answer), what Shades are (ghost ships, with
  recognisable hulls), why tonight and why here (they're this reef's own wrecks, come back for the
  lamp's last night). The wreck-to-wisp cue teaches it with no text at all.
- **Fits what's built.** It keeps the name "Shades" (shade = ghost), the purple palette, the eyes,
  the rest-like fade, the existing narrative line and the "THE LAMP GOES OUT" card. The art work is
  one Shade redraw, the wisp, and the shared reef/answer cue, all `_draw()`.
- B is the runner-up if Boss wants something playful over something wistful.

**Suggested follow-up tickets if A is picked:** (1) view: shared "ship sees the reef" cue;
(2) view: ghost-ship Shade + wreck wisp + dawn sink; (3) copy: title/end strings and the optional
HULL → LAMP label, moved to the strings file.
