#!/usr/bin/env python3
"""Generate cosmetic ICON art with Imagen 4 Ultra for the catalog items that need it.

Titles + accents are text/color (no art). Nameplates are color backplates (skipped here). Everything
else — emblems, frames, badges, markers, tags, charms — gets a small on-tone icon. Rust-belt / The
Wire aesthetic: desaturated, matte, a single red accent, no glow/sparkle, reads at small size.

Usage:  GEMINI_API_KEY=$(cat .gemini_key) python3 tools/gen_cosmetic_art.py
Output: assets/generated/cosmetics/<id>.png (full) + assets/sprites/cosmetics/<id>.png (256, shipped)
Also rewrites data/cosmetics.json 'art' fields for every item it makes.
"""
import base64, json, os, subprocess, sys, time, urllib.request, urllib.error

ROOT = os.path.join(os.path.dirname(__file__), "..")
MODEL = "imagen-4.0-ultra-generate-001"
URL = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:predict"
GEN_DIR = os.path.join(ROOT, "assets", "generated", "cosmetics")
SPR_DIR = os.path.join(ROOT, "assets", "sprites", "cosmetics")
CAT = os.path.join(ROOT, "data", "cosmetics.json")

BASE = ("Rust-belt street aesthetic, The Wire tone: desaturated, matte, muted palette with a single "
        "muted-red accent, on a dark charcoal background, centered, clean silhouette that reads at "
        "small sizes. NO text, NO glow, NO sparkle, NO haze, not glamorized, documentary flat style.")

STYLE = {
  "emblem":  lambda n: f"A minimalist flat street EMBLEM / insignia icon evoking '{n}'. {BASE}",
  "frame":   lambda n: f"An ornamental avatar FRAME — a decorative border ring only, empty center, "
                       f"industrial/street materials, evoking '{n}'. {BASE}",
  "badge":   lambda n: f"A small achievement BADGE / enamel medal icon representing '{n}'. {BASE}",
  "marker":  lambda n: f"A flat top-down map PIN / marker icon shaped after '{n}'. {BASE}",
  "tag":     lambda n: f"A single spray-paint GRAFFITI mark evoking '{n}' on grimy concrete, "
                       f"no legible letters. {BASE}",
  "charm":   lambda n: f"A small dangling phone CHARM / keychain trinket object of '{n}'. {BASE}",
  "nameplate": lambda n: (f"A wide horizontal NAMEPLATE background banner texture evoking '{n}' — a "
                       f"subtle grimy surface (concrete, metal, neon-lit brick) with empty center space "
                       f"for a name to sit over. {BASE}"),
}
# Aspect ratio per category (nameplates are wide banners; everything else is a square icon).
ASPECT = {"nameplate": "16:9"}

def gen(prompt, out_path, aspect="1:1"):
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        sys.exit("GEMINI_API_KEY not set")
    body = json.dumps({"instances": [{"prompt": prompt}],
        "parameters": {"sampleCount": 1, "aspectRatio": aspect, "personGeneration": "dont_allow"}}).encode()
    req = urllib.request.Request(URL, data=body, method="POST",
        headers={"Content-Type": "application/json", "x-goog-api-key": key})
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        print(f"  HTTP {e.code}: {e.read().decode()[:200]}"); return False
    except Exception as e:
        print(f"  ERR {e}"); return False
    preds = data.get("predictions") or []
    if not preds or "bytesBase64Encoded" not in preds[0]:
        print(f"  no image: {json.dumps(data)[:200]}"); return False
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(base64.b64decode(preds[0]["bytesBase64Encoded"]))
    return True

def main():
    cat = json.load(open(CAT))
    made = 0
    for c in cat["cosmetics"]:
        cid, category = c["id"], c["category"]
        if category not in STYLE:
            continue
        spr = os.path.join(SPR_DIR, f"{cid}.png")
        if c.get("art") and os.path.exists(spr):
            continue                                  # already has art
        print(f"[{category}] {cid} — {c['name']}")
        full = os.path.join(GEN_DIR, f"{cid}.png")
        if not gen(STYLE[category](c["name"]), full, ASPECT.get(category, "1:1")):
            continue
        os.makedirs(SPR_DIR, exist_ok=True)
        rz = "512x160" if category == "nameplate" else "256x256"
        subprocess.run(["convert", full, "-resize", rz, spr], check=False)
        if not os.path.exists(spr):                   # convert missing -> ship the full res
            subprocess.run(["cp", full, spr], check=False)
        c["art"] = f"res://assets/sprites/cosmetics/{cid}.png"
        made += 1
        print(f"  OK ({made})")
        time.sleep(1.0)                               # be gentle on rate limits
    json.dump(cat, open(CAT, "w"), indent=1)
    print(f"\nDONE — generated {made} cosmetic icons; cosmetics.json updated.")

if __name__ == "__main__":
    main()
