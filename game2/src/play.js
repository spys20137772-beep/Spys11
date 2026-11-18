// One level being played: input -> physics -> effects -> camera -> drawing.
import { parseLevel, World, DT, TILE, R, T, launchFromPull, predict, MAX_LAUNCH, MIN_LAUNCH, CRUMBLE_TIME } from './physics.js';
import { LEVELS, WORLDS } from './levels.js';

const TAU = Math.PI * 2;
const rand = (a, b) => a + Math.random() * (b - a);

export const THEMES = {
  kitchen: {
    sky: ['#fff4e6', '#ffd8bd'], block: '#c98b5b', blockDark: '#8f5a35', top: '#fff3df', topEdge: '#ead2b0', speck: 'rgba(90,50,20,0.12)',
    spike: '#a9b4c2', spikeEdge: '#6b7785', deco: 'rgba(214,150,110,0.16)', accent: '#ff7a59',
  },
  garden: {
    sky: ['#e2f6ff', '#d7f5de'], block: '#7a5a3c', blockDark: '#4f3922', top: '#7ccf6a', topEdge: '#4fa84a', speck: 'rgba(40,25,10,0.15)',
    spike: '#8d6e9e', spikeEdge: '#5b4468', deco: 'rgba(255,255,255,0.7)', accent: '#ff6f91',
  },
  night: {
    sky: ['#1b2050', '#4a2d6d'], block: '#4d5196', blockDark: '#2c2f63', top: '#b9b3ff', topEdge: '#8a84e6', speck: 'rgba(255,255,255,0.08)',
    spike: '#ff8fb3', spikeEdge: '#c2477a', deco: 'rgba(255,255,255,0.9)', accent: '#ffd36e',
  },
};

function hash(x, y, s) {
  let h = (x * 374761393 + y * 668265263 + s * 2147483647) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
}

export class Play {
  constructor(app, index) {
    this.app = app;
    this.index = index;
    this.def = LEVELS[index];
    this.L = parseLevel(this.def);
    this.world = new World(this.L);
    this.themeName = WORLDS[this.def.world - 1].theme;
    this.th = THEMES[this.themeName];
    this.prev = app.save.level(this.def.id);
    this.parts = [];
    this.cam = { x: this.L.start.x, y: this.L.start.y };
    this.shake = 0;
    this.acc = 0;
    this.deadT = 0;
    this.clearT = -1;
    this.sq = { a: 0, v: 0 };
    this.time = 0;
    this.aim = { ang: -Math.PI / 4, k: 0.6, active: false };
    this.aimVec = null;
    this.pred = null;
    this.blinkT = 2;
    this.flagT = [];
    this.dynamic = [];
    for (let i = 0; i < this.L.grid.length; i++) {
      const t = this.L.grid[i];
      if (t === T.CRATE || t === T.CRUMBLE || t === T.FAN) this.dynamic.push(i);
    }
    this.layer = this.buildStatic();
    this.bgStars = Array.from({ length: 70 }, () => ({ x: Math.random(), y: Math.random(), s: rand(0.6, 1.8), p: Math.random() * TAU }));
    this.clouds = Array.from({ length: 6 }, (_, i) => ({ x: Math.random(), y: 0.08 + Math.random() * 0.45, s: rand(0.6, 1.3), v: rand(4, 10) }));
  }

  // ------------------------------------------------------------ update
  update(dt, input) {
    const app = this.app, w = this.world, p = w.p;
    this.time += dt;
    const maxPull = Math.min(170, Math.max(90, innerHeight * 0.26));

    // aiming
    let aimVec = null, launchVec = null;
    if (input.drag) {
      const dx = input.drag.x - input.drag.ox, dy = input.drag.y - input.drag.oy;
      if (Math.hypot(dx, dy) > 12) { aimVec = launchFromPull(dx, dy, maxPull); this.aim.active = false; }
    }
    if (input.released) {
      const r = input.released; input.released = null;
      if (Math.hypot(r.dx, r.dy) > 18) launchVec = launchFromPull(r.dx, r.dy, maxPull);
    }
    const L = input.held('ArrowLeft') || input.held('KeyA'), Rr = input.held('ArrowRight') || input.held('KeyD');
    const U = input.held('ArrowUp') || input.held('KeyW'), D = input.held('ArrowDown') || input.held('KeyS');
    if (L || Rr || U || D) {
      this.aim.active = true;
      if (L) this.aim.ang -= 2.2 * dt;
      if (Rr) this.aim.ang += 2.2 * dt;
      if (U) this.aim.k = Math.min(1, this.aim.k + 0.9 * dt);
      if (D) this.aim.k = Math.max(0.08, this.aim.k - 0.9 * dt);
    }
    const pa = input.padAim();
    if (pa) { this.aim.active = true; this.aim.ang = Math.atan2(pa.y, pa.x); this.aim.k = Math.max(0.08, pa.k); }
    if (this.aim.active && !aimVec) {
      const sp = MIN_LAUNCH + (MAX_LAUNCH - MIN_LAUNCH) * this.aim.k;
      aimVec = { vx: Math.cos(this.aim.ang) * sp, vy: Math.sin(this.aim.ang) * sp, k: this.aim.k };
      if (input.act('launch')) launchVec = aimVec;
    }
    if (launchVec && w.canLaunch()) w.launch(launchVec.vx, launchVec.vy);
    this.aimVec = w.canLaunch() ? aimVec : null;
    this.pred = this.aimVec && app.save.data.options.preview ? predict(w, this.aimVec.vx, this.aimVec.vy, 0.85, 3) : null;

    // physics
    if (this.deadT > 0) {
      this.deadT -= dt;
      if (this.deadT <= 0) { w.respawnPlayer(); this.burst(w.p.x, w.p.y, '#ffffff', 14, 120, 3); }
    }
    this.acc += dt;
    let steps = 0;
    while (this.acc >= DT && steps < 12) { w.step(DT); this.acc -= DT; steps++; }
    if (steps >= 12) this.acc = 0;
    this.handleEvents();

    if (this.clearT > 0) {
      this.clearT -= dt;
      if (this.clearT <= 0) app.levelClear(this);
    }

    // squash spring
    this.sq.v += (-this.sq.a * 260 - this.sq.v * 13) * dt;
    this.sq.a += this.sq.v * dt;
    this.blinkT -= dt;
    if (this.blinkT < -0.12) this.blinkT = rand(2, 4.5);

    // camera
    const view = app.view;
    const hw = view.cw / view.scale / 2, hh = view.ch / view.scale / 2;
    let tx = p.x, ty = p.y;
    if (this.aimVec) { const m = Math.hypot(this.aimVec.vx, this.aimVec.vy) || 1; tx += this.aimVec.vx / m * 80; ty += this.aimVec.vy / m * 80; }
    const k = Math.min(1, dt * 5);
    this.cam.x += (tx - this.cam.x) * k;
    this.cam.y += (ty - this.cam.y) * k;
    const LW = this.L.W * TILE, LH = this.L.H * TILE;
    this.cam.x = LW <= hw * 2 ? LW / 2 : Math.max(hw - 40, Math.min(LW - hw + 40, this.cam.x));
    this.cam.y = LH <= hh * 2 ? LH / 2 : Math.max(hh - 40, Math.min(LH - hh + 40, this.cam.y));
    this.shake = Math.max(0, this.shake - dt * 25);

    for (const q of this.parts) { q.vy += (q.g || 0) * dt; q.x += q.vx * dt; q.y += q.vy * dt; q.vx *= 0.97; q.life -= dt; q.rot = (q.rot || 0) + (q.spin || 0) * dt; }
    this.parts = this.parts.filter((q) => q.life > 0);
  }

  handleEvents() {
    const app = this.app, w = this.world, s = app.sound;
    for (const ev of w.events) {
      switch (ev.type) {
        case 'launch': s.play('launch'); this.sq.a = 0.25; this.sq.v = 0; this.burst(w.p.x, w.p.y, '#fffaf0', 6, 80, 3); break;
        case 'stick': {
          if (ev.speed > 60) {
            s.play('stick');
            const k = Math.min(1, ev.speed / 900);
            this.sq.a = -0.45 * k - 0.1; this.sq.v = 0;
            const cx = ev.x - ev.nx * R, cy = ev.y - ev.ny * R;
            for (let i = 0; i < 8; i++) {
              const a = Math.atan2(ev.ny, ev.nx) + rand(-1.3, 1.3), sp = rand(40, 160) * (0.4 + k);
              this.parts.push({ x: cx, y: cy, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, life: 0.4, max: 0.4, size: rand(2, 4), color: '#fff8ee', g: 300 });
            }
            if (ev.speed > 700) this.shake = Math.max(this.shake, 3);
          }
          break;
        }
        case 'boing': s.play('boing'); this.sq.a = 0.4; this.burst(ev.x, ev.y, '#ff7d8a', 10, 180, 4); break;
        case 'clink': s.play('clink'); this.burst(ev.x, ev.y, '#dff6ff', 5, 120, 2); break;
        case 'break':
          s.play('break'); this.shake = Math.max(this.shake, 6);
          for (let i = 0; i < 14; i++) this.parts.push({ x: ev.x + rand(-14, 14), y: ev.y + rand(-14, 14), vx: rand(-220, 220), vy: rand(-320, 40), life: 0.9, max: 0.9, size: rand(5, 10), color: i % 2 ? '#b07a44' : '#d39b5f', g: 900, spin: rand(-10, 10), plank: true });
          break;
        case 'crumble': {
          s.play('crumble');
          const x = (ev.idx % w.W) * TILE + TILE / 2, y = Math.floor(ev.idx / w.W) * TILE + TILE / 2;
          for (let i = 0; i < 10; i++) this.parts.push({ x: x + rand(-16, 16), y: y + rand(-10, 10), vx: rand(-60, 60), vy: rand(-80, 20), life: 0.8, max: 0.8, size: rand(3, 6), color: '#d9a86c', g: 900 });
          break;
        }
        case 'berry': s.play('berry'); this.sparkle(ev.x, ev.y, '#ff4d6d'); break;
        case 'flag': s.play('flag'); this.sparkle(this.L.flags[ev.i].x, this.L.flags[ev.i].y - 30, this.th.accent); break;
        case 'die':
          s.play('die'); this.deadT = 0.7; this.shake = Math.max(this.shake, 7);
          this.burst(ev.x, ev.y, '#ffffff', 22, 260, 5); this.burst(ev.x, ev.y, '#ffd1dc', 10, 200, 4);
          app.save.data.deaths++;
          break;
        case 'goal':
          s.play('goal'); this.clearT = 1.1;
          for (let i = 0; i < 40; i++) {
            const a = rand(-Math.PI, 0), sp = rand(150, 420);
            this.parts.push({ x: this.L.goal.x, y: this.L.goal.y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, life: 1.2, max: 1.2, size: rand(4, 7), color: ['#ff6f91', '#ffd36e', '#7ccf6a', '#6ec5ff', '#b39cff'][i % 5], g: 500, spin: rand(-12, 12), plank: true });
          }
          break;
      }
    }
    w.events.length = 0;
  }

  burst(x, y, color, n, speed, size) {
    for (let i = 0; i < n; i++) {
      const a = Math.random() * TAU, sp = speed * rand(0.3, 1);
      this.parts.push({ x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, life: 0.5, max: 0.5, size: size * rand(0.6, 1.2), color });
    }
  }

  sparkle(x, y, color) {
    for (let i = 0; i < 12; i++) {
      const a = (i / 12) * TAU, sp = rand(90, 170);
      this.parts.push({ x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, life: 0.55, max: 0.55, size: 4, color, star: true });
    }
  }

  // ------------------------------------------------------------ static layer
  buildStatic() {
    const L = this.L, th = this.th;
    let RS = 2;
    const maxDim = Math.max(L.W, L.H) * TILE;
    if (maxDim * RS > 4096) RS = 4096 / maxDim;
    const c = document.createElement('canvas');
    c.width = Math.ceil(L.W * TILE * RS); c.height = Math.ceil(L.H * TILE * RS);
    const g = c.getContext('2d');
    g.scale(RS, RS);
    const at = (x, y) => (x < 0 || y < 0 || x >= L.W || y >= L.H ? T.SOLID : L.grid[y * L.W + x]);
    const isBlock = (t) => t === T.SOLID;

    for (let y = 0; y < L.H; y++) for (let x = 0; x < L.W; x++) {
      const t = at(x, y), X = x * TILE, Y = y * TILE;
      if (t === T.SOLID) {
        g.fillStyle = th.block; g.fillRect(X, Y, TILE + 0.5, TILE + 0.5);
        g.fillStyle = th.speck;
        for (let i = 0; i < 4; i++) g.fillRect(X + hash(x, y, i) * 34 + 2, Y + hash(x, y, i + 9) * 34 + 2, 3, 3);
      }
    }
    // edges and tops
    for (let y = 0; y < L.H; y++) for (let x = 0; x < L.W; x++) {
      if (at(x, y) !== T.SOLID) continue;
      const X = x * TILE, Y = y * TILE;
      g.fillStyle = th.blockDark;
      if (!isBlock(at(x, y + 1))) g.fillRect(X, Y + TILE - 5, TILE, 5);
      if (!isBlock(at(x - 1, y))) g.fillRect(X, Y, 3, TILE);
      if (!isBlock(at(x + 1, y))) g.fillRect(X + TILE - 3, Y, 3, TILE);
      if (!isBlock(at(x, y - 1))) {
        g.fillStyle = th.top;
        g.fillRect(X, Y, TILE, 7);
        g.beginPath();
        for (let i = 0; i < 4; i++) g.arc(X + 5 + i * 10, Y + 7, 5, 0, Math.PI);
        g.fill();
        g.fillStyle = th.topEdge; g.fillRect(X, Y, TILE, 2);
        if (this.themeName === 'garden') {
          g.strokeStyle = th.topEdge; g.lineWidth = 2;
          g.beginPath();
          for (let i = 0; i < 3; i++) { const gx = X + 6 + hash(x, y, 30 + i) * 28; g.moveTo(gx, Y + 1); g.lineTo(gx - 2, Y - 6); g.moveTo(gx + 3, Y + 1); g.lineTo(gx + 4, Y - 5); }
          g.stroke();
        }
      }
    }
    for (let y = 0; y < L.H; y++) for (let x = 0; x < L.W; x++) {
      const t = at(x, y), X = x * TILE, Y = y * TILE;
      if (t === T.ICE) {
        g.fillStyle = 'rgba(190,232,255,0.6)'; g.fillRect(X, Y, TILE, TILE);
        g.strokeStyle = 'rgba(255,255,255,0.85)'; g.lineWidth = 2; g.strokeRect(X + 1, Y + 1, TILE - 2, TILE - 2);
        g.strokeStyle = 'rgba(255,255,255,0.6)'; g.lineWidth = 3;
        g.beginPath(); g.moveTo(X + 8, Y + 30); g.lineTo(X + 22, Y + 10); g.moveTo(X + 18, Y + 34); g.lineTo(X + 28, Y + 20); g.stroke();
      } else if (t === T.SPIKE) {
        let dir = 'up';
        if (isSolidish(at(x, y + 1))) dir = 'up'; else if (isSolidish(at(x, y - 1))) dir = 'down';
        else if (isSolidish(at(x - 1, y))) dir = 'right'; else if (isSolidish(at(x + 1, y))) dir = 'left';
        g.save(); g.translate(X + TILE / 2, Y + TILE / 2);
        g.rotate({ up: 0, right: Math.PI / 2, down: Math.PI, left: -Math.PI / 2 }[dir]);
        g.fillStyle = th.spike; g.strokeStyle = th.spikeEdge; g.lineWidth = 1.5;
        for (let i = 0; i < 3; i++) {
          const bx = -20 + i * 13.33;
          g.beginPath(); g.moveTo(bx, 20); g.lineTo(bx + 6.67, -8); g.lineTo(bx + 13.33, 20); g.closePath(); g.fill(); g.stroke();
        }
        g.fillStyle = 'rgba(255,255,255,0.5)';
        for (let i = 0; i < 3; i++) { const bx = -20 + i * 13.33; g.fillRect(bx + 5.5, -2, 1.6, 14); }
        g.restore();
      } else if (t === T.BOUNCE) {
        g.fillStyle = '#f3e3c3'; g.fillRect(X + 13, Y + 18, 14, 22);
        g.fillStyle = '#e5534b';
        g.beginPath(); g.ellipse(X + 20, Y + 20, 21, 17, 0, Math.PI, 0); g.lineTo(X + 41, Y + 22); g.lineTo(X - 1, Y + 22); g.fill();
        g.fillStyle = '#fff';
        for (const [dx, dy, r] of [[8, 12, 3.5], [20, 7, 4], [31, 13, 3], [15, 17, 2.5]]) { g.beginPath(); g.arc(X + dx, Y + dy, r, 0, TAU); g.fill(); }
      } else if (t === T.FAN) {
        g.fillStyle = '#3b3f6e'; g.fillRect(X + 2, Y + 8, TILE - 4, TILE - 8);
        g.fillStyle = '#6c71b5'; g.fillRect(X + 2, Y + 4, TILE - 4, 6);
      }
    }
    function isSolidish(t) { return t === T.SOLID || t === T.ICE || t === T.CRATE || t === T.CRUMBLE || t === T.FAN || t === T.BOUNCE; }
    return c;
  }

  // ------------------------------------------------------------ render
  render(ctx, view) {
    const { cw, ch, scale } = view;
    const th = this.th, w = this.world, L = this.L;
    const sh = this.app.save.data.options.shake ? this.shake : 0;
    const camX = this.cam.x + rand(-sh, sh), camY = this.cam.y + rand(-sh, sh);

    this.drawBackground(ctx, cw, ch, camX, camY, scale);

    ctx.setTransform(scale, 0, 0, scale, cw / 2 - camX * scale, ch / 2 - camY * scale);
    ctx.drawImage(this.layer, 0, 0, L.W * TILE, L.H * TILE);

    // fan wind streaks
    for (const f of L.fans) {
      if (w.grid[f.ty * L.W + Math.floor(f.x0 / TILE)] !== T.FAN) continue;
      const h = f.y1 - f.y0;
      ctx.fillStyle = 'rgba(220,230,255,0.10)';
      ctx.fillRect(f.x0 + 4, f.y0, TILE - 8, h);
      ctx.strokeStyle = 'rgba(235,240,255,0.55)'; ctx.lineWidth = 2;
      ctx.beginPath();
      for (let i = 0; i < 4; i++) {
        const ph = ((this.time * 260 + i * h / 4 + f.tx * 37) % h);
        const yy = f.y1 - ph, xx = f.x0 + 8 + ((i * 11 + f.tx * 7) % 24);
        ctx.moveTo(xx, yy); ctx.lineTo(xx, yy - 18);
      }
      ctx.stroke();
    }

    // dynamic tiles
    for (const idx of this.dynamic) {
      const t0 = L.grid[idx], t = w.grid[idx];
      const x = (idx % L.W) * TILE, y = Math.floor(idx / L.W) * TILE;
      if (t0 === T.CRATE && t === T.CRATE) drawCrate(ctx, x, y);
      else if (t0 === T.CRUMBLE) {
        const c = w.crumble.get(idx);
        if (t === T.CRUMBLE) {
          const shake = c && !c.gone ? (1 - c.t / CRUMBLE_TIME) * 3 : 0;
          drawBiscuit(ctx, x + rand(-shake, shake), y + rand(-shake, shake), 1);
        } else {
          drawBiscuit(ctx, x, y, 0.18);
        }
      } else if (t0 === T.FAN) {
        ctx.save(); ctx.translate(x + TILE / 2, y + 6);
        ctx.scale(1, 0.35);
        ctx.rotate(this.time * 14);
        ctx.fillStyle = '#d4d8ff';
        for (let i = 0; i < 3; i++) { ctx.rotate(TAU / 3); ctx.beginPath(); ctx.ellipse(9, 0, 10, 4, 0, 0, TAU); ctx.fill(); }
        ctx.restore();
      }
    }

    // flags
    L.flags.forEach((f, i) => {
      const on = i === w.flagIdx;
      ctx.fillStyle = '#e8e2d6'; ctx.fillRect(f.x - 2, f.y - 44, 3, 44);
      const wave = Math.sin(this.time * 6 + i) * 3;
      ctx.fillStyle = on ? th.accent : 'rgba(255,255,255,0.85)';
      ctx.beginPath(); ctx.moveTo(f.x + 1, f.y - 44); ctx.quadraticCurveTo(f.x + 14, f.y - 40 + wave, f.x + 24, f.y - 36); ctx.lineTo(f.x + 1, f.y - 28); ctx.fill();
    });

    // goal
    const g = L.goal, t = this.time;
    ctx.save(); ctx.translate(g.x, g.y);
    const gr = ctx.createRadialGradient(0, 0, 4, 0, 0, 34);
    gr.addColorStop(0, 'rgba(255,240,180,0.95)'); gr.addColorStop(1, 'rgba(255,200,120,0)');
    ctx.fillStyle = gr; ctx.beginPath(); ctx.arc(0, 0, 34, 0, TAU); ctx.fill();
    ctx.rotate(t * 1.5);
    ctx.strokeStyle = '#ffb347'; ctx.lineWidth = 3; ctx.setLineDash([6, 6]);
    ctx.beginPath(); ctx.arc(0, 0, 20, 0, TAU); ctx.stroke(); ctx.setLineDash([]);
    ctx.rotate(-t * 1.5);
    drawStar(ctx, 0, Math.sin(t * 3) * 2, 11, '#ffd36e', '#e8a33a');
    ctx.restore();

    // berries
    L.berries.forEach((b, i) => {
      if (w.got[i]) return;
      const y = b.y + Math.sin(t * 3 + i) * 3;
      ctx.globalAlpha = this.prev.berries[i] ? 0.45 : 1;
      drawBerry(ctx, b.x, y);
      ctx.globalAlpha = 1;
    });

    // trajectory preview
    if (this.pred) {
      const pts = this.pred.pts;
      for (let i = 0; i < pts.length; i += 2) {
        const k = i / pts.length;
        ctx.globalAlpha = 0.9 - k * 0.7;
        ctx.fillStyle = this.pred.dead && i >= pts.length - 4 ? '#ff4d6d' : (this.themeName === 'night' ? '#ffffff' : '#5a3e2b');
        ctx.beginPath(); ctx.arc(pts[i], pts[i + 1], 3.2 - k * 1.6, 0, TAU); ctx.fill();
      }
      ctx.globalAlpha = 1;
    }

    // power ring + arrow
    const p = w.p;
    if (this.aimVec && !p.dead) {
      const k = this.aimVec.k ?? 0.5, ang = Math.atan2(this.aimVec.vy, this.aimVec.vx);
      ctx.strokeStyle = 'rgba(255,255,255,0.35)'; ctx.lineWidth = 4;
      ctx.beginPath(); ctx.arc(p.x, p.y, R + 9, 0, TAU); ctx.stroke();
      ctx.strokeStyle = k > 0.95 ? '#ff6f61' : th.accent; ctx.lineWidth = 4;
      ctx.beginPath(); ctx.arc(p.x, p.y, R + 9, ang - Math.PI * k, ang + Math.PI * k); ctx.stroke();
      const ax = p.x + Math.cos(ang) * (R + 16 + k * 18), ay = p.y + Math.sin(ang) * (R + 16 + k * 18);
      ctx.save(); ctx.translate(ax, ay); ctx.rotate(ang);
      ctx.fillStyle = th.accent; ctx.beginPath(); ctx.moveTo(8, 0); ctx.lineTo(-5, -7); ctx.lineTo(-5, 7); ctx.fill();
      ctx.restore();
    }

    if (!p.dead) this.drawMochi(ctx);

    // particles
    for (const q of this.parts) {
      ctx.globalAlpha = Math.max(0, Math.min(1, q.life / q.max * 1.5));
      ctx.fillStyle = q.color;
      if (q.star) drawStar(ctx, q.x, q.y, q.size, q.color, null);
      else if (q.plank) { ctx.save(); ctx.translate(q.x, q.y); ctx.rotate(q.rot || 0); ctx.fillRect(-q.size / 2, -q.size / 4, q.size, q.size / 2); ctx.restore(); }
      else { ctx.beginPath(); ctx.arc(q.x, q.y, q.size, 0, TAU); ctx.fill(); }
    }
    ctx.globalAlpha = 1;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
  }

  drawBackground(ctx, cw, ch, camX, camY, scale) {
    const th = this.th;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    const gr = ctx.createLinearGradient(0, 0, 0, ch);
    gr.addColorStop(0, th.sky[0]); gr.addColorStop(1, th.sky[1]);
    ctx.fillStyle = gr; ctx.fillRect(0, 0, cw, ch);
    if (this.themeName === 'kitchen') {
      // wall tiles with parallax
      const s = 70 * scale, ox = -((camX * 0.3 * scale) % s), oy = -((camY * 0.3 * scale) % s);
      ctx.strokeStyle = th.deco; ctx.lineWidth = 2 * scale;
      ctx.beginPath();
      for (let x = ox - s; x < cw + s; x += s) { ctx.moveTo(x, 0); ctx.lineTo(x, ch); }
      for (let y = oy - s; y < ch + s; y += s) { ctx.moveTo(0, y); ctx.lineTo(cw, y); }
      ctx.stroke();
    } else if (this.themeName === 'garden') {
      for (const c of this.clouds) {
        const x = ((c.x * cw + this.time * c.v * scale - camX * 0.1 * scale) % (cw + 300 * scale) + cw + 300 * scale) % (cw + 300 * scale) - 150 * scale;
        const y = c.y * ch;
        ctx.fillStyle = th.deco;
        ctx.beginPath();
        const r = 26 * c.s * scale;
        ctx.arc(x, y, r, 0, TAU); ctx.arc(x + r, y + r * 0.2, r * 0.8, 0, TAU); ctx.arc(x - r, y + r * 0.25, r * 0.7, 0, TAU);
        ctx.fill();
      }
      ctx.fillStyle = 'rgba(124,207,106,0.25)';
      ctx.beginPath(); ctx.moveTo(0, ch);
      for (let x = 0; x <= cw; x += 20) ctx.lineTo(x, ch * 0.78 + Math.sin((x + camX * 0.2 * scale) / (120 * scale)) * 26 * scale);
      ctx.lineTo(cw, ch); ctx.fill();
    } else {
      for (const s of this.bgStars) {
        const tw = 0.5 + 0.5 * Math.sin(this.time * 2 + s.p);
        ctx.globalAlpha = 0.3 + tw * 0.7;
        ctx.fillStyle = '#fff';
        const x = ((s.x * cw - camX * 0.05 * scale) % cw + cw) % cw, y = ((s.y * ch - camY * 0.05 * scale) % ch + ch) % ch;
        ctx.beginPath(); ctx.arc(x, y, s.s * scale, 0, TAU); ctx.fill();
      }
      ctx.globalAlpha = 1;
      ctx.fillStyle = 'rgba(255,244,214,0.9)';
      ctx.beginPath(); ctx.arc(cw * 0.82, ch * 0.18, 34 * scale, 0, TAU); ctx.fill();
      ctx.fillStyle = th.sky[0];
      ctx.beginPath(); ctx.arc(cw * 0.82 + 14 * scale, ch * 0.18 - 8 * scale, 30 * scale, 0, TAU); ctx.fill();
    }
  }

  drawMochi(ctx) {
    const p = this.world.p;
    let rot = 0, along = 1, perp = 1, ox = 0, oy = 0;
    const sq = this.sq.a;
    if (p.stuck) {
      rot = Math.atan2(p.ny, p.nx);
      along = Math.max(0.55, 0.9 + sq);
      perp = 1 + (1 - along) * 0.6;
      ox = -p.nx * (1 - along) * R; oy = -p.ny * (1 - along) * R;
    } else {
      const sp = Math.hypot(p.vx, p.vy);
      rot = Math.atan2(p.vy, p.vx);
      along = 1 + Math.min(0.32, sp / 2600) + Math.max(0, sq) * 0.5;
      perp = 1 / along;
    }
    ctx.save();
    ctx.translate(p.x + ox, p.y + oy);
    ctx.save();
    ctx.rotate(rot);
    ctx.scale(along, perp);
    ctx.fillStyle = 'rgba(0,0,0,0.12)';
    ctx.beginPath(); ctx.arc(1.5, 2, R, 0, TAU); ctx.fill();
    const gr = ctx.createRadialGradient(-4, -5, 2, 0, 0, R);
    gr.addColorStop(0, '#ffffff'); gr.addColorStop(1, '#f6ecdc');
    ctx.fillStyle = gr;
    ctx.beginPath(); ctx.arc(0, 0, R, 0, TAU); ctx.fill();
    ctx.strokeStyle = '#e0cfb5'; ctx.lineWidth = 1.5; ctx.stroke();
    ctx.restore();
    // face
    let lx = 0, ly = 0;
    const v = this.aimVec || (p.stuck ? null : { vx: p.vx, vy: p.vy });
    if (v) { const m = Math.hypot(v.vx, v.vy) || 1; lx = v.vx / m * 3.5; ly = v.vy / m * 3.5; }
    const blink = this.blinkT < 0;
    ctx.fillStyle = '#3a2a22';
    for (const ex of [-4.5, 4.5]) {
      ctx.beginPath();
      if (blink) ctx.fillRect(ex + lx - 2, ly - 1, 4, 1.6);
      else ctx.ellipse(ex + lx, ly - 1, 1.9, 2.6, 0, 0, TAU);
      ctx.fill();
    }
    ctx.fillStyle = 'rgba(255,140,160,0.55)';
    ctx.beginPath(); ctx.ellipse(-8 + lx * 0.6, 3 + ly * 0.6, 2.8, 1.8, 0, 0, TAU); ctx.ellipse(8 + lx * 0.6, 3 + ly * 0.6, 2.8, 1.8, 0, 0, TAU); ctx.fill();
    ctx.strokeStyle = '#3a2a22'; ctx.lineWidth = 1.2;
    ctx.beginPath();
    if (!p.stuck) { ctx.arc(lx, 3 + ly, 2.2, 0, TAU); }
    else { ctx.moveTo(lx - 2.5, 3 + ly); ctx.quadraticCurveTo(lx - 1.2, 4.6 + ly, lx, 3 + ly); ctx.quadraticCurveTo(lx + 1.2, 4.6 + ly, lx + 2.5, 3 + ly); }
    ctx.stroke();
    ctx.restore();
  }
}

function drawCrate(ctx, x, y) {
  ctx.fillStyle = '#b07a44'; ctx.fillRect(x + 1, y + 1, TILE - 2, TILE - 2);
  ctx.strokeStyle = '#7a4f26'; ctx.lineWidth = 3; ctx.strokeRect(x + 2.5, y + 2.5, TILE - 5, TILE - 5);
  ctx.beginPath(); ctx.moveTo(x + 4, y + 4); ctx.lineTo(x + TILE - 4, y + TILE - 4); ctx.moveTo(x + TILE - 4, y + 4); ctx.lineTo(x + 4, y + TILE - 4); ctx.stroke();
  ctx.fillStyle = 'rgba(255,255,255,0.15)'; ctx.fillRect(x + 4, y + 4, TILE - 8, 4);
}

function drawBiscuit(ctx, x, y, alpha) {
  ctx.globalAlpha = alpha;
  ctx.fillStyle = '#e0b072';
  ctx.beginPath(); ctx.roundRect(x + 1, y + 4, TILE - 2, TILE - 10, 6); ctx.fill();
  ctx.strokeStyle = '#a8743b'; ctx.lineWidth = 2; ctx.stroke();
  ctx.fillStyle = '#a8743b';
  for (const [dx, dy] of [[10, 14], [20, 20], [30, 13], [14, 26], [27, 27]]) { ctx.beginPath(); ctx.arc(x + dx, y + dy, 1.8, 0, TAU); ctx.fill(); }
  ctx.globalAlpha = 1;
}

function drawBerry(ctx, x, y) {
  ctx.fillStyle = '#ff4d6d';
  ctx.beginPath(); ctx.moveTo(x, y + 11); ctx.bezierCurveTo(x - 13, y + 2, x - 10, y - 9, x, y - 7); ctx.bezierCurveTo(x + 10, y - 9, x + 13, y + 2, x, y + 11); ctx.fill();
  ctx.fillStyle = '#ffe9a8';
  for (const [dx, dy] of [[-4, -1], [3, -2], [0, 4], [-5, 5], [5, 4]]) ctx.fillRect(x + dx, y + dy, 1.6, 2);
  ctx.fillStyle = '#4caf50';
  ctx.beginPath(); ctx.moveTo(x, y - 6); ctx.lineTo(x - 7, y - 10); ctx.lineTo(x - 2, y - 8); ctx.lineTo(x, y - 13); ctx.lineTo(x + 2, y - 8); ctx.lineTo(x + 7, y - 10); ctx.closePath(); ctx.fill();
}

function drawStar(ctx, x, y, r, fill, stroke) {
  ctx.beginPath();
  for (let i = 0; i < 10; i++) {
    const a = -Math.PI / 2 + (i / 10) * TAU, rr = i % 2 ? r * 0.45 : r;
    ctx.lineTo(x + Math.cos(a) * rr, y + Math.sin(a) * rr);
  }
  ctx.closePath();
  ctx.fillStyle = fill; ctx.fill();
  if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = 1.5; ctx.stroke(); }
}
