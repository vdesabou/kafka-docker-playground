# heap-analyzer

Docker image behind `playground analyze heap-dump`: [Eclipse Memory Analyzer (MAT)](https://eclipse.dev/mat/)
run headless on a heap dump, plus a text digest and an HTML report of the result.

## What it does

1. MAT parses the dump (`.hprof`, or `.hprof.gz` as written by `jcmd <pid> GC.heap_dump -gz`), builds its
   indexes and generates the HTML report(s) selected by `--report-type`:

   | `--report-type` | MAT report id | Output folder |
   | --- | --- | --- |
   | `leaks` | `org.eclipse.mat.api:suspects` | `Leak_Suspects/` |
   | `overview` | `org.eclipse.mat.api:overview` | `System_Overview/` |
   | `top-components` | `org.eclipse.mat.api:top_components` | `Top_Components/` |
   | `all` (default) | the three above | |

2. Two MAT queries in text format: `heap_dump_overview` and `dominator_tree -groupBy BY_CLASS` (retained
   sizes), saved in `queries/`.
3. With `--compare <second dump>`: the `histogram` query on both dumps, diffed per class.
4. `digest.py` prints the digest and saves it to `summary.txt`: heap overview, MAT leak suspects (accumulation
   point and who holds it), top retained heap by class and, with `--compare`, the classes that grew.
5. Back on the host, `heap_report.py` reads the same files (with the parsers of `digest.py`) and writes
   `<dump>-heap-report.html`, or prints JSON with `--json`. The report has:
   - a verdict, and the leak suspects in plain words
   - Kafka-aware hints: producer buffers, consumer fetch buffers, records held by the tasks, storage sink writers,
     CDC queues, schema caches, plugin class loaders
   - retained heap and growth charts, and links to the MAT reports

The full MAT output is in `mat.log`. When MAT can't parse a dump (truncated file, out of memory), the command
exits non-zero with MAT's error and a hint. It never reports a healthy heap on a failed parse.

## Files

- `Dockerfile`: `eclipse-temurin:21-jre` plus a pinned MAT release (version, build and SHA-512 per architecture,
  `x86_64` and `aarch64`). The CLI tags the image with a checksum of the Dockerfile, so bumping MAT rebuilds it.
- `analyze-heap.sh`: entrypoint. It runs MAT through the Equinox launcher jar (no GTK needed) in a writable
  work directory, because MAT writes its indexes next to the dump. Mounted at run time.
- `digest.py`: text digest. Mounted at run time.
- `heap_report.py`: HTML report and JSON, run on the host with `python3` (look shared with the other reports in
  `tools/report-common/report_html.py`).

## Memory

MAT needs roughly as much Java heap as the used heap of the dump (1 to 1.5x the `.hprof` size). By default it
gets 80% of the container memory (`-XX:MaxRAMPercentage=80`). Raise the Docker memory, or pass
`--max-memory 12g`, for big dumps.

## Usage

Always go through the playground CLI:

```bash
playground analyze heap-dump --sample leak               # try it on the samples below
playground analyze heap-dump --sample leak_growth
playground debug heap-dump --container connect          # prints the analyze command to run next
playground analyze heap-dump --file heap-dump-connect-2026-04-08.hprof
playground analyze heap-dump -f heap-dump-connect-1.hprof --compare heap-dump-connect-2.hprof
playground analyze heap-dump -f big-heap-dump.hprof --max-memory 12g --report-type leaks
```

For paths to GC roots, OQL or interactive browsing, open the `.hprof` in the MAT GUI.

## Samples

Two `jcmd <pid> GC.heap_dump -gz=9` dumps of `samples/SessionCacheLeak.java` (a session cache that is never
evicted), taken a few seconds apart on JDK 21 with `-Xmx64m -XX:+UseSerialGC`, kept small on purpose (2 and 3 MB):

| `--sample` | Files | Expected result |
| --- | --- | --- |
| `leak` | `session-cache-leak-2.hprof.gz` | MAT leak suspect: the class `SessionCacheLeak` holds ~80 % of the heap through one `HashMap` |
| `leak_growth` | `session-cache-leak-1.hprof.gz`, compared with `session-cache-leak-2.hprof.gz` | the same suspect, and `SessionCacheLeak$Session` / `byte[]` grow between the two dumps |

The repository ignores `*.gz`: `.gitignore` keeps `samples/*.hprof.gz`.

## Updating MAT

Take the version, build date and SHA-512 sums of the `linux.gtk.x86_64` / `linux.gtk.aarch64` zips from
<https://eclipse.dev/mat/download/>, update the `ARG`s of the `Dockerfile` and run a dump through
`playground analyze heap-dump`.
