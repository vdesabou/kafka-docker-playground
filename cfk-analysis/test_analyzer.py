#!/usr/bin/env python3
"""
Regression tests of the CFK analyzer on small bundles written in a temporary folder, plain asserts (PyYAML only, the
dependency of the analyzer):

    python3 -I cfk-analysis/test_analyzer.py
"""

import os
import sys
import tempfile
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import problem as problem_statement  # noqa: E402
from analyzer import CFKBundleAnalyzer  # noqa: E402

FAILED = []


def check(name, ok, detail=""):
    print(("✅ " if ok else "❌ ") + name + ("" if ok else f": {detail}"))
    if not ok:
        FAILED.append(name)


NS = "confluent"
RB = "app-consumer-subjects-rb"
SCOPE_ERROR = ("kafka rest API request failed: Invalid scope resource type binding with cluster type : kafka-cluster "
               "and resource type : Subject (0)")


def operator_line(second, level, logger, msg, name, error):
    minutes, seconds = divmod(second, 60)
    return ('{"level":"%s","time":"2026-11-09T13:%02d:%02d.000Z","name":"%s","caller":"log/log.go:53","msg":"%s",'
            '"name":"%s","namespace":"%s","error":"%s"}' % (level, 50 + minutes, seconds, logger, msg, name, NS, error))


def flat_bundle(folder):
    """a flat collection of kubectl outputs (no pod manifest): the operator retries the delete of a ConfluentRolebinding
    twice a second for 2 minutes (a loop), a Schema every 30 s (a normal requeue, not a loop), and pods.txt shows the
    operator pod restarted 6 times and a crash-looping connect-0"""
    lines = []
    for i in range(240):
        second = i // 2
        lines.append(operator_line(second, "ERROR", "confluentrolebinding", f"confluentrolebinding {RB} delete failed", RB, SCOPE_ERROR))
        lines.append(operator_line(second, "ERROR", "confluentrolebinding", "failed to delete ConfluentRolebinding", RB, SCOPE_ERROR))
    for second in range(0, 120, 30):
        lines.append(operator_line(second, "ERROR", "schema", "apply failed", "orders-value", "schema registry rest API request failed: 409"))
    lines.sort(key=lambda line: line.split('"time":"')[1][:24])
    with open(os.path.join(folder, "confluent-operator-5c94578d76-fjlb5.log"), "w") as fh:
        fh.write("\n".join(lines) + "\n")
    with open(os.path.join(folder, "pods.txt"), "w") as fh:
        fh.write("NAME                                  READY   STATUS             RESTARTS        AGE\n"
                 "confluent-operator-5c94578d76-fjlb5   1/1     Running            6 (16m ago)     3h58m\n"
                 "connect-0                             0/1     CrashLoopBackOff   12 (2m ago)     1h\n"
                 "kafka-0                               1/1     Running            0               10d\n")
    with open(os.path.join(folder, "deployment.yaml"), "w") as fh:
        fh.write("apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: confluent-operator\nspec:\n  template:\n"
                 "    spec:\n      containers:\n      - name: confluent-operator\n"
                 "        image: confluentinc/confluent-operator:0.1718.99\n"
                 "        resources:\n          limits: {cpu: 500m, memory: 512Mi}\n          requests: {memory: 256Mi}\n")
    with open(os.path.join(folder, f"confluentrolebinding_platform_confluent_io-{RB}.yaml"), "w") as fh:
        fh.write(f"apiVersion: platform.confluent.io/v1beta1\nkind: ConfluentRolebinding\nmetadata:\n  name: {RB}\n"
                 f"  namespace: {NS}\n  deletionTimestamp: '2026-10-28T13:38:45Z'\n  finalizers:\n"
                 "  - confluentrolebinding.finalizers.platform.confluent.io\nspec:\n  role: DeveloperRead\n"
                 "status:\n  state: ERROR\n  conditions:\n  - type: platform.confluent.io/app-ready\n    status: 'False'\n"
                 f"    reason: DeleteFailed\n    message: '{SCOPE_ERROR}'\n")


def analyze(folder):
    with redirect_stdout(sys.stderr):
        return CFKBundleAnalyzer(folder).analyze()


def test_reconcile_loop_and_pods_table():
    with tempfile.TemporaryDirectory() as d:
        flat_bundle(d)
        results = analyze(d)
        issues = results["issues"]
        loops = [i for i in issues if i["category"] == "Reconcile Loop"]
        check("one reconcile loop (the Schema requeued every 30 s is not one)", len(loops) == 1, [i["message"] for i in loops])
        if loops:
            loop = loops[0]
            check("loop: failures counted once per pair of lines", loop.get("count") == 240, loop.get("count"))
            check("loop: critical (the operator restarted)", loop["severity"] == "critical", loop["severity"])
            check("loop: full error from the condition of the CR", SCOPE_ERROR in loop["message"], loop["message"])
            check("loop: rate, restarts and memory limit",
                  "per minute" in loop["message"] and "6 restart(s)" in loop["message"] and "512Mi" in loop["message"],
                  loop["message"])
            check("loop: operator component", loop.get("component") == "operator", loop.get("component"))
            check("loop: runbook", "rolebinding_retry_loop" in (loop.get("runbooks") or []), loop.get("runbooks"))
        restarted = [i for i in issues if i["message"].startswith("Container confluent-operator-5c94578d76-fjlb5 restarted 6 times")]
        check("pods.txt: operator restarts", len(restarted) == 1 and "last 16m ago" in restarted[0]["message"],
              [i["message"] for i in issues if "pods.txt" in i["file"]])
        crash = [i for i in issues if i["message"].startswith("Container connect-0 status CrashLoopBackOff")]
        check("pods.txt: CrashLoopBackOff", len(crash) == 1, [i["message"] for i in issues if "pods.txt" in i["file"]])
        many = [i for i in issues if i["message"].startswith("Container connect-0 restarted 12 times")]
        check("pods.txt: 10 restarts or more are high", len(many) == 1 and many[0]["severity"] == "high",
              [(i["severity"], i["message"]) for i in many])
        check("pods.txt: a healthy pod gives nothing", not any("kafka-0" in i["message"] for i in issues if "pods.txt" in i["file"]))
        check("pods.txt: pods counted", results["coverage"]["pods"] == 3, results["coverage"]["pods"])
        parsed = problem_statement.parse("CFK operator pod OOMKilled and restarting", results)
        verdict = problem_statement.correlate(results, parsed)
        check("--problem: explained by the loop", "Reconcile Loop" in verdict.get("verdict_text", ""), verdict.get("verdict_text"))


def main():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    if FAILED:
        print(f"{len(FAILED)} check(s) failed: {', '.join(FAILED)}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
