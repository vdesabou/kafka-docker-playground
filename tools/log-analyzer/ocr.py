#!/usr/bin/env python3
"""The text of a screenshot of a log, for playground analyze logs --ocr: one line of the picture per line.

Engines, the first available (PLAYGROUND_OCR_ENGINE=vision|tesseract|docker forces one):
  - vision: the Vision framework of macOS (offline, built in), through ocr/ocr.swift compiled once with swiftc into
    ~/.cache/playground (about a minute the first time, then about 1 s per picture)
  - tesseract: a tesseract on the PATH (brew install tesseract, apt install tesseract-ocr)
  - docker: tesseract in a container, the image built on first use from ocr/Dockerfile

OCR misreads some characters (orq.apache, JsonConverterConfiq, a digit): only the usual confusions inside the names of
Java packages and classes are fixed (fix_line), never digits or values, which a regex would invent. The lines are
approximate, and analyze logs says so.

usage: ocr.py <image> <output>
prints "<engine>\\t<lines>" and exits 0 (output written), 2: no text in the picture, 1: no engine or the picture cannot
be read (the reason on stderr)
"""
import hashlib
import os
import platform
import re
import shutil
import subprocess
import sys
from typing import List, Optional, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
SWIFT_SOURCE = os.path.join(HERE, "ocr", "ocr.swift")
DOCKERFILE_DIR = os.path.join(HERE, "ocr")
CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "playground")
TIMEOUT_S = 120

# the usual misreadings inside a dotted Java name (org.apache.kafka.connect.json.JsonConverterConfig): g read q, j read i
PACKAGE_FIXES = [
    (re.compile(r"\borq\.(?=[a-z])"), "org."),
    (re.compile(r"(?<=[a-z])\.ison\.(?=[a-zA-Z])"), ".json."),
    (re.compile(r"\blo\.confluent\."), "io.confluent."),
    (re.compile(r"(?<=[a-z])Confiq\b"), "Config"),
    (re.compile(r"(?<=[A-Z][a-z])Confiq(?=[A-Z:)])"), "Config"),
]
# a dotted Java name: the fixes apply inside it only
JAVA_NAME = re.compile(r"\b[a-zA-Z_$][\w$]*(?:\.[a-zA-Z_$][\w$]*){2,}\b")


# the spaces tesseract adds inside a Java name and the (Class.java:line) of a frame or a logger: "org.apache. kafka.
# connect", "deliverMessages (WorkerSinkTask. java: 632)", "(…AppInfoParser: 131)". A space after a dot followed by a
# lower case name and another dot, colon or parenthesis is not prose (a sentence goes on with a capital)
SPACING_FIXES = [
    (re.compile(r"(?<=[a-z0-9_$])\. (?=[a-z][\w$]*[.:(])"), "."),
    (re.compile(r"(?<=[a-z])\. (?=java\b)"), "."),
    (re.compile(r"(?<=[\w$]) \((?=[A-Z][\w$]*\.java:)"), "("),
    (re.compile(r"(?<=[\w$]): (?=\d+\))"), ":"),
]


def fix_line(line: str) -> str:
    for rx, repl in SPACING_FIXES:
        line = rx.sub(repl, line)
    def fix(m: "re.Match") -> str:
        name = m.group(0)
        for rx, repl in PACKAGE_FIXES:
            name = rx.sub(repl, name)
        return name
    return JAVA_NAME.sub(fix, line)


# the start of a log4j record: its timestamp, with the brackets OCR reads as | / l / I / 1 ("|2026-11-09 10:00:05,4561 ERROR")
RECORD_START = re.compile(r"^[\[|lI(]?(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:[,.]\d{3})?)(?:[\]|l1I)])?\s")
# a stack frame, its tab lost: "at org.apache.kafka.connect.runtime.WorkerSinkTask.deliverMessages(WorkerSinkTask.java:632)"
FRAME = re.compile(r"^\s*at [\w$.<>]+\(")
EXCEPTION_START = re.compile(r"^(?:Caused by:|\s*\.\.\. \d+ more|[a-z][\w$]*(?:\.[\w$]+)+(?:Exception|Error|Throwable)\b)")
# WorkerSinkTask{id=jdbc-sink-0} read as WorkerSinkTaskiid=jdbc-sink-0; (the context of a connector)
TASK_ID = re.compile(r"\b(Worker(?:Sink|Source)Task)[i{(\[]id=([\w.-]+?)[;})\]]")


def rebuild(lines: List[str]) -> List[str]:
    """the log records of the lines of a screenshot: the brackets of a timestamp, the {} of a task id, the tab of a stack
    frame; a line wrapped by the terminal (it starts neither a record nor an exception, a frame or a Caused by) is
    joined to the line before it"""
    out: List[str] = []
    for line in lines:
        m = RECORD_START.match(line)
        if m:
            line = f"[{m.group(1)}] " + line[m.end():]
        line = TASK_ID.sub(r"\1{id=\2}", line)
        if FRAME.match(line):
            out.append("\t" + line.strip())
        elif m or EXCEPTION_START.match(line) or not out:
            out.append(line)
        else:
            out[-1] = out[-1].rstrip() + " " + line.strip()
    return out


def vision_binary() -> Optional[str]:
    """the Vision program, compiled once per version of ocr.swift (None: not macOS, or no swiftc)"""
    if platform.system() != "Darwin" or not shutil.which("swiftc") or not os.path.isfile(SWIFT_SOURCE):
        return None
    with open(SWIFT_SOURCE, "rb") as fh:
        digest = hashlib.sha256(fh.read()).hexdigest()[:12]
    binary = os.path.join(CACHE_DIR, f"ocr-vision-{digest}")
    if os.access(binary, os.X_OK):
        return binary
    os.makedirs(CACHE_DIR, exist_ok=True)
    print("🏗️  compiling the OCR program of the Vision framework once (about a minute)...", file=sys.stderr)
    tmp = binary + f".{os.getpid()}"
    try:
        subprocess.run(["swiftc", "-O", "-o", tmp, SWIFT_SOURCE], check=True, capture_output=True, timeout=600)
        os.replace(tmp, binary)
    except (subprocess.SubprocessError, OSError) as ex:
        print(f"cannot compile {SWIFT_SOURCE}: {ex}", file=sys.stderr)
        return None
    return binary


def docker_image() -> Optional[str]:
    """the tesseract image, built on first use (None: no docker, or the build failed)"""
    if not shutil.which("docker"):
        return None
    with open(os.path.join(DOCKERFILE_DIR, "Dockerfile"), "rb") as fh:
        image = "playground-ocr:" + hashlib.sha256(fh.read()).hexdigest()[:12]
    if subprocess.run(["docker", "image", "inspect", image], capture_output=True).returncode == 0:
        return image
    print(f"🏗️  building {image} (tesseract, first run only)...", file=sys.stderr)
    try:
        subprocess.run(["docker", "build", "-t", image, DOCKERFILE_DIR], check=True, capture_output=True, timeout=900)
    except (subprocess.SubprocessError, OSError) as ex:
        print(f"cannot build {image}: {ex}", file=sys.stderr)
        return None
    return image


def engines() -> List[str]:
    forced = os.environ.get("PLAYGROUND_OCR_ENGINE", "")
    return [forced] if forced else ["vision", "tesseract", "docker"]


def recognize(image: str) -> Tuple[str, str]:
    """(engine, text) of the picture; raises RuntimeError when no engine can read it"""
    reasons = []
    for engine in engines():
        if engine == "vision":
            binary = vision_binary()
            if not binary:
                reasons.append("vision: macOS with swiftc only (xcode-select --install)")
                continue
            cmd = [binary, image]
        elif engine == "tesseract":
            if not shutil.which("tesseract"):
                reasons.append("tesseract: not installed (brew install tesseract, apt install tesseract-ocr)")
                continue
            # --psm 6: a single block of text, the layout of a terminal or a log viewer
            cmd = ["tesseract", image, "stdout", "--psm", "6", "-l", "eng"]
        elif engine == "docker":
            docker = docker_image()
            if not docker:
                reasons.append("docker: not available, or the tesseract image could not be built")
                continue
            folder, name = os.path.split(os.path.abspath(image))
            cmd = ["docker", "run", "--rm", "--network", "none", "-v", f"{folder}:/in:ro", docker, f"/in/{name}",
                   "stdout", "--psm", "6", "-l", "eng"]
        else:
            reasons.append(f"{engine}: unknown engine (vision, tesseract, docker)")
            continue
        try:
            done = subprocess.run(cmd, capture_output=True, timeout=TIMEOUT_S)
        except (subprocess.SubprocessError, OSError) as ex:
            reasons.append(f"{engine}: {ex}")
            continue
        if done.returncode == 0:
            return engine, done.stdout.decode("utf-8", "replace")
        reasons.append(f"{engine}: {done.stderr.decode('utf-8', 'replace').strip().splitlines()[-1:] or done.returncode}")
    raise RuntimeError("; ".join(reasons))


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 1
    try:
        engine, text = recognize(sys.argv[1])
    except RuntimeError as ex:
        print(f"no OCR engine could read it: {ex}", file=sys.stderr)
        return 1
    lines = [fix_line(l.rstrip()) for l in text.replace("\r", "").split("\n")]
    lines = rebuild([l for l in lines if l.strip()])
    if not lines:
        print(engine)
        return 2
    with open(sys.argv[2], "w", encoding="utf-8") as out:
        out.write("\n".join(lines) + "\n")
    print(f"{engine}\t{len(lines)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
