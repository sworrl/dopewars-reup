#!/usr/bin/env python3
"""Generate MID and BULK product art per drug (the existing {id}.png stays the SMALL baggie tier).

Same anti-glorification framing as gen_item_icons.py: everything is a POLICE EVIDENCE seizure on a
forensic surface, desaturated, no glow/sparkle/haze. The point is that a bulk seizure of weed reads
visibly different from a bulk seizure of meth. The market/inventory row swaps art by stash size.

Usage:  GEMINI_API_KEY=... python3 tools/gen_item_tiers.py [ids...]
Output: assets/generated/items/<id>_mid.png , <id>_bulk.png  (1:1)
"""
import base64, json, os, sys, urllib.request, urllib.error

MODEL = "imagen-4.0-ultra-generate-001"
URL = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:predict"
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "generated", "items")

# Shared forensic staging. Bulk is a bigger haul but still an evidence photo, never a product shot.
STYLE = ("Photographed straight top-down on a dark charcoal forensic surface under flat clinical "
         "lighting, with a small printed white evidence label and a numbered yellow forensic marker "
         "beside it. Forensic/documentary look, desaturated, matte, NO glow, NO sparkle, NO smoke or "
         "haze, NOT glamorized. Fills most of the square frame, centered, dark neutral background, "
         "subtle soft shadow. No readable text.")

# (mid description, bulk description) per drug. Bulk forms are deliberately drug-specific.
TIERS = {
  "weed": (
    "A glass mason jar and one medium vacuum-sealed bag holding roughly an ounce of dried green cannabis flower",
    "A large vacuum-sealed compressed BRICK of green cannabis flower beside an overstuffed turkey bag of buds, a bulk seizure"),
  "hash": (
    "A few small pressed dark brown blocks of hashish stacked",
    "A tall stack of pressed dark brown hashish slabs, stamped, wrapped in plastic, a bulk seizure"),
  "cocaine": (
    "A sandwich bag holding a compressed golf-ball-sized amount of white powder",
    "A rectangular taped KILO BRICK of cocaine tightly wrapped in clear plastic, a bulk seizure"),
  "meth": (
    "A quart sandwich bag full of clear-white crystalline meth shards",
    "A large clear bag packed with clear-white crystalline meth shards, several pounds, a bulk seizure"),
  "heroin": (
    "A medium bag of tan-brown heroin powder",
    "A rectangular pressed BRICK of tan-brown heroin wrapped in plastic and tape, a bulk seizure"),
  "fentanyl": (
    "A small bag of plain white pressed pills with a hazardous-material warning card",
    "A pressed white BRICK marked as hazardous, wrapped and taped, handled at arm's length, a bulk seizure"),
  "oxy": (
    "A full amber prescription pill bottle of round white pills",
    "A large pharmacy stock bottle and many blister sheets of white round pills spread out, a bulk seizure"),
  "mdma": (
    "A small bag of a couple dozen plain pressed tablets",
    "A large bag packed with hundreds of plain pressed tablets, a bulk seizure"),
  "lsd": (
    "A partial perforated blotter-paper sheet",
    "A stack of full perforated blotter-paper sheets, a bulk seizure"),
  "shrooms": (
    "A quart bag of dried mushroom caps",
    "An overstuffed turkey bag of dried mushroom caps, a bulk seizure"),
}

def gen(prompt, out_path):
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        sys.exit("GEMINI_API_KEY not set")
    body = json.dumps({"instances": [{"prompt": prompt}],
        "parameters": {"sampleCount": 1, "aspectRatio": "1:1",
                       "personGeneration": "dont_allow"}}).encode()
    req = urllib.request.Request(URL, data=body, method="POST",
        headers={"Content-Type": "application/json", "x-goog-api-key": key})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        print(f"  HTTP {e.code}: {e.read().decode()[:300]}"); return False
    preds = data.get("predictions") or []
    if not preds or "bytesBase64Encoded" not in preds[0]:
        print(f"  no image: {json.dumps(data)[:300]}"); return False
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(base64.b64decode(preds[0]["bytesBase64Encoded"]))
    print(f"  OK {out_path}"); return True

if __name__ == "__main__":
    ids = sys.argv[1:] or list(TIERS.keys())
    for iid in ids:
        mid, bulk = TIERS[iid]
        print(f"[{iid} mid]");  gen(f"{mid}. {STYLE}",  os.path.join(OUT_DIR, f"{iid}_mid.png"))
        print(f"[{iid} bulk]"); gen(f"{bulk}. {STYLE}", os.path.join(OUT_DIR, f"{iid}_bulk.png"))
