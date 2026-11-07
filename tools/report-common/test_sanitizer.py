"""
Regression tests of sanitizer.py (and of the speed of the known causes on long lines), plain asserts, no dependency:

    python3 -I tools/report-common/test_sanitizer.py

- LEAKS: a secret (the second value) must not be in the output of the line (the first one)
- KEPT: the text must come out unchanged (no over-redaction that would hide the evidence)
- speed: adversarial lines of 50,000 characters must be sanitized / matched in well under a second each
"""
import os
import sys
import time

# no __pycache__ next to the tools of the repository
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import known_causes  # noqa: E402
from sanitizer import DataSanitizer, sanitize_stream  # noqa: E402

LEAKS = [
    ('sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="u" password="s3cr3tP4ss";', "s3cr3tP4ss"),
    ("basic.auth.user.info=ABCDEFGHIJKLMNOP:veryS3cretValue123", "veryS3cretValue123"),
    ("aws.secret.access.key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", "wJalrXUtnFEMI"),
    ("key AKIAIOSFODNN7EXAMPLE used", "AKIAIOSFODNN7EXAMPLE"),
    ("DefaultEndpointsProtocol=https;AccountName=acct;AccountKey=Zm9vYmFyYmF6cXV4Zm9vYmFyYmF6cXV4==;EndpointSuffix=core.windows.net", "Zm9vYmFyYmF6cXV4"),
    ("GET https://acct.blob.core.windows.net/c/blob?sv=2022-11-02&ss=b&srt=co&sp=r&sig=AbCdEfGh%2BIjKl%3D 403", "AbCdEfGh"),
    ("connection.url=jdbc:oracle:thin:scott/tiger@//oracle.acme.corp:1521/ORCLPDB1", "tiger"),
    ("jdbc:oracle:thin:scott/tiger@oracle.acme.corp:1521:ORCL", "tiger"),
    ("connection.uri=mongodb://user:p@ss@mongo.acme.corp:27017/db", "p@ss"),
    ("connection.url=jdbc:postgresql://db.acme.corp:5432/db?user=app&password=Pg5ecret", "Pg5ecret"),
    ("Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U", "eyJzdWIiOiIxMjM0NTY3ODkwIn0"),
    ("ssl.keystore.password = changeit123", "changeit123"),
    ("java.net.UnknownHostException: db.acme.corp: Name or service not known", "db.acme.corp"),
    ("connecting to [2001:db8::1]:9092 and fe80::1ff:fe23:4567:890a%eth0", "2001:db8::1"),
    ("connecting to [2001:db8::1]:9092 and fe80::1ff:fe23:4567:890a%eth0", "fe80::1ff"),
    ("broker at 10.42.0.12:9092", "10.42.0.12"),
    ("connection.password=abc,def;ghi", "def;ghi"),
    ("<settings><password>XmlS3cret</password></settings>", "XmlS3cret"),
    ("connection.password\tTsvS3cret", "TsvS3cret"),
    ("salesforce.consumer.key=3MVG9SalesforceKey", "3MVG9SalesforceKey"),
    ("salesforce.consumer.secret=SfSecret123", "SfSecret123"),
    ("> Cookie: JSESSIONID=abc123def456; session=xyz", "abc123def456"),
    ("curl -s -u alice:alicepass http://connect:8083/connectors", "alicepass"),
    ("token xoxb-123456789012-abcdefghijkl leaked", "xoxb-123456789012"),
    ("key sk_live_51HabcdefghijKLMNOPQR", "sk_live_51Habc"),
    ("GITHUB_TOKEN=ghp_abcdefghijklmnopqrstuvwxyz0123456789", "ghp_abcdefghijklmnop"),
]

KEPT = [
    "2026-11-06 10:00:00,123 ERROR [my-sink|task-0] WorkerSinkTask{id=my-sink-0} Task threw an uncaught exception",
    "org.apache.kafka.connect.errors.ConnectException: kafka.server.KafkaServer failed",
    "retry.backoff.ms = 100",
    "Kafka version: 7.6.1-ce, kafka-clients-3.6.1.1.jar",
    "jdk 11.0.20.1 and CP 7.6.0.1",
    "credentials.provider=BASIC",
    "password=[hidden]",
    "std::string and rdkafka::error::KafkaError and Vec::new",
    "at 10:00:00 the task restarted",
    "assignment.strategy = signature design",
    "<configuration><name>tasks.max</name><value>1</value></configuration>",
    "connection.password\tPASSWORD\tHIGH",
]


def check(name, ok, detail=""):
    if not ok:
        raise AssertionError(f"{name}: {detail}")


def test_leaks():
    for text, secret in LEAKS:
        out = DataSanitizer().sanitize_text(text)
        check("leak", secret not in out, f"{secret!r} kept in {out!r}")


def test_kept():
    for text in KEPT:
        out = DataSanitizer().sanitize_text(text)
        check("kept", out == text, f"{text!r} became {out!r}")


def test_value_stops_at_the_next_key():
    for text, want in [("password=x1, retries=3 then", "password=<REDACTED>, retries=3 then"),
                       ("ssl.key.password=k1,ssl.truststore.location=/etc/ts.jks", "ssl.key.password=<REDACTED>,ssl.truststore.location=/etc/ts.jks"),
                       ("connection.password=abc,def;ghi end", "connection.password=<REDACTED> end")]:
        out = DataSanitizer().sanitize_text(text)
        check("value end", out == want, f"{text!r} became {out!r}")


def test_same_placeholder_any_case_and_after_colon():
    s = DataSanitizer()
    first = s.sanitize_text("connecting to db.acme.corp:5432")
    second = s.sanitize_text("DB.ACME.CORP: timeout, db.acme.corp. Retrying")
    placeholder = first.split()[-1].split(":")[0]
    check("placeholder", placeholder.startswith("<HOST-"), first)
    check("placeholder", second.count(placeholder) == 2 and "acme" not in second.lower(), second)


def test_pem_in_context_lines():
    records = "\n".join([
        "@@PGREC@@\tERROR\tconnect.log\t1",
        "@@PGCTX@@\t    10 ▶ ssl.key=-----BEGIN PRIVATE KEY-----",
        "@@PGCTX@@\t    11   MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7",
        # the last line of a key body is short: the 40+ characters base64 rule does not catch it on its own
        "@@PGCTX@@\t    12   xQ5mA9kLr2Tw==",
        "@@PGCTX@@\t    13   -----END PRIVATE KEY----- loaded",
        "@@PGCTX@@\t    14   next line",
    ])
    out = sanitize_stream(DataSanitizer(), records)
    check("pem", "MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7" not in out and "xQ5mA9kLr2Tw" not in out, out)
    lines = out.split("\n")
    check("pem", len(lines) == 6 and all(l.startswith("@@PG") for l in lines), out)
    check("pem", "    11 " in lines[2] and "    12 " in lines[3] and "loaded" in lines[4] and "next line" in lines[5], out)


ADVERSARIAL = ["x " + "a" * 50000, "x " + "1" * 50000, "x " + "a." * 25000, "x " + "Zm9v" * 12500,
               "x " + "1" * 50000 + " brokers are down", "x " + "ab " * 16000]


def test_sanitizer_speed():
    # a quadratic regex takes seconds to minutes on these, a linear one milliseconds
    for line in ADVERSARIAL:
        start = time.time()
        DataSanitizer().sanitize_text(line)
        took = time.time() - start
        check("sanitizer speed", took < 1, f"{took:.1f} s on {line[:12]!r}… ({len(line)} chars)")


def test_known_causes_speed():
    import re
    patterns = [h[0] for h in known_causes.hints()] + [c["pattern"] for c in known_causes.error_patterns().values()]
    for pattern in patterns:
        regex = re.compile(pattern if pattern.startswith("(?i)") else "(?i)" + pattern)
        for line in ADVERSARIAL:
            start = time.time()
            regex.search(line)
            took = time.time() - start
            check("known cause speed", took < 0.5, f"{took:.1f} s for {pattern[:60]!r} on {line[:12]!r}…")


def test_known_causes_internal_links():
    """The private runbooks file: links by known cause title, https only, nothing without the file"""
    import json
    import tempfile
    saved = os.environ.get("PLAYGROUND_LOG_RUNBOOKS_FILE")
    try:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"links": {"🔐 TLS handshake failure": [{"title": "PKIX runbook", "url": "https://example.com/pkix"},
                                                             {"title": "bad", "url": "javascript:alert(1)"}]}}, f)
        os.environ["PLAYGROUND_LOG_RUNBOOKS_FILE"] = f.name
        known_causes._internal = None
        check("internal links", known_causes.internal_links("🔐 TLS handshake failure")
              == [{"title": "PKIX runbook", "url": "https://example.com/pkix"}], "the https link only")
        check("internal links", known_causes.internal_links("🔑 Authentication failure") == [], "none for another cause")
        os.environ["PLAYGROUND_LOG_RUNBOOKS_FILE"] = f.name + ".missing"
        known_causes._internal = None
        check("internal links", known_causes.internal_links("🔐 TLS handshake failure") == [], "none without the file")
        os.unlink(f.name)
    finally:
        known_causes._internal = None
        if saved is None:
            os.environ.pop("PLAYGROUND_LOG_RUNBOOKS_FILE", None)
        else:
            os.environ["PLAYGROUND_LOG_RUNBOOKS_FILE"] = saved


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"✅ {t.__name__}")
        except AssertionError as ex:
            failed += 1
            print(f"❌ {t.__name__}: {ex}")
    sys.exit(1 if failed else 0)
