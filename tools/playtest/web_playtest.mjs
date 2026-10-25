// Plays the browser build in Chromium (scripts/perf/playtest.gd does the
// playing) and saves its result, plus the browser's own memory (the page's
// renderer and GPU processes, which is what runs out on an 8 GB Mac).
//
// Run: node tools/playtest/web_playtest.mjs <exported web dir> <seconds> <out.json> [ws://host:port/CODE] [name] [pin]
// The optional region plays in that region instead of alone, as the player name given.
// Needs Playwright (NODE_PATH pointing at a global install is fine).
//
// By default it runs in headless Chromium with software drawing (SwiftShader),
// which is what CI has. To measure what a player's browser does, set:
//   PLAYTEST_CHANNEL=chrome   the installed Google Chrome, not Playwright's Chromium
//   PLAYTEST_HEADED=1         a real window, so the real graphics chip draws
//   PLAYTEST_VIEW=1280x720    the page's size (default 800x450)
//   PLAYTEST_TOWN=t20.city    open this saved town and watch it (a file in the
//                             export dir or in PLAYTEST_TOWNS; tools/scale/make_town_save.gd)
//   PLAYTEST_TOWNS=dir        where saved towns are served from
//   PLAYTEST_PORT=8790        a fixed port (default: any free one)
// Beside the game's own numbers it records the load (page open to the game
// starting, the town's download and opening) and the Chromium processes'
// memory over time.
import { createServer } from "node:http";
import { readFile, writeFile } from "node:fs/promises";
import { execSync } from "node:child_process";
import { extname, join } from "node:path";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { createRequire } from "node:module";

// require() honours NODE_PATH, so a global Playwright works too.
const { chromium } = createRequire(import.meta.url)("playwright");

const [dir, seconds = "120", out = "playtest-web.json", region = "", name = "", pin = ""] = process.argv.slice(2);
const TOWN = process.env.PLAYTEST_TOWN || "";
const TOWNS = process.env.PLAYTEST_TOWNS || "";
const HEADED = process.env.PLAYTEST_HEADED === "1";
const CHANNEL = process.env.PLAYTEST_CHANNEL || "";
const [VW, VH] = (process.env.PLAYTEST_VIEW || "800x450").split("x").map(Number);
const TYPES = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm",
  ".pck": "application/octet-stream", ".png": "image/png" };

const server = createServer(async (req, res) => {
  let path = decodeURIComponent(new URL(req.url, "http://x").pathname);
  if (path === "/") path = "/index.html";
  try {
    let body;
    try {
      body = await readFile(join(dir, path));
    } catch (e) {
      if (!TOWNS) throw e;
      body = await readFile(join(TOWNS, path));
    }
    res.writeHead(200, { "Content-Type": TYPES[extname(path)] || "application/octet-stream",
      "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp" });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end();
  }
});
await new Promise((ok) => server.listen(Number(process.env.PLAYTEST_PORT || 0), ok));
const port = server.address().port;

// A profile folder of our own, so the memory counted below is only this run's
// browser (the player's other Chrome windows are left out).
const profile = mkdtempSync(join(tmpdir(), "playtest-chrome-"));

// Resident memory of this run's Chromium processes, in MB, by kind.
function browserMemory() {
  const mb = { renderer: 0, gpu: 0, all: 0 };
  try {
    for (const line of execSync("ps -eo rss=,args=", { encoding: "utf8" }).split("\n")) {
      if (!line.includes(profile)) continue;
      const rss = parseInt(line.trim(), 10) / 1024;
      if (!rss) continue;
      mb.all += rss;
      if (line.includes("--type=renderer")) mb.renderer = Math.max(mb.renderer, rss);
      if (line.includes("--type=gpu-process")) mb.gpu = Math.max(mb.gpu, rss);
    }
  } catch {}
  return mb;
}

const args = ["--enable-precise-memory-info", "--disable-renderer-backgrounding",
  "--disable-background-timer-throttling", "--disable-backgrounding-occluded-windows"];
if (!HEADED) args.push("--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist");
// A persistent context so the profile folder is ours (and the memory count is exact).
const context = await chromium.launchPersistentContext(profile, {
  headless: !HEADED, args, viewport: { width: VW, height: VH }, ...(CHANNEL ? { channel: CHANNEL } : {}),
});
const page = context.pages()[0] || await context.newPage();
// What the browser actually draws with (software drawing makes every number worse).
const gl = await page.evaluate(() => {
  const c = document.createElement("canvas").getContext("webgl2");
  if (!c) return "no WebGL2";
  const x = c.getExtension("WEBGL_debug_renderer_info");
  return x ? c.getParameter(x.UNMASKED_RENDERER_WEBGL) : "unknown";
});
let result = null;
let crashed = "";
const log = [];
let startedAt = 0;
page.on("console", (m) => {
  const t = m.text();
  if (t.startsWith("PLAYTEST_RESULT ")) result = JSON.parse(t.slice(16));
  else {
    if (!startedAt && t.startsWith("Playtest:")) startedAt = Date.now();
    if (log.length < 400) log.push(t);
  }
});
page.on("crash", () => { crashed = "the page crashed (out of memory?)"; });
page.on("pageerror", (e) => log.push("pageerror: " + e.message));

const peak = { renderer: 0, gpu: 0, all: 0 };
const series = [];
const timer = setInterval(() => {
  const m = browserMemory();
  for (const k in peak) peak[k] = Math.max(peak[k], m[k]);
  series.push([Math.round((Date.now() - t0) / 1000), Math.round(m.renderer), Math.round(m.gpu), Math.round(m.all)]);
}, 2000);

const t0 = Date.now();
await page.goto(`http://localhost:${port}/?playtest=${seconds}` + (region ? `&region=${encodeURIComponent(region)}` : "") +
  (name ? `&name=${encodeURIComponent(name)}` : "") + (pin ? `&pin=${encodeURIComponent(pin)}` : "") + (TOWN ? `&town=${encodeURIComponent(TOWN)}` : ""));
// The load, the build steps and the run, with room to spare.
const limit = (Number(seconds) + (TOWN ? 1500 : 600)) * 1000;
while (!result && !crashed && Date.now() - t0 < limit) {
  await new Promise((ok) => setTimeout(ok, 1000));
}
clearInterval(timer);
const report = result || { ok: false, error: crashed || "no result before the time limit" };
report.browser_memory_peak_mb = Object.fromEntries(Object.entries(peak).map(([k, v]) => [k, Math.round(v)]));
report.wall_seconds = Math.round((Date.now() - t0) / 1000);
report.engine_start_s = startedAt ? Math.round((startedAt - t0) / 100) / 10 : null;  // page open to the game's first line
report.browser = { channel: CHANNEL || "playwright chromium", headed: HEADED, version: await page.evaluate(() => navigator.userAgent.split(" ").filter((w) => w.startsWith("Chrome/")).join("")), viewport: [VW, VH], webgl: gl };
report.browser_memory_series = series;  // [seconds, renderer MB, gpu MB, all MB]
report.console_tail = log.slice(-40);
await writeFile(out, JSON.stringify(report, null, 2));
console.log(JSON.stringify({ ok: report.ok, browser: report.browser, engine_start_s: report.engine_start_s, error: report.error, total: report.total,
  memory_peak_mb: report.memory_peak_mb, browser_memory_peak_mb: report.browser_memory_peak_mb }));
// (A headed Chrome sometimes never answers the close: give it 10 s, then leave.)
await Promise.race([context.close(), new Promise((ok) => setTimeout(ok, 10000))]);
server.close();
try { rmSync(profile, { recursive: true, force: true }); } catch {}
process.exit(report.ok ? 0 : 1);
