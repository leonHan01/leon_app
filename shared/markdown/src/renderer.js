import MarkdownIt from 'markdown-it';
import taskLists from 'markdown-it-task-lists';
import footnotes from 'markdown-it-footnote';
import definitions from 'markdown-it-deflist';
import mark from 'markdown-it-mark';
import sub from 'markdown-it-sub';
import sup from 'markdown-it-sup';
import { full as emoji } from 'markdown-it-emoji';
import anchor from 'markdown-it-anchor';
import { katex } from '@mdit/plugin-katex';
import DOMPurify from 'dompurify';
import hljs from 'highlight.js';

const root = document.getElementById('message');
const escape = value => MarkdownIt().utils.escapeHtml(value);
const slug = value => value.trim().toLowerCase().replace(/\s+/g, '-').replace(/[^\p{L}\p{N}_-]/gu, '');
let source = null, generation = 0, lastHeight = 0, diagramsPromise, measuring = false;
let theme = 'light';
const emit = value => {
  const encoded = JSON.stringify(value);
  if (window.webkit?.messageHandlers?.leonMarkdown) window.webkit.messageHandlers.leonMarkdown.postMessage(encoded);
  else if (window.LeonBridge?.postMessage) window.LeonBridge.postMessage(encoded);
  window.dispatchEvent(new CustomEvent('leon-markdown-event', { detail: value }));
};

const md = new MarkdownIt({ html: true, breaks: true, linkify: true })
  .use(taskLists, { enabled: true, label: true })
  .use(footnotes).use(definitions).use(mark).use(sub).use(sup).use(emoji)
  .use(anchor, { slugify: slug })
  .use(katex, { delimiters: 'all', mathFence: true, throwOnError: false, trust: false,
    maxExpand: 1000, maxSize: 20, strict: 'ignore' });

md.inline.ruler.before('link', 'wiki', (state, silent) => {
  const start = state.pos;
  if (state.src.slice(start, start + 2) !== '[[') return false;
  const end = state.src.indexOf(']]', start + 2);
  if (end < 0) return false;
  const content = state.src.slice(start + 2, end);
  if (!content || content.includes('\n')) return false;
  const [target, ...alias] = content.split('|');
  const label = alias.join('|') || target.replace(/^#/, '');
  if (!silent) {
    const open = state.push('link_open', 'a', 1);
    const external = /^(https?:\/\/|mailto:)/i.test(target);
    open.attrSet('href', external ? target : '#' + encodeURIComponent(slug(target.split('#').pop())));
    open.attrSet('class', 'wiki-link');
    if (!external) open.attrSet('data-wiki-target', target);
    state.push('text', '', 0).content = label;
    state.push('link_close', 'a', -1);
  }
  state.pos = end + 2;
  return true;
});

// Parse the original delimiter sequence, so escaped stars and code stay literal.
md.inline.ruler.before('emphasis', 'cjk-strong', (state, silent) => {
  const match = /^\*\*([^*\n]+[\u3000-\u303f\uff00-\uffef])\*\*(?=\S)/.exec(state.src.slice(state.pos));
  if (!match) return false;
  if (!silent) {
    state.push('strong_open', 'strong', 1);
    const children = [];
    state.md.inline.parse(match[1], state.md, state.env, children);
    state.tokens.push(...children);
    state.push('strong_close', 'strong', -1);
  }
  state.pos += match[0].length;
  return true;
});

const alertTitles = { NOTE: '提示', TIP: '建议', IMPORTANT: '重要', WARNING: '警告', CAUTION: '注意' };
md.core.ruler.after('inline', 'alerts', state => {
  const tokens = state.tokens;
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i].type !== 'blockquote_open' || tokens[i + 2]?.type !== 'inline') continue;
    const inline = tokens[i + 2];
    const match = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\](?:[ \t]+([^\n]+))?(?:\n|$)/i.exec(inline.content);
    if (!match) continue;
    const type = match[1].toUpperCase();
    tokens[i].meta = { alert: type, title: match[2] || alertTitles[type] };
    // Find the matching close without touching nested quotes.
    let nesting = 1;
    for (let j = i + 1; j < tokens.length; j++) {
      if (tokens[j].type === 'blockquote_open') nesting++;
      if (tokens[j].type === 'blockquote_close' && --nesting === 0) { tokens[j].meta = { alert: type }; break; }
    }
    inline.content = inline.content.slice(match[0].length);
    inline.children = [];
    state.md.inline.parse(inline.content, state.md, state.env, inline.children);
  }
});
md.renderer.rules.blockquote_open = (tokens, i) => tokens[i].meta?.alert
  ? `<aside class="alert alert-${tokens[i].meta.alert.toLowerCase()}"><p class="alert-title">${escape(tokens[i].meta.title)}</p>\n`
  : '<blockquote>\n';
md.renderer.rules.blockquote_close = (tokens, i) => tokens[i].meta?.alert ? '</aside>\n' : '</blockquote>\n';

const defaultFence = md.renderer.rules.fence;
md.renderer.rules.fence = (tokens, i, options, env, renderer) => {
  const token = tokens[i];
  const language = token.info.trim().split(/\s+/)[0].toLowerCase();
  if (language === 'mermaid') return `<div class="diagram" data-mermaid="${encodeURIComponent(token.content)}"><pre>${escape(token.content)}</pre></div>\n`;
  // The math plugin handles math/latex fences before this rule when enabled.
  if (language === 'math' || language === 'latex') return defaultFence(tokens, i, options, env, renderer);
  let code = escape(token.content);
  if (language && hljs.getLanguage(language)) {
    try { code = hljs.highlight(token.content, { language, ignoreIllegals: true }).value; } catch { /* preserve code */ }
  }
  return `<pre><code class="hljs${language ? ' language-' + escape(language) : ''}">${code}</code></pre>\n`;
};

const safeURL = (url, image = false) => image
  ? /^https:\/\//i.test(url) || /^data:image\/(png|jpeg|gif|webp);base64,/i.test(url)
  : /^https?:\/\//i.test(url) || /^mailto:/i.test(url) || url.startsWith('#');

function cleanStyle(value) {
  const probe = document.createElement('span'); probe.style.cssText = value;
  const output = [];
  for (const property of ['color', 'background-color', 'font-weight', 'font-style', 'text-decoration', 'text-align']) {
    const val = probe.style.getPropertyValue(property);
    if (val && !/url|expression|var\s*\(/i.test(val)) output.push(`${property}:${val}`);
  }
  // KaTeX positions its glyphs using numeric inline dimensions. Keep these
  // values while rejecting URL-bearing CSS and arbitrary positioning rules.
  for (const property of ['height', 'width', 'min-width', 'max-width', 'vertical-align', 'margin-left', 'margin-right',
    'padding-left', 'padding-right', 'padding-top', 'padding-bottom', 'margin-top', 'margin-bottom',
    'top', 'bottom', 'left', 'right', 'border-top-width', 'border-bottom-width', 'border-left-width', 'border-right-width', 'font-size']) {
    const val = probe.style.getPropertyValue(property);
    if (/^-?(?:\d+(?:\.\d*)?|\.\d+)(?:px|em|rem|%)$/.test(val)) output.push(`${property}:${val}`);
  }
  return output.join(';');
}
DOMPurify.addHook('afterSanitizeAttributes', node => {
  if (!(node instanceof Element)) return;
  if (node.hasAttribute('style')) { const style = cleanStyle(node.getAttribute('style')); if (style) node.setAttribute('style', style); else node.removeAttribute('style'); }
  if (node.hasAttribute('href') && !safeURL(node.getAttribute('href'))) node.removeAttribute('href');
  if (node.tagName === 'IMG') {
    node.removeAttribute('srcset');
    if (!safeURL(node.getAttribute('src') || '', true)) node.removeAttribute('src');
    node.setAttribute('referrerpolicy', 'no-referrer');
    node.setAttribute('loading', 'lazy'); node.setAttribute('decoding', 'async');
  }
  if (node.tagName === 'INPUT') {
    if (node.getAttribute('type') !== 'checkbox') node.remove();
    else { node.removeAttribute('name'); node.removeAttribute('form'); node.setAttribute('aria-label', '任务完成状态（仅当前显示）'); }
  }
  for (const attr of ['colspan', 'rowspan']) {
    if (node.hasAttribute(attr)) node.setAttribute(attr, String(Math.min(100, Math.max(1, parseInt(node.getAttribute(attr), 10) || 1))));
  }
});

function sanitize(html) {
  return DOMPurify.sanitize(html, {
    FORBID_TAGS: ['script', 'style', 'iframe', 'object', 'embed', 'form', 'textarea', 'select', 'button', 'video', 'audio', 'link', 'meta', 'base'],
    FORBID_ATTR: ['srcdoc', 'autofocus', 'contenteditable', 'action', 'formaction'],
    ALLOW_DATA_ATTR: false,
    ADD_ATTR: ['data-mermaid', 'data-wiki-target', 'loading', 'decoding', 'referrerpolicy', 'checked', 'open'],
  });
}

function measure() {
  if (measuring) return;
  measuring = true;
  // Native containers also need the final size before a page becomes visible;
  // WebKit can suspend animation frames for offscreen message views.
  Promise.resolve().then(() => {
    measuring = false;
    const style = getComputedStyle(document.body);
    const height = Math.ceil(root.getBoundingClientRect().height + parseFloat(style.paddingTop) + parseFloat(style.paddingBottom) + 2);
    if (height !== lastHeight) { lastHeight = height; emit({ type: 'height', height }); }
  });
}

function decorate() {
  for (const pre of root.querySelectorAll('pre')) {
    if (pre.closest('.diagram') || pre.closest('.code-block')) continue;
    const code = pre.querySelector('code'); if (!code) continue;
    const wrapper = document.createElement('div'); wrapper.className = 'code-block';
    pre.replaceWith(wrapper);
    const toolbar = document.createElement('div'); toolbar.className = 'code-toolbar';
    const label = document.createElement('span'); label.textContent = [...code.classList].find(c => c.startsWith('language-'))?.slice(9) || '代码';
    const copy = document.createElement('button'); copy.type = 'button'; copy.textContent = '复制代码';
    copy.addEventListener('click', () => { emit({ type: 'copy', text: code.textContent }); copy.textContent = '已复制'; setTimeout(() => { copy.textContent = '复制代码'; }, 1600); });
    toolbar.append(label, copy); wrapper.append(toolbar, pre);
  }
  for (const table of root.querySelectorAll('table')) {
    const scroll = document.createElement('div'); scroll.className = 'table-scroll';
    table.replaceWith(scroll); scroll.append(table);
  }
  for (const image of root.querySelectorAll('img')) {
    const fail = () => { const fallback = document.createElement('span'); fallback.className = 'image-fallback'; fallback.textContent = image.alt || '图片加载失败'; image.replaceWith(fallback); measure(); };
    image.addEventListener('load', measure); image.addEventListener('error', fail);
    if (!image.hasAttribute('src')) fail();
  }
  for (const details of root.querySelectorAll('details')) details.addEventListener('toggle', measure);
}

function loadDiagrams() {
  if (!diagramsPromise) diagramsPromise = new Promise((resolve, reject) => {
    const script = document.createElement('script'); script.src = new URL('diagrams.js', document.baseURI).href;
    script.onload = () => resolve(window.LeonDiagrams); script.onerror = reject; document.head.append(script);
  });
  return diagramsPromise;
}

async function drawDiagrams(version) {
  const nodes = [...root.querySelectorAll('[data-mermaid]')];
  if (!nodes.length) return;
  try {
    const mermaid = await loadDiagrams();
    if (version !== generation) return;
    mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme, htmlLabels: false, maxTextSize: 10000, maxEdges: 500,
      suppressErrorRendering: true, fontFamily: 'system-ui, sans-serif', flowchart: { htmlLabels: false },
      secure: ['secure', 'securityLevel', 'startOnLoad', 'maxTextSize', 'maxEdges', 'suppressErrorRendering', 'fontFamily', 'htmlLabels'] });
    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i];
      const code = decodeURIComponent(node.getAttribute('data-mermaid'));
      try {
        const { svg } = await mermaid.render(`leon_diagram_${version}_${i}`, code);
        if (version !== generation) return;
        // Mermaid's strict mode already sanitizes its SVG. This second pass
        // removes event handlers and embedded navigation from the final result.
        const clean = DOMPurify.sanitize(svg, { USE_PROFILES: { html: true, svg: true, svgFilters: true, mathMl: true }, ADD_TAGS: ['style', 'foreignObject'],
          FORBID_TAGS: ['a', 'script', 'image'], FORBID_ATTR: ['href', 'xlink:href'] });
        node.innerHTML = clean;
        node.querySelector('svg')?.setAttribute('aria-label', 'Mermaid 图表');
      } catch {
        node.replaceChildren(); const pre = document.createElement('pre'); pre.textContent = code; node.append(pre);
        const message = document.createElement('small'); message.textContent = '图表语法有误，已保留原文'; node.append(message);
      }
      measure();
    }
  } catch { /* the readable source stays visible if the optional renderer fails */ }
}

root.addEventListener('click', event => {
  const link = event.target.closest('a');
  if (!link) return;
  event.preventDefault();
  const url = link.getAttribute('href') || '';
  if (url.startsWith('#')) {
    let id; try { id = decodeURIComponent(url.slice(1)); } catch { return; }
    const target = document.getElementById(id);
    if (target && root.contains(target)) {
      for (let parent = target.parentElement; parent && parent !== root; parent = parent.parentElement) if (parent.tagName === 'DETAILS') parent.open = true;
      emit({ type: 'anchor', y: target.getBoundingClientRect().top + window.scrollY });
    } else {
      emit({ type: 'notice', text: `未找到当前消息中的标题：${link.getAttribute('data-wiki-target') || id}` });
    }
  } else if (safeURL(url)) emit({ type: 'open', url });
});

root.addEventListener('contextmenu', event => {
  if (document.body.dataset.platform !== 'mac') return;
  event.preventDefault();
  emit({ type: 'context', x: event.clientX, y: event.clientY });
});

window.renderMessage = async payload => {
  const nextTheme = payload.dark || payload.mine && payload.platform !== 'android' ? 'dark' : 'default';
  const nextSource = String(payload.source ?? '');
  const changed = source !== nextSource;
  const themeChanged = theme !== nextTheme;
  theme = nextTheme;
  document.body.dataset.theme = nextTheme === 'dark' ? 'dark' : 'light';
  document.body.dataset.mine = String(!!payload.mine);
  document.body.dataset.platform = payload.platform || 'mac';
  const fontScale = payload.fontScale;
  if (document.body.dataset.platform === 'mac' && Number.isFinite(fontScale) && fontScale > 0) {
    document.body.style.setProperty('--message-font-scale', fontScale);
  } else {
    document.body.style.removeProperty('--message-font-scale');
  }
  if (changed) {
    generation++;
    source = nextSource;
    // A new environment isolates KaTeX macros and footnotes between messages.
    try { root.innerHTML = sanitize(md.render(source, {})); }
    catch { root.replaceChildren(); const pre = document.createElement('pre'); pre.textContent = source; root.append(pre); }
    decorate();
  }
  if (changed || themeChanged) await drawDiagrams(generation);
  await document.fonts?.ready;
  measure();
  emit({ type: 'rendered' });
};
new ResizeObserver(measure).observe(root);
window.addEventListener('resize', measure);
window.LeonMarkdown = { render: input => sanitize(md.render(input, {})), safeURL };
emit({ type: 'ready' });
