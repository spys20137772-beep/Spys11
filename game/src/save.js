// Persistent data in localStorage (works in the browser and in Electron).
const KEY = 'lanternbound.save.v1';

const DEFAULT = () => ({
  gold: 0,
  meta: { hp: 0, might: 0, speed: 0, magnet: 0, greed: 0, revive: 0 },
  best: { time: 0, kills: 0, level: 0 },
  runs: 0,
  wins: 0,
  options: { master: 0.8, music: 0.6, sfx: 0.8, shake: true, dmgNums: true, fullscreen: false },
});

export class Save {
  constructor() {
    this.data = DEFAULT();
    try {
      const raw = localStorage.getItem(KEY);
      if (raw) {
        const d = JSON.parse(raw), def = DEFAULT();
        this.data = { ...def, ...d, meta: { ...def.meta, ...d.meta }, best: { ...def.best, ...d.best }, options: { ...def.options, ...d.options } };
      }
    } catch { /* private mode or broken data: start fresh */ }
  }

  write() {
    try { localStorage.setItem(KEY, JSON.stringify(this.data)); } catch { /* ignore */ }
  }

  recordRun(r) {
    const d = this.data;
    d.runs++;
    if (r.win) d.wins++;
    d.gold += r.gold;
    const newBest = r.time > d.best.time;
    d.best.time = Math.max(d.best.time, r.time);
    d.best.kills = Math.max(d.best.kills, r.kills);
    d.best.level = Math.max(d.best.level, r.level);
    this.write();
    return newBest;
  }

  reset() { const o = this.data.options; this.data = DEFAULT(); this.data.options = o; this.write(); }
}
