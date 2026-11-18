// Progress and settings in localStorage.
const KEY = 'chaltteok.save.v1';

const DEFAULT = () => ({
  levels: {}, // id -> { done, berries: [b,b,b], best, time }
  deaths: 0,
  playTime: 0,
  options: { master: 0.8, music: 0.6, sfx: 0.8, preview: true, shake: true, fullscreen: false },
});

export class Save {
  constructor() {
    this.data = DEFAULT();
    try {
      const raw = localStorage.getItem(KEY);
      if (raw) {
        const d = JSON.parse(raw), def = DEFAULT();
        this.data = { ...def, ...d, options: { ...def.options, ...d.options }, levels: d.levels || {} };
      }
    } catch { /* fresh start */ }
  }

  write() { try { localStorage.setItem(KEY, JSON.stringify(this.data)); } catch { /* ignore */ } }

  level(id) { return this.data.levels[id] || { done: false, berries: [false, false, false], best: 0, time: 0 }; }

  record(id, got, launches, time) {
    const prev = this.level(id);
    const firstClear = !prev.done;
    const rec = {
      done: true,
      berries: prev.berries.map((b, i) => b || !!got[i]),
      best: prev.best ? Math.min(prev.best, launches) : launches,
      time: prev.time ? Math.min(prev.time, time) : time,
    };
    const newBest = !prev.best || launches < prev.best;
    this.data.levels[id] = rec;
    this.write();
    return { firstClear, newBest };
  }

  totalBerries() {
    let n = 0;
    for (const id in this.data.levels) n += this.data.levels[id].berries.filter(Boolean).length;
    return n;
  }
}
