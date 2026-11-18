// Brute-force solver: proves every level can be finished and every berry can be reached.
// BFS over "stuck" positions; from each one, tries a fan of launch angles and powers
// using the exact game physics. Usage: node tests/solve.mjs [levelIndex...]
import { parseLevel, World, DT, MAX_LAUNCH, MIN_LAUNCH } from '../src/physics.js';
import { LEVELS } from '../src/levels.js';

const ANGLES = 64;
const POWERS = [0.12, 0.25, 0.38, 0.5, 0.62, 0.74, 0.86, 1];
const MAX_NODES = 2500;
const SIM_STEPS = Math.round(6 / DT);

function settle(w) {
  for (let i = 0; i < SIM_STEPS && !w.p.stuck && !w.p.dead && !w.won; i++) w.step(DT);
}

function key(w) {
  let h = 0;
  for (let i = 0; i < w.grid.length; i++) if (w.grid[i] !== w.L.grid[i]) h = (h * 31 + i) | 0;
  return `${Math.round(w.p.x / 8)},${Math.round(w.p.y / 8)},${h}`;
}

export function solve(def) {
  const L = parseLevel(def);
  const start = new World(L, { preview: true });
  settle(start);
  if (!start.p.stuck) return { id: def.id, ok: false, why: 'start not stable' };
  const seen = new Set([key(start)]);
  let frontier = [{ w: start, path: [] }];
  const berries = L.berries.map(() => null);
  let win = null, nodes = 0;
  for (let depth = 0; frontier.length && nodes < MAX_NODES; depth++) {
    const next = [];
    for (const node of frontier) {
      nodes++;
      for (let a = 0; a < ANGLES; a++) {
        const ang = (a / ANGLES) * Math.PI * 2;
        for (const k of POWERS) {
          const sp = MIN_LAUNCH + (MAX_LAUNCH - MIN_LAUNCH) * k;
          const w = node.w.clone(true);
          w.launch(Math.cos(ang) * sp, Math.sin(ang) * sp);
          let i = 0;
          for (; i < SIM_STEPS && !w.p.stuck && !w.p.dead && !w.won; i++) w.step(DT);
          w.got.forEach((g, bi) => { if (g && !berries[bi]) berries[bi] = depth + 1; });
          if (w.p.dead) continue;
          if (w.won) { if (!win) win = { launches: depth + 1, path: [...node.path, [a, k]] }; continue; }
          if (!w.p.stuck) continue;
          const kk = key(w);
          if (seen.has(kk)) continue;
          seen.add(kk);
          next.push({ w, path: [...node.path, [a, k]] });
        }
      }
      if (win && berries.every(Boolean)) break;
    }
    if (win && berries.every(Boolean)) break;
    frontier = next;
  }
  return {
    id: def.id, name: def.name, ok: !!win && berries.every(Boolean) && berries.length === 3,
    minLaunches: win ? win.launches : null, berries: berries.map((b) => b !== null), nodes,
    size: `${L.W}x${L.H}`, path: win ? win.path : null,
  };
}

const only = process.argv.slice(2).map(Number);
const list = only.length ? only.map((i) => LEVELS[i]) : LEVELS;
let allOk = true;
const paths = {};
for (const def of list) {
  const t0 = Date.now();
  const r = solve(def);
  paths[def.id] = r.path;
  allOk = allOk && r.ok;
  console.log(`${r.ok ? 'OK  ' : 'FAIL'} ${r.id} ${r.name || ''} | goal in ${r.minLaunches ?? '-'} | berries ${r.berries ? r.berries.map((b) => (b ? '●' : '○')).join('') : r.why} | nodes ${r.nodes} | ${((Date.now() - t0) / 1000).toFixed(1)}s`);
}
console.log(allOk ? 'ALL LEVELS SOLVABLE' : 'SOME LEVELS FAILED');
import('node:fs').then((fs) => { fs.mkdirSync('tests/out', { recursive: true }); fs.writeFileSync('tests/out/paths.json', JSON.stringify(paths)); });
process.exitCode = allOk ? 0 : 1;
