// Full acceptance run for Chaltteok Jump.
// Needs: game served on http://localhost:8081, tests/out/paths.json from `node tests/solve.mjs`.
const { chromium, devices } = require('playwright');
const fs = require('fs');
const OUT = 'tests/out/';
const PATHS = JSON.parse(fs.readFileSync(OUT + 'paths.json', 'utf8'));
const report = {};
const log = (k, v) => { report[k] = v; console.log(k, JSON.stringify(v)); };

(async () => {
  const b = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  const errs = [];
  p.on('pageerror', (e) => errs.push('pageerror: ' + e.message));
  p.on('console', (m) => { if (m.type() === 'error') errs.push('console: ' + m.text()); });
  const ev = (f, a) => p.evaluate(f, a);
  const press = async (k) => { await p.keyboard.press(k); await p.waitForTimeout(70); };
  const shot = (n) => p.screenshot({ path: OUT + n + '.png' });
  const state = () => ev(() => __cj.app.state);
  const until = async (fn, ms = 8000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (await ev(fn)) return true; await p.waitForTimeout(50); } return false; };

  await p.goto('http://localhost:8081/?test&fps');
  await ev(() => localStorage.clear()); await p.reload(); await p.waitForTimeout(600);
  await shot('10-title');

  // menus by keyboard
  await press('ArrowDown'); await press('Enter');
  log('select_screen', await ev(() => __cj.app.ui.screen));
  log('locked_level2', await ev(() => !__cj.app.unlocked(1)));
  await shot('11-select');
  await press('Escape');
  log('back_title_focus', await ev(() => [__cj.app.ui.screen, __cj.app.ui.focus]));
  await press('ArrowUp'); await press('Enter');
  log('started', await ev(() => [__cj.app.state, __cj.play.def.id]));
  await until(() => __cj.play.world.canLaunch());

  // mouse pull-and-release
  const l0 = await ev(() => __cj.play.world.launches);
  await p.mouse.move(640, 360); await p.mouse.down(); await p.mouse.move(600, 420, { steps: 5 });
  await p.waitForTimeout(120);
  log('mouse_preview_points', await ev(() => (__cj.play.pred ? __cj.play.pred.pts.length / 2 : 0)));
  await p.mouse.up(); await p.waitForTimeout(80);
  log('mouse_launch', (await ev(() => __cj.play.world.launches)) - l0);
  await until(() => __cj.play.world.canLaunch());

  // keyboard aim + Space
  await p.keyboard.down('ArrowRight'); await p.waitForTimeout(250); await p.keyboard.up('ArrowRight');
  const l1 = await ev(() => __cj.play.world.launches);
  await press('Space');
  log('keyboard_launch', (await ev(() => __cj.play.world.launches)) - l1);
  await until(() => __cj.play.world.canLaunch());

  // gamepad aim + A
  await ev(() => {
    const pad = { connected: true, axes: [0.7, -0.7, 0, 0], buttons: Array.from({ length: 17 }, () => ({ pressed: false })) };
    window.__pad = pad; navigator.getGamepads = () => [pad];
  });
  await p.waitForTimeout(100);
  const l2 = await ev(() => __cj.play.world.launches);
  await ev(() => { __pad.buttons[0].pressed = true; }); await p.waitForTimeout(60);
  await ev(() => { __pad.buttons[0].pressed = false; __pad.axes[0] = 0; __pad.axes[1] = 0; }); await p.waitForTimeout(60);
  log('gamepad_launch', (await ev(() => __cj.play.world.launches)) - l2);
  await ev(() => { __pad.buttons[9].pressed = true; }); await p.waitForTimeout(60);
  log('gamepad_start_pause', await state());
  await ev(() => { __pad.buttons[9].pressed = false; navigator.getGamepads = () => []; });
  await shot('12-pause');
  await press('ArrowDown'); await press('ArrowDown'); await press('ArrowDown'); await press('Enter');
  log('pause_options', await ev(() => __cj.app.ui.screen));
  await press('Escape');
  log('back_to_pause', await ev(() => __cj.app.ui.screen));
  await press('Escape');
  log('resumed', await state());

  // restart with R
  await press('KeyR');
  log('restart_resets_launches', await ev(() => __cj.play.world.launches));

  // death and respawn on 1-3 spikes
  await ev(() => __cj.app.startLevel(2));
  await until(() => __cj.play.world.canLaunch());
  const d0 = await ev(() => __cj.app.save.data.deaths);
  await ev(() => __cj.launchAt(56, 0.4));
  await until(() => __cj.play.world.p.dead, 3000);
  await p.waitForTimeout(150); await shot('13-death');
  log('died_on_spikes', (await ev(() => __cj.app.save.data.deaths)) - d0);
  log('respawned_and_stuck', await until(() => __cj.play.world.canLaunch(), 3000));

  // play all 24 levels with the solver's routes, through the real UI flow
  await ev(() => __cj.app.startLevel(0));
  const results = [];
  for (let i = 0; i < PATHS && 0; i++);
  const ids = await ev(() => __cj.LEVELS.map((l) => l.id));
  for (let i = 0; i < ids.length; i++) {
    const id = ids[i];
    const cur = await ev(() => __cj.play && __cj.play.def.id);
    if (cur !== id) { results.push([id, 'wrong level ' + cur]); break; }
    const r = await p.evaluate(async (path) => {
      const sleep = (ms) => new Promise((res) => setTimeout(res, ms));
      const deaths0 = __cj.app.save.data.deaths;
      for (const [a, k] of path) {
        let t = 0;
        while (!__cj.play.world.canLaunch()) {
          await sleep(16); t += 16;
          if (__cj.app.state !== 'playing') return 'state ' + __cj.app.state;
          if (t > 9000) return 'stuck-timeout';
        }
        __cj.launchAt(a, k);
      }
      let t = 0;
      while (__cj.app.state === 'playing') { await sleep(16); t += 16; if (t > 9000) return 'no-clear'; }
      return __cj.app.save.data.deaths > deaths0 ? 'died' : __cj.app.state;
    }, PATHS[id]);
    results.push([id, r]);
    if (r !== 'clear') break;
    if (i === 0 || i === 12 || i === 23) await shot(`2${i < 10 ? '0' : ''}${i}-clear`);
    await p.waitForTimeout(150);
    await press('Enter');
    await p.waitForTimeout(150);
  }
  log('replay_all', results);
  log('ending_screen', await ev(() => __cj.app.ui.screen));
  await p.waitForTimeout(500);
  await shot('30-ending');
  log('saved_done', await ev(() => Object.values(__cj.app.save.data.levels).filter((l) => l.done).length));

  // fps on the biggest level
  await ev(() => __cj.app.startLevel(23));
  await p.waitForTimeout(800);
  await p.mouse.move(640, 360); await p.mouse.down(); await p.mouse.move(580, 420, { steps: 3 });
  const f = [];
  for (let i = 0; i < 6; i++) { await p.waitForTimeout(500); f.push(Math.round(await ev(() => __cj.app.fps))); }
  await p.mouse.up();
  log('fps_desktop_aiming', f);
  log('audio', await ev(() => ({ ctx: __cj.app.sound.ctx && __cj.app.sound.ctx.state, played: __cj.app.sound.played, track: __cj.app.sound.track })));

  // persistence
  await ev(() => { __cj.app.save.data.options.music = 0.3; __cj.app.save.write(); });
  const before = await ev(() => JSON.stringify(__cj.app.save.data.levels) + __cj.app.save.data.options.music);
  await p.reload(); await p.waitForTimeout(500);
  log('persist_equal', before === await ev(() => JSON.stringify(__cj.app.save.data.levels) + __cj.app.save.data.options.music));
  await shot('31-title-after');
  log('errors_desktop', errs);

  // phone
  const ctx = await b.newContext({ ...devices['iPhone 13'] });
  const m = await ctx.newPage();
  const merrs = []; m.on('pageerror', (e) => merrs.push(e.message));
  await m.goto('http://localhost:8081/?test&fps'); await m.waitForTimeout(600);
  await m.screenshot({ path: OUT + '40-phone-title.png' });
  await m.tap('text=스테이지 선택'); await m.waitForTimeout(300);
  await m.screenshot({ path: OUT + '41-phone-select.png' });
  await m.tap('.cell >> nth=0'); await m.waitForTimeout(900);
  const cdp = await ctx.newCDPSession(m);
  const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y }] });
  const ml0 = await m.evaluate(() => __cj.play.world.launches);
  await touch('touchStart', 200, 500);
  for (let i = 1; i <= 6; i++) { await touch('touchMove', 200 - i * 8, 500 + i * 10); await m.waitForTimeout(30); }
  await m.waitForTimeout(200);
  await m.screenshot({ path: OUT + '42-phone-aim.png' });
  await touch('touchEnd'); await m.waitForTimeout(100);
  log('phone_touch_launch', (await m.evaluate(() => __cj.play.world.launches)) - ml0);
  const mf = [];
  for (let i = 0; i < 4; i++) { await m.waitForTimeout(500); mf.push(Math.round(await m.evaluate(() => __cj.app.fps))); }
  log('fps_phone', mf);
  await m.tap('#btn-pause'); await m.waitForTimeout(200);
  log('phone_pause', await m.evaluate(() => __cj.app.state));
  log('phone_hscroll', await m.evaluate(() => document.documentElement.scrollWidth > innerWidth));
  log('errors_phone', merrs);

  fs.writeFileSync(OUT + 'report.json', JSON.stringify(report, null, 2));
  await b.close();
})().catch((e) => { console.error('TEST CRASH', e); process.exit(1); });
