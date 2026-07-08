#!/usr/bin/env bash
# Bundle the web installer into site/install/ (committed, so Cloudflare Pages
# needs no build step). Run after changing src/app.js or index.html:
#   cd web-installer && npm install && ./build.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../site/install"
mkdir -p "$OUT"
"$HERE/node_modules/.bin/esbuild" "$HERE/src/app.js" \
  --bundle --minify --format=esm --target=es2022 \
  --outfile="$OUT/app.js"
cp "$HERE/index.html" "$OUT/index.html"
echo "Built $OUT (app.js + index.html)"
