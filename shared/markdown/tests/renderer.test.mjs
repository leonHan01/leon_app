import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import { chromium } from 'playwright-core';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

let browser, page, server, base;
const runtime = path.resolve(fileURLToPath(new URL('../runtime/', import.meta.url)));
before(async () => {
  server = createServer(async (req, res) => {
    try {
      const name = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\//, '') || 'markdown.html';
      const file = path.resolve(runtime, name);
      if (!file.startsWith(runtime + path.sep)) { res.writeHead(404).end(); return; }
      const types = { '.js': 'text/javascript', '.css': 'text/css', '.html': 'text/html', '.woff2': 'font/woff2' };
      res.setHeader('Content-Type', types[path.extname(file)] || 'text/plain'); res.end(await readFile(file));
    } catch { res.writeHead(404).end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}/markdown.html`;
  browser = await chromium.launch({ executablePath: process.env.LEON_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true });
  page = await browser.newPage({ viewport: { width: 580, height: 800 } });
  await page.addInitScript(() => {
    window.nativeEvents = [];
    window.LeonBridge = { postMessage: value => window.nativeEvents.push(JSON.parse(value)) };
  });
  await page.goto(base);
  await page.waitForFunction(() => !!window.renderMessage);
});
after(async () => { await browser?.close(); await new Promise(resolve => server?.close(resolve)); });
async function render(source, extra = {}) {
  await page.evaluate(async payload => { window.nativeEvents = []; await window.renderMessage(payload); }, { source, mine: false, dark: false, platform: 'mac', ...extra });
  await page.waitForTimeout(80);
}
const text = selector => page.locator(selector).innerText();

test('task lists, footnotes, definition lists, text extensions, emoji and wiki anchors', async () => {
  await render('# 我的标题\n\n- [ ] 待办\n- [x] 完成\n\n正文[^one] 和 [[我的标题|跳转标题]]。\n\n[^one]: 脚注 **说明**\n\n术语\n: 这是定义\n\n==高亮== H~2~O x^2^ :smile:');
  assert.equal(await page.locator('input[type=checkbox]').count(), 2);
  assert.equal(await page.locator('input[type=checkbox]').nth(1).isChecked(), true);
  await page.locator('input[type=checkbox]').first().check();
  assert.equal(await page.locator('input[type=checkbox]').first().isChecked(), true);
  assert.equal(await text('mark'), '高亮');
  assert.equal(await text('sub'), '2'); assert.equal(await text('sup:not(.footnote-ref)'), '2');
  assert.equal(await text('dt'), '术语'); assert.equal(await text('dd'), '这是定义');
  assert.equal(await page.locator('.footnotes strong').innerText(), '说明');
  assert.match(await text('#message'), /😄/u);
  await page.locator('.wiki-link').click();
  assert.equal(await page.evaluate(() => window.nativeEvents.at(-1).type), 'anchor');
  await page.locator('.footnote-ref a').click();
  assert.equal(await page.evaluate(() => window.nativeEvents.at(-1).type), 'anchor');
});

test('HTML collapse, merged table cells, callouts and resize notifications', async () => {
  await render('> [!WARNING]\n> 小心 **操作**\n\n<details><summary>展开详情</summary>\n\n折叠正文。\n\n</details>\n\n<table><tr><th colspan="2">合并标题</th></tr><tr><td rowspan="2">A</td><td>B</td></tr><tr><td>C</td></tr></table>');
  assert.equal(await text('.alert-title'), '警告'); assert.equal(await text('.alert strong'), '操作');
  assert.equal(await page.locator('th').getAttribute('colspan'), '2');
  assert.equal(await page.locator('td').first().getAttribute('rowspan'), '2');
  const before = await page.evaluate(() => document.getElementById('message').getBoundingClientRect().height);
  await page.locator('summary').click(); await page.waitForTimeout(100);
  const height = await page.evaluate(() => document.getElementById('message').getBoundingClientRect().height);
  assert.ok(height > before);
  assert.ok(await page.evaluate(() => window.nativeEvents.some(event => event.type === 'height')));
});

test('syntax highlighting and copy preserve exact original code', async () => {
  const code = 'const value = "**原样**";\nconsole.log(value);\n';
  await render('```javascript\n' + code + '```\n\n**总结：**Transformer\n\n`==不是高亮==` \\*\\*原文：\\*\\*T');
  assert.equal(await page.locator('.hljs-keyword').first().innerText(), 'const');
  assert.equal(await page.locator('pre code').textContent(), code);
  assert.equal(await text('strong'), '总结：');
  assert.equal(await page.locator('mark').count(), 0);
  await page.locator('.code-toolbar button').click();
  assert.equal(await page.evaluate(() => window.nativeEvents.findLast(event => event.type === 'copy').text), code);
  await page.locator('#message').dispatchEvent('contextmenu', { clientX: 20, clientY: 30 });
  assert.equal(await page.evaluate(() => window.nativeEvents.at(-1).type), 'context');
});

test('all math delimiters work alongside extensions without corrupting currency or code', async () => {
  await render('==公式== $x_i^2$ 与 \\(\\frac{a}{b}\\)\n\n\\[\\text{Attention}(Q,K,V)=\\text{softmax}\\left(\\frac{QK^T}{\\sqrt{d_k}}\\right)V\\]\n\n$$\\sum_{i=1}^{n}x_i$$\n\n价格 $5 和 $10。`$x$`');
  assert.equal(await page.locator('.katex').count(), 4);
  assert.equal(await page.locator('.katex-display').count(), 2);
  assert.match(await text('#message'), /价格 \$5 和 \$10/);
  assert.equal(await page.locator('p>code').innerText(), '$x$');
  assert.equal(await page.locator('.katex .frac-line').count() > 0, true);
  assert.ok(await page.evaluate(() => {
    const root = document.querySelector('.katex .sqrt');
    const radicand = root.querySelector('.mathnormal');
    return !!root.querySelector('svg path') && radicand.getBoundingClientRect().left - root.getBoundingClientRect().left > 5;
  }), 'The root sign must have room before the radicand');
});

test('Mermaid produces diagrams and retains invalid source as a fallback', async () => {
  await render('```mermaid\nflowchart LR\n A[开始] --> B[完成]\n```\n\n```mermaid\nsequenceDiagram\n Alice->>Bob: 你好\n```');
  assert.equal(await page.locator('.diagram svg').count(), 2);
  assert.match(await page.locator('.diagram').first().textContent(), /开始/);
  await render('```mermaid\nnot a valid diagram !!!\n```');
  assert.match(await page.locator('.diagram pre').textContent(), /not a valid diagram/);
});

test('remote images display; failures have alt text; injected content cannot execute or navigate', async () => {
  await page.route('https://images.example.test/pixel.png', route => route.fulfill({ contentType: 'image/png', body: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aHeUAAAAASUVORK5CYII=', 'base64') }));
  await render('![示例](https://images.example.test/pixel.png)\n\n<img src="file:///etc/passwd" alt="受限图片" onerror="window.leonUserScriptExecuted=1">\n<script>window.leonUserScriptExecuted=2</script><iframe src="https://example.com"></iframe>\n<a href="javascript:window.leonUserScriptExecuted=3">危险</a>\n<span style="color:red;background-image:url(https://evil.test/x)">文字</span>');
  await page.waitForFunction(() => document.querySelector('img')?.naturalWidth > 0);
  assert.equal(await page.locator('img').getAttribute('referrerpolicy'), 'no-referrer');
  assert.equal(await page.locator('.image-fallback').innerText(), '受限图片');
  assert.equal(await page.locator('script:not([src]),iframe,[onerror]').count(), 0);
  assert.equal(await page.evaluate(() => window.leonUserScriptExecuted), undefined);
  assert.equal(await page.locator('a').getAttribute('href'), null);
  assert.equal(await page.locator('span').last().getAttribute('style'), 'color:red');
});

test('mobile width and dark theme keep wide content inside the message', async () => {
  await page.setViewportSize({ width: 320, height: 800 });
  await render('# 扩展 Markdown\n\n- [x] 已支持\n\n> [!TIP]\n> 文字与 ==高亮==、H~2~O。\n\n```python\ndef hello(name):\n    return "hello " + name\n```\n\n$$\\frac{1}{\\sqrt{d_k}}$$', { dark: true, platform: 'android' });
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  assert.equal(await page.locator('body').getAttribute('data-theme'), 'dark');
  await mkdir(new URL('../test-results/', import.meta.url), { recursive: true });
  await page.evaluate(() => { document.documentElement.style.backgroundColor = '#20242a'; });
  await page.screenshot({ path: fileURLToPath(new URL('../test-results/android-dark.png', import.meta.url)), fullPage: true });
  await page.evaluate(() => { document.documentElement.style.backgroundColor = ''; });
  await page.setViewportSize({ width: 620, height: 900 });
});
