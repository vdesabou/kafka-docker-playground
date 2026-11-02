// Cloud costs reports (costs_report.py, ccloud): the tiles follow the range selected in the cost per day chart.
// The records are in <script type="application/json" id="cost-range-data"> (range_data() in costs_report.py), the tiles
// to compute again are marked by:
//   data-range-kpi="total|top|discount|days|perday|permonth"   a KPI card (label, value and unit replaced)
//   data-range-tile="category|group|top|lines|matrix|per-category"   the content of a chart or table card
//   data-range-title="<template>"   a title: {range} (range of days), {k} (rows shown) and {n} (rows in total) replaced
// Same computations and markup as costs_report.py (build() for "history", build_range() for "range"). When the whole
// chart is shown again, every tile gets back its HTML written by Python.
(function () {
  "use strict";
  const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const esc = s => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#x27;");
  const dayLong = d => MON[+d.slice(5, 7) - 1] + " " + d.slice(8, 10) + ", " + d.slice(0, 4);
  const money = v => v === 0 ? "$0.00" : Math.abs(v) < 0.01 ? "<$0.01"
    : (v < 0 ? "-" : "") + "$" + Math.abs(v).toLocaleString("en-US", {minimumFractionDigits: 2, maximumFractionDigits: 2});
  const pct = (v, t, digits) => t ? (100 * v / t).toFixed(digits) + "%" : "-";
  const ranked = m => Array.from(m.entries()).sort((x, y) => y[1] - x[1]);
  const add = (m, k, v) => m.set(k, (m.get(k) || 0) + v);
  const SERIES_1 = "#2a78d6";

  function table(headers, rows, num) {
    const cell = (tag, i, c) => num.includes(i) ? "<" + tag + " class='num'>" + c + "</" + tag + ">" : "<" + tag + ">" + c + "</" + tag + ">";
    return "<table><tr>" + headers.map((h, i) => cell("th", i, h)).join("") + "</tr>" +
      rows.map(r => "<tr>" + r.map((c, i) => cell("td", i, c)).join("") + "</tr>").join("") + "</table>";
  }
  // same as rh.svg_hbars()
  function hbars(rows) {
    if (!rows.length) return "";
    const W = 600, rowh = 22, L = 300, H = 10 + rowh * rows.length;
    const mx = Math.max(...rows.map(r => r[1])) || 1;
    const o = ['<svg viewBox="0 0 ' + W + " " + H + '" xmlns="http://www.w3.org/2000/svg" role="img">'];
    rows.forEach(function (r, i) {
      const y = 5 + i * rowh, w = (W - L - 70) * r[1] / mx;
      o.push('<text x="' + (L - 6) + '" y="' + (y + 14) + '" font-size="10" fill="#334155" text-anchor="end">' + esc(r[0].slice(0, 52)) + "</text>" +
             '<rect x="' + L + '" y="' + (y + 3) + '" width="' + Math.max(1, w).toFixed(1) + '" height="15" rx="2" fill="' + SERIES_1 + '"><title>' + esc(r[2]) + "</title></rect>" +
             '<text x="' + (L + w + 5).toFixed(1) + '" y="' + (y + 14) + '" font-size="10" fill="#475569">' + esc(money(r[1])) + "</text>");
    });
    return o.join("") + "</svg>";
  }
  function heat(v, mx) {
    return v <= 0 || mx <= 0 ? "" : " class='heat' style='background:rgba(42,120,214," + (0.06 + 0.5 * v / mx).toFixed(2) + ")'";
  }

  document.addEventListener("DOMContentLoaded", function () {
    const el = document.getElementById("cost-range-data");
    if (!el) return;
    const D = JSON.parse(el.textContent), lab = D.labels;
    const billing = new Set(D.billing);
    const saved = new Map();
    const banner = document.querySelector(".range-banner");
    function save(node) { if (!saved.has(node)) saved.set(node, node.innerHTML); }
    function restore() {
      saved.forEach((html, node) => { node.innerHTML = html; node.classList.remove("range-on"); });
      if (banner) banner.hidden = true;
    }
    if (banner) banner.querySelector("button").addEventListener("click", function () {
      const all = document.querySelector("#" + D.chart + " [data-zoom='all']");
      if (all) all.click();
    });

    document.addEventListener("zoomchange", function (ev) {
      if (ev.target.id !== D.chart) return;
      if (ev.detail.all) restore(); else apply(ev.detail.from, ev.detail.to);
    });

    function apply(from, to) {
      const d0 = D.days.indexOf(from), d1 = D.days.indexOf(to);
      if (d0 < 0 || d1 < 0) return;
      const nDays = d1 - d0 + 1, range = dayLong(from) + " → " + dayLong(to);
      let total = 0, discount = 0;
      const byCat = new Map(), byGroup = new Map(), lines = new Map(), catGroup = new Map(), items = new Map(), daysWithData = new Set();
      for (const r of D.rows) {
        const [day, item, cat, group, detail, amount, disc] = r;
        if (day < d0 || day > d1) continue;
        daysWithData.add(day);
        total += amount;
        discount += disc;
        add(byCat, D.categories[cat], amount);
        add(byGroup, D.groups[group], amount);
        add(lines, cat + "\u0000" + detail, amount);
        if (!catGroup.has(cat)) catGroup.set(cat, new Map());
        add(catGroup.get(cat), D.groups[group], amount);
        let it = items.get(item);
        if (!it) {
          it = {idx: item, info: D.items[item], total: 0, cats: new Set(), details: new Set(), days: new Set(), months: new Set(), first: "", last: ""};
          items.set(item, it);
        }
        it.total += amount;
        it.cats.add(D.categories[cat]);
        const det = D.details[detail];
        if (det && (D.mode === "range" || det !== it.info[0])) it.details.add(det);
        if (amount > 0) {
          const d = D.days[day];
          it.days.add(d);
          it.months.add(D.dayMonth[day]);
          if (!it.first || d < it.first) it.first = d;
          if (d > it.last) it.last = d;
        }
      }
      const cats = ranked(byCat), groups = ranked(byGroup);
      const withData = daysWithData.size, perDay = withData ? total / withData : 0;
      const top = Array.from(items.values()).filter(it => Math.round(it.total * 1e4) !== 0).sort((x, y) => y.total - x.total);

      // KPI cards
      document.querySelectorAll("[data-range-kpi]").forEach(function (card) {
        save(card);
        card.classList.add("range-on");
        const set = (label, value, unit) => {
          card.querySelector(".kpi-label").textContent = "🔍 " + label;
          card.querySelector(".kpi-value").textContent = value;
          card.querySelector(".kpi-unit").textContent = unit;
        };
        const k = card.dataset.rangeKpi;
        if (k === "total") set("Selected range", money(total), range + " (" + nDays + " day" + (nDays > 1 ? "s" : "") + ")");
        else if (k === "top") set("Top " + lab.category, cats.length ? money(cats[0][1]) : "-",
                                 cats.length && total ? cats[0][0] + " (" + pct(cats[0][1], total, 0) + ")" : "");
        else if (k === "discount") set("Discounts", money(Math.abs(discount)), "already deducted");
        else if (k === "days") set("Days with data", withData + " / " + nDays, "the last days can be incomplete");
        else if (k === "perday") set("Per day", money(perDay), "average over the days with data");
        else if (k === "permonth") set("≈ per month", money(30 * perDay), "at this pace");
      });

      // titles
      document.querySelectorAll("[data-range-title]").forEach(function (t) {
        save(t);
        const n = t.dataset.rangeKey === "per-category" ? cats.length : top.length;
        const k = Math.min(30, top.length);
        const tpl = t.dataset.rangeTitle;
        t.innerHTML = (tpl.startsWith("🔍") ? "" : "🔍 ") + tpl.replace("{range}", esc(range)).replace("{k}", k).replace("{n}", n);
      });

      // charts and tables
      const itemRow = function (it, withCategory) {
        const [name, id, group, category] = it.info;
        const row = [esc(name) + (billing.has(it.idx) ? " " + D.badge : ""),
                     "<span class='mono' style='word-break:normal;white-space:nowrap'>" + esc(id) + "</span>"];
        const details = "<span class='mono'>" + esc(Array.from(it.details).sort().join(", ")) + "</span>";
        if (D.mode === "history") {
          row.push(esc(Array.from(it.cats).sort().join(", ")), esc(group), details, String(it.months.size),
                   "<span style='white-space:nowrap'>" + esc(it.last || "-") + "</span>");
        } else {
          const days = Array.from(it.days).sort();
          if (withCategory) row.push(esc(category));
          row.push(esc(group), details, String(days.length),
                   "<span style='white-space:nowrap'>" + esc(days[0] || "-") + "</span>",
                   "<span style='white-space:nowrap'>" + esc(days[days.length - 1] || "-") + "</span>");
        }
        row.push(money(it.total), pct(it.total, total, 1));
        return row;
      };
      const numTail = (headers, n) => Array.from({length: n}, (_, i) => headers.length - n + i);
      const render = {
        "category": () => hbars(cats.slice(0, 15).map(([k, v]) => [k, v, k + ": " + money(v)])),
        "group": () => hbars(groups.slice(0, 15).map(([k, v]) => [k || "(none)", v, k + ": " + money(v)])),
        "top": () => table(D.topHeaders, top.slice(0, 30).map(it => itemRow(it, true)), numTail(D.topHeaders, 4)),
        "lines": () => table(["Product", "Line type", "Total", "Share"],
          Array.from(lines.entries()).filter(([, v]) => Math.round(v * 1e4) !== 0).sort((x, y) => y[1] - x[1]).slice(0, 30)
            .map(([k, v]) => { const [c, d] = k.split("\u0000"); return [esc(D.categories[c]), "<span class='mono'>" + esc(D.details[d]) + "</span>", money(v), pct(v, total, 1)]; }),
          [2, 3]),
        "matrix": function () {
          let mx = 0;
          catGroup.forEach(m => m.forEach(v => { if (v > mx) mx = v; }));
          const rows = cats.map(([c, v]) => {
            const m = catGroup.get(D.categories.indexOf(c));
            return [esc(c)].concat(groups.map(([g]) => {
              const x = m.get(g) || 0;
              return Math.round(x * 1e4) ? "<span" + heat(x, mx) + ">" + money(x) + "</span>" : "<span class='muted'>-</span>";
            })).concat(["<b>" + money(v) + "</b>"]);
          });
          rows.push(["<b>Total</b>"].concat(groups.map(([, v]) => "<b>" + money(v) + "</b>")).concat(["<b>" + money(total) + "</b>"]));
          return table([esc(lab.category.charAt(0).toUpperCase() + lab.category.slice(1))].concat(groups.map(([g]) => esc(g || "(none)"))).concat(["Total"]),
                       rows, Array.from({length: groups.length + 1}, (_, i) => i + 1));
        },
        "per-category": function () {
          const headers = ["Resource", "Id"].concat(D.topHeaders.slice(3));
          return cats.map(function ([c, v]) {
            const rows = top.filter(it => it.info[3] === c).map(it => itemRow(it, false));
            return "<details><summary><b>" + esc(c) + "</b>: " + money(v) + " <span class='muted'>(" + pct(v, total, 1) + ", " + rows.length + " " +
              (rows.length === 1 ? lab.item : lab.items) + ")</span></summary>" + table(headers, rows, numTail(headers, 4)) + "</details>";
          }).join("");
        },
      };
      document.querySelectorAll("[data-range-tile]").forEach(function (tile) {
        const f = render[tile.dataset.rangeTile];
        if (!f) return;
        save(tile);
        tile.innerHTML = f();
      });

      if (banner) {
        banner.querySelector(".range-text").textContent = "The tiles marked 🔍 show " + range + " (" + nDays + " day" + (nDays > 1 ? "s" : "") +
          ", " + money(total) + "), the range selected in the cost per day chart. " + D.note;
        banner.hidden = false;
      }
    }
  });
})();
