# 📊 Reports

The playground does not only start environments: it also tells you **what is wrong** with them. The `playground analyze`
commands, the connector benchmark and the SMT tester print a short digest in the terminal (made to be read by you or by
[Claude Code](/claude-code.md)) and write a **self-contained HTML report** you can share with a colleague or a customer.

The reports below are real ones, generated from the samples shipped in the repository. Click a screenshot to open the
report and click around: this is what you get on your own data.

> [!TIP]
> Every `playground analyze` command accepts `--sample <name>` to run it on those samples, so you can see what it
> reports before running it on real data. `playground analyze <command> --help` lists the samples.

<div class="report-gallery">
  <div class="report-card">
    <a href="reports/thread-dump.html" target="_blank" rel="noopener"><img src="images/reports/thread-dump.png" alt="🧵 Thread dumps report" loading="lazy"></a>
    <div class="report-body">
      <h3><a href="#/playground%20analyze%20thread-dump">🧵 Thread dumps</a></h3>
      <p>Why is the connector stuck, hanging or burning CPU? Three dumps of one JVM, 5 s apart: deadlocks, blocked threads, contended locks, CPU-hot threads, stuck tasks, leaking pools.</p>
      <p><code>playground analyze thread-dump -c connect</code></p>
      <p>Try it: <code>playground analyze thread-dump --sample deadlock_jdk21</code></p>
    </div>
  </div>
  <div class="report-card">
    <a href="reports/gc-logs.html" target="_blank" rel="noopener"><img src="images/reports/gc-logs.png" alt="♻️ GC logs report" loading="lazy"></a>
    <div class="report-body">
      <h3><a href="#/playground%20analyze%20gc-logs">♻️ GC logs</a></h3>
      <p>Long GC pauses, memory leak, heap too small? Pause timeline, heap before / after GC, pause distribution, health score and recommendations, for every collector from JDK 7 to 21.</p>
      <p><code>playground analyze gc-logs -c connect</code></p>
      <p>Try it: <code>playground analyze gc-logs --sample jdk21_g1_kafka_real</code></p>
    </div>
  </div>
  <div class="report-card">
    <a href="reports/flight-recorder.html" target="_blank" rel="noopener"><img src="images/reports/flight-recorder.png" alt="🛩️ Flight recorder report" loading="lazy"></a>
    <div class="report-body">
      <h3><a href="#/playground%20analyze%20flight-recorder">🛩️ Flight recorder</a></h3>
      <p>Where does the time of the connector tasks go? Records the worker with Java Flight Recorder over JMX and splits the task time between I/O, Kafka, locks, converters and the hot methods.</p>
      <p><code>playground analyze flight-recorder -c connect --duration 60s</code></p>
      <p>Try it: <code>playground analyze flight-recorder --sample jdbc_postgres_sink</code></p>
    </div>
  </div>
  <div class="report-card">
    <a href="reports/benchmark.html" target="_blank" rel="noopener"><img src="images/reports/benchmark.png" alt="🏎️ Connector benchmark report" loading="lazy"></a>
    <div class="report-body">
      <h3><a href="#/reusables?id=%e2%8f%b1%ef%b8%8f-benchmark-a-connector">🏎️ Connector benchmark</a></h3>
      <p>How fast is this connector, and is version Y slower? Drains a backlog with each connector version, compares the throughput, CPU and batch times, and says where the task time went.</p>
      <p><code>playground connector benchmark --connector-tag 10.8.4 --connector-tag 10.9.9</code></p>
    </div>
  </div>
  <div class="report-card">
    <a href="reports/smt-test.html" target="_blank" rel="noopener"><img src="images/reports/smt-test.png" alt="🔀 SMT test report" loading="lazy"></a>
    <div class="report-body">
      <h3><a href="#/playground%20connector%20smt%20test">🔀 SMT test</a></h3>
      <p>What does this transform chain do to a record, and why does it fail? Runs the record through each transform, step by step, and compares Confluent Platform versions.</p>
      <p><code>playground connector smt test --connector filestream-sink --cp-version 7.9.0 --cp-version 8.3.2</code></p>
    </div>
  </div>
  <div class="report-card">
    <a href="reports/oracle-xstream-report.html" target="_blank" rel="noopener"><img src="images/reports/oracle-xstream-report.png" alt="🅾️ Oracle XStream diagnostics report" loading="lazy"></a>
    <div class="report-body">
      <h3><a href="#/playground%20analyze%20oracle-xstream-report">🅾️ Oracle XStream diagnostics</a></h3>
      <p>What does this <code>orclcdc_diag</code> report say? Prerequisites, capture, LogMiner, outbound server, streams pool, open transactions: findings with the exact values and the SQL to fix them.</p>
      <p><code>playground analyze oracle-xstream-report -f orclcdc_diag_&lt;date&gt;.html</code></p>
      <p>Try it: <code>playground analyze oracle-xstream-report --sample synthetic_failures</code></p>
    </div>
  </div>
  <div class="report-card">
    <a href="reports/cfk-bundle.html" target="_blank" rel="noopener"><img src="images/reports/cfk-bundle.png" alt="📦 CFK support bundle report" loading="lazy"></a>
    <div class="report-body">
      <h3><a href="#/playground%20analyze%20cfk-bundle">📦 CFK support bundle</a></h3>
      <p>What is wrong in this Confluent for Kubernetes bundle? Crash-looping pods, expired certificates, pending volumes, OOMKilled containers, failed connector tasks, operator errors, with next steps.</p>
      <p><code>playground analyze cfk-bundle --bundle support-bundle.tar.gz</code></p>
      <p>Try it: <code>playground analyze cfk-bundle --sample synthetic</code></p>
    </div>
  </div>
  <div class="report-card">
    <a href="reports/tcp-dump.html" target="_blank" rel="noopener"><img src="images/reports/tcp-dump.png" alt="🦈 Network capture report" loading="lazy"></a>
    <div class="report-body">
      <h3><a href="#/playground%20analyze%20tcp-dump">🦈 Network capture</a></h3>
      <p>What goes over the wire? Refused, unanswered and reset connections, retransmissions, TLS alerts with their likely cause, DNS errors, Kafka and HTTP errors with response times, and the bodies of the HTTP error responses.</p>
      <p><code>playground debug tcp-dump -c connect --port 9092 --duration 30s</code></p>
      <p>Try it: <code>playground analyze tcp-dump --sample kafka_and_network_errors</code> (or <code>--sample http_errors</code>)</p>
    </div>
  </div>
</div>

## 🔁 Regenerate this page

The reports and screenshots are generated by
[`scripts/generate-reports-gallery.sh`](https://github.com/vdesabou/kafka-docker-playground-docs/blob/main/scripts/generate-reports-gallery.sh)
from a clone of kafka-docker-playground. The benchmark and SMT test reports need a real run and are passed by hand:

```bash
BENCHMARK_REPORT=/tmp/playground-benchmark/<run>.html \
SMT_REPORT=/tmp/playground-smt-test/<run>.html \
scripts/generate-reports-gallery.sh ../kafka-docker-playground
```
