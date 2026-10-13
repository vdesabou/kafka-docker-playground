# heap-analyzer

Docker image behind `playground debug heap-analyze`: [Eclipse Memory Analyzer (MAT)](https://eclipse.dev/mat/)
run headless on a heap dump, plus a text digest of the result.

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

The full MAT output is in `mat.log`. When MAT can't parse a dump (truncated file, out of memory), the command
exits non-zero with MAT's error and a hint. It never reports a healthy heap on a failed parse.

## Files

- `Dockerfile`: `eclipse-temurin:21-jre` plus a pinned MAT release (version, build and SHA-512 per architecture,
  `x86_64` and `aarch64`). The CLI tags the image with a checksum of the Dockerfile, so bumping MAT rebuilds it.
- `analyze-heap.sh`: entrypoint. It runs MAT through the Equinox launcher jar (no GTK needed) in a writable
  work directory, because MAT writes its indexes next to the dump. Mounted at run time.
- `digest.py`: text digest. Mounted at run time.

## Memory

MAT needs roughly as much Java heap as the used heap of the dump (1 to 1.5x the `.hprof` size). By default it
gets 80% of the container memory (`-XX:MaxRAMPercentage=80`). Raise the Docker memory, or pass
`--max-memory 12g`, for big dumps.

## Usage

Always go through the playground CLI:

```bash
playground debug heap-dump --container connect          # prints the heap-analyze command to run next
playground debug heap-analyze --file heap-dump-connect-2026-04-08.hprof
playground debug heap-analyze -f heap-dump-connect-1.hprof --compare heap-dump-connect-2.hprof
playground debug heap-analyze -f big-heap-dump.hprof --max-memory 12g --report-type leaks
```

For paths to GC roots, OQL or interactive browsing, open the `.hprof` in the MAT GUI.

## Updating MAT

Take the version, build date and SHA-512 sums of the `linux.gtk.x86_64` / `linux.gtk.aarch64` zips from
<https://eclipse.dev/mat/download/>, update the `ARG`s of the `Dockerfile` and run a dump through
`playground debug heap-analyze`.
