#!/usr/bin/env python3
"""Known vulnerabilities of the jars of a connector plugin version, from a grype scan of its lib/ folder.

One --scan: the vulnerabilities, worst first. Two (--scan for the version in use, --compare-scan for the other one):
fixed by the other version, still there, new. --changelog (the JSON of tools/connector-changelog/changelog.py) tells in
which version the release notes mention each CVE id. Prints a JSON document on stdout; --html-out writes a report.

The result is what a scanner sees in the jars, not an official statement: a vulnerable library can be unused, or its
vulnerable code unreachable, in the connector.
"""
import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "report-common"))
import report_html as rh  # noqa: E402

SEVERITIES = ["Critical", "High", "Medium", "Low", "Negligible", "Unknown"]


def vulnerabilities(path):
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    out = {}
    for m in doc.get("matches", []):
        v, a = m.get("vulnerability", {}), m.get("artifact", {})
        aliases = sorted({r.get("id") for r in m.get("relatedVulnerabilities", []) if r.get("id")} - {v.get("id")})
        cve = next((x for x in [v.get("id")] + aliases if x and x.startswith("CVE-")), None)
        vid = cve or v.get("id")
        location = (a.get("locations") or [{}])[0].get("path", "").lstrip("/")
        key = (vid, a.get("name"), a.get("version"))
        if key in out:
            if location and location not in out[key]["jars"]:
                out[key]["jars"].append(location)
            continue
        out[key] = {
            "id": vid,
            "aliases": [x for x in [v.get("id")] + aliases if x and x != vid],
            "severity": v.get("severity") or "Unknown",
            "library": a.get("name"),
            "version": a.get("version"),
            "jars": [location] if location else [],
            "fixed_in": (v.get("fix") or {}).get("versions") or [],
            "url": v.get("dataSource"),
        }
    return sorted(out.values(), key=lambda x: (SEVERITIES.index(x["severity"]) if x["severity"] in SEVERITIES else 9, x["id"], x["library"] or ""))


def keep(vulns, min_severity):
    if not min_severity:
        return vulns
    limit = SEVERITIES.index(min_severity.capitalize())
    return [v for v in vulns if v["severity"] in SEVERITIES and SEVERITIES.index(v["severity"]) <= limit]


def counts(vulns):
    return {s: sum(1 for v in vulns if v["severity"] == s) for s in SEVERITIES if any(v["severity"] == s for v in vulns)}


def mentioned_in(changelog, vid):
    if not changelog or not vid.startswith("CVE-"):
        return None
    for version in sorted(changelog.get("versions", []), key=lambda v: [int(p) if p.isdigit() else 0 for p in re.split(r"[.-]", v["version"])]):
        if any(vid in c for c in version.get("changes", [])):
            return version["version"]
    return None


def html_report(result, path):
    sev_cls = {"Critical": "fatal", "High": "error", "Medium": "warn", "Low": "paused"}

    def rows(vulns, extra=None):
        out = []
        for v in vulns:
            row = [rh.badge(v["severity"], sev_cls.get(v["severity"], "")),
                   f"<a href='{rh.e(v['url'])}'>{rh.e(v['id'])}</a>" if v.get("url") else rh.e(v["id"]),
                   rh.e(v["library"]), rh.e(v["version"]), rh.e(", ".join(v["fixed_in"]) or "-"), rh.e(", ".join(v["jars"]))]
            if extra:
                row.append(rh.e(extra(v) or "-"))
            out.append(row)
        return out

    body = []
    if "fixed" in result:
        c_old, c_new = result["counts_from"], result["counts_to"]
        body.append(rh.kpis_html([rh.kpi(f"in {result['from']}", sum(c_old.values()), "vulnerabilities"),
                                  rh.kpi(f"in {result['to']}", sum(c_new.values()), "vulnerabilities"),
                                  rh.kpi("fixed", len(result["fixed"]), f"by {result['to']}", "ok"),
                                  rh.kpi("new", len(result["new"]), f"in {result['to']}", "warn" if result["new"] else "")]))
        headers = ["Severity", "Vulnerability", "Library", "Version", "Fixed in (library)", "Jar"]
        body.append(rh.card(f"✅ Fixed by {rh.e(result['to'])} ({len(result['fixed'])})",
                            rh.table(headers + ["In the release notes of"], rows(result["fixed"], lambda v: v.get("release_notes")))))
        body.append(rh.card(f"⚠️ Still in {rh.e(result['to'])} ({len(result['still'])})", rh.table(headers, rows(result["still"]))))
        body.append(rh.card(f"🆕 New in {rh.e(result['to'])} ({len(result['new'])})", rh.table(headers, rows(result["new"]))))
    else:
        c = result["counts"]
        body.append(rh.kpis_html([rh.kpi(s, n, "vulnerabilities", "fatal" if s in ("Critical", "High") else "") for s, n in c.items()]
                                 or [rh.kpi("vulnerabilities", 0, "found", "ok")]))
        body.append(rh.card(f"🛡️ Vulnerabilities ({len(result['vulnerabilities'])})",
                            rh.table(["Severity", "Vulnerability", "Library", "Version", "Fixed in (library)", "Jar"], rows(result["vulnerabilities"]))))
    body.append(rh.verdict_html("warn", "What a scanner sees in the jars, not an official Confluent statement: a vulnerable library can be "
                                        "unused, or its vulnerable code unreachable. Check the Confluent security advisories."))
    meta = [rh.e(result["plugin"]), rh.e(f"scanner: {result.get('scanner', 'grype')}")]
    with open(path, "w", encoding="utf-8") as f:
        f.write(rh.page(f"CVE scan — {result['plugin']}", "🛡️ Connector Plugin CVE Scan", meta, "".join(body),
                        "playground connector-plugin cve-scan"))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--scan", required=True, help="grype JSON of the version in use")
    p.add_argument("--compare-scan", help="grype JSON of the version to compare with")
    p.add_argument("--label", required=True)
    p.add_argument("--compare-label")
    p.add_argument("--plugin", required=True)
    p.add_argument("--min-severity", choices=[s.lower() for s in SEVERITIES[:4]])
    p.add_argument("--changelog", help="JSON of changelog.py between the two versions")
    p.add_argument("--html-out")
    a = p.parse_args()

    old = keep(vulnerabilities(a.scan), a.min_severity)
    if not a.compare_scan:
        result = {"plugin": a.plugin, "version": a.label, "counts": counts(old), "vulnerabilities": old}
    else:
        new = keep(vulnerabilities(a.compare_scan), a.min_severity)
        changelog = None
        if a.changelog and os.path.exists(a.changelog):
            with open(a.changelog, encoding="utf-8") as f:
                changelog = json.load(f)
        new_ids = {(v["id"], v["library"]) for v in new}
        old_ids = {(v["id"], v["library"]) for v in old}
        fixed = [dict(v, release_notes=mentioned_in(changelog, v["id"])) for v in old if (v["id"], v["library"]) not in new_ids]
        result = {"plugin": a.plugin, "from": a.label, "to": a.compare_label,
                  "counts_from": counts(old), "counts_to": counts(new),
                  "fixed": fixed,
                  "still": [v for v in new if (v["id"], v["library"]) in old_ids],
                  "new": [v for v in new if (v["id"], v["library"]) not in old_ids]}
    if a.html_out:
        html_report(result, a.html_out)
        result["html_report"] = a.html_out
    json.dump(result, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
