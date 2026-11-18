// Full acceptance run. Usage: NODE_PATH=$(npm root -g) node tests/full.cjs
// Needs the game served at http://localhost:8080 (npm run serve).
const { chromium } = require('playwright');
const OUT = 'tests/out/';
const report = {};
const log = (k, v) => { report[k] = v; console.log(k, JSON.stringify(v)); };

(async () => {
  const b = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  const errs = [];
  p.on('pageerror', (e) => errs.push('pageerror: ' + e.message));
  p.on('console', (m) => { if (m.type() === 'error') errs.push('console: ' + m.text()); });
  const press = async (k) => { await p.keyboard.press(k); await p.waitForTimeout(60); };
  const shot = (n) => p.screenshot({ path: OUT + n + '.png' });
  const ev = (f, a) => p.evaluate(f, a);
  const waitFor = async (fn, ms, step = 200) => {
    const t0 = Date.now();
    while (Date.now() - t0 < ms) { if (await ev(fn)) return true; await p.waitForTimeout(step); }
    return false;
  };

  await p.goto('http://localhost:8080/?test&fps');
  await p.evaluate(() => localStorage.clear());
  await p.reload();
  await p.waitForTimeout(600);
  await shot('01-title');

  // --- options screen from title (keyboard nav)
  await press('ArrowDown'); await press('ArrowDown'); await press('Enter');
  await p.waitForTimeout(200);
  await press('ArrowRight'); // master volume +10%? (already .8 -> .9)
  await shot('02-options');
  log('options_master_after_right', await ev(() => __lb.app.save.data.options.master));
  await press('Escape');
  await p.waitForTimeout(150);
  log('back_to', await ev(() => __lb.app.ui.screen));

  // --- start run
  await press('ArrowUp'); await press('ArrowUp');
  await press('Enter');
  await p.waitForTimeout(200);
  log('state_after_start', await ev(() => __lb.app.state));
  await ev(() => { __lb.bot(); __lb.setTimeScale(4); });

  // --- first level up screen, choose with keyboard
  log('levelup_reached', await waitFor(() => __lb.app.state === 'levelup', 60000));
  await p.waitForTimeout(400);
  await shot('03-levelup');
  const before = await ev(() => __lb.game.weapons.length + Object.keys(__lb.game.passives).length);
  await press('ArrowRight'); await press('Enter');
  await p.waitForTimeout(100);
  const after = await ev(() => __lb.game.weapons.map((w) => w.id + w.lvl).join() + '|' + JSON.stringify(__lb.game.passives));
  log('picked_upgrade', { before, after });

  // --- pause + options from pause + resume
  await press('Escape');
  await p.waitForTimeout(200);
  log('paused', await ev(() => __lb.app.state));
  await shot('04-pause');
  await press('ArrowDown'); await press('Enter');
  await p.waitForTimeout(150);
  log('pause_options_screen', await ev(() => __lb.app.ui.screen));
  await press('Escape'); await p.waitForTimeout(100);
  log('back_to_pause', await ev(() => __lb.app.ui.screen));
  const tPause = await ev(() => __lb.game.time);
  await p.waitForTimeout(500);
  log('time_frozen_while_paused', (await ev(() => __lb.game.time)) === tPause);
  await press('Escape'); await p.waitForTimeout(100);
  log('resumed', await ev(() => __lb.app.state));

  // --- gamepad: fake a pad and press A on next levelup
  await ev(() => {
    const pad = { connected: true, axes: [0, 0, 0, 0], buttons: Array.from({ length: 17 }, () => ({ pressed: false, value: 0 })) };
    window.__pad = pad;
    navigator.getGamepads = () => [pad];
  });
  await ev(() => { __lb.game.pendingLevels++; });
  log('levelup2', await waitFor(() => __lb.app.state === 'levelup', 5000));
  await p.waitForTimeout(150);
  const lvBefore = await ev(() => __lb.game.weapons.map((w) => w.lvl).join() + JSON.stringify(__lb.game.passives));
  await ev(() => { __pad.buttons[15].pressed = true; }); await p.waitForTimeout(80);
  await ev(() => { __pad.buttons[15].pressed = false; }); await p.waitForTimeout(80);
  await ev(() => { __pad.buttons[0].pressed = true; }); await p.waitForTimeout(80);
  await ev(() => { __pad.buttons[0].pressed = false; }); await p.waitForTimeout(80);
  log('gamepad_pick', { state: await ev(() => __lb.app.state), changed: lvBefore !== await ev(() => __lb.game.weapons.map((w) => w.lvl).join() + JSON.stringify(__lb.game.passives)) });
  // gamepad stick moves player
  const px0 = await ev(() => { __lb.bot(false); __lb.setTimeScale(1); __pad.axes[0] = 1; return __lb.game.player.x; });
  await p.waitForTimeout(500);
  log('gamepad_move_dx', Math.round(await ev(() => __lb.game.player.x) - px0));
  await ev(() => { __pad.axes[0] = 0; __pad.buttons[9].pressed = true; });
  await p.waitForTimeout(80);
  log('gamepad_start_pauses', await ev(() => __lb.app.state));
  await ev(() => { __pad.buttons[9].pressed = false; }); await p.waitForTimeout(80);
  await ev(() => { __pad.buttons[9].pressed = true; }); await p.waitForTimeout(80);
  await ev(() => { __pad.buttons[9].pressed = false; navigator.getGamepads = () => []; });
  await p.waitForTimeout(80);
  if (await ev(() => __lb.app.state) === 'paused') await press('Escape');

  // --- sound check
  log('audio', await ev(() => ({ ctx: __lb.app.sound.ctx && __lb.app.sound.ctx.state, played: __lb.app.sound.played, track: __lb.app.sound.track })));

  // --- long run: god mode, auto pick, fast forward to ~8 min
  await ev(() => { __lb.god(); __lb.autoPick(); __lb.bot(); __lb.setTimeScale(12); });
  let peak = 0;
  const t0 = Date.now();
  while (Date.now() - t0 < 240000) {
    const s = await ev(() => ({ t: __lb.game.time, n: __lb.game.enemies.length }));
    peak = Math.max(peak, s.n);
    if (s.t > 470) break;
    await p.waitForTimeout(1000);
  }
  // fps at normal speed with a big crowd
  await ev(() => __lb.setTimeScale(1));
  await p.waitForTimeout(1500);
  const fpsSamples = [];
  for (let i = 0; i < 6; i++) { await p.waitForTimeout(500); fpsSamples.push(await ev(() => ({ fps: Math.round(__lb.app.fps), n: __lb.game.enemies.length }))); }
  await shot('05-crowd');
  log('crowd_fps', { peakEnemies: peak, samples: fpsSamples });
  log('loadout_8min', await ev(() => ({ t: Math.round(__lb.game.time), lv: __lb.game.level, w: __lb.game.weapons.map((w) => w.id + w.lvl), p: __lb.game.passives, kills: __lb.game.kills })));
  log('enemy_types_seen', await ev(() => [...new Set(__lb.game.enemies.map((e) => e.type))]));

  // --- boss at 10:00
  await ev(() => __lb.setTimeScale(12));
  log('boss_spawned', await waitFor(() => !!__lb.game.boss, 120000));
  log('boss_time', await ev(() => Math.round(__lb.game.time)));
  await ev(() => __lb.setTimeScale(1));
  await p.waitForTimeout(1500);
  await shot('06-boss');
  await ev(() => __lb.setTimeScale(8));
  const won = await waitFor(() => __lb.app.state === 'result', 180000, 500);
  log('boss_killed_result', { won, result: await ev(() => __lb.app.game && __lb.app.game.result) });
  await p.waitForTimeout(400);
  await shot('07-victory');

  // --- defeat path: restart, no god, stand still
  await ev(() => { __lb.god(false); __lb.bot(false); __lb.autoPick(); });
  await press('Enter'); // focused "다시 하기"
  await p.waitForTimeout(200);
  log('restarted', await ev(() => ({ state: __lb.app.state, t: __lb.game.time })));
  await ev(() => { __lb.setTimeScale(12); __lb.skipTo(300); });
  log('died', await waitFor(() => __lb.app.state === 'result', 120000, 300));
  await p.waitForTimeout(300);
  await shot('08-defeat');
  log('defeat_result', await ev(() => __lb.app.game.result));

  // --- shop purchase
  await ev(() => __lb.app.ui.show('shop'));
  const goldBefore = await ev(() => __lb.app.save.data.gold);
  await press('Enter');
  await p.waitForTimeout(100);
  await shot('09-shop');
  log('shop_buy', { goldBefore, goldAfter: await ev(() => __lb.app.save.data.gold), meta: await ev(() => __lb.app.save.data.meta) });

  // --- persistence after reload
  const saved = await ev(() => JSON.stringify({ g: __lb.app.save.data.gold, m: __lb.app.save.data.meta, b: __lb.app.save.data.best, runs: __lb.app.save.data.runs, wins: __lb.app.save.data.wins, master: __lb.app.save.data.options.master }));
  await p.reload(); await p.waitForTimeout(500);
  const loaded = await ev(() => JSON.stringify({ g: __lb.app.save.data.gold, m: __lb.app.save.data.meta, b: __lb.app.save.data.best, runs: __lb.app.save.data.runs, wins: __lb.app.save.data.wins, master: __lb.app.save.data.options.master }));
  log('persist_equal', saved === loaded);
  log('persist_data', JSON.parse(loaded));
  await shot('10-title-after');

  log('errors', errs);
  require('fs').writeFileSync(OUT + 'report.json', JSON.stringify(report, null, 2));
  await b.close();
})().catch((e) => { console.error('TEST CRASH', e); process.exit(1); });
