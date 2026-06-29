#!/usr/bin/env node
// roadmap/visual-check.mjs — headless render check for ROADMAP.html.
//
// Why: the live roadmap is a self-contained HTML file (no build step), and Chrome
// was removed from the dev Mac — so a regression in the inline JS would otherwise
// only show up by eyeballing the deployed Artifact. This loads the file in
// Playwright's Chromium and ASSERTS the things that have actually broken before:
//   1. no JS errors on load,
//   2. all 5 history era nodes (H_elec/H_rn/H_desk/H_mob/H_conv) render + are positioned,
//   3. opening a history card shows its shipped log (shipLine-parsed dated rows).
// It also writes two screenshots next to the file for a quick eyeball.
//
// Run:  node roadmap/visual-check.mjs            (exit 0 = pass, 1 = fail)
// Needs Playwright (globally installed in the web/remote env at /opt/node22; or
// `npm i -D playwright` locally). Chromium is pre-installed in the remote env.

import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const require = createRequire(import.meta.url);
function loadPlaywright() {
  const candidates = [
    'playwright',
    '/opt/node22/lib/node_modules/playwright/index.js',
    process.env.PLAYWRIGHT_PATH,
  ].filter(Boolean);
  for (const c of candidates) {
    try { return require(c); } catch { /* try next */ }
  }
  console.error('✗ Playwright not found. Install it (`npm i -D playwright`) or set PLAYWRIGHT_PATH.');
  process.exit(2);
}
const { chromium } = loadPlaywright();

const ERAS = ['H_elec', 'H_rn', 'H_desk', 'H_mob', 'H_conv'];
const here = path.dirname(new URL(import.meta.url).pathname);
const file = path.join(here, 'ROADMAP.html');
const url = pathToFileURL(file).href;

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
page.on('console', m => { if (m.type() === 'error') errors.push('console: ' + m.text()); });

await page.goto(url, { waitUntil: 'networkidle' });
await page.waitForTimeout(400);

const result = await page.evaluate((eras) => {
  const histCount = document.querySelectorAll('.node.hist').length;
  const present = {}, positioned = {};
  eras.forEach(id => {
    const el = document.querySelector(`.node[data-id="${id}"]`);
    present[id] = !!el;
    positioned[id] = el ? (el.style.left !== '' && el.style.top !== '') : false;
  });
  return { histCount, present, positioned };
}, ERAS);

await page.click('.node[data-id="H_elec"]');
await page.waitForTimeout(250);
const ship = await page.evaluate(() => {
  const pop = document.querySelector('#pop.open');
  if (!pop) return { open: false };
  const rows = pop.querySelectorAll('.shiprow');
  return {
    open: true,
    header: pop.querySelector('.ship-h')?.textContent || '',
    rowCount: rows.length,
    firstDate: rows[0]?.querySelector('.shipdate')?.textContent || '',
    firstHash: rows[0]?.querySelector('.shiphash')?.textContent || '',
  };
});

await page.keyboard.press('Escape');
await page.waitForTimeout(150);
await page.click('#zfit');
await page.waitForTimeout(300);
await page.screenshot({ path: path.join(here, 'visual-check-full.png') });
await page.click('.node[data-id="H_conv"]');
await page.waitForTimeout(250);
await page.screenshot({ path: path.join(here, 'visual-check-shiplog.png') });
await browser.close();

const allPresent = ERAS.every(id => result.present[id]);
const allPositioned = ERAS.every(id => result.positioned[id]);
console.log(JSON.stringify({ ...result, ship, errors, allPresent, allPositioned }, null, 2));

let ok = true;
if (errors.length) { console.error('✗ JS errors on load'); ok = false; }
if (result.histCount !== ERAS.length) { console.error(`✗ expected ${ERAS.length} .node.hist, got ${result.histCount}`); ok = false; }
if (!allPresent) { console.error('✗ not all era nodes present'); ok = false; }
if (!allPositioned) { console.error('✗ some era node not positioned'); ok = false; }
if (!ship.open || ship.rowCount < 1) { console.error('✗ shipped log did not open'); ok = false; }
console.log(ok ? '✓ visual-check PASSED' : '✗ visual-check FAILED');
process.exit(ok ? 0 : 1);
