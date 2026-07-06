#!/usr/bin/env python3
"""Generate the 8 transport-mode icons with Imagen 4 Ultra (replaces the emoji set).

Consistent object-on-dark documentary look, rust-belt flavor, matte, no logos/text.

Usage:  GEMINI_API_KEY=... python3 tools/gen_transport_icons.py [ids...]
Output: assets/generated/transport/<id>.png  (1:1)
"""
import base64, json, os, sys, urllib.request, urllib.error

MODEL = "imagen-4.0-ultra-generate-001"
URL = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:predict"
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "generated", "transport")

STYLE = ("Single object centered on a plain dark charcoal studio background, straight product "
         "shot, soft even lighting, desaturated matte documentary look, gritty and worn, "
         "American rust-belt flavor. NO text, NO brand logos, NO license plates, no people. "
         "Fills the square frame with a little margin, subtle soft shadow beneath.")

MODES = {
  "walk":       "a worn pair of everyday sneakers, side profile",
  "walk_offroad": "a muddy scuffed pair of hiking boots, side profile",
  "bike":       "an old used road bicycle, clean side profile",
  "motorcycle": "a used mid-size cruiser motorcycle, clean side profile",
  "car":        "a beat-up older four-door sedan, three-quarter front view",
  "bus":        "an intercity coach bus, three-quarter side view",
  "rideshare":  "an ordinary compact sedan with a phone mounted on the dashboard, three-quarter view",
  "plane":      "a small commercial regional airliner parked on a tarmac, side view",
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
    ids = sys.argv[1:] or list(MODES.keys())
    for mid in ids:
        print(f"[{mid}]")
        gen(f"{MODES[mid]}. {STYLE}", os.path.join(OUT_DIR, f"{mid}.png"))
