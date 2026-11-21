#!/usr/bin/env python3
"""Convert a Megazip (partsbooster EPC) scrape into Garage Virtus's Amayama-format catalogue.

Input:  a partsCollect output folder (catalog.json + images/), e.g.
        ~/Documents/dev/partsCollect/out/nissan-180sx-krps13-hb-sr20det-mt-typer_x-4ws
Output: catalogue/<make>/<model>/<frame>/<variant>/<category>/<code>_<Name>/schema-group.json
        catalogue/<make>/_parts/<key[:2]>/<key>.json
        catalogue/<make>/_images/megazip/<series>/<code>_<NNN>.png

Amayama data wins: groups go into Amayama's existing folder for their code (its name and category), a group that
already has an Amayama schema-group.json is left alone, and so are part pages already scraped from Amayama. Files this script wrote earlier (source.site == "megazip") are overwritten, so it can be rerun.

Usage:
    python3 -I tools/megazip/convert_to_catalogue.py SOURCE_DIR \
        --catalogue catalogue --variant 6976_1994-1998_TYPE-RX_MT_4WS [--dry-run]
"""

import argparse
import json
import re
import shutil
import sys
from collections import Counter
from pathlib import Path

SITE = "megazip"
CATALOG = "nissan-japan"  # Amayama's catalog id for Japan-market Nissans
AMAYAMA = "https://www.amayama.com/en"
MAKE = "nissan"
MODEL_FOLDER = "180sx"
OPEN_END = "1998-12"  # "08.1996-" (still in production) -> last month of 180SX production, as in the Amayama data

CATEGORY_BY_CHAPTER = {
    "Engine, Fuel": "engine",
    "Body, Trim": "body",
    "Chasis, Power Train, Brake": "trans",
    "Electrical": "electric",
    "Accessory": "misc",
}


def part_key(number):
    """'10102-50FR2' -> '1010250FR2' (same rule as CatalogueStore.normalize)."""
    return re.sub(r"[^A-Za-z0-9]", "", number).upper()


def month(text):
    """'01.1994' -> '1994-01'; '' -> None."""
    text = (text or "").strip()
    match = re.fullmatch(r"(\d{2})\.(\d{4})", text)
    return f"{match.group(2)}-{match.group(1)}" if match else (text or None)


def period(text):
    """'[01.1994-08.1996]' / '08.1996-' -> {'from', 'to', 'raw'}; None for empty."""
    raw = (text or "").strip()
    inner = raw.strip("[]").strip()
    if not inner:
        return None
    start, _, end = inner.partition("-")
    start, end = start.strip(), end.strip()
    return {"from": month(start), "to": month(end) or OPEN_END, "raw": f"{start} - {end or '...'}"}


def labelled_fields(text):
    """'Specification: X; App. model: MT +AT' -> {'specification': 'X', 'app_model': 'MT +AT'}."""
    fields = {}
    for piece in (text or "").split(";"):
        title, sep, value = piece.partition(":")
        if sep:
            fields[re.sub(r"[^a-z0-9]+", "_", title.strip().lower()).strip("_")] = value.strip()
    return fields


def applies_list(app_model):
    """'SR20DE +SR20DET' -> ['SR20DE', 'SR20DET']."""
    return [token.strip() for token in (app_model or "").split("+") if token.strip()]


def folder_name(code, name):
    """('112', 'Fan,Compressor & Power Steering Belt') -> '112_Fan-Compressor-and-Power-Steering-Belt'."""
    words = re.sub(r"[^A-Za-z0-9]+", " ", name.replace("&", " and ")).split()
    return f"{code}_{'-'.join(words) or 'Group'}"


def price_of(part):
    if part and part.get("available") and part.get("price") is not None:
        amount = round(float(part["price"]), 2)
        return {"status": "Available", "amount": amount, "currency": "USD", "raw": f"{amount:,.2f}"}
    return {"status": "Not available", "amount": None, "currency": "USD", "raw": None}


def superseded_by(part):
    return [entry["partUid"] for group in (part or {}).get("supersededBy", []) for entry in group.get("parts", [])]


def is_amayama(path):
    try:
        return json.loads(path.read_text())["source"]["site"] != SITE
    except (OSError, ValueError, KeyError, TypeError):
        return True  # unreadable or unknown: don't touch it


class Converter:
    def __init__(self, source, catalogue, variant, is_dry_run):
        self.source = source
        self.catalogue = catalogue
        self.variant = variant
        self.is_dry_run = is_dry_run
        self.data = json.loads((source / "catalog.json").read_text())
        self.parts = self.data["parts"]
        self.diagrams = {d["uid"]: d for d in self.data["diagrams"]}
        self.make_dir = catalogue / MAKE
        self.variant_dir = self.make_dir / MODEL_FOLDER / self.data["vehicle"]["variant"] / variant
        self.variant_id = variant.split("_", 1)[0]
        self.series = self.data["vehicle"]["params"].get("Series", "images")
        self.image_keys = {}  # Megazip image file -> our key, named after the first group and sheet that uses it
        self.stats = Counter()
        self.group_of_diagram = {}  # diagram uid -> (category, section code)

    # MARK: shared pieces

    def vehicle(self):
        params = self.data["vehicle"]["params"]
        production = params.get("Production Dates", "")
        start = re.search(r"(\w{3}) (\d{4})", production)
        months = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
        start_month = f"{start.group(2)}-{months.index(start.group(1)) + 1:02d}" if start else None
        return {
            "make": "Nissan",
            "catalog": CATALOG,
            "model": "180SX",
            "frame": self.data["vehicle"]["variant"],
            "variant_id": self.variant_id,
            "period": {"from": start_month, "to": OPEN_END, "raw": production} if production else None,
            "engine": params.get("Engine"),
            "body": params.get("Body"),
            "grade": params.get("Grade"),
            "transmission": params.get("Trans"),
            "options": [params["Susp"]] if params.get("Susp") else [],
        }

    def period_text(self):
        """'01.1994 - ...' like Amayama's titles."""
        start = (self.vehicle().get("period") or {}).get("from")
        return f"{start[5:]}.{start[:4]} - ..." if start else "..."

    def source_block(self):
        return {"site": SITE, "url": self.data["source"], "scraped_at": self.data.get("scrapedAt")}

    def image_key(self, diagram, code, number):
        """'megazip/RS13/110_001.png': same layout as Amayama's 'imgjp16/RS13/101B_001.png'."""
        file = diagram["image"]["file"]
        if file not in self.image_keys:
            self.image_keys[file] = f"megazip/{self.series}/{code}_{number:03d}.png"
        return self.image_keys[file]

    def group_url(self, category, code):
        """Amayama's page for this group, e.g. .../180sx/krps13/6976-sr20det/engine/101."""
        engine = (self.data["vehicle"]["params"].get("Engine") or "").lower()
        return (f"{AMAYAMA}/genuine-catalogs/epc/{CATALOG}/{MODEL_FOLDER}/{self.data['vehicle']['variant'].lower()}/"
                f"{self.variant_id}-{engine}/{category}/{code}")

    @staticmethod
    def part_url(number):
        return f"{AMAYAMA}/part/{MAKE}/{part_key(number).lower()}"

    # MARK: groups

    def existing_group_folders(self):
        """Group code -> existing folder in the variant. Amayama's folders (often empty placeholders the Amayama
        scraper creates for every group) win, so their name and category define the structure."""
        folders = {}
        for folder in sorted(self.variant_dir.glob("*/*")):
            if not folder.is_dir():
                continue
            code = folder.name.split("_", 1)[0]
            json_file = folder / "schema-group.json"
            is_megazip_output = json_file.exists() and not is_amayama(json_file)
            if code not in folders or not is_megazip_output:
                folders[code] = folder
        return folders

    def convert_groups(self):
        existing = self.existing_group_folders()
        vehicle, source = self.vehicle(), self.source_block()
        for section in self.data["sections"]:
            diagrams = [self.diagrams[uid] for uid in section["diagrams"] if uid in self.diagrams]
            if not diagrams:
                continue
            folder = existing.get(section["code"])
            if folder is None:
                chapter = Counter(d["chapter"] for d in diagrams).most_common(1)[0][0]
                folder = self.variant_dir / CATEGORY_BY_CHAPTER.get(chapter, "misc") / folder_name(section["code"], section["name"])
                self.stats["groups without an Amayama folder"] += 1
            category = folder.parent.name
            for diagram in diagrams:
                self.group_of_diagram[diagram["uid"]] = (category, section["code"])
            target = folder / "schema-group.json"
            if target.exists() and is_amayama(target):
                self.stats["groups kept from Amayama"] += 1
                continue
            name = folder.name.split("_", 1)[1].replace("-", " ").lower()
            name = re.sub(r"\band\b", "&", name)
            group = {
                "format_version": 2,
                "source": source,
                "vehicle": vehicle,
                "group": {"category": category, "code": section["code"], "name": name,
                          "title_raw": f"{name} ({category}) for Nissan 180SX, {vehicle['frame']}, {self.period_text()}"},
                "images": {},
                "schemas": [],
            }
            sheet_numbers = {}
            for index, diagram in enumerate(diagrams, start=1):
                file = diagram["image"]["file"]
                sheet_numbers.setdefault(file, len(sheet_numbers) + 1)
                key = self.image_key(diagram, section["code"], sheet_numbers[file])
                group["images"][key] = {"url": diagram["image"]["src"],
                                        "width": diagram["image"]["width"], "height": diagram["image"]["height"]}
                group["schemas"].append(self.schema(diagram, index, len(diagrams), key))
                self.copy_image(diagram, key)
            self.write(target, group)
            self.stats["groups written"] += 1
            self.stats["schemas written"] += len(diagrams)

    def schema(self, diagram, index, count, image_key):
        fields = labelled_fields(diagram.get("description"))
        width, height = diagram["image"]["width"], diagram["image"]["height"]
        hotspots = {}
        for hotspot in diagram["hotspots"]:
            hotspots.setdefault(hotspot["ref"], []).extend(hotspot["areas"])
        callouts = []
        for ref, entries in diagram["refs"].items():
            parts = [self.part_row(entry) for entry in entries]
            first = self.parts.get(entries[0]["partUid"]) if entries else None
            name = (first or {}).get("name", "").lower() or None
            callouts.append({
                "pnc": ref,
                "name": name,
                "hotspots": [{
                    "shape": "rect",
                    "rect": {k: round(area[k]) for k in ("x1", "y1", "x2", "y2")},
                    "norm": {"x1": round(area["x1"] / width, 4), "y1": round(area["y1"] / height, 4),
                             "x2": round(area["x2"] / width, 4), "y2": round(area["y2"] / height, 4)},
                    "title": name,
                } for area in hotspots.get(ref, [])],
                "parts": parts,
            })
            self.stats["callouts written"] += 1
        stem = Path(image_key).stem
        return {
            "id": f"{stem}_{index - 1}",
            "index": index,
            "of": count,
            "applies": applies_list(fields.get("app_model")),
            "period": period(diagram.get("dateRange")),
            "image": image_key,
            "callouts": callouts,
        }

    def part_row(self, entry):
        part = self.parts.get(entry["partUid"], {})
        notes = {note["title"]: ", ".join(note["values"]) for note in entry.get("notes", [])}
        fields = labelled_fields(notes.get("Note"))
        applies = applies_list(fields.pop("app_model", None))
        details = dict(fields)
        if applies:
            details["applies"] = " +".join(applies)
        if notes.get("Required"):
            details["required"] = notes["Required"]
        quantity = entry.get("quantity")
        number = part.get("numberFormatted") or entry["partUid"].split("-", 1)[-1]
        description = " ".join(f"{title.replace('_', ' ').capitalize()}: {value}" for title, value in details.items())
        return {
            "oem": number,
            "url": self.part_url(number),
            "applies": applies,
            "details": details,
            "period": period(notes.get("Year")),
            "qty": quantity if isinstance(quantity, int) else None,
            "qty_raw": None if quantity is None else f"{quantity:02d}",
            "price": price_of(part),
            "replacements": [{
                "oem": self.parts.get(uid, {}).get("numberFormatted") or uid.split("-", 1)[-1],
                "url": self.part_url(self.parts.get(uid, {}).get("numberFormatted") or uid.split("-", 1)[-1]),
                "price": price_of(self.parts.get(uid)),
            } for uid in superseded_by(part)],
            "description_raw": description or None,
        }

    def copy_image(self, diagram, key):
        target = self.make_dir / "_images" / key
        if target.exists():
            return
        if not self.is_dry_run:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.source / diagram["image"]["file"], target)
        self.stats["images copied"] += 1

    # MARK: part pages

    def convert_part_pages(self):
        source, frame = self.source_block(), self.data["vehicle"]["variant"]
        for uid, part in self.parts.items():
            number = part.get("numberFormatted") or part["number"]
            key = part_key(number)
            target = self.make_dir / "_parts" / key[:2] / f"{key}.json"
            if target.exists() and is_amayama(target):
                self.stats["part pages kept from Amayama"] += 1
                continue
            refs = []
            for used in part.get("usedIn", []):
                category, code = self.group_of_diagram.get(used["diagramUid"], (None, None))
                if code is None:
                    continue
                ref = {"catalog": CATALOG, "model": MODEL_FOLDER, "frame": frame, "variant_id": self.variant_id,
                       "category": category, "group": code, "url": self.group_url(category, code)}
                if ref not in refs:
                    refs.append(ref)
            page = {
                "format_version": 1,
                "source": {**source, "scraped_at": part.get("offersFetchedAt") or source["scraped_at"]},
                "make": MAKE,
                "oem": number,
                "key": key,
                "name": (part.get("name") or number).upper(),
                "brand": f"Genuine {part['brand']}" if part.get("brand") else None,
                "catalog_name": (part.get("name") or number).upper(),
                "weight": {"kg": None, "raw": "unknown"},
                "offers": [self.offer(offer) for offer in part.get("offers", [])],
                "substitutes": [],
                "aftermarket": [],
                "notices": [{"kind": "note", "text": str(note)} for note in part.get("notes", [])],
                "fits": {"model": "Nissan 180SX"},
                "photos": [],
                "diagrams": refs,
            }
            self.write(target, page)
            self.stats["part pages written"] += 1

    @staticmethod
    def offer(offer):
        days = offer.get("handlingDays") or {}
        delivery = f"{days['from']:02d} - {days['to']:02d} days" if days.get("from") is not None else None
        price = offer.get("price")
        return {
            "from": {"JP": "Japan", "AE": "UAE"}.get(offer.get("warehouse"), offer.get("warehouse") or "Megazip"),
            "price": round(float(price), 2) if price is not None else None,
            "price_raw": f"{price:,.2f}" if price is not None else None,
            "currency": "USD",
            "shipping_raw": None,
            "delivery_raw": delivery,
            "availability": None if offer.get("availabilityRate") is None else str(offer["availabilityRate"]),
        }

    # MARK: output

    def write(self, path, payload):
        if self.is_dry_run:
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")

    def run(self):
        if not self.variant_dir.parent.exists() and not self.is_dry_run:
            self.variant_dir.parent.mkdir(parents=True)
        self.convert_groups()
        self.convert_part_pages()
        return self.stats


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", type=Path, help="partsCollect output folder holding catalog.json and images/")
    parser.add_argument("--catalogue", type=Path, default=Path("catalogue"), help="Garage Virtus catalogue folder")
    parser.add_argument("--variant", required=True, help="variant folder name, e.g. 6976_1994-1998_TYPE-RX_MT_4WS")
    parser.add_argument("--dry-run", action="store_true", help="report what would be written without writing")
    args = parser.parse_args()
    if not (args.source / "catalog.json").exists():
        sys.exit(f"{args.source} has no catalog.json")
    stats = Converter(args.source.expanduser(), args.catalogue, args.variant, args.dry_run).run()
    for name, count in sorted(stats.items()):
        print(f"{count:6d}  {name}")


if __name__ == "__main__":
    main()
