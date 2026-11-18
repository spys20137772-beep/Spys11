const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1100, height: 700 } });
  await p.goto('http://localhost:8080/tests/out/frame.html');
  await p.waitForTimeout(800);
  const f = p.frames().find(x => x.url().includes('127.0.0.1'));
  // user clicks "시작하기" with the mouse, then holds D
  await p.mouse.click(500, 30 + 341 * 600 / 720);
  await p.waitForTimeout(300);
  console.log('state', await f.evaluate(() => __lb.app.state));
  const x0 = await f.evaluate(() => __lb.game && __lb.game.player.x);
  await p.keyboard.down('KeyD'); await p.waitForTimeout(700); await p.keyboard.up('KeyD');
  console.log('moved', await f.evaluate(() => __lb.game && __lb.game.player.x) - x0);
  await b.close();
})();
