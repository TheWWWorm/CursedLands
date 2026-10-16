import {mountConstructor} from './constructors.mjs';
const $ = selector => document.querySelector(selector);
const SUPPORTED = ['en', 'ru', 'de'];
const CAMPAIGNS = ['cursed_lands', 'lost_in_astral'];
const ITEM_TYPES = {
  weapon_sword: ['weapons', 'swords'], weapon_axe: ['weapons', 'axes'], weapon_dagger: ['weapons', 'daggers'],
  weapon_spear: ['weapons', 'spears'], weapon_hammer: ['weapons', 'hammers'], weapon_bow: ['weapons', 'bows'], weapon_crossbow: ['weapons', 'crossbows'],
  armor_helm: ['armour', 'helmets'], armor_plate: ['armour', 'chestArmour'], armor_leggings: ['armour', 'leggings'], armor_leggins: ['armour', 'leggings'],
  armor_shirt: ['armour', 'shirts'], armor_pants: ['armour', 'trousers'], armor_gloves: ['armour', 'gloves'], armor_boots: ['armour', 'boots'],
  quest: ['otherItems', 'questItems'], wand: ['otherItems', 'wands'], potion: ['otherItems', 'potions'], loot: ['otherItems', 'loot'], other: ['otherItems', 'otherItems']
};
const ALLOWED = new Set(['ARTICLE', 'H1', 'H2', 'H3', 'P', 'BR', 'TABLE', 'TBODY', 'TR', 'TH', 'TD', 'A', 'STRONG', 'EM']);
let lang = 'en', campaign = 'cursed_lands', strings, catalog, entry, page, constructors, generation = 0;
const indexes = new Map(), pages = new Map();

function route() {
  const params = new URLSearchParams(location.search);
  const requested = params.get('lang') || navigator.language.slice(0, 2);
  return {lang: SUPPORTED.includes(requested) ? requested : 'en',
    campaign: CAMPAIGNS.includes(params.get('campaign')) ? params.get('campaign') : 'cursed_lands',
    key: params.get('page') || 'home', variant: params.get('version') || '',
    spell:params.get('spell') || '', runes:params.has('runes') ? params.get('runes').split(';').filter(Boolean) : null};
}

function href(key, variant = '', language = lang, game = campaign) {
  const params = new URLSearchParams({lang: language, page: key});
  if (game !== 'cursed_lands') params.set('campaign', game);
  if (variant) params.set('version', variant);
  return '/wiki/?' + params;
}

function navigate(key, variant = '', language = lang) {
  const url = new URL(href(key, variant, language),location.origin);
  if (key === route().key) {
    const current = new URLSearchParams(location.search);
    for (const name of ['spell','runes']) if (current.has(name)) url.searchParams.set(name,current.get(name));
  }
  if (location.href !== url.href) history.pushState(null, '', url);
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
  $('#campaigns').ariaLabel = strings.campaign;
  for (const tab of document.querySelectorAll('[data-campaign]')) {
    tab.href = href('home', '', lang, tab.dataset.campaign);
    if (tab.dataset.campaign === campaign) tab.setAttribute('aria-current', 'page');
    else tab.removeAttribute('aria-current');
  }
  $('.eyebrow').textContent = campaign === 'lost_in_astral' ? strings.astralEdition : strings.edition;
  $('footer p').textContent = campaign === 'lost_in_astral' ? strings.astralSource : strings.source;
}

function search(resetScroll = false) {
  if (!catalog) return;
  const words = $('#search').value.trim().toLocaleLowerCase(lang).split(/\s+/).filter(Boolean);
  const category = $('#category').value;
  const itemType = $('#item-category').value;
  $('#item-filters').hidden = category !== 'Items';
  const found = catalog.entries.filter(row => {
    // Keep linked rune combinations available as articles without listing
    // every equipped variant alongside the base spell. The key check also
    // supports older indexes during a rolling website deployment.
    if (row.listed === false || (row.kind === 'spell' && decodeURIComponent(row.key).includes('{'))) return false;
    const typeLabel = row.subcategory ? strings[ITEM_TYPES[row.subcategory]?.[1] || 'otherItems'] : '';
    const text = (row.title + ' ' + (row.search || '') + ' ' + catalog.categories[row.category] + ' ' + typeLabel).toLocaleLowerCase(lang);
    return (category === 'All pages' || row.category === category) &&
      (category !== 'Items' || !itemType || row.subcategory === itemType) && words.every(word => text.includes(word));
  });
  $('#status').textContent = found.length ? strings.matches.replace('{count}', found.length.toLocaleString(lang)) : strings.empty;
  const scroll = resetScroll ? 0 : $('#results').scrollTop;
  $('#results').replaceChildren(...found.map(row => {
    const a = document.createElement('a');
    a.href = href(row.key);
    a.textContent = row.title;
    if (entry?.key === row.key) a.setAttribute('aria-current', 'page');
    return a;
  }));
  $('#results').scrollTop = scroll;
}

function itemCategories() {
  const available = new Set(catalog.entries.filter(row => row.listed !== false).map(row => row.subcategory));
  const groups = new Map();
  $('#item-category').replaceChildren(new Option(strings.allItems, ''));
  for (const [id, [group, label]] of Object.entries(ITEM_TYPES)) {
    if (!available.has(id)) continue;
    if (!groups.has(group)) {
      const el = document.createElement('optgroup'); el.label = strings[group];
      groups.set(group, el); $('#item-category').append(el);
    }
    groups.get(group).append(new Option(strings[label], id));
  }
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
  if (id && id !== version.id) {
    const url = new URL(location.href); url.searchParams.set('version',version.id);
    history.replaceState(null, '', url);
  }
  $('#variant').value = version.id;
  const content = article(version.html);
  content.id = 'article'; content.tabIndex = -1;
  if (version.image) {
    const figure = document.createElement('figure'), img = document.createElement('img'), caption = document.createElement('figcaption');
    img.src = '/wiki/images/' + version.image + '.webp';
    img.alt = version.title; img.width = 280; img.height = 280;
    img.decoding = 'async';
    caption.textContent = entry.kind === 'map' ? strings.mapOverview : version.representative_image ? strings.imageRepresentative : strings.image;
    if (entry.kind === 'map') figure.classList.add('map-overview');
    figure.append(img, caption);
    content.querySelector('h1').after(figure);
  }
  $('#content').replaceChildren(content);
  $('#spell-note').hidden = true;
  if (constructors) mountConstructor($('#constructor'), {data:constructors,entry,version,strings,state:route(),onChange:state => {
    const url=new URL(location.href);
    for (const key of ['spell','runes']) url.searchParams.delete(key);
    if (entry.kind === 'item' && state.spell) url.searchParams.set('spell',state.spell);
    if (state.runes.length || (entry.kind === 'spell' && decodeURIComponent(entry.key).includes('{'))) url.searchParams.set('runes',state.runes.join(';'));
    history.replaceState(null,'',url);
  }});
  document.title = version.title + ' · Cursed Lands';
}

async function load() {
  const token = ++generation, target = route();
  lang = target.lang; campaign = target.campaign; strings = translations[lang];
  translate();
  $('#notice').textContent = strings.loading;
  $('#versions').hidden = true;
  $('#spell-note').hidden = true;
  $('#content').replaceChildren();
  $('#constructor').hidden = true;
  try {
    const directory = '/wiki/data/' + (campaign === 'lost_in_astral' ? campaign + '/' : '') + lang;
    const index = await json(directory + '/index.json', indexes);
    if (token !== generation) return;
    const changed = catalog !== index;
    catalog = index;
    if (changed) {
      $('#category').replaceChildren(...Object.entries(catalog.categories).map(([id, name]) => new Option(name, id)));
      itemCategories();
      $('#search').value = '';
    }
    $('#version').textContent = catalog.version;
    entry = catalog.entries.find(row => row.key === target.key);
    search(changed);
    if (!entry) {
      $('#notice').textContent = strings.unavailable;
      return;
    }
    const loaded = await json(directory + '/pages/' + entry.file, pages);
    if (token !== generation) return;
    page = loaded;
    constructors = await json(directory + '/constructors.json', pages);
    if (token !== generation) return;
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
      $('#search').value = ''; search(true); $('#search').focus();
    } else if (new URL(a.href).pathname === '/wiki/') {
      event.preventDefault(); history.pushState(null, '', a.href); load();
    }
  });
  $('#search').addEventListener('input', () => search(true));
  $('#category').addEventListener('change', () => search(true));
  $('#item-category').addEventListener('change', () => search(true));
  $('#language').addEventListener('change', () => navigate(route().key, route().variant, $('#language').value));
  $('#variant').addEventListener('change', () => navigate(entry.key, $('#variant').value));
  window.addEventListener('popstate', load);
  load();
}
