const { chromium, devices } = require('playwright');
(async () => {
  const b = await chromium.launch();
  // 1) desktop: game inside an iframe, mouse click start, then keyboard
  {
    const p = await b.newPage({ viewport: { width: 1100, height: 700 } });
    await p.goto('http://localhost:8080/tests/out/frame.html'); await p.waitForTimeout(800);
    const f = p.frames().find((x) => x.url().includes('127.0.0.1'));
    await p.mouse.click(500, 30 + 341 * 600 / 720); await p.waitForTimeout(300);
    const x0 = await f.evaluate(() => __lb.game.player.x);
    await p.keyboard.down('KeyD'); await p.waitForTimeout(700); await p.keyboard.up('KeyD');
    console.log('iframe keyboard moved', Math.round(await f.evaluate(() => __lb.game.player.x) - x0));
    // mouse drag joystick
    const y0 = await f.evaluate(() => __lb.game.player.y);
    await p.mouse.move(500, 400); await p.mouse.down(); await p.mouse.move(500, 470, { steps: 5 });
    await p.waitForTimeout(600); await p.mouse.up();
    console.log('iframe mouse-drag moved y', Math.round(await f.evaluate(() => __lb.game.player.y) - y0));
    await p.close();
  }
  // 2) phone portrait with real touch events
  const ctx = await b.newContext({ ...devices['iPhone 13'] });
  const p = await ctx.newPage();
  const errs = []; p.on('pageerror', (e) => errs.push(e.message));
  await p.goto('http://localhost:8080/?test'); await p.waitForTimeout(800);
  await p.screenshot({ path: 'tests/out/m1-title.png' });
  await p.tap('text=시작하기'); await p.waitForTimeout(400);
  console.log('phone state', await p.evaluate(() => __lb.app.state));
  const cdp = await ctx.newCDPSession(p);
  const touch = (type, x, y) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y }] });
  const s0 = await p.evaluate(() => ({ x: __lb.game.player.x, y: __lb.game.player.y }));
  await touch('touchStart', 190, 600);
  for (let i = 1; i <= 6; i++) { await touch('touchMove', 190 + i * 12, 600 - i * 8); await p.waitForTimeout(30); }
  await p.waitForTimeout(500);
  await p.screenshot({ path: 'tests/out/m2-drag.png' });
  await touch('touchEnd');
  const s1 = await p.evaluate(() => ({ x: __lb.game.player.x, y: __lb.game.player.y }));
  console.log('phone touch moved', Math.round(s1.x - s0.x), Math.round(s1.y - s0.y));
  // force a level-up to check card layout, tap a card
  await p.evaluate(() => { __lb.game.pendingLevels = 1; }); await p.waitForTimeout(500);
  await p.screenshot({ path: 'tests/out/m3-levelup.png' });
  await p.tap('.card >> nth=1'); await p.waitForTimeout(200);
  console.log('after card tap', await p.evaluate(() => __lb.app.state));
  await p.tap('#pausebtn'); await p.waitForTimeout(200);
  console.log('pause button', await p.evaluate(() => __lb.app.state));
  await p.screenshot({ path: 'tests/out/m4-pause.png' });
  console.log('h-scroll', await p.evaluate(() => document.documentElement.scrollWidth > innerWidth), 'errors', errs);
  await b.close();
})();
