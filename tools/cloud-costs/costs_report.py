#!/usr/bin/env python3
"""
HTML report of playground ccloud-costs-history, cloud-resources aws costs-history and cloud-resources azure costs-history:
cost per month (and per day for ccloud), per product / service, the month x product matrix, the top resources (the ones
still billing flagged), per environment and line type (ccloud) or resource group (azure), and the details of each month.

--data-dir holds one raw response of the cost API per month, named <start date>_<end date>.json:

  ccloud  confluent billing cost list --output json: one line per day, product, resource and line type
  aws     aws ce get-cost-and-usage, grouped by SERVICE and USAGE_TYPE, cost and usage quantity (resources tagged
          cflt_managed_id=<user>); plus s3-buckets.json, the S3 buckets with that tag (save_aws_s3_buckets), for the
          Amazon S3 details: cost and volume per kind of S3 usage, per month and per destination, the buckets, hints
  azure   Cost Management query, grouped by ServiceName and ResourceId (resources tagged cflt_managed_id=<user>)

A month without file, or with a file that cannot be read, is shown as "no data" (the query failed).

--range-file (ccloud): report of playground ccloud-costs, one range of dates instead of the months of --data-dir.
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
                # GB, GB-Month, Requests... (files saved before UsageQuantity was asked for have none)
                "quantity": amount(g.get("Metrics", {}).get("UsageQuantity", {}).get("Amount")),
                "unit": g.get("Metrics", {}).get("UsageQuantity", {}).get("Unit") or "",
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


# ── Amazon S3 details (aws) ──────────────────────────────────────────────────

S3_SERVICE = "Amazon Simple Storage Service"

# region codes of the AWS usage types (EU is the old code of eu-west-1)
AWS_REGIONS = {
    "USE1": "us-east-1", "USE2": "us-east-2", "USW1": "us-west-1", "USW2": "us-west-2", "CAN1": "ca-central-1",
    "CAN2": "ca-west-1", "EU": "eu-west-1", "EUW2": "eu-west-2", "EUW3": "eu-west-3", "EUC1": "eu-central-1",
    "EUC2": "eu-central-2", "EUN1": "eu-north-1", "EUS1": "eu-south-1", "EUS2": "eu-south-2", "APN1": "ap-northeast-1",
    "APN2": "ap-northeast-2", "APN3": "ap-northeast-3", "APS1": "ap-southeast-1", "APS2": "ap-southeast-2",
    "APS3": "ap-south-1", "APS4": "ap-southeast-3", "APS5": "ap-south-2", "APS6": "ap-southeast-4", "APE1": "ap-east-1",
    "SAE1": "sa-east-1", "MES1": "me-south-1", "MEC1": "me-central-1", "AFS1": "af-south-1", "ILC1": "il-central-1",
    "UGW1": "us-gov-west-1", "UGE1": "us-gov-east-1",
}

# <source>-<destination>-AWS-Out-Bytes (USE1-USW2-AWS-Out-Bytes), and the region prefix of the other usage types
S3_TRANSFER_RE = re.compile(r"^(?:([A-Z]+\d*)-)?([A-Z]+\d*)-AWS-(Out|In)-Bytes$")
S3_PREFIX_RE = re.compile(r"^([A-Z]+\d*)-(.+)$")

# storage class tokens of TimedStorage-<token>-ByteHrs, Retrieval-<token>, Requests-<token>-Tier1
S3_CLASSES = [("GlacierByteHrs", "GLACIER"), ("GDA", "DEEP_ARCHIVE"), ("GIR", "GLACIER_IR"), ("SIA", "STANDARD_IA"),
              ("ZIA", "ONEZONE_IA"), ("INT", "INTELLIGENT_TIERING"), ("RRS", "REDUCED_REDUNDANCY"), ("XZ", "EXPRESS_ONEZONE")]

S3_KINDS = [  # key, label, what it is
    ("storage", "💾 Storage", "data stored, per storage class"),
    ("requests", "📨 Requests", "PUT, COPY, POST, LIST (Tier1), GET and the others (Tier2)"),
    ("retrieval", "📤 Retrieval fee", "paid per GB read from Standard-IA, One Zone-IA and Glacier"),
    ("internet", "🌐 Data sent to the Internet", "downloads from outside AWS (laptops, GitHub-hosted runners...)"),
    ("region", "🔀 Data sent to another AWS region", "downloads from EC2, CI runners... running in another region"),
    ("regional", "🏢 Data within the region", "between availability zones"),
    ("in", "📥 Data received", "uploads, free"),
    ("other", "🧩 Other", "early deletion, monitoring, inventory, bucket fees..."),
]
S3_KIND_LABEL = {k: label for k, label, _ in S3_KINDS}
S3_READ_KINDS = ("retrieval", "internet", "region")


def region_name(code: str) -> str:
    return AWS_REGIONS.get(code, code)


def storage_class(usage: str) -> str:
    return next((name for token, name in S3_CLASSES if token in usage), "STANDARD")


def s3_usage(usage: str) -> dict:
    """Kind of an S3 usage type, its plain label, and for data sent out the destination ('Internet' or a region)"""
    m = S3_TRANSFER_RE.match(usage)
    if m:
        src, dst = region_name(m.group(1) or "USE1"), region_name(m.group(2))
        if m.group(3) == "In":
            return {"kind": "in", "label": f"received from {dst} in {src}", "dest": ""}
        return {"kind": "region", "label": f"{src} → {dst}", "dest": dst, "src": src}
    p = S3_PREFIX_RE.match(usage)
    region, rest = (region_name(p.group(1)), p.group(2)) if p else ("us-east-1", usage)
    if rest.startswith("TimedStorage"):
        return {"kind": "storage", "label": f"{storage_class(rest)} in {region}", "dest": ""}
    if rest.startswith("Requests"):
        tier = rest.rsplit("-", 1)[-1]
        cls = storage_class(rest)
        return {"kind": "requests", "label": f"{tier}{'' if cls == 'STANDARD' else ' ' + cls} in {region}", "dest": ""}
    if rest.startswith("Retrieval"):
        return {"kind": "retrieval", "label": f"{storage_class(rest)} in {region}", "dest": ""}
    if rest == "DataTransfer-Out-Bytes":
        return {"kind": "internet", "label": f"{region} → Internet", "dest": "Internet", "src": region}
    if rest == "DataTransfer-In-Bytes":
        return {"kind": "in", "label": f"from the Internet in {region}", "dest": ""}
    if rest.startswith("DataTransfer-Regional"):
        return {"kind": "regional", "label": f"within {region}", "dest": ""}
    return {"kind": "other", "label": usage, "dest": ""}


def fmt_quantity(q: float, unit: str) -> str:
    if not q:
        return "-"
    if unit == "GB":
        return f"{q / 1024:,.1f} TB" if q >= 1024 else f"{q:,.1f} GB" if q >= 1 else f"{q * 1024:,.1f} MB" if q * 1024 >= 0.1 else "<0.1 MB"
    if unit == "GB-Month":
        return f"{q:,.1f} GB-month"
    if unit == "Requests":
        return f"{q / 1e6:,.1f}M requests" if q >= 1e6 else f"{q / 1e3:,.1f}k requests" if q >= 1e3 else f"{q:,.0f} requests"
    return f"{q:,.2f} {unit}".strip()


def pct(v: float, total: float) -> str:
    share = 100 * v / total if total else 0
    return f"{share:.1f}%" if share < 1 else f"{share:.0f}%"


def quantity_of(records: List[dict]) -> str:
    """Volume of records of one kind: the sum per unit (a kind can mix units, other)"""
    per_unit: Dict[str, float] = defaultdict(float)
    for r in records:
        per_unit[r.get("unit", "")] += r.get("quantity", 0.0)
    return ", ".join(fmt_quantity(q, u) for u, q in per_unit.items() if q) or "-"


def s3_section(months: List[dict], buckets: Optional[List[dict]], user: str) -> str:
    """Card with the S3 costs per kind of usage, per month and per destination, the tagged buckets and hints; '' without S3 cost"""
    for m in months:
        for r in m["records"]:
            if r["category"] == S3_SERVICE and "kind" not in r:
                r.update(s3_usage(r["item"]))
    s3 = [r for m in months for r in m["records"] if r["category"] == S3_SERVICE]
    s3_total = sum(r["amount"] for r in s3)
    if round(s3_total, 2) <= 0:
        return ""
    current = months[-1]
    cur = [r for r in current["records"] if r["category"] == S3_SERVICE]
    by_kind = sum_by(s3, "kind")
    has_quantity = any(r.get("quantity") for r in s3)

    # hints
    hints = []
    read_cost = sum(by_kind.get(k, 0.0) for k in S3_READ_KINDS)
    storage_cost = by_kind.get("storage", 0.0)
    if read_cost > 0.5 * s3_total:
        hints.append({"severity": "HIGH", "text": f"{100 * read_cost / s3_total:.0f}% of the S3 cost ({money(read_cost)}) comes from reading the data "
                                                  f"(data sent out and retrieval fees), storage is only {pct(storage_cost, s3_total)} "
                                                  f"({money(storage_cost)}): something downloads it, deleting objects would barely change the bill."})
    dests = sum_by([r for r in s3 if r["kind"] in ("internet", "region")], lambda r: (r["dest"], r.get("src", "")))
    for (dest, src), v in ranked(dests)[:2]:
        if v < 0.1 * s3_total:
            break
        gb = sum(r.get("quantity", 0.0) for r in s3 if r["kind"] in ("internet", "region") and r["dest"] == dest and r.get("src") == src)
        volume = f"{fmt_quantity(gb, 'GB')} " if gb else ""
        if dest == "Internet":
            hints.append({"severity": "MEDIUM", "text": f"{volume}sent from {src} to the Internet ({money(v)}): downloads from outside AWS, "
                                                        "laptops or GitHub-hosted runners (they run on Azure)."})
        else:
            hints.append({"severity": "MEDIUM", "text": f"{volume}sent from {src} to {dest} ({money(v)}): something running in {dest} "
                                                        f"(EC2, CI runners...) downloads from the bucket; a copy in {dest}, or a cache on its side, "
                                                        "would remove it."})
    retrieval = by_kind.get("retrieval", 0.0)
    if retrieval > max(storage_cost, 0.05 * s3_total):
        ia = [b["name"] for b in buckets or [] if any("IA" in t for t in b.get("lifecycle", []))]
        hints.append({"severity": "MEDIUM", "text": f"Retrieval fees ({money(retrieval)}) cost more than the storage ({money(storage_cost)}): the objects are "
                                                    "read too often for an infrequent access class. STANDARD or INTELLIGENT_TIERING have no retrieval fee"
                                                    + (f"; lifecycle rule moving objects to an IA class on {', '.join(ia)}." if ia else ".")})
    if buckets is not None and read_cost > 0.1 * s3_total:
        no_log = [b["name"] for b in buckets if not b.get("logging_target") and sum(s.get("bytes", 0) for s in b.get("storage", [])) > 1e9]
        if no_log:
            hints.append({"severity": "LOW", "text": f"Server access logging is off on {', '.join(no_log)}: nothing records who downloads. "
                                                     "Turn it on (aws s3api put-bucket-logging) to see the requester and source IP of each GET."})
    if buckets is None:
        hints.append({"severity": "INFO", "text": f"The S3 buckets tagged cflt_managed_id={user} could not be listed (resourcegroupstaggingapi, CloudWatch)."})

    parts = [rh.findings_html(rh.sort_findings(hints))] if hints else []

    # per kind, 12 months and current period
    rows = []
    for k, label, what in S3_KINDS:
        recs = [r for r in s3 if r["kind"] == k]
        if not recs or round(sum(r["amount"] for r in recs), 4) == 0 and k != "in":
            continue
        crecs = [r for r in cur if r["kind"] == k]
        v = sum(r["amount"] for r in recs)
        row = [f"{e(label)}<div class='muted' style='font-size:.75rem'>{e(what)}</div>"]
        if has_quantity:
            row.append(e(quantity_of(recs)))
        row += [money(v), f"{100 * v / s3_total:.1f}%"]
        if has_quantity:
            row.append(e(quantity_of(crecs)))
        row.append(money(sum(r["amount"] for r in crecs)))
        rows.append(row)
    headers = ["Kind of usage"] + (["Volume"] if has_quantity else []) + ["Cost", "Share"] \
        + (["Volume, current period"] if has_quantity else []) + ["Cost, current period"]
    parts.append("<h3>Per kind of usage <span class='muted'>(last 12 months, and current period)</span></h3>"
                 + rh.table(headers, rows, num=tuple(range(1, len(headers)))))

    # kind x month
    kinds = [k for k, _ in ranked(by_kind)]
    per_month = [sum_by([r for r in m["records"] if r["category"] == S3_SERVICE], "kind") for m in months]
    mx = max((v for pm in per_month for v in pm.values()), default=0)
    month_headers = [f"<span title='{e(range_label(m))}'>{e(short_label(m))}</span>" for m in months]
    rows = []
    for k in kinds:
        row = [e(S3_KIND_LABEL[k])]
        for m, pm in zip(months, per_month):
            v = pm.get(k, 0.0)
            if not round(v, 4):
                row.append("<span class='muted'>-</span>")
                continue
            q = quantity_of([r for r in m["records"] if r["category"] == S3_SERVICE and r["kind"] == k])
            row.append(f"<span{heat(v, mx)} title='{e(q)}'>{money(v)}</span>")
        rows.append(row)
    parts.append("<h3>Per kind of usage and per month <span class='muted'>(hover a cell for the volume)</span></h3>"
                 + rh.table(["Kind of usage"] + month_headers, rows, num=tuple(range(1, len(months) + 1))))

    # data sent out, per destination
    out_recs = [r for r in s3 if r["kind"] in ("internet", "region")]
    if out_recs:
        rows = []
        for (dest, src), v in ranked(sum_by(out_recs, lambda r: (r["dest"], r.get("src", ""))))[:15]:
            recs = [r for r in out_recs if r["dest"] == dest and r.get("src") == src]
            crecs = [r for r in recs if r in cur]
            row = [e(src), e(dest)]
            if has_quantity:
                row.append(e(quantity_of(recs)))
            row.append(money(v))
            if has_quantity:
                row.append(e(quantity_of(crecs)))
            row.append(money(sum(r["amount"] for r in crecs)))
            rows.append(row)
        headers = ["From", "To"] + (["Volume"] if has_quantity else []) + ["Cost"] \
            + (["Volume, current period"] if has_quantity else []) + ["Cost, current period"]
        parts.append("<h3>Data sent out, per destination <span class='muted'>(last 12 months, and current period)</span></h3>"
                     + rh.table(headers, rows, num=tuple(range(2, len(headers)))))

    # top usage types, with their plain meaning
    rows = []
    usage_tot = sum_by(s3, "item")
    for usage, v in ranked(usage_tot)[:15]:
        recs = [r for r in s3 if r["item"] == usage]
        row = [f"<span class='mono' style='word-break:normal'>{e(usage)}</span>", e(S3_KIND_LABEL[recs[0]["kind"]]), e(recs[0]["label"])]
        if has_quantity:
            row.append(e(quantity_of(recs)))
        row += [money(v), f"{100 * v / s3_total:.1f}%"]
        rows.append(row)
    headers = ["Usage type", "Kind", "Meaning"] + (["Volume"] if has_quantity else []) + ["Cost", "Share"]
    parts.append("<h3>Top usage types <span class='muted'>(last 12 months)</span></h3>"
                 + rh.table(headers, rows, num=tuple(range(3, len(headers)))))

    # buckets
    if buckets:
        rows = []
        for b in sorted(buckets, key=lambda b: -sum(s.get("bytes", 0) for s in b.get("storage", []))):
            storage = b.get("storage", [])
            size = sum(s.get("bytes", 0) for s in storage)
            classes = ", ".join(f"{s['type'].replace('Storage', '')}: {rh.fmt_bytes(s['bytes'])}" for s in sorted(storage, key=lambda s: -s.get("bytes", 0)) if s.get("bytes"))
            objects = f"{int(b['objects']):,}" if b.get("objects") is not None else "-"
            logging = (f"✅ to {e(b['logging_target'])}" if b.get("logging_target") else "❌ off")
            rows.append([f"<span class='mono' style='word-break:normal'>{e(b['name'])}</span>", e(b.get("region", "")),
                         rh.fmt_bytes(size) if size else "<span class='muted'>empty</span>", e(classes or "-"), objects, logging,
                         e(", ".join(b.get("lifecycle", [])) or "-")])
        parts.append(f"<h3>{len(buckets)} bucket{'s' if len(buckets) > 1 else ''} tagged cflt_managed_id={e(user)} "
                     "<span class='muted'>(size from the daily CloudWatch metrics)</span></h3>"
                     + rh.table(["Bucket", "Region", "Size", "Per storage class", "Objects", "Access logging", "Lifecycle"], rows, num=(2, 4)))
    elif buckets is not None:
        parts.append(f"<p class='muted'>No S3 bucket tagged cflt_managed_id={e(user)} found.</p>")
    parts.append("<p class='muted' style='font-size:.8rem;margin-top:8px'>Cost Explorer has no cost per bucket for this account: "
                 "it needs the resource-level data, an opt-in of the payer account.</p>")

    # id: link target (reports gallery of the docs: reports/aws-costs.html#s3-details)
    return "<div id='s3-details'>" + rh.card(f"🪣 Amazon S3 details <span class='muted'>({money(s3_total)} over the last 12 months, "
                                             f"{100 * s3_total / max(sum(r['amount'] for m in months for r in m['records']), 0.01):.0f}% of the total)</span>",
                                             "".join(parts)) + "</div>"


def still_billing(records: List[dict]) -> set:
    """ccloud: the resources with a cost on each of the last 3 days with data (not a connector of a short run that day)"""
    last_day = max((r["day"] for r in records), default="")
    if not last_day:
        return set()
    recent_days = {(date.fromisoformat(last_day) - timedelta(days=i)).isoformat() for i in range(3)}
    billed_days: Dict[str, set] = defaultdict(set)
    for r in records:
        if r["day"] in recent_days and r["amount"] > 0:
            billed_days[r["item_id"] or r["item"]].add(r["day"])
    return {k for k, d in billed_days.items() if d == recent_days}


def still_billing_card(records: List[dict], billing_now: set) -> str:
    last_day = max(r["day"] for r in records)
    last_cost = sum_by([r for r in records if r["day"] == last_day], lambda r: r["item_id"] or r["item"])
    info = {}
    for r in records:
        info.setdefault(r["item_id"] or r["item"], r)
    rows = [[e(info[k]["item"]), f"<span class='mono' style='word-break:normal;white-space:nowrap'>{e(info[k]['item_id'])}</span>",
             e(info[k]["category"]), e(info[k]["group"]), money(last_cost.get(k, 0)), money(30 * last_cost.get(k, 0))]
            for k in sorted(billing_now, key=lambda k: -last_cost.get(k, 0))][:30]
    return rh.card(f"🔥 {len(billing_now)} resource{'s' if len(billing_now) > 1 else ''} still billing <span class='muted'>(billed on each of the last 3 days with data, "
                   f"most expensive first)</span>",
                   rh.table(["Resource", "Id", "Product", "Environment", f"Cost on {e(last_day)}", "≈ per month"], rows, num=(4, 5)))


def build(cloud: str, user: str, months: List[dict], buckets: Optional[List[dict]] = None) -> str:
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
    billing_now = set()
    if cloud == "ccloud":
        billing_now = still_billing(records)
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

        if cloud == "aws":
            body.append(s3_section(months, buckets, user))

        if cloud == "ccloud" and billing_now:
            body.append(still_billing_card(records, billing_now))

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


def build_range(user: str, period: dict) -> str:
    """ccloud, one range of dates (playground ccloud-costs): per day, product, environment, resource and line type"""
    lab = LABELS["ccloud"]
    records = period["records"]
    total = sum(r["amount"] for r in records)
    daily = sum_by(records, "day")
    start, end = date.fromisoformat(period["start"]), date.fromisoformat(period["end"])
    # the end date is exclusive
    days = [(start + timedelta(days=i)).isoformat() for i in range(max(1, (end - start).days))]
    with_data = [d for d in days if d in daily]
    per_day = total / len(with_data) if with_data else 0.0
    by_category = ranked(sum_by(records, "category"))
    by_group = ranked(sum_by(records, "group"))
    billing_now = still_billing(records)
    billing_daily = sum(r["amount"] for r in records if r["day"] == max(daily, default="") and (r["item_id"] or r["item"]) in billing_now)

    body = []
    if not period["ok"]:
        body.append(rh.verdict_html("warn", "⚠️ The cost data could not be read."))
    elif not records:
        body.append(rh.verdict_html("ok", f"✅ No {lab['name']} cost from {range_label(period)}."))
    elif billing_now:
        body.append(rh.verdict_html("warn", f"⚠️ {money(total)} from {range_label(period)}, {money(per_day)} per day on average: "
                                            f"{len(billing_now)} resource{'s' if len(billing_now) > 1 else ''} still billing "
                                            f"{money(billing_daily)} a day, check them below."))
    else:
        body.append(rh.verdict_html("ok", f"✅ {money(total)} from {range_label(period)}, {money(per_day)} per day on average, "
                                          "nothing billed on each of the last 3 days."))

    cards = [
        rh.kpi("Total", money(total), range_label(period)),
        rh.kpi("Days with data", f"{len(with_data)} / {len(days)}", "the last days can be incomplete"),
        rh.kpi("Per day", money(per_day), "average over the days with data"),
        rh.kpi("≈ per month", money(30 * per_day), "at this pace"),
        rh.kpi(f"Top {lab['category']}", money(by_category[0][1]) if by_category else "-",
               f"{by_category[0][0]} ({100 * by_category[0][1] / total:.0f}%)" if by_category and total else ""),
        rh.kpi("Resources still billing", str(len(billing_now)), "billed on each of the last 3 days with data",
               "warn" if billing_now else "ok"),
    ]
    discount = sum(r["discount"] for r in records)
    if discount:
        cards.append(rh.kpi("Discounts", money(abs(discount)), "already deducted"))
    body.append(rh.kpis_html(cards))

    if records:
        body.append(rh.charts_grid([
            ("📆 Cost per day", svg_columns(
                [(datetime.strptime(d, "%Y-%m-%d").strftime("%b %d"), daily.get(d, 0.0), d, True) for d in days])),
            (f"👛 Cost per {lab['category']}", rh.svg_hbars([(k, v, f"{k}: {money(v)}") for k, v in by_category[:15]], money)),
            ("🌍 Cost per environment", rh.svg_hbars([(k or "(none)", v, f"{k}: {money(v)}") for k, v in by_group[:15]], money)),
        ]))

        if billing_now:
            body.append(still_billing_card(records, billing_now))

        # top resources
        items: Dict[str, dict] = {}
        for r in records:
            it = items.setdefault(r["item_id"] or r["item"], {"item": r["item"], "item_id": r["item_id"], "category": r["category"],
                                                              "group": r["group"], "details": set(), "total": 0.0, "days": set()})
            it["total"] += r["amount"]
            if r["detail"]:
                it["details"].add(r["detail"])
            if r["amount"] > 0:
                it["days"].add(r["day"])
        top = sorted((it for it in items.values() if round(it["total"], 4) != 0), key=lambda it: -it["total"])

        def item_row(it: dict, with_category: bool = True) -> List[str]:
            key = it["item_id"] or it["item"]
            row = [e(it["item"]) + (" " + rh.badge("still billing", "warn") if key in billing_now else ""),
                   f"<span class='mono' style='word-break:normal;white-space:nowrap'>{e(it['item_id'])}</span>"]
            if with_category:
                row.append(e(it["category"]))
            days_billed = sorted(it["days"])
            row += [e(it["group"]), f"<span class='mono'>{e(', '.join(sorted(it['details'])))}</span>", str(len(days_billed)),
                    f"<span style='white-space:nowrap'>{e(days_billed[0] if days_billed else '-')}</span>",
                    f"<span style='white-space:nowrap'>{e(days_billed[-1] if days_billed else '-')}</span>",
                    money(it["total"]), f"{100 * it['total'] / total:.1f}%" if total else "-"]
            return row

        tail = ["Environment", "Line types", "Days billed", "First billed", "Last billed", "Total", "Share"]
        headers = ["Resource", "Id", lab["category"].capitalize()] + tail
        body.append(rh.card(f"🔝 Top {min(30, len(top))} {lab['items']} <span class='muted'>(of {len(top)})</span>",
                            rh.table(headers, [item_row(it) for it in top[:30]], num=tuple(range(len(headers) - 4, len(headers))))))

        # the resources of each product, like the text output
        details = []
        for c, v in by_category:
            rows = [item_row(it, False) for it in top if it["category"] == c]
            headers = ["Resource", "Id"] + tail
            details.append(f"<details><summary><b>{e(c)}</b>: {money(v)} <span class='muted'>({100 * v / total:.1f}%, "
                           f"{len(rows)} {lab['item'] if len(rows) == 1 else lab['items']})</span></summary>"
                           + rh.table(headers, rows, num=tuple(range(len(headers) - 4, len(headers)))) + "</details>")
        body.append(rh.card(f"🔍 {lab['items'].capitalize()} per {lab['category']}", "".join(details)))

        # product x environment matrix
        groups = [k for k, _ in by_group]
        per_cat = {c: sum_by([r for r in records if r["category"] == c], "group") for c, _ in by_category}
        mx = max((v for pc in per_cat.values() for v in pc.values()), default=0)
        rows = [[e(c)] + [f"<span{heat(per_cat[c].get(g, 0), mx)}>{money(per_cat[c][g])}</span>" if round(per_cat[c].get(g, 0), 4)
                          else "<span class='muted'>-</span>" for g in groups] + [f"<b>{money(v)}</b>"] for c, v in by_category]
        rows.append(["<b>Total</b>"] + [f"<b>{money(v)}</b>" for _, v in by_group] + [f"<b>{money(total)}</b>"])
        body.append(rh.card(f"🗂️ {lab['categories'].capitalize()} per environment",
                            rh.table([lab["category"].capitalize()] + [e(g or "(none)") for g in groups] + ["Total"], rows,
                                     num=tuple(range(1, len(groups) + 2)))))

        lines = sum_by(records, lambda r: (r["category"], r["detail"]))
        rows = [[e(c), f"<span class='mono'>{e(d)}</span>", money(v), f"{100 * v / total:.1f}%" if total else "-"]
                for (c, d), v in sorted(lines.items(), key=lambda kv: -kv[1]) if round(v, 4) != 0][:30]
        body.append(rh.card("🧾 Cost per line type", rh.table(["Product", "Line type", "Total", "Share"], rows, num=(2, 3))))

    notes = [DELAY_NOTE["ccloud"],
             "Costs of the whole organization the confluent CLI is logged into (confluent billing cost list), amounts after discounts.",
             "The end date is excluded. One month is the maximum window, the start date can go back one year.",
             "Cost per month over the last year: playground ccloud-costs-history."]
    body.append(rh.card("💡 Notes", "<ul style='margin-left:18px;font-size:.86rem'>" + "".join(f"<li>{e(n)}</li>" for n in notes) + "</ul>"))

    css = ("<style>.kpi-grid{grid-template-columns:repeat(auto-fill,minmax(140px,1fr))}.kpi-value{font-size:1.4rem;white-space:nowrap}"
           "td .heat{display:block;margin:-7px -11px;padding:7px 11px}</style>")
    return rh.page(f"{lab['name']} costs", f"💰 {e(lab['name'])} costs, {e(range_label(period))}",
                   [f"☁️ {e(lab['name'])}", f"🗓️ {e(range_label(period))}"], css + "".join(body),
                   f"playground ccloud-costs --start-date {period['start']} --end-date {period['end']}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cloud", required=True, choices=sorted(PARSERS))
    ap.add_argument("--data-dir")
    ap.add_argument("--user", default=os.environ.get("USER", ""))
    ap.add_argument("--html-out", required=True)
    ap.add_argument("--range-file", help="ccloud only: report of this one range of dates (<start date>_<end date>.json) "
                                         "instead of the months of --data-dir")
    a = ap.parse_args()
    if a.range_file:
        m = FILE_RE.match(os.path.basename(a.range_file))
        if a.cloud != "ccloud" or not m:
            ap.error("--range-file: ccloud only, file named <start date>_<end date>.json")
        period = {"start": m.group(1), "end": m.group(2), "ok": True, "records": []}
        try:
            with open(a.range_file, encoding="utf-8") as fh:
                period["records"] = parse_ccloud(json.load(fh), period)
        except (OSError, ValueError):
            period["ok"] = False
        with open(a.html_out, "w", encoding="utf-8") as fh:
            fh.write(build_range(a.user, period))
        return 0
    if not a.data_dir:
        ap.error("--data-dir or --range-file is required")
    months = fill_missing_months(load_months(a.cloud, a.data_dir))
    # aws: the S3 buckets tagged cflt_managed_id=<user>, saved by costs-history (None: not listed)
    buckets = None
    try:
        with open(os.path.join(a.data_dir, "s3-buckets.json"), encoding="utf-8") as fh:
            buckets = json.load(fh)
    except (OSError, ValueError):
        pass
    with open(a.html_out, "w", encoding="utf-8") as fh:
        fh.write(build(a.cloud, a.user, months, buckets if isinstance(buckets, list) else None))
    return 0


if __name__ == "__main__":
    sys.exit(main())
