#!/usr/bin/env python3
"""Generate the 10 market item icons with Imagen 4 Ultra.

Anti-glorification framing: every product is a sealed POLICE EVIDENCE BAG, forensic/clinical,
never glamorized, no glow/sparkle/haze. Documentary, desaturated. Reads at small sizes.

Usage:  GEMINI_API_KEY=... python3 tools/gen_item_icons.py [ids...]
Output: assets/generated/items/<id>.png  (1:1)
"""
import base64, json, os, sys, urllib.request, urllib.error

MODEL = "imagen-4.0-ultra-generate-001"
URL = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:predict"
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "generated", "items")

STYLE = ("Sealed transparent police EVIDENCE bag with a small printed white evidence label "
         "and a red tamper seal, photographed straight top-down on a dark charcoal forensic "
         "surface under flat clinical lighting. Forensic/documentary look, desaturated, matte, "
         "NO glow, NO sparkle, NO smoke or haze, NOT glamorized. The bag fills most of the "
         "square frame, centered, dark neutral background, subtle soft shadow. No readable text.")

ITEMS = {
  "weed":     "containing a small amount of dried greenish cannabis flower",
  "hash":     "containing a small dark brown pressed block of hashish",
  "cocaine":  "containing a small amount of white powder",
  "meth":     "containing a few small clear-white crystalline shards",
  "heroin":   "containing a small amount of tan-brown powder",
  "fentanyl": "containing two small plain white pressed pills, marked as hazardous",
  "oxy":      "containing a few round white prescription pills",
  "mdma":     "containing three plain pressed tablets",
  "lsd":      "containing a single small square of perforated blotter paper",
  "shrooms":  "containing a few dried mushroom caps",
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
    ids = sys.argv[1:] or list(ITEMS.keys())
    for iid in ids:
        print(f"[{iid}]")
        gen(f"A police evidence bag {ITEMS[iid]}. {STYLE}", os.path.join(OUT_DIR, f"{iid}.png"))
