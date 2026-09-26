# NIGHTBEAM — Pitch (v1)

**One line:** You are the keeper of a lighthouse on a reef; turn a single narrow beam through a
3-minute night to guide lost ships to safety, but anything the light touches notices it, and the
shadow-ships come straight for your rock when you light them.

## Hook / the twist
The light helps and it hurts. The same beam that saves a ship pulls a **Shade** (a ghost ship)
toward your reef at 6x its dark speed. Every sweep is a quick choice: which ship do you light
now, and which path do you have to avoid lighting to get there? You can read it in one glance:
warm hulls want your light, purple shades must stay dark.

## Fantasy
A lone keeper holding the dark back until dawn. You can't save everyone, so you pick.

## Target player / session
Short-session arcade players, jam judges, anyone with 3 minutes. Runs last 2-4 minutes.
Controls: two turn keys and one flare key (or the mouse).

## Pillars (each one rules something out)
1. **One beam, one decision.** All play comes from where the beam points and when you fire the
   flare. *Rules out:* shooting, upgrades between runs, extra abilities, a moving keeper.
2. **Readable in one glance.** Warm means help it and purple means avoid it. Guidance shows as a
   filling ring around each ship, and the night clock is the sky. *Rules out:* text-heavy HUD,
   hidden stats, more than two entity types in v1, visual noise that hides the beam edge.
3. **Same seed, same night.** The sim is pure and seeded with a fixed 60 Hz step, so bots can
   play thousands of nights and people can compare seeds. *Rules out:* wall-clock timers,
   physics-engine collisions, unseeded randomness, gameplay rules inside draw code.

## Win / lose
- **Win:** survive until dawn (180 s). Score = ships saved (+ hull bonus).
- **Lose:** the reef takes 5 hits, from wrecked ships or shades reaching it.

## References (feel, not clones)
Lighthouse-keeper mood; "triage under a single cursor" tension like air-traffic control games;
the flashlight-reveals-and-provokes idea from horror games, turned into a top-down arcade rule.

## Tech / art in one breath
Godot 4.6 GDScript, one screen, `_draw()` shapes plus one beam shader at most, and
`AudioStreamGenerator` synth sounds (bell, foghorn, hum, surf). No imported assets.
