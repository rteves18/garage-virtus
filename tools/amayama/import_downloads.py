#!/usr/bin/env python3
"""Import Amayama files from ~/Downloads into catalogue/ (one file per source; never touches other sources).

  gv_<variant>_<category>_<group>.json   -> catalogue/nissan/180sx/<FRAME>/<variant folder>/<category>/<group folder>/amayama.json
  gvimg__amayama__a__b__c.png            -> catalogue/nissan/_images/amayama/a/b/c.png
  gvpart_<KEY>.json                      -> catalogue/nissan/_parts/<KEY[:2]>/<KEY>/amayama.json
  gvbundle_*.json   {"groups": [...]}    -> one amayama.json per group (one download for a whole batch)
  gvimages_*.json   {"images": {key: base64 png}} -> catalogue/nissan/_images/<key>

Safety rules:
  * Only files named amayama.json (and _images/amayama/...) are ever written.
  * An existing amayama.json is replaced only by a newer scrape, and only if it really is Amayama data.
  * Chrome renames repeat downloads "name (1).json"; the newest copy of each wins.
Afterwards every amayama.json is validated.

usage: import_downloads.py <downloads dir> <catalogue dir>
"""
import json
import re
import shutil
import sys
from pathlib import Path

SOURCE = "amayama"
downloads, catalogue = Path(sys.argv[1]), Path(sys.argv[2])
make = catalogue / "nissan"
report = {"groups": [], "images": [], "parts": [], "skipped": [], "problems": []}


def newest(pattern):
    best = {}
    for f in downloads.glob(pattern):
        k = re.sub(r" \(\d+\)(?=\.\w+$)", "", f.name)
        if k not in best or f.stat().st_mtime > best[k].stat().st_mtime:
            best[k] = f
    return best


def safe_write(src: Path, dst: Path, data: dict | None = None):
    assert dst.name == f"{SOURCE}.json" or SOURCE in dst.parts, f"refusing to write {dst}"
    if dst.exists() and data is not None:
        old = json.loads(dst.read_text())
        if old.get("source", {}).get("site") != SOURCE:
            report["problems"].append(f"{dst}: exists but isn't {SOURCE} data — left alone")
            return False
        if old.get("source", {}).get("scraped_at", "") >= data["source"]["scraped_at"]:
            report["skipped"].append(dst.parent.name)
            return False
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    dst.chmod(0o644)
    return True


import base64
import tempfile

# Bundles (one download per batch) are unpacked into the same single-file shapes handled below.
staging = Path(tempfile.mkdtemp(prefix="gv_import_"))
pending = {}  # group name -> (path, data)
for name, f in sorted(newest("gvbundle_*.json").items()):
    bundle = json.loads(f.read_text())
    for g in bundle.get("groups", []):
        gname = f"gv_{g['vehicle']['variant_id']}_{g['group']['category']}_{g['group']['code']}.json"
        tmp = staging / gname
        tmp.write_text(json.dumps(g, indent=2, ensure_ascii=False))
        pending[gname] = tmp
bundled_images = {}  # real image key -> decoded file (keys can contain "__", e.g. A52__001.png, so no name encoding)
for name, f in sorted(newest("gvimages_*.json").items()):
    for key, b64 in json.loads(f.read_text()).get("images", {}).items():
        tmp = staging / f"img_{len(bundled_images):05d}.png"
        tmp.write_bytes(base64.b64decode(b64))
        bundled_images[key] = tmp

singles = {**newest("gv_*.json")}
for gname, tmp in pending.items():
    if gname.startswith("gv_"):
        singles[gname] = tmp  # a bundled copy beats a stray single download of the same group

# ---- schema groups ----
for name, f in sorted(singles.items()):
    m = re.match(r"gv_(\d+)_(\w+?)_(\w+)\.json$", name)
    if not m:
        continue
    variant, category, code = m.groups()
    data = json.loads(f.read_text())
    if data.get("source", {}).get("site") != SOURCE:
        report["problems"].append(f"{name}: not {SOURCE} data")
        continue
    if not all(s["image"].startswith(SOURCE + "/") for s in data["schemas"]):
        report["problems"].append(f"{name}: old image keys (re-read the tab with the current reader)")
        continue
    frame = data["vehicle"]["frame"]
    vdirs = sorted(d for d in (make / "180sx" / frame).glob(f"{variant}_*") if d.is_dir())
    if not vdirs:
        report["problems"].append(f"{name}: no variant folder {frame}/{variant}_*")
        continue
    gdirs = sorted(d for d in (vdirs[0] / category).glob(f"{code}_*") if d.is_dir())
    gdir = gdirs[0] if gdirs else vdirs[0] / category / f"{code}_{re.sub(r'[^A-Za-z0-9]+', '-', data['group']['name']).strip('-').capitalize()}"
    if safe_write(f, gdir / f"{SOURCE}.json", data):
        report["groups"].append(f"{category}/{code}")

# ---- images ----
images = {name[len("gvimg__"):].replace("__", "/"): f for name, f in newest("gvimg__*.png").items()}  # legacy single files
images.update(bundled_images)
for rel, f in sorted(images.items()):
    name = rel
    if not rel.startswith(SOURCE + "/"):
        report["problems"].append(f"{name}: not an {SOURCE} image name")
        continue
    dst = make / "_images" / rel
    if not dst.exists() or dst.stat().st_size != f.stat().st_size:
        safe_write(f, dst)
        report["images"].append(rel)

# ---- part pages ----
for name, f in sorted(newest("gvpart_*.json").items()):
    key = name[len("gvpart_"):-len(".json")]
    data = json.loads(f.read_text())
    if safe_write(f, make / "_parts" / key[:2] / key / f"{SOURCE}.json", data):
        report["parts"].append(key)

# ---- trim hotspots to the image (rendered-pixel rounding can overshoot an edge by 1px) ----
for sg in sorted(make.glob(f"*/*/*/*/*/{SOURCE}.json")):
    d = json.loads(sg.read_text())
    changed = False
    for s in d["schemas"]:
        info = d["images"].get(s["image"])
        if not info:
            continue
        w, h = info["width"], info["height"]
        for c in s["callouts"] + s.get("links", []):
            for hs in c["hotspots"]:
                r, n = hs["rect"], hs["norm"]
                fixed = {"x1": max(0, r["x1"]), "y1": max(0, r["y1"]), "x2": min(w, r["x2"]), "y2": min(h, r["y2"])}
                if fixed != r:
                    hs["rect"] = fixed
                    hs["norm"] = {"x1": round(fixed["x1"] / w, 4), "y1": round(fixed["y1"] / h, 4),
                                  "x2": round(fixed["x2"] / w, 4), "y2": round(fixed["y2"] / h, 4)}
                    changed = True
    if changed:
        sg.write_text(json.dumps(d, indent=2, ensure_ascii=False))
        print(f"trimmed hotspots to image edges: {'/'.join(sg.parts[-3:-1])}")

# ---- validate every amayama.json ----
totals = {"groups": 0, "schemas": 0, "callouts": 0, "parts": 0, "links": 0}
for sg in sorted(make.glob(f"*/*/*/*/*/{SOURCE}.json")):
    d = json.loads(sg.read_text())
    where = "/".join(sg.parts[-3:-1])
    totals["groups"] += 1
    for s in d["schemas"]:
        totals["schemas"] += 1
        totals["links"] += len(s.get("links", []))
        info = d["images"].get(s["image"], {})
        if not (make / "_images" / s["image"]).exists():
            report["problems"].append(f"{where} {s['id']}: missing image {s['image']}")
        for c in s["callouts"]:
            totals["callouts"] += 1
            totals["parts"] += len(c["parts"])
            if not c["parts"]:
                report["problems"].append(f"{where} {s['id']}/{c['pnc']}: no parts")
            for h in c["hotspots"]:
                r = h["rect"]
                if info and not (0 <= r["x1"] < r["x2"] <= info["width"] and 0 <= r["y1"] < r["y2"] <= info["height"]):
                    report["problems"].append(f"{where} {s['id']}/{c['pnc']}: hotspot outside image")

print(f"imported groups ({len(report['groups'])}): {', '.join(report['groups']) or '-'}")
print(f"imported images ({len(report['images'])}): {', '.join(report['images']) or '-'}")
if report["parts"]:
    print(f"imported part pages ({len(report['parts'])}): {', '.join(report['parts'])}")
if report["skipped"]:
    print(f"skipped (already newer): {', '.join(report['skipped'])}")
print(f"{SOURCE} totals:", totals)
print("problems:", "\n  ".join([""] + report["problems"]) if report["problems"] else "none")
