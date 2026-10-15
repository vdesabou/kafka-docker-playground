#!/usr/bin/env python3
"""HTML report of a 'playground connector benchmark' run.

Self-contained file (inline SVG drawn by a small script, no external resource), light and dark themes:
stat tiles, throughput / connect CPU / batch latency over time, history of the comparable runs, run details and
the samples as a table.

    benchmark_report.py --result <run.json> --samples <run.csv> [--history <benchmark-history>]
                        [--warning <text>]... --output <report.html>
"""
import argparse
import csv
import html
import json
import os
import sys


def load_samples(path, phase):
    samples = []
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            if row["phase"] != phase:
                continue

            def num(key):
                try:
                    return float(row[key])
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
                        and run.get("lower_bound") is not True and (run.get("records") or 0) > 0:
                    runs.append(run)
    # with --no-history, this run is not in the file
    if not runs or runs[-1].get("date") != result.get("date") or runs[-1].get("samples_csv") != result.get("samples_csv"):
        if result.get("lower_bound") is not True and (result.get("records") or 0) > 0:
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
  --good: #0ca30c; --good-text: #006300; --critical: #d03b3b; --warning: #fab219;
}
@media (prefers-color-scheme: dark) {
  :root:where(:not([data-theme="light"])) .viz-root {
    color-scheme: dark;
    --page: #0d0d0d; --surface-1: #1a1a19; --text-primary: #f0efec; --text-secondary: #c3c2b7; --text-muted: #898781;
    --grid: #2c2c2a; --axis: #383835; --border: rgba(255,255,255,0.10); --series-1: #3987e5;
    --good-text: #0ca30c;
  }
}
:root[data-theme="dark"] .viz-root {
  color-scheme: dark;
  --page: #0d0d0d; --surface-1: #1a1a19; --text-primary: #f0efec; --text-secondary: #c3c2b7; --text-muted: #898781;
  --grid: #2c2c2a; --axis: #383835; --border: rgba(255,255,255,0.10); --series-1: #3987e5;
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
.theme-toggle { font: inherit; font-size: .8rem; color: var(--text-secondary); background: var(--surface-1);
  border: 1px solid var(--border); border-radius: 6px; padding: 4px 10px; cursor: pointer; }
.tiles { display: grid; grid-template-columns: repeat(auto-fill, minmax(230px, 1fr)); gap: 12px; margin: 22px 0; }
.tile, .card { background: var(--surface-1); border: 1px solid var(--border); border-radius: 10px; }
.tile { padding: 14px 16px; }
.tile .label { color: var(--text-secondary); font-size: .8rem; }
.tile .value { font-size: 1.6rem; font-weight: 600; margin-top: 4px; font-variant-numeric: tabular-nums; white-space: nowrap; }
.tile .unit { font-size: .85rem; font-weight: 400; color: var(--text-secondary); }
.tile .note { color: var(--text-muted); font-size: .78rem; margin-top: 4px; }
.delta-good { color: var(--good-text); } .delta-bad { color: var(--critical); }
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
.tooltip .key { display: inline-block; width: 12px; height: 2px; background: var(--series-1); vertical-align: middle; margin-right: 6px; }
.tooltip .muted { color: var(--text-secondary); }
table { border-collapse: collapse; width: 100%; font-size: .82rem; font-variant-numeric: tabular-nums; }
th, td { text-align: left; padding: 5px 10px; border-bottom: 1px solid var(--grid); }
th { color: var(--text-secondary); font-weight: 500; }
td.num, th.num { text-align: right; }
details { margin-top: 16px; } summary { cursor: pointer; font-weight: 600; font-size: .95rem; padding: 6px 0; }
.full { grid-column: 1 / -1; }
.empty { color: var(--text-muted); font-size: .875rem; padding: 24px 0; }
footer { color: var(--text-muted); font-size: .78rem; margin-top: 24px; }
</style>
</head>
<body>
<div class="viz-root">
<header>
  <div>
    <h1>🏎️ Benchmark of __CONNECTOR__</h1>
    <p class="sub">__SUBTITLE__</p>
  </div>
  <button class="theme-toggle" id="theme-toggle" type="button">Toggle theme</button>
</header>
<div class="tiles" id="tiles"></div>
__WARNINGS__
<div class="grid">
  <section class="card"><h2>Throughput</h2><p class="sub">records per second, per sample</p><div id="chart-rate"></div></section>
  <section class="card"><h2>Connect CPU</h2><p class="sub">% of one core, average of the workers running the tasks</p><div id="chart-cpu"></div></section>
  <section class="card"><h2>__BATCH_TITLE__</h2><p class="sub">average per task, ms</p><div id="chart-batch"></div></section>
  <section class="card"><h2>Comparable runs</h2><p class="sub">records per second, same example, connector, mode and shape (benchmark-history)</p><div id="chart-history"></div></section>
</div>
<details open><summary>Run details</summary><div class="card"><table id="details"></table></div></details>
<details><summary>Comparable runs (table)</summary><div class="card"><table id="history-table"></table></div></details>
<details><summary>Samples (table)</summary><div class="card"><table id="samples-table"></table></div></details>
<footer>Results are relative to the docker host they ran on: compare runs on the same machine only. Generated by playground connector benchmark.</footer>
</div>
<script type="application/json" id="data">__DATA__</script>
<script>
(function () {
  const data = JSON.parse(document.getElementById("data").textContent);
  const r = data.result, samples = data.samples, history = data.history;
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
  tile("Throughput", (r.lower_bound ? "≥ " : "") + nf.format(r.records_per_second), "records/s",
       r.rate_p50 !== "-" ? "p50 " + compact(+r.rate_p50) + " · p95 " + compact(+r.rate_p95) + " · min " + compact(+r.rate_min) : "");
  tile("Duration", nf1.format(r.seconds), "s", r.mode === "drain" ? "time to process the backlog" : "measure, after the warm-up");
  tile("Records", nf.format(r.records), "", r.mode === "drain" ? "backlog, loaded in " + r.load_seconds + " s" : "processed during the measure");
  const previous = history.length > 1 ? history[history.length - 2] : null;
  if (previous && previous.records_per_second > 0) {
    const delta = (r.records_per_second - previous.records_per_second) / previous.records_per_second * 100;
    const same = Math.abs(delta) < 5;
    tile("Vs previous run", (same ? "≈ " + (delta >= 0 ? "+" : "") : delta > 0 ? "▲ +" : "▼ ") + nf.format(delta) + "%",
         same ? "within ±5%" : delta > 0 ? "faster" : "slower",
         nf.format(previous.records_per_second) + " records/s on " + previous.date.replace("T", " ").replace("Z", " UTC"),
         same ? "" : delta > 0 ? "delta-good" : "delta-bad");
  } else {
    tile("Vs previous run", "–", "", "no comparable run in benchmark-history yet");
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
  function lineChart(id, key, unitLabel, yfmt, reference) {
    const host = document.getElementById(id);
    const pts = samples.filter(s => s[key] !== null && s.elapsed !== null);
    if (pts.length === 0) { host.appendChild(el("div", { class: "empty" }, "no sample for this metric")); return; }
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
  lineChart("chart-cpu", "cpu", "% of one core", v => nf.format(v) + "%");
  lineChart("chart-batch", "batch", "ms", v => nf1.format(v));

  // history bars
  (function () {
    const host = document.getElementById("chart-history");
    if (history.length === 0) { host.appendChild(el("div", { class: "empty" }, "no comparable run")); return; }
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
        fill: "var(--series-1)", tabindex: 0
      });
      svg.appendChild(bar);
      const current = i === n - 1;
      if (current || n <= 8) {
        const t = svgEl("text", { x: x + bw / 2, y: y - 6, "text-anchor": "middle", "font-size": 11, fill: "var(--text-secondary)" });
        t.textContent = compact(h.records_per_second);
        svg.appendChild(t);
      }
      const lab = svgEl("text", { x: x + bw / 2, y: H - B + 16, "text-anchor": "middle", "font-size": 10.5,
        fill: current ? "var(--text-primary)" : "var(--text-muted)", "font-weight": current ? 600 : 400 });
      lab.textContent = current ? "this run" : (h.date || "").slice(5, 16).replace("T", " ");
      svg.appendChild(lab);
      const showTip = () => {
        tip.replaceChildren();
        tip.appendChild(el("strong", {}, nf.format(h.records_per_second)));
        tip.appendChild(document.createTextNode(" records/s"));
        tip.appendChild(el("br"));
        tip.appendChild(el("span", { class: "muted" }, (h.date || "").replace("T", " ").replace("Z", " UTC")));
        tip.appendChild(el("br"));
        tip.appendChild(el("span", { class: "muted" }, h.plugin_version + " · CP " + h.cp_tag + " · " + h.tasks + " task(s) · " + nf.format(h.records) + " records"));
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
    ["batch avg", r.batch_avg_ms + " ms"], ["running ratio avg", r.running_ratio],
    ["connect cpu avg / max", r.cpu_percent_of_one_core_avg + "% / " + r.cpu_percent_of_one_core_max + "% of one core"],
    ["load", r.load_seconds === "-" ? "-" : r.load_seconds + " s"],
    ["records in topics", r.topic_records_delta === "-" ? "-" : "+" + nf.format(+r.topic_records_delta)],
    ["date", r.date], ["samples", r.samples_csv]
  ]);
  fillTable("history-table", [["date"], ["records/s", 1], ["records", 1], ["seconds", 1], ["plugin"], ["CP"], ["tasks", 1]],
    history.slice().reverse().map(h => [h.date, nf1.format(h.records_per_second), nf.format(h.records), h.seconds, h.plugin_version, h.cp_tag, h.tasks]));
  fillTable("samples-table", [["time"], ["elapsed s", 1], ["records", 1], ["records/s", 1], ["batch ms", 1], ["running ratio", 1], ["cpu %", 1], ["consumer lag max", 1]],
    samples.map(s => [s.time, s.elapsed, s.records === null ? null : nf.format(s.records), s.rate === null ? null : nf1.format(s.rate), s.batch, s.ratio, s.cpu, s.lag === null ? null : nf.format(s.lag)]));
})();
</script>
</body>
</html>
"""


def main():
    parser = argparse.ArgumentParser(description="HTML report of a playground connector benchmark run")
    parser.add_argument("--result", required=True)
    parser.add_argument("--samples", required=True)
    parser.add_argument("--history")
    parser.add_argument("--warning", action="append", default=[])
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    with open(args.result) as f:
        result = json.load(f)
    samples = load_samples(args.samples, result.get("mode", "drain"))
    history = load_history(args.history, result)

    subtitle = " · ".join(str(x) for x in [
        result.get("connector_class"), result.get("plugin_version"), "CP " + str(result.get("cp_tag")),
        f"{result.get('mode')} of {fmt_int(result.get('records'))} records" if result.get("mode") == "drain"
        else f"steady for {result.get('seconds')} s",
        "shape " + str(result.get("shape")), str(result.get("date", "")).replace("T", " ").replace("Z", " UTC"),
    ])
    warnings = ""
    if args.warning:
        warnings = '<ul class="card warnings">' + "".join("<li>%s</li>" % html.escape(w) for w in args.warning) + "</ul>"
    payload = json.dumps({"result": result, "samples": samples, "history": history}).replace("</", "<\\/")
    page = (PAGE.replace("__CONNECTOR__", html.escape(str(result.get("connector"))))
            .replace("__SUBTITLE__", html.escape(subtitle))
            .replace("__BATCH_TITLE__", "Put batch time" if result.get("type") == "sink" else "Poll batch time")
            .replace("__WARNINGS__", warnings)
            .replace("__DATA__", payload))
    with open(args.output, "w") as f:
        f.write(page)
    print(args.output)


if __name__ == "__main__":
    sys.exit(main())
