// Mirrors Spells.parse/constr_rune_fits and Items.can_enchant. Inputs are
// exported from the selected campaign's real builders, not copied databases.
export function buildSpell(data, code, runes = []) {
  const base = data.spells[code];
  if (!base || runes.length > data.max_runes) return null;
  const result = {...base, runes: [...runes]};
  for (const code of runes) {
    const r = data.runes[code];
    if (!r || (r.type < 5 && !base.allowed[r.type])) return null;
    const field = {a:'area', e:'effect', r:'range', m:'mana', d:'duration', t:'targets'}[code[0]];
    if (field) {
      let addition = r.value * base[field];
      if (field === 'duration' || field === 'targets') addition = Math.trunc(addition);
      result[field] += addition;
      if (field !== 'targets') result[field] = Math.max(0, result[field]);
    }
    if (code[0] === 'f') result.filter |= {e:2,f:1,g:8,h:4,l:32,o:16}[code[1]] || 0;
    if (code[0] === 'i') result.flags |= {c:0x20000,t:0x10000}[code[1]] || 0;
    result.mana += r.mana; result.complex += r.complex; result.price += r.price;
  }
  result.mana = Math.max(base.mana, result.mana);
  result.radius = result.area > 0 ? Math.sqrt(result.area / Math.PI) : 0;
  return result;
}

export function canEnchant(item, spell) {
  return !!item && !!spell && ['weapon','armor','quick'].includes(item.kind)
    && (item.kind === 'quick' || spell.runes.some(r => ['ic','it'].includes(r)))
    && Math.trunc(spell.complex) <= item.slots && spell.mana <= item.energy;
}

export function itemResult(item, spell = null) {
  if (!item || (spell && !canEnchant(item,spell))) return null;
  const price = Math.max(1, Math.trunc(item.raw_price + (spell?.price || 0)));
  return {...item, price, construction: Math.trunc(price * item.construction_coefficient)};
}

let selectedRune = '';
export function mountConstructor(host, {data, entry, version, strings, state, onChange}) {
  const isSpell = entry.kind === 'spell';
  const item = version.builder;
  const authored = isSpell ? decodeURIComponent(entry.key.slice(6)) : '';
  host.hidden = (isSpell && !data.spells[authored.split('{')[0]]) || (!isSpell && !item);
  host.replaceChildren();
  if (host.hidden) return;
  let code = isSpell ? authored.split('{')[0] : data.spells[state.spell] ? state.spell : '';
  let runes = state.runes ?? (authored.split('{')[1] || '').replace(/}$/, '').split(';').filter(Boolean);
  if (code && !buildSpell(data,code,runes)) runes = [];
  const el = (tag, text, cls) => {
    const node = document.createElement(tag);
    if (text) node.textContent = text;
    if (cls) node.className = cls;
    return node;
  };
  const number = value => new Intl.NumberFormat(document.documentElement.lang, {maximumFractionDigits:3}).format(value);
  const title = spell => spell.title + (spell.runes.length ? ' · ' + spell.runes.map(r => data.runes[r].title).join(', ') : '');
  const button = (label, action, disabled = false, id = '') => {
    const node = el('button',label); node.type = 'button'; node.disabled = disabled;
    if (id) node.id=id;
    node.addEventListener('click',action); return node;
  };
  const commit = () => {onChange({spell:code, runes:[...runes]}); render();};
  function render() {
    host.replaceChildren(el('h2',isSpell ? strings.spellConstructor : strings.itemConstructor));
    host.append(el('p',strings.previewOnly,'constructor-note'));
    if (!isSpell) {
      const label = el('label',strings.spellChoice);
      const select = el('select'); select.id = 'constructor-spell';
      select.append(new Option(strings.noSpell,''));
      for (const [id,spell] of Object.entries(data.spells)) select.append(new Option(spell.title,id));
      select.value = code;
      select.addEventListener('change',() => {code=select.value; runes=[]; commit();});
      label.append(select); host.append(label);
    }
    const spell = code ? buildSpell(data,code,runes) : null;
    if (spell) {
      const controls = el('div','','constructor-controls');
      const label = el('label',strings.runeChoice);
      const select = el('select'); select.id = 'constructor-rune';
      for (const [id,rune] of Object.entries(data.runes)) {
        if (buildSpell(data,code,[...runes,id])) select.append(new Option(rune.title,id));
      }
      if ([...select.options].some(o => o.value === selectedRune)) select.value = selectedRune;
      selectedRune = select.value;
      const art = el('img','','rune-art'); art.width=80; art.height=80;
      const updateArt = () => {
        selectedRune=select.value;
        const rune=data.runes[selectedRune]; art.hidden=!rune?.image;
        if (rune?.image) {art.src='/wiki/images/'+rune.image+'.webp'; art.alt=rune.title;}
      };
      select.addEventListener('change',updateArt); updateArt();
      select.disabled=!select.options.length;
      if (!select.options.length) select.append(new Option(strings.noRunes,''));
      label.append(select); controls.append(label,art);
      controls.append(button(strings.addRune,() => {runes.push(select.value); commit();},select.disabled,'constructor-add-rune'));
      controls.append(button(strings.removeRune,() => {runes.pop(); commit();},!runes.length,'constructor-remove-rune'));
      controls.append(button(strings.resetSpell,() => {runes=[]; commit();},!runes.length,'constructor-reset'));
      host.append(controls,el('p',title(spell),'constructed-title'));
    }
    const rows = [];
    if (item) {
      const result = itemResult(item,spell);
      host.append(el('p',result ? strings.validItem : strings.invalidItem,result ? 'constructor-valid' : 'constructor-error'));
      for (const [key,label] of [['weight','weightLabel'],['slots','slotsLabel'],['energy','energyLabel'],['components','componentsLabel']]) rows.push([strings[label],item[key]]);
      if (result) rows.push([strings.priceLabel,result.price],[strings.constructionLabel,result.construction]);
    }
    if (spell) for (const [key,label] of [['effect','powerLabel'],['mana','manaLabel'],['complex','complexityLabel'],['range','rangeLabel'],['area','areaLabel'],['radius','radiusLabel'],['duration','durationLabel'],['targets','targetsLabel'],['price','spellPriceLabel']]) rows.push([strings[label],spell[key]]);
    const table=el('table'); table.id='constructor-values';
    const head=el('tr'); head.append(el('th',strings.propertyLabel),el('th',strings.valueLabel)); table.append(head);
    for (const [label,value] of rows) {const row=el('tr'); row.append(el('td',label),el('td',number(value))); table.append(row);}
    host.append(table);
    host.dataset.runeCount=String(runes.length);
    host.dataset.valid=String(!item || !!itemResult(item,spell));
  }
  render();
}
