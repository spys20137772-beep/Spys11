// One run of the game: simulation + rendering.
import {
  WEAPONS, PASSIVES, ENEMIES, TIMELINE, RUN_LENGTH, MAX_WEAPONS, MAX_PASSIVES,
  spawnWeights, xpFor,
} from './content.js';
import { SS } from './sprites.js';

const TAU = Math.PI * 2;
const rand = (a, b) => a + Math.random() * (b - a);
const MAX_ENEMIES = 520;
const CELL = 64;

function shuffle(a) {
  for (let i = a.length - 1; i > 0; i--) { const j = (Math.random() * (i + 1)) | 0; [a[i], a[j]] = [a[j], a[i]]; }
  return a;
}

export class Game {
  constructor(app) {
    this.app = app;
    this.sound = app.sound;
    this.opts = app.save.data.options;
    this.meta = app.save.data.meta;
    this.time = 0;
    this.kills = 0;
    this.goldRun = 0;
    this.level = 1;
    this.xp = 0;
    this.xpNext = xpFor(1);
    this.player = { x: 0, y: 0, r: 12, hp: 100, fx: 1, fy: 0, inv: 0, moving: false, walk: 0, hurtT: 0 };
    this.weapons = [];
    this.passives = {};
    this.enemies = [];
    this.projs = [];
    this.eprojs = [];
    this.gems = [];
    this.pickups = [];
    this.parts = [];
    this.nums = [];
    this.zones = [];
    this.bolts = [];
    this.warnings = [];
    this.grid = new Map();
    this.q = [];
    this.nextId = 1;
    this.spawnAcc = 0;
    this.eventIdx = 0;
    this.shake = 0;
    this.pendingLevels = 0;
    this.pendingChest = 0;
    this.boss = null;
    this.over = false;
    this.result = null;
    this.victoryT = -1;
    this.revives = this.meta.revive || 0;
    this.god = false;
    this.banner = null; // {text, t}
    this.halfW = 640; this.halfH = 360;
    this.recompute();
    this.player.hp = this.stats.maxHp;
    this.addWeapon('ember');
  }

  // ------------------------------------------------------------ stats
  recompute() {
    const m = this.meta, P = (id) => this.passives[id] || 0;
    const s = {
      maxHp: 100 * (1 + 0.1 * (m.hp || 0)) * (1 + 0.2 * P('vigor')),
      speed: 145 * (1 + 0.05 * (m.speed || 0)) * (1 + 0.1 * P('swift')),
      might: (1 + 0.05 * (m.might || 0)) + 0.1 * P('might'),
      cooldown: Math.pow(0.92, P('haste')),
      area: 1 + 0.1 * P('reach'),
      magnet: 90 * (1 + 0.2 * (m.magnet || 0)) * (1 + 0.3 * P('magnet')),
      armor: P('armor'),
      regen: 0.4 * P('regen'),
      amount: P('multi'),
      greed: 1 + 0.1 * (m.greed || 0),
    };
    if (this.stats) this.player.hp += Math.max(0, s.maxHp - this.stats.maxHp);
    this.stats = s;
  }

  hasWeapon(id) { return this.weapons.some((w) => w.id === id); }
  addWeapon(id) { this.weapons.push({ id, lvl: 1, t: 0.3, ang: 0, orbs: [] }); }

  // ------------------------------------------------------------ level up
  rollChoices(n = 3) {
    const pool = [];
    for (const w of this.weapons) if (w.lvl < WEAPONS[w.id].max) pool.push({ kind: 'w', id: w.id, w: 3 });
    if (this.weapons.length < MAX_WEAPONS)
      for (const id in WEAPONS) if (!this.hasWeapon(id)) pool.push({ kind: 'w', id, w: 2 });
    const owned = Object.keys(this.passives).length;
    for (const id in PASSIVES) {
      const l = this.passives[id] || 0;
      if (l > 0 && l < PASSIVES[id].max) pool.push({ kind: 'p', id, w: 2 });
      else if (l === 0 && owned < MAX_PASSIVES) pool.push({ kind: 'p', id, w: 1.5 });
    }
    const out = [];
    while (out.length < n && pool.length) {
      let tot = 0; for (const c of pool) tot += c.w;
      let r = Math.random() * tot, i = 0;
      for (; i < pool.length - 1; i++) { r -= pool[i].w; if (r <= 0) break; }
      out.push(pool.splice(i, 1)[0]);
    }
    if (!out.length) out.push({ kind: 'heal' }, { kind: 'gold' });
    return out.map((c) => this.describe(c));
  }

  describe(c) {
    if (c.kind === 'w') {
      const d = WEAPONS[c.id], w = this.weapons.find((x) => x.id === c.id);
      const next = w ? w.lvl + 1 : 1;
      return { ...c, name: d.name, icon: d.icon, lvl: next, isNew: !w, text: d.desc[next - 1], tag: w ? `Lv ${next}` : '새 무기' };
    }
    if (c.kind === 'p') {
      const d = PASSIVES[c.id], l = this.passives[c.id] || 0;
      return { ...c, name: d.name, icon: d.icon, lvl: l + 1, isNew: !l, text: d.desc, tag: l ? `Lv ${l + 1}` : '새 능력' };
    }
    if (c.kind === 'heal') return { ...c, name: '등불 기름', icon: '🍖', text: '체력을 40 회복합니다.', tag: '회복' };
    return { ...c, name: '금화 주머니', icon: '🪙', text: '금화 25개를 얻습니다.', tag: '보상' };
  }

  applyChoice(c) {
    if (c.kind === 'w') {
      const w = this.weapons.find((x) => x.id === c.id);
      if (w) w.lvl++; else this.addWeapon(c.id);
    } else if (c.kind === 'p') {
      this.passives[c.id] = (this.passives[c.id] || 0) + 1;
      this.recompute();
    } else if (c.kind === 'heal') {
      this.player.hp = Math.min(this.stats.maxHp, this.player.hp + 40);
    } else {
      this.goldRun += 25;
    }
  }

  // ------------------------------------------------------------ helpers
  rebuildGrid() {
    const g = this.grid;
    for (const arr of g.values()) arr.length = 0;
    for (const e of this.enemies) {
      const k = ((Math.floor(e.x / CELL) + 32768) << 16) | (Math.floor(e.y / CELL) + 32768);
      let a = g.get(k);
      if (!a) { a = []; g.set(k, a); }
      a.push(e);
    }
  }

  // Enemies whose cell overlaps the circle. Returns a reused array.
  query(x, y, r) {
    const out = this.q; out.length = 0;
    const x0 = Math.floor((x - r - 48) / CELL), x1 = Math.floor((x + r + 48) / CELL);
    const y0 = Math.floor((y - r - 48) / CELL), y1 = Math.floor((y + r + 48) / CELL);
    for (let cx = x0; cx <= x1; cx++) for (let cy = y0; cy <= y1; cy++) {
      const a = this.grid.get(((cx + 32768) << 16) | (cy + 32768));
      if (a) for (const e of a) if (!e.dead) out.push(e);
    }
    return out;
  }

  nearest(x, y, n, range) {
    const list = [];
    for (const e of this.enemies) {
      if (e.dead) continue;
      const d = (e.x - x) ** 2 + (e.y - y) ** 2;
      if (d < range * range) list.push([d, e]);
    }
    list.sort((a, b) => a[0] - b[0]);
    return list.slice(0, n).map((p) => p[1]);
  }

  burst(x, y, color, n, speed = 140, size = 3, life = 0.45) {
    for (let i = 0; i < n && this.parts.length < 700; i++) {
      const a = Math.random() * TAU, s = speed * rand(0.3, 1);
      this.parts.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: life * rand(0.6, 1), max: life, size: size * rand(0.6, 1.2), color });
    }
  }

  say(text) { this.banner = { text, t: 3 }; }

  // ------------------------------------------------------------ spawning
  spawnEnemy(type, opts = {}) {
    const d = ENEMIES[type];
    const p = this.player;
    let x = opts.x, y = opts.y;
    if (x === undefined) {
      const a = Math.random() * TAU;
      const dist = Math.hypot(this.halfW, this.halfH) + 50;
      x = p.x + Math.cos(a) * dist; y = p.y + Math.sin(a) * dist;
    }
    const min = this.time / 60;
    const scale = type === 'boss' ? 1 : 1 + min * 0.16 + Math.max(0, min - 5) * 0.18;
    const elite = !!opts.elite;
    const hp = d.hp * scale * (elite ? 14 : 1);
    const e = {
      id: this.nextId++, type, x, y, hp, maxHp: hp,
      r: d.r * (elite ? 1.6 : 1), speed: d.speed * (elite ? 1.05 : 1), dmg: d.dmg * (elite ? 1.5 : 1),
      xp: d.xp, ai: d.ai, kbRes: elite ? 0.9 : d.kbRes,
      kx: 0, ky: 0, flash: 0, t: rand(0.5, 2.5), state: 0, dx: 0, dy: 0, elite, dead: false, hitT: 0, face: 1,
      t2: 6,
    };
    this.enemies.push(e);
    return e;
  }

  runTimeline() {
    while (this.eventIdx < TIMELINE.length && this.time >= TIMELINE[this.eventIdx].t) {
      const ev = TIMELINE[this.eventIdx++];
      const p = this.player;
      if (ev.kind === 'ring') {
        const R = Math.hypot(this.halfW, this.halfH) * 0.85;
        for (let i = 0; i < ev.n; i++) {
          const a = (i / ev.n) * TAU;
          this.spawnEnemy(ev.enemy, { x: p.x + Math.cos(a) * R, y: p.y + Math.sin(a) * R });
        }
      } else if (ev.kind === 'elite') {
        this.spawnEnemy(ev.enemy, { elite: true });
      } else if (ev.kind === 'boss') {
        this.boss = this.spawnEnemy('boss');
        this.sound.play('boss');
        this.sound.music('boss');
        this.shake = 14;
      }
      this.say(ev.msg);
    }
  }

  // ------------------------------------------------------------ damage
  hurt(e, base, kx = 0, ky = 0, quiet = false) {
    if (e.dead) return;
    const dmg = Math.max(1, Math.round(base * this.stats.might * rand(0.9, 1.1)));
    e.hp -= dmg;
    e.flash = 0.09;
    const k = 1 - e.kbRes;
    e.kx += kx * k; e.ky += ky * k;
    if (!quiet && this.opts.dmgNums && this.nums.length < 140) this.nums.push({ x: e.x + rand(-6, 6), y: e.y - e.r, v: dmg, life: 0.7, big: dmg >= 40 });
    this.sound.play('hit');
    if (e.hp <= 0) this.kill(e);
  }

  kill(e) {
    e.dead = true;
    this.kills++;
    const colors = { wisp: '#a78bfa', bat: '#f43f5e', splitter: '#fb923c', splitling: '#fdba74', brute: '#9ca3af', spitter: '#2dd4bf', charger: '#60a5fa', boss: '#e879f9' };
    this.burst(e.x, e.y, colors[e.type], e.type === 'boss' ? 80 : e.elite ? 30 : 8, e.type === 'boss' ? 320 : 150);
    this.sound.play('kill');
    if (e.type === 'boss') {
      this.victoryT = 2.4;
      this.shake = 20;
      this.sound.play('explode');
      for (const o of this.enemies) if (!o.dead && o !== e) { o.dead = true; this.burst(o.x, o.y, '#c4b5fd', 4); }
      this.eprojs.length = 0;
      return;
    }
    if (e.elite) {
      this.pickups.push({ type: 'chest', x: e.x, y: e.y, bob: 0 });
    } else {
      this.gems.push({ x: e.x, y: e.y, v: e.xp * (1 + Math.floor(this.time / 240)), mag: false });
    }
    const r = Math.random();
    if (r < 0.035) this.pickups.push({ type: 'coin', x: e.x + 8, y: e.y, v: 1 + ((Math.random() * 4) | 0), bob: Math.random() * 6 });
    else if (r < 0.041) this.pickups.push({ type: 'heart', x: e.x, y: e.y, bob: 0 });
    else if (r < 0.0435) this.pickups.push({ type: 'magnet', x: e.x, y: e.y, bob: 0 });
    const d = ENEMIES[e.type];
    if (d.splits) for (let i = 0; i < 2; i++) this.spawnEnemy(d.splits, { x: e.x + rand(-8, 8), y: e.y + rand(-8, 8) });
  }

  damagePlayer(dmg) {
    const p = this.player;
    if (this.god || p.inv > 0 || this.over || this.victoryT >= 0) return;
    const real = Math.max(1, Math.round(dmg - this.stats.armor));
    p.hp -= real;
    p.inv = 0.45;
    p.hurtT = 0.25;
    this.shake = Math.max(this.shake, 7);
    this.sound.play('hurt');
    if (p.hp <= 0) {
      if (this.revives > 0) {
        this.revives--;
        p.hp = this.stats.maxHp * 0.5;
        p.inv = 2.5;
        this.say('두 번째 등불이 타올랐습니다!');
        this.sound.play('levelup');
        for (const e of this.query(p.x, p.y, 260)) {
          if (Math.hypot(e.x - p.x, e.y - p.y) < 260 && e.type !== 'boss') this.hurt(e, 9999);
        }
        this.burst(p.x, p.y, '#fde68a', 60, 380, 4, 0.8);
      } else {
        p.hp = 0;
        this.finish(false);
      }
    }
  }

  finish(win) {
    if (this.over) return;
    this.over = true;
    const gold = Math.round((this.goldRun + this.kills * 0.05 + (win ? 200 : 0)) * this.stats.greed);
    this.result = {
      win, time: this.time, kills: this.kills, level: this.level, gold,
      weapons: this.weapons.map((w) => ({ icon: WEAPONS[w.id].icon, name: WEAPONS[w.id].name, lvl: w.lvl })),
    };
    this.sound.play(win ? 'victory' : 'defeat');
    this.sound.music(null);
  }

  // ------------------------------------------------------------ update
  update(dt, input) {
    // particles keep moving even when over
    this.updateFx(dt);
    if (this.over) return;

    if (this.victoryT >= 0) {
      this.victoryT -= dt;
      if (this.victoryT < 0) this.finish(true);
      return;
    }

    this.time += dt;
    const p = this.player, s = this.stats;

    // movement
    const m = input.move();
    p.moving = m.x !== 0 || m.y !== 0;
    if (p.moving) {
      p.x += m.x * s.speed * dt; p.y += m.y * s.speed * dt;
      const l = Math.hypot(m.x, m.y); p.fx = m.x / l; p.fy = m.y / l;
      p.walk += dt * 10;
    }
    p.inv -= dt; p.hurtT -= dt;
    if (s.regen) p.hp = Math.min(s.maxHp, p.hp + s.regen * dt);

    // spawning
    this.runTimeline();
    const min = this.time / 60;
    const rate = (1.1 + min * 1.25 + min * min * 0.11) * (this.boss ? 0.25 : 1);
    this.spawnAcc += rate * dt;
    if (this.time < RUN_LENGTH + 1e9) {
      const weights = spawnWeights(min);
      let tot = 0; for (const [, w] of weights) tot += w;
      while (this.spawnAcc >= 1) {
        this.spawnAcc -= 1;
        if (this.enemies.length >= MAX_ENEMIES) continue;
        let r = Math.random() * tot, type = 'wisp';
        for (const [k, w] of weights) { r -= w; if (r <= 0) { type = k; break; } }
        this.spawnEnemy(type);
      }
    }

    this.rebuildGrid();
    this.updateEnemies(dt);
    this.updateWeapons(dt);
    this.updateProjectiles(dt);
    this.updatePickups(dt);

    // sweep dead enemies
    let j = 0;
    for (let i = 0; i < this.enemies.length; i++) { const e = this.enemies[i]; if (!e.dead) this.enemies[j++] = e; }
    this.enemies.length = j;
    if (this.boss && this.boss.dead && this.victoryT < 0) this.boss = null;
  }

  updateEnemies(dt) {
    const p = this.player;
    const decay = Math.exp(-9 * dt);
    const far = Math.hypot(this.halfW, this.halfH) + 260;
    for (const e of this.enemies) {
      if (e.dead) continue;
      e.flash -= dt;
      let dx = p.x - e.x, dy = p.y - e.y;
      const d = Math.hypot(dx, dy) || 1;
      dx /= d; dy /= d;
      let vx = dx * e.speed, vy = dy * e.speed;

      switch (e.ai) {
        case 'zig': {
          const w = Math.sin(this.time * 5 + e.id) * 0.8;
          vx += -dy * e.speed * w; vy += dx * e.speed * w;
          break;
        }
        case 'ranged': {
          if (d < 200) { vx = -dx * e.speed * 0.6; vy = -dy * e.speed * 0.6; }
          else if (d < 280) { vx = -dy * e.speed * 0.5; vy = dx * e.speed * 0.5; }
          e.t -= dt;
          if (e.t <= 0 && d < 480) {
            e.t = 2.8;
            this.eprojs.push({ x: e.x, y: e.y, vx: dx * 165, vy: dy * 165, r: 6, dmg: 9, life: 4 });
          }
          break;
        }
        case 'charge': {
          e.t -= dt;
          if (e.state === 0) {
            if (e.t <= 0 && d < 300) { e.state = 1; e.t = 0.55; e.dx = dx; e.dy = dy; }
          } else if (e.state === 1) {
            vx = 0; vy = 0; e.flash = Math.max(e.flash, (Math.sin(this.time * 40) > 0) ? 0.02 : 0);
            if (e.t <= 0) { e.state = 2; e.t = 0.5; }
          } else {
            vx = e.dx * 420; vy = e.dy * 420;
            if (e.t <= 0) { e.state = 0; e.t = 2.6; }
          }
          break;
        }
        case 'boss': this.bossAi(e, dt, dx, dy, d); break;
      }

      e.x += (vx + e.kx) * dt; e.y += (vy + e.ky) * dt;
      e.kx *= decay; e.ky *= decay;
      if (Math.abs(vx) > 1) e.face = vx > 0 ? 1 : -1;

      // contact damage
      if (d < e.r + p.r) this.damagePlayer(e.dmg);

      // recycle stragglers left far behind
      if (d > far && e.type !== 'boss' && !e.elite) {
        const a = Math.random() * TAU, R = Math.hypot(this.halfW, this.halfH) + 50;
        e.x = p.x + Math.cos(a) * R; e.y = p.y + Math.sin(a) * R;
      }
    }

    // separation (cheap, grid based)
    for (const a of this.grid.values()) {
      for (let i = 0; i < a.length; i++) {
        const e = a[i];
        for (let k = i + 1; k < a.length && k < i + 6; k++) {
          const o = a[k];
          const dx = o.x - e.x, dy = o.y - e.y, rr = e.r + o.r;
          const d2 = dx * dx + dy * dy;
          if (d2 > 0.01 && d2 < rr * rr) {
            const d = Math.sqrt(d2), push = (rr - d) * 0.5 / d;
            const we = e.type === 'boss' ? 0 : 1, wo = o.type === 'boss' ? 0 : 1;
            e.x -= dx * push * we; e.y -= dy * push * we;
            o.x += dx * push * wo; o.y += dy * push * wo;
          }
        }
      }
    }

    // enemy projectiles
    for (const b of this.eprojs) {
      b.x += b.vx * dt; b.y += b.vy * dt; b.life -= dt;
      if (Math.hypot(b.x - p.x, b.y - p.y) < b.r + p.r) { this.damagePlayer(b.dmg); b.life = 0; }
    }
    this.eprojs = this.eprojs.filter((b) => b.life > 0);
  }

  bossAi(e, dt, dx, dy, d) {
    const enraged = e.hp < e.maxHp * 0.5;
    e.t -= dt; e.t2 -= dt;
    if (e.t <= 0) {
      e.t = enraged ? 2.4 : 3.6;
      const n = enraged ? 22 : 14, off = Math.random() * TAU;
      for (let i = 0; i < n; i++) {
        const a = off + (i / n) * TAU;
        this.eprojs.push({ x: e.x, y: e.y, vx: Math.cos(a) * 150, vy: Math.sin(a) * 150, r: 7, dmg: 14, life: 5 });
      }
      this.sound.play('zap');
    }
    if (e.t2 <= 0) {
      e.t2 = enraged ? 5 : 7;
      for (let i = 0; i < 8; i++) {
        const a = (i / 8) * TAU;
        this.spawnEnemy(enraged ? 'bat' : 'wisp', { x: e.x + Math.cos(a) * 80, y: e.y + Math.sin(a) * 80 });
      }
    }
    if (enraged) e.speed = ENEMIES.boss.speed * 1.35;
  }

  // ------------------------------------------------------------ weapons
  updateWeapons(dt) {
    const p = this.player, S = this.stats;
    for (const w of this.weapons) {
      const s = WEAPONS[w.id].stats(w.lvl);
      w.t -= dt;
      switch (w.id) {
        case 'ember': {
          if (w.t > 0) break;
          const targets = this.nearest(p.x, p.y, s.count + S.amount, 560);
          if (!targets.length) break;
          for (let i = 0; i < s.count + S.amount; i++) {
            const t = targets[i % targets.length];
            const a = Math.atan2(t.y - p.y, t.x - p.x) + (i >= targets.length ? rand(-0.2, 0.2) : 0);
            this.projs.push({ kind: 'ember', x: p.x, y: p.y, vx: Math.cos(a) * s.speed, vy: Math.sin(a) * s.speed, r: 7 * S.area, dmg: s.dmg, pierce: s.pierce, life: 1.4, hit: new Set() });
          }
          w.t = s.cd * S.cooldown;
          this.sound.play('shoot');
          break;
        }
        case 'orbit': {
          const n = s.count + S.amount, R = s.radius * S.area;
          w.ang += s.spin * dt;
          w.orbs.length = 0;
          for (let i = 0; i < n; i++) {
            const a = w.ang + (i / n) * TAU;
            const ox = p.x + Math.cos(a) * R, oy = p.y + Math.sin(a) * R;
            w.orbs.push(ox, oy);
            const rr = 13 * S.area;
            for (const e of this.query(ox, oy, rr)) {
              if (e.hitT > this.time) continue;
              const dd = Math.hypot(e.x - ox, e.y - oy);
              if (dd < e.r + rr) {
                e.hitT = this.time + 0.4;
                this.hurt(e, s.dmg, (e.x - p.x) / (dd + 1) * 160, (e.y - p.y) / (dd + 1) * 160);
              }
            }
          }
          break;
        }
        case 'aura': {
          w.radius = s.radius * S.area;
          if (w.t > 0) break;
          w.t = s.tick * S.cooldown;
          for (const e of this.query(p.x, p.y, w.radius)) {
            if (Math.hypot(e.x - p.x, e.y - p.y) < w.radius + e.r) this.hurt(e, s.dmg, 0, 0, true);
          }
          break;
        }
        case 'sparks': {
          if (w.t > 0) break;
          const n = s.count + S.amount * 2, base = Math.atan2(p.fy, p.fx), spread = 0.9;
          for (let i = 0; i < n; i++) {
            const a = base + (n === 1 ? 0 : (i / (n - 1) - 0.5) * spread) + rand(-0.05, 0.05);
            const sp = s.speed * rand(0.85, 1.1);
            this.projs.push({ kind: 'spark', x: p.x, y: p.y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, r: 6 * S.area, dmg: s.dmg, pierce: 1, life: s.life, hit: new Set() });
          }
          w.t = s.cd * S.cooldown;
          this.sound.play('spark');
          break;
        }
        case 'chain': {
          if (w.t > 0) break;
          const first = this.nearest(p.x, p.y, 6, 420);
          if (!first.length) break;
          let cur = first[(Math.random() * first.length) | 0];
          const hit = new Set();
          const pts = [p.x, p.y - 10];
          for (let i = 0; i <= s.chains + S.amount && cur; i++) {
            hit.add(cur.id);
            pts.push(cur.x, cur.y);
            this.hurt(cur, s.dmg);
            let best = null, bd = 170 * S.area;
            for (const e of this.query(cur.x, cur.y, bd)) {
              if (hit.has(e.id)) continue;
              const dd = Math.hypot(e.x - cur.x, e.y - cur.y);
              if (dd < bd) { bd = dd; best = e; }
            }
            cur = best;
          }
          this.bolts.push({ pts, life: 0.18 });
          w.t = s.cd * S.cooldown;
          this.sound.play('zap');
          break;
        }
        case 'trail': {
          if (!p.moving || w.t > 0) break;
          w.t = 0.2;
          this.zones.push({ x: p.x + rand(-4, 4), y: p.y + rand(-4, 4), r: s.radius * S.area, life: s.dur, max: s.dur, dmg: s.dmg, tick: 0 });
          break;
        }
        case 'meteor': {
          if (w.t > 0) break;
          const n = s.count + S.amount;
          const cands = this.nearest(p.x, p.y, 40, Math.max(this.halfW, this.halfH));
          for (let i = 0; i < n; i++) {
            const t = cands.length ? cands[(Math.random() * cands.length) | 0] : null;
            const x = t ? t.x : p.x + rand(-200, 200), y = t ? t.y : p.y + rand(-200, 200);
            this.warnings.push({ x, y, r: s.radius * S.area, t: 0.7, max: 0.7, dmg: s.dmg });
          }
          w.t = s.cd * S.cooldown;
          break;
        }
        case 'sickle': {
          if (w.t > 0) break;
          const n = s.count + S.amount, base = Math.atan2(p.fy, p.fx);
          for (let i = 0; i < n; i++) {
            const a = base + (i / n) * TAU;
            this.projs.push({ kind: 'sickle', x: p.x, y: p.y, vx: Math.cos(a) * 470, vy: Math.sin(a) * 470, r: s.size * S.area, dmg: s.dmg, pierce: Infinity, life: 3, t: 0, out: 0.55, spin: 0, hitMap: new Map() });
          }
          w.t = s.cd * S.cooldown;
          this.sound.play('shoot');
          break;
        }
      }
    }
  }

  updateProjectiles(dt) {
    const p = this.player;
    for (const pr of this.projs) {
      pr.life -= dt;
      if (pr.kind === 'sickle') {
        pr.t += dt; pr.spin += dt * 16;
        if (pr.t < pr.out) {
          const k = 1 - pr.t / pr.out * 0.85;
          pr.x += pr.vx * k * dt; pr.y += pr.vy * k * dt;
        } else {
          const dx = p.x - pr.x, dy = p.y - pr.y, d = Math.hypot(dx, dy) || 1;
          const sp = 520 + (pr.t - pr.out) * 400;
          pr.x += dx / d * sp * dt; pr.y += dy / d * sp * dt;
          if (d < 20) pr.life = 0;
        }
      } else {
        pr.x += pr.vx * dt; pr.y += pr.vy * dt;
      }
      if (pr.life <= 0) continue;
      for (const e of this.query(pr.x, pr.y, pr.r)) {
        const dd = Math.hypot(e.x - pr.x, e.y - pr.y);
        if (dd >= e.r + pr.r) continue;
        if (pr.hitMap) {
          if ((pr.hitMap.get(e.id) || 0) > this.time) continue;
          pr.hitMap.set(e.id, this.time + 0.35);
        } else {
          if (pr.hit.has(e.id)) continue;
          pr.hit.add(e.id);
        }
        const sp = Math.hypot(pr.vx, pr.vy) || 1;
        this.hurt(e, pr.dmg, pr.vx / sp * 120, pr.vy / sp * 120);
        if (pr.kind !== 'sickle') this.burst(pr.x, pr.y, '#fdba74', 2, 90, 2, 0.25);
        pr.pierce--;
        if (pr.pierce < 0) { pr.life = 0; break; }
      }
    }
    this.projs = this.projs.filter((pr) => pr.life > 0);

    // fire zones
    for (const z of this.zones) {
      z.life -= dt; z.tick -= dt;
      if (z.tick <= 0) {
        z.tick = 0.4;
        for (const e of this.query(z.x, z.y, z.r)) if (Math.hypot(e.x - z.x, e.y - z.y) < z.r + e.r * 0.5) this.hurt(e, z.dmg, 0, 0, true);
      }
    }
    this.zones = this.zones.filter((z) => z.life > 0);

    // meteor warnings -> explosions
    for (const m of this.warnings) {
      m.t -= dt;
      if (m.t <= 0) {
        for (const e of this.query(m.x, m.y, m.r)) {
          const dd = Math.hypot(e.x - m.x, e.y - m.y);
          if (dd < m.r + e.r) this.hurt(e, m.dmg, (e.x - m.x) / (dd + 1) * 300, (e.y - m.y) / (dd + 1) * 300);
        }
        this.burst(m.x, m.y, '#fb923c', 26, 260, 4, 0.5);
        this.burst(m.x, m.y, '#fde68a', 12, 160, 3, 0.4);
        this.shake = Math.max(this.shake, 4);
        this.sound.play('explode');
      }
    }
    this.warnings = this.warnings.filter((m) => m.t > 0);
  }

  updatePickups(dt) {
    const p = this.player, mag = this.stats.magnet;
    for (const g of this.gems) {
      const dx = p.x - g.x, dy = p.y - g.y, d = Math.hypot(dx, dy) || 1;
      if (!g.mag && d < mag) g.mag = true;
      if (g.mag) {
        const sp = Math.min(900, 260 + (g.sp = (g.sp || 0) + dt * 900));
        g.x += dx / d * sp * dt; g.y += dy / d * sp * dt;
      }
      if (d < p.r + 8) { g.v2 = g.v; g.v = 0; this.gainXp(g.v2); }
    }
    this.gems = this.gems.filter((g) => g.v > 0);
    // merge if too many lie around
    if (this.gems.length > 380) {
      const old = this.gems.splice(0, 120);
      let sum = 0; for (const g of old) sum += g.v;
      const last = old[old.length - 1];
      this.gems.push({ x: last.x, y: last.y, v: sum, mag: false });
    }

    for (const it of this.pickups) {
      it.bob += dt * 4;
      const dx = p.x - it.x, dy = p.y - it.y, d = Math.hypot(dx, dy) || 1;
      if (it.type === 'coin' && d < mag) { it.x += dx / d * 380 * dt; it.y += dy / d * 380 * dt; }
      if (d < p.r + 14) {
        it.gone = true;
        if (it.type === 'coin') { this.goldRun += it.v; this.sound.play('coin'); }
        else if (it.type === 'heart') { p.hp = Math.min(this.stats.maxHp, p.hp + 30); this.sound.play('heal'); this.burst(p.x, p.y, '#f87171', 12, 120); }
        else if (it.type === 'magnet') { for (const g of this.gems) g.mag = true; this.sound.play('heal'); }
        else if (it.type === 'chest') { this.pendingChest++; this.sound.play('chest'); this.burst(it.x, it.y, '#fde047', 30, 220); }
      }
    }
    this.pickups = this.pickups.filter((it) => !it.gone);
  }

  gainXp(v) {
    this.xp += v;
    this.sound.play('gem');
    while (this.xp >= this.xpNext) {
      this.xp -= this.xpNext;
      this.level++;
      this.xpNext = xpFor(this.level);
      this.pendingLevels++;
    }
  }

  updateFx(dt) {
    for (const q of this.parts) { q.x += q.vx * dt; q.y += q.vy * dt; q.vx *= 0.92; q.vy *= 0.92; q.life -= dt; }
    this.parts = this.parts.filter((q) => q.life > 0);
    for (const n of this.nums) { n.y -= 40 * dt; n.life -= dt; }
    this.nums = this.nums.filter((n) => n.life > 0);
    for (const b of this.bolts) b.life -= dt;
    this.bolts = this.bolts.filter((b) => b.life > 0);
    this.shake = Math.max(0, this.shake - dt * 30);
    if (this.banner) { this.banner.t -= dt; if (this.banner.t <= 0) this.banner = null; }
  }

  // ------------------------------------------------------------ render
  render(ctx, view, S) {
    const { cw, ch, scale } = view;
    this.halfW = cw / scale / 2; this.halfH = ch / scale / 2;
    const p = this.player;
    const sh = this.opts.shake ? this.shake : 0;
    const camX = p.x + rand(-sh, sh), camY = p.y + rand(-sh, sh);

    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = '#0c0e13';
    ctx.fillRect(0, 0, cw, ch);
    ctx.setTransform(scale, 0, 0, scale, cw / 2 - camX * scale, ch / 2 - camY * scale);

    const L = camX - this.halfW, R = camX + this.halfW, T = camY - this.halfH, B = camY + this.halfH;
    drawGround(ctx, L, R, T, B);

    // fire zones
    ctx.globalCompositeOperation = 'lighter';
    for (const z of this.zones) {
      const a = Math.min(1, z.life / z.max * 2) * 0.8;
      ctx.globalAlpha = a;
      const sz = z.r * 2.4;
      ctx.drawImage(S.glowFire.img, z.x - sz / 2, z.y - sz / 2, sz, sz);
    }
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';

    // meteor warnings
    for (const m of this.warnings) {
      const k = 1 - m.t / m.max;
      ctx.fillStyle = `rgba(248,113,113,${0.08 + k * 0.22})`;
      ctx.strokeStyle = 'rgba(252,165,165,0.8)';
      ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(m.x, m.y, m.r, 0, TAU); ctx.fill(); ctx.stroke();
      ctx.beginPath(); ctx.arc(m.x, m.y, m.r * k, 0, TAU); ctx.stroke();
    }

    // aura
    const aura = this.weapons.find((w) => w.id === 'aura');
    if (aura && aura.radius) {
      const pulse = 1 + Math.sin(this.time * 4) * 0.03;
      const gr = ctx.createRadialGradient(p.x, p.y, aura.radius * 0.3, p.x, p.y, aura.radius * pulse);
      gr.addColorStop(0, 'rgba(253,224,71,0.02)');
      gr.addColorStop(0.85, 'rgba(253,186,116,0.13)');
      gr.addColorStop(1, 'rgba(253,186,116,0)');
      ctx.fillStyle = gr;
      ctx.beginPath(); ctx.arc(p.x, p.y, aura.radius * pulse, 0, TAU); ctx.fill();
    }

    // gems
    ctx.globalCompositeOperation = 'lighter';
    for (const g of this.gems) {
      if (g.x < L - 20 || g.x > R + 20 || g.y < T - 20 || g.y > B + 20) continue;
      const tier = g.v >= 20 ? 2 : g.v >= 5 ? 1 : 0;
      const spr = S.glowGem[tier], sz = spr.size;
      ctx.drawImage(spr.img, g.x - sz / 2, g.y - sz / 2, sz, sz);
    }
    ctx.globalCompositeOperation = 'source-over';
    for (const g of this.gems) {
      if (g.x < L - 20 || g.x > R + 20 || g.y < T - 20 || g.y > B + 20) continue;
      const tier = g.v >= 20 ? 2 : g.v >= 5 ? 1 : 0;
      const s = 4 + tier * 1.5;
      ctx.fillStyle = ['#7dd3fc', '#86efac', '#fda4af'][tier];
      ctx.beginPath(); ctx.moveTo(g.x, g.y - s); ctx.lineTo(g.x + s * 0.7, g.y); ctx.lineTo(g.x, g.y + s); ctx.lineTo(g.x - s * 0.7, g.y); ctx.fill();
    }

    // pickups
    for (const it of this.pickups) {
      const y = it.y + Math.sin(it.bob) * 3;
      if (it.type === 'coin') {
        ctx.fillStyle = '#fbbf24'; ctx.beginPath(); ctx.arc(it.x, y, 6, 0, TAU); ctx.fill();
        ctx.fillStyle = '#fde68a'; ctx.fillRect(it.x - 1, y - 3.5, 2, 7);
      } else if (it.type === 'heart') {
        ctx.fillStyle = '#f87171';
        ctx.beginPath(); ctx.moveTo(it.x, y + 7); ctx.bezierCurveTo(it.x - 12, y - 2, it.x - 5, y - 10, it.x, y - 3); ctx.bezierCurveTo(it.x + 5, y - 10, it.x + 12, y - 2, it.x, y + 7); ctx.fill();
      } else if (it.type === 'magnet') {
        ctx.strokeStyle = '#60a5fa'; ctx.lineWidth = 4;
        ctx.beginPath(); ctx.arc(it.x, y, 7, Math.PI, 0); ctx.lineTo(it.x + 7, y + 6); ctx.moveTo(it.x - 7, y); ctx.lineTo(it.x - 7, y + 6); ctx.stroke();
      } else if (it.type === 'chest') {
        ctx.globalCompositeOperation = 'lighter';
        ctx.drawImage(S.glowOrb.img, it.x - 30, y - 30, 60, 60);
        ctx.globalCompositeOperation = 'source-over';
        ctx.fillStyle = '#92400e'; ctx.fillRect(it.x - 12, y - 8, 24, 16);
        ctx.fillStyle = '#fbbf24'; ctx.fillRect(it.x - 12, y - 2, 24, 3); ctx.fillRect(it.x - 2, y - 4, 4, 7);
      }
    }

    // enemies
    for (const e of this.enemies) {
      if (e.x < L - 70 || e.x > R + 70 || e.y < T - 70 || e.y > B + 70) continue;
      const spr = S.enemy[e.type];
      const k = e.elite ? 1.6 : 1;
      const sz = spr.size * k;
      ctx.fillStyle = 'rgba(0,0,0,0.3)';
      ctx.beginPath(); ctx.ellipse(e.x, e.y + e.r * 0.9, e.r * 0.9, e.r * 0.35, 0, 0, TAU); ctx.fill();
      ctx.save();
      ctx.translate(e.x, e.y);
      if (e.type === 'charger') ctx.rotate(e.state === 2 ? Math.atan2(e.dy, e.dx) : Math.atan2(p.y - e.y, p.x - e.x));
      else if (e.face < 0 && e.type !== 'boss') ctx.scale(-1, 1);
      if (e.type === 'wisp' || e.type === 'bat') ctx.translate(0, Math.sin(this.time * 6 + e.id) * 2);
      ctx.drawImage(spr.img, -sz / 2, -sz / 2, sz, sz);
      if (e.flash > 0) {
        ctx.globalAlpha = 0.7;
        ctx.drawImage(S.enemyWhite[e.type].img, -sz / 2, -sz / 2, sz, sz);
        ctx.globalAlpha = 1;
      }
      ctx.restore();
      if (e.elite) {
        ctx.strokeStyle = '#fbbf24'; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.arc(e.x, e.y, e.r + 6, 0, TAU); ctx.stroke();
        this.drawBar(ctx, e.x - 24, e.y - e.r - 14, 48, 5, e.hp / e.maxHp, '#fbbf24');
      }
    }

    // player
    this.drawPlayer(ctx, S);

    // orbit lanterns
    ctx.globalCompositeOperation = 'lighter';
    for (const w of this.weapons) {
      if (w.id !== 'orbit') continue;
      for (let i = 0; i < w.orbs.length; i += 2) {
        ctx.drawImage(S.glowOrb.img, w.orbs[i] - 23, w.orbs[i + 1] - 23, 46, 46);
      }
    }
    // projectiles
    for (const pr of this.projs) {
      if (pr.kind === 'sickle') continue;
      const spr = pr.kind === 'spark' ? S.glowSpark : S.glowEmber;
      const sz = spr.size * (pr.r / 7);
      ctx.drawImage(spr.img, pr.x - sz / 2, pr.y - sz / 2, sz, sz);
    }
    for (const b of this.eprojs) ctx.drawImage(S.glowEnemy.img, b.x - 13, b.y - 13, 26, 26);
    ctx.globalCompositeOperation = 'source-over';
    for (const w of this.weapons) {
      if (w.id !== 'orbit') continue;
      ctx.fillStyle = '#fff7d6';
      for (let i = 0; i < w.orbs.length; i += 2) { ctx.beginPath(); ctx.arc(w.orbs[i], w.orbs[i + 1], 5, 0, TAU); ctx.fill(); }
    }
    for (const pr of this.projs) {
      if (pr.kind !== 'sickle') continue;
      ctx.save(); ctx.translate(pr.x, pr.y); ctx.rotate(pr.spin);
      ctx.fillStyle = '#e0f2fe'; ctx.shadowColor = '#7dd3fc'; ctx.shadowBlur = 10;
      ctx.beginPath(); ctx.arc(0, 0, pr.r, 0.2, Math.PI * 1.3); ctx.arc(pr.r * 0.35, -pr.r * 0.2, pr.r * 0.75, Math.PI * 1.3, 0.2, true); ctx.fill();
      ctx.restore();
    }

    // lightning
    ctx.lineCap = 'round';
    for (const b of this.bolts) {
      ctx.globalAlpha = Math.min(1, b.life / 0.1);
      for (const [col, wdt] of [['rgba(147,197,253,0.5)', 7], ['#eff6ff', 2.5]]) {
        ctx.strokeStyle = col; ctx.lineWidth = wdt;
        ctx.beginPath(); ctx.moveTo(b.pts[0], b.pts[1]);
        for (let i = 2; i < b.pts.length; i += 2) {
          const x0 = b.pts[i - 2], y0 = b.pts[i - 1], x1 = b.pts[i], y1 = b.pts[i + 1];
          ctx.lineTo((x0 + x1) / 2 + rand(-10, 10), (y0 + y1) / 2 + rand(-10, 10));
          ctx.lineTo(x1, y1);
        }
        ctx.stroke();
      }
    }
    ctx.globalAlpha = 1;

    // particles
    ctx.globalCompositeOperation = 'lighter';
    for (const q of this.parts) {
      ctx.globalAlpha = Math.max(0, q.life / q.max);
      ctx.fillStyle = q.color;
      ctx.fillRect(q.x - q.size / 2, q.y - q.size / 2, q.size, q.size);
    }
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';

    // damage numbers
    ctx.textAlign = 'center';
    ctx.lineWidth = 3;
    ctx.strokeStyle = 'rgba(0,0,0,0.8)';
    for (const n of this.nums) {
      ctx.globalAlpha = Math.min(1, n.life * 3);
      ctx.font = `${n.big ? 'bold 16px' : 'bold 12px'} system-ui, sans-serif`;
      ctx.fillStyle = n.big ? '#fde047' : '#ffffff';
      ctx.strokeText(n.v, n.x, n.y); ctx.fillText(n.v, n.x, n.y);
    }
    ctx.globalAlpha = 1;

    // darkness + lantern light
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    const sx = cw / 2 + (p.x - camX) * scale, sy = ch / 2 + (p.y - camY) * scale;
    const inner = 200 * scale, outer = Math.max(cw, ch) * 0.72;
    const dark = ctx.createRadialGradient(sx, sy, inner, sx, sy, outer);
    dark.addColorStop(0, 'rgba(4,5,9,0)');
    dark.addColorStop(1, 'rgba(4,5,9,0.78)');
    ctx.fillStyle = dark;
    ctx.fillRect(0, 0, cw, ch);
    if (p.hurtT > 0) {
      ctx.fillStyle = `rgba(220,38,38,${p.hurtT * 0.6})`;
      ctx.fillRect(0, 0, cw, ch);
    }
    if (this.victoryT >= 0) {
      ctx.fillStyle = `rgba(255,245,220,${Math.max(0, 0.6 - this.victoryT * 0.25)})`;
      ctx.fillRect(0, 0, cw, ch);
    }
  }

  drawBar(ctx, x, y, w, h, k, color) {
    ctx.fillStyle = 'rgba(0,0,0,0.6)'; ctx.fillRect(x - 1, y - 1, w + 2, h + 2);
    ctx.fillStyle = color; ctx.fillRect(x, y, w * Math.max(0, k), h);
  }

  drawPlayer(ctx, S) {
    const p = this.player;
    const bob = p.moving ? Math.sin(p.walk) * 1.5 : 0;
    ctx.globalCompositeOperation = 'lighter';
    ctx.drawImage(S.lantern.img, p.x - 130, p.y - 130, 260, 260);
    ctx.globalCompositeOperation = 'source-over';
    // shadow
    ctx.fillStyle = 'rgba(0,0,0,0.35)';
    ctx.beginPath(); ctx.ellipse(p.x, p.y + 13, 11, 4, 0, 0, TAU); ctx.fill();
    const blink = p.inv > 0 && Math.sin(this.time * 40) > 0;
    ctx.globalAlpha = blink ? 0.45 : 1;
    const dir = p.fx < 0 ? -1 : 1;
    ctx.save(); ctx.translate(p.x, p.y + bob); ctx.scale(dir, 1);
    // cloak
    ctx.fillStyle = '#134e4a';
    ctx.beginPath(); ctx.moveTo(0, -14); ctx.quadraticCurveTo(12, -6, 11, 12); ctx.lineTo(-11, 12); ctx.quadraticCurveTo(-12, -6, 0, -14); ctx.fill();
    ctx.fillStyle = '#0f766e';
    ctx.beginPath(); ctx.moveTo(0, -14); ctx.quadraticCurveTo(10, -10, 8, 0); ctx.lineTo(-8, 0); ctx.quadraticCurveTo(-10, -10, 0, -14); ctx.fill();
    // face
    ctx.fillStyle = '#0b1214';
    ctx.beginPath(); ctx.ellipse(2, -5, 5, 4, 0, 0, TAU); ctx.fill();
    ctx.fillStyle = '#fef3c7';
    ctx.fillRect(3, -6, 2, 2);
    // lantern
    ctx.strokeStyle = '#a16207'; ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.moveTo(10, 0); ctx.lineTo(14, 4); ctx.stroke();
    ctx.fillStyle = '#fde68a'; ctx.shadowColor = '#fbbf24'; ctx.shadowBlur = 14;
    ctx.beginPath(); ctx.roundRect(11, 4, 7, 9, 2); ctx.fill();
    ctx.shadowBlur = 0;
    ctx.restore();
    ctx.globalAlpha = 1;
    this.drawBar(ctx, p.x - 16, p.y + 19, 32, 4, p.hp / this.stats.maxHp, '#ef4444');
  }
}

// Deterministic ground decoration per 160px tile.
function hash(x, y, s) {
  let h = (x * 374761393 + y * 668265263 + s * 2147483647) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
}

function drawGround(ctx, L, R, T, B) {
  const TS = 160;
  const x0 = Math.floor(L / TS), x1 = Math.floor(R / TS), y0 = Math.floor(T / TS), y1 = Math.floor(B / TS);
  for (let tx = x0; tx <= x1; tx++) for (let ty = y0; ty <= y1; ty++) {
    const bx = tx * TS, by = ty * TS;
    // soft patches
    if (hash(tx, ty, 1) < 0.35) {
      ctx.fillStyle = 'rgba(30,41,36,0.55)';
      ctx.beginPath(); ctx.ellipse(bx + hash(tx, ty, 2) * TS, by + hash(tx, ty, 3) * TS, 40 + hash(tx, ty, 4) * 50, 22 + hash(tx, ty, 5) * 25, hash(tx, ty, 6) * 3, 0, TAU); ctx.fill();
    }
    // grass tufts
    ctx.strokeStyle = 'rgba(52,78,62,0.7)';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    for (let i = 0; i < 5; i++) {
      const gx = bx + hash(tx, ty, 10 + i) * TS, gy = by + hash(tx, ty, 20 + i) * TS;
      ctx.moveTo(gx, gy); ctx.lineTo(gx - 2, gy - 6);
      ctx.moveTo(gx + 3, gy); ctx.lineTo(gx + 4, gy - 7);
    }
    ctx.stroke();
    // stones
    if (hash(tx, ty, 30) < 0.25) {
      ctx.fillStyle = 'rgba(71,85,105,0.5)';
      ctx.beginPath(); ctx.ellipse(bx + hash(tx, ty, 31) * TS, by + hash(tx, ty, 32) * TS, 6, 4, 0, 0, TAU); ctx.fill();
    }
    // tiny flowers
    if (hash(tx, ty, 40) < 0.2) {
      ctx.fillStyle = 'rgba(167,139,250,0.55)';
      const fx = bx + hash(tx, ty, 41) * TS, fy = by + hash(tx, ty, 42) * TS;
      ctx.fillRect(fx, fy, 2.5, 2.5); ctx.fillRect(fx + 5, fy + 2, 2.5, 2.5);
    }
  }
}

export { SS };
