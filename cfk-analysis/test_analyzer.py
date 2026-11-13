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

import environment  # noqa: E402
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


KUBECTL_ALL = """\
NAME                                     READY   STATUS             RESTARTS      AGE   IP          NODE
pod/confluent-operator-5c94578d76-fjlb5  1/1     Running            1 (10d ago)   10d   10.0.0.11   node-1
pod/connect-0                            0/1     CrashLoopBackOff   4 (2m ago)    13d   10.0.0.12   node-2
pod/kafka-0                              1/1     Running            0             10d   10.0.0.13   node-3

NAME                          TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                               AGE
service/connect               ClusterIP   None         <none>        8083/TCP,7203/TCP,7777/TCP,7778/TCP   507d
service/kafka-0-internal      ClusterIP   10.0.1.63    <none>        9074/TCP,9092/TCP,8090/TCP,7778/TCP   507d
service/kafka-bootstrap-np    NodePort    10.0.1.126   <none>        9092:32524/TCP                        515d

NAME                                 READY   UP-TO-DATE   AVAILABLE   AGE    CONTAINERS           IMAGES
deployment.apps/confluent-operator   1/1     1            1           507d   confluent-operator   confluentinc/confluent-operator:0.1514.76

NAME                               DESIRED   CURRENT   READY   AGE    CONTAINERS   IMAGES
replicaset.apps/grafana-cb8d5598   1         1         1       515d   grafana      grafana/grafana:latest

NAME                               READY   AGE    CONTAINERS   IMAGES
statefulset.apps/kafka             3/3     172d   kafka        confluentinc/cp-server:7.7.1
"""


def test_kubectl_get_all_sections():
    """`kubectl get all`: the service / deployment / replicaset / statefulset sections have their own header, read
    with the columns of the pod header they gave "Container service/kafka-0-internal Clus restarted 63 times"."""
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "kubectl-all-confluent.txt"), "w") as fh:
            fh.write(KUBECTL_ALL)
        results = analyze(d)
        table = [i for i in results["issues"] if i["message"].startswith("Container ") and "kubectl get pods" in i["message"]]
        messages = [i["message"] for i in table]
        check("kubectl get all: no finding on a service / deployment / replicaset / statefulset row",
              not any(k in m for m in messages for k in ("service/", ".apps/", "NAME ")), messages)
        check("kubectl get all: the CrashLoopBackOff pod, without its pod/ prefix",
              any(m.startswith("Container connect-0 status CrashLoopBackOff") for m in messages), messages)
        check("kubectl get all: 3 restarts or more of a pod", any(m.startswith("Container connect-0 restarted 4 times")
                                                                for m in messages), messages)
        check("kubectl get all: only the pods counted", results["coverage"]["pods"] == 3, results["coverage"]["pods"])


def test_cp_version_only_from_confluent_cp_images():
    """a custom image tag (confluent-xstream-container:4.0.1, my-connect:1.0.3) is not a Confluent Platform version"""
    check("cp_version: cp-server", environment.cp_version("registry.example.com:8083/confluentinc/cp-server:7.7.1") == "7.7.1")
    check("cp_version: cp-server-connect ubi tag",
          environment.cp_version("confluentinc/cp-server-connect:8.3.2-1-ubi9.amd64") == "8.3.2")
    check("cp_version: Control Center next gen",
          environment.cp_version("confluentinc/cp-enterprise-control-center-next-gen:2.4.0") == "2.4.0")
    for image in ("registry.example.com:8083/confluentinc/confluent-xstream-container:4.0.1",
                  "registry.example.com/team/my-connect:1.0.3", "confluentinc/confluent-init-container:3.2.3",
                  "confluentinc/confluent-operator:0.1514.76", "registry.example.com/cp-connect-custom:1.2.0"):
        check(f"cp_version: none for {image}", environment.cp_version(image) is None, environment.cp_version(image))
    env = {"cfk_version": "3.2.3", "components": {
        "connect": {"image": "registry.example.com:8083/confluentinc/confluent-xstream-container:4.0.1",
                    "init_image": "registry.example.com:8083/confluentinc/confluent-init-container:3.2.3"},
        "kafka": {"image": "registry.example.com:8083/confluentinc/cp-server:7.7.1",
                  "init_image": "registry.example.com:8083/confluentinc/confluent-init-container:3.2.3"},
        "schemaregistry": {"image": "confluentinc/cp-schema-registry:7.3.0",
                           "init_image": "registry.example.com/team/custom-init:1.0.0"}}}
    findings = environment.compatibility_findings(env)
    messages = [f["message"] for f in findings]
    check("compatibility: no CP version finding for a custom image", not any("4.0.1" in m for m in messages), messages)
    check("compatibility: a cp- image outside the range is still high",
          any(f["severity"] == "high" and f.get("instance") == "schemaregistry" for f in findings), messages)
    check("compatibility: a custom init image is not compared with the operator",
          not any("confluent-init-container" in m for m in messages), messages)
    check("compatibility: different CP versions of the cp- images only",
          any("7.3.0 (schemaregistry), 7.7.1 (kafka)" in m for m in messages), messages)


def main():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    if FAILED:
        print(f"{len(FAILED)} check(s) failed: {', '.join(FAILED)}")
        return 1
    return 0



def test_private_kb_links():
    """the knowledge-base articles of the known CFK issues are private ("kb" of the private runbooks file): shown as
    public links of the entry (a customer can read them), not as internal 🔒 ones; none in the public catalog"""
    import json
    import runbooks
    check("no knowledge-base article in the public catalog",
          not any("support.confluent.io" in l["url"] for e in runbooks.RUNBOOKS for l in e.get("links") or []))
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "runbooks-internal.json")
        with open(path, "w") as fh:
            json.dump({"kb": {"jaas_context": [{"title": "synthetic article", "url": "https://kb.example/jaas"}]},
                       "links": {"jaas_context": [{"title": "synthetic runbook", "url": "https://wiki.example/jaas"}]}}, fh)
        entry = runbooks.Catalog(path).by_name["jaas_context"]
    check("kb: a public link of the entry", [l["url"] for l in entry["links"]] == ["https://kb.example/jaas"], entry["links"])
    check("links: internal", [l["url"] for l in entry["internal_links"]] == ["https://wiki.example/jaas"], entry["internal_links"])

if __name__ == "__main__":
    sys.exit(main())
