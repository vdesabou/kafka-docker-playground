#!/usr/bin/env python3
"""HTML report of a 'playground connector benchmark' run.

Self-contained file (inline SVG drawn by a small script, no external resource), light and dark themes:
stat tiles, throughput / connect CPU / batch latency over time, history of the comparable runs, run details and
the samples as a table. For a source connector in steady mode, the end-to-end latency of its records (percentiles over
time, distribution, slowest records), from the latency csv of tools/benchmark-report/benchmark_latency.py.

    benchmark_report.py --result <run.json> --samples <run.csv> [--history <benchmark-history>]
                        [--warning <text>]... [--jfr <flight recorder analysis.json>] --output <report.html>

With a flight recorder analysis (tools/jfr-analyzer), a "Where the time goes" section follows the charts; in a
--connector-tag comparison (--runs), the analyses of the runs are compared by version. With --group-by shape, the runs
of a --shape sequence (bulk,update,delete) are compared by phase.
"""
import argparse
import csv
import html
import json
import os
import sys

# no __pycache__ in the repository
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "jfr-analyzer"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jfr_analyzer  # noqa: E402
import benchmark_latency  # noqa: E402


def load_samples(path, phase):
    samples = []
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            if row["phase"] != phase:
                continue

            def num(key):
                # columns are added over time: a sample file of an older version does not have them
                try:
                    return float(row.get(key))
                except (TypeError, ValueError):
                    return None

            samples.append({
                "time": row["timestamp"],
                "elapsed": num("elapsed_s"),
                "records": num("records"),
                "rate": num("rate_records_per_s"),
                "batch": num("batch_avg_ms"),
                "ratio": num("running_ratio"),
                "cpu": num("cpu_percent_of_one_core"),
                "lag": num("consumer_lag_max"),
                "epoch": num("epoch"),
            })
    return samples


def load_history(path, result):
    """Comparable runs (same example, connector, mode and shape), oldest first, ending with this run."""
    runs = []
    if path and os.path.exists(path):
        with open(path) as f:
            for line in f:
                try:
                    run = json.loads(line)
                except ValueError:
                    continue
                if all(run.get(k) == result.get(k) for k in ("test_file", "connector", "mode", "shape")) \
                        and run.get("lower_bound") is not True and run.get("incomplete") is not True and (run.get("records") or 0) > 0:
                    runs.append(run)
    # with --no-history, this run is not in the file
    if not runs or runs[-1].get("date") != result.get("date") or runs[-1].get("samples_csv") != result.get("samples_csv"):
        if result.get("lower_bound") is not True and result.get("incomplete") is not True and (result.get("records") or 0) > 0:
            runs.append(result)
    return runs[-20:]


def fmt_int(value):
    try:
        return f"{float(value):,.0f}"
    except (TypeError, ValueError):
        return "-"


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Benchmark of __CONNECTOR__</title>
<style>
.viz-root {
  color-scheme: light;
  --page: #f9f9f7; --surface-1: #fcfcfb; --text-primary: #0b0b0b; --text-secondary: #52514e; --text-muted: #898781;
  --grid: #e1e0d9; --axis: #c3c2b7; --border: rgba(11,11,11,0.10); --series-1: #2a78d6;
  --series-2: #eb6834; --series-3: #1baf7a; --series-4: #eda100; --series-5: #e87ba4; --series-6: #008300; --series-7: #6250d6; --series-8: #e34948;
  --good: #0ca30c; --good-text: #006300; --critical: #d03b3b; --warning: #fab219;
}
@media (prefers-color-scheme: dark) {
  :root:where(:not([data-theme="light"])) .viz-root {
    color-scheme: dark;
    --page: #0d0d0d; --surface-1: #1a1a19; --text-primary: #f0efec; --text-secondary: #c3c2b7; --text-muted: #898781;
    --grid: #2c2c2a; --axis: #383835; --border: rgba(255,255,255,0.10); --series-1: #3987e5;
    --series-2: #d95926; --series-3: #199e70; --series-4: #c98500; --series-5: #d55181; --series-6: #008300; --series-7: #9085e9; --series-8: #e66767;
    --good-text: #0ca30c;
  }
}
:root[data-theme="dark"] .viz-root {
  color-scheme: dark;
  --page: #0d0d0d; --surface-1: #1a1a19; --text-primary: #f0efec; --text-secondary: #c3c2b7; --text-muted: #898781;
  --grid: #2c2c2a; --axis: #383835; --border: rgba(255,255,255,0.10); --series-1: #3987e5;
    --series-2: #d95926; --series-3: #199e70; --series-4: #c98500; --series-5: #d55181; --series-6: #008300; --series-7: #9085e9; --series-8: #e66767;
  --good-text: #0ca30c;
}
* { box-sizing: border-box; }
body { margin: 0; }
.viz-root { background: var(--page); color: var(--text-primary); min-height: 100vh;
  font-family: system-ui, -apple-system, "Segoe UI", sans-serif; padding: 28px 32px 48px; }
header { display: flex; justify-content: space-between; align-items: flex-start; gap: 16px; }
h1 { font-size: 1.35rem; margin: 0 0 4px; font-weight: 600; }
h2 { font-size: 1rem; margin: 0 0 2px; font-weight: 600; }
.sub { color: var(--text-secondary); font-size: .875rem; margin: 0; }
a { color: var(--series-1); }
.theme-toggle { white-space: nowrap; flex-shrink: 0; font: inherit; font-size: .8rem; color: var(--text-secondary); background: var(--surface-1);
  border: 1px solid var(--border); border-radius: 6px; padding: 4px 10px; cursor: pointer; }
.tiles { display: grid; grid-template-columns: repeat(auto-fill, minmax(230px, 1fr)); gap: 12px; margin: 22px 0; }
.tile, .card { background: var(--surface-1); border: 1px solid var(--border); border-radius: 10px; }
.tile { padding: 14px 16px; }
.tile .label { color: var(--text-secondary); font-size: .8rem; }
.tile .value { font-size: 1.6rem; font-weight: 600; margin-top: 4px; font-variant-numeric: tabular-nums; white-space: nowrap; }
.tile .value.bad { color: var(--critical); }
.tile .unit { font-size: .85rem; font-weight: 400; color: var(--text-secondary); }
.tile .note { color: var(--text-muted); font-size: .78rem; margin-top: 4px; }
.delta-good { color: var(--good-text); } .delta-bad { color: var(--critical); }
.verdict { margin: 0 0 22px; padding: 12px 16px; border-left: 4px solid var(--sev); font-size: 1rem; font-weight: 500; }
.warnings { margin: 0 0 22px; padding: 12px 16px; list-style: none; }
.warnings li { font-size: .875rem; color: var(--text-primary); padding: 3px 0; }
.warnings li::before { content: "⚠️ "; }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(520px, 1fr)); gap: 16px; }
.card { padding: 16px 18px; position: relative; }
.card .sub { margin-bottom: 8px; }
svg { display: block; width: 100%; height: auto; overflow: visible; }
svg text { font-family: inherit; }
.tooltip { position: absolute; pointer-events: none; background: var(--surface-1); border: 1px solid var(--border);
  border-radius: 6px; padding: 6px 9px; font-size: .78rem; box-shadow: 0 2px 8px rgba(0,0,0,.12); display: none;
  white-space: nowrap; z-index: 2; }
.tooltip strong { font-size: .9rem; font-variant-numeric: tabular-nums; }
.legend { display: flex; gap: 16px; flex-wrap: wrap; font-size: .8rem; color: var(--text-secondary); margin: 2px 0 6px; }
.legend span::before { content: ""; display: inline-block; width: 10px; height: 10px; border-radius: 2px; background: var(--c); margin-right: 6px; vertical-align: -1px; }
.tooltip .key { display: inline-block; width: 12px; height: 2px; background: var(--series-1); vertical-align: middle; margin-right: 6px; }
.tooltip .muted { color: var(--text-secondary); }
table { border-collapse: collapse; width: 100%; font-size: .82rem; font-variant-numeric: tabular-nums; }
th, td { text-align: left; padding: 5px 10px; border-bottom: 1px solid var(--grid); }
th { color: var(--text-secondary); font-weight: 500; }
td.num, th.num { text-align: right; }
pre { margin: 0; font-family: 'SFMono-Regular', Consolas, Menlo, monospace; font-size: .8rem; white-space: pre-wrap; word-break: break-all; }
details { margin-top: 16px; } summary { cursor: pointer; font-weight: 600; font-size: .95rem; padding: 6px 0; }
.full { grid-column: 1 / -1; }
.empty { color: var(--text-muted); font-size: .875rem; padding: 24px 0; }
footer { color: var(--text-muted); font-size: .78rem; margin-top: 24px; }
__JFR_CSS__
</style>
</head>
<body>
<div class="viz-root">
<header>
  <div>
    <h1>🏎️ Benchmark of __CONNECTOR__</h1>
    <p class="sub">__SUBTITLE__</p>
    <p class="sub" id="example-link"></p>
  </div>
  <button class="theme-toggle" id="theme-toggle" type="button">Toggle theme</button>
</header>
<div class="tiles" id="tiles"></div>
__VERDICT__
__WARNINGS__
<div class="grid">
  <section class="card"><h2>🚀 Throughput</h2><p class="sub">records per second, per sample</p><div id="chart-rate"></div></section>
  <section class="card"><h2>🔥 Connect CPU</h2><p class="sub">% of one core, average of the workers running the tasks</p><div id="chart-cpu"></div></section>
  <section class="card"><h2>__BATCH_TITLE__</h2><p class="sub">average per task, ms</p><div id="chart-batch"></div></section>
  <section class="card"><h2>📜 Comparable runs</h2><p class="sub">records per second, same example, connector, mode and shape (benchmark-history); faded bars and * : another setup</p><div id="chart-history"></div></section>
  <section class="card" id="latency-card" hidden><h2>⏱️ End-to-end latency</h2><p class="sub" id="latency-sub"></p><div class="legend" id="latency-legend"></div><div id="chart-latency"></div></section>
  <section class="card" id="latency-hist-card" hidden><h2>📊 Latency distribution</h2><p class="sub">records per end-to-end latency range; grey: slower than p95 × 2, red: negative (clock skew)</p><div id="chart-latency-hist"></div></section>
</div>
__JFR__
<details open id="versions-section" hidden><summary>__GROUP_TITLE__</summary><div class="card"><table id="versions-table"></table></div></details>
<details id="latency-slowest-section" hidden><summary>🐢 Slowest records (end-to-end latency)</summary><div class="card"><table id="latency-slowest"></table></div></details>
<details open><summary>📋 Run details</summary><div class="card"><table id="details"></table></div></details>
<details open><summary>🖥️ Setup</summary><div class="card"><table id="setup"></table></div></details>
<details><summary>⚙️ Connector configuration (secrets masked)</summary><div class="card"><pre id="connector-config"></pre></div></details>
<details><summary>📜 Comparable runs (table)</summary><div class="card"><table id="history-table"></table></div></details>
<details><summary>📋 Samples (table)</summary><div class="card"><table id="samples-table"></table></div></details>
<footer>🛠️ Results are relative to the docker host they ran on: compare runs on the same machine only. Generated by playground connector benchmark.</footer>
</div>
<script type="application/json" id="data">__DATA__</script>
<script>
(function () {
  const data = JSON.parse(document.getElementById("data").textContent);
  const r = data.result, samples = data.samples, history = data.history, versions = data.versions || [];
  const comparison = versions.length > 0;
  // what the runs of a comparison are grouped by: connector versions (--connector-tag) or phases (--shape a,b,c)
  const groupKey = data.group_key || "plugin_version", groupNoun = data.group_noun || "version", groupTitle = data.group_title || "🆚 Connector versions";
  const root = document.documentElement;
  document.getElementById("theme-toggle").addEventListener("click", () => {
    const dark = root.dataset.theme ? root.dataset.theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
    root.dataset.theme = dark ? "light" : "dark";
  });

  const nf = new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 });
  const nf1 = new Intl.NumberFormat("en-US", { maximumFractionDigits: 1 });
  const el = (tag, attrs, text) => {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) e.setAttribute(k, v);
    if (text !== undefined) e.textContent = text;
    return e;
  };
  const svgEl = (tag, attrs) => {
    const e = document.createElementNS("http://www.w3.org/2000/svg", tag);
    for (const [k, v] of Object.entries(attrs || {})) e.setAttribute(k, v);
    return e;
  };
  // round axis: a 1/2/5 x 10^n step giving at most 5 intervals, and the max as a multiple of it
  const niceScale = (v) => {
    if (!(v > 0)) return { max: 1, step: 0.25 };
    const raw = v / 5, p = Math.pow(10, Math.floor(Math.log10(raw))), n = raw / p;
    const step = (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * p;
    return { max: Math.ceil(v / step - 1e-9) * step, step };
  };
  const compact = (v) => v >= 1e6 ? nf1.format(v / 1e6) + "M" : v >= 1e3 ? nf1.format(v / 1e3) + "k" : nf1.format(v);

  // setup of a run: what changes the throughput, to tell comparable runs apart
  const gib = b => b ? Math.floor(b / 1073741824) + " GiB" : "?";
  const setupKey = st => st ? JSON.stringify([st.host && st.host.cpu_model, st.host && st.host.cpus, st.engine && st.engine.cpus,
    st.engine && st.engine.memory_bytes, st.connect && st.connect.image, st.connect && st.connect.emulated,
    st.connect && st.connect.heap_max_bytes, st.connect && st.connect.workers, st.kafka && st.kafka.brokers, st.kafka && st.kafka.environment]) : null;
  const setupShort = st => st && st.host ? st.host.cpu_model + ", " + st.engine.name + " " + st.engine.cpus + " cpus / " + gib(st.engine.memory_bytes) +
    (st.connect && st.connect.emulated ? ", emulated" : "") : "unknown";
  const currentSetup = setupKey(r.setup);
  const sameSetup = h => !currentSetup || !h.setup || setupKey(h.setup) === currentSetup;

  // tiles
  const tiles = document.getElementById("tiles");
  function tile(label, value, unit, note, cls) {
    const t = el("div", { class: "tile" });
    t.appendChild(el("div", { class: "label" }, label));
    const v = el("div", { class: "value" + (cls ? " " + cls : "") }, value);
    if (unit) { v.appendChild(document.createTextNode(" ")); v.appendChild(el("span", { class: "unit" }, unit)); }
    t.appendChild(v);
    if (note) t.appendChild(el("div", { class: "note" }, note));
    tiles.appendChild(t);
  }
  tile(comparison ? "🚀 Last run (" + r[groupKey] + ")" : "🚀 Throughput", (r.lower_bound ? "≥ " : "") + nf.format(r.records_per_second), "records/s",
       r.rate_p50 !== "-" ? "p50 " + compact(+r.rate_p50) + " · p95 " + compact(+r.rate_p95) + " · min " + compact(+r.rate_min) : "");
  tile("⏱️ Duration", nf1.format(r.seconds), "s", r.incomplete ? "stopped by --max-wait" : r.mode === "drain" ? "time to process the backlog" : "measure, after the warm-up");
  tile("🧾 Records", nf.format(r.records), "", r.incomplete ? "of " + nf.format(r.expected_records) + ": the drain did not finish (--max-wait)" :
       r.mode === "drain" ? "backlog, loaded in " + r.load_seconds + " s" : "processed during the measure", r.incomplete ? "bad" : undefined);
  const lat = r.latency || {};
  const latencyText = v => v === null || v === undefined ? "-" : Math.abs(v) >= 10000 ? nf1.format(v / 1000) + " s" : nf.format(v) + " ms";
  if (lat.enabled) {
    tile("⏱️ End-to-end latency p95", latencyText(lat.p95_ms), "", "p50 " + latencyText(lat.p50_ms) + " · p99 " + latencyText(lat.p99_ms) + " · max " + latencyText(lat.max_ms));
  } else if (r.type === "source" && r.mode === "steady" && lat.reason) {
    tile("⏱️ End-to-end latency", "–", "", lat.reason);
  }
  const previous = history.length > 1 ? history[history.length - 2] : null;
  const versionColor = version => "var(--series-" + (versions.findIndex(v => v.version === version) % 8 + 1) + ")";
  if (comparison) {
    const measured = versions.filter(v => v.mean !== null);
    if (measured.length) {
      const best = measured.reduce((a, b) => (b.mean > a.mean ? b : a));
      const d = best.delta;
      tile("🏆 Fastest " + groupNoun, best.version, "", nf.format(best.mean) + " records/s (mean of " + best.rates.length + " run(s))" +
           (d !== null && Math.abs(d) >= 1 ? ", " + (d > 0 ? "+" : "") + nf.format(d) + "% vs " + measured[0].version : ""));
    } else {
      tile("🏆 Fastest " + groupNoun, "–", "", "only lower bounds: increase --nb-records");
    }
  } else if (previous && previous.records_per_second > 0) {
    const delta = (r.records_per_second - previous.records_per_second) / previous.records_per_second * 100;
    const same = Math.abs(delta) < 5;
    tile("📜 Vs previous run", (same ? "≈ " + (delta >= 0 ? "+" : "") : delta > 0 ? "▲ +" : "▼ ") + nf.format(delta) + "%",
         same ? "within ±5%" : delta > 0 ? "faster" : "slower",
         nf.format(previous.records_per_second) + " records/s on " + previous.date.replace("T", " ").replace("Z", " UTC"),
         same ? "" : delta > 0 ? "delta-good" : "delta-bad");
  } else {
    tile("📜 Vs previous run", "–", "", "🆕 no comparable run in benchmark-history yet");
  }

  // charts
  const W = 560, H = 250, L = 58, R = 16, T = 14, B = 34;
  function yGrid(svg, ys, yfmt) {
    for (let v = 0; v <= ys.max + 1e-9; v += ys.step) {
      const y = T + (H - T - B) * (1 - v / ys.max);
      svg.appendChild(svgEl("line", { x1: L, x2: W - R, y1: y, y2: y, stroke: v ? "var(--grid)" : "var(--axis)", "stroke-width": 1 }));
      const t = svgEl("text", { x: L - 8, y: y + 4, "text-anchor": "end", "font-size": 11, fill: "var(--text-muted)" });
      t.textContent = yfmt(v);
      svg.appendChild(t);
    }
  }
  function axes(svg, xs, ys, xlabel, yfmt) {
    yGrid(svg, ys, yfmt);
    for (let v = 0; v <= xs.max + 1e-9; v += xs.step) {
      const x = L + (W - L - R) * v / xs.max;
      const t = svgEl("text", { x, y: H - B + 18, "text-anchor": "middle", "font-size": 11, fill: "var(--text-muted)" });
      t.textContent = nf1.format(v) + (v + xs.step > xs.max + 1e-9 ? " " + xlabel : "");
      svg.appendChild(t);
    }
  }
  function lineChart(id, key, unitLabel, yfmt, reference, data) {
    const host = document.getElementById(id);
    const pts = (data || samples).filter(s => s[key] !== null && s.elapsed !== null);
    if (pts.length === 0) {
      const fullyManaged = r.setup && r.setup.connect && r.setup.connect.fully_managed;
      host.appendChild(el("div", { class: "empty" }, fullyManaged ? "☁️ not available for a fully managed connector (no JMX)" : "🤷 no sample for this metric"));
      return;
    }
    const xs = niceScale(Math.max(...pts.map(p => p.elapsed)));
    const ys = niceScale(Math.max(...pts.map(p => p[key]), reference ? reference.value : 0));
    const xmax = xs.max, ymax = ys.max;
    const sx = x => L + (W - L - R) * x / xmax, sy = y => T + (H - T - B) * (1 - y / ymax);
    const svg = svgEl("svg", { viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": unitLabel + " over time" });
    axes(svg, xs, ys, "s", yfmt);
    if (reference && reference.value > 0) {
      const y = sy(reference.value);
      svg.appendChild(svgEl("line", { x1: L, x2: W - R, y1: y, y2: y, stroke: "var(--text-secondary)", "stroke-width": 1, "stroke-dasharray": "4 4" }));
      const t = svgEl("text", { x: W - R, y: y - 6, "text-anchor": "end", "font-size": 11, fill: "var(--text-secondary)" });
      t.textContent = reference.label;
      svg.appendChild(t);
    }
    svg.appendChild(svgEl("path", { d: pts.map((p, i) => (i ? "L" : "M") + sx(p.elapsed).toFixed(1) + "," + sy(p[key]).toFixed(1)).join(""),
      fill: "none", stroke: "var(--series-1)", "stroke-width": 2, "stroke-linejoin": "round", "stroke-linecap": "round" }));
    if (pts.length <= 40) {
      for (const p of pts) svg.appendChild(svgEl("circle", { cx: sx(p.elapsed), cy: sy(p[key]), r: 4, fill: "var(--series-1)", stroke: "var(--surface-1)", "stroke-width": 2 }));
    }
    const cross = svgEl("line", { y1: T, y2: H - B, stroke: "var(--text-muted)", "stroke-width": 1, visibility: "hidden" });
    svg.appendChild(cross);
    const hit = svgEl("rect", { x: L, y: T, width: W - L - R, height: H - T - B, fill: "transparent" });
    svg.appendChild(hit);
    host.appendChild(svg);
    const tip = el("div", { class: "tooltip" });
    host.parentElement.appendChild(tip);
    function show(evt) {
      const box = svg.getBoundingClientRect(), scale = W / box.width;
      const x = (evt.clientX - box.left) * scale;
      let best = pts[0];
      for (const p of pts) if (Math.abs(sx(p.elapsed) - x) < Math.abs(sx(best.elapsed) - x)) best = p;
      cross.setAttribute("x1", sx(best.elapsed)); cross.setAttribute("x2", sx(best.elapsed)); cross.setAttribute("visibility", "visible");
      tip.replaceChildren();
      tip.appendChild(el("span", { class: "key" }));
      tip.appendChild(el("strong", {}, nf1.format(best[key])));
      tip.appendChild(document.createTextNode(" " + unitLabel));
      tip.appendChild(el("br"));
      tip.appendChild(el("span", { class: "muted" }, nf1.format(best.elapsed) + " s · " + best.time));
      tip.style.display = "block";
      const host_box = host.parentElement.getBoundingClientRect();
      const px = box.left - host_box.left + sx(best.elapsed) / scale;
      tip.style.left = Math.min(px + 12, host_box.width - tip.offsetWidth - 8) + "px";
      tip.style.top = (box.top - host_box.top + sy(best[key]) / scale - tip.offsetHeight - 10) + "px";
    }
    hit.addEventListener("pointermove", show);
    hit.addEventListener("pointerleave", () => { tip.style.display = "none"; cross.setAttribute("visibility", "hidden"); });
  }
  lineChart("chart-rate", "rate", "records/s", compact,
            { value: r.records_per_second, label: (r.lower_bound ? "≥ " : "") + "average " + compact(r.records_per_second) });
  // a fully managed connector has no cpu: its records per minute in the Metrics API instead
  const ma = r.metrics_api;
  if (ma && ma.enabled && ma.records_per_minute.some(p => p.records > 0)) {
    const card = document.getElementById("chart-cpu").parentElement;
    card.querySelector("h2").textContent = "☁️ Records per minute (Metrics API)";
    card.querySelector(".sub").textContent = ma.metric + " of the connector, one point per minute (seconds since its first minute with records)";
    const active = ma.records_per_minute.filter(p => p.records > 0);
    const t0 = active[0].epoch, t1 = active[active.length - 1].epoch;
    lineChart("chart-cpu", "records", "records per minute", v => nf.format(v), null,
      ma.records_per_minute.filter(p => p.epoch >= t0 && p.epoch <= t1).map(p => ({ elapsed: p.epoch - t0, records: p.records })));
  } else {
    lineChart("chart-cpu", "cpu", "% of one core", v => nf.format(v) + "%");
  }
  lineChart("chart-batch", "batch", "ms", v => nf1.format(v));

  // end-to-end latency: p50 / p95 / p99 per time bucket of the measure, histogram, slowest records
  (function () {
    const lp = data.latency;
    if (!lat.enabled || !lp) return;
    document.getElementById("latency-card").hidden = false;
    document.getElementById("latency-hist-card").hidden = false;
    document.getElementById("latency-sub").textContent = "kafka record timestamp − " + lat.field + " (" + lat.field_source + "), p50 / p95 / p99 per " +
      lp.bucket_s + " s of the measure, " + nf.format(lat.records) + " records";
    const series = [["p50", "var(--series-1)"], ["p95", "var(--series-2)"], ["p99", "var(--series-3)"]];
    const legend = document.getElementById("latency-legend");
    series.forEach(([k, c]) => { const item = el("span", {}, k); item.style.setProperty("--c", c); legend.appendChild(item); });
    const host = document.getElementById("chart-latency");
    const pts = lp.buckets;
    // same x axis as the charts over time above
    const xs = niceScale(Math.max(...pts.map(p => p.elapsed), ...samples.filter(s => s.elapsed !== null).map(s => s.elapsed), 1));
    const ys = niceScale(Math.max(...pts.map(p => p.p99), 1));
    const sx = x => L + (W - L - R) * x / xs.max, sy = y => T + (H - T - B) * (1 - Math.max(0, y) / ys.max);
    const svg = svgEl("svg", { viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": "end-to-end latency over time" });
    axes(svg, xs, ys, "s", latencyText);
    for (const [k, c] of series) {
      // no line across a gap of more than 2 buckets (a measure read in slices)
      svg.appendChild(svgEl("path", { d: pts.map((p, i) => (i && p.elapsed - pts[i - 1].elapsed <= 2.5 * lp.bucket_s ? "L" : "M") + sx(p.elapsed).toFixed(1) + "," + sy(p[k]).toFixed(1)).join(""),
        fill: "none", stroke: c, "stroke-width": 2, "stroke-linejoin": "round", "stroke-linecap": "round" }));
      if (pts.length <= 40) for (const p of pts) svg.appendChild(svgEl("circle", { cx: sx(p.elapsed), cy: sy(p[k]), r: 4, fill: c, stroke: "var(--surface-1)", "stroke-width": 2 }));
    }
    const cross = svgEl("line", { y1: T, y2: H - B, stroke: "var(--text-muted)", "stroke-width": 1, visibility: "hidden" });
    svg.appendChild(cross);
    const hit = svgEl("rect", { x: L, y: T, width: W - L - R, height: H - T - B, fill: "transparent" });
    svg.appendChild(hit);
    host.appendChild(svg);
    const tip = el("div", { class: "tooltip" });
    host.parentElement.appendChild(tip);
    hit.addEventListener("pointermove", evt => {
      const box = svg.getBoundingClientRect(), scale = W / box.width, x = (evt.clientX - box.left) * scale;
      let best = pts[0];
      for (const p of pts) if (Math.abs(sx(p.elapsed) - x) < Math.abs(sx(best.elapsed) - x)) best = p;
      cross.setAttribute("x1", sx(best.elapsed)); cross.setAttribute("x2", sx(best.elapsed)); cross.setAttribute("visibility", "visible");
      tip.replaceChildren();
      tip.appendChild(el("span", { class: "muted" }, nf1.format(best.elapsed) + " s · " + nf.format(best.n) + " records"));
      for (const [k, c] of series.slice().reverse()) {
        tip.appendChild(el("br"));
        const key = el("span", { class: "key" }); key.style.background = c; tip.appendChild(key);
        tip.appendChild(document.createTextNode(k + " "));
        tip.appendChild(el("strong", {}, latencyText(best[k])));
      }
      tip.style.display = "block";
      const hbox = host.parentElement.getBoundingClientRect();
      tip.style.left = Math.min(box.left - hbox.left + sx(best.elapsed) / scale + 12, hbox.width - tip.offsetWidth - 8) + "px";
      tip.style.top = (box.top - hbox.top + sy(best.p99) / scale - tip.offsetHeight - 10) + "px";
    });
    hit.addEventListener("pointerleave", () => { tip.style.display = "none"; cross.setAttribute("visibility", "hidden"); });

    // histogram
    const hhost = document.getElementById("chart-latency-hist");
    const bins = lp.histogram;
    const hsvg = svgEl("svg", { viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": "distribution of the end-to-end latency" });
    const hys = niceScale(Math.max(...bins.map(b => b.n), 1));
    yGrid(hsvg, hys, v => compact(v));
    const n = bins.length, slot = (W - L - R) / n, bw = Math.max(1, slot - 2);
    const hsy = y => T + (H - T - B) * (1 - y / hys.max);
    const htip = el("div", { class: "tooltip" });
    hhost.parentElement.appendChild(htip);
    const every = Math.ceil(n / 6);
    bins.forEach((b, i) => {
      const x = L + slot * i + 1, y = hsy(b.n), base = hsy(0), rad = Math.min(4, bw / 2, base - y);
      const g = svgEl("g");
      g.appendChild(svgEl("rect", { x: L + slot * i, y: T, width: slot, height: H - T - B, fill: "transparent" }));
      if (b.n) g.appendChild(svgEl("path", { d: `M${x},${base}V${y + rad}Q${x},${y} ${x + rad},${y}H${x + bw - rad}Q${x + bw},${y} ${x + bw},${y + rad}V${base}Z`,
        fill: b.tail ? "var(--text-muted)" : b.to <= 0 ? "var(--critical)" : "var(--series-1)" }));
      if (b.tail && b.n) {
        const t = svgEl("text", { x: x + bw / 2, y: y - 6, "text-anchor": "middle", "font-size": 11, fill: "var(--text-secondary)" });
        t.textContent = "> " + latencyText(b.from);
        hsvg.appendChild(t);
      }
      if (!b.tail && i % every === 0) {
        const t = svgEl("text", { x: L + slot * i, y: H - B + 18, "text-anchor": "middle", "font-size": 11, fill: "var(--text-muted)" });
        t.textContent = latencyText(b.from);
        hsvg.appendChild(t);
      }
      g.addEventListener("pointermove", () => {
        htip.replaceChildren();
        htip.appendChild(el("strong", {}, nf.format(b.n)));
        htip.appendChild(document.createTextNode(" records"));
        htip.appendChild(el("br"));
        htip.appendChild(el("span", { class: "muted" }, latencyText(b.from) + " → " + latencyText(b.to) + (b.tail ? " (slower than p95 × 2)" : "")));
        htip.style.display = "block";
        const sbox = hsvg.getBoundingClientRect(), hb = hhost.parentElement.getBoundingClientRect(), scale = W / sbox.width;
        htip.style.left = Math.max(8, Math.min(sbox.left - hb.left + (x + bw / 2) / scale - htip.offsetWidth / 2, hb.width - htip.offsetWidth - 8)) + "px";
        htip.style.top = (sbox.top - hb.top + y / scale - htip.offsetHeight - 10) + "px";
      });
      g.addEventListener("pointerleave", () => htip.style.display = "none");
      hsvg.appendChild(g);
    });
    hhost.appendChild(hsvg);
    if (lp.slowest.length) {
      document.getElementById("latency-slowest-section").hidden = false;
    }
  })();

  // history bars
  (function () {
    const host = document.getElementById("chart-history");
    if (history.length === 0) { host.appendChild(el("div", { class: "empty" }, "🆕 no comparable run yet")); return; }
    const ys = niceScale(Math.max(...history.map(h => h.records_per_second)));
    const ymax = ys.max;
    const n = history.length, slot = (W - L - R) / n, bw = Math.min(56, slot - 2);
    const sy = y => T + (H - T - B) * (1 - y / ymax);
    const svg = svgEl("svg", { viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": "throughput of the comparable runs" });
    yGrid(svg, ys, compact);
    const tip = el("div", { class: "tooltip" });
    host.parentElement.appendChild(tip);
    history.forEach((h, i) => {
      const x = L + slot * i + (slot - bw) / 2, y = sy(h.records_per_second), base = sy(0), rad = Math.min(4, bw / 2);
      const bar = svgEl("path", {
        d: `M${x},${base}V${y + rad}Q${x},${y} ${x + rad},${y}H${x + bw - rad}Q${x + bw},${y} ${x + bw},${y + rad}V${base}Z`,
        fill: comparison ? versionColor(h[groupKey]) : "var(--series-1)", tabindex: 0,
        "fill-opacity": (comparison && h.lower_bound) || !sameSetup(h) ? 0.35 : 1
      });
      svg.appendChild(bar);
      const current = !comparison && i === n - 1;
      if (current || comparison || n <= 8) {
        const t = svgEl("text", { x: x + bw / 2, y: y - 6, "text-anchor": "middle", "font-size": 11, fill: "var(--text-secondary)" });
        t.textContent = compact(h.records_per_second);
        svg.appendChild(t);
      }
      const lab = svgEl("text", { x: x + bw / 2, y: H - B + 16, "text-anchor": "middle", "font-size": 10.5,
        fill: current ? "var(--text-primary)" : "var(--text-muted)", "font-weight": current ? 600 : 400 });
      lab.textContent = comparison ? h[groupKey] + (h.round > 1 || versions.some(v => v.runs > 1) ? " · r" + h.round : "") : current ? "this run" : (h.date || "").slice(5, 16).replace("T", " ") + (sameSetup(h) ? "" : " *");
      svg.appendChild(lab);
      const showTip = () => {
        tip.replaceChildren();
        tip.appendChild(el("strong", {}, (h.lower_bound ? "≥ " : "") + nf.format(h.records_per_second)));
        tip.appendChild(document.createTextNode(" records/s" + (comparison ? " · " + groupNoun + " " + h[groupKey] + ", round " + h.round : "") +
          (h.lower_bound ? " (lower bound, not in the mean)" : "")));
        tip.appendChild(el("br"));
        tip.appendChild(el("span", { class: "muted" }, (h.date || "").replace("T", " ").replace("Z", " UTC")));
        tip.appendChild(el("br"));
        tip.appendChild(el("span", { class: "muted" }, h.plugin_version + " · CP " + h.cp_tag + " · " + h.tasks + " task(s) · " + nf.format(h.records) + " records"));
        if (h.latency && h.latency.enabled) {
          tip.appendChild(el("br"));
          tip.appendChild(el("span", { class: "muted" }, "end-to-end latency p95 " + latencyText(h.latency.p95_ms) + " · p99 " + latencyText(h.latency.p99_ms)));
        }
        tip.appendChild(el("br"));
        tip.appendChild(el("span", { class: "muted" }, (sameSetup(h) ? "" : "other setup: ") + setupShort(h.setup)));
        tip.style.display = "block";
        const sbox = svg.getBoundingClientRect(), hbox = host.parentElement.getBoundingClientRect(), scale = W / sbox.width;
        tip.style.left = Math.max(8, Math.min(sbox.left - hbox.left + (x + bw / 2) / scale - tip.offsetWidth / 2, hbox.width - tip.offsetWidth - 8)) + "px";
        tip.style.top = (sbox.top - hbox.top + y / scale - tip.offsetHeight - 10) + "px";
      };
      bar.addEventListener("pointerenter", showTip); bar.addEventListener("focus", showTip);
      bar.addEventListener("pointerleave", () => tip.style.display = "none"); bar.addEventListener("blur", () => tip.style.display = "none");
    });
    host.appendChild(svg);
  })();

  // tables
  function fillTable(id, header, rows) {
    const table = document.getElementById(id);
    const tr = el("tr");
    header.forEach(([h, num]) => tr.appendChild(el("th", num ? { class: "num" } : {}, h)));
    table.appendChild(tr);
    rows.forEach(row => {
      const tr = el("tr");
      row.forEach((c, i) => tr.appendChild(el("td", header[i][1] ? { class: "num" } : {}, c === null || c === undefined ? "-" : String(c))));
      table.appendChild(tr);
    });
  }
  fillTable("details", [["Property"], ["Value"]], [
    ["connector", r.connector + " (" + r.type + ", " + r.tasks + " task(s))"],
    ["connector class", r.connector_class], ["plugin version", r.plugin_version], ["CP version", r.cp_tag],
    ["example", r.test_file], ["mode", r.mode], ["shape", r.shape],
    ["records", nf.format(r.records)], ["duration", r.seconds + " s"],
    ["throughput", (r.lower_bound ? "≥ " : "") + nf1.format(r.records_per_second) + " records/s"],
    ...(r.metrics_api && r.metrics_api.enabled ? [["Metrics API (" + r.metrics_api.metric + ")",
      (r.metrics_api.steady_records_per_second === null ? "no full minute during the measure" :
        nf1.format(r.metrics_api.steady_records_per_second) + " records/s steady, median of " + r.metrics_api.full_minutes + " full minute(s)") +
      (r.metrics_api.batch_size_avg === null ? "" : ", " + nf1.format(r.metrics_api.batch_size_avg) + " records per batch") +
      "; records per minute: " + r.metrics_api.records_per_minute.filter(p => p.records > 0)
        .map(p => new Date(p.epoch * 1000).toISOString().slice(11, 16) + " " + nf.format(p.records)).join(" · ")]] : []),
    ["batch avg", r.batch_avg_ms + " ms"], ["running ratio avg", r.running_ratio],
    ["connect cpu avg / max", r.cpu_percent_of_one_core_avg + "% / " + r.cpu_percent_of_one_core_max + "% of one core" +
      (r.cpu_percent_of_available_avg !== undefined ? " (" + r.cpu_percent_of_available_avg + "% of the cpus available)" : "")],
    ["gc pauses", r.gc_percent === undefined || r.gc_percent === "-" ? "-" : r.gc_percent + "% of the time"],
    ["records per task", r.task_shares],
    ["dlq / dropped records", r.dlq_records === undefined ? "-" : r.dlq_records + " sent to the dlq" + (r.skipped_records === "-" ? "" : ", " + r.skipped_records + " dropped without dlq")],
    ["load", r.load_seconds === "-" ? "-" : r.load_seconds + " s"],
    ["records in topics", r.topic_records_delta === "-" ? "-" : "+" + nf.format(+r.topic_records_delta)],
    ...(r.type === "source" && r.latency ? [["end-to-end latency", lat.enabled ?
      "p50 " + latencyText(lat.p50_ms) + " · p95 " + latencyText(lat.p95_ms) + " · p99 " + latencyText(lat.p99_ms) + " · max " + latencyText(lat.max_ms) +
      " (kafka timestamp − " + lat.field + ", " + nf.format(lat.records) + " records" + (lat.csv ? ", " + lat.csv : "") + ")" : lat.reason]] : []),
    ["date", r.date], ["samples", r.samples_csv]
  ].filter(row => !(r.setup && r.setup.connect && r.setup.connect.fully_managed) ||
    !(["running ratio avg", "connect cpu avg / max", "gc pauses", "records per task"].includes(row[0]) ||
      (row[0] === "batch avg" && r.batch_avg_ms === "-") || (row[0] === "dlq / dropped records" && r.dlq_records === "-"))));
  const withLatency = history.some(h => h.latency && h.latency.enabled);
  fillTable("history-table", [["date"], ["records/s", 1], ...(withLatency ? [["latency p95", 1]] : []), ["records", 1], ["seconds", 1], ["plugin"], ["CP"], ["tasks", 1], ["setup"]],
    history.slice().reverse().map(h => [h.date, nf1.format(h.records_per_second),
      ...(withLatency ? [h.latency && h.latency.enabled ? latencyText(h.latency.p95_ms) : "-"] : []), nf.format(h.records), h.seconds, h.plugin_version, h.cp_tag, h.tasks,
      (sameSetup(h) ? "" : "≠ ") + setupShort(h.setup)]));
  if (lat.enabled && data.latency) {
    fillTable("latency-slowest", [["latency", 1], ["elapsed s", 1], ["topic"], ["partition", 1], ["offset", 1], ["kafka timestamp"]],
      data.latency.slowest.map(x => [latencyText(x.latency_ms), nf1.format(x.elapsed_s), x.topic, x.partition, x.offset, new Date(x.kafka_ts_ms).toISOString().replace("T", " ").replace("Z", " UTC")]));
  }
  if (comparison) {
    document.getElementById("versions-section").hidden = false;
    const f1 = x => x === null ? "-" : nf1.format(x);
    const versionsLatency = versions.some(v => v.latency_p95 !== null && v.latency_p95 !== undefined);
    fillTable("versions-table", [[groupNoun], ["runs", 1], ["lower bounds", 1], ["records/s (mean)", 1], ["min", 1], ["max", 1], ["vs first " + groupNoun, 1],
      ...(versionsLatency ? [["latency p95 (mean)", 1]] : [])],
      versions.map(v => [v.version, v.runs, v.lower_bounds, f1(v.mean), f1(v.min), f1(v.max),
        v.delta === null ? "-" : (v.delta > 0 ? "+" : "") + nf.format(v.delta) + "%",
        ...(versionsLatency ? [v.latency_p95 === null ? "-" : latencyText(v.latency_p95)] : [])]));
    document.querySelector("#chart-history").previousElementSibling.textContent = "records per second of each run, in run order; faded: lower bound, not in the mean";
    const legend = el("div", { class: "legend" });
    versions.forEach(v => { const item = el("span", {}, v.version); item.style.setProperty("--c", versionColor(v.version)); legend.appendChild(item); });
    document.querySelector("#chart-history").before(legend);
    document.querySelector("#chart-history").parentElement.querySelector("h2").textContent = groupTitle;
  }
  // links to the example on github, at the commit it ran with and on the default branch
  function exampleLinks(st) {
    const pg = (st && st.playground) || {};
    if (!pg.repo_url || !pg.repo_path || !pg.repo_url.startsWith("https://github.com/")) return null;
    const span = el("span");
    const link = (text, href) => { const a = el("a", { href: href, target: "_blank", rel: "noopener" }, text); span.appendChild(a); };
    span.appendChild(el("code", {}, pg.repo_path));
    span.appendChild(document.createTextNode(" · "));
    if (pg.repo_commit) {
      link("at commit " + pg.repo_commit.slice(0, 10), pg.repo_url + "/blob/" + pg.repo_commit + "/" + pg.repo_path);
      span.appendChild(document.createTextNode(" · "));
    }
    link("latest version", pg.repo_url + "/blob/HEAD/" + pg.repo_path);
    span.appendChild(document.createTextNode(" · "));
    link("folder", pg.repo_url + "/tree/HEAD/" + pg.repo_path.slice(0, pg.repo_path.lastIndexOf("/")));
    if (pg.repo_dirty) span.appendChild(document.createTextNode(" (ran with local changes: the commit link may differ from what ran)"));
    return span;
  }
  // link to the documentation of the connector (documentation_url of the plugin manifest)
  function documentationLink(st) {
    const url = st && st.connector && st.connector.documentation_url;
    if (!url || !/^https?:/.test(url)) return null;
    return el("a", { href: url, target: "_blank", rel: "noopener" }, "connector documentation");
  }
  const headerLinks = exampleLinks(r.setup);
  if (headerLinks) document.getElementById("example-link").appendChild(headerLinks);
  const headerDoc = documentationLink(r.setup);
  if (headerDoc) {
    const line = document.getElementById("example-link");
    if (line.childNodes.length) line.appendChild(document.createTextNode(" · "));
    line.appendChild(headerDoc);
  }
  // grafana of the environment: the dashboards at the time of the run(s), where the measure is annotated
  if ((data.grafana || []).length) {
    const line = document.getElementById("example-link");
    if (line.childNodes.length) line.appendChild(el("br"));
    line.appendChild(document.createTextNode("📊 Grafana: "));
    data.grafana.forEach((g, i) => {
      if (i) line.appendChild(document.createTextNode(" · "));
      line.appendChild(el("a", { href: g.url, target: "_blank", rel: "noopener" }, g.title));
    });
  }

  // setup of this run
  const st = r.setup || {};
  const o = (v, unit) => v === undefined || v === null || v === "" ? "-" : v + (unit || "");
  if (st.host) {
    fillTable("setup", [["Component"], ["Details"]], [
      ["host", o(st.host.os) + " " + o(st.host.arch) + ", " + o(st.host.cpu_model) + ", " + o(st.host.cpus) + " cpus, " + gib(st.host.memory_bytes)],
      ["container engine", o(st.engine.name) + " " + o(st.engine.version) + " (" + o(st.engine.os) + "), " + o(st.engine.cpus) + " cpus, " + gib(st.engine.memory_bytes)],
      // a fully managed connector runs in Confluent Cloud: only the load runs on this host
      ...(st.connect.fully_managed ? [
        ["connect", "fully managed connector, Confluent Cloud (records counted from " +
          (r.type === "sink" ? "the offsets committed by its consumer group, at each offset commit" : "the end offsets of the topics") + ", no JMX)"]
      ] : [
        ["connect image", o(st.connect.image) + " (" + o(st.connect.image_arch) + (st.connect.emulated ? ", EMULATED on " + st.host.arch : ", native") + ")"],
        ["connect workers", o(st.connect.workers)],
        ["connect jvm", o(st.connect.jvm_version) + ", " + o(st.connect.jvm_cpus) + " cpus available, heap max " + gib(st.connect.heap_max_bytes) +
          (st.connect.heap_opts ? " (KAFKA_HEAP_OPTS " + st.connect.heap_opts + ")" : "")],
        ["kafka", o(st.kafka.brokers) + " broker(s), " + (st.kafka.kraft ? "kraft" : "zookeeper") + ", environment " + o(st.kafka.environment) + ", CP " + o(r.cp_tag)]
      ]),
      ["connector", o(r.connector_class) + " " + o(r.plugin_version) + ", " + o(r.tasks) + " task(s)"],
      ["playground", o(st.playground.test_file) + " at commit " + o(st.playground.commit) + (st.playground.dirty ? " (with local changes)" : "")]
    ]);
    const rows = document.querySelectorAll("#setup tr");
    const links = exampleLinks(st);
    if (links) {
      const last = rows[rows.length - 1].children[1];
      last.textContent = "";
      last.appendChild(links);
    }
    const doc = documentationLink(st);
    if (doc) {
      // the "connector" row is the second to last
      const cell = rows[rows.length - 2].children[1];
      cell.appendChild(document.createTextNode(" · "));
      cell.appendChild(doc);
    }
    document.getElementById("connector-config").textContent = JSON.stringify(st.connector_config || {}, null, 2);
  } else {
    fillTable("setup", [["Component"], ["Details"]], [["setup", "not recorded for this run"]]);
    document.getElementById("connector-config").textContent = "not recorded for this run";
  }
  fillTable("samples-table", [["time"], ["elapsed s", 1], ["records", 1], ["records/s", 1], ["batch ms", 1], ["running ratio", 1], ["cpu %", 1], ["consumer lag max", 1]],
    samples.map(s => [s.time, s.elapsed, s.records === null ? null : nf.format(s.records), s.rate === null ? null : nf1.format(s.rate), s.batch, s.ratio, s.cpu, s.lag === null ? null : nf.format(s.lag)]));
})();
</script>
__JFR_JS__
</body>
</html>
"""


def verdict(result, history, versions, warnings, jfr_findings, group_noun="version"):
    """one friendly sentence at the top of the report, from what the report shows below"""
    parts = []
    severity = "var(--good)"
    if versions:
        measured = [v for v in versions if v["mean"] is not None]
        if measured:
            best = max(measured, key=lambda v: v["mean"])
            delta = best["delta"]
            parts.append(f"🏆 {best['version']} is the fastest{'' if group_noun == 'version' else ' ' + group_noun} ({best['mean']:,.0f} records/s"
                         + (f", {delta:+.0f}% vs {measured[0]['version']}" if delta is not None and abs(delta) >= 1 else "") + ")")
        else:
            parts.append(f"⚠️ only lower bounds: increase --nb-records to compare the {group_noun}s")
            severity = "var(--warning)"
    else:
        parts.append(f"🚀 {'≥ ' if result.get('lower_bound') else ''}{result.get('records_per_second') or 0:,.0f} records/s")
        latency = result.get("latency") or {}
        if latency.get("enabled"):
            parts.append(f"⏱️ end-to-end latency p95 {latency['p95_ms']:,.0f} ms")
        if result.get("incomplete"):
            parts.append(f"🛑 the drain did not finish: {result.get('records') or 0:,} of {result.get('expected_records') or 0:,} records")
            severity = "var(--critical)"
        previous = history[-2] if len(history) > 1 else None
        if previous and previous.get("records_per_second"):
            delta = (result["records_per_second"] - previous["records_per_second"]) / previous["records_per_second"] * 100
            parts.append("≈ same as the previous run" if abs(delta) < 5 else f"{'▲' if delta > 0 else '▼'} {abs(delta):.0f}% "
                         f"{'faster' if delta > 0 else 'slower'} than the previous run")
    if warnings:
        parts.append(f"⚠️ {len(warnings)} warning{'s' if len(warnings) > 1 else ''} below")
        if severity == "var(--good)":
            severity = "var(--warning)"
    top = next((f for f in jfr_findings if f.get("severity") in ("critical", "warning")), None)
    if top:
        parts.append("🛩️ " + top["title"].rstrip("."))
        if top["severity"] == "critical":
            severity = "var(--critical)"
        elif severity == "var(--good)":
            severity = "var(--warning)"
    return f'<div class="card verdict" style="--sev: {severity}">{html.escape(" · ".join(parts))}</div>'


def grafana_links(runs):
    """links to the grafana dashboards of the runs, from the start of the first measure to the end of the last one"""
    runs = [r for r in runs if (r.get("grafana") or {}).get("enabled") and r.get("measure_from_ms") and r.get("measure_to_ms")]
    if not runs:
        return []
    start = min(r["measure_from_ms"] for r in runs) - 30000
    end = max(r["measure_to_ms"] for r in runs) + 30000
    return [{"title": d["title"], "url": "http://localhost:3000/d/%s?orgId=1&from=%d&to=%d" % (d["uid"], start, end)}
            for d in runs[-1]["grafana"].get("dashboards", []) if d.get("uid")]


def jfr_comparison(runs, versions, group_key="plugin_version", group_noun="version"):
    """'where the time goes' of each version of a --connector-tag comparison (or each phase of a --shape sequence), from
    the flight recordings of its runs"""
    entries = []
    for v in versions:
        analyses = []
        for run in runs:
            path = (run.get("flight_recorder") or {}).get("analysis")
            if run.get(group_key) == v["version"] and path and os.path.exists(path):
                with open(path) as f:
                    analyses.append(json.load(f))
        if analyses:
            entries.append({"version": v["version"], "records_per_second": v["mean"], "analyses": analyses})
    if len(entries) < 2:
        return ""
    return jfr_analyzer.render_comparison(jfr_analyzer.compare(entries, group_noun), group_noun)


def main():
    parser = argparse.ArgumentParser(description="HTML report of a playground connector benchmark run")
    parser.add_argument("--result")
    parser.add_argument("--samples")
    parser.add_argument("--runs", nargs="+", help="result json of the runs of a --connector-tag comparison or a --shape sequence")
    parser.add_argument("--group-by", choices=["plugin_version", "shape"], default="plugin_version",
                        help="what the runs are compared by: connector versions (default) or the phases of a --shape sequence")
    parser.add_argument("--history")
    parser.add_argument("--warning", action="append", default=[])
    parser.add_argument("--jfr", help="flight recorder analysis json of tools/jfr-analyzer/jfr_analyzer.py")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    versions = []
    if args.runs:
        # comparison of connector versions: the runs replace the history, the charts over time show the last run
        runs = []
        for path in args.runs:
            with open(path) as f:
                runs.append(json.load(f))
        result = runs[-1]
        samples = load_samples(result.get("samples_csv"), result.get("mode", "drain")) if os.path.exists(result.get("samples_csv", "")) else []
        history = runs
        first = None
        for run in runs:
            version = run.get(args.group_by)
            entry = next((v for v in versions if v["version"] == version), None)
            if entry is None:
                entry = {"version": version, "rates": [], "lower_bounds": 0, "runs": 0}
                versions.append(entry)
            entry["runs"] += 1
            run["round"] = entry["runs"]
            # a lower bound is not a measure: it does not count in the mean
            if run.get("lower_bound") is True:
                entry["lower_bounds"] += 1
            else:
                entry["rates"].append(run.get("records_per_second") or 0)
            latency = run.get("latency") or {}
            if latency.get("enabled") and latency.get("p95_ms") is not None:
                entry.setdefault("latencies", []).append(latency["p95_ms"])
        for v in versions:
            rates = v["rates"]
            v["mean"] = sum(rates) / len(rates) if rates else None
            v["min"], v["max"] = (min(rates), max(rates)) if rates else (None, None)
            if first is None and v["mean"] is not None:
                first = v["mean"]
            v["delta"] = (v["mean"] - first) / first * 100 if first and v["mean"] is not None else None
            latencies = v.pop("latencies", [])
            v["latency_p95"] = sum(latencies) / len(latencies) if latencies else None
    else:
        if not args.result or not args.samples:
            parser.error("--result and --samples are required without --runs")
        with open(args.result) as f:
            result = json.load(f)
        samples = load_samples(args.samples, result.get("mode", "drain"))
        history = load_history(args.history, result)

    subtitle = " · ".join(str(x) for x in [
        result.get("connector_class"), result.get("plugin_version"), "CP " + str(result.get("cp_tag")),
        (f"drain stopped at {fmt_int(result.get('records'))} of {fmt_int(result.get('expected_records'))} records" if result.get("incomplete") else
         f"{result.get('mode')} of {fmt_int(result.get('records'))} records") if result.get("mode") == "drain"
        else f"steady for {result.get('seconds')} s",
        "shape " + str(result.get("shape")), str(result.get("date", "")).replace("T", " ").replace("Z", " UTC"),
    ])
    warnings = ""
    if args.warning:
        warnings = '<ul class="card warnings">' + "".join("<li>%s</li>" % html.escape(w) for w in args.warning) + "</ul>"
    group_noun, group_title = ("version", "🆚 Connector versions") if args.group_by == "plugin_version" else ("phase", "🔁 Phases of the sequence")
    jfr_html = ""
    jfr_findings = []
    if versions:
        jfr_html = jfr_comparison(history, versions, args.group_by, group_noun)
    elif args.jfr and os.path.exists(args.jfr):
        with open(args.jfr) as f:
            analysis = json.load(f)
        jfr_findings = analysis.get("findings", [])
        files = (result.get("flight_recorder") or {}).get("files") or []
        jfr_html = jfr_analyzer.render_section(analysis, recording_link=files[0] if len(files) == 1 else None,
                                               subtitle_prefix=("Recorded during the " + ("drain" if result.get("mode") == "drain" else "measure") + " · "))
    latency = None
    if (result.get("latency") or {}).get("enabled"):
        interval = next((b["elapsed"] - a["elapsed"] for a, b in zip(samples, samples[1:]) if a.get("elapsed") is not None and b.get("elapsed") is not None), 5)
        # same time axis as the other charts: seconds since the start of the benchmark
        start = next((s["epoch"] - s["elapsed"] for s in samples if s.get("epoch") is not None and s.get("elapsed") is not None), None)
        offset = result["measure_from_ms"] / 1000 - start if start is not None and result.get("measure_from_ms") else 0
        latency = benchmark_latency.report_payload(result["latency"], max(1, round(interval)), offset)
    payload = json.dumps({"result": result, "samples": samples, "history": history, "versions": versions, "latency": latency,
                          "group_key": args.group_by, "group_noun": group_noun, "group_title": group_title,
                          "grafana": grafana_links(history if versions else [result])}).replace("</", "<\\/")
    if versions:
        subtitle = ("connector versions " if group_noun == "version" else "sequence ") + (", " if group_noun == "version" else " → ").join(v["version"] for v in versions) + " · " + subtitle
    page = (PAGE.replace("__CONNECTOR__", html.escape(str(result.get("connector"))))
            .replace("__SUBTITLE__", html.escape(subtitle))
            .replace("__BATCH_TITLE__", "⏱️ Put batch time" if result.get("type") == "sink" else "⏱️ Poll batch time")
            .replace("__VERDICT__", verdict(result, history, versions, args.warning, jfr_findings, group_noun))
            .replace("__GROUP_TITLE__", group_title)
            .replace("__WARNINGS__", warnings)
            .replace("__JFR_CSS__", jfr_analyzer.SECTION_CSS if jfr_html else "")
            .replace("__JFR_JS__", jfr_analyzer.TOOLTIP_JS if jfr_html else "")
            .replace("__JFR__", jfr_html)
            .replace("__DATA__", payload))
    with open(args.output, "w") as f:
        f.write(page)
    print(args.output)


if __name__ == "__main__":
    sys.exit(main())
