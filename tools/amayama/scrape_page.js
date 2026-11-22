// Amayama EPC schema-group scraper. Run in the browser on a schema-group page, e.g.
// .../genuine-catalogs/epc/nissan-japan/180sx/krps13/6976-sr20det/engine/101
// Returns a JSON-serializable object and stashes it on window.__gv.
// Writes to catalogue/<make>/<model>/<frame>/<variant>/<category>/<group>/amayama.json
(async () => {
  const OPEN_END = { year: 1998, month: 12 }; // "..." => last production month of the 180SX
  const clean = s => (s || '').replace(/\s+/g, ' ').trim();

  const parseDate = s => {
    s = clean(s);
    if (s === '...' || s === '') return null;
    const m = s.match(/^(\d{2})\.(\d{4})$/);
    return m ? `${m[2]}-${m[1]}` : s;
  };
  const parsePeriod = raw => {
    raw = clean(raw);
    if (!raw) return null;
    const [a, b] = raw.split(/\s+-\s+/);
    const to = b === '...' ? `${OPEN_END.year}-${String(OPEN_END.month).padStart(2, '0')}` : parseDate(b);
    return { from: parseDate(a), to, raw };
  };
  // "Applies: SR20DET Note: xyz" -> {applies: "SR20DET", note: "xyz"}
  const parseDetails = raw => {
    raw = clean(raw);
    const out = {};
    const re = /([A-Za-z][A-Za-z .\/]*?):\s*(.*?)(?=\s+[A-Z][A-Za-z .\/]*?:\s|$)/g;
    let m;
    while ((m = re.exec(raw))) out[m[1].trim().toLowerCase().replace(/\s+/g, '_')] = m[2].trim();
    return out;
  };
  const splitList = s => (s ? s.split(/\s*[;,]\s*/).filter(Boolean) : []);
  const parsePrice = raw => {
    raw = clean(raw);
    const n = raw.replace(/,/g, '');
    if (/^\d+(\.\d+)?$/.test(n)) return { status: 'Available', amount: Number(n), currency: 'USD', raw };
    return { status: raw || null, amount: null, currency: 'USD', raw };
  };

  // ---- page / vehicle ----
  const url = location.href.split('?')[0].split('#')[0];
  const path = url.split('/genuine-catalogs/epc/')[1].split('/'); // nissan-japan,180sx,krps13,6976-sr20det,engine,101
  const detailsText = clean(document.querySelector('.epcVariation__details')?.textContent);
  const field = k => (detailsText.match(new RegExp(k + ':\\s*(.*?)(?=\\s+[A-Z][a-z]+:|$)')) || [])[1] || null;
  const variantPeriod = (detailsText.match(/(\d{2}\.\d{4}\s+-\s+(?:\d{2}\.\d{4}|\.\.\.))/) || [])[1];
  const h1 = clean(document.querySelector('h1')?.textContent);

  const result = {
    format_version: 2,
    source: { site: 'amayama', url, scraped_at: new Date().toISOString() },
    vehicle: {
      make: 'Nissan',
      catalog: path[0],
      model: '180SX',
      frame: path[2].toUpperCase(),
      variant_id: path[3].split('-')[0],
      period: parsePeriod(variantPeriod),
      engine: field('Engine'),
      body: field('Body'),
      grade: field('Grade'),
      transmission: field('Transmission'),
      options: splitList(field('Options')),
    },
    group: {
      category: path[4],
      code: path[5],
      name: h1.split(/\s+for\s+/)[0].replace(/\s*\([^)]*\)\s*$/, ''),
      title_raw: h1,
    },
    images: {},
    schemas: [],
  };

  // ---- schemas ----
  for (const sc of document.querySelectorAll('.epcSchema__schema')) {
    const picId = sc.dataset.id; // e.g. 101B_001_0
    const img = sc.querySelector('img.imgMap');
    const src = new URL(img.getAttribute('src'), location.origin).href.split('?')[0];
    // image key = amayama/<path on the image server>; each source keeps its own folder under _images/
    const file = 'amayama/' + new URL(src).pathname.replace(/^\/+/, ''); // -> catalogue/<make>/_images/amayama/imgjp16/RS13/101B_001.png
    const natW = img.naturalWidth, natH = img.naturalHeight;
    const scale = natW / img.width; // area coords are in rendered pixels
    result.images[file] = { url: src, width: natW, height: natH };

    const desc = clean(sc.querySelector('.img__description')?.textContent); // Schema 1 / 2 Applies: X; Period: a - b
    const idx = desc.match(/Schema\s+(\d+)\s*\/\s*(\d+)/) || [];
    const applies = (desc.match(/Applies:\s*(.*?)(?:;|$)/) || [])[1];
    const period = (desc.match(/Period:\s*(.*)$/) || [])[1];

    // hotspots grouped by PNC
    // hotspots grouped by PNC; areas that link to another schema group (e.g. "110" on the gasket-kit
    // diagram -> engine/110) go to `links` instead of callouts
    const hotspots = {};
    const linkMap = {};
    for (const a of sc.querySelectorAll('area')) {
      const pnc = a.dataset.key.slice(picId.length + 1);
      const [x1, y1, x2, y2] = a.coords.split(',').map(Number).map(v => Math.round(v * scale));
      const hrefPath = a.getAttribute('href') ? new URL(a.getAttribute('href'), location.origin).pathname : '';
      const target = hrefPath.split('/genuine-catalogs/epc/')[1]?.split('/');
      if (target && target.length >= 6) {
        const link = (linkMap[pnc] = linkMap[pnc] || {
          code: pnc, title: a.title || null, category: target[4], group: target[5],
          variant_id: target[3].split('-')[0], url: location.origin + hrefPath, hotspots: [] });
        link.hotspots.push({ shape: a.getAttribute('shape') || 'rect', rect: { x1, y1, x2, y2 },
          norm: { x1: +(x1 / natW).toFixed(4), y1: +(y1 / natH).toFixed(4), x2: +(x2 / natW).toFixed(4), y2: +(y2 / natH).toFixed(4) } });
        continue;
      }
      (hotspots[pnc] = hotspots[pnc] || []).push({
        shape: a.getAttribute('shape') || 'rect',
        rect: { x1, y1, x2, y2 },
        norm: { x1: +(x1 / natW).toFixed(4), y1: +(y1 / natH).toFixed(4), x2: +(x2 / natW).toFixed(4), y2: +(y2 / natH).toFixed(4) },
        title: a.title || null,
      });
    }

    // part table: a tbody per PNC group (header row + part rows)
    const callouts = [];
    for (const tb of sc.querySelectorAll('tbody')) {
      // only tbodies that directly hold a PNC group header (skip index + nested detail tables)
      const header = tb.querySelector(':scope > tr > .entriesPncTable__groupHeader');
      if (!header) {
        // "Common parts" (bolts, clips…): a header-less tbody, one row per part keyed <picId>-<part key>.
        // Each becomes its own callout (kind "common") so its diagram label still selects it.
        let lastCommon = null;
        for (const r of tb.querySelectorAll(':scope > tr[data-key]')) {
          const num = r.querySelector(':scope > .entriesTable__number');
          if (!num) continue;
          const oem = clean(num.textContent);
          const link = num.querySelector('a')?.href?.split('?')[0] || null;
          const descRaw = clean(r.querySelector(':scope > .entriesTable__description')?.textContent);
          const price = parsePrice(r.querySelector(':scope > .entriesTable__price')?.textContent);
          if (descRaw === 'Replacement' && lastCommon) { lastCommon.replacements.push({ oem, url: link, price }); continue; }
          const pnc = r.dataset.key.slice(picId.length + 1);
          if (linkMap[pnc]) continue; // a row in the "Subschemes" list, already stored as a link
          const qtyRaw = clean(r.querySelector(':scope > .entriesTable__required')?.textContent);
          lastCommon = { oem, url: link, applies: [], details: {}, period: parsePeriod(r.querySelector(':scope > .entriesTable__period')?.textContent),
            qty: qtyRaw ? parseInt(qtyRaw, 10) : null, qty_raw: qtyRaw || null, price, replacements: [], description_raw: descRaw };
          const existing = callouts.find(c => c.pnc === pnc);
          if (existing) existing.parts.push(lastCommon);
          else callouts.push({ pnc, kind: 'common', name: descRaw, hotspots: hotspots[pnc] || [], parts: [lastCommon] });
        }
        continue;
      }
      const headerText = clean(header.textContent); // "10102 - ENGINE ASSEMBLY, BEAR"
      if (/^(subschemes|common parts)$/i.test(headerText)) continue; // section labels, not callouts
      const firstRow = tb.querySelector('tr[data-pnc]');
      const pnc = firstRow?.dataset.pnc || headerText.split(/\s+-\s+/)[0];
      const callout = {
        pnc,
        kind: 'pnc',
        name: headerText.split(/\s+-\s+/).slice(1).join(' - '),
        hotspots: hotspots[pnc] || [],
        parts: [],
      };
      let last = null;
      for (const r of tb.querySelectorAll(':scope > tr')) {
        const num = r.querySelector(':scope > .entriesTable__number');
        if (!num) continue;
        const oem = clean(num.textContent);
        const link = num.querySelector('a')?.href?.split('?')[0] || null;
        const descRaw = clean(r.querySelector('.entriesTable__description')?.textContent);
        const price = parsePrice(r.querySelector('.entriesTable__price')?.textContent);
        if (descRaw === 'Replacement') {
          if (last) last.replacements.push({ oem, url: link, price });
          continue;
        }
        const details = parseDetails(descRaw);
        const qtyRaw = clean(r.querySelector('.entriesTable__required')?.textContent);
        last = {
          oem,
          url: link,
          applies: splitList(details.applies),
          details,
          period: parsePeriod(r.querySelector('.entriesTable__period')?.textContent),
          qty: qtyRaw ? parseInt(qtyRaw, 10) : null,
          qty_raw: qtyRaw || null,
          price,
          replacements: [],
          description_raw: descRaw,
        };
        callout.parts.push(last);
      }
      callouts.push(callout);
    }
    // hotspots with no table group (rare) still kept
    for (const pnc of Object.keys(hotspots)) {
      if (!callouts.find(c => c.pnc === pnc)) callouts.push({ pnc, name: hotspots[pnc][0].title, hotspots: hotspots[pnc], parts: [] });
    }

    result.schemas.push({
      id: picId,
      index: Number(idx[1]) || result.schemas.length + 1,
      of: Number(idx[2]) || null,
      applies: splitList(applies),
      period: parsePeriod(period),
      image: file,
      callouts,
      links: Object.values(linkMap),
    });
  }

  window.__gv = result;
  return result;
})();
