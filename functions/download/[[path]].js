// Same-origin proxy for GitHub release assets (Cloudflare Pages Function).
// GitHub's release CDN sends no CORS headers, so the browser installer can't fetch
// the APK from github.com directly — it fetches it from here instead. Also gives
// humans stable URLs that always point at the newest release:
//
//   /download/latest.apk      -> newest signed APK (resolved via the latest.json manifest)
//   /download/latest.json     -> the release manifest { version, url, sha256, notes }
//   /download/windows         -> DopeWarsReUp-Windows-Installer.zip
//   /download/sha256sums.txt  -> SHA256SUMS.txt
//   /download/<tag>/<asset>   -> a specific release asset (apk/zip/txt/json only)
const REPO = "sworrl/dopewars-reup";
const LATEST = `https://github.com/${REPO}/releases/latest/download/`;

const STABLE = {
  "latest.json": LATEST + "latest.json",
  "windows": LATEST + "DopeWarsReUp-Windows-Installer.zip",
  "sha256sums.txt": LATEST + "SHA256SUMS.txt",
};

const TYPES = {
  apk: "application/vnd.android.package-archive",
  zip: "application/zip",
  txt: "text/plain; charset=utf-8",
  json: "application/json; charset=utf-8",
};

async function proxy(url, filename) {
  const upstream = await fetch(url, {
    redirect: "follow",
    cf: { cacheEverything: true, cacheTtl: 300 },
  });
  if (!upstream.ok) {
    return new Response("Upstream fetch failed: HTTP " + upstream.status, { status: 502 });
  }
  const ext = filename.split(".").pop().toLowerCase();
  const headers = new Headers({
    "Content-Type": TYPES[ext] || "application/octet-stream",
    "Content-Disposition": ext === "json" || ext === "txt"
      ? "inline"
      : `attachment; filename="${filename}"`,
    "Cache-Control": "public, max-age=300",
    "Access-Control-Allow-Origin": "*",
  });
  const len = upstream.headers.get("Content-Length");
  if (len) headers.set("Content-Length", len);
  return new Response(upstream.body, { status: 200, headers });
}

export async function onRequestGet(context) {
  const parts = context.params.path || [];
  const path = (Array.isArray(parts) ? parts.join("/") : parts).toLowerCase();

  if (STABLE[path]) {
    return proxy(STABLE[path], STABLE[path].split("/").pop());
  }

  if (path === "latest.apk") {
    // The APK asset name is versioned; latest.json tells us where it lives.
    const mres = await fetch(STABLE["latest.json"], {
      redirect: "follow",
      cf: { cacheEverything: true, cacheTtl: 300 },
    });
    if (!mres.ok) return new Response("Release manifest unavailable", { status: 502 });
    const manifest = await mres.json();
    const url = String(manifest.url || "");
    if (!url.startsWith(`https://github.com/${REPO}/releases/download/`)) {
      return new Response("Manifest points outside this project's releases", { status: 502 });
    }
    return proxy(url, url.split("/").pop());
  }

  // /download/<tag>/<asset> — pinned versions, tight allowlist.
  const m = /^([a-z0-9][\w.-]*)\/([\w][\w .-]*\.(apk|zip|txt|json))$/i.exec(
    Array.isArray(parts) ? parts.join("/") : parts
  );
  if (m) {
    return proxy(
      `https://github.com/${REPO}/releases/download/${m[1]}/${m[2]}`,
      m[2]
    );
  }

  return new Response("Not found. Try /download/latest.apk", { status: 404 });
}
