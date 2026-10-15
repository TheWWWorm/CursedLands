const $ = selector => document.querySelector(selector);
const PAGE_SIZE = 40;
const SUPPORTED = ['en', 'ru', 'de'];
const ALLOWED = new Set(['ARTICLE', 'H1', 'H2', 'H3', 'P', 'BR', 'TABLE', 'TBODY', 'TR', 'TH', 'TD', 'A', 'STRONG', 'EM']);
let lang = 'en', strings, catalog, entry, page, resultsPage = 0, generation = 0;
const indexes = new Map(), pages = new Map();

function route() {
  const params = new URLSearchParams(location.search);
  const requested = params.get('lang') || navigator.language.slice(0, 2);
  return {lang: SUPPORTED.includes(requested) ? requested : 'en', key: params.get('page') || 'home', variant: params.get('version') || ''};
}

function href(key, variant = '', language = lang) {
  const params = new URLSearchParams({lang: language, page: key});
  if (variant) params.set('version', variant);
  return '/wiki/?' + params;
}

function navigate(key, variant = '', language = lang) {
  const url = href(key, variant, language);
  if (location.pathname + location.search !== url) history.pushState(null, '', url);
  load();
}

async function json(url, cache) {
  if (!cache.has(url)) cache.set(url, fetch(url, {cache: 'no-cache'}).then(response => {
    if (!response.ok) throw new Error('HTTP ' + response.status);
    return response.json();
  }).catch(error => {cache.delete(url); throw error;}));
  return cache.get(url);
}

function translate() {
  document.documentElement.lang = lang;
  document.title = 'Cursed Lands · ' + strings.encyclopedia;
  $('meta[name=description]').content = strings.description;
  for (const el of document.querySelectorAll('[data-text]')) el.textContent = strings[el.dataset.text];
  $('#language').value = lang;
  $('#search').placeholder = strings.searchHelp;
  $('#results').ariaLabel = strings.results;
  $('header nav').ariaLabel = strings.navigation;
  $('.brand').ariaLabel = 'Cursed Lands · ' + strings.encyclopedia;
  $('.brand').href = $('#contents').href = href('home');
}

function search() {
  if (!catalog) return;
  const words = $('#search').value.trim().toLocaleLowerCase(lang).split(/\s+/).filter(Boolean);
  const category = $('#category').value;
  const found = catalog.entries.filter(row => {
    const text = (row.title + ' ' + (row.search || '') + ' ' + catalog.categories[row.category]).toLocaleLowerCase(lang);
    return (category === 'All pages' || row.category === category) && words.every(word => text.includes(word));
  });
  const count = Math.max(1, Math.ceil(found.length / PAGE_SIZE));
  resultsPage = Math.min(resultsPage, count - 1);
  $('#status').textContent = found.length ? strings.matches.replace('{count}', found.length.toLocaleString(lang)) : strings.empty;
  $('#results').replaceChildren(...found.slice(resultsPage * PAGE_SIZE, (resultsPage + 1) * PAGE_SIZE).map(row => {
    const a = document.createElement('a');
    a.href = href(row.key);
    a.textContent = row.title;
    if (entry?.key === row.key) a.setAttribute('aria-current', 'page');
    return a;
  }));
  $('#page-number').textContent = `${resultsPage + 1} / ${count}`;
  $('#previous').disabled = resultsPage === 0;
  $('#next').disabled = resultsPage + 1 >= count;
}

// Articles are generated from escaped source text, but only the wiki's small
// semantic HTML vocabulary is admitted. Original text never becomes script,
// style, an external URL, an event handler or an arbitrary embedded object.
function article(html) {
  const parsed = new DOMParser().parseFromString(html, 'text/html');
  function safe(node) {
    if (node.nodeType === Node.TEXT_NODE) return document.createTextNode(node.textContent);
    if (node.nodeType !== Node.ELEMENT_NODE || !ALLOWED.has(node.tagName)) return document.createTextNode('');
    const el = document.createElement(node.tagName.toLowerCase());
    if (node.tagName === 'A') {
      const link = node.getAttribute('href') || '';
      if (link.startsWith('wiki://')) {
        const [key, query = ''] = link.slice(7).split('?');
        if (key.startsWith('category/')) {
          el.href = href('home');
          el.dataset.category = decodeURIComponent(key.slice(9));
        } else {
          el.href = href(key, new URLSearchParams(query).get('version') || '');
        }
      }
    }
    el.append(...Array.from(node.childNodes, safe));
    return el;
  }
  return safe(parsed.body.querySelector('article'));
}

function showVersion(id) {
  const version = page.versions.find(row => row.id === id) || page.versions[0];
  $('#variant').value = version.id;
  const content = article(version.html);
  content.id = 'article'; content.tabIndex = -1;
  if (version.image) {
    const figure = document.createElement('figure'), img = document.createElement('img'), caption = document.createElement('figcaption');
    img.src = '/wiki/images/' + version.image + '.webp';
    img.alt = version.title; img.width = 280; img.height = 280;
    img.decoding = 'async';
    caption.textContent = strings.image;
    figure.append(img, caption);
    content.querySelector('h1').after(figure);
  }
  $('#content').replaceChildren(content);
  $('#spell-note').hidden = entry.kind !== 'spell';
  document.title = entry.title + ' · Cursed Lands';
}

async function load() {
  const token = ++generation, target = route();
  lang = target.lang; strings = translations[lang];
  translate();
  $('#notice').textContent = strings.loading;
  $('#versions').hidden = true;
  $('#spell-note').hidden = true;
  $('#content').replaceChildren();
  try {
    const index = await json('/wiki/data/' + lang + '/index.json', indexes);
    if (token !== generation) return;
    const changed = catalog !== index;
    catalog = index;
    if (changed) {
      $('#category').replaceChildren(...Object.entries(catalog.categories).map(([id, name]) => new Option(name, id)));
      $('#search').value = ''; resultsPage = 0;
    }
    $('#version').textContent = catalog.version;
    entry = catalog.entries.find(row => row.key === target.key);
    search();
    if (!entry) {
      $('#notice').textContent = strings.unavailable;
      return;
    }
    const loaded = await json('/wiki/data/' + lang + '/pages/' + entry.file, pages);
    if (token !== generation) return;
    page = loaded;
    $('#variant').replaceChildren(...page.versions.map(row => new Option(row.title, row.id)));
    $('#versions').hidden = page.versions.length < 2;
    showVersion(target.variant);
    $('#notice').textContent = '';
  } catch (error) {
    if (token !== generation) return;
    $('#notice').textContent = strings.error + ' ';
    const button = document.createElement('button');
    button.textContent = strings.retry; button.onclick = load;
    $('#notice').append(button);
  }
}

const translations = await fetch('/wiki/i18n.json', {cache: 'no-cache'}).then(r => {
  if (!r.ok) throw new Error('Translation catalogue unavailable');
  return r.json();
}).catch(() => {
  $('#notice').textContent = 'Could not load. Reload to retry. / Ошибка загрузки. Обновите страницу. / Laden fehlgeschlagen. Bitte neu laden.';
  return null;
});
if (translations) {
  document.addEventListener('click', event => {
    const a = event.target.closest('a');
    if (!a || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    if (a.dataset.category) {
      event.preventDefault();
      $('#category').value = a.dataset.category;
      $('#search').value = ''; resultsPage = 0; search(); $('#search').focus();
    } else if (new URL(a.href).pathname === '/wiki/') {
      event.preventDefault(); history.pushState(null, '', a.href); load();
    }
  });
  $('#search').addEventListener('input', () => {resultsPage = 0; search();});
  $('#category').addEventListener('change', () => {resultsPage = 0; search();});
  $('#language').addEventListener('change', () => navigate(route().key, route().variant, $('#language').value));
  $('#variant').addEventListener('change', () => navigate(entry.key, $('#variant').value));
  $('#previous').onclick = () => {resultsPage--; search(); $('#results').scrollTop = 0;};
  $('#next').onclick = () => {resultsPage++; search(); $('#results').scrollTop = 0;};
  window.addEventListener('popstate', load);
  load();
}
