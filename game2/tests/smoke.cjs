const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 720 } });
  const errs = []; p.on('pageerror', (e) => errs.push(e.message)); p.on('console', (m) => m.type() === 'error' && errs.push(m.text()));
  await p.goto('http://localhost:8081/?test&fps'); await p.waitForTimeout(700);
  await p.screenshot({ path: 'tests/out/01-title.png' });
  for (const [i, n] of [[0, '02-l1'], [11, '03-l12'], [23, '04-l24']]) {
    await p.evaluate((i) => __cj.app.startLevel(i), i); await p.waitForTimeout(900);
    await p.mouse.move(640, 360); await p.mouse.down(); await p.mouse.move(560, 440, { steps: 4 }); await p.waitForTimeout(150);
    await p.screenshot({ path: `tests/out/${n}.png` });
    await p.mouse.up(); await p.waitForTimeout(500);
  }
  console.log('state', await p.evaluate(() => __cj.app.state), 'launches', await p.evaluate(() => __cj.play.world.launches), 'errors', errs);
  await b.close();
})();
