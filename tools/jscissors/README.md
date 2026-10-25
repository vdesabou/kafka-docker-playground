# jscissors

Java agent and analyzer behind `playground debug jscissors` and `playground analyze jscissors`. It answers the question a
thread dump or a flight recording cannot: **what did this method receive, what did it return or throw, and how long
did each call take?** On a running JVM, without restart and without debugger.

## How it works

| File | Role |
| --- | --- |
| `agent/` | The java agent (maven project, [byte-buddy](https://bytebuddy.net) relocated in `jscissors.shaded`, compiled for JDK 8, runs up to the JDK 25 of the cp 8.x images). Built on the first use by `jscissors_agent_jar` (`scripts/cli/src/lib/cli_function.sh`) in a `maven:3.9.11-eclipse-temurin-17` container, cached in `/tmp/playground-jscissors/jscissors-<checksum of the sources>.jar`: no jar in the repository. |
| `jscissors_report.py` | Turns a trace into the analysis: text digest, `--json`, self-contained HTML report (`tools/report-common/report_html.py`). Standard library only, runs with the host `python3`. |
| `samples/` | Traces of real runs, for `--sample`. |

The agent classes:

| Class | Role |
| --- | --- |
| `Agent` | `premain` (`-javaagent:`) and `agentmain` (attach). Arguments: `config=<rules file>,out=<folder>,action=start\|stop`. Attaching again with `action=start` replaces the session, `action=stop` ends it. |
| `Attach` | Main class of the jar, run in the container: loads the agent in the java process of the container with the HotSpot attach protocol (`.attach_pid<pid>` + `SIGQUIT`, then `load instrument` on `/tmp/.java_pid<pid>`, what `jcmd` does: the cp images have no `jcmd` and no `jdk.attach` module). Needs JDK 16+ in the container (unix domain sockets); otherwise `--jmx host:port` runs the `JVMTI.agent_load` diagnostic command over JMX. |
| `Config` | The rules file: `class{method}=OP+OP` per line (the syntax of jscissors 1.0), `jscissors.<setting>=<n>` for the limits. A plain name is exact, anything else a java regex. |
| `Session` | One `AgentBuilder` with `RETRANSFORMATION` (already loaded classes are rewritten, and restored by `reset` on stop), the advice of a method bound to the union of the operations of the rules matching it, the per-method statistics and `summary.json`. Skips the classes whose class loader cannot see the agent, and JDK classes. |
| `TraceAdvice`, `TraceAdviceNoArgs` | Inlined in the traced methods, `suppress = Throwable.class`: the agent never throws in the traced code. |
| `Tracer` | Per thread stack of the traced calls (parent, depth), the limits, the events. While it works for a thread (formatting an argument, a dump), the calls of that thread are not traced: no recursion. |
| `Values` | Bounded text of a value: strings, collections, maps and arrays cut, `byte[]` as text when printable (else the Confluent wire format schema id + hex), secrets masked. |
| `EventWriter` | `events.jsonl` written by a background thread from a bounded queue (the traced threads never wait for the disk, a full queue drops and counts), `summary.json` refreshed every 5 s. |
| `Dumps` | Thread dumps in the jstack format (`DiagnosticCommand threadPrint`, read by `playground analyze thread-dump`) and heap dumps, rate limited. |

## What a trace holds

`<out>/pid-<pid>/` (copied by `--action stop` to `--output-dir/jscissors-<container>-<date>/`):

| File | Content |
| --- | --- |
| `events.jsonl` | `{"ev":"enter","id":4,"parent":3,"depth":2,"ts":…,"us":…,"thread":…,"class":…,"method":…,"sig":"(java.lang.String,[B)","args":[…],"stack":[…]}`, `{"ev":"exit","id":4,"dur_us":297,"ret":…}` or `"exc"`, `"exc_msg"`, `"exc_stack"` (first exception of its class per method), `"exc_cause"`; `{"ev":"dump","kind":"threads","file":"dumps/…"}` |
| `summary.json` | rules, settings, classes instrumented, statistics of every method (exact: every call is counted, even past the limits), limits reached, errors, dumps |
| `agent.log` | what the agent did: rules, classes instrumented, warnings, errors |
| `instrumented.txt` | classes instrumented |
| `dumps/` | `threads-<n>-<ms>.txt`, `heap-<n>-<ms>.hprof` |

Filters (`jscissors.onlyFailed=1`, `jscissors.slowerThanMs=<n>`, or `--only-failed`, `--slower-than`): the enter event of
each call is built when it starts (the arguments as they are then) and kept on the call stack of the thread; it is
written with the exit only when the call throws or takes at least the threshold.

For timing questions on JDK 25+, `playground analyze flight-recorder --trace-method` (JFR method tracing) needs no
agent: jscissors is for the values and the older JDKs.

Limits (rules file `jscissors.<name>=<n>`, or the flags of `playground debug jscissors`): `maxCalls` 50000 (`--max-calls`),
`maxCallsPerMethod` 2000 (`--max-calls-per-method`), `maxValueLength` 300 (`--max-value-length`), `maxStackDepth` 40,
`maxThreadDumps` 10, `maxHeapDumps` 1, `dumpIntervalMs` 2000.

## Usage

Always go through the playground CLI:

```bash
playground analyze jscissors --sample filestream_sink_bad_json                                   # try the analysis
playground debug jscissors -c connect --class io.confluent.connect.jdbc.sink.JdbcDbWriter --duration 60s
playground debug jscissors --class 'io.confluent.connect.jdbc.sink.*' --action start             # ... then --action stop
playground debug jscissors --config-file rules.props --action start
playground debug jscissors -c broker --class kafka.server.KafkaApis --method handleProduceRequest --restart
```

See the [deep dive](https://kafka-docker-playground.io/#/deep-dive-jvm-diagnostics) for the gotchas.

## Developing the agent

```bash
# build and test it on any JVM, outside the playground
docker run --rm -v "$PWD/tools/jscissors/agent:/src:ro" maven:3.9.11-eclipse-temurin-17 sh -c 'cp -r /src /b && cd /b && mvn -q package && cat target/jscissors.jar' > /tmp/jscissors.jar
java -javaagent:/tmp/jscissors.jar=config=rules.props,out=/tmp/out -cp app.jar Main
java -cp /tmp/jscissors.jar jscissors.Attach --pid <pid> --agent-args config=rules.props,out=/tmp/out
python3 -I tools/jscissors/jscissors_report.py --dir /tmp/out --html-out /tmp/report.html
```

A JVM keeps the classes of the first jar attached to it: after a change of the agent, restart the container before
attaching the new jar. `playground debug jscissors` rebuilds the jar on its own when the sources change.
