#!/usr/bin/env python3
"""
HTML report of 'playground tools cert inspect': the certificates of a keystore, truststore, PEM / DER file or server,
and the checks that explain the TLS errors of Kafka clients (expired certificate, incomplete chain, hostname not in the
subject alternative names, truststore that does not trust the chain, key that does not match).

Written for someone who is new to TLS: every check says what it means, why it matters, the java error it causes and
how to fix it, and the page starts with a short explanation of certificates, chains, keystores and truststores.

Input: the JSON printed by 'playground tools cert inspect --json' (stdin or --json-file).
Usage: cert_report.py --json-file result.json --out report.html [--file f] [--server s] [--hostname h]
                      [--truststore t] [--purpose server|client]
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "report-common"))
import report_html as rh  # noqa: E402
from report_html import e  # noqa: E402

# what a check means, why it matters, the error it causes in a java (Kafka) client
EXPLAIN = {
    "expiry": {
        "title": "Certificate expiry",
        "what": "Every certificate has an end date. After it, nobody accepts it any more, even if nothing else changed.",
        "why": "An expired certificate in a broker, a client or the chain breaks every TLS connection at once, usually "
               "on the day it expires, without any change in the configuration.",
        "error": "javax.net.ssl.SSLHandshakeException: PKIX path validation failed: java.security.cert.CertificateExpiredException: NotAfter: …",
    },
    "validity": {
        "title": "Certificate not valid yet",
        "what": "A certificate also has a start date: before it, it is refused.",
        "why": "It happens when the clock of the machine that created the certificate (or of the machine that checks it) is wrong.",
        "error": "java.security.cert.CertificateNotYetValidException: NotBefore: …",
    },
    "keysize": {
        "title": "Key too small",
        "what": "The key of the certificate is what proves its identity. A short RSA key can be broken.",
        "why": "Recent JDKs refuse RSA keys under 2048 bits (jdk.certpath.disabledAlgorithms in java.security).",
        "error": "java.security.cert.CertPathValidatorException: Algorithm constraints check failed on keysize limits",
    },
    "signature": {
        "title": "Weak signature",
        "what": "A certificate is signed by its issuer with a hash algorithm. SHA-1 is not considered safe any more.",
        "why": "Recent JDKs refuse SHA-1 signed certificates.",
        "error": "java.security.cert.CertPathValidatorException: Algorithm constraints check failed on signature algorithm: SHA1withRSA",
    },
    "chain_order": {
        "title": "Certificate chain",
        "what": "Your certificate is signed (issued) by a certificate authority (CA), whose certificate can itself be "
                "issued by another CA, up to a root CA. That list is the chain, and it must be in order: your "
                "certificate first, then the CA that issued it, and so on.",
        "why": "When a certificate of the chain is missing or in the wrong place, the other side cannot link your "
               "certificate to a CA it trusts.",
        "error": "javax.net.ssl.SSLHandshakeException: PKIX path building failed: … unable to find valid certification path to requested target",
    },
    "chain_end": {
        "title": "End of the chain",
        "what": "A chain normally ends with a root CA certificate, which is signed by itself (self signed). It is "
                "fine for a chain to stop before the root, as long as the other side already has the root (or the "
                "intermediate) in its truststore.",
        "why": "The other side trusts your certificate only if one certificate of the chain is in its truststore.",
        "error": "PKIX path building failed: unable to find valid certification path to requested target (when the truststore lacks it)",
    },
    "first_ca": {
        "title": "First certificate of the chain",
        "what": "The first certificate of a keystore entry is the one presented during the connection: it should be "
                "the certificate of the broker or client itself, not the certificate of a CA.",
        "why": "A CA certificate presented as server certificate does not carry the name of the server.",
        "error": "No subject alternative names matching … found, or bad_certificate on the other side",
    },
    "hostname": {
        "title": "Hostname verification",
        "what": "A client checks that the server it connects to is the one named in the certificate. Java (and so "
                "Kafka) only looks at the Subject Alternative Names (SAN) of the certificate: the CN of the subject "
                "is ignored.",
        "why": "If the name used in bootstrap.servers (or the advertised listener) is not in the SANs, the client "
               "refuses the broker, even when the certificate is trusted. A wildcard *.example.com covers exactly "
               "one level: broker1.example.com, not a.b.example.com.",
        "error": "javax.net.ssl.SSLHandshakeException: No subject alternative names matching DNS name … found (or: No subject alternative names present)",
    },
    "eku": {
        "title": "Allowed usage",
        "what": "The extended key usage of a certificate says what it may be used for: TLS server authentication "
                "(a broker, Schema Registry…) and / or TLS client authentication (a client in mTLS).",
        "why": "A certificate without the usage of its role is refused by the other side.",
        "error": "java.security.cert.CertificateException: Extended key usage does not permit use for TLS server (or client) authentication",
    },
    "privkey": {
        "title": "Private key",
        "what": "A certificate holds a public key; the matching private key stays secret on the broker or client. "
                "Both must belong together.",
        "why": "With a key that does not belong to the certificate, the TLS handshake fails, and keytool refuses to "
               "import a CA reply.",
        "error": "keytool error: java.lang.Exception: Public keys in reply and keystore don't match (or a handshake failure on the other side)",
    },
    "truststore": {
        "title": "Trusted by the truststore",
        "what": "The truststore is the list of CA certificates a client (or broker) trusts. A certificate is trusted "
                "when one certificate of its chain is in the truststore.",
        "why": "This is the most frequent TLS error of Kafka clients: the truststore does not contain the CA that "
               "issued the broker certificate.",
        "error": "javax.net.ssl.SSLHandshakeException: PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target",
    },
}

# commands that fix a problem, for the 'How to fix' blocks
FIX_COMMANDS = {
    "truststore": "# add the CA certificate (root, or intermediate) to the truststore\n"
                  "keytool -importcert -alias my-ca -file ca.crt -keystore truststore.jks -storepass <password> -noprompt",
    "hostname": "# create the key and certificate request with the hostname(s) in the SAN\n"
                "keytool -genkeypair -alias broker -keyalg RSA -keysize 2048 -keystore keystore.jks \\\n"
                "  -dname \"CN=broker\" -ext SAN=dns:broker,dns:broker.example.com\n"
                "keytool -certreq -alias broker -keystore keystore.jks -ext SAN=dns:broker,dns:broker.example.com -file broker.csr",
    "chain_order": "# import the CA certificates first, then the signed certificate: keytool builds the chain in order\n"
                   "keytool -importcert -alias root-ca -file root.crt -keystore keystore.jks\n"
                   "keytool -importcert -alias intermediate-ca -file intermediate.crt -keystore keystore.jks\n"
                   "keytool -importcert -alias broker -file broker-signed.crt -keystore keystore.jks",
    "expiry": "# see the dates of every certificate of a keystore\n"
              "keytool -list -v -keystore keystore.jks | grep -E 'Alias name|Valid from'",
    "privkey": "# compare the public key of the certificate and of the private key: both lines must be the same\n"
               "openssl x509 -in cert.pem -noout -pubkey | openssl sha256\n"
               "openssl pkey -in key.pem -pubout | openssl sha256",
}

USAGE_WORDS = {
    "TLS Web Server Authentication": "can prove the identity of a server",
    "TLS Web Client Authentication": "can prove the identity of a client (mTLS)",
    "Digital Signature": "signs",
    "Key Encipherment": "encrypts keys",
    "Certificate Sign": "signs other certificates (a CA)",
    "CRL Sign": "signs revocation lists (a CA)",
    "Key Agreement": "agrees on keys",
    "Code Signing": "signs code",
    "E-mail Protection": "protects e-mails",
}

KIND_WORDS = {
    "PrivateKeyEntry": "key pair entry (private key + its certificate chain): what a keystore holds",
    "trustedCertEntry": "trusted certificate: what a truststore holds",
    "pem": "PEM file (text, -----BEGIN CERTIFICATE-----)",
    "der": "DER file (binary certificate)",
    "server": "certificates sent by the server during the TLS handshake",
}

GLOSSARY = [
    ("Certificate", "A file that ties a name (a server, a client) to a public key, signed by a certificate authority."),
    ("CA (certificate authority)", "Who signs certificates. A root CA signs itself; an intermediate CA is signed by another CA."),
    ("Chain", "Your certificate, then the CA that issued it, then the CA that issued that one… up to a root."),
    ("Keystore", "Holds the private key and the certificate chain of a broker or client: what it presents to prove who it is (ssl.keystore.location)."),
    ("Truststore", "Holds the CA certificates a broker or client trusts: what it uses to check the other side (ssl.truststore.location)."),
    ("Subject / CN", "The name inside the certificate (CN = common name). Java does not use the CN to check the hostname."),
    ("SAN (subject alternative name)", "The list of DNS names and IP addresses the certificate is valid for: the hostname of the connection must be in it."),
    ("Issuer", "The CA that signed the certificate: it must be the subject of the next certificate of the chain."),
    ("EKU (extended key usage)", "What the certificate may be used for: TLS server and / or client authentication."),
    ("Self signed", "Signed by itself: a root CA, or a test certificate that has to be in the truststore of the other side."),
    ("PEM / DER", "Two encodings of a certificate: PEM is text (-----BEGIN CERTIFICATE-----), DER is binary."),
    ("JKS / PKCS12", "Two keystore formats used by java. PKCS12 (.p12, .pfx) is the default since java 9."),
    ("Fingerprint (SHA-256)", "A short unique digest of a certificate, to compare two certificates quickly."),
]

CSS = """
.explain{background:#fff;border-radius:10px;padding:16px 20px;box-shadow:0 1px 3px rgba(0,0,0,.07);margin-bottom:22px;font-size:.9rem}
.explain h2{margin-bottom:8px}.explain p{margin:6px 0}.explain ul{margin:6px 0 6px 20px}
.flow{display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin:12px 0}
.flow .box{border:2px solid #2563eb;border-radius:8px;padding:6px 10px;background:#eff6ff;font-size:.82rem;max-width:300px}
.flow .arrow{color:#64748b;font-size:.8rem}
.problem{background:#fff;border-radius:10px;box-shadow:0 1px 3px rgba(0,0,0,.07);margin-bottom:14px;border-left:5px solid #94a3b8;padding:14px 18px}
.problem.fail{border-left-color:#dc2626}.problem.warn{border-left-color:#d97706}.problem.ok{border-left-color:#16a34a}.problem.info{border-left-color:#3b82f6}
.problem h3{font-size:.98rem;margin-bottom:6px}
.problem .row{margin:6px 0;font-size:.88rem}.problem .lbl{font-weight:600;color:#475569;margin-right:6px}
.problem pre{margin-top:6px}
.chain{display:flex;flex-direction:column;gap:0;margin:10px 0 4px}
.certbox{background:#fff;border:1px solid #e2e8f0;border-radius:10px;padding:12px 16px;box-shadow:0 1px 2px rgba(0,0,0,.05)}
.certbox.bad{border-color:#dc2626}.certbox.warnb{border-color:#d97706}
.certbox h4{font-size:.95rem;margin-bottom:6px}
.issued{color:#64748b;font-size:.8rem;margin:4px 0 4px 26px}
.kv{display:grid;grid-template-columns:150px 1fr;gap:3px 12px;font-size:.84rem}
.kv .k{color:#64748b}
.chip{display:inline-block;background:#f1f5f9;border-radius:12px;padding:1px 8px;margin:1px 3px 1px 0;font-size:.78rem}
.chip.hit{background:#dcfce7;color:#166534;font-weight:600}
.bar{position:relative;height:10px;border-radius:5px;background:#dcfce7;margin:6px 0 2px;overflow:visible}
.bar.expired{background:#fee2e2}.bar.soon{background:#fef3c7}
.bar .used{position:absolute;left:0;top:0;bottom:0;border-radius:5px;background:#86efac}
.bar.expired .used{background:#fca5a5}.bar.soon .used{background:#fcd34d}
.bar .today{position:absolute;top:-4px;bottom:-4px;width:2px;background:#1e293b}
.barlbl{display:flex;justify-content:space-between;font-size:.72rem;color:#64748b}
.entry{margin-bottom:26px}
.entry-head{font-size:1rem;font-weight:600;margin-bottom:4px}
.entry-kind{font-size:.8rem;color:#64748b;margin-bottom:6px}
.gloss dt{font-weight:600;margin-top:8px}.gloss dd{margin-left:0;color:#334155;font-size:.88rem}
"""

DARK_CSS = rh.dark("""
.explain,.problem,.certbox{background:#1e293b;color:#e2e8f0;border-color:#334155}
.flow .box{background:#1e3a5f;border-color:#3b82f6;color:#e2e8f0}
.chip{background:#334155;color:#e2e8f0}.chip.hit{background:#14532d;color:#bbf7d0}
.kv .k,.issued,.barlbl,.entry-kind{color:#94a3b8}
.gloss dd{color:#cbd5e1}
""") if hasattr(rh, "dark") else ""


def kind_of(check: dict) -> str:
    name = check["check"]
    for prefix, kind in (("expiry", "expiry"), ("validity", "validity"), ("key size", "keysize"), ("signature", "signature"),
                         ("chain order", "chain_order"), ("chain end", "chain_end"), ("first certificate", "first_ca"),
                         ("hostname", "hostname"), ("extended key usage", "eku"), ("private key", "privkey"),
                         ("truststore", "truststore")):
        if name.startswith(prefix):
            return kind
    return ""


def cn(dn: str) -> str:
    for part in dn.split(","):
        if part.strip().upper().startswith("CN="):
            return part.strip()[3:]
    return dn


def day(iso: str) -> str:
    return iso[:10]


def days_left(iso: str) -> int:
    end = datetime.strptime(iso, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    return int((end - datetime.now(timezone.utc)).total_seconds() // 86400)


def validity_bar(cert: dict) -> str:
    start = datetime.strptime(cert["not_before"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    end = datetime.strptime(cert["not_after"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    now = datetime.now(timezone.utc)
    total = max((end - start).total_seconds(), 1)
    pos = min(max((now - start).total_seconds() / total, 0), 1) * 100
    left = days_left(cert["not_after"])
    cls = "expired" if left < 0 else ("soon" if left < 30 else "")
    state = f"expired {-left} day(s) ago" if left < 0 else f"{left} day(s) left"
    return (f"<div class='bar {cls}'><div class='used' style='width:{pos:.1f}%'></div><div class='today' style='left:{pos:.1f}%' "
            f"title='today'></div></div><div class='barlbl'><span>valid from {e(day(cert['not_before']))}</span>"
            f"<span><b>{e(state)}</b></span><span>until {e(day(cert['not_after']))}</span></div>")


def host_matches(host: str, san: str) -> bool:
    host = host.lower()
    kind, _, value = san.partition(":")
    value = value.lower()
    if kind == "DNS":
        if value == host:
            return True
        return value.startswith("*.") and "." in host and host.split(".", 1)[1] == value[2:]
    return kind == "IP" and value == host


def usage_words(ku: str, eku: str) -> str:
    items = [u.strip() for u in (ku + "," + eku).split(",") if u.strip()]
    if not items:
        return "<span class='chip'>no restriction</span>"
    return "".join(f"<span class='chip' title='{e(u)}'>{e(USAGE_WORDS.get(u, u))}</span>" for u in items)


def cert_box(cert: dict, role: str, hostname: str, entry_checks: list) -> str:
    left = days_left(cert["not_after"])
    cls = "bad" if left < 0 else ("warnb" if left < 30 else "")
    badges = []
    if cert["self_signed"]:
        badges.append(rh.badge("self signed (a root CA)" if cert["ca"] else "self signed", "info"))
    elif cert["ca"]:
        badges.append(rh.badge("CA", "info"))
    sans = "".join(f"<span class='chip{' hit' if hostname and host_matches(hostname, s) else ''}'>{e(s)}</span>" for s in cert["sans"]) \
        or "<span class='chip'>none</span>"
    return (f"<div class='certbox {cls}'><h4>#{cert['index']} {e(cn(cert['subject']))} <small>{e(role)}</small> {' '.join(badges)}</h4>"
            f"{validity_bar(cert)}<div class='kv' style='margin-top:8px'>"
            f"<div class='k'>Subject</div><div class='mono'>{e(cert['subject'])}</div>"
            f"<div class='k'>Issued by</div><div class='mono'>{e(cert['issuer'])}</div>"
            f"<div class='k' title='the names this certificate is valid for'>Valid for (SAN)</div><div>{sans}</div>"
            f"<div class='k'>Can be used to</div><div>{usage_words(cert['key_usage'], cert['extended_key_usage'])}</div>"
            f"<div class='k'>Key</div><div>{e(cert['key'].replace('rsaEncryption', 'RSA'))} bits, signed with {e(cert['signature'])}</div>"
            f"<div class='k'>Serial</div><div class='mono'>{e(cert['serial'])}</div>"
            f"<div class='k'>SHA-256 fingerprint</div><div class='mono'>{e(cert['sha256'])}</div>"
            "</div></div>")


def role_of(index: int, total: int, cert: dict, kind: str) -> str:
    if kind == "trustedCertEntry":
        return "trusted CA certificate" if cert["ca"] else "trusted certificate"
    if index == 1:
        return "the certificate presented during the connection" if kind in ("PrivateKeyEntry", "server") else "first certificate"
    if cert["self_signed"]:
        return "root CA"
    return "intermediate CA"


def problem_card(check: dict, entry: str) -> str:
    kind = kind_of(check)
    ex = EXPLAIN.get(kind, {})
    status = check["status"]
    label = {"fail": "❌ Problem", "warn": "⚠️ Warning", "ok": "✅ OK", "info": "ℹ️ Note"}.get(status, status)
    rows = [f"<div class='row'><span class='lbl'>Found:</span>{e(check['value'])}</div>"]
    if status in ("fail", "warn") and ex:
        rows.append(f"<div class='row'><span class='lbl'>What it means:</span>{e(ex['what'])}</div>")
        rows.append(f"<div class='row'><span class='lbl'>Why it matters:</span>{e(ex['why'])}</div>")
        rows.append(f"<div class='row'><span class='lbl'>Error you would see:</span><span class='mono'>{e(ex['error'])}</span></div>")
    if check.get("fix"):
        rows.append(f"<div class='row'><span class='lbl'>How to fix:</span>{e(check['fix'])}</div>")
    if status == "fail" and kind in FIX_COMMANDS:
        rows.append(f"<pre>{e(FIX_COMMANDS[kind])}</pre>")
    return (f"<div class='problem {status}'><h3>{label} · {e(ex.get('title', check['check']))} "
            f"<small style='font-weight:400;color:#64748b'>({e(check['check'])} — {e(entry)})</small></h3>{''.join(rows)}</div>")


def intro(args, result) -> str:
    what = []
    if args.file:
        what.append(f"the file <b>{e(os.path.basename(args.file))}</b>")
    if args.server:
        what.append(f"the certificates sent by the server <b>{e(args.server)}</b>")
    checks = ["the dates of every certificate", "the order and the end of each chain"]
    if args.hostname:
        checks.append(f"that <b>{e(args.hostname)}</b> is one of the names of the certificate (hostname verification)")
    if args.truststore:
        checks.append(f"that the truststore <b>{e(os.path.basename(args.truststore))}</b> trusts the chain")
    if args.purpose:
        checks.append(f"that the certificate may be used by a TLS {e(args.purpose)}")
    return (f"<div class='explain'><h2>🧭 What this report checked</h2><p>It read {' and '.join(what) or 'the input'} and checked "
            + ", ".join(checks) + ". Problems come first, with what they mean, why they matter, the error a Kafka client "
            "would log and how to fix them; then every certificate, explained.</p></div>")


def tls_basics() -> str:
    return ("<details class='explain' open><summary><b>📘 TLS in two minutes (read this first if certificates are new to you)</b></summary>"
            "<p>When a Kafka client connects to a broker over TLS (SSL), the broker <b>presents its certificate</b> to prove who it is. "
            "The client then checks three things:</p>"
            "<ul><li><b>Is it signed by someone I trust?</b> The certificate is issued (signed) by a <b>certificate authority (CA)</b>. "
            "The client accepts it only if that CA, or a CA above it in the chain, is in its <b>truststore</b>.</li>"
            "<li><b>Is it for the server I wanted?</b> The hostname of the connection must be one of the <b>Subject Alternative Names (SAN)</b> "
            "of the certificate.</li>"
            "<li><b>Is it still valid?</b> Today must be between its start and end dates.</li></ul>"
            "<div class='flow'><span class='box'>🖥️ broker certificate<br><small>CN=broker, SAN=broker</small></span><span class='arrow'>issued by →</span>"
            "<span class='box'>🏢 intermediate CA</span><span class='arrow'>issued by →</span><span class='box'>🏛️ root CA<br><small>self signed</small></span>"
            "<span class='arrow'>found in →</span><span class='box'>📒 client truststore</span></div>"
            "<p>The broker keeps its private key and its certificate chain in a <b>keystore</b> (<code>ssl.keystore.location</code>); "
            "the client keeps the CAs it trusts in a <b>truststore</b> (<code>ssl.truststore.location</code>). With mutual TLS (mTLS, "
            "<code>ssl.client.auth=required</code>) it also works the other way: the client presents its own certificate from its keystore, "
            "and the broker checks it with its truststore.</p></details>")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--json-file")
    parser.add_argument("--out", required=True)
    parser.add_argument("--file", default="")
    parser.add_argument("--server", default="")
    parser.add_argument("--hostname", default="")
    parser.add_argument("--truststore", default="")
    parser.add_argument("--purpose", default="")
    args = parser.parse_args()
    result = json.load(open(args.json_file) if args.json_file else sys.stdin)

    entries = result.get("entries", [])
    all_certs = [c for en in entries for c in en["certificates"]]
    soonest = min((days_left(c["not_after"]) for c in all_certs), default=None)
    fails = [(en["entry"], c) for en in entries for c in en["checks"] if c["status"] == "fail"]
    warns = [(en["entry"], c) for en in entries for c in en["checks"] if c["status"] == "warn"]
    oks = [(en["entry"], c) for en in entries for c in en["checks"] if c["status"] in ("ok", "info")]
    errors = result.get("errors", [])

    if errors or fails:
        names = [EXPLAIN.get(kind_of(c), {}).get("title", c["check"]).lower() for _, c in fails]
        verdict = rh.verdict_html("danger", f"❌ {len(fails) + len(errors)} problem(s) would break TLS connections: "
                                  + ", ".join(dict.fromkeys(names + errors)) + ". See 'What to fix' below.")
    elif warns:
        verdict = rh.verdict_html("warn", f"⚠️ No blocking problem, {len(warns)} warning(s) to look at before it bites.")
    else:
        verdict = rh.verdict_html("ok", "✅ No problem found: these certificates pass every check below.")

    tiles = rh.kpis_html([
        rh.kpi("Certificates", len(all_certs), f"in {len(entries)} entr{'y' if len(entries) == 1 else 'ies'}"),
        rh.kpi("Problems", len(fails) + len(errors), "break the connection", "danger" if fails or errors else "ok"),
        rh.kpi("Warnings", len(warns), "to look at", "warn" if warns else "ok"),
        rh.kpi("Expires first", "-" if soonest is None else (f"{soonest} d" if soonest >= 0 else "expired"),
               "days left of the soonest certificate", "danger" if soonest is not None and soonest < 0 else
               ("warn" if soonest is not None and soonest < 30 else "ok")),
    ])

    body = [verdict, tiles, intro(args, result), tls_basics()]
    if errors:
        body.append(rh.card("❌ Could not read", "".join(f"<p>{e(m)}</p>" for m in errors)
                            + "<p>Check the path, the format and the password (<code>--password</code>, <code>--truststore-password</code>).</p>"))
    if fails or warns:
        body.append("<div class='section-title'>🛠️ What to fix (most important first)</div>")
        body.extend(problem_card(c, entry) for entry, c in fails + warns)
    if oks:
        body.append("<details class='explain'><summary><b>✅ Checks that passed</b> (" + str(len(oks)) + ")</summary>"
                    + "".join(problem_card(c, entry) for entry, c in oks) + "</details>")

    body.append("<div class='section-title'>🔗 The certificates, one chain per entry</div>")
    for en in entries:
        certs = en["certificates"]
        parts = []
        for i, cert in enumerate(certs):
            if i:
                parts.append("<div class='issued'>⬇ which was issued by:</div>")
            parts.append(cert_box(cert, role_of(cert["index"], len(certs), cert, en["kind"]), args.hostname, en["checks"]))
        tls = en.get("tls")
        body.append(f"<div class='entry'><div class='entry-head'>🔐 {e(en['entry'])}</div>"
                    f"<div class='entry-kind'>{e(KIND_WORDS.get(en['kind'], en['kind']))}"
                    + (f" · negotiated {e(tls['protocol'])}, cipher {e(tls['cipher'])}" if tls and tls.get("protocol") else "")
                    + f"</div><div class='chain'>{''.join(parts)}</div></div>")

    if result.get("info"):
        body.append(rh.card("ℹ️ Notes", "".join(f"<p>{e(m)}</p>" for m in result["info"])))
    body.append("<div class='explain gloss'><h2>📖 Glossary</h2><dl>"
                + "".join(f"<dt>{e(t)}</dt><dd>{e(d)}</dd>" for t, d in GLOSSARY) + "</dl>"
                "<p style='margin-top:10px'>To look by yourself: <code>keytool -list -v -keystore &lt;file&gt;</code> (keystore, truststore), "
                "<code>openssl x509 -in cert.pem -noout -text</code> (PEM certificate), "
                "<code>openssl s_client -connect host:port -showcerts</code> (what a server sends). To change the format of a keystore "
                "(JKS, PKCS12, PEM files for python / go / .net clients, Kafka properties with the certificates inline): "
                "<code>playground tools cert convert --file &lt;file&gt; --to pkcs12|jks|pem|properties</code>.</p></div>")

    meta = []
    if args.file:
        meta.append(f"📄 {e(os.path.basename(args.file))}")
    if args.server:
        meta.append(f"🖥️ {e(args.server)}")
    if args.hostname:
        meta.append(f"🏷️ hostname {e(args.hostname)}")
    if args.truststore:
        meta.append(f"📒 truststore {e(os.path.basename(args.truststore))}")
    html = rh.page("Certificate inspection", "🔐 Certificate inspection", meta, "".join(body), "playground tools cert inspect")
    html = html.replace("</head>", f"<style>{CSS}{DARK_CSS}</style></head>", 1)
    with open(args.out, "w") as f:
        f.write(html)


if __name__ == "__main__":
    main()
