const { chromium, devices } = require('playwright');
(async () => {
  const b = await chromium.launch(); const ctx = await b.newContext({ ...devices['iPhone 13'] }); const m = await ctx.newPage();
  await m.goto('http://localhost:8081/?test'); await m.waitForTimeout(500);
  await m.evaluate(() => __cj.app.startLevel(11)); await m.waitForTimeout(1200);
  await m.screenshot({ path: 'tests/out/43-phone-level.png' }); await b.close();
})();
