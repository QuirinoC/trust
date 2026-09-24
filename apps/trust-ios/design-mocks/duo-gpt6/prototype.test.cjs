/* Optional browser verification. The prototype itself needs no dependencies. */
const { test, before, after, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
const { createServer } = require('node:http');
const { readFile } = require('node:fs/promises');
const { join, extname } = require('node:path');
const { pathToFileURL } = require('node:url');

let browser, server, httpBase;
let pages = [];
const errors = [];
const externalRequests = [];
const files = new Set(['index.html', 'app.html', 'app.js', 'styles.css']);

before(async () => {
  browser = await chromium.launch({ headless: true });
  server = createServer(async (req, res) => {
    const name = new URL(req.url, 'http://localhost').pathname.slice(1) || 'index.html';
    if (!files.has(name)) { res.writeHead(404).end(); return; }
    try {
      const data = await readFile(join(__dirname, name));
      res.writeHead(200, {'Content-Type': {'.html':'text/html', '.js':'text/javascript', '.css':'text/css'}[extname(name)]});
      res.end(data);
    } catch { res.writeHead(500).end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  httpBase = `http://127.0.0.1:${server.address().port}/`;
});
afterEach(async () => {
  await Promise.all(pages.map(page => page.close())); pages = [];
  assert.deepEqual(errors.splice(0), [], 'No browser runtime errors');
  assert.deepEqual(externalRequests.splice(0), [], 'No external network requests');
});
after(async () => {
  await browser?.close();
  if (server) await new Promise(resolve => server.close(resolve));
});

async function open(protocol, route = 'circle', width = 393, useClock = false) {
  const page = await browser.newPage({viewport:{width, height:852}}); pages.push(page);
  // Install before app timers are registered so fastForward controls real expiry logic.
  if (useClock) await page.clock.install();
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => { if (/^https?:/.test(request.url()) && !request.url().startsWith(httpBase)) externalRequests.push(request.url()); });
  const url = protocol === 'file' ? pathToFileURL(join(__dirname, 'app.html')).href : httpBase+'app.html';
  await page.goto(`${url}#${route}`);
  // Circle is list-first: its h1 is visually hidden, so wait for attachment rather than visibility.
  await page.locator('#screen h1').waitFor({state:'attached'});
  return page;
}
async function tab(page, name) {
  await page.locator('#tabs').getByRole('link', {name,exact:true}).click();
  await page.waitForFunction(expected => location.hash === `#${expected}`, name.toLowerCase());
  // hash changes before the hashchange handler renders the new screen.
  await page.locator(`#tabs a[href="#${name.toLowerCase()}"][aria-current="page"]`).waitFor();
}

for (const protocol of ['file', 'http']) {
  test(`${protocol}: sealed by default; cancel/Escape never reveal; confirmation creates a receipt and only one pin`, async () => {
    const page = await open(protocol);
    assert.equal(await page.locator('.person-row').count(), 9);
    assert.equal(await page.getByText('Sealed', {exact:false}).count() >= 6, true, 'Until-they-look people stay Sealed');
    assert.equal(await page.getByText('Available', {exact:false}).count() >= 3, true, 'Always / For a while show Available');
    assert.equal(await page.getByText('Sealed · presence hidden').count(), 2, 'Hidden + sealed (not Always)');
    assert.equal(await page.getByText('Available · presence hidden').count(), 1, 'Hidden can still share location as Available');
    assert.equal(await page.getByRole('button', {name:'View Leo Park',exact:true}).count(), 1, 'Available people use View, not Look');
    assert.equal(await page.locator('#screen h1').evaluate(el => el.classList.contains('sr-only')), true, 'Circle is list-first: no visible page title');
    assert.equal(await page.locator('.stats-strip, .stat').count(), 0, 'No counters on Circle');
    assert.equal(await page.locator('.app-header [data-action], .app-header button').count(), 0, 'No + in the header; Invite is a tab');
    assert.equal(await page.getByText('Inner Sunset').count(), 0);
    await page.getByRole('link', {name:'Map',exact:true}).click();
    await page.locator('.map-pin').first().waitFor();
    assert.equal(await page.locator('.map-pin').count(), 3, 'Available shares appear on the map without Look');
    await tab(page, 'Circle');
    await page.getByRole('button', {name:'View Leo Park',exact:true}).click();
    await page.getByRole('heading', {name:'Leo.'}).waitFor();
    assert.match(await page.locator('#screen').innerText(), /Capitol Hill/);
    assert.match(await page.locator('#screen').innerText(), /view logged/);
    await tab(page, 'You');
    assert.match(await page.locator('.receipt-row').innerText(), /You viewed Leo Park/);
    await tab(page, 'Circle');
    await page.getByRole('button', {name:'Look at Maya Chen',exact:true}).click();
    await page.getByRole('dialog').waitFor();
    const sheet = await page.getByRole('dialog').innerText();
    assert.match(sheet, /Maya will be notified/);
    assert.ok(sheet.indexOf('Maya will be notified') < sheet.indexOf('snapshot'), 'Consequence (notify) is stated before what gets revealed');
    assert.equal(await page.locator('#screen').evaluate(el => el.inert), true);
    await page.keyboard.press('Shift+Tab');
    assert.equal(await page.getByRole('button', {name:'Cancel',exact:true}).evaluate(el => el === document.activeElement), true);
    await page.keyboard.press('Tab');
    assert.equal(await page.getByRole('button', {name:'Close confirmation',exact:true}).evaluate(el => el === document.activeElement), true);
    await page.keyboard.press('Escape');
    assert.equal(await page.getByRole('dialog').count(), 0);
    assert.equal(await page.getByRole('button', {name:'Look at Maya Chen',exact:true}).count(), 1);
    await page.getByRole('button', {name:'Look at Maya Chen',exact:true}).click();
    await page.getByRole('button', {name:'Cancel',exact:true}).click();
    assert.equal(await page.getByRole('dialog').count(), 0);
    await page.getByRole('button', {name:'Look at Maya Chen',exact:true}).click();
    await page.getByRole('button', {name:'Look · notify Maya',exact:true}).click();
    await page.getByRole('heading', {name:'Maya.'}).waitFor();
    assert.match(await page.locator('#screen').innerText(), /Inner Sunset/);
    assert.match(await page.locator('#screen').innerText(), /Snapshot only/);
    await page.getByRole('link', {name:'Circle map'}).click();
    await page.locator('.map-pin').first().waitFor();
    assert.equal(await page.locator('.map-pin').count(), 4, 'Maya Look + 3 Available');
    assert.match(await page.locator('#screen').innerText(), /5 sealed location/);
    await tab(page, 'You');
    assert.equal(await page.locator('.receipt-row').count(), 2);
    assert.match(await page.locator('.receipt-row').first().innerText(), /You looked at Maya Chen/);
    await tab(page, 'Circle');
    await page.getByRole('button', {name:'View Maya Chen',exact:true}).click();
    await page.getByRole('heading', {name:'Maya.'}).waitFor();
    await tab(page, 'You');
    assert.equal(await page.locator('.receipt-row').count(), 2, 'Reviewing a saved snapshot does not create another look');
  });

  test(`${protocol}: inline modes, duration, timer expiration, presence, and global stop`, async () => {
    const page = await open(protocol, 'sharing', 393, true);
    const maya = page.getByRole('region', {name:'Sharing with Maya Chen'});
    await maya.getByRole('button', {name:'Always',exact:true}).click();
    assert.equal(await maya.getByRole('button', {name:'Always',exact:true}).getAttribute('aria-pressed'), 'true');
    await maya.getByRole('button', {name:'For a while',exact:true}).click();
    await maya.getByRole('combobox').selectOption('15');
    assert.equal(await maya.getByRole('combobox').inputValue(), '15');
    await tab(page, 'Circle');
    assert.equal(await page.getByRole('button', {name:'Look at Maya Chen',exact:true}).count(), 1, 'Outgoing permissions do not reveal incoming locations');
    await tab(page, 'Sharing');
    assert.equal(await maya.getByRole('combobox').inputValue(), '15');
    await page.clock.fastForward(16*60*1000);
    assert.match(await maya.innerText(), /Not sharing/);
    await maya.getByRole('button', {name:'Until they look',exact:true}).click();
    assert.match(await maya.innerText(), /Sealed until they Look/);
    await maya.getByRole('button', {name:'Stop',exact:true}).click();
    assert.equal(await maya.locator('[aria-pressed=true]').count(), 0);
    await tab(page, 'You');
    const presence = page.getByRole('group', {name:'My presence'});
    assert.deepEqual(await presence.getByRole('button').allInnerTexts(), ['Home','Away','Hidden'], 'Presence is a three-way control');
    await presence.getByRole('button', {name:'Hidden',exact:true}).click();
    assert.equal(await presence.getByRole('button', {name:'Hidden',exact:true}).getAttribute('aria-pressed'), 'true');
    assert.match(await page.locator('#screen').innerText(), /Your circle sees no presence signal/);
    assert.equal(await page.getByRole('switch').count(), 0, 'Look notifications have no toggle; they cannot be disabled');
    assert.match(await page.locator('#screen').innerText(), /Available views are logged/);
    assert.match(await page.locator('.plus-card').innerText(), /Privacy basics stay free/, 'Plus teaser sells capacity, not privacy');
    await page.getByRole('button', {name:'Stop all location sharing'}).click();
    assert.match(await page.locator('.privacy-summary').innerText(), /No outbound location shares/);
    await tab(page, 'Sharing');
    assert.equal(await page.locator('.mode-control [aria-pressed=true]').count(), 0);
  });

  test(`${protocol}: nine-city scenario has selectable pins, correct detail, and explicit disclosure`, async () => {
    const page = await open(protocol, 'map-demo');
    assert.equal(await page.locator('.map-pin').count(), 9);
    const cities = ['San Francisco','Seattle','Lisbon','New York','Austin','London','Tokyo','Mexico City','Sydney'];
    for (const city of cities) {
      await page.locator(`.map-pin[aria-label$=", ${city}"]`).click();
      assert.match(await page.locator('.map-person-card').innerText(), new RegExp(city));
      assert.equal(await page.locator('.map-pin[aria-pressed=true]').count(), 1);
    }
    await page.getByRole('button', {name:'Refresh simulated locations',exact:true}).click();
    assert.match(await page.locator('#toast').innerText(), /Simulated updates/);
    assert.match(await page.locator('.scenario-banner').innerText(), /all nine friends granted Always access/);
    await tab(page, 'You');
    assert.equal(await page.locator('.receipt-row').count(), 9);
  });

  test(`${protocol}: invitation validation, safe rendering, and clipboard fallback`, async () => {
    const page = await open(protocol, 'invite');
    await page.getByRole('button', {name:'Prepare invite'}).click();
    assert.equal(await page.locator('.invite-success').count(), 0);
    assert.equal(await page.locator('#invite-email').evaluate(el => el.validity.valueMissing), true);
    await page.locator('#invite-email').fill('friend@example.com');
    await page.getByRole('button', {name:'Prepare invite'}).click();
    assert.match(await page.locator('.invite-success').innerText(), /friend@example.com/);
    assert.match(await page.locator('.invite-success').innerText(), /Nothing sent/);
    await page.getByRole('button', {name:'Invite someone else'}).click();
    await page.evaluate(() => Object.defineProperty(navigator, 'clipboard', {value:{writeText:() => Promise.reject(new Error('Denied'))}, configurable:true}));
    await page.getByRole('button', {name:'Copy demo invite link'}).click();
    assert.equal(await page.locator('.invite-code').innerText(), 'https://trust.example/invite/alex-demo');
    assert.match(await page.locator('#toast').innerText(), /Copy unavailable/);
    await page.evaluate(() => { document.querySelector('#invite-email').value = '"<img/src=x>"@example.com'; document.querySelector('#invite-form').dispatchEvent(new Event('submit', {bubbles:true,cancelable:true})); });
    assert.equal(await page.locator('.invite-success img').count(), 0);
    assert.match(await page.locator('.invite-success').innerText(), /<img\/src=x>/);
  });
}

test('file: all gallery embeds and deep links load without external assets or horizontal overflow', async () => {
  const page = await open('file');
  await page.setViewportSize({width:1440,height:1000});
  await page.goto(pathToFileURL(join(__dirname,'index.html')).href);
  assert.equal(await page.locator('iframe').count(), 6);
  for (const frame of await page.locator('iframe').all()) {
    await frame.scrollIntoViewIfNeeded();
    const content = await frame.contentFrame();
    await content.locator('#screen h1').waitFor({state:'attached'});
    assert.equal(await content.locator('body').evaluate(el => el.scrollWidth <= innerWidth), true);
  }
  for (const width of [1440,1024,768,393,320]) {
    await page.setViewportSize({width,height:1000});
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `Gallery fits at ${width}px`);
  }
  const links = await page.locator('a').evaluateAll(elements => elements.map(el => el.getAttribute('href')));
  for (const link of new Set(links)) {
    await page.goto(new URL(link, pathToFileURL(join(__dirname,'index.html'))).href);
    assert.equal(await page.locator('h1').count(), 1, `Deep link ${link} loads`);
  }
});

test('file: every phone route fits at 320px; footer remains reachable; reload resets state', async () => {
  const page = await open('file', 'circle', 320);
  for (const route of ['circle','look','view-demo','map-demo','sharing','invite','you']) {
    await page.goto(`${pathToFileURL(join(__dirname,'app.html')).href}#${route}`);
    await page.locator('#screen h1').waitFor({state:'attached'});
    assert.equal(await page.locator('#screen').evaluate(el => el.scrollWidth <= el.clientWidth), true, `${route} fits narrow phone`);
    const bounds = await page.locator('#tabs').boundingBox();
    assert.ok(bounds.y+bounds.height <= 852, `${route} footer fits`);
  }
  await page.goto(`${pathToFileURL(join(__dirname,'app.html')).href}#circle`);
  await page.reload();
  assert.equal(await page.locator('[data-action=look]').count(), 6, 'Only sealed people require Look after reload');
  assert.equal(await page.locator('[data-action=view]').count(), 3, 'Available people keep View');
});
