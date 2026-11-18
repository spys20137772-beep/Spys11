const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on('pageerror', e => errs.push(e.message)); p.on('console', m => m.type()==='error' && errs.push(m.text()));
  await p.goto('file://' + process.cwd() + '/dist/Lanternbound-win32-x64/resources/app/index.html');
  await p.waitForTimeout(500); await p.keyboard.press('Enter'); await p.waitForTimeout(1500);
  console.log('state', await p.evaluate(() => document.querySelector('#hud').className), 'errors', errs);
  await b.close();
})();
