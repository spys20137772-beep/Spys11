const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on('pageerror', (e) => errs.push(e.message));
  await p.goto('file://' + process.cwd() + '/dist/ChaltteokJump-win32-x64/resources/app/index.html');
  await p.waitForTimeout(400); await p.keyboard.press('Enter'); await p.waitForTimeout(800);
  console.log('hud visible', await p.evaluate(() => !document.querySelector('#hud').classList.contains('hidden')), 'errors', errs);
  await b.close();
})();
