# Catalogue layout (format v2)

Parts and diagrams are shared across frames and models (e.g. `10102-50FR2` is on both KRPS13 and RPS13 pages,
and both frames use diagrams under `imgjp16/RS13/`), so they live once at the **make** level. Everything else
references them by key.

```
catalogue/
  <make>/                                   nissan
    _images/<path on image server>          _images/imgjp16/RS13/101B_001.png
    _parts/<key[0..2]>/<key>.json           _parts/10/1010250FR2.json
    <model>/<frame>/                        180sx/KRPS13/
      <variant>/                            6976_1994-1998_TYPE-RX_MT_4WS/
        <category>/<group>/                 engine/101_Bearing-and-short-engine-assembly/
          schema-group.json
```

- **Folders starting with `_`** are shared stores, not models. The app skips them when it builds the tree.
- **Part key** = OEM number uppercased with everything except letters and digits removed
  (`10102-50FR2` → `1010250FR2`). Files go in subfolders named after the key's first 2 characters, so no
  single folder ends up holding thousands of files.
- **Image key** = the path on Amayama's image server (`imgjp16/RS13/101B_001.png`). A schema's `image`
  field holds this key. If an image is already present, it's never downloaded again.

## Files

| File | Written by | Holds | Changes |
|---|---|---|---|
| `schema-group.json` | `tools/amayama/scrape_page.js` | schemas, callouts + hotspots, OEM parts per variant | rarely |
| `_parts/../<key>.json` | `tools/amayama/scrape_part.js` | name, weight, offers, notices, fitment, every Amayama page listing the part | offers often (`source.scraped_at`) |
| `_images/...` | browser download | diagram PNGs | never |

Dates written as `...` on the site are stored as `1998-12` (end of 180SX production); the original text is kept in `raw`.
Status wording such as "Discontinued" or "Not available" is kept exactly as the site shows it.
