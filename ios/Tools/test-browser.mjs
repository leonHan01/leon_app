import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';

// Exercise the same feature suite as Android/Mac against the actual iOS bundle
// and WKWebView bridge shape. The shared sources and tests remain unchanged.
const ios = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const shared = path.resolve(ios, '../shared/markdown');
const results = path.join(ios, '.build/renderer-browser');
await fs.mkdir(results, { recursive: true });
let suite = await fs.readFile(path.join(shared, 'tests/renderer.test.mjs'), 'utf8');
function replaceOnce(before, after) {
  if (!suite.includes(before)) throw new Error('Shared renderer test changed; review iOS adapter: ' + before);
  suite = suite.replace(before, after);
}
replaceOnce("import { chromium } from 'playwright-core';", `import { createRequire } from 'node:module';\nconst { chromium } = createRequire(${JSON.stringify(path.join(shared, 'package.json'))})('playwright-core');`);
replaceOnce("const runtime = path.resolve(fileURLToPath(new URL('../runtime/', import.meta.url)));", `const runtime = ${JSON.stringify(path.join(ios, 'Resources/Markdown'))};`);
replaceOnce("window.LeonBridge = { postMessage: value => window.nativeEvents.push(JSON.parse(value)) };", "window.webkit = { messageHandlers: { leonMarkdown: { postMessage: value => window.nativeEvents.push(JSON.parse(value)) } } };");
// Desktop context menus use a JS event; mobile uses its native context menu.
// Both still share the code-copy bridge exercised immediately beforehand.
replaceOnce("assert.equal(await page.evaluate(() => window.nativeEvents.at(-1).type), 'context');", "assert.equal(await page.evaluate(() => window.nativeEvents.some(event => event.type === 'context')), false, 'iOS must keep its native context-menu handling');");
suite = suite.replaceAll("platform: 'mac'", "platform: 'ios'").replaceAll("platform: 'android'", "platform: 'ios'");
suite = suite.replaceAll("new URL('../test-results/', import.meta.url)", `new URL(${JSON.stringify(pathToFileURL(results + path.sep).href)})`);
suite = suite.replaceAll("new URL('../test-results/android-dark.png', import.meta.url)", `new URL(${JSON.stringify(pathToFileURL(path.join(results, 'ios-dark.png')).href)})`);
const test = path.join(results, 'native-renderer.test.mjs');
await fs.writeFile(test, suite);
const run = spawnSync(process.execPath, ['--test', test], { stdio: 'inherit', env: process.env });
process.exit(run.status ?? 1);
