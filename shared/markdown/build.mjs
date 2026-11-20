import { build } from 'esbuild';
import { mkdir, cp, readFile, writeFile, readdir } from 'node:fs/promises';
import path from 'node:path';
const runtime = new URL('./runtime/', import.meta.url);
await mkdir(runtime, { recursive: true });
await build({ entryPoints: ['src/renderer.js', 'src/diagrams.js'], outdir: 'runtime', bundle: true,
  format: 'iife', target: ['chrome80', 'safari15'], minify: true, legalComments: 'linked', logLevel: 'info' });
for (const file of ['markdown.html', 'renderer.css']) await cp(new URL(`src/${file}`, import.meta.url), new URL(file, runtime));
await cp('node_modules/katex/dist/katex.min.css', new URL('katex.min.css', runtime));
await mkdir(new URL('fonts/', runtime), { recursive: true });
for (const name of await readdir('node_modules/katex/dist/fonts')) if (name.endsWith('.woff2')) {
  await cp(`node_modules/katex/dist/fonts/${name}`, new URL(`fonts/${name}`, runtime));
}
const lock = JSON.parse(await readFile('package-lock.json', 'utf8'));
const notices = ['Leon message Markdown runtime — third-party licenses\n'];
for (const [location] of Object.entries(lock.packages)) {
  if (!location || lock.packages[location].dev) continue;
  const names = await readdir(location);
  const license = names.find(name => /^licen[sc]e(?:\.|$)/i.test(name));
  if (license) notices.push(`\n--- ${location} ---\n${await readFile(path.join(location, license), 'utf8')}`);
}
await writeFile(new URL('THIRD-PARTY-LICENSES.txt', runtime), notices.join('\n'));
