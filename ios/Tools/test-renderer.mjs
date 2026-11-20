import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const ios = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const shared = path.resolve(ios, '../shared/markdown');
const require = createRequire(path.join(shared, 'package.json'));
const MarkdownIt = require('markdown-it');
const { patchSource } = await import('./prepare-assets.mjs');
const source = patchSource(fs.readFileSync(path.join(shared, 'src/renderer.js'), 'utf8'));
const start = source.indexOf("md.inline.ruler.before('emphasis', 'cjk-strong'");
const end = source.indexOf('const alertTitles', start);
const md = new MarkdownIt({html:true,linkify:true,breaks:true});
const configStart = source.indexOf('md.linkify.set(');
new Function('md', source.slice(configStart, source.indexOf('\n', configStart)))(md);
new Function('md', source.slice(start,end))(md);
md.use(require('markdown-it-mark')).use(require('markdown-it-sup')).use(require('markdown-it-deflist'));
const cases = [
  ['这是**“注意力”**机制', '<strong>“注意力”</strong>'],
  ['**一句话总结：**Transformer', '<strong>一句话总结：</strong>Transformer'],
  ['标题\n===', '<h1>标题</h1>'],
  ['==高亮==', '<mark>高亮</mark>'],
  ['x^2^', '<sup>2</sup>'],
  ['Term\n: definition', '<dl>'],
  ['www.example.com', 'href="http://www.example.com"'],
  ['AT&amp;T', 'AT&amp;T'],
  ['`这是**“注意力”**机制`', '<code>这是**“注意力”**机制</code>'],
  [String.raw`\*\*“注意力”\*\*`, '**“注意力”**'],
  ['**未闭合', '**未闭合'],
];
for (const [input, expected] of cases) assert.ok(md.render(input).includes(expected), input);
console.log(`Native rich text: ${cases.length} cases passed`);
