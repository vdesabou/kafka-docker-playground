#!/usr/bin/env python3
"""
HTML report of playground ccloud-costs-history, cloud-resources aws costs-history and cloud-resources azure costs-history:
cost per month (and per day for ccloud), per product / service, the month x product matrix, the top resources (the ones
still billing flagged), per environment and line type (ccloud) or resource group (azure), and the details of each month.

--data-dir holds one raw response of the cost API per month, named <start date>_<end date>.json:

  ccloud  confluent billing cost list --output json: one line per day, product, resource and line type
  aws     aws ce get-cost-and-usage, grouped by SERVICE and USAGE_TYPE (resources tagged cflt_managed_id=<user>)
  azure   Cost Management query, grouped by ServiceName and ResourceId (resources tagged cflt_managed_id=<user>)

A month without file, or with a file that cannot be read, is shown as "no data" (the query failed).
"""

import argparse
import calendar
import json
import os
import re
import sys
from collections import defaultdict
from datetime import date, datetime, timedelta
from typing import Dict, List, Optional

# no __pycache__ left in the repository
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "report-common"))
import report_html as rh  # noqa: E402
from report_html import e  # noqa: E402

FILE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})_(\d{4}-\d{2}-\d{2})\.json$")

# what the generic fields of a record are called for each cloud
LABELS = {
    "ccloud": {"name": "Confluent Cloud", "category": "product", "categories": "products", "item": "resource",
               "items": "resources", "group": "environment", "groups": "environments", "detail": "line type"},
    "aws": {"name": "AWS", "category": "service", "categories": "services", "item": "usage type",
            "items": "usage types", "group": "region", "groups": "regions", "detail": "usage type"},
    "azure": {"name": "Azure", "category": "service", "categories": "services", "item": "resource",
              "items": "resources", "group": "resource group", "groups": "resource groups", "detail": ""},
}

# data takes a few days to be consolidated by each cloud
DELAY_NOTE = {
    "ccloud": "Confluent Cloud cost data can take up to 72 hours to become available: the last days are incomplete.",
    "aws": "AWS Cost Explorer may have a 24-48 hour delay in reporting costs: the last days are incomplete.",
    "azure": "Azure Cost Management data can take up to 48 hours to be consolidated: the last days are incomplete.",
}

# AWS usage types start with a region code (EUW3-DataTransfer-Regional-Bytes), US East 1 has none
AWS_REGION_RE = re.compile(r"^([A-Z]{2,4}\d)-")


def money(v: float) -> str:
    if v == 0:
        return "$0.00"
    if abs(v) < 0.01:
        return "<$0.01"
    return f"${v:,.2f}"


def amount(s) -> float:
    """'$0.0417' or 0.0417 or '0.0417'"""
    try:
        return float(str(s).replace("$", "").replace(",", "").strip() or 0)
    except ValueError:
        return 0.0


def parse_ccloud(data, month: dict) -> List[dict]:
    out = []
    for r in data if isinstance(data, list) else []:
        out.append({
            "day": r.get("start_date") or month["start"],
            "category": r.get("product") or "unknown",
            "item": r.get("resource_name") or r.get("resource") or "unknown",
            "item_id": r.get("resource") or "",
            "group": r.get("environment") or "",
            "detail": r.get("line_type") or "",
            "price": r.get("price") or "",
            "amount": amount(r.get("amount")),
            "discount": amount(r.get("discount_amount")),
        })
    return out


def parse_aws(data, month: dict) -> List[dict]:
    out = []
    for period in data.get("ResultsByTime", []) if isinstance(data, dict) else []:
        for g in period.get("Groups", []):
            keys = g.get("Keys", []) + ["", ""]
            usage = keys[1] or keys[0]
            m = AWS_REGION_RE.match(usage)
            out.append({
                "day": period.get("TimePeriod", {}).get("Start") or month["start"],
                "category": keys[0] or "unknown",
                "item": usage,
                "item_id": "",
                "group": m.group(1) if m else "USE1",
                "detail": usage,
                "price": "",
                "amount": amount(g.get("Metrics", {}).get("UnblendedCost", {}).get("Amount")),
                "discount": 0.0,
            })
    return out


def parse_azure(data, month: dict) -> List[dict]:
    props = data.get("properties", {}) if isinstance(data, dict) else {}
    cols = [c.get("name") for c in props.get("columns", [])]

    def idx(name):
        return cols.index(name) if name in cols else None

    ci, si, ri, mi = idx("Cost"), idx("ServiceName"), idx("ResourceId"), idx("BillingMonth")
    if ci is None:
        return []
    out = []
    for row in props.get("rows", []):
        rid = str(row[ri]) if ri is not None and row[ri] else ""
        # /subscriptions/<id>/resourcegroups/<rg>/providers/<type>/<name>: the subscription id is left out of the report
        parts = rid.split("/")
        lower = [p.lower() for p in parts]
        rg = parts[lower.index("resourcegroups") + 1] if "resourcegroups" in lower[:-1] else ""
        short_id = re.sub(r"^/subscriptions/[^/]+", "", rid, flags=re.I)
        out.append({
            "day": (str(row[mi])[:10] if mi is not None and row[mi] else month["start"]),
            "category": (row[si] if si is not None else None) or "unknown",
            "item": parts[-1] if rid else "unknown",
            "item_id": short_id,
            "group": rg,
            "detail": "",
            "price": "",
            "amount": amount(row[ci]),
            "discount": 0.0,
        })
    return out


PARSERS = {"ccloud": parse_ccloud, "aws": parse_aws, "azure": parse_azure}


def load_months(cloud: str, data_dir: str) -> List[dict]:
    months = []
    for name in sorted(os.listdir(data_dir)):
        m = FILE_RE.match(name)
        if not m:
            continue
        month = {"start": m.group(1), "end": m.group(2), "ok": True, "records": []}
        try:
            with open(os.path.join(data_dir, name), encoding="utf-8") as fh:
                month["records"] = PARSERS[cloud](json.load(fh), month)
        except (OSError, ValueError):
            month["ok"] = False
        months.append(month)
    return months


def fill_missing_months(months: List[dict]) -> List[dict]:
    """The months whose query failed have no file: keep a gap in the chart for them"""
    if not months:
        return months
    out = [months[0]]
    for m in months[1:]:
        while out[-1]["end"] < m["start"]:
            prev_end = date.fromisoformat(out[-1]["end"])
            nxt = add_month(prev_end)
            out.append({"start": prev_end.isoformat(), "end": min(nxt, date.fromisoformat(m["start"])).isoformat(),
                        "ok": False, "records": []})
        out.append(m)
    return out


def add_month(d: date) -> date:
    y, mo = (d.year + 1, 1) if d.month == 12 else (d.year, d.month + 1)
    return date(y, mo, min(d.day, calendar.monthrange(y, mo)[1]))


def short_label(m: dict) -> str:
    return datetime.strptime(m["start"], "%Y-%m-%d").strftime("%b %d")


def range_label(m: dict) -> str:
    fmt = lambda s: datetime.strptime(s, "%Y-%m-%d").strftime("%b %d, %Y")  # noqa: E731
    return f"{fmt(m['start'])} to {fmt(m['end'])}"


def sum_by(records: List[dict], key) -> Dict[str, float]:
    out: Dict[str, float] = defaultdict(float)
    for r in records:
        out[key(r) if callable(key) else r[key]] += r["amount"]
    return out


def ranked(d: Dict[str, float]) -> List[tuple]:
    return sorted(((k, v) for k, v in d.items() if round(v, 4) != 0), key=lambda kv: -kv[1])


def svg_columns(points: List[tuple], highlight: Optional[int] = None) -> str:
    """One column per point: (label, value, tooltip, has_data); value labels on the highest and the highlighted columns"""
    if not points:
        return ""
    W, H, L, B, T = 600, 210, 54, 26, 16
    pw, ph = W - L - 10, H - B - T
    mx = rh.nice_max(max((p[1] for p in points), default=0))
    n = len(points)
    slot = pw / n
    bw = max(1.0, min(46.0, slot - (2 if n > 60 else 6)))
    top = max(range(n), key=lambda i: points[i][1])
    out = [f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg" role="img">']
    for frac in (0, 0.5, 1):
        y = T + ph * (1 - frac)
        out.append(f'<line x1="{L}" x2="{W - 10}" y1="{y:.1f}" y2="{y:.1f}" stroke="#e2e8f0" stroke-width="1"/>'
                   f'<text x="{L - 6}" y="{y + 3:.1f}" font-size="10" fill="#64748b" text-anchor="end">${mx * frac:,.0f}</text>')
    for i, (label, v, tip, has_data) in enumerate(points):
        x = L + i * slot + (slot - bw) / 2
        if not has_data:
            out.append(f'<rect x="{x:.1f}" y="{T}" width="{bw:.1f}" height="{ph}" fill="url(#nodata)" opacity=".5">'
                       f'<title>{e(tip)}: no data (query failed)</title></rect>')
            continue
        h = max(1.5, ph * v / mx) if v > 0 else 0
        color = rh.SERIES_2 if i == highlight else rh.SERIES_1
        # hit target taller than the column, for the tooltip of the small ones
        out.append(f'<g><rect x="{L + i * slot:.1f}" y="{T}" width="{slot:.1f}" height="{ph}" fill="transparent"/>'
                   f'<rect x="{x:.1f}" y="{T + ph - h:.1f}" width="{bw:.1f}" height="{h:.1f}" rx="2" fill="{color}"/>'
                   f'<title>{e(tip)}: {money(v)}</title></g>')
        if n <= 24 and (i == top or i == highlight) and v > 0:
            out.append(f'<text x="{x + bw / 2:.1f}" y="{T + ph - h - 4:.1f}" font-size="10" fill="#334155" '
                       f'text-anchor="middle">{e(money(v))}</text>')
    step = max(1, n // 12)
    for i in range(0, n, step):
        out.append(f'<text x="{L + i * slot + slot / 2:.1f}" y="{H - 8}" font-size="10" fill="#64748b" text-anchor="middle">'
                   f'{e(points[i][0])}</text>')
    out.append('<defs><pattern id="nodata" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">'
               '<line x1="0" y1="0" x2="0" y2="6" stroke="#94a3b8" stroke-width="2"/></pattern></defs></svg>')
    return "".join(out)


def heat(v: float, mx: float) -> str:
    """Background of a matrix cell: one hue, light to dark with the amount (text stays dark, so capped)"""
    if v <= 0 or mx <= 0:
        return ""
    return f" class='heat' style='background:rgba(42,120,214,{0.06 + 0.5 * v / mx:.2f})'"


def build(cloud: str, user: str, months: List[dict]) -> str:
    lab = LABELS[cloud]
    today = date.today()
    records = [r for m in months for r in m["records"]]
    month_totals = [sum(r["amount"] for r in m["records"]) for m in months]
    total = sum(month_totals)
    current = months[-1] if months else None
    full = [(m, t) for m, t in zip(months[:-1], month_totals[:-1]) if m["ok"]]
    previous_total = full[-1][1] if full else 0.0
    average = sum(t for _, t in full) / len(full) if full else 0.0
    by_category = ranked(sum_by(records, "category"))

    # projection of the current period, from the last day with data (ccloud) or the day the data is consolidated
    projected = None
    if current and current["ok"]:
        start = date.fromisoformat(current["start"])
        period_days = (add_month(start) - start).days
        if cloud == "ccloud" and current["records"]:
            covered = (date.fromisoformat(max(r["day"] for r in current["records"])) - start).days + 1
        else:
            covered = (today - start).days - 2
        if covered >= 3:
            projected = month_totals[-1] * period_days / covered

    # ccloud: still billing = a cost on each of the last 3 days with data (not a connector of a short run that day)
    # azure (monthly data): billed in the current period; aws: usage types are not resources, nothing flagged
    last_day = max((r["day"] for r in records), default="")
    billing_now = set()
    if cloud == "ccloud" and last_day:
        recent_days = {(date.fromisoformat(last_day) - timedelta(days=i)).isoformat() for i in range(3)}
        billed_days: Dict[str, set] = defaultdict(set)
        for r in records:
            if r["day"] in recent_days and r["amount"] > 0:
                billed_days[r["item_id"] or r["item"]].add(r["day"])
        billing_now = {k for k, d in billed_days.items() if d == recent_days}
    elif cloud == "azure":
        billing_now = {r["item_id"] or r["item"] for r in (current["records"] if current else []) if r["amount"] > 0}
    billing_badge = "still billing" if cloud == "ccloud" else "billed this period"

    body = []

    # verdict
    if projected is not None and average > 0 and projected > 1.5 * average:
        body.append(rh.verdict_html("warn", f"⚠️ The current period is heading to {money(projected)}, "
                                            f"{projected / average:.1f}x the monthly average of {money(average)}: "
                                            f"check the {lab['items']} {'still billing' if cloud == 'ccloud' else 'per month'} below."))
    elif not records:
        body.append(rh.verdict_html("ok", f"✅ No {lab['name']} cost over the last year"
                                          + ("" if cloud == "ccloud" else f" for resources tagged cflt_managed_id={user}") + "."))
    else:
        body.append(rh.verdict_html("ok", f"✅ {money(total)} over the last year, {money(average)} per month on average"
                                          + (f", current period heading to {money(projected)}" if projected is not None else "") + "."))

    failed = [m for m in months if not m["ok"]]
    if failed:
        body.append(rh.findings_html([{"severity": "MEDIUM", "text": f"No data for {range_label(m)}: the cost query failed, "
                                                                      f"this month is left out of the totals."} for m in failed]))

    cards = [
        rh.kpi("Last 12 months", money(total), f"{len(months)} periods"),
        rh.kpi("Current period", money(month_totals[-1]) if months else "-",
               f"since {range_label(current).split(' to ')[0]}" if current else "", "warn" if projected and average and projected > 1.5 * average else ""),
        rh.kpi("Projected", money(projected) if projected is not None else "-", "current period at this pace"),
        rh.kpi("Previous period", money(previous_total), range_label(full[-1][0]) if full else ""),
        rh.kpi("Monthly average", money(average), "complete periods"),
        rh.kpi(f"Top {lab['category']}", money(by_category[0][1]) if by_category else "-",
               f"{by_category[0][0]} ({100 * by_category[0][1] / total:.0f}%)" if by_category and total else ""),
    ]
    if cloud == "ccloud":
        cards.append(rh.kpi("Resources still billing", str(len(billing_now)), "billed on each of the last 3 days with data",
                            "warn" if billing_now else "ok"))
    else:
        n_current = len({r["item_id"] or r["item"] for r in (current["records"] if current else []) if r["amount"] > 0})
        cards.append(rh.kpi(f"{lab['items'].capitalize()} billed", str(n_current), "in the current period"))
    discount = sum(r["discount"] for r in records)
    if discount:
        cards.append(rh.kpi("Discounts", money(abs(discount)), "already deducted"))
    body.append(rh.kpis_html(cards))

    # charts
    points = [(short_label(m), t, range_label(m), m["ok"]) for m, t in zip(months, month_totals)]
    charts = [(f"📅 Cost per month <span class='muted'>(current period in orange)</span>", svg_columns(points, len(points) - 1)),
              (f"👛 Cost per {lab['category']} <span class='muted'>(last 12 months)</span>",
               rh.svg_hbars([(k, v, f"{k}: {money(v)}") for k, v in by_category[:15]], money))]
    if cloud == "ccloud" and records:
        daily = sum_by(records, "day")
        first = date.fromisoformat(min(daily))
        days = [(first + timedelta(days=i)).isoformat() for i in range((date.fromisoformat(max(daily)) - first).days + 1)]
        charts.append(("📆 Cost per day", svg_columns(
            [(datetime.strptime(d, "%Y-%m-%d").strftime("%b %d"), daily.get(d, 0.0), d, True) for d in days])))
        charts.append(("🌍 Cost per environment", rh.svg_hbars(
            [(k or "(none)", v, f"{k}: {money(v)}") for k, v in ranked(sum_by(records, "group"))[:15]], money)))
    elif cloud == "azure" and records:
        charts.append(("📦 Cost per resource group", rh.svg_hbars(
            [(k or "(none)", v, f"{k}: {money(v)}") for k, v in ranked(sum_by(records, "group"))[:15]], money)))
    elif cloud == "aws" and records:
        charts.append(("🌍 Cost per region code <span class='muted'>(prefix of the usage type)</span>", rh.svg_hbars(
            [(k, v, f"{k}: {money(v)}") for k, v in ranked(sum_by(records, "group"))[:15]], money)))
    body.append(rh.charts_grid(charts))

    if records:
        # month x category matrix
        cats = [k for k, _ in by_category]
        per_month = [sum_by(m["records"], "category") for m in months]
        mx = max((v for pm in per_month for v in pm.values()), default=0)
        headers = [lab["category"].capitalize()] + [f"<span title='{e(range_label(m))}'>{e(short_label(m))}</span>" for m in months] + ["Total"]
        rows = [[e(c)] + [f"<span{heat(pm.get(c, 0), mx)}>{money(pm[c])}</span>" if round(pm.get(c, 0), 4) else "<span class='muted'>-</span>"
                          for pm in per_month] + [f"<b>{money(dict(by_category)[c])}</b>"] for c in cats]
        rows.append(["<b>Total</b>"] + [f"<b>{money(t)}</b>" if m["ok"] else "<span class='muted'>no data</span>"
                                        for m, t in zip(months, month_totals)] + [f"<b>{money(total)}</b>"])
        body.append(rh.card(f"🗓️ {lab['categories'].capitalize()} per month",
                            rh.table(headers, rows, num=tuple(range(1, len(months) + 2)))))

        if cloud == "ccloud" and billing_now:
            last_cost = sum_by([r for r in records if r["day"] == last_day], lambda r: r["item_id"] or r["item"])
            info = {}
            for r in records:
                info.setdefault(r["item_id"] or r["item"], r)
            rows = [[e(info[k]["item"]), f"<span class='mono' style='word-break:normal;white-space:nowrap'>{e(info[k]['item_id'])}</span>",
                     e(info[k]["category"]), e(info[k]["group"]), money(last_cost.get(k, 0)), money(30 * last_cost.get(k, 0))]
                    for k in sorted(billing_now, key=lambda k: -last_cost.get(k, 0))][:30]
            body.append(rh.card(f"🔥 {len(billing_now)} resource{'s' if len(billing_now) > 1 else ''} still billing <span class='muted'>(billed on each of the last 3 days with data, "
                                f"most expensive first)</span>",
                                rh.table(["Resource", "Id", "Product", "Environment", f"Cost on {e(last_day)}", "≈ per month"], rows, num=(4, 5))))

        # top items
        items: Dict[str, dict] = {}
        for m in months:
            for r in m["records"]:
                key = r["item_id"] or r["item"]
                it = items.setdefault(key, {"item": r["item"], "item_id": r["item_id"], "categories": set(), "group": r["group"],
                                            "details": set(), "total": 0.0, "first": r["day"], "last": "", "months": set()})
                it["total"] += r["amount"]
                it["categories"].add(r["category"])
                if r["detail"] and r["detail"] != r["item"]:
                    it["details"].add(r["detail"])
                if r["amount"] > 0:
                    it["first"] = min(it["first"], r["day"])
                    it["last"] = max(it["last"], r["day"])
                    it["months"].add(m["start"])
        top = sorted((it for it in items.values() if round(it["total"], 4) != 0), key=lambda it: -it["total"])[:30]
        headers = [lab["item"].capitalize()]
        if cloud != "aws":
            headers.append("Id")
        headers += [lab["category"].capitalize(), lab["group"].capitalize()]
        if cloud == "ccloud":
            headers.append("Line types")
        headers += ["Months billed", "Last billed", "Total", "Share"]
        rows = []
        for it in top:
            key = it["item_id"] or it["item"]
            name = e(it["item"]) + (" " + rh.badge(billing_badge, "warn") if key in billing_now else "")
            row = [name]
            if cloud != "aws":
                # ccloud ids are short (lcc-xxxxx), the azure ones are paths
                nowrap = " style='word-break:normal;white-space:nowrap'" if cloud == "ccloud" else ""
                row.append(f"<span class='mono'{nowrap}>{e(it['item_id'])}</span>")
            row += [e(", ".join(sorted(it["categories"]))), e(it["group"])]
            if cloud == "ccloud":
                row.append(f"<span class='mono'>{e(', '.join(sorted(it['details'])))}</span>")
            last = it["last"] if cloud == "ccloud" else it["last"][:7]
            row += [str(len(it["months"])), f"<span style='white-space:nowrap'>{e(last or '-')}</span>", money(it["total"]), f"{100 * it['total'] / total:.1f}%" if total else "-"]
            rows.append(row)
        n_num = 4
        body.append(rh.card(f"🔝 Top {len(top)} {lab['items']} <span class='muted'>(of {len(items)}, last 12 months)</span>",
                            rh.table(headers, rows, num=tuple(range(len(headers) - n_num, len(headers))))))

        if cloud == "ccloud":
            lines = sum_by(records, lambda r: (r["category"], r["detail"]))
            rows = [[e(c), f"<span class='mono'>{e(d)}</span>", money(v), f"{100 * v / total:.1f}%" if total else "-"]
                    for (c, d), v in sorted(lines.items(), key=lambda kv: -kv[1]) if round(v, 4) != 0][:30]
            body.append(rh.card("🧾 Cost per line type", rh.table(["Product", "Line type", "Total", "Share"], rows, num=(2, 3))))

        # details of each month, the most recent first
        details = []
        for m, t in reversed(list(zip(months, month_totals))):
            if not m["ok"]:
                details.append(f"<details><summary>{e(range_label(m))}: <span class='muted'>no data (query failed)</span></summary></details>")
                continue
            cat_rows = [[e(k), money(v), f"{100 * v / t:.1f}%" if t else "-"] for k, v in ranked(sum_by(m["records"], "category"))]
            item_tot = ranked(sum_by(m["records"], lambda r: (r["item"], r["item_id"], r["category"], r["group"])))[:20]
            item_rows = [[e(i), f"<span class='mono'>{e(iid)}</span>", e(c), e(g), money(v)] for (i, iid, c, g), v in item_tot]
            inner = ("<h3>Per " + e(lab["category"]) + "</h3>" + rh.table([lab["category"].capitalize(), "Total", "Share"], cat_rows, num=(1, 2))
                     + f"<h3>Top {len(item_rows)} {e(lab['items'])}</h3>"
                     + rh.table([lab["item"].capitalize(), "Id", lab["category"].capitalize(), lab["group"].capitalize(), "Total"], item_rows, num=(4,)))
            opened = " open" if m is months[-1] else ""
            details.append(f"<details{opened}><summary><b>{e(range_label(m))}</b>: {money(t)}</summary>{inner}</details>")
        body.append(rh.card("🔍 Details per month", "".join(details)))

    notes = [DELAY_NOTE[cloud]]
    if cloud == "ccloud":
        notes.append("Costs of the whole organization the confluent CLI is logged into (confluent billing cost list), amounts after discounts.")
    else:
        notes.append(f"Only resources tagged cflt_managed_id={user} (the tag the playground puts on what it creates), unblended cost in USD."
                     if cloud == "aws" else
                     f"Only resources tagged cflt_managed_id={user} and cflt_managed_by=user (the tags the playground puts on what it creates).")
    cmd = "playground ccloud-costs" if cloud == "ccloud" else f"playground cloud-resources {cloud} costs"
    notes.append(f"Text version of one period: {cmd} --start-date <yyyy-mm-dd> --end-date <yyyy-mm-dd>.")
    body.append(rh.card("💡 Notes", "<ul style='margin-left:18px;font-size:.86rem'>" + "".join(f"<li>{e(n)}</li>" for n in notes) + "</ul>"))

    meta = [f"☁️ {e(lab['name'])}"]
    if cloud != "ccloud":
        meta.append(f"🏷️ cflt_managed_id={e(user)}")
    if months:
        meta.append(f"🗓️ {e(range_label({'start': months[0]['start'], 'end': months[-1]['end']}))}")
    css = ("<style>.kpi-grid{grid-template-columns:repeat(auto-fill,minmax(140px,1fr))}.kpi-value{font-size:1.4rem;white-space:nowrap}"
           "td .heat{display:block;margin:-7px -11px;padding:7px 11px}</style>")
    return rh.page(f"{lab['name']} costs", f"💰 {e(lab['name'])} costs, last 12 months", meta, css + "".join(body),
                   f"playground {'ccloud-costs-history' if cloud == 'ccloud' else 'cloud-resources ' + cloud + ' costs-history'}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cloud", required=True, choices=sorted(PARSERS))
    ap.add_argument("--data-dir", required=True)
    ap.add_argument("--user", default=os.environ.get("USER", ""))
    ap.add_argument("--html-out", required=True)
    a = ap.parse_args()
    months = fill_missing_months(load_months(a.cloud, a.data_dir))
    with open(a.html_out, "w", encoding="utf-8") as fh:
        fh.write(build(a.cloud, a.user, months))
    return 0


if __name__ == "__main__":
    sys.exit(main())
