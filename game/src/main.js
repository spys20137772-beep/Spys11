import { Input } from './input.js';
import { Sound } from './audio.js';
import { Save } from './save.js';
import { Game } from './game.js';
import { UI } from './ui.js';
import { buildSprites } from './sprites.js';

const canvas = document.getElementById('c');
const ctx = canvas.getContext('2d');
const params = new URLSearchParams(location.search);

const app = {
  state: 'title', // title | playing | levelup | paused | result
  game: null,
  timeScale: 1,
  autoPick: false,
  fps: 60,
  showFps: params.has('fps'),
  input: new Input(),
  sound: new Sound(),
  save: new Save(),
  sprites: buildSprites(),
  view: { cw: 1, ch: 1, scale: 1 },
  titleFx: [],
};
app.ui = new UI(app);

// ---------------------------------------------------------------- flow
app.startRun = () => {
  app.sound.init();
  app.game = new Game(app);
  if (app.godMode) app.game.god = true;
  app.state = 'playing';
  app.ui.stack = [];
  app.ui.hide();
  app.ui.showHud(true);
  app.ui.hudCache = {};
  app.sound.music('battle');
};

app.toTitle = () => {
  app.game = null;
  app.state = 'title';
  app.ui.stack = [];
  app.ui.showHud(false);
  app.ui.show('title');
  app.sound.music('menu');
};

app.resume = () => {
  app.state = 'playing';
  app.ui.stack = [];
  app.ui.hide();
};

app.pick = (choice) => {
  const g = app.game;
  g.applyChoice(choice);
  if (app.levelupChest) g.pendingChest--; else g.pendingLevels--;
  app.sound.play('levelup');
  g.burst(g.player.x, g.player.y, '#fde68a', 24, 200);
  app.state = 'playing';
  app.ui.hide();
};

app.openLevelup = () => {
  const g = app.game;
  app.levelupChest = g.pendingChest > 0;
  const choices = g.rollChoices(app.levelupChest ? 3 : 3);
  if (app.autoPick) { app.pick(choices[0]); return; }
  app.state = 'levelup';
  app.sound.play(app.levelupChest ? 'chest' : 'levelup');
  app.ui.show('levelup', { choices, chest: app.levelupChest });
};

app.endRun = () => {
  const r = app.game.result;
  r.newBest = app.save.recordRun(r);
  app.state = 'result';
  app.ui.showHud(false);
  app.ui.stack = [];
  app.ui.show('result', r);
  app.sound.music('menu');
};

app.applyOptions = (changed) => {
  const o = app.save.data.options;
  app.sound.setVolumes({ master: o.master, music: o.music, sfx: o.sfx });
  if (changed === 'fullscreen') {
    try {
      if (o.fullscreen && !document.fullscreenElement) document.documentElement.requestFullscreen();
      else if (!o.fullscreen && document.fullscreenElement) document.exitFullscreen();
    } catch { /* not allowed */ }
  }
  app.save.write();
};

document.addEventListener('fullscreenchange', () => {
  app.save.data.options.fullscreen = !!document.fullscreenElement;
});

// ---------------------------------------------------------------- view
function resize() {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.floor(innerWidth * dpr);
  canvas.height = Math.floor(innerHeight * dpr);
  // world units visible vertically ~ 720 at any resolution
  const zoom = Math.max(0.6, Math.min(2.2, innerHeight / 720));
  app.view = { cw: canvas.width, ch: canvas.height, scale: dpr * zoom, dpr };
}
addEventListener('resize', resize);
resize();

function renderTitle(dt) {
  const { cw, ch } = app.view;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  const g = ctx.createRadialGradient(cw / 2, ch * 0.62, 0, cw / 2, ch * 0.62, Math.max(cw, ch) * 0.7);
  g.addColorStop(0, '#2a1d0e');
  g.addColorStop(0.35, '#121018');
  g.addColorStop(1, '#07080b');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, cw, ch);
  // rising embers
  const fx = app.titleFx;
  if (fx.length < 90) fx.push({ x: Math.random() * cw, y: ch + 10, v: 20 + Math.random() * 60, s: 1 + Math.random() * 2.5, w: Math.random() * 6 });
  ctx.globalCompositeOperation = 'lighter';
  for (const p of fx) {
    p.y -= p.v * dt * app.view.dpr; p.w += dt;
    const x = p.x + Math.sin(p.w) * 14;
    ctx.globalAlpha = Math.min(1, p.y / ch) * 0.9;
    ctx.fillStyle = '#fbbf24';
    ctx.beginPath(); ctx.arc(x, p.y, p.s * app.view.dpr, 0, Math.PI * 2); ctx.fill();
  }
  ctx.globalAlpha = 1;
  ctx.globalCompositeOperation = 'source-over';
  app.titleFx = fx.filter((p) => p.y > -10);
}

// ---------------------------------------------------------------- loop
let last = performance.now(), fpsAcc = 0, fpsN = 0;
const fpsEl = document.getElementById('fps');

function frame(now) {
  const rawDt = Math.min(0.1, (now - last) / 1000);
  last = now;
  fpsAcc += rawDt; fpsN++;
  if (fpsAcc >= 0.5) {
    app.fps = fpsN / fpsAcc; fpsAcc = 0; fpsN = 0;
    if (app.showFps) fpsEl.textContent = `${Math.round(app.fps)} FPS · ${app.game ? app.game.enemies.length : 0} 적`;
  }
  const dt = Math.min(rawDt, 1 / 30);
  const input = app.input;
  input.poll();

  if (input.pressed.has('F3')) { app.showFps = !app.showFps; fpsEl.textContent = ''; }
  if (input.any()) app.sound.init();

  const g = app.game;
  if (app.state === 'playing' && g) {
    if (input.act('pause')) {
      app.state = 'paused';
      app.ui.show('pause');
    } else {
      const steps = Math.max(1, Math.round(app.timeScale));
      for (let i = 0; i < steps; i++) {
        g.update(dt, input);
        if (g.pendingLevels > 0 || g.pendingChest > 0 || g.over) break;
      }
      if (g.over) {
        g.overT = (g.overT || 0) + dt;
        if (g.overT > 1.2) app.endRun();
      } else if (g.pendingChest > 0 || g.pendingLevels > 0) app.openLevelup();
    }
  } else {
    app.ui.tick(input);
  }

  if (g && app.state !== 'title') {
    g.render(ctx, app.view, app.sprites);
    app.ui.updateHud(g);
  } else {
    renderTitle(rawDt);
  }

  input.endFrame();
  requestAnimationFrame(frame);
}

// ---------------------------------------------------------------- test hooks
if (params.has('test')) {
  window.__lb = {
    app,
    get game() { return app.game; },
    start: () => app.startRun(),
    setTimeScale: (n) => { app.timeScale = n; },
    god: (b = true) => { app.godMode = b; if (app.game) app.game.god = b; },
    autoPick: (b = true) => { app.autoPick = b; },
    skipTo: (t) => { const g = app.game; g.time = t; },
    bot: (on = true) => {
      // test bot: flee close enemies, otherwise collect gems, fight the boss at range
      app.input.botMove = on ? () => {
        const g = app.game; if (!g) return { x: 0, y: 0 };
        const p = g.player;
        let ax = 0, ay = 0, danger = 0;
        for (const e of g.enemies) {
          const dx = p.x - e.x, dy = p.y - e.y, d2 = dx * dx + dy * dy + 1;
          if (d2 < 110 * 110) { ax += dx / d2; ay += dy / d2; danger++; }
        }
        if (!danger) {
          let best = null, bd = 1e12;
          for (const it of g.gems.concat(g.pickups)) {
            const d2 = (it.x - p.x) ** 2 + (it.y - p.y) ** 2;
            if (d2 < bd) { bd = d2; best = it; }
          }
          if (g.boss && !g.boss.dead) {
            const b = g.boss, dx = b.x - p.x, dy = b.y - p.y, d = Math.hypot(dx, dy);
            if (d > 160) { ax = dx; ay = dy; } else { ax = -dy; ay = dx; }
          } else if (best && bd < 500 * 500) { ax = best.x - p.x; ay = best.y - p.y; }
          else { ax = Math.cos(g.time * 0.6); ay = Math.sin(g.time * 0.6); }
        }
        const l = Math.hypot(ax, ay) || 1;
        return { x: ax / l, y: ay / l };
      } : null;
    },
  };
}

app.applyOptions();
app.ui.show('title');
app.sound.music('menu');
requestAnimationFrame(frame);
