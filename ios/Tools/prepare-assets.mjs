import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const ios = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const shared = path.resolve(ios, '../shared/markdown');
const output = path.join(ios, 'Resources/Markdown');
const require = createRequire(path.join(shared, 'package.json'));
const esbuild = require('esbuild');
export function patchSource(source) {
const old = "const match = /^\\*\\*([^*\\n]+[\\u3000-\\u303f\\uff00-\\uffef])\\*\\*(?=\\S)/.exec(state.src.slice(state.pos));";
if (!source.includes(old)) throw new Error('Shared renderer changed: review iOS CJK compatibility before rebuilding');
source = source.replace(old, "const match = /^\\*\\*([^*\\n]+)\\*\\*(?=\\S)/.exec(state.src.slice(state.pos));\n  if (match && (!/[^\\x00-\\x7f]/.test(match[1]) || !/\\p{P}/u.test(match[1]))) return false;");
source = source.replace("md.inline.ruler.before('link', 'wiki'", "md.linkify.set({ fuzzyLink: true });\n\nmd.inline.ruler.before('link', 'wiki'");
source = source.replace("payload.platform !== 'android'", "payload.platform !== 'android' && payload.platform !== 'ios'");
return source;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
fs.mkdirSync(output, { recursive: true });
fs.cpSync(path.join(shared, 'runtime'), output, { recursive: true });
const source = patchSource(fs.readFileSync(path.join(shared, 'src/renderer.js'), 'utf8'));
await esbuild.build({ stdin: { contents: source, resolveDir: shared, sourcefile: 'ios-renderer.js' }, bundle: true, minify: true, outfile: path.join(output, 'renderer.js'), platform: 'browser', target: ['safari16'] });
let css = fs.readFileSync(path.join(output, 'renderer.css'), 'utf8').replace('body[data-platform=android]', 'body[data-platform=android],body[data-platform=ios]');
fs.writeFileSync(path.join(output, 'renderer.css'), css);
console.log('Prepared native iOS offline message resources; Android/Mac sources unchanged.');

}
