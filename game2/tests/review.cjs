// Checks for the review round: fixes and additions.
const { chromium, devices } = require('playwright');
const OUT = 'tests/out/';
const log = (k, v) => console.log(k, JSON.stringify(v));
(async () => {
  const b = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  const errs = []; p.on('pageerror', (e) => errs.push(e.message)); p.on('console', (m) => m.type() === 'error' && errs.push(m.text()));
  const ev = (f, a) => p.evaluate(f, a);
  const until = async (fn, ms = 6000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (await ev(fn)) return true; await p.waitForTimeout(40); } return false; };
  await p.goto('http://localhost:8081/?test'); await ev(() => localStorage.clear()); await p.reload(); await p.waitForTimeout(500);

  // F1 preview gets shorter per world (same aim)
  const lens = [];
  for (const i of [0, 8, 16]) {
    await ev((i) => __cj.app.startLevel(i), i); await until(() => __cj.play.world.canLaunch());
    await p.mouse.move(640, 360); await p.mouse.down(); await p.mouse.move(600, 420, { steps: 3 }); await p.waitForTimeout(80);
    lens.push(await ev(() => __cj.play.pred.pts.length / 2));
    await p.keyboard.press('Escape'); await p.mouse.up(); await p.waitForTimeout(50);
  }
  log('F1_preview_points_w1_w2_w3', lens);

  // F3 cancel: Esc while dragging cancels without pausing or launching
  await ev(() => __cj.app.startLevel(0)); await until(() => __cj.play.world.canLaunch());
  await p.mouse.move(640, 360); await p.mouse.down(); await p.mouse.move(590, 420, { steps: 3 });
  await p.keyboard.press('Escape'); await p.mouse.up(); await p.waitForTimeout(80);
  log('F3_esc_cancel', await ev(() => ({ state: __cj.app.state, launches: __cj.play.world.launches })));
  await p.mouse.move(640, 360); await p.mouse.down(); await p.mouse.move(590, 420, { steps: 3 });
  await p.mouse.down({ button: 'right' }); await p.mouse.up({ button: 'right' }); await p.mouse.up(); await p.waitForTimeout(80);
  log('F3_rightclick_cancel', await ev(() => __cj.play.world.launches));
  await p.mouse.move(640, 360); await p.mouse.down(); await p.waitForTimeout(60);
  await p.screenshot({ path: OUT + '50-cancel-hint.png' });
  await p.mouse.up();

  // F5 buffer: release while falling just before landing, launch fires on landing
  await ev(() => __cj.launchAt(48, 0.2));
  await until(() => __cj.play.world.p.vy > 150, 3000);
  const midAir = await ev(() => { const air = !__cj.play.world.canLaunch(); __cj.app.input.released = { dx: -50, dy: 60 }; return air; });
  await p.waitForTimeout(600);
  log('F5_buffered_launch', { releasedMidAir: midAir, launches: await ev(() => __cj.play.world.launches) });

  // A3 intro + F2 goal arrow on a wide level
  await ev(() => __cj.app.startLevel(10)); await p.waitForTimeout(350);
  log('A3_intro_active', await ev(() => !!__cj.play.intro));
  await p.screenshot({ path: OUT + '51-intro.png' });
  await p.waitForTimeout(2200);
  log('A3_intro_done', await ev(() => !__cj.play.intro));
  await p.screenshot({ path: OUT + '52-goal-arrow.png' });

  // A4 mute
  await p.click('#btn-mute'); await p.waitForTimeout(50);
  log('A4_mute', await ev(() => ({ muted: __cj.app.save.data.options.muted, gain: __cj.app.sound.master ? __cj.app.sound.master.gain.value : null, icon: document.querySelector('#btn-mute').textContent })));
  await p.keyboard.press('KeyM'); await p.waitForTimeout(50);
  log('A4_unmute_key', await ev(() => __cj.app.save.data.options.muted));

  // A1 medal: clear 1-1 with the solver route, then check
  const paths = require('./out/paths.json');
  await ev(() => __cj.app.startLevel(0));
  await p.evaluate(async (path) => {
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    for (const [a, k] of path) { while (!__cj.play.world.canLaunch()) await sleep(16); __cj.launchAt(a, k); }
    while (__cj.app.state === 'playing') await sleep(16);
  }, paths['1-1']);
  await p.waitForTimeout(600);
  log('A1_clear_medal', await ev(() => __cj.app.ui.lastArg.medal));
  await p.screenshot({ path: OUT + '53-clear-medal.png' });
  await ev(() => __cj.app.toSelect()); await p.waitForTimeout(200);
  log('A1_select_medal_icon', await ev(() => !!document.querySelector('.cell i.medal.gold')));
  await p.screenshot({ path: OUT + '54-select-medal.png' });

  // A2 skins: give 12 berries, pick 쑥떡
  await ev(() => { const L = __cj.LEVELS; for (let i = 1; i < 5; i++) __cj.app.save.data.levels[L[i].id] = { done: true, berries: [true, true, true], best: 3, time: 10 }; __cj.app.save.write(); __cj.app.toTitle(); });
  await p.waitForTimeout(150);
  await p.click('text=꾸미기'); await p.waitForTimeout(200);
  await p.click('[data-skin="mugwort"]'); await p.waitForTimeout(200);
  await p.screenshot({ path: OUT + '55-skins.png' });
  await p.click('[data-skin="sesame"]'); await p.waitForTimeout(100);
  log('A2_skin', await ev(() => ({ chosen: __cj.app.save.data.options.skin, lockedRejected: __cj.app.save.data.options.skin !== 'sesame' })));
  await ev(() => __cj.app.startLevel(0)); await p.waitForTimeout(900);
  log('A2_skin_in_game', await ev(() => __cj.play.skin.id));
  await p.screenshot({ path: OUT + '56-skin-ingame.png' });
  await p.reload(); await p.waitForTimeout(400);
  log('A2_skin_persist', await ev(() => __cj.app.save.data.options.skin));

  // phone HUD layout
  const ctx = await b.newContext({ ...devices['iPhone 13'] }); const m = await ctx.newPage();
  await m.goto('http://localhost:8081/?test'); await m.waitForTimeout(400);
  await m.evaluate(() => __cj.app.startLevel(10)); await m.waitForTimeout(2600);
  await m.screenshot({ path: OUT + '57-phone-hud.png' });
  log('errors', errs);
  await b.close();
})().catch((e) => { console.error('TEST CRASH', e); process.exit(1); });
