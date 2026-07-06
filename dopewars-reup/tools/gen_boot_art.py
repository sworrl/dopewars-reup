#!/usr/bin/env python3
"""Branded loading-screen key art (animated in-engine via slow zoom + drawn route line).

Motif matches the app icon: a single glowing red route line threading a dark rust-belt city grid
at night, seen from above. Cinematic, desaturated except the red route. Documentary, no glamour,
no text. 9:16 so it fills a portrait phone.

Usage:  GEMINI_API_KEY=... python3 tools/gen_boot_art.py
Output: assets/generated/ui/boot_art.png
"""
import base64, json, os, sys, urllib.request, urllib.error

MODEL = "imagen-4.0-ultra-generate-001"
URL = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:predict"
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "generated", "ui", "boot_art.png")

PROMPT = (
    "A moody cinematic night-time aerial view of an American rust-belt city street grid seen from "
    "high above, dark charcoal and deep blue, sparse cold streetlights, industrial river and "
    "bridges, low fog. One single thin glowing crimson-red route line threads through the grid "
    "from bottom to top, like a plotted trip on a map. Desaturated and bleak everywhere EXCEPT "
    "that red line. Documentary, somber, The-Wire tone, NOT glamorized, no people, no cars, no "
    "text, no logos, film grain. Vertical 9:16 composition, the red route leading the eye upward.")

def main():
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        sys.exit("GEMINI_API_KEY not set")
    body = json.dumps({"instances": [{"prompt": PROMPT}],
        "parameters": {"sampleCount": 1, "aspectRatio": "9:16",
                       "personGeneration": "dont_allow"}}).encode()
    req = urllib.request.Request(URL, data=body, method="POST",
        headers={"Content-Type": "application/json", "x-goog-api-key": key})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read().decode()[:300]}")
    preds = data.get("predictions") or []
    if not preds or "bytesBase64Encoded" not in preds[0]:
        sys.exit(f"no image: {json.dumps(data)[:300]}")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as f:
        f.write(base64.b64decode(preds[0]["bytesBase64Encoded"]))
    print(f"OK {OUT}")

if __name__ == "__main__":
    main()
