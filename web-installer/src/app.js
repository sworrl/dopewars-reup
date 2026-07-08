// Dope Wars: Re-Up — browser installer (WebUSB + WebADB, à la Meshtastic's web flasher).
// Bundled with esbuild into site/install/app.js. The APK is streamed same-origin via the
// /download/* Cloudflare Pages Function (GitHub release assets don't send CORS headers).
import { Adb, AdbDaemonTransport } from "@yume-chan/adb";
import { AdbDaemonWebUsbDeviceManager } from "@yume-chan/adb-daemon-webusb";
import AdbWebCredentialStore from "@yume-chan/adb-credential-web";
import { PackageManager } from "@yume-chan/android-bin";

const PACKAGE_ID = "com.dopewarsreup.app";
const $ = (id) => document.getElementById(id);

const logEl = $("log");
function log(msg) {
  logEl.textContent += (logEl.textContent ? "\n" : "") + msg;
  logEl.scrollTop = logEl.scrollHeight;
}
function setStatus(msg, cls = "") {
  const el = $("status");
  el.textContent = msg;
  el.className = "status " + cls;
}
function setProgress(frac, label) {
  const wrap = $("progress");
  wrap.hidden = frac == null;
  if (frac != null) {
    $("bar").style.width = Math.round(frac * 100) + "%";
    $("plabel").textContent = label || "";
  }
}
function step(n) {
  document.querySelectorAll(".step").forEach((el, i) => {
    el.classList.toggle("active", i === n);
    el.classList.toggle("done", i < n);
  });
}

// ---------- environment routing: send each visitor down the path that works ----------
const ua = navigator.userAgent;
const isAndroid = /Android/i.test(ua);
const isIOS = /iPhone|iPad|iPod/i.test(ua);
const hasWebUsb = "usb" in navigator;

function route() {
  if (isAndroid) {
    $("android-path").hidden = false;
    $("usb-path").hidden = true;
    return;
  }
  if (isIOS) {
    $("ios-path").hidden = false;
    $("usb-path").hidden = true;
    return;
  }
  if (!hasWebUsb) {
    $("nousb-path").hidden = false;
    $("usb-path").hidden = true;
    return;
  }
  $("usb-path").hidden = false;
}

// ---------- WebADB flow ----------
let adb = null;

async function connect() {
  const btn = $("connect");
  btn.disabled = true;
  try {
    setStatus("Waiting for you to pick your phone in the popup…");
    log("Requesting USB device…");
    const manager = AdbDaemonWebUsbDeviceManager.BROWSER;
    const device = await manager.requestDevice();
    if (!device) {
      setStatus("No phone picked. Empty list? See 'My phone isn't listed' below.", "warn");
      $("notlisted").open = true;
      return;
    }
    setStatus("Connecting to " + (device.name || device.serial) + "…");
    const connection = await device.connect();

    const hint = setTimeout(() => {
      setStatus("👉 LOOK AT YOUR PHONE — tap “Allow USB debugging” on the popup.", "warn");
      log("Waiting for you to tap Allow on the phone…");
    }, 2500);
    const transport = await AdbDaemonTransport.authenticate({
      serial: device.serial,
      connection,
      credentialStore: new AdbWebCredentialStore("Dope Wars: Re-Up installer"),
    });
    clearTimeout(hint);

    adb = new Adb(transport);
    log("Connected: " + (device.name || device.serial));
    setStatus("✅ Phone connected: " + (device.name || device.serial), "ok");
    step(2);
    $("install").disabled = false;
    $("install").focus();
  } catch (e) {
    explainConnectError(e);
  } finally {
    btn.disabled = false;
  }
}

function explainConnectError(e) {
  const m = String(e?.message || e);
  log("Connect failed: " + m);
  if (/claim|busy|in use|Unable to claim/i.test(m)) {
    setStatus("Another program is holding the phone (adb, Android Studio, scrcpy…). Close it, unplug/replug the cable, and try again.", "err");
  } else if (/denied|security|protected/i.test(m)) {
    setStatus("The browser was denied USB access. On Linux, your user may need udev rules / plugdev; easiest fix is to try another machine or use the APK download below.", "err");
  } else if (/rejected|REJECTED|auth/i.test(m)) {
    setStatus("The phone refused the connection. Unplug it, plug it back in, and tap ALLOW on the phone popup this time.", "err");
  } else {
    setStatus("Couldn't connect: " + m + " — unplug/replug and try again, or use one of the other install options below.", "err");
  }
}

async function fetchApk() {
  // latest.json is the release manifest: { version, url, sha256 } — served same-origin.
  let manifest = null;
  try {
    manifest = await (await fetch("/download/latest.json", { cache: "no-cache" })).json();
    log("Latest release: v" + manifest.version);
  } catch {
    log("Couldn't read release manifest — installing without hash check.");
  }

  setStatus("Downloading the game…");
  const res = await fetch("/download/latest.apk");
  if (!res.ok) throw new Error("APK download failed (HTTP " + res.status + ")");
  const total = Number(res.headers.get("Content-Length")) || 0;
  const chunks = [];
  let got = 0;
  const reader = res.body.getReader();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    got += value.length;
    setProgress(total ? got / total : null, "Downloading… " + (got / 1e6).toFixed(1) + (total ? " / " + (total / 1e6).toFixed(1) : "") + " MB");
  }
  const apk = new Uint8Array(got);
  let off = 0;
  for (const c of chunks) { apk.set(c, off); off += c.length; }
  log("Downloaded " + (got / 1e6).toFixed(1) + " MB.");

  if (manifest?.sha256) {
    setProgress(1, "Checking the download is genuine…");
    const digest = await crypto.subtle.digest("SHA-256", apk);
    const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
    if (hex !== manifest.sha256.toLowerCase()) {
      throw new Error("Checksum mismatch — the download doesn't match the signed release. Refusing to install. Try again, and report this if it repeats.");
    }
    log("SHA-256 verified ✔ (matches the published release checksum)");
  }
  return apk;
}

function progressStream(bytes, onProgress) {
  let sent = 0;
  const CHUNK = 512 * 1024;
  return new ReadableStream({
    pull(controller) {
      if (sent >= bytes.length) { controller.close(); return; }
      const c = bytes.subarray(sent, Math.min(sent + CHUNK, bytes.length));
      sent += c.length;
      onProgress(sent / bytes.length);
      controller.enqueue(c);
    },
  });
}

async function installApk(apk) {
  setStatus("Installing on the phone… leave it plugged in.");
  const pm = new PackageManager(adb);
  await pm.installStream(
    apk.length,
    progressStream(apk, (f) => setProgress(f, "Copying to phone… " + Math.round(f * 100) + "%"))
  );
}

async function install() {
  if (!adb) return;
  const btn = $("install");
  btn.disabled = true;
  try {
    const apk = await fetchApk();
    await installApk(apk);
    setProgress(null);
    step(3);
    setStatus("🎉 Installed! Unplug the phone and open “Dope Wars: Re-Up”.", "ok");
    log("Install complete.");
    $("done").hidden = false;
  } catch (e) {
    setProgress(null);
    await explainInstallError(e);
  } finally {
    btn.disabled = !adb;
  }
}

async function explainInstallError(e) {
  const m = String(e?.message || e);
  log("Install failed: " + m);
  if (/UPDATE_INCOMPATIBLE|signatures do not match/i.test(m)) {
    setStatus("Your phone has an old test build with a different signature. It has to be removed first (its LOCAL save data goes with it; online progress is safe on the server).", "warn");
    $("reinstall").hidden = false;
  } else if (/VERSION_DOWNGRADE/i.test(m)) {
    setStatus("Your phone already has a newer version installed — you're all set.", "ok");
  } else if (/NO_MATCHING_ABIS/i.test(m)) {
    setStatus("This phone's processor isn't supported (the game needs a 64-bit ARM phone, which is everything mainstream since ~2015).", "err");
  } else if (/INSUFFICIENT_STORAGE/i.test(m)) {
    setStatus("The phone is out of storage. Free up ~200 MB and try again.", "err");
  } else if (/Checksum mismatch/.test(m)) {
    setStatus(m, "err");
  } else {
    setStatus("Install failed: " + m + " — unplug/replug and try again, or use the APK download below.", "err");
  }
}

async function uninstallAndRetry() {
  const btn = $("reinstall");
  btn.disabled = true;
  try {
    setStatus("Removing the old copy…");
    log("pm uninstall " + PACKAGE_ID);
    await new PackageManager(adb).uninstall(PACKAGE_ID);
    log("Old copy removed.");
    $("reinstall").hidden = true;
    await install();
  } catch (e) {
    log("Uninstall failed: " + String(e?.message || e));
    setStatus("Couldn't remove the old copy automatically. On the phone: long-press the old Dope Wars icon → App info → Uninstall, then click Install here again.", "err");
  } finally {
    btn.disabled = false;
  }
}

route();
if ($("connect")) {
  $("connect").addEventListener("click", connect);
  $("install").addEventListener("click", install);
  $("reinstall").addEventListener("click", uninstallAndRetry);
  step(0);
}
