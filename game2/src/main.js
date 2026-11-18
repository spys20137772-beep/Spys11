import { Input } from './input.js';
import { Sound } from './audio.js';
import { Save } from './save.js';
import { UI } from './ui.js';
import { Play } from './play.js';
import { LEVELS, WORLDS } from './levels.js';
import { DT } from './physics.js';

const canvas = document.getElementById('c');
const ctx = canvas.getContext('2d');
const params = new URLSearchParams(location.search);

const app = {
  state: 'title', // title | playing | paused | clear
  play: null,
  input: new Input(),
  sound: new Sound(),
  save: new Save(),
  view: { cw: 1, ch: 1, scale: 1, dpr: 1 },
  fps: 60,
};
app.ui = new UI(app);

// ---------------------------------------------------------------- progress
app.unlocked = (i) => i === 0 || !!app.save.level(LEVELS[i - 1].id).done || !!app.save.level(LEVELS[i].id).done;
app.nextLevel = () => {
  for (let i = 0; i < LEVELS.length; i++) if (!app.save.level(LEVELS[i].id).done) return i;
  return LEVELS.length - 1;
};

// ---------------------------------------------------------------- flow
app.startLevel = (i) => {
  app.sound.init();
  app.play = new Play(app, i);
  app.deathsAtStart = app.save.data.deaths;
  app.state = 'playing';
  app.ui.stack = [];
  app.ui.hide();
  app.ui.showHud(true);
  app.ui.hudKey = '';
  app.ui.tip(LEVELS[i].tip);
  app.sound.music(WORLDS[LEVELS[i].world - 1].theme);
  app.input.drag = null; app.input.released = null;
};
app.restart = () => { if (app.play) app.startLevel(app.play.index); };
app.pause = () => { if (app.state === 'playing') { app.state = 'paused'; app.input.drag = null; app.ui.show('pause'); } };
app.resume = () => { app.state = 'playing'; app.ui.stack = []; app.ui.hide(); app.input.released = null; };
app.next = () => {
  const i = app.play.index + 1;
  if (i >= LEVELS.length) { app.showEnding(); return; }
  app.startLevel(i);
};
app.toSelect = () => {
  app.play = null; app.state = 'title';
  app.ui.showHud(false); app.ui.stack = [['title', undefined, 1]];
  app.ui.show('select');
  app.sound.music('menu');
};
app.toTitle = () => {
  app.play = null; app.state = 'title';
  app.ui.showHud(false); app.ui.stack = []; app.ui.show('title');
  app.sound.music('menu');
};
app.showEnding = () => {
  app.play = null; app.state = 'title';
  app.ui.showHud(false); app.ui.stack = []; app.ui.show('ending');
  app.sound.play('ending'); app.sound.music('night');
};
app.levelClear = (play) => {
  const w = play.world;
  const res = app.save.record(play.def.id, w.got, w.launches, w.time);
  app.state = 'clear';
  app.ui.showHud(false);
  app.ui.show('clear', {
    id: play.def.id, name: play.def.name, got: w.got, launches: w.launches, time: w.time,
    deaths: app.save.data.deaths - app.deathsAtStart, last: play.index === LEVELS.length - 1, ...res,
  });
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
document.addEventListener('fullscreenchange', () => { app.save.data.options.fullscreen = !!document.fullscreenElement; });

// ---------------------------------------------------------------- view
function resize() {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.floor(innerWidth * dpr);
  canvas.height = Math.floor(innerHeight * dpr);
  // about 15 tiles tall on desktop; at least ~11 tiles across on a phone
  const zoom = Math.max(0.45, Math.min(2.2, innerHeight / 600, innerWidth / 560));
  app.view = { cw: canvas.width, ch: canvas.height, scale: dpr * zoom, dpr };
}
addEventListener('resize', resize);
resize();
app.input.attach(canvas);
app.input.enabled = () => app.state === 'playing';

// title background: floating mochi bubbles
const bubbles = Array.from({ length: 24 }, () => ({ x: Math.random(), y: Math.random(), r: 6 + Math.random() * 18, v: 8 + Math.random() * 18, p: Math.random() * 6 }));
function renderTitle(dt) {
  const { cw, ch, dpr } = app.view;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  const g = ctx.createLinearGradient(0, 0, 0, ch);
  g.addColorStop(0, '#fff4e6'); g.addColorStop(1, '#ffd8c2');
  ctx.fillStyle = g; ctx.fillRect(0, 0, cw, ch);
  for (const b of bubbles) {
    b.y -= b.v * dt / ch * dpr * 10; b.p += dt;
    if (b.y < -0.1) { b.y = 1.1; b.x = Math.random(); }
    ctx.fillStyle = 'rgba(255,255,255,0.55)';
    ctx.beginPath(); ctx.arc(b.x * cw + Math.sin(b.p) * 10 * dpr, b.y * ch, b.r * dpr, 0, Math.PI * 2); ctx.fill();
  }
}

// ---------------------------------------------------------------- loop
let last = performance.now(), fAcc = 0, fN = 0;
const fpsEl = document.getElementById('fps');
app.showFps = params.has('fps');
function frame(now) {
  const raw = Math.min(0.1, (now - last) / 1000); last = now;
  fAcc += raw; fN++;
  if (fAcc >= 0.5) { app.fps = fN / fAcc; fAcc = 0; fN = 0; if (app.showFps) fpsEl.textContent = `${Math.round(app.fps)} FPS`; }
  const dt = Math.min(raw, 1 / 20);
  const input = app.input;
  input.poll();
  if (input.pressed.size || input.padPressed.size) app.sound.init();
  if (input.pressed.has('F3')) { app.showFps = !app.showFps; fpsEl.textContent = ''; }

  if (app.state === 'playing' && app.play) {
    if (input.act('pause') || document.hidden) app.pause();
    else if (input.act('restart')) app.restart();
    else app.play.update(dt, input);
  } else {
    app.ui.tick(input);
  }
  if (app.play && app.state !== 'title') {
    app.play.render(ctx, app.view);
    if (app.state === 'playing') app.ui.updateHud(app.play);
  } else renderTitle(raw);
  if (app.state === 'playing') app.save.data.playTime += raw;

  input.endFrame();
  requestAnimationFrame(frame);
}

// ---------------------------------------------------------------- test hooks
if (params.has('test')) {
  window.__cj = {
    app, LEVELS, DT,
    get play() { return app.play; },
    // launch with an angle index (of 64) and power k, the solver's format
    launchAt(a, k, angles = 64) {
      const w = app.play.world, ang = (a / angles) * Math.PI * 2;
      const sp = 160 + (980 - 160) * k;
      return w.launch(Math.cos(ang) * sp, Math.sin(ang) * sp);
    },
  };
}

app.applyOptions();
app.ui.show('title');
app.sound.music('menu');
requestAnimationFrame(frame);
