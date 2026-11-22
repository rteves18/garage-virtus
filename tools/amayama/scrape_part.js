// Amayama part-page scraper. Run in the browser on any amayama.com page:
//   await window.__gvScrapePart('1010250fr2')
// Fetches /en/part/nissan/<slug> and /en/part/nissan/<slug>/diagrams (no navigation needed)
// and returns the JSON stored at catalogue/<make>/_parts/<key[0..1]>/<key>/amayama.json
window.__gvScrapePart = async (slug, make = 'nissan') => {
  const clean = s => (s || '').replace(/\s+/g, ' ').trim();
  const parse = html => new DOMParser().parseFromString(html, 'text/html');
  const normalize = s => clean(s).toUpperCase().replace(/[^A-Z0-9]/g, '');
  const num = s => { const n = clean(s).replace(/,/g, ''); return /^\d+(\.\d+)?$/.test(n) ? Number(n) : null; };
  const hidden = e => /display\s*:\s*none/i.test(e?.getAttribute('style') || '');

  const base = `${location.origin}/en/part/${make}/${slug.toLowerCase()}`;
  const [pageRes, diagRes] = await Promise.all([fetch(base, { credentials: 'include' }), fetch(base + '/diagrams', { credentials: 'include' })]);
  if (!pageRes.ok) throw new Error(`part page ${pageRes.status}`);
  const d = parse(await pageRes.text());
  const dd = diagRes.ok ? parse(await diagRes.text()) : null;
  const t = sel => clean(d.querySelector(sel)?.textContent);

  // ---- identity ----
  const oem = t('.part-page__number') || slug.toUpperCase();
  const brandLine = t('.part-page__name h2'); // "Genuine Nissan (1010250FR2)"
  const weightRaw = t('.part-page__weight').replace(/^Weight\s*/i, '');
  const wm = weightRaw.match(/([\d.,]+)\s*(kg|g)\b/i);
  const weightKg = wm ? Number(wm[1].replace(',', '.')) / (wm[2].toLowerCase() === 'g' ? 1000 : 1) : null;

  // ---- tables: [0] offers, [1] substitutes ("Original Number"), [2] aftermarket ("Brand / From") ----
  const tables = [...d.querySelectorAll('table.part-table')];
  const currency = (clean(tables[0]?.querySelector('tr')?.textContent).match(/Price,\s*([A-Z]{3})/) || [])[1] || 'USD';
  const rowsOf = tb => tb ? [...tb.querySelectorAll('tbody tr')].map(r => [...r.children].map(c => clean(c.textContent))) : [];

  const offers = rowsOf(tables[0]).map(c => ({
    from: c[0] || null,
    price: num(c[1]),
    price_raw: c[1] || null,
    currency,
    shipping_raw: c[2] && c[2] !== '?' ? c[2] : null,
    delivery_raw: c[3] || null,
    availability: c[4] || null,
  }));
  const tableRows = tb => rowsOf(tb).map(cells => ({ cells: cells.filter(Boolean) }));

  // ---- notices (visible warning plates only) ----
  const notices = [...d.querySelectorAll('.warning-plate')]
    .filter(e => !hidden(e))
    .map(e => ({ kind: [...e.classList].find(c => c.startsWith('part-page__'))?.replace('part-page__', '') || 'notice', text: clean(e.textContent) }))
    .filter(n => n.text);

  // ---- "may fit to" ----
  const fits = {};
  for (const row of d.querySelectorAll('.fitness__row')) {
    const k = clean(row.querySelector('.fitness__row-name')?.textContent);
    const v = clean(row.querySelector('.fitness__row-content')?.textContent);
    if (k && v && !/vin/i.test(k)) fits[k.toLowerCase()] = v;
  }

  // ---- gallery photos (URLs only; the diagram crop is skipped, we have the full diagram) ----
  const photos = [...d.querySelectorAll('.part-page__gallery img')]
    .map(i => i.getAttribute('src') || '')
    .filter(src => src && !/\/schema\//.test(src))
    .map(src => new URL(src, location.origin).href.split('?')[0]);

  // ---- every catalogue page this part appears on (across frames/models) ----
  const diagrams = [];
  const seen = new Set();
  for (const a of dd ? dd.querySelectorAll('a[href*="/genuine-catalogs/epc/"]') : []) {
    const href = new URL(a.getAttribute('href'), location.origin);
    const p = href.pathname.split('/genuine-catalogs/epc/')[1]?.split('/') || [];
    if (p.length < 6 || seen.has(href.pathname)) continue;
    seen.add(href.pathname);
    diagrams.push({
      catalog: p[0], model: p[1], frame: p[2].toUpperCase(),
      variant_id: p[3].split('-')[0], category: p[4], group: p[5],
      url: href.origin + href.pathname,
    });
  }

  return {
    format_version: 1,
    source: { site: 'amayama', url: base, scraped_at: new Date().toISOString() },
    make,
    oem,
    key: normalize(oem),
    name: t('.part-page__name h1'),
    brand: brandLine.replace(/\s*\(.*\)\s*$/, '') || null,
    catalog_name: t('.part-page__catalog-name .info-hint-new') || null,
    weight: { kg: weightKg, raw: weightRaw || null },
    offers,
    substitutes: tableRows(tables[1]),
    aftermarket: tableRows(tables[2]),
    notices,
    fits,
    photos,
    diagrams,
  };
};
