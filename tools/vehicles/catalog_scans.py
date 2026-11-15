#!/usr/bin/env python3
"""Adds the vehicle scans to tools/assets/catalog.json.

tools/vehicles/scans.json says which game kind each downloaded scan is
(VehicleTypes) and its real bumper-to-bumper length in metres (maker specs);
credits.json (from the vehicle-scans-raw release) gives title, author, page
and licence. Run: python3 tools/vehicles/catalog_scans.py credits.json
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LIC = {"http://creativecommons.org/licenses/by/4.0/": "CC-BY-4.0",
       "https://creativecommons.org/licenses/by/4.0/": "CC-BY-4.0",
       "http://creativecommons.org/publicdomain/zero/1.0/": "CC0-1.0"}


def main():
    credits = json.load(open(sys.argv[1]))
    scans = json.load(open(os.path.join(ROOT, "tools/vehicles/scans.json")))
    path = os.path.join(ROOT, "tools/assets/catalog.json")
    cat = json.load(open(path))
    n = 0
    for slug, s in scans.items():
        c = credits.get(slug)
        if c is None:
            print("no credit for", slug)
            continue
        lic = LIC.get(c.get("licence_url", ""))
        if lic is None:
            print("REFUSED", slug, c.get("licence"))
            continue
        aid = "veh_%s_%s" % (s["kind"], slug.replace("-", "_"))
        if slug == "fusion":
            aid = "veh_sedan_fusion_2016"
        cat["models"][aid] = {
            "src": "scan", "raw": slug + ".zip", "length": s["length"], "licence": lic,
            "author": c["author"], "page": c["url"],
            "name": "%s (cleaned and resized for the game)" % c["title"],
            "loop": "vehicles", "use": "%s in traffic and parked (VehicleScans)" % s["kind"],
            "real": "%s, %.2f m long (maker spec)" % (c["title"].replace(" Photoscan", "").replace("Photoscanned ", ""), s["length"]),
        }
        if s.get("flip"):
            cat["models"][aid]["flip"] = True
        n += 1
    json.dump(cat, open(path, "w"), indent=1)
    print(n, "vehicle scans in the catalog")


main()
