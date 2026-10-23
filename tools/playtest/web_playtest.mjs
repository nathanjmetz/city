// Plays the browser build in Chromium (scripts/perf/playtest.gd does the
// playing) and saves its result, plus the browser's own memory (the page's
// renderer and GPU processes, which is what runs out on an 8 GB Mac).
//
// Run: node tools/playtest/web_playtest.mjs <exported web dir> <seconds> <out.json> [ws://host:port/CODE]
// The last, optional, plays in that region instead of alone.
// Needs Playwright (NODE_PATH pointing at a global install is fine).
import { createServer } from "node:http";
import { readFile, writeFile } from "node:fs/promises";
import { execSync } from "node:child_process";
import { extname, join } from "node:path";
import { createRequire } from "node:module";

// require() honours NODE_PATH, so a global Playwright works too.
const { chromium } = createRequire(import.meta.url)("playwright");

const [dir, seconds = "120", out = "playtest-web.json", region = ""] = process.argv.slice(2);
const TYPES = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm",
  ".pck": "application/octet-stream", ".png": "image/png" };

const server = createServer(async (req, res) => {
  let path = decodeURIComponent(new URL(req.url, "http://x").pathname);
  if (path === "/") path = "/index.html";
  try {
    const body = await readFile(join(dir, path));
    res.writeHead(200, { "Content-Type": TYPES[extname(path)] || "application/octet-stream",
      "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp" });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end();
  }
});
await new Promise((ok) => server.listen(0, ok));
const port = server.address().port;

// Resident memory of every Chromium process, in MB, by kind.
function browserMemory() {
  const mb = { renderer: 0, gpu: 0, all: 0 };
  try {
    for (const line of execSync("ps -eo rss=,args=", { encoding: "utf8" }).split("\n")) {
      if (!/chrom/i.test(line)) continue;
      const rss = parseInt(line.trim(), 10) / 1024;
      if (!rss) continue;
      mb.all += rss;
      if (line.includes("--type=renderer")) mb.renderer = Math.max(mb.renderer, rss);
      if (line.includes("--type=gpu-process")) mb.gpu = Math.max(mb.gpu, rss);
    }
  } catch {}
  return mb;
}

const browser = await chromium.launch({
  args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
    "--enable-precise-memory-info", "--disable-renderer-backgrounding",
    "--disable-background-timer-throttling", "--disable-backgrounding-occluded-windows"],
});
const page = await browser.newPage({ viewport: { width: 800, height: 450 } });
let result = null;
let crashed = "";
const log = [];
page.on("console", (m) => {
  const t = m.text();
  if (t.startsWith("PLAYTEST_RESULT ")) result = JSON.parse(t.slice(16));
  else if (log.length < 400) log.push(t);
});
page.on("crash", () => { crashed = "the page crashed (out of memory?)"; });
page.on("pageerror", (e) => log.push("pageerror: " + e.message));

const peak = { renderer: 0, gpu: 0, all: 0 };
const timer = setInterval(() => {
  const m = browserMemory();
  for (const k in peak) peak[k] = Math.max(peak[k], m[k]);
}, 2000);

const t0 = Date.now();
await page.goto(`http://localhost:${port}/?playtest=${seconds}` + (region ? `&region=${encodeURIComponent(region)}` : ""));
// The load, the build steps and the run, with room to spare.
const limit = (Number(seconds) + 600) * 1000;
while (!result && !crashed && Date.now() - t0 < limit) {
  await new Promise((ok) => setTimeout(ok, 1000));
}
clearInterval(timer);
const report = result || { ok: false, error: crashed || "no result before the time limit" };
report.browser_memory_peak_mb = Object.fromEntries(Object.entries(peak).map(([k, v]) => [k, Math.round(v)]));
report.wall_seconds = Math.round((Date.now() - t0) / 1000);
report.console_tail = log.slice(-40);
await writeFile(out, JSON.stringify(report, null, 2));
console.log(JSON.stringify({ ok: report.ok, error: report.error, total: report.total,
  memory_peak_mb: report.memory_peak_mb, browser_memory_peak_mb: report.browser_memory_peak_mb }));
await browser.close();
server.close();
process.exit(report.ok ? 0 : 1);
