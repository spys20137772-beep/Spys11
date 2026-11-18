// Deterministic physics for Chaltteok Jump. No DOM: shared by the game and the node solver.

export const TILE = 40;
export const R = 13;            // player radius
export const GRAV = 1500;
export const MAX_LAUNCH = 980;
export const MIN_LAUNCH = 160;
export const DT = 1 / 120;
export const CRATE_BREAK = 600; // impact speed that smashes a crate
export const FAN_ACCEL = 2900;
export const FAN_MAX_UP = 720;
export const BOUNCE_SPEED = 1050;
export const CRUMBLE_TIME = 0.75;
export const CRUMBLE_REGEN = 3;

// tile codes
export const T = { EMPTY: 0, SOLID: 1, ICE: 2, SPIKE: 3, BOUNCE: 4, CRATE: 5, CRUMBLE: 6, FAN: 7 };
const CHAR = { '#': T.SOLID, 'I': T.ICE, '^': T.SPIKE, 'B': T.BOUNCE, 'C': T.CRATE, '~': T.CRUMBLE, 'U': T.FAN };

export function parseLevel(def) {
  const rows = def.map;
  const H = rows.length, W = Math.max(...rows.map((r) => r.length));
  const grid = new Uint8Array(W * H);
  const berries = [], flags = [];
  let start = null, goal = null;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const c = rows[y][x] || '.';
      const cx = x * TILE + TILE / 2, cy = y * TILE + TILE / 2;
      if (CHAR[c] !== undefined) grid[y * W + x] = CHAR[c];
      else if (c === 'P') start = { x: cx, y: cy };
      else if (c === 'G') goal = { x: cx, y: cy };
      else if (c === '*') berries.push({ x: cx, y: cy });
      else if (c === 'F') flags.push({ x: cx, y: cy + TILE / 2 - 2 });
    }
  }
  if (!start || !goal) throw new Error(`level ${def.id}: needs P and G`);
  // fan columns blow upward until a blocking tile
  const fans = [];
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    if (grid[y * W + x] !== T.FAN) continue;
    let top = y - 1;
    while (top >= 0 && grid[top * W + x] === T.EMPTY) top--;
    fans.push({ x0: x * TILE, x1: (x + 1) * TILE, y0: (top + 1) * TILE, y1: y * TILE, tx: x, ty: y });
  }
  return { id: def.id, name: def.name, W, H, grid, berries, flags, start, goal, fans };
}

const solidLike = (t) => t === T.SOLID || t === T.CRATE || t === T.CRUMBLE || t === T.FAN || t === T.ICE || t === T.BOUNCE;

export class World {
  constructor(level, opts = {}) {
    this.L = level;
    this.W = level.W; this.H = level.H;
    this.grid = level.grid.slice();
    this.preview = !!opts.preview;
    this.crumble = new Map(); // idx -> {t, gone, regen}
    this.got = level.berries.map(() => false);
    this.respawn = { x: level.start.x, y: level.start.y };
    this.flagIdx = -1;
    this.p = { x: level.start.x, y: level.start.y, vx: 0, vy: 0, stuck: false, nx: 0, ny: -1, tx: -1, ty: -1, dead: false, impact: 0 };
    this.won = false;
    this.time = 0;
    this.launches = 0;
    this.events = [];
  }

  tile(tx, ty) {
    if (tx < 0 || tx >= this.W || ty < 0) return T.EMPTY;
    if (ty >= this.H) return T.EMPTY;
    return this.grid[ty * this.W + tx];
  }

  emit(type, data) { if (!this.preview) this.events.push({ type, ...data }); }

  canLaunch() { return this.p.stuck && !this.p.dead && !this.won; }

  launch(vx, vy) {
    if (!this.canLaunch()) return false;
    const p = this.p;
    p.stuck = false; p.vx = vx; p.vy = vy; p.tx = -1;
    this.launches++;
    this.emit('launch', { speed: Math.hypot(vx, vy) });
    return true;
  }

  respawnPlayer() {
    const p = this.p;
    Object.assign(p, { x: this.respawn.x, y: this.respawn.y, vx: 0, vy: 0, stuck: false, dead: false, tx: -1 });
  }

  inFan(x, y) {
    for (const f of this.L.fans) {
      if (this.grid[f.ty * this.W + Math.floor(f.x0 / TILE)] !== T.FAN) continue;
      if (x > f.x0 && x < f.x1 && y > f.y0 && y < f.y1) return true;
    }
    return false;
  }

  updateCrumbles(dt) {
    for (const [idx, c] of this.crumble) {
      if (!c.gone) {
        c.t -= dt;
        if (c.t <= 0) { c.gone = true; c.regen = CRUMBLE_REGEN; this.grid[idx] = T.EMPTY; this.emit('crumble', { idx }); }
      } else {
        c.regen -= dt;
        if (c.regen <= 0) {
          const tx = idx % this.W, ty = Math.floor(idx / this.W);
          const cx = tx * TILE + TILE / 2, cy = ty * TILE + TILE / 2;
          if (Math.abs(this.p.x - cx) > TILE / 2 + R || Math.abs(this.p.y - cy) > TILE / 2 + R) {
            this.grid[idx] = T.CRUMBLE; this.crumble.delete(idx);
          }
        }
      }
    }
  }

  step(dt = DT) {
    const p = this.p;
    this.time += dt;
    this.updateCrumbles(dt);
    if (p.dead || this.won) return;

    if (p.stuck) {
      // lose grip if the block under us is gone
      if (p.tx >= 0 && !solidLike(this.tile(p.tx, p.ty))) { p.stuck = false; }
      else return;
    }

    p.vy += GRAV * dt;
    if (this.inFan(p.x, p.y)) {
      p.vy -= FAN_ACCEL * dt;
      if (p.vy < -FAN_MAX_UP) p.vy = -FAN_MAX_UP;
    }
    p.x += p.vx * dt;
    p.y += p.vy * dt;
    this.collide();
    if (p.dead) return;

    // pickups
    for (let i = 0; i < this.L.berries.length; i++) {
      if (this.got[i]) continue;
      const b = this.L.berries[i];
      if ((b.x - p.x) ** 2 + (b.y - p.y) ** 2 < (R + 13) ** 2) { this.got[i] = true; this.emit('berry', { i, x: b.x, y: b.y }); }
    }
    for (let i = 0; i < this.L.flags.length; i++) {
      if (i === this.flagIdx) continue;
      const f = this.L.flags[i];
      if (Math.abs(f.x - p.x) < R + 10 && p.y > f.y - 60 && p.y < f.y + 4) {
        this.flagIdx = i; this.respawn = { x: f.x, y: f.y - R - 2 }; this.emit('flag', { i });
      }
    }
    const g = this.L.goal;
    if ((g.x - p.x) ** 2 + (g.y - p.y) ** 2 < (R + 16) ** 2) { this.won = true; p.stuck = true; p.vx = p.vy = 0; this.emit('goal', {}); }

    if (p.y > this.H * TILE + 300 || p.x < -400 || p.x > this.W * TILE + 400) this.die();
  }

  die() {
    const p = this.p;
    if (p.dead) return;
    p.dead = true; p.stuck = false;
    this.emit('die', { x: p.x, y: p.y });
  }

  collide() {
    const p = this.p;
    const x0 = Math.floor((p.x - R) / TILE), x1 = Math.floor((p.x + R) / TILE);
    const y0 = Math.floor((p.y - R) / TILE), y1 = Math.floor((p.y + R) / TILE);
    // spikes first (forgiving inset hitbox)
    for (let ty = y0; ty <= y1; ty++) for (let tx = x0; tx <= x1; tx++) {
      if (this.tile(tx, ty) !== T.SPIKE) continue;
      const ins = 9;
      const cx = Math.max(tx * TILE + ins, Math.min(p.x, (tx + 1) * TILE - ins));
      const cy = Math.max(ty * TILE + ins, Math.min(p.y, (ty + 1) * TILE - ins));
      if ((p.x - cx) ** 2 + (p.y - cy) ** 2 < (R - 2) ** 2) { this.die(); return; }
    }
    // gather contacts, deepest first
    const contacts = [];
    for (let ty = y0; ty <= y1; ty++) for (let tx = x0; tx <= x1; tx++) {
      const t = this.tile(tx, ty);
      if (!solidLike(t)) continue;
      const cx = Math.max(tx * TILE, Math.min(p.x, (tx + 1) * TILE));
      const cy = Math.max(ty * TILE, Math.min(p.y, (ty + 1) * TILE));
      const dx = p.x - cx, dy = p.y - cy, d2 = dx * dx + dy * dy;
      if (d2 >= R * R) continue;
      contacts.push({ tx, ty, t, dx, dy, d2 });
    }
    contacts.sort((a, b) => a.d2 - b.d2);
    for (const c of contacts) {
      const t = this.tile(c.tx, c.ty);
      if (!solidLike(t)) continue; // may have been broken this step
      // recompute against the current position
      const cx = Math.max(c.tx * TILE, Math.min(p.x, (c.tx + 1) * TILE));
      const cy = Math.max(c.ty * TILE, Math.min(p.y, (c.ty + 1) * TILE));
      let dx = p.x - cx, dy = p.y - cy, d = Math.hypot(dx, dy);
      if (d >= R) continue;
      let nx, ny;
      if (d < 1e-6) {
        const sp = Math.hypot(p.vx, p.vy) || 1;
        nx = -p.vx / sp; ny = -p.vy / sp; d = 0;
      } else { nx = dx / d; ny = dy / d; }
      const pen = R - d;
      p.x += nx * pen; p.y += ny * pen;
      const vn = p.vx * nx + p.vy * ny;
      if (p.stuck) continue;
      if (vn >= 0) continue; // moving away
      const speed = Math.hypot(p.vx, p.vy);
      const idx = c.ty * this.W + c.tx;
      if (t === T.CRATE && speed > CRATE_BREAK) {
        this.grid[idx] = T.EMPTY;
        p.vx *= 0.72; p.vy *= 0.72;
        this.emit('break', { x: c.tx * TILE + TILE / 2, y: c.ty * TILE + TILE / 2 });
        continue;
      }
      if (t === T.BOUNCE) {
        const tx = p.vx - vn * nx, ty = p.vy - vn * ny;
        p.vx = nx * BOUNCE_SPEED + tx * 0.5;
        p.vy = ny * BOUNCE_SPEED + ty * 0.5;
        this.emit('boing', { x: p.x, y: p.y });
        continue;
      }
      if (t === T.ICE) {
        const e = 0.55;
        p.vx -= (1 + e) * vn * nx; p.vy -= (1 + e) * vn * ny;
        // tangential friction
        const tvx = p.vx - (p.vx * nx + p.vy * ny) * nx, tvy = p.vy - (p.vx * nx + p.vy * ny) * ny;
        p.vx -= tvx * 0.04; p.vy -= tvy * 0.04;
        if (-vn > 140) this.emit('clink', { x: p.x, y: p.y, speed: -vn });
        if (ny < -0.7 && Math.hypot(p.vx, p.vy) < 70) this.stickTo(c.tx, c.ty, nx, ny, speed);
        continue;
      }
      // sticky surfaces
      this.stickTo(c.tx, c.ty, nx, ny, speed);
      if (t === T.CRUMBLE && !this.crumble.has(idx)) this.crumble.set(idx, { t: CRUMBLE_TIME, gone: false, regen: 0 });
    }
  }

  stickTo(tx, ty, nx, ny, speed) {
    const p = this.p;
    p.stuck = true; p.vx = 0; p.vy = 0; p.nx = nx; p.ny = ny; p.tx = tx; p.ty = ty; p.impact = speed;
    this.emit('stick', { x: p.x, y: p.y, nx, ny, speed });
  }

  // Clone for previews and the solver.
  clone(preview = true) {
    const w = Object.create(World.prototype);
    w.L = this.L; w.W = this.W; w.H = this.H;
    w.grid = this.grid.slice();
    w.preview = preview;
    w.crumble = new Map([...this.crumble].map(([k, v]) => [k, { ...v }]));
    w.got = this.got.slice();
    w.respawn = { ...this.respawn };
    w.flagIdx = this.flagIdx;
    w.p = { ...this.p };
    w.won = this.won; w.time = this.time; w.launches = this.launches; w.events = [];
    return w;
  }
}

// Launch velocity from a pull vector (dx, dy in screen px, pointing where the player pulled).
export function launchFromPull(dx, dy, maxPull) {
  const len = Math.hypot(dx, dy);
  if (len < 1e-6) return { vx: 0, vy: 0, k: 0 };
  const k = Math.min(1, len / maxPull);
  const sp = MIN_LAUNCH + (MAX_LAUNCH - MIN_LAUNCH) * k;
  return { vx: -dx / len * sp, vy: -dy / len * sp, k };
}

// Predicted path points for the aim preview.
export function predict(world, vx, vy, secs = 0.75, every = 3) {
  const w = world.clone(true);
  w.launch(vx, vy);
  const pts = [];
  const n = Math.round(secs / DT);
  for (let i = 0; i < n; i++) {
    w.step(DT);
    if (i % every === 0) pts.push(w.p.x, w.p.y);
    if (w.p.stuck || w.p.dead || w.won) { pts.push(w.p.x, w.p.y); break; }
  }
  return { pts, dead: w.p.dead };
}
