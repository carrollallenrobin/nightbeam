// Playtest Lab adapter for NIGHTBEAM (Godot 4.6.1) — engine bridge, see TDD "Playtest Lab plan".
// The lab launches Scenes/PlaytestHarness.tscn headless; its root (Scripts/Playtest/PlaytestTarget.gd) owns a
// NightbeamSim and steps it once per physics tick (== one bridge frame under --fixed-fps 60).
// Bot skills live once in GDScript (Scripts/Sim/NightbeamBots.gd): the greedy/careful policies here only send
// {policy: "<skill>"} and the target asks NightbeamBots for the action on every tick.
// Godot 4.6 binary: GODOT_BIN, else "godot" in .playtest/local.json (gitignored, per machine), else "godot" on PATH.
// Owner: ticket C (GJ-6).
import { readFileSync } from 'node:fs';

function localGodot() {
  try { return JSON.parse(readFileSync(new URL('./local.json', import.meta.url), 'utf8')).godot; } catch { return undefined; }
}
const GODOT_BIN = process.env.GODOT_BIN || localGodot() || 'godot';

// Night = dawn_time 180 s (Data/Tuning/NightbeamTuning.tres); 200 s leaves a margin before a softlock is called.
// personaFrames: default frames per `lab.js play` turn (0.5 s of game time).
export const meta = { name: 'NIGHTBEAM', dt: 1 / 60, decisionEvery: 6, maxSeconds: 200, personaFrames: 30 };

export const bridge = {
  command: GODOT_BIN,
  cwd: '.',
  args: ['--headless', '--fixed-fps', '60', '--path', '.', 'res://Scenes/PlaytestHarness.tscn', '--', '--playtestPort={PORT}'],
  startupTimeoutMs: 60000,
  stepTimeoutMs: 30000,
};

// Persona sessions (GJ-10, `lab.js host`): the real Main scene in a 960x540 window, starting on the title card.
// Scenes/PersonaHarness.tscn root = Scripts/Playtest/PersonaTarget.gd (human-fidelity observe, input via the
// input map). Actions: {turn: -1..1} held, {flare: true} = one Space press, {key: "space"|"r"|"n"|"esc"} one press.
export const personaBridge = {
  command: GODOT_BIN,
  cwd: '.',
  args: ['--fixed-fps', '60', '--resolution', '960x540', '--path', '.', 'res://Scenes/PersonaHarness.tscn', '--', '--playtestPort={PORT}'],
  hideWindow: false,
  startupTimeoutMs: 60000,
  stepTimeoutMs: 60000,
};

export const idleAction = () => ({ turn: 0, flare: false });

// Random input: a new turn value every decision (10 Hz), flares rarely so charges are not all spent at once.
const RANDOM_FLARE_CHANCE = 0.02;
export const randomAction = (_obs, rng) => ({ turn: rng.range(-1, 1), flare: rng.next() < RANDOM_FLARE_CHANCE });

export const policies = {
  greedy: () => ({ policy: 'greedy' }),
  careful: () => ({ policy: 'careful' }),
};

// GDD §4 "target skill gradient": careful survives >= 4x idle and >= 1.3x greedy; careful wins 50-80 % of runs.
const GRADIENT = { carefulVsIdle: 4, carefulVsGreedy: 1.3, winMin: 0.5, winMax: 0.8 };

export function findings(p) {
  const out = [];
  const m = (pol, k) => p[pol]?.metrics?.[k]?.mean;
  const surv = (pol) => m(pol, 'time_survived');
  const fmt = (x) => (x === undefined ? 'n/a' : x.toFixed(1));
  if (surv('careful') !== undefined && surv('idle') !== undefined && surv('careful') < GRADIENT.carefulVsIdle * surv('idle'))
    out.push({ title: 'Careful play barely outlasts doing nothing', severity: 'P2', category: 'balance',
      evidence: `mean time survived: careful ${fmt(surv('careful'))} s vs idle ${fmt(surv('idle'))} s (GDD wants >= ${GRADIENT.carefulVsIdle}x)` });
  if (surv('careful') !== undefined && surv('greedy') !== undefined && surv('careful') < GRADIENT.carefulVsGreedy * surv('greedy'))
    out.push({ title: 'Careful play does not clearly beat greedy play', severity: 'P2', category: 'balance',
      evidence: `mean time survived: careful ${fmt(surv('careful'))} s vs greedy ${fmt(surv('greedy'))} s (GDD wants >= ${GRADIENT.carefulVsGreedy}x)` });
  const win = m('careful', 'won');
  if (win !== undefined && (win < GRADIENT.winMin || win > GRADIENT.winMax))
    out.push({ title: win > GRADIENT.winMax ? 'Careful play wins too often (late night too soft)' : 'Careful play loses too often',
      severity: 'P2', category: 'balance',
      evidence: `careful win rate ${(win * 100).toFixed(0)} % (GDD wants ${GRADIENT.winMin * 100}-${GRADIENT.winMax * 100} %)` });
  return out;
}
