#!/usr/bin/env python3
"""Phone gear art. Phones are RPG equipment (they take damage, need charging, run stock or hardened
OS). Same desaturated documentary tone as the rest of the game: each phone photographed top-down on
a dark charcoal surface, a little worn/used, no glamour, no logos, no readable text.

Usage:  GEMINI_API_KEY=... python3 tools/gen_phone_art.py [ids...]
Output: assets/generated/phones/<id>.png  (1:1)
"""
import base64, json, os, sys, urllib.request, urllib.error

MODEL = "imagen-4.0-ultra-generate-001"
URL = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:predict"
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "generated", "phones")

STYLE = ("Photographed straight top-down on a dark charcoal surface under flat, cool lighting. "
         "Slightly worn and used, faint scuffs. Desaturated, matte, documentary, NO glow, NO logos, "
         "NO readable text, not glamorized. The device fills most of the square frame, centered, "
         "dark neutral background, subtle soft shadow.")

PHONES = {
  "burner_flip":   "A cheap small black plastic flip phone, closed, basic, no screen visible",
  "prepaid_droid": "A cheap thick budget touchscreen smartphone with a plastic body and large bezels, screen off",
  "ifruit_se":     "A small older glass-and-aluminum touchscreen smartphone, single rear camera, screen off",
  "pixhell_6a":    "A clean modern midrange touchscreen smartphone with a horizontal rear camera bar, screen off",
  "galaxa_s":      "A large glossy flagship touchscreen smartphone with a triple rear camera cluster, screen off",
  "pixhell_9pro":  "A large premium matte touchscreen smartphone with a wide horizontal rear camera visor, screen off",
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
        print(f"  HTTP {e.code}: {e.read().decode()[:200]}"); return False
    preds = data.get("predictions") or []
    if not preds or "bytesBase64Encoded" not in preds[0]:
        print(f"  no image: {json.dumps(data)[:200]}"); return False
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(base64.b64decode(preds[0]["bytesBase64Encoded"]))
    print(f"  OK {out_path}"); return True

if __name__ == "__main__":
    ids = sys.argv[1:] or list(PHONES.keys())
    for pid in ids:
        print(f"[{pid}]")
        gen(f"{PHONES[pid]}. {STYLE}", os.path.join(OUT_DIR, f"{pid}.png"))
