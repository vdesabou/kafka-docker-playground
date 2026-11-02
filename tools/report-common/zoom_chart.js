// Zoomable charts of the playground HTML reports (inlined by report_html.style(), see zoom_chart() there).
// Each <div class="zoom-chart" data-chart="{json}"> holds a static SVG drawn in Python (the chart without JavaScript),
// replaced here by the same chart drawn for the visible window: drag over it to zoom on a range, ◀ ▶ to move the
// window, the preset buttons (last 7 days…), double-click or "All" to zoom out. Charts with the same "group" zoom
// together. Chart types:
//   columns  one slot per x value: "x" (ISO days with "xfmt": "day", seconds with "xfmt": "second"), "values" (one
//            array per slot, one value per series)
//   events   "times": one sorted array of epoch seconds per series, counted again per time bucket (at most 60 buckets)
//            for the visible window, so that zooming shows the detail of a burst; "ms": true when the times have
//            milliseconds (buckets down to 1 ms)
//   xy       "layers": {kind: dots|line, label, color, r, points: [[x, y], ...]}, "hline": {y, label, color},
//            "xlabel", "ylabel"
// Common keys: series [{label, color}] (columns, events), fmt (money|int|num), W, H, presets [[label, span]], group,
// note (end of the legend), labels (value above the columns when they are few).
// An element of another chart with data-zoom-link="<id of a zoom chart>", data-zoom-from and data-zoom-to (x values, the
// end excluded) zooms that chart on a click (a month of the cost per month chart → its days in the cost per day chart).
// Each draw fires a "zoomchange" event (bubbles) on the chart: detail {from, to, all}, the first and last visible x values
// (ISO days of a columns chart of days, the end included; numbers otherwise) and whether the whole chart is shown (the
// tiles of the cloud costs reports follow the range of the cost per day chart with it, tools/cloud-costs/costs_filter.js).
(function () {
  "use strict";
  const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const BUCKETS = [1, 5, 10, 30, 60, 300, 600, 1800, 3600, 7200, 21600, 43200, 86400];
  const MS_BUCKETS = [0.001, 0.005, 0.01, 0.05, 0.1, 0.5].concat(BUCKETS);
  const MAX_DOTS = 4000;
  const groups = {};
  const pad = n => String(n).padStart(2, "0");
  const esc = s => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const dayShort = d => MON[+d.slice(5, 7) - 1] + " " + d.slice(8, 10);
  const dayLong = d => dayShort(d) + ", " + d.slice(0, 4);

  function fmtValue(v, fmt) {
    if (fmt === "money") return v === 0 ? "$0.00" : Math.abs(v) < 0.01 ? "<$0.01"
      : "$" + v.toLocaleString("en-US", {minimumFractionDigits: 2, maximumFractionDigits: 2});
    if (fmt === "int") return Math.round(v).toLocaleString("en-US");
    return (+v.toPrecision(4)).toLocaleString("en-US");
  }
  function fmtAxis(v, fmt) {
    return (fmt === "money" ? "$" : "") + (+v.toPrecision(6)).toLocaleString("en-US");
  }
  // same as nice_max() of report_html.py: 1, 2, 2.5, 3, 4, 5, 6 or 8 x 10^n, even, so that the middle tick is an integer
  function niceMax(v) {
    if (v <= 2) return 2;
    const mag = Math.pow(10, String(Math.floor(v)).length - 1);
    for (const m of [1, 2, 2.5, 3, 4, 5, 6, 8, 10]) { const t = Math.round(m * mag); if (t >= v && t % 2 === 0) return t; }
    return 10 * mag;
  }
  // same as _nice_ticks() of gc_log_analyzer.py
  function niceTicks(lo, hi, n) {
    if (hi <= lo) hi = lo + 1;
    const raw = (hi - lo) / (n || 5), mag = Math.pow(10, Math.floor(Math.log10(raw)));
    const step = [1, 2, 2.5, 5, 10].map(m => m * mag).find(s => s >= raw);
    const ticks = [];
    for (let v = Math.floor(lo / step) * step; v < hi + step * 0.999; v += step) ticks.push(+v.toPrecision(12));
    return ticks;
  }
  function stamp(t, ms) {
    const d = new Date(Math.round(t * 1000));
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) + " " +
      pad(d.getHours()) + ":" + pad(d.getMinutes()) + ":" + pad(d.getSeconds()) + (ms ? "." + String(d.getMilliseconds()).padStart(3, "0") : "");
  }
  function fmtBucket(s) {
    return s < 1 ? Math.round(s * 1000) + "ms" : s < 60 ? s + "s" : s < 3600 ? s / 60 + "min" : s < 86400 ? s / 3600 + "h" : s / 86400 + "d";
  }
  function lowerBound(arr, x) {
    let lo = 0, hi = arr.length;
    while (lo < hi) { const m = (lo + hi) >> 1; if (arr[m] < x) lo = m + 1; else hi = m; }
    return lo;
  }
  function minMax(arrays) {
    let lo = Infinity, hi = -Infinity;
    for (const a of arrays) for (const v of a) { if (v < lo) lo = v; if (v > hi) hi = v; }
    return [lo, hi];
  }
  function legend(items, note) {
    if (!items.length && !note) return "";
    return "<div class='legend'>" + items.map(s => "<i style='background:" + esc(s.color) + "'></i>" + esc(s.label)).join("") +
      (note ? (items.length ? " · " : "") + esc(note) : "") + "</div>";
  }

  document.addEventListener("click", function (ev) {
    const link = ev.target.closest && ev.target.closest("[data-zoom-link]");
    const chart = link && document.getElementById(link.dataset.zoomLink);
    if (!chart || !chart.zoomTo) return;
    if (chart.zoomTo(link.dataset.zoomFrom, link.dataset.zoomTo)) chart.scrollIntoView({behavior: "smooth", block: "nearest"});
  });

  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll(".zoom-chart").forEach(function (box) {
      try { init(box); } catch (err) { console.error("zoom chart", err); }  // the static chart stays
    });
  });

  function init(box) {
    const c = JSON.parse(box.dataset.chart), type = c.type, fmt = c.fmt || "int";
    const W = c.W || 600, H = c.H || (type === "xy" ? 270 : 200), R = 10;
    const L = c.L || (type === "xy" ? 56 : 54), T = type === "xy" ? 14 : 16, B = type === "xy" ? 36 : 26;
    const pw = W - L - R, ph = H - T - B;
    const holder = box.querySelector(".zoom-svg"), info = box.querySelector(".zoom-info");
    const series = c.series || [];
    let lo, hi;
    if (type === "columns") { lo = 0; hi = c.x.length; }
    else if (type === "events") { [lo, hi] = minMax(c.times); hi += c.ms ? 0.001 : 1; }
    else { lo = 0; hi = minMax(c.layers.map(l => l.points.map(p => p[0])))[1] || 1; }
    const minSpan = type === "columns" ? 1 : type === "events" ? (c.ms ? 0.05 : 10) : (hi - lo) / 1000;
    let a = lo, b = hi;
    const self = {};
    if (c.group) (groups[c.group] = groups[c.group] || []).push(self);

    function show(na, nb, fromGroup) {
      const span = Math.max(minSpan, nb - na);
      if (span >= hi - lo) { na = lo; nb = hi; } else { na = Math.max(lo, Math.min(na, hi - span)); nb = na + span; }
      if (type === "columns") { na = Math.round(na); nb = Math.max(na + 1, Math.round(nb)); }
      a = na; b = nb;
      draw();
      if (c.group && !fromGroup) groups[c.group].forEach(o => { if (o !== self) o.show(a, b, true); });
    }
    self.show = show;
    // zoom on [from, to): x values (ISO days of a columns chart); false when nothing of the chart is in that range
    box.zoomTo = function (from, to) {
      if (type !== "columns") { if (+to <= lo || +from >= hi) return false; show(+from, +to); return true; }
      const i0 = c.x.findIndex(x => x >= from), i1 = c.x.findIndex(x => x >= to);
      const na = i0, nb = i1 < 0 ? hi : i1;
      if (na < 0 || nb <= na) return false;
      show(na, nb);
      return true;
    };
    const zoomed = () => a > lo || b < hi;

    // --- columns and events: one slot per column, several series side by side in each slot -------------------------
    function columns(n, val, tip, xlab, labelsFmt) {
      const slot = pw / n, k = series.length || 1;
      const mx = niceMax(Math.max(0, ...Array.from({length: n}, (_, i) => Math.max(...series.map((_, j) => val(i, j))))));
      const bw = k === 1 ? Math.max(1, Math.min(46, slot - (n > 60 ? 2 : 6))) : Math.max(1, (slot - 2) / k);
      const o = [];
      for (const f of [0, 0.5, 1]) {
        const y = (T + ph * (1 - f)).toFixed(1);
        o.push('<line x1="' + L + '" x2="' + (W - R) + '" y1="' + y + '" y2="' + y + '" stroke="#e2e8f0" stroke-width="1"/>' +
               '<text x="' + (L - 6) + '" y="' + (+y + 3) + '" font-size="10" fill="#64748b" text-anchor="end">' + esc(fmtAxis(mx * f, fmt)) + "</text>");
      }
      let top = 0, topV = -1;
      for (let i = 0; i < n; i++) {
        const v0 = val(i, 0);
        if (v0 > topV) { top = i; topV = v0; }
        o.push('<g><rect x="' + (L + i * slot).toFixed(1) + '" y="' + T + '" width="' + slot.toFixed(1) + '" height="' + ph + '" fill="transparent"/>');
        const tips = [];
        series.forEach(function (s, j) {
          const v = val(i, j);
          tips.push(fmtValue(v, fmt) + (s.label && (k > 1 || type === "events") ? " " + s.label : ""));
          if (!(v > 0)) return;
          const h = Math.max(1.5, ph * v / mx);
          const x = k === 1 ? L + i * slot + (slot - bw) / 2 : L + i * slot + 1 + j * bw;
          o.push('<rect x="' + x.toFixed(1) + '" y="' + (T + ph - h).toFixed(1) + '" width="' + bw.toFixed(1) + '" height="' + h.toFixed(1) +
                 '" rx="' + (k === 1 ? 2 : 1) + '" fill="' + esc(s.color) + '"/>');
        });
        o.push("<title>" + esc(tip(i) + ": " + tips.join(", ")) + "</title></g>");
      }
      if (labelsFmt && k === 1) {
        for (let i = 0; i < n; i++) {
          const v = val(i, 0);
          if (!(v > 0) || !(n <= 16 || (n <= 62 && i === top))) continue;
          const h = Math.max(1.5, ph * v / mx), x = L + i * slot + slot / 2;
          o.push('<text x="' + x.toFixed(1) + '" y="' + (T + ph - h - 4).toFixed(1) + '" font-size="' + (n > 31 ? 9 : 10) +
                 '" fill="#334155" text-anchor="middle">' + esc(fmtValue(v, fmt)) + "</text>");
        }
      }
      const step = Math.max(1, Math.ceil(n / Math.max(4, Math.floor(W / 60))));
      for (let i = 0; i < n; i += step)
        o.push('<text x="' + (L + i * slot + slot / 2).toFixed(1) + '" y="' + (H - 8) + '" font-size="10" fill="#64748b" text-anchor="middle">' +
               esc(xlab(i)) + "</text>");
      return o.join("");
    }

    function drawColumns() {
      const n = b - a, day = c.xfmt === "day";
      const xs = c.x.slice(a, b), vs = c.values.slice(a, b);
      const body = columns(n, (i, j) => vs[i][j] || 0,
        i => day ? dayLong(xs[i]) : "second " + xs[i],
        i => day ? dayShort(xs[i]) : xs[i] + "s", c.labels);
      const totals = series.map((_, j) => vs.reduce((t, v) => t + (v[j] || 0), 0));
      let text = (day ? dayLong(xs[0]) + " → " + dayLong(xs[n - 1]) + " · " + n + " day" + (n > 1 ? "s" : "")
                      : "seconds " + xs[0] + " → " + xs[n - 1]) + " · ";
      text += series.length === 1 && fmt === "money"
        ? fmtValue(totals[0], fmt) + " · " + fmtValue(totals[0] / n, fmt) + " per day"
        : series.map((s, j) => fmtValue(totals[j], fmt) + " " + s.label).join(" · ");
      return [legend(series.length > 1 ? series : [], c.note), body, text];
    }

    function drawEvents() {
      const list = c.ms ? MS_BUCKETS : BUCKETS;
      const bucket = list.find(bk => (b - a) / bk <= 60) || list[list.length - 1];
      const start = Math.floor(a / bucket) * bucket, n = Math.max(1, Math.ceil((b - start) / bucket - 1e-9));
      const counts = c.times.map(ts => {
        const out = [];
        let prev = lowerBound(ts, start);
        for (let i = 0; i < n; i++) { const next = lowerBound(ts, start + (i + 1) * bucket); out.push(next - prev); prev = next; }
        return out;
      });
      const d0 = new Date(start * 1000), d1 = new Date((start + n * bucket) * 1000 - 1);
      const oneDay = d0.toDateString() === d1.toDateString(), ms = bucket < 1;
      const xlab = t => { const s = stamp(t, ms); return ms ? s.slice(17) : bucket < 60 ? s.slice(11) : oneDay ? s.slice(11, 16) : s.slice(5, 16); };
      const body = columns(n, (i, j) => counts[j][i], i => stamp(start + i * bucket, ms), i => xlab(start + i * bucket));
      const inWindow = c.times.map(ts => lowerBound(ts, b) - lowerBound(ts, a));
      const showMs = c.ms && b - a < 60;  // milliseconds in the range only when they matter
      const text = stamp(a, showMs) + " → " + stamp(b, showMs) + " · " + series.map((s, j) => fmtValue(inWindow[j], "int") + " " + s.label).join(" · ");
      return [legend(series, "per " + fmtBucket(bucket) + (c.note || "")), body, text];
    }

    function drawXY() {
      const vis = c.layers.map(l => {
        let pts = l.points.filter(p => p[0] >= a && p[0] <= b);
        if (l.kind === "line") {  // one point on each side, so that the line reaches the edges
          const i0 = l.points.findIndex(p => p[0] >= a), i1 = l.points.findIndex(p => p[0] > b);
          if (i0 > 0) pts.unshift(l.points[i0 - 1]);
          if (i1 > 0) pts.push(l.points[i1]);
        } else if (pts.length > MAX_DOTS && !l.keep) {
          const step = pts.length / MAX_DOTS;
          pts = Array.from({length: MAX_DOTS}, (_, i) => pts[Math.floor(i * step)]);
        }
        return pts;
      });
      let ymax = 0;
      vis.forEach((pts, i) => pts.forEach(p => { if (p[0] >= a && p[0] <= b && p[1] > ymax) ymax = p[1]; }));
      if (c.hline && c.hline.y > ymax) ymax = c.hline.y;
      const yt = niceTicks(0, ymax || 1), ytop = yt[yt.length - 1] || 1;
      const xt = niceTicks(a, b).filter(x => x >= a - 1e-9 && x <= b + 1e-9);
      const sx = x => L + pw * (x - a) / (b - a), sy = y => T + ph * (1 - y / ytop);
      const id = "zc" + Math.random().toString(36).slice(2, 8);
      const o = ['<defs><clipPath id="' + id + '"><rect x="' + L + '" y="' + (T - 4) + '" width="' + pw + '" height="' + (ph + 8) + '"/></clipPath></defs>'];
      for (const y of yt)
        o.push('<line x1="' + L + '" y1="' + sy(y).toFixed(1) + '" x2="' + (W - R) + '" y2="' + sy(y).toFixed(1) + '" stroke="#e2e8f0"/>' +
               '<text x="' + (L - 6) + '" y="' + (sy(y) + 4).toFixed(1) + '" font-size="10" text-anchor="end" fill="#64748b">' + esc(fmtAxis(y, fmt)) + "</text>");
      for (const x of xt)
        o.push('<text x="' + sx(x).toFixed(1) + '" y="' + (H - B + 14) + '" font-size="10" text-anchor="middle" fill="#64748b">' + esc(fmtAxis(x, "num")) + "</text>");
      o.push('<line x1="' + L + '" y1="' + (T + ph) + '" x2="' + (W - R) + '" y2="' + (T + ph) + '" stroke="#94a3b8"/>');
      if (c.xlabel) o.push('<text x="' + (L + pw / 2) + '" y="' + (H - 4) + '" font-size="11" text-anchor="middle" fill="#475569">' + esc(c.xlabel) + "</text>");
      if (c.ylabel) o.push('<text x="12" y="' + (T + ph / 2) + '" font-size="11" text-anchor="middle" fill="#475569" transform="rotate(-90 12 ' + (T + ph / 2) + ')">' + esc(c.ylabel) + "</text>");
      o.push('<g clip-path="url(#' + id + ')">');
      c.layers.forEach(function (l, i) {
        const pts = vis[i];
        if (l.kind === "line") {
          if (pts.length) o.push('<path d="' + pts.map((p, k) => (k ? "L" : "M") + sx(p[0]).toFixed(1) + "," + sy(p[1]).toFixed(1)).join(" ") +
                                 '" fill="none" stroke="' + esc(l.color) + '" stroke-width="1.2" stroke-opacity=".85"/>');
        } else {
          const r = l.r || 2, op = l.opacity || 1;
          for (const p of pts)
            o.push('<circle cx="' + sx(p[0]).toFixed(1) + '" cy="' + sy(p[1]).toFixed(1) + '" r="' + r + '" fill="' + esc(l.color) + '" fill-opacity="' + op + '">' +
                   "<title>" + esc(fmtAxis(p[0], "num") + " " + (c.xlabel || "") + ": " + fmtValue(p[1], fmt) + " " + (c.yunit || "")) + "</title></circle>");
        }
      });
      if (c.hline) o.push('<line x1="' + L + '" y1="' + sy(c.hline.y).toFixed(1) + '" x2="' + (W - R) + '" y2="' + sy(c.hline.y).toFixed(1) +
                          '" stroke="' + esc(c.hline.color) + '" stroke-dasharray="4 3"/>');
      o.push("</g>");
      const items = c.layers.map(l => ({label: l.label, color: l.color})).concat(c.hline ? [{label: c.hline.label, color: c.hline.color}] : []);
      const dots = c.layers.map((l, i) => l.kind === "line" ? null : fmtValue(l.points.filter(p => p[0] >= a && p[0] <= b).length, "int") + " " + l.label)
        .filter(Boolean);
      const text = fmtAxis(a, "num") + " → " + fmtAxis(b, "num") + " " + (c.xlabel || "") + (dots.length ? " · " + dots.join(" · ") : "");
      return [legend(items, c.note), o.join(""), text];
    }

    function draw() {
      const [leg, body, text] = type === "columns" ? drawColumns() : type === "events" ? drawEvents() : drawXY();
      holder.innerHTML = leg + '<svg viewBox="0 0 ' + W + " " + H + '" xmlns="http://www.w3.org/2000/svg" role="img">' + body +
        '<rect class="zoom-sel" x="0" y="' + T + '" width="0" height="' + ph + '" fill="#2a78d6" opacity=".15" pointer-events="none"/></svg>';
      info.textContent = text;
      box.querySelectorAll("[data-zoom]").forEach(x => x.classList.remove("on"));
      const preset = box.querySelector("[data-zoom='all']");
      if (!zoomed()) preset.classList.add("on");
      box.querySelectorAll("[data-span]").forEach(x => { if (b === hi && Math.abs(b - a - +x.dataset.span) < 1e-6) x.classList.add("on"); });
      box.querySelector("[data-zoom='prev']").disabled = a <= lo;
      box.querySelector("[data-zoom='next']").disabled = b >= hi;
      bind(holder.querySelector("svg"));
      const detail = type === "columns" ? {from: c.x[a], to: c.x[b - 1], all: !zoomed()} : {from: a, to: b, all: !zoomed()};
      box.dispatchEvent(new CustomEvent("zoomchange", {bubbles: true, detail: detail}));
    }

    // domain value under the mouse
    function at(svg, ev) {
      const r = svg.getBoundingClientRect(), px = (ev.clientX - r.left) * W / r.width;
      const f = Math.max(0, Math.min(1, (px - L) / pw));
      return type === "columns" ? Math.min(b - 1, a + Math.floor(f * (b - a))) : a + f * (b - a);
    }
    function bind(svg) {
      const sel = svg.querySelector(".zoom-sel");
      const px = v => L + pw * (v - a) / (b - a);
      function paint(v0, v1) {
        let x0 = Math.min(v0, v1), x1 = Math.max(v0, v1);
        if (type === "columns") x1 += 1;
        sel.setAttribute("x", px(x0).toFixed(1));
        sel.setAttribute("width", Math.max(0, px(x1) - px(x0)).toFixed(1));
      }
      svg.addEventListener("mousedown", function (ev) {
        if (ev.button !== 0) return;
        ev.preventDefault();
        const start = at(svg, ev);
        paint(start, start);
        function move(e2) { paint(start, at(svg, e2)); }
        function up(e2) {
          document.removeEventListener("mousemove", move);
          document.removeEventListener("mouseup", up);
          const end = at(svg, e2), x0 = Math.min(start, end), x1 = Math.max(start, end) + (type === "columns" ? 1 : 0);
          // a click (or a selection of one column) is not a zoom: the tooltips stay usable
          if ((type === "columns" && x1 - x0 >= 2) || (type !== "columns" && px(x1) - px(x0) > 4)) show(x0, x1);
          else sel.setAttribute("width", "0");
        }
        document.addEventListener("mousemove", move);
        document.addEventListener("mouseup", up);
      });
      svg.addEventListener("dblclick", () => show(lo, hi));
    }

    box.querySelectorAll("[data-zoom]").forEach(function (x) {
      x.addEventListener("click", function () {
        const k = x.dataset.zoom, w = b - a;
        if (k === "all") show(lo, hi);
        else if (k === "prev") show(a - w, a);
        else if (k === "next") show(b, b + w);
        else show(hi - +x.dataset.span, hi);
      });
    });
    box.querySelectorAll("[hidden]").forEach(x => { x.hidden = false; });
    draw();
  }
})();
