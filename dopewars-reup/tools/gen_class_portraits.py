#!/usr/bin/env python3
"""Generate the 10 chargen class portraits with Imagen 4 Ultra.

Tone: anti-glorification, documentary realism (The Wire, not GTA). Somber,
desaturated, no weapons brandished, no drug use depicted, no glamour.

Usage:  GEMINI_API_KEY=... python3 tools/gen_class_portraits.py
Output: assets/generated/classes/<id>.png  (1:1)
"""
import base64, json, os, sys, urllib.request, urllib.error

MODEL = "imagen-4.0-ultra-generate-001"
URL = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:predict"
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "generated", "classes")

STYLE = ("Somber documentary-realism character portrait, desaturated cold color grade, "
         "natural overcast lighting, American rust-belt setting, cinematic like the TV "
         "show The Wire. Weary, human, dignified — NOT glamorous, NOT action-hero posed, "
         "no brandished weapons, no drugs shown. Head-and-shoulders, neutral dark backdrop "
         "for easy compositing, shallow depth of field. Square framing. "
         "Full-bleed photograph filling the entire frame — no white border, no frame, "
         "no matte, no margin.")

CLASSES = {
  "street_hustler": "A young corner hustler who grew up on these blocks, guarded eyes, hood up, knows everyone and owes everyone.",
  "cook": "A tired former lab technician in their 30s, chemical burn scar on the hand, spent two years in a bio lab and walked away with the recipes.",
  "muscle": "A heavyset bouncer-turned-enforcer, broad shoulders, calm intimidating stare, solves problems with his weight.",
  "hacker": "A wiry hoodie-wearing tech obsessive surrounded by dim monitor glow, phones and transponders are their toys.",
  "ex_cop": "A grizzled former police officer in their late 40s who took the badge for fifteen years and then crossed the street, conflicted expression.",
  "trust_fund_kid": "A bored wealthy young adult in expensive but rumpled clothes, curious about the wrong things, out of place and knows it.",
  "veteran": "A military veteran with two tours behind them, thousand-yard stare, honorable-discharge bearing, a chip the size of a city.",
  "junkie": "A gaunt weathered person who knows the streets because they live there — depicted with clinical compassion and dignity, NOT as a caricature, a survivor coming back.",
  "pharm_tech": "A pharmacy technician in a white coat and blue nitrile gloves, fluorescent-lit, holds a key to the cabinet, quietly compromised.",
  "biker": "A patched outlaw motorcycle club member, leather vest with club colors, prospect days behind them, riding for the club.",
}

def gen(prompt, out_path):
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        sys.exit("GEMINI_API_KEY not set")
    body = json.dumps({"instances": [{"prompt": prompt}],
        "parameters": {"sampleCount": 1, "aspectRatio": "1:1",
                       "personGeneration": "allow_adult"}}).encode()
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
    # Optional: pass class ids as args to generate only a subset (style-lock batch).
    ids = sys.argv[1:] or list(CLASSES.keys())
    for cid in ids:
        print(f"[{cid}]")
        gen(f"{CLASSES[cid]} {STYLE}", os.path.join(OUT_DIR, f"{cid}.png"))
