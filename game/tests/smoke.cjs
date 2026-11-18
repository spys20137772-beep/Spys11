const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  const errs = [];
  p.on('pageerror', e => errs.push('pageerror: ' + e.message));
  p.on('console', m => { if (m.type() === 'error') errs.push('console: ' + m.text()); });
  await p.goto('http://localhost:8080/?test&fps');
  await p.waitForTimeout(800);
  await p.screenshot({ path: 'tests/out/01-title.png' });
  await p.keyboard.press('Enter');
  await p.waitForTimeout(300);
  await p.evaluate(() => { __lb.bot(); });
  await p.waitForTimeout(6000);
  await p.screenshot({ path: 'tests/out/02-play.png' });
  console.log(await p.evaluate(() => ({ state: __lb.app.state, t: __lb.game.time, lv: __lb.game.level, en: __lb.game.enemies.length, hp: __lb.game.player.hp })));
  console.log('errors', errs);
  await b.close();
})();
